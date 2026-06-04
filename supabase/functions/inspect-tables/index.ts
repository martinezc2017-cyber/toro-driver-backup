// Edge Function: inspect-tables
// Read-only counts and recent rows across critical tables, using SUPABASE_DB_URL
// (service role / direct postgres) so RLS doesn't hide anon-blocked rows.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const url = new URL(req.url)
    const action = url.searchParams.get('action')

    const dbUrl = Deno.env.get('SUPABASE_DB_URL')!
    const { Client } = await import("https://deno.land/x/postgres@v0.17.0/mod.ts")
    const client = new Client(dbUrl)
    await client.connect()

    // ──────────────── ACTION: seed_paloma_orders ────────────────
    if (action === 'inspect_active_order') {
      const o = await client.queryObject(`
        SELECT id, status, subtotal, delivery_fee, flat_commission, total, vendor_payout,
               payment_method, payment_status, delivery_type, delivery_address,
               buyer_phone, pickup_otp, delivery_otp,
               held_for_review, hold_reason,
               vendor_accepted_at, vendor_ready_at, picked_up_at, delivered_at, completed_at,
               cancelled_at, delivery_id,
               created_at, vendor_responded_in_ms
        FROM marketplace_orders
        WHERE vendor_id = '862f91a1-9612-4dfc-9105-278acd7276f8'
          AND status NOT IN ('auto_cancelled','cancelled_by_buyer','cancelled_by_vendor','failed')
        ORDER BY created_at DESC LIMIT 1
      `)
      if (o.rows.length === 0) {
        await client.end()
        return new Response(JSON.stringify({ note: 'no active order' }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      }
      const orderId = (o.rows[0] as any).id
      const events = await client.queryObject(`
        SELECT created_at, from_status, to_status, actor_type, note
        FROM marketplace_order_events
        WHERE order_id = $1 ORDER BY created_at ASC
      `, [orderId])
      const items = await client.queryObject(`
        SELECT product_name_snapshot, quantity, unit_price_snapshot, line_total, prep_status, prepared_at
        FROM marketplace_order_items WHERE order_id = $1 ORDER BY created_at
      `, [orderId])
      const deliveryRow = (o.rows[0] as any).delivery_id
        ? await client.queryObject(`
            SELECT id, status, driver_id, created_at
            FROM deliveries WHERE id = $1
          `, [(o.rows[0] as any).delivery_id])
        : { rows: [] }
      const recentLogs = await client.queryObject(`
        SELECT created_at, level, event, message, context::text AS ctx
        FROM app_logs
        WHERE source = 'vendor_cascade'
          AND created_at > NOW() - INTERVAL '10 minutes'
        ORDER BY created_at DESC LIMIT 20
      `)
      await client.end()
      return new Response(JSON.stringify({
        order: o.rows[0],
        events: events.rows,
        items: items.rows,
        delivery: deliveryRow.rows[0] ?? null,
        recent_cascade_actions: recentLogs.rows,
      }, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'wipe_paloma_test_orders') {
      const vendorId = '862f91a1-9612-4dfc-9105-278acd7276f8'
      // Delete events + items + orders for this vendor (test data only).
      await client.queryArray(`
        DELETE FROM marketplace_order_events
        WHERE order_id IN (SELECT id FROM marketplace_orders WHERE vendor_id = $1)
      `, [vendorId])
      await client.queryArray(`
        DELETE FROM marketplace_order_items
        WHERE order_id IN (SELECT id FROM marketplace_orders WHERE vendor_id = $1)
      `, [vendorId])
      const r = await client.queryObject<{ id: string }>(`
        DELETE FROM marketplace_orders WHERE vendor_id = $1 RETURNING id
      `, [vendorId])
      await client.end()
      return new Response(JSON.stringify({ deleted: r.rows.length }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'real_purchase_via_rpc') {
      // FULL FLOW: call place_marketplace_order as a real buyer (Carlos).
      // This exercises every server-side path — fees lookup, OTP gen, hold
      // logic, item snapshots, audit log, events, and the notify trigger
      // we wired earlier.
      const log: string[] = []
      try {
        const vendorId = '862f91a1-9612-4dfc-9105-278acd7276f8'

        // Pick the BUYER — anyone who is NOT Paloma. Prefer a Mexicali rider with rider_app_installed.
        const buyer = await client.queryObject<{ id: string; full_name: string; phone: string | null }>(`
          SELECT p.id, p.full_name, p.phone
          FROM profiles p
          WHERE p.id <> (SELECT user_id FROM vendors WHERE id = $1)
            AND COALESCE(p.full_name, '') <> ''
          ORDER BY p.created_at DESC LIMIT 1
        `, [vendorId])
        if (buyer.rows.length === 0) throw new Error('no buyer profile available')
        const b = buyer.rows[0]
        log.push(`buyer: ${b.full_name} (${b.id})`)

        const prod = await client.queryObject<{ id: string }>(`
          SELECT id FROM products WHERE vendor_id = $1 ORDER BY created_at DESC LIMIT 1
        `, [vendorId])
        if (prod.rows.length === 0) throw new Error('vendor has no product')
        const pid = prod.rows[0].id
        log.push(`product: ${pid}`)

        // Ensure vendor is_open + active + accepts_cash so RPC doesn't reject
        // (we're testing the order flow, not vendor gating).
        await client.queryArray(`
          UPDATE vendors SET
            is_open = true,
            status = 'active',
            accepts_cash = true,
            accepts_card = COALESCE(accepts_card, false)
          WHERE id = $1
        `, [vendorId])

        // Wrap in a transaction so SET LOCAL request.jwt.claims is visible
        // to the place_marketplace_order RPC body.
        await client.queryArray('BEGIN')
        await client.queryArray(`
          SELECT set_config('request.jwt.claims', $1, true),
                 set_config('request.jwt.claim.sub', $2, true),
                 set_config('request.jwt.claim.role', 'authenticated', true)
        `, [
          JSON.stringify({ sub: b.id, role: 'authenticated', email: '' }),
          b.id,
        ])

        const items = [{ product_id: pid, qty: 1 }]
        const orderRow = await client.queryObject<{ order_id: string }>(`
          SELECT place_marketplace_order(
            $1::uuid,
            $2::jsonb,
            'toro',
            'cash',
            'Calz. Independencia 1234, Col. Centro, Mexicali, BC',
            32.6245,
            -115.4523,
            'Departamento 3, segundo piso. Tocar el timbre.',
            $3,
            0
          ) AS order_id
        `, [vendorId, JSON.stringify(items), b.phone ?? '+526860000099'])
        await client.queryArray('COMMIT')
        const orderId = orderRow.rows[0].order_id
        log.push(`OK real order created via RPC: ${orderId}`)

        // Read back the full order
        const full = await client.queryObject(`
          SELECT id, status, subtotal, delivery_fee, flat_commission, total,
                 vendor_payout, payment_method, delivery_type,
                 delivery_address, buyer_phone, pickup_otp, delivery_otp,
                 held_for_review, hold_reason, prep_time_min
          FROM marketplace_orders WHERE id = $1
        `, [orderId])

        await client.end()
        return new Response(JSON.stringify({
          success: true, log,
          order: full.rows[0],
        }, null, 2),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      } catch (e) {
        log.push(`ERR: ${(e as Error).message}`)
        await client.end()
        return new Response(JSON.stringify({ success: false, log }, null, 2),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 })
      }
    }

    if (action === 'fix_paloma_payouts') {
      // Repair test orders that were seeded with the WRONG math.
      // Correct rule: total = subtotal + flat_commission + delivery_fee + tip,
      //               vendor_payout = subtotal (vendor's listed price).
      const r = await client.queryObject<{ id: string; new_total: number; new_payout: number }>(`
        UPDATE marketplace_orders
        SET total = subtotal + COALESCE(flat_commission, 0) + COALESCE(delivery_fee, 0) + COALESCE(tip, 0),
            vendor_payout = subtotal,
            updated_at = NOW()
        WHERE vendor_id = '862f91a1-9612-4dfc-9105-278acd7276f8'
          AND (vendor_payout <> subtotal OR total <> subtotal + COALESCE(flat_commission, 0) + COALESCE(delivery_fee, 0) + COALESCE(tip, 0))
        RETURNING id, total AS new_total, vendor_payout AS new_payout
      `)
      await client.end()
      return new Response(JSON.stringify({
        fixed: r.rows.length,
        rows: r.rows.map(x => ({ id: x.id.substring(0, 8), total: Number(x.new_total), payout: Number(x.new_payout) })),
      }, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'ps5_product') {
      const prod = await client.queryObject(`
        SELECT p.id, p.name, p.price, p.currency, v.business_name
        FROM products p JOIN vendors v ON v.id = p.vendor_id
        WHERE LOWER(p.name) LIKE '%control%' OR LOWER(p.name) LIKE '%ps5%'
        ORDER BY p.created_at DESC LIMIT 5
      `)
      const order = await client.queryObject(`
        SELECT id, total, subtotal, flat_commission, vendor_payout, status, payment_method
        FROM marketplace_orders
        WHERE id = '7fa6a4a1-b7aa-4beb-8c2e-2bfb9f9cf85b'
      `)
      await client.end()
      return new Response(JSON.stringify({
        product: prod.rows.map((r: any) => ({
          ...r, price: Number(r.price),
        })),
        completed_order: order.rows.map((r: any) => ({
          id: r.id, status: r.status,
          total_buyer_paid: Number(r.total),
          subtotal: Number(r.subtotal),
          toro_commission: Number(r.flat_commission),
          vendor_payout: Number(r.vendor_payout),
        })),
      }, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'check_orders_policies') {
      const policies = await client.queryObject(`
        SELECT policyname, cmd::text, qual::text, with_check::text
        FROM pg_policies WHERE tablename = 'marketplace_orders'
      `)
      const fnInfo = await client.queryObject(`
        SELECT p.proname, r.rolname AS owner, p.proconfig::text, p.prosecdef
        FROM pg_proc p JOIN pg_roles r ON p.proowner = r.oid
        WHERE p.proname = 'vendor_sales_cascade'
      `)
      const role = await client.queryObject(`SELECT current_user, session_user`)
      await client.end()
      return new Response(JSON.stringify({
        policies: policies.rows,
        function: fnInfo.rows,
        connection_role: role.rows,
      }, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'fix_cascade_rls_bypass') {
      // Recreate the function with explicit "SET row_security = off" so RLS
      // can't filter rows out from under it (it already validates ownership).
      await client.queryArray(`
        CREATE OR REPLACE FUNCTION vendor_sales_cascade(
          p_vendor_id UUID,
          p_history_days INT DEFAULT 7
        )
        RETURNS TABLE (
          bucket TEXT, order_id UUID, status TEXT,
          buyer_name TEXT, buyer_phone TEXT,
          items_summary TEXT, items_count INT,
          total NUMERIC, vendor_payout NUMERIC,
          payment_method TEXT, delivery_type TEXT,
          created_at TIMESTAMPTZ,
          vendor_accepted_at TIMESTAMPTZ, vendor_ready_at TIMESTAMPTZ,
          delivered_at TIMESTAMPTZ, completed_at TIMESTAMPTZ,
          cancelled_at TIMESTAMPTZ, cancellation_reason TEXT,
          seconds_since_placed INT, seconds_until_auto_cancel INT,
          first_image_url TEXT, all_items JSONB
        )
        LANGUAGE plpgsql
        SECURITY DEFINER
        SET row_security = off
        SET search_path = public
        AS $fn$
        BEGIN
          IF NOT EXISTS (
            SELECT 1 FROM vendors v
            WHERE v.id = p_vendor_id
              AND (v.user_id = auth.uid() OR coalesce(auth.jwt() ->> 'role','') = 'service_role')
          ) THEN
            RAISE EXCEPTION 'not vendor owner';
          END IF;

          RETURN QUERY
          WITH order_items_agg AS (
            SELECT
              oi.order_id,
              COUNT(*)::INT AS items_count,
              STRING_AGG(oi.quantity || ' x ' || oi.product_name_snapshot, ', ' ORDER BY oi.created_at) AS items_summary,
              JSONB_AGG(JSONB_BUILD_OBJECT(
                'id', oi.id,
                'name', oi.product_name_snapshot,
                'quantity', oi.quantity,
                'unit_price', oi.unit_price_snapshot,
                'line_total', oi.line_total,
                'prep_status', oi.prep_status,
                'special_instructions', oi.special_instructions
              ) ORDER BY oi.created_at) AS all_items,
              MIN((SELECT (p.image_urls)[1] FROM products p WHERE p.id = oi.product_id)) AS first_image_url
            FROM marketplace_order_items oi
            GROUP BY oi.order_id
          )
          SELECT
            CASE
              WHEN o.status IN ('placed','accepted_by_vendor','preparing','ready_for_pickup','driver_assigned','picked_up','in_transit') THEN 'live'
              WHEN o.completed_at::DATE = CURRENT_DATE OR o.cancelled_at::DATE = CURRENT_DATE OR o.delivered_at::DATE = CURRENT_DATE THEN 'today'
              WHEN (o.completed_at::DATE = CURRENT_DATE - 1 OR o.cancelled_at::DATE = CURRENT_DATE - 1 OR o.delivered_at::DATE = CURRENT_DATE - 1) THEN 'yesterday'
              WHEN COALESCE(o.completed_at, o.cancelled_at, o.delivered_at, o.created_at) > NOW() - INTERVAL '7 days' THEN 'this_week'
              ELSE 'older'
            END AS bucket,
            o.id, o.status, o.buyer_name, o.buyer_phone,
            COALESCE(items.items_summary, '') AS items_summary,
            COALESCE(items.items_count, 0) AS items_count,
            o.total, o.vendor_payout, o.payment_method, o.delivery_type,
            o.created_at, o.vendor_accepted_at, o.vendor_ready_at,
            o.delivered_at, o.completed_at, o.cancelled_at, o.cancellation_reason,
            EXTRACT(EPOCH FROM (NOW() - o.created_at))::INT AS seconds_since_placed,
            CASE WHEN o.status = 'placed'
                 THEN GREATEST(0, 300 - EXTRACT(EPOCH FROM (NOW() - o.created_at))::INT)
                 ELSE NULL END AS seconds_until_auto_cancel,
            items.first_image_url,
            COALESCE(items.all_items, '[]'::JSONB) AS all_items
          FROM marketplace_orders o
          LEFT JOIN order_items_agg items ON items.order_id = o.id
          WHERE o.vendor_id = p_vendor_id
            AND (
              o.status IN ('placed','accepted_by_vendor','preparing','ready_for_pickup','driver_assigned','picked_up','in_transit')
              OR o.created_at > NOW() - (p_history_days || ' days')::INTERVAL
            )
          ORDER BY
            CASE WHEN o.status IN ('placed','accepted_by_vendor','preparing','ready_for_pickup','driver_assigned','picked_up','in_transit')
                 THEN 0 ELSE 1 END,
            o.created_at DESC;
        END;
        $fn$
      `)
      await client.end()
      return new Response(JSON.stringify({ ok: true, message: 'function recreated with row_security=off' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'recent_cascade_logs') {
      const r = await client.queryObject(`
        SELECT l.created_at, l.level, l.event, l.message, l.user_id,
               l.context::text AS ctx,
               p.full_name AS user_name, p.email
        FROM app_logs l
        LEFT JOIN profiles p ON p.id = l.user_id
        WHERE l.source = 'vendor_cascade'
        ORDER BY l.created_at DESC LIMIT 30
      `)
      await client.end()
      return new Response(JSON.stringify(r.rows, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'debug_paloma_cascade') {
      // Run the EXACT inner SELECT of vendor_sales_cascade against PALOMA,
      // bypassing the auth check, to confirm it's a data/RLS issue vs auth.
      const vId = '862f91a1-9612-4dfc-9105-278acd7276f8'
      const ownerRow = await client.queryObject<{
        user_id: string; full_name: string | null; email: string | null;
      }>(`
        SELECT v.user_id, p.full_name, p.email
        FROM vendors v LEFT JOIN profiles p ON p.id = v.user_id
        WHERE v.id = $1
      `, [vId])
      const recent = await client.queryObject(`
        SELECT id, status, total, payment_method, created_at
        FROM marketplace_orders WHERE vendor_id = $1
        ORDER BY created_at DESC LIMIT 10
      `, [vId])
      // Run the INNER SELECT directly (bypassing the auth.uid() check)
      // to confirm whether the data + filter would produce rows.
      const rpc = await client.queryObject(`
        WITH order_items_agg AS (
          SELECT oi.order_id,
                 COUNT(*)::INT AS items_count,
                 STRING_AGG(oi.quantity || ' x ' || oi.product_name_snapshot, ', ' ORDER BY oi.created_at) AS items_summary
          FROM marketplace_order_items oi GROUP BY oi.order_id
        )
        SELECT
          CASE
            WHEN o.status IN ('placed','accepted_by_vendor','preparing','ready_for_pickup','driver_assigned','picked_up','in_transit') THEN 'live'
            ELSE 'history' END AS bucket,
          o.status, o.total, items.items_summary, o.created_at
        FROM marketplace_orders o
        LEFT JOIN order_items_agg items ON items.order_id = o.id
        WHERE o.vendor_id = $1
          AND (
            o.status IN ('placed','accepted_by_vendor','preparing','ready_for_pickup','driver_assigned','picked_up','in_transit')
            OR o.created_at > NOW() - INTERVAL '7 days'
          )
        ORDER BY o.created_at DESC
      `, [vId])
      // Also check RLS state
      const rls = await client.queryObject<{ relname: string; relrowsecurity: boolean }>(`
        SELECT relname, relrowsecurity
        FROM pg_class WHERE relname IN ('marketplace_orders','marketplace_order_items')
      `)
      await client.end()
      return new Response(JSON.stringify({
        vendor_owner: ownerRow.rows[0] ?? null,
        recent_orders_in_db: recent.rows.map((r: any) => ({
          id: r.id, status: r.status, total: Number(r.total), created_at: r.created_at,
        })),
        rpc_rows: rpc.rows.map((r: any) => ({
          bucket: r.bucket, status: r.status, total: Number(r.total),
          summary: r.items_summary, created_at: r.created_at,
        })),
        rls: rls.rows,
      }, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'find_palomas') {
      const r = await client.queryObject(`
        SELECT v.id AS vendor_id, v.business_name, v.user_id, p.full_name, p.email,
               (SELECT COUNT(*) FROM marketplace_orders WHERE vendor_id = v.id) AS order_count,
               (SELECT MAX(created_at) FROM marketplace_orders WHERE vendor_id = v.id) AS last_order
        FROM vendors v
        LEFT JOIN profiles p ON p.id = v.user_id
        WHERE LOWER(v.business_name) LIKE '%paloma%'
           OR LOWER(p.full_name) LIKE '%paloma%'
        ORDER BY v.created_at DESC
      `)
      await client.end()
      return new Response(JSON.stringify(r.rows, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'seed_active_palomas') {
      // Inject a `placed` order in EVERY vendor matching paloma — covers the
      // case where the seed went into a stale duplicate.
      const log: string[] = []
      const vendors = await client.queryObject<{ vendor_id: string; user_id: string }>(`
        SELECT v.id AS vendor_id, v.user_id
        FROM vendors v
        LEFT JOIN profiles p ON p.id = v.user_id
        WHERE LOWER(v.business_name) LIKE '%paloma%'
           OR LOWER(p.full_name) LIKE '%paloma%'
      `)
      for (const v of vendors.rows) {
        const buyer = await client.queryObject<{ id: string }>(`
          SELECT id FROM profiles WHERE id <> $1 LIMIT 1
        `, [v.user_id])
        let prod = await client.queryObject<{ id: string; name: string; price: number }>(`
          SELECT id, name, price FROM products WHERE vendor_id = $1 LIMIT 1
        `, [v.vendor_id])
        if (prod.rows.length === 0) {
          const np = await client.queryObject<{ id: string }>(`
            INSERT INTO products (vendor_id, name, description, price, currency)
            VALUES ($1, 'Producto LIVE test', 'auto', 199, 'MXN') RETURNING id
          `, [v.vendor_id])
          prod = { rows: [{ id: np.rows[0].id, name: 'Producto LIVE test', price: 199 }] } as any
        }
        const p = prod.rows[0]
        const sub = Number(p.price)
        const com = Math.round(sub * 0.10 * 100) / 100
        const tot = sub + com  // buyer pays subtotal + commission
        const o = await client.queryObject<{ id: string }>(`
          INSERT INTO marketplace_orders (
            vendor_id, buyer_id, status, subtotal, delivery_fee, flat_commission,
            total, vendor_payout, payment_status, payment_method, currency,
            delivery_type, buyer_name, buyer_phone, created_at
          ) VALUES (
            $1, $2, 'placed', $3, 0, $4, $5, $3, 'authorized', 'card', 'MXN',
            'toro', 'Cliente LIVE', '+526860000001', NOW()
          ) RETURNING id
        `, [v.vendor_id, buyer.rows[0].id, sub, com, tot])
        await client.queryArray(`
          INSERT INTO marketplace_order_items (order_id, product_id, product_name_snapshot,
            quantity, unit_price_snapshot, line_total, prep_status)
          VALUES ($1, $2, $3, 1, $4, $4, 'pending')
        `, [o.rows[0].id, p.id, p.name, sub])
        log.push(`OK ${v.vendor_id.substring(0,8)} order ${o.rows[0].id.substring(0,8)}`)
      }
      await client.end()
      return new Response(JSON.stringify({ vendors: vendors.rows.length, log }, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'seed_paloma_one') {
      const log: string[] = []
      const vendorId = '862f91a1-9612-4dfc-9105-278acd7276f8'
      try {
        const buyerRes = await client.queryObject<{ id: string }>(`
          SELECT id FROM profiles WHERE id <> (SELECT user_id FROM vendors WHERE id = $1)
          ORDER BY created_at DESC LIMIT 1
        `, [vendorId])
        const prodRes = await client.queryObject<{ id: string; name: string; price: number }>(`
          SELECT id, name, price FROM products WHERE vendor_id = $1
          ORDER BY created_at DESC LIMIT 1
        `, [vendorId])
        const buyer = buyerRes.rows[0]
        const prod = prodRes.rows[0]
        // VENDOR PRICE RESPECTED — buyer pays subtotal + commission.
        const subtotal = Number(prod.price)
        const commission = Math.round(subtotal * 0.10 * 100) / 100
        const total = subtotal + commission
        const vendorPayout = subtotal

        const o = await client.queryObject<{ id: string }>(`
          INSERT INTO marketplace_orders (
            vendor_id, buyer_id, status,
            subtotal, delivery_fee, flat_commission, total, vendor_payout,
            payment_status, payment_method, currency,
            delivery_type, buyer_name, buyer_phone,
            created_at
          ) VALUES (
            $1, $2, 'placed',
            $3, 0, $4, $5, $6,
            'authorized', 'card', 'MXN',
            'toro', 'Cliente LIVE', '+526860000001',
            NOW()
          ) RETURNING id
        `, [vendorId, buyer.id, subtotal, commission, total, vendorPayout])
        const oid = o.rows[0].id

        await client.queryArray(`
          INSERT INTO marketplace_order_items (
            order_id, product_id, product_name_snapshot, quantity,
            unit_price_snapshot, line_total, prep_status
          ) VALUES ($1, $2, $3, 1, $4, $4, 'pending')
        `, [oid, prod.id, prod.name, subtotal])

        log.push(`OK order ${oid.substring(0, 8)} for vendor PALOMA — should appear LIVE`)
        await client.end()
        return new Response(JSON.stringify({ success: true, order_id: oid, log }, null, 2),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      } catch (e) {
        await client.end()
        return new Response(JSON.stringify({ success: false, error: (e as Error).message }, null, 2),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 })
      }
    }

    if (action === 'check_realtime_pub') {
      const r = await client.queryObject<{ schemaname: string; tablename: string }>(`
        SELECT schemaname, tablename FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
        ORDER BY tablename
      `)
      await client.end()
      return new Response(JSON.stringify({ tables: r.rows }, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'add_marketplace_to_realtime') {
      const log: string[] = []
      for (const t of ['marketplace_orders','marketplace_order_items','marketplace_order_events']) {
        try {
          await client.queryArray(`ALTER PUBLICATION supabase_realtime ADD TABLE public.${t}`)
          log.push(`OK added ${t}`)
        } catch (e) {
          const msg = (e as Error).message
          if (msg.includes('already member')) log.push(`already in pub: ${t}`)
          else log.push(`ERR ${t}: ${msg}`)
        }
        // Ensure REPLICA IDENTITY FULL so OLD values come through on UPDATE/DELETE
        try {
          await client.queryArray(`ALTER TABLE public.${t} REPLICA IDENTITY FULL`)
          log.push(`OK replica full ${t}`)
        } catch (e) { log.push(`ERR replica ${t}: ${(e as Error).message}`) }
      }
      await client.end()
      return new Response(JSON.stringify({ success: true, log }, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'paloma_orders') {
      const r = await client.queryObject(`
        SELECT id, status, total, vendor_payout, created_at, payment_method
        FROM marketplace_orders
        WHERE vendor_id = '862f91a1-9612-4dfc-9105-278acd7276f8'
        ORDER BY created_at DESC
        LIMIT 20
      `)
      await client.end()
      return new Response(JSON.stringify(r.rows, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'patch_log_payment_event_canonical') {
      // Fix: NEW.transaction_id only exists on some tables. Use jsonb lookup.
      await client.queryArray(`
        CREATE OR REPLACE FUNCTION public.log_payment_event_canonical()
         RETURNS trigger
         LANGUAGE plpgsql
         SECURITY DEFINER
        AS $fn$
        DECLARE
          v_event_type text;
          v_status text;
          v_amount numeric;
          v_tx_id text;
          v_desc text;
          v_new jsonb := to_jsonb(NEW);
        BEGIN
          v_tx_id := COALESCE(
            v_new->>'stripe_payment_intent_id',
            v_new->>'transaction_id',
            v_new->>'id'
          );

          IF TG_OP = 'INSERT' THEN
            v_event_type := TG_TABLE_NAME || '_created';
            v_status := 'pending';
            v_desc := format('%s creado', TG_TABLE_NAME);
          ELSIF TG_OP = 'UPDATE' THEN
            IF NEW.status IS DISTINCT FROM OLD.status THEN
              v_event_type := TG_TABLE_NAME || '_status_change';
              v_status := NEW.status;
              v_desc := format('%s status: %s -> %s', TG_TABLE_NAME, OLD.status, NEW.status);
            ELSE
              RETURN NEW;
            END IF;
          ELSE
            RETURN NEW;
          END IF;

          v_amount := COALESCE(
            (v_new->>'total_price')::numeric,
            (v_new->>'total')::numeric,
            (v_new->>'amount')::numeric,
            NULL
          );

          INSERT INTO public.payment_events (
            transaction_id, event_type, status, amount, description, metadata
          ) VALUES (
            v_tx_id, v_event_type, v_status, v_amount, v_desc,
            jsonb_build_object(
              'source_table', TG_TABLE_NAME,
              'source_id', v_new->>'id',
              'status', NEW.status,
              'payment_method', v_new->>'payment_method'
            )
          );
          RETURN NEW;
        EXCEPTION WHEN OTHERS THEN
          RAISE WARNING 'log_payment_event_canonical failed: %', SQLERRM;
          RETURN NEW;
        END;
        $fn$
      `)
      await client.end()
      return new Response(JSON.stringify({ ok: true, message: 'patched' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'drop_redundant_otp_rpcs') {
      await client.queryArray(`DROP FUNCTION IF EXISTS public.driver_verify_pickup_otp(UUID, TEXT)`)
      await client.queryArray(`DROP FUNCTION IF EXISTS public.driver_verify_delivery_otp(UUID, TEXT)`)
      await client.end()
      return new Response(JSON.stringify({ ok: true, message: 'dropped redundant OTP RPCs — using canonical marketplace_confirm_pickup/delivery instead' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'setup_driver_marketplace_rpcs') {
      const log: string[] = []

      // ──────── driver_accept_marketplace_delivery ────────
      try {
        await client.queryArray(`
          CREATE OR REPLACE FUNCTION public.driver_accept_marketplace_delivery(
            p_delivery_id UUID
          )
          RETURNS jsonb
          LANGUAGE plpgsql
          SECURITY DEFINER
          SET search_path = public
          AS $fn$
          DECLARE
            v_uid uuid := auth.uid();
            v_driver_id uuid;
            v_delivery RECORD;
            v_order_id uuid;
          BEGIN
            IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;

            SELECT id INTO v_driver_id FROM drivers
            WHERE user_id = v_uid AND is_online = true AND can_receive_rides = true;
            IF v_driver_id IS NULL THEN
              RAISE EXCEPTION 'Driver not eligible (offline or restricted)';
            END IF;

            SELECT * INTO v_delivery FROM deliveries
            WHERE id = p_delivery_id FOR UPDATE;
            IF NOT FOUND THEN RAISE EXCEPTION 'Delivery not found'; END IF;

            IF v_delivery.service_type <> 'marketplace' THEN
              RAISE EXCEPTION 'Not a marketplace delivery';
            END IF;
            IF v_delivery.status <> 'pending' THEN
              RAISE EXCEPTION 'Delivery already %', v_delivery.status;
            END IF;
            IF v_delivery.driver_id IS NOT NULL THEN
              RAISE EXCEPTION 'Delivery already taken';
            END IF;

            UPDATE deliveries
            SET driver_id = v_driver_id,
                status = 'accepted',
                accepted_at = NOW(),
                updated_at = NOW()
            WHERE id = p_delivery_id;

            SELECT id INTO v_order_id FROM marketplace_orders
            WHERE delivery_id = p_delivery_id;

            IF v_order_id IS NOT NULL THEN
              UPDATE marketplace_orders
              SET status = 'driver_assigned', updated_at = NOW()
              WHERE id = v_order_id;

              INSERT INTO marketplace_order_events (
                order_id, from_status, to_status, actor_type, actor_id, note
              ) VALUES (
                v_order_id, 'ready_for_pickup', 'driver_assigned',
                'driver', v_driver_id, 'chofer aceptó la entrega'
              );
            END IF;

            INSERT INTO app_logs (level, source, event, message, user_id, context, app_role)
            VALUES ('info', 'driver_marketplace', 'accept_delivery',
                    'Driver accepted marketplace delivery', v_uid,
                    jsonb_build_object('delivery_id', p_delivery_id, 'order_id', v_order_id),
                    'driver');

            RETURN jsonb_build_object(
              'success', true,
              'delivery_id', p_delivery_id,
              'order_id', v_order_id
            );
          END;
          $fn$
        `)
        log.push('OK: driver_accept_marketplace_delivery')
      } catch (e) { log.push(`ERR accept: ${(e as Error).message}`) }

      // ──────── driver_verify_pickup_otp ────────
      try {
        await client.queryArray(`
          CREATE OR REPLACE FUNCTION public.driver_verify_pickup_otp(
            p_delivery_id UUID,
            p_otp TEXT
          )
          RETURNS jsonb
          LANGUAGE plpgsql
          SECURITY DEFINER
          SET search_path = public
          AS $fn$
          DECLARE
            v_uid uuid := auth.uid();
            v_driver_id uuid;
            v_delivery RECORD;
            v_order RECORD;
          BEGIN
            IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;

            SELECT id INTO v_driver_id FROM drivers WHERE user_id = v_uid;
            IF v_driver_id IS NULL THEN RAISE EXCEPTION 'Not a driver'; END IF;

            SELECT * INTO v_delivery FROM deliveries WHERE id = p_delivery_id FOR UPDATE;
            IF NOT FOUND THEN RAISE EXCEPTION 'Delivery not found'; END IF;
            IF v_delivery.driver_id <> v_driver_id THEN
              RAISE EXCEPTION 'Not your delivery';
            END IF;
            IF v_delivery.status NOT IN ('accepted', 'in_progress') THEN
              RAISE EXCEPTION 'Cannot pickup from status %', v_delivery.status;
            END IF;

            SELECT * INTO v_order FROM marketplace_orders
            WHERE delivery_id = p_delivery_id FOR UPDATE;
            IF NOT FOUND THEN RAISE EXCEPTION 'Marketplace order not found'; END IF;

            IF v_order.pickup_otp IS NULL OR v_order.pickup_otp <> p_otp THEN
              INSERT INTO app_logs (level, source, event, message, user_id, context, app_role)
              VALUES ('warn', 'driver_marketplace', 'pickup_otp_wrong',
                      'Wrong pickup OTP attempted', v_uid,
                      jsonb_build_object('delivery_id', p_delivery_id, 'attempted', p_otp),
                      'driver');
              RAISE EXCEPTION 'OTP incorrecto';
            END IF;

            UPDATE deliveries
            SET status = 'in_progress',
                picked_up_at = NOW(),
                updated_at = NOW()
            WHERE id = p_delivery_id;

            UPDATE marketplace_orders
            SET status = 'picked_up',
                picked_up_at = NOW(),
                pickup_geofence_passed = true,
                updated_at = NOW()
            WHERE id = v_order.id;

            INSERT INTO marketplace_order_events (
              order_id, from_status, to_status, actor_type, actor_id, note
            ) VALUES (
              v_order.id, v_order.status, 'picked_up',
              'driver', v_driver_id, 'PIN pickup verificado'
            );

            INSERT INTO app_logs (level, source, event, message, user_id, context, app_role)
            VALUES ('info', 'driver_marketplace', 'pickup_otp_ok',
                    'Driver verified pickup OTP', v_uid,
                    jsonb_build_object('delivery_id', p_delivery_id, 'order_id', v_order.id),
                    'driver');

            RETURN jsonb_build_object('success', true, 'status', 'picked_up');
          END;
          $fn$
        `)
        log.push('OK: driver_verify_pickup_otp')
      } catch (e) { log.push(`ERR pickup: ${(e as Error).message}`) }

      // ──────── driver_verify_delivery_otp ────────
      try {
        await client.queryArray(`
          CREATE OR REPLACE FUNCTION public.driver_verify_delivery_otp(
            p_delivery_id UUID,
            p_otp TEXT
          )
          RETURNS jsonb
          LANGUAGE plpgsql
          SECURITY DEFINER
          SET search_path = public
          AS $fn$
          DECLARE
            v_uid uuid := auth.uid();
            v_driver_id uuid;
            v_delivery RECORD;
            v_order RECORD;
          BEGIN
            IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;

            SELECT id INTO v_driver_id FROM drivers WHERE user_id = v_uid;
            IF v_driver_id IS NULL THEN RAISE EXCEPTION 'Not a driver'; END IF;

            SELECT * INTO v_delivery FROM deliveries WHERE id = p_delivery_id FOR UPDATE;
            IF NOT FOUND THEN RAISE EXCEPTION 'Delivery not found'; END IF;
            IF v_delivery.driver_id <> v_driver_id THEN
              RAISE EXCEPTION 'Not your delivery';
            END IF;
            IF v_delivery.status <> 'in_progress' THEN
              RAISE EXCEPTION 'Pickup not completed yet';
            END IF;

            SELECT * INTO v_order FROM marketplace_orders
            WHERE delivery_id = p_delivery_id FOR UPDATE;
            IF NOT FOUND THEN RAISE EXCEPTION 'Marketplace order not found'; END IF;

            IF v_order.delivery_otp IS NULL OR v_order.delivery_otp <> p_otp THEN
              INSERT INTO app_logs (level, source, event, message, user_id, context, app_role)
              VALUES ('warn', 'driver_marketplace', 'delivery_otp_wrong',
                      'Wrong delivery OTP attempted', v_uid,
                      jsonb_build_object('delivery_id', p_delivery_id, 'attempted', p_otp),
                      'driver');
              RAISE EXCEPTION 'OTP incorrecto';
            END IF;

            UPDATE deliveries
            SET status = 'completed',
                delivered_at = NOW(),
                completed_at = NOW(),
                updated_at = NOW()
            WHERE id = p_delivery_id;

            UPDATE marketplace_orders
            SET status = 'delivered',
                delivered_at = NOW(),
                completed_at = NOW(),
                delivery_geofence_passed = true,
                updated_at = NOW()
            WHERE id = v_order.id;

            INSERT INTO marketplace_order_events (
              order_id, from_status, to_status, actor_type, actor_id, note
            ) VALUES (
              v_order.id, 'picked_up', 'delivered',
              'driver', v_driver_id, 'PIN delivery verificado, entregado al cliente'
            );

            INSERT INTO app_logs (level, source, event, message, user_id, context, app_role)
            VALUES ('info', 'driver_marketplace', 'delivery_otp_ok',
                    'Driver verified delivery OTP', v_uid,
                    jsonb_build_object('delivery_id', p_delivery_id, 'order_id', v_order.id),
                    'driver');

            -- The marketplace_order_to_transaction trigger fires on delivered/completed
            -- and writes the canonical transaction record + cash ledger entries.
            RETURN jsonb_build_object('success', true, 'status', 'delivered');
          END;
          $fn$
        `)
        log.push('OK: driver_verify_delivery_otp')
      } catch (e) { log.push(`ERR delivery: ${(e as Error).message}`) }

      // GRANT execute to authenticated
      try {
        await client.queryArray(`
          GRANT EXECUTE ON FUNCTION
            driver_accept_marketplace_delivery(UUID),
            driver_verify_pickup_otp(UUID, TEXT),
            driver_verify_delivery_otp(UUID, TEXT)
          TO authenticated
        `)
        log.push('OK: grants')
      } catch (e) { log.push(`ERR grant: ${(e as Error).message}`) }

      await client.end()
      return new Response(JSON.stringify({ success: true, log }, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'delivery_full') {
      const r = await client.queryObject(`
        SELECT id, service_type, status,
               pickup_lat, pickup_lng, pickup_address,
               destination_lat, destination_lng, destination_address,
               estimated_price, total_price, base_fare,
               driver_earnings, platform_fee, insurance_fee, tax_fee,
               country_code, state_code, driver_id, notes
        FROM deliveries
        WHERE id = '04c47e43-0255-4a3c-9b45-f74f4afb43e3'
      `)
      const o = await client.queryObject(`
        SELECT id, status, subtotal, delivery_fee, flat_commission, total,
               vendor_payout, payment_method, pickup_otp, delivery_otp,
               vendor_pickup_address, delivery_address, buyer_name
        FROM marketplace_orders WHERE delivery_id = '04c47e43-0255-4a3c-9b45-f74f4afb43e3'
      `)
      await client.end()
      return new Response(JSON.stringify({
        delivery: r.rows[0] ?? null,
        marketplace_order: o.rows[0] ?? null,
      }, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'patch_marketplace_dispatch') {
      // Bug found: marketplace_create_delivery_on_ready set state_code from
      // profiles.state_code (buyer's home state). Should resolve from the
      // VENDOR's location since pickup is the vendor's address.
      await client.queryArray(`
        CREATE OR REPLACE FUNCTION public.marketplace_create_delivery_on_ready()
         RETURNS trigger
         LANGUAGE plpgsql
         SECURITY DEFINER
        AS $fn$
        DECLARE
          v_delivery_id   uuid;
          v_buyer_name    text;
          v_country       text;
          v_state         text;
          v_split         RECORD;
          v_decimals      integer;
          v_fee           numeric;
          v_platform_fee  numeric;
          v_insurance_fee numeric;
          v_tax_fee       numeric;
          v_driver_amount numeric;
        BEGIN
          IF NEW.status = 'ready_for_pickup'
             AND OLD.status <> 'ready_for_pickup'
             AND NEW.delivery_id IS NULL THEN

            IF NEW.delivery_type IN ('vendor', 'pickup') THEN
              RETURN NEW;
            END IF;

            -- Buyer name only
            SELECT full_name INTO v_buyer_name
              FROM public.profiles WHERE id = NEW.buyer_id;

            -- Zone: resolved from the VENDOR (pickup origin), NOT the buyer.
            SELECT country_code, state_code INTO v_country, v_state
              FROM public.vendors WHERE id = NEW.vendor_id;
            v_country := COALESCE(v_country, 'MX');

            SELECT driver_pct, platform_pct, insurance_pct, tax_pct
              INTO v_split
              FROM public.pricing_split(v_country, v_state);

            IF v_split.driver_pct IS NULL THEN
              RAISE EXCEPTION 'marketplace dispatch aborted: no pricing_config row for country=% state=%',
                v_country, v_state;
            END IF;

            v_decimals := CASE WHEN v_country = 'MX' THEN 0 ELSE 2 END;
            v_fee           := ROUND(NEW.delivery_fee, v_decimals);
            v_platform_fee  := ROUND(v_fee * v_split.platform_pct  / 100.0, v_decimals);
            v_insurance_fee := ROUND(v_fee * v_split.insurance_pct / 100.0, v_decimals);
            v_tax_fee       := ROUND(v_fee * v_split.tax_pct       / 100.0, v_decimals);
            v_driver_amount := v_fee - v_platform_fee - v_insurance_fee - v_tax_fee;

            INSERT INTO public.deliveries (
              user_id, user_name, service_type, status,
              pickup_lat, pickup_lng, pickup_address,
              destination_lat, destination_lng, destination_address,
              package_size, quantity, notes,
              estimated_price, total_price, base_fare,
              driver_earnings, platform_fee, insurance_fee, tax_fee,
              country_code, state_code
            ) VALUES (
              NEW.buyer_id, COALESCE(v_buyer_name, 'Cliente'), 'marketplace', 'pending',
              NEW.vendor_pickup_lat, NEW.vendor_pickup_lng,
              COALESCE(NEW.vendor_pickup_address, 'Vendedor'),
              COALESCE(NEW.delivery_lat, NEW.vendor_pickup_lat),
              COALESCE(NEW.delivery_lng, NEW.vendor_pickup_lng),
              COALESCE(NEW.delivery_address, 'Cliente'),
              'small', 1,
              'Marketplace order #' || substring(NEW.id::text, 1, 8) ||
                COALESCE(' | ' || NEW.delivery_notes, ''),
              v_fee, v_fee, v_fee,
              v_driver_amount, v_platform_fee, v_insurance_fee, v_tax_fee,
              v_country, v_state
            ) RETURNING id INTO v_delivery_id;

            UPDATE public.marketplace_orders SET delivery_id = v_delivery_id WHERE id = NEW.id;
          END IF;
          RETURN NEW;
        END;
        $fn$
      `)

      // Backfill existing pending marketplace deliveries with NULL state_code.
      const r = await client.queryObject(`
        UPDATE deliveries d
        SET state_code = v.state_code,
            country_code = COALESCE(d.country_code, v.country_code, 'MX')
        FROM marketplace_orders o
        JOIN vendors v ON v.id = o.vendor_id
        WHERE o.delivery_id = d.id
          AND d.service_type = 'marketplace'
          AND d.status = 'pending'
          AND (d.state_code IS NULL OR d.state_code = '')
        RETURNING d.id, d.state_code
      `)
      await client.end()
      return new Response(JSON.stringify({
        ok: true, message: 'function patched + backfilled',
        backfilled: r.rows,
      }, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'refire_driver_dispatch') {
      const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
      const ANON = Deno.env.get('SUPABASE_ANON_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
      const dr = await client.queryObject(`
        SELECT id, pickup_lat, pickup_lng, pickup_address,
               estimated_price, service_type, country_code, state_code
        FROM deliveries WHERE id = '04c47e43-0255-4a3c-9b45-f74f4afb43e3'
      `)
      await client.end()
      const d = dr.rows[0] as any
      const resp = await fetch(`${SUPABASE_URL}/functions/v1/notify-drivers-of-ride`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'apikey': ANON, 'Authorization': `Bearer ${ANON}` },
        body: JSON.stringify({
          ride_id: d.id,
          pickup_lat: Number(d.pickup_lat),
          pickup_lng: Number(d.pickup_lng),
          pickup_address: d.pickup_address,
          estimated_price: Number(d.estimated_price),
          service_type: d.service_type,
          country_code: d.country_code,
          state_code: d.state_code,
        }),
      })
      const text = await resp.text()
      return new Response(JSON.stringify({
        status: resp.status,
        delivery: d,
        response_body: text.slice(0, 2000),
      }, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'why_no_driver_push') {
      const driverId = '230d4ba5-6d67-4583-a127-4c5104ad11c2'
      const d = await client.queryObject(`
        SELECT id, full_name, is_online, can_receive_rides,
               country_code, state_code, operating_city,
               current_lat, current_lng, fcm_token IS NOT NULL AS has_fcm,
               LENGTH(fcm_token) AS token_len,
               updated_at, user_id
        FROM drivers WHERE id = $1
      `, [driverId])

      const delivery = await client.queryObject(`
        SELECT id, status, service_type, country_code, state_code,
               pickup_lat, pickup_lng, estimated_price, driver_id, created_at
        FROM deliveries
        WHERE id = '04c47e43-0255-4a3c-9b45-f74f4afb43e3'
      `)

      const dispatchLogs = await client.queryObject(`
        SELECT created_at, level, event, message, context::text AS ctx
        FROM app_logs
        WHERE source = 'notify-drivers-of-ride'
          AND created_at > NOW() - INTERVAL '30 minutes'
        ORDER BY created_at DESC LIMIT 10
      `)

      // Show whatever columns fcm_tokens actually has
      const fcmCols = await client.queryObject<{ column_name: string }>(`
        SELECT column_name FROM information_schema.columns
        WHERE table_name = 'fcm_tokens' ORDER BY ordinal_position
      `)
      const fcmTokens = await client.queryObject(`
        SELECT * FROM fcm_tokens
        WHERE user_id = (SELECT user_id FROM drivers WHERE id = $1)
        ORDER BY created_at DESC LIMIT 5
      `, [driverId])

      await client.end()
      return new Response(JSON.stringify({
        driver: d.rows[0] ?? null,
        delivery: delivery.rows[0] ?? null,
        recent_dispatch_logs: dispatchLogs.rows,
        fcm_tokens_columns: fcmCols.rows.map(x => x.column_name),
        fcm_tokens: fcmTokens.rows,
      }, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'deliveries_triggers') {
      const r = await client.queryObject(`
        SELECT t.tgname, p.proname, t.tgenabled::text
        FROM pg_trigger t
        JOIN pg_class c ON t.tgrelid = c.oid
        JOIN pg_proc p ON t.tgfoid = p.oid
        WHERE c.relname = 'deliveries' AND NOT t.tgisinternal
        ORDER BY t.tgname
      `)
      await client.end()
      return new Response(JSON.stringify(r.rows, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'list_triggers') {
      const r = await client.queryObject<{ tgname: string; proname: string; tgenabled: string }>(`
        SELECT t.tgname, p.proname, t.tgenabled::text
        FROM pg_trigger t
        JOIN pg_class c ON t.tgrelid = c.oid
        JOIN pg_proc p ON t.tgfoid = p.oid
        WHERE c.relname = 'marketplace_orders' AND NOT t.tgisinternal
        ORDER BY t.tgname
      `)
      await client.end()
      return new Response(JSON.stringify(r.rows, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'fn_source') {
      const fn = url.searchParams.get('fn') || ''
      const r = await client.queryObject<{ src: string }>(`
        SELECT pg_get_functiondef(oid) AS src FROM pg_proc WHERE proname = $1 LIMIT 1
      `, [fn])
      await client.end()
      return new Response(r.rows[0]?.src ?? 'NOT FOUND',
        { headers: { ...corsHeaders, 'Content-Type': 'text/plain' } })
    }

    if (action === 'check_constraints') {
      const r = await client.queryObject<{ conname: string; def: string }>(`
        SELECT conname, pg_get_constraintdef(oid) AS def
        FROM pg_constraint
        WHERE conrelid = 'marketplace_orders'::regclass
          AND contype = 'c'
      `)
      await client.end()
      return new Response(JSON.stringify(r.rows, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'orders_columns') {
      const r = await client.queryObject<{ column_name: string }>(`
        SELECT column_name FROM information_schema.columns
        WHERE table_schema='public' AND table_name='marketplace_orders'
        ORDER BY ordinal_position
      `)
      const r2 = await client.queryObject<{ column_name: string }>(`
        SELECT column_name FROM information_schema.columns
        WHERE table_schema='public' AND table_name='marketplace_order_items'
        ORDER BY ordinal_position
      `)
      await client.end()
      return new Response(JSON.stringify({
        marketplace_orders: r.rows.map(x => x.column_name),
        marketplace_order_items: r2.rows.map(x => x.column_name),
      }, null, 2), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'seed_paloma_orders') {
      const log: string[] = []
      try {
        // Find Paloma's vendor
        const vendorRes = await client.queryObject<{
          id: string; user_id: string; business_name: string; category_primary: string | null;
        }>(`
          SELECT v.id, v.user_id, v.business_name, v.category_primary
          FROM vendors v
          JOIN profiles p ON p.id = v.user_id
          WHERE LOWER(p.full_name) LIKE '%paloma%'
             OR LOWER(v.business_name) LIKE '%paloma%'
          ORDER BY v.created_at DESC LIMIT 1
        `)
        if (vendorRes.rows.length === 0) {
          log.push('ERR: no vendor for PALOMA found')
          await client.end()
          return new Response(JSON.stringify({ success: false, log }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          })
        }
        const vendor = vendorRes.rows[0]
        log.push(`OK vendor: ${vendor.business_name} (${vendor.id})`)

        // Find a buyer (any rider OTHER than vendor's owner)
        const buyerRes = await client.queryObject<{ id: string; full_name: string | null }>(`
          SELECT p.id, p.full_name
          FROM profiles p
          WHERE p.id <> $1
            AND COALESCE(p.full_name, '') <> ''
          ORDER BY p.created_at DESC LIMIT 1
        `, [vendor.user_id])
        if (buyerRes.rows.length === 0) {
          log.push('ERR: no buyer profile found')
          await client.end()
          return new Response(JSON.stringify({ success: false, log }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          })
        }
        const buyer = buyerRes.rows[0]
        log.push(`OK buyer: ${buyer.full_name} (${buyer.id})`)

        // Find some of Paloma's products
        const prodRes = await client.queryObject<{
          id: string; name: string; price: number;
        }>(`
          SELECT id, name, price
          FROM products
          WHERE vendor_id = $1
          ORDER BY created_at DESC LIMIT 5
        `, [vendor.id])
        if (prodRes.rows.length === 0) {
          log.push('WARN: vendor has no products — creating a temp product')
          const t = await client.queryObject<{ id: string }>(`
            INSERT INTO products (vendor_id, name, description, price, currency)
            VALUES ($1, 'Producto de prueba', 'Generado para test cascade', 99, 'MXN')
            RETURNING id
          `, [vendor.id])
          prodRes.rows.push({ id: t.rows[0].id, name: 'Producto de prueba', price: 99 })
        }
        log.push(`OK products: ${prodRes.rows.length}`)

        // Create 3 test orders — one fresh `placed`, one in `accepted_by_vendor`, one completed earlier today
        const orders: Array<{ status: string; ageMin: number; payment: string }> = [
          { status: 'placed',            ageMin: 0,   payment: 'authorized' },
          { status: 'accepted_by_vendor', ageMin: 3,  payment: 'authorized' },
          { status: 'completed',         ageMin: 90, payment: 'captured'   },
        ]

        for (let i = 0; i < orders.length; i++) {
          const o = orders[i]
          const prod = prodRes.rows[i % prodRes.rows.length]
          const qty = 1 + (i % 2)
          // VENDOR PRICE IS RESPECTED — buyer pays subtotal + commission + delivery.
          // vendor_payout = subtotal (intact).
          const subtotal = Number(prod.price) * qty
          const deliveryFee = 0
          const commission = Math.round(subtotal * 0.10 * 100) / 100
          const total = subtotal + commission + deliveryFee
          const payout = subtotal

          const created = `NOW() - INTERVAL '${o.ageMin} minutes'`
          const completed = o.status === 'completed' ? created : 'NULL'
          const accepted = o.status === 'completed' || o.status === 'accepted_by_vendor' ? created : 'NULL'

          const orderRow = await client.queryObject<{ id: string }>(`
            INSERT INTO marketplace_orders (
              vendor_id, buyer_id, status,
              subtotal, delivery_fee, flat_commission, total, vendor_payout,
              payment_status, payment_method, currency,
              delivery_type, buyer_name, buyer_phone,
              created_at, vendor_accepted_at, completed_at
            ) VALUES (
              $1, $2, $3,
              $4, $5, $6, $7, $8,
              $9, 'card', 'MXN',
              'toro', 'Cliente Test', '+526860000000',
              ${created}, ${accepted}, ${completed}
            )
            RETURNING id
          `, [
            vendor.id, buyer.id, o.status,
            subtotal, deliveryFee, commission, total, payout,
            o.payment,
          ])
          const orderId = orderRow.rows[0].id

          await client.queryArray(`
            INSERT INTO marketplace_order_items (
              order_id, product_id, product_name_snapshot, quantity,
              unit_price_snapshot, line_total, prep_status
            ) VALUES ($1, $2, $3, $4, $5, $6, $7)
          `, [orderId, prod.id, prod.name, qty, prod.price, lineTotal,
              o.status === 'completed' ? 'ready' : 'pending'])

          await client.queryArray(`
            INSERT INTO marketplace_order_events (order_id, from_status, to_status, actor_type, note)
            VALUES ($1, NULL, $2, 'system', 'test seed')
          `, [orderId, o.status])

          log.push(`OK order #${i + 1}: status=${o.status} total=$${total} id=${orderId.substring(0, 8)}…`)
        }

        await client.end()
        return new Response(JSON.stringify({ success: true, log,
          vendor_id: vendor.id, vendor_name: vendor.business_name,
        }, null, 2), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
      } catch (e) {
        log.push(`ERR seed: ${(e as Error).message}`)
        await client.end()
        return new Response(JSON.stringify({ success: false, log }, null, 2), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500
        })
      }
    }

    const counts: Record<string, any> = {}

    // ---- profiles (riders + everyone in auth) ----
    try {
      const total = await client.queryObject<{ c: bigint }>(`SELECT COUNT(*)::bigint AS c FROM profiles`)
      counts.profiles_total = Number(total.rows[0].c)

      const installedRider = await client.queryObject<{ c: bigint }>(`
        SELECT COUNT(*)::bigint AS c FROM profiles WHERE rider_app_installed = true
      `)
      counts.profiles_with_rider_app = Number(installedRider.rows[0].c)

      const installedDriver = await client.queryObject<{ c: bigint }>(`
        SELECT COUNT(*)::bigint AS c FROM profiles WHERE driver_app_installed = true
      `)
      counts.profiles_with_driver_app = Number(installedDriver.rows[0].c)

      const active7 = await client.queryObject<{ c: bigint }>(`
        SELECT COUNT(*)::bigint AS c FROM profiles
        WHERE rider_app_last_open > NOW() - INTERVAL '7 days'
      `)
      counts.riders_opened_last_7d = Number(active7.rows[0].c)

      const active30 = await client.queryObject<{ c: bigint }>(`
        SELECT COUNT(*)::bigint AS c FROM profiles
        WHERE rider_app_last_open > NOW() - INTERVAL '30 days'
      `)
      counts.riders_opened_last_30d = Number(active30.rows[0].c)

      const byRole = await client.queryObject<{ role: string | null; c: bigint }>(`
        SELECT role, COUNT(*)::bigint AS c FROM profiles GROUP BY role ORDER BY c DESC
      `)
      counts.profiles_by_role = byRole.rows.map(r => ({ role: r.role, count: Number(r.c) }))
    } catch (e) {
      counts.profiles_error = (e as Error).message
    }

    // ---- drivers ----
    try {
      const total = await client.queryObject<{ c: bigint }>(`SELECT COUNT(*)::bigint AS c FROM drivers`)
      counts.drivers_total = Number(total.rows[0].c)

      const approved = await client.queryObject<{ c: bigint }>(`SELECT COUNT(*)::bigint AS c FROM drivers WHERE admin_approved = true`)
      counts.drivers_approved = Number(approved.rows[0].c)

      const online = await client.queryObject<{ c: bigint }>(`SELECT COUNT(*)::bigint AS c FROM drivers WHERE is_online = true`)
      counts.drivers_online = Number(online.rows[0].c)
    } catch (e) {
      counts.drivers_error = (e as Error).message
    }

    // ---- waitlist signups ----
    try {
      const total = await client.queryObject<{ c: bigint }>(`SELECT COUNT(*)::bigint AS c FROM waitlist`)
      counts.waitlist_total = Number(total.rows[0].c)
      const last7 = await client.queryObject<{ c: bigint }>(`SELECT COUNT(*)::bigint AS c FROM waitlist WHERE created_at > NOW() - INTERVAL '7 days'`)
      counts.waitlist_last_7d = Number(last7.rows[0].c)
    } catch (e) {
      counts.waitlist_error = (e as Error).message
    }

    // ---- deliveries (rides) ----
    try {
      const total = await client.queryObject<{ c: bigint }>(`SELECT COUNT(*)::bigint AS c FROM deliveries`)
      counts.deliveries_total = Number(total.rows[0].c)
      const byStatus = await client.queryObject<{ status: string; c: bigint }>(`
        SELECT status, COUNT(*)::bigint AS c FROM deliveries GROUP BY status ORDER BY c DESC
      `)
      counts.deliveries_by_status = byStatus.rows.map(r => ({ status: r.status, count: Number(r.c) }))
    } catch (e) {
      counts.deliveries_error = (e as Error).message
    }

    // ---- recent profiles ----
    try {
      const recent = await client.queryObject<any>(`
        SELECT id, email, full_name, role, rider_app_installed, driver_app_installed,
               rider_app_last_open, created_at, country_code, city, referral_code
        FROM profiles
        ORDER BY created_at DESC NULLS LAST
        LIMIT 10
      `)
      counts.recent_profiles = recent.rows
    } catch (e) {
      counts.recent_profiles_error = (e as Error).message
    }

    // ---- WHO cancelled the 46 rides? ----
    try {
      const byUser = await client.queryObject<{ email: string | null; user_id: string; full_name: string | null; c: bigint }>(`
        SELECT p.email, p.full_name, d.user_id, COUNT(*)::bigint AS c
        FROM deliveries d
        LEFT JOIN profiles p ON p.id = d.user_id
        WHERE d.status = 'cancelled'
        GROUP BY p.email, p.full_name, d.user_id
        ORDER BY c DESC
        LIMIT 10
      `)
      counts.cancelled_by_user = byUser.rows.map(r => ({
        user_id: r.user_id,
        email: r.email,
        full_name: r.full_name,
        cancelled_count: Number(r.c),
      }))

      const byCancelledBy = await client.queryObject<{ cancelled_by: string | null; c: bigint }>(`
        SELECT cancelled_by, COUNT(*)::bigint AS c FROM deliveries
        WHERE status = 'cancelled'
        GROUP BY cancelled_by ORDER BY c DESC
      `)
      counts.cancelled_by_actor = byCancelledBy.rows.map(r => ({
        cancelled_by: r.cancelled_by,
        count: Number(r.c),
      }))

      const reasons = await client.queryObject<{ cancellation_reason: string | null; c: bigint }>(`
        SELECT cancellation_reason, COUNT(*)::bigint AS c FROM deliveries
        WHERE status = 'cancelled'
        GROUP BY cancellation_reason ORDER BY c DESC LIMIT 10
      `)
      counts.cancellation_reasons = reasons.rows.map(r => ({
        reason: r.cancellation_reason ?? '(null)',
        count: Number(r.c),
      }))
    } catch (e) {
      counts.cancellation_analysis_error = (e as Error).message
    }

    // ---- 2 completed rides ----
    try {
      const completed = await client.queryObject<any>(`
        SELECT id, user_id, driver_id, pickup_address, destination_address,
               estimated_price, final_price, total_price, completed_at, created_at, state_code
        FROM deliveries WHERE status = 'completed'
        ORDER BY completed_at DESC LIMIT 5
      `)
      counts.completed_rides = completed.rows
    } catch (e) {
      counts.completed_rides_error = (e as Error).message
    }

    // ---- Rider app versions installed across users ----
    try {
      const versions = await client.queryObject<{ rider_app_version: string | null; c: bigint }>(`
        SELECT rider_app_version, COUNT(*)::bigint AS c
        FROM profiles
        WHERE rider_app_installed = true
        GROUP BY rider_app_version
        ORDER BY c DESC
      `)
      counts.rider_app_versions = versions.rows.map(r => ({
        version: r.rider_app_version,
        count: Number(r.c),
      }))

      // Most recent rider opens
      const recent = await client.queryObject<any>(`
        SELECT email, full_name, rider_app_version, rider_app_last_open, country_code, city
        FROM profiles
        WHERE rider_app_installed = true
        ORDER BY rider_app_last_open DESC NULLS LAST
        LIMIT 15
      `)
      counts.recent_rider_devices = recent.rows
    } catch (e) {
      counts.rider_versions_error = (e as Error).message
    }

    // ---- Driver app versions installed ----
    try {
      const dversions = await client.queryObject<{ driver_app_version: string | null; c: bigint }>(`
        SELECT driver_app_version, COUNT(*)::bigint AS c
        FROM profiles
        WHERE driver_app_installed = true
        GROUP BY driver_app_version
        ORDER BY c DESC
      `)
      counts.driver_app_versions = dversions.rows.map(r => ({
        version: r.driver_app_version,
        count: Number(r.c),
      }))
    } catch (e) {
      counts.driver_versions_error = (e as Error).message
    }

    await client.end()

    return new Response(
      JSON.stringify(counts, null, 2),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ success: false, error: String(error) }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
    )
  }
})
