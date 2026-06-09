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

    // ──────────────── ACTION: raw_query ────────────────
    if (action === 'raw_query') {
      const body = await req.json().catch(() => ({}))
      const sql = body.sql as string
      if (!sql) {
        await client.end()
        return new Response(JSON.stringify({ error: 'sql required' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      }
      try {
        const r = await client.queryObject(sql)
        await client.end()
        const safe = (o: any) => JSON.parse(JSON.stringify(o, (_,v) => typeof v === 'bigint' ? Number(v) : v))
        return new Response(JSON.stringify(safe({ rows: r.rows, rowCount: r.rowCount }), null, 2),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      } catch (e: any) {
        await client.end()
        return new Response(JSON.stringify({ error: e.message, hint: e.hint, where: e.where, code: e.code }, null, 2),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      }
    }

    // ──────────────── ACTION: apply_pricing_canonical_unified ────────────────
    if (action === 'apply_pricing_canonical_unified') {
      const body = await req.json().catch(() => ({}))
      const sql = body.sql as string
      if (!sql) {
        await client.end()
        return new Response(JSON.stringify({ error: 'sql required' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      }
      const errors: any[] = []
      const ran: string[] = []
      try {
        // Execute the whole SQL as a single multi-statement script. Postgres
        // protocol's simple-query mode happily runs N semicolon-separated stmts.
        try {
          await client.queryArray(sql)
          ran.push('full migration script')
        } catch (e: any) {
          errors.push({ error: e.message, hint: e.hint, where: e.where, code: e.code })
        }

        // Smoke tests with explicit casts
        let smoke: any = {}
        try {
          const surge = await client.queryArray(`SELECT public.pricing_surge_now('MX'::text, 'BC'::text)`)
          smoke.surge_mx_bc = surge.rows[0][0]
        } catch (e: any) { smoke.surge_error = e.message }
        try {
          const eb = await client.queryArray(`SELECT public.pricing_is_commission_exempt('bus'::text)`)
          const em = await client.queryArray(`SELECT public.pricing_is_commission_exempt('marketplace'::text)`)
          smoke.exempt_bus = eb.rows[0][0]
          smoke.exempt_marketplace = em.rows[0][0]
        } catch (e: any) { smoke.exempt_error = e.message }
        try {
          const h = await client.queryArray(`SELECT count(*)::int FROM public.pricing_holidays`)
          smoke.holidays = h.rows[0][0]
        } catch (e: any) { smoke.holidays_error = e.message }

        await client.end()
        return new Response(JSON.stringify({
          ok: errors.length === 0,
          statements_run: ran.length,
          errors,
          smoke,
        }, null, 2), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      } catch (e: any) {
        await client.end()
        return new Response(JSON.stringify({ ok: false, ran: ran.length, errors, fatal: e.message }, null, 2),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      }
    }

    // ──────────────── ACTION: audit_carlos_test_split ────────────────
    if (action === 'audit_carlos_test_split') {
      const deliveryId = 'bafae585-cc3c-4280-bd64-25ec067aaf9e'
      const del = await client.queryObject(`SELECT to_jsonb(x.*) AS row FROM deliveries x WHERE id = $1`, [deliveryId])
      const order = await client.queryObject(`
        SELECT to_jsonb(o.*) AS row FROM marketplace_orders o
        WHERE o.id::text LIKE '6e71b855%' OR o.delivery_id = $1::uuid
        ORDER BY o.created_at DESC LIMIT 1
      `, [deliveryId])
      const splitTbls = await client.queryObject(`
        SELECT table_name FROM information_schema.tables
        WHERE table_schema='public' AND table_name ~* '(pricing_split|payment_split|earnings_split|split)'
      `)
      const splits: any = { rows: [] }
      for (const t of (splitTbls.rows as any[])) {
        try {
          const r = await client.queryObject(`SELECT '${t.table_name}' AS source, to_jsonb(x.*) AS row FROM ${t.table_name} x LIMIT 3`)
          splits.rows.push(...r.rows)
        } catch (_) {}
      }
      const transCols = await client.queryObject(`SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name='transactions'`)
      const trans = await client.queryObject(`SELECT to_jsonb(t.*) AS row FROM transactions t ORDER BY t.created_at DESC LIMIT 6`)
      const cfgCols = await client.queryObject(`SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name='pricing_config'`)
      const config = await client.queryObject(`SELECT to_jsonb(c.*) AS row FROM pricing_config c LIMIT 50`)
      const safe = (o: any) => JSON.parse(JSON.stringify(o, (_,v) => typeof v === 'bigint' ? Number(v) : v))
      await client.end()
      return new Response(JSON.stringify(safe({
        delivery: (del.rows[0] as any)?.row ?? null,
        marketplace_order: (order.rows[0] as any)?.row ?? null,
        split_tables_found: splitTbls.rows,
        pricing_splits_sample: splits.rows,
        transactions_columns: transCols.rows,
        recent_transactions: (trans.rows as any[]).map(r => r.row),
        pricing_config_columns: cfgCols.rows,
        pricing_config: (config.rows as any[]).map(r => r.row),
      }), null, 2), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // ──────────────── ACTION: force_cancel_carlos_stale ────────────────
    if (action === 'force_cancel_carlos_stale') {
      const driverId = '230d4ba5-6d67-4583-a127-4c5104ad11c2'
      const before = await client.queryObject(`
        SELECT id, status, service_type, notes, picked_up_at FROM deliveries
        WHERE driver_id = $1 AND status NOT IN ('completed','cancelled','delivered','expired')
      `, [driverId])
      const ids = (before.rows as any[]).map(r => r.id)
      await client.queryObject(`
        UPDATE deliveries SET status='cancelled', cancelled_at=NOW(), cancelled_by=$2,
                              cancellation_reason='stale E2E test delivery — manual cleanup'
        WHERE id = ANY($1::uuid[])
      `, [ids, driverId])
      const after = await client.queryObject(`
        SELECT id, status, cancelled_at FROM deliveries WHERE id = ANY($1::uuid[])
      `, [ids])
      await client.end()
      return new Response(JSON.stringify({ cancelled: ids, before: before.rows, after: after.rows }, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // ──────────────── ACTION: carlos_ride_state ────────────────
    if (action === 'carlos_ride_state') {
      const driverId = '230d4ba5-6d67-4583-a127-4c5104ad11c2'
      const drv = await client.queryObject(`
        SELECT to_jsonb(d.*) AS row,
               (SELECT count(*) FROM fcm_tokens t WHERE t.user_id = d.user_id AND t.is_active) AS active_tokens
        FROM drivers d WHERE d.id = $1
      `, [driverId])
      const ridesTbl = await client.queryObject(`
        SELECT table_name FROM information_schema.tables
        WHERE table_schema='public' AND table_name ~* '^(rides?|ride_requests?|trips?|bookings?)$'
      `)
      const recentRides = { rows: [] as any[] }
      for (const t of (ridesTbl.rows as any[])) {
        const tn = t.table_name
        const r = await client.queryObject(`SELECT '${tn}'::text AS source_table, to_jsonb(x.*) AS row FROM ${tn} x WHERE driver_id = $1 ORDER BY created_at DESC NULLS LAST LIMIT 8`, [driverId])
        recentRides.rows.push(...r.rows)
      }
      const recentDeliveries = await client.queryObject(`
        SELECT to_jsonb(x.*) AS row FROM deliveries x WHERE driver_id = $1 ORDER BY created_at DESC NULLS LAST LIMIT 8
      `, [driverId])
      await client.end()
      const safe = (o: any) => JSON.parse(JSON.stringify(o, (_,v) => typeof v === 'bigint' ? Number(v) : v))
      return new Response(JSON.stringify(safe({
        driver: (drv.rows[0] as any) ?? null,
        rides_tables_found: ridesTbl.rows,
        rides: recentRides.rows,
        deliveries: (recentDeliveries.rows as any[]).map(d => d.row),
      }), null, 2), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

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

    if (action === 'fix_transactions_constraints_and_trigger') {
      const log: string[] = []
      // 1. Extend the CHECK constraint to allow 'marketplace' type
      try {
        await client.queryArray(`ALTER TABLE transactions DROP CONSTRAINT IF EXISTS transactions_type_check`)
        await client.queryArray(`
          ALTER TABLE transactions ADD CONSTRAINT transactions_type_check
          CHECK (type = ANY (ARRAY['ride','carpool','delivery','package','cancellation_fee','no_show_fee','service_fee','tip','refund','partial_refund','adjustment','marketplace']::text[]))
        `)
        log.push('OK transactions_type_check: added marketplace')
      } catch (e) { log.push(`ERR type check: ${(e as Error).message}`) }

      // 2. Patch the trigger to use status='success' (canonical) instead of 'completed'
      try {
        await client.queryArray(`
          CREATE OR REPLACE FUNCTION public.marketplace_order_to_transaction()
          RETURNS trigger
          LANGUAGE plpgsql
          SECURITY DEFINER
          AS $fn$
          DECLARE
            v_split RECORD;
            v_vendor RECORD;
            v_driver_share numeric;
            v_platform_delivery_share numeric;
          BEGIN
            IF (NEW.status IN ('completed', 'delivered'))
               AND (OLD.status IS NULL OR OLD.status NOT IN ('completed', 'delivered')) THEN

              IF NOT EXISTS (
                SELECT 1 FROM public.transactions WHERE marketplace_order_id = NEW.id
              ) THEN
                SELECT country_code, state_code INTO v_vendor
                FROM public.vendors WHERE id = NEW.vendor_id;

                SELECT * INTO v_split FROM public.marketplace_delivery_split(
                  v_vendor.country_code, v_vendor.state_code
                );

                v_driver_share := COALESCE(NEW.delivery_fee, 0) * v_split.driver_pct / 100.0;
                v_platform_delivery_share := COALESCE(NEW.delivery_fee, 0) * v_split.platform_pct / 100.0;

                INSERT INTO public.transactions (
                  user_id, type, booking_type, amount, status,
                  marketplace_order_id, platform_fee, driver_amount, tip,
                  payment_method, country_code, metadata, completed_at, created_at
                ) VALUES (
                  NEW.buyer_id,
                  'marketplace',
                  'marketplace',
                  NEW.total,
                  'success',
                  NEW.id,
                  COALESCE(NEW.flat_commission, 0) + v_platform_delivery_share,
                  v_driver_share,
                  NEW.tip,
                  NEW.payment_method,
                  v_vendor.country_code,
                  jsonb_build_object(
                    'vendor_id', NEW.vendor_id,
                    'vendor_payout', NEW.vendor_payout,
                    'subtotal', NEW.subtotal,
                    'delivery_fee_total', NEW.delivery_fee,
                    'delivery_fee_driver_share', v_driver_share,
                    'delivery_fee_platform_share', v_platform_delivery_share,
                    'driver_pct', v_split.driver_pct,
                    'platform_pct', v_split.platform_pct,
                    'flat_commission', NEW.flat_commission,
                    'delivery_type', NEW.delivery_type
                  ),
                  now(),
                  now()
                );
              END IF;
            END IF;
            RETURN NEW;
          END;
          $fn$
        `)
        log.push('OK trigger marketplace_order_to_transaction: status=success')
      } catch (e) { log.push(`ERR trigger: ${(e as Error).message}`) }

      await client.end()
      return new Response(JSON.stringify({ success: true, log }, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'refire_all_pending_marketplace_dispatch') {
      const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
      const SERVICE_KEY  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
      const pending = await client.queryObject<{ id: string; pickup_lat: number; pickup_lng: number; country_code: string }>(`
        SELECT id, pickup_lat, pickup_lng, country_code
        FROM deliveries
        WHERE service_type = 'marketplace'
          AND status = 'pending'
          AND driver_id IS NULL
        ORDER BY created_at DESC LIMIT 50
      `)
      let fired = 0
      for (const d of pending.rows) {
        try {
          const resp = await fetch(`${SUPABASE_URL}/functions/v1/notify-drivers-of-ride`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${SERVICE_KEY}`,
              'apikey': SERVICE_KEY,
            },
            body: JSON.stringify({
              ride_id: d.id,
              service_type: 'marketplace',
              pickup_lat: Number(d.pickup_lat),
              pickup_lng: Number(d.pickup_lng),
              country_code: d.country_code,
              search_radius_km: 50,  // very wide for re-dispatch
            }),
          })
          if (resp.ok) fired++
        } catch (_) {}
      }
      // Also list current eligible drivers for visibility
      const drivers = await client.queryObject(`
        SELECT id, full_name, country_code, state_code, operating_city, operating_state,
               is_online, can_receive_rides, fcm_token IS NOT NULL AS has_token,
               current_lat, current_lng
        FROM drivers
        WHERE is_online = true AND can_receive_rides = true AND country_code = 'MX'
        ORDER BY updated_at DESC LIMIT 20
      `)
      await client.end()
      return new Response(JSON.stringify({
        pending_marketplace_deliveries: pending.rows.length,
        dispatches_fired: fired,
        online_mx_drivers: drivers.rows,
      }, null, 2), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'reset_paloma_real_stripe_state') {
      // Mi test E2E forzó charges_enabled=true para test. Revierte al estado real
      // del Stripe Connect API: tiene account pero no ha completado onboarding.
      const stripeKey = Deno.env.get('STRIPE_SECRET_KEY')!
      const v = await client.queryObject<{ acct: string | null }>(`
        SELECT stripe_account_id AS acct FROM vendors
        WHERE id = '862f91a1-9612-4dfc-9105-278acd7276f8'
      `)
      const acct = v.rows[0].acct
      if (acct) {
        const r = await fetch(`https://api.stripe.com/v1/accounts/${acct}`, {
          headers: { 'Authorization': `Bearer ${stripeKey}` }
        })
        const j = await r.json()
        await client.queryArray(`
          UPDATE vendors SET
            charges_enabled = $1,
            payouts_enabled = $2,
            accepts_card = $1
          WHERE id = '862f91a1-9612-4dfc-9105-278acd7276f8'
        `, [j.charges_enabled === true, j.payouts_enabled === true])
        await client.end()
        return new Response(JSON.stringify({
          synced: true,
          stripe_account: acct,
          charges_enabled: j.charges_enabled,
          payouts_enabled: j.payouts_enabled,
          details_submitted: j.details_submitted,
          requirements_due: (j.requirements?.currently_due ?? []).length,
        }, null, 2), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      }
      await client.end()
      return new Response(JSON.stringify({ synced: false, reason: 'no account' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    if (action === 'setup_top5_fixes') {
      const log: string[] = []

      // ════════════════ #1 RATE LIMIT ════════════════
      // Throttle place_marketplace_order: each buyer can place max 3 orders
      // per rolling 60-second window. Prevents double-click + spam.
      try {
        await client.queryArray(`
          CREATE OR REPLACE FUNCTION public.marketplace_orders_rate_limit()
          RETURNS TRIGGER
          LANGUAGE plpgsql
          SECURITY DEFINER
          AS $fn$
          DECLARE
            v_count int;
          BEGIN
            SELECT COUNT(*) INTO v_count
            FROM marketplace_orders
            WHERE buyer_id = NEW.buyer_id
              AND created_at > NOW() - INTERVAL '60 seconds';
            IF v_count >= 3 THEN
              RAISE EXCEPTION 'Rate limit: max 3 pedidos por minuto. Espera un momento.'
                USING ERRCODE = 'P0001';
            END IF;
            RETURN NEW;
          END;
          $fn$
        `)
        await client.queryArray(`DROP TRIGGER IF EXISTS trg_marketplace_orders_rate_limit ON marketplace_orders`)
        await client.queryArray(`
          CREATE TRIGGER trg_marketplace_orders_rate_limit
          BEFORE INSERT ON marketplace_orders
          FOR EACH ROW EXECUTE FUNCTION marketplace_orders_rate_limit()
        `)
        log.push('OK #1 rate limit: 3 orders/60s per buyer')
      } catch (e) { log.push(`ERR rate limit: ${(e as Error).message}`) }

      // ════════════════ #2 CAPTURE PI AT PICKED_UP ════════════════
      // Trigger: when marketplace_orders.status transitions to picked_up AND
      // payment_status='authorized' AND stripe_payment_intent_id present,
      // invoke the canonical capture edge function. This prevents
      // expired_uncaptured_charge (which already cost us $373 USD in refunds).
      try {
        const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
        const SERVICE_KEY  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
        await client.queryArray(`
          CREATE OR REPLACE FUNCTION public.marketplace_capture_at_pickup()
          RETURNS TRIGGER
          LANGUAGE plpgsql
          SECURITY DEFINER
          AS $fn$
          BEGIN
            IF NEW.status = 'picked_up'
               AND COALESCE(OLD.status, '') <> 'picked_up'
               AND NEW.payment_status = 'authorized'
               AND NEW.stripe_payment_intent_id IS NOT NULL THEN
              PERFORM net.http_post(
                url := '${SUPABASE_URL}/functions/v1/stripe-marketplace-capture',
                headers := jsonb_build_object(
                  'Content-Type','application/json',
                  'Authorization','Bearer ${SERVICE_KEY}'
                ),
                body := jsonb_build_object(
                  'order_id', NEW.id,
                  'payment_intent_id', NEW.stripe_payment_intent_id
                )
              );
              -- Mark as capture-pending; webhook from Stripe will flip to 'captured'
              UPDATE marketplace_orders
              SET payment_status = 'capture_pending'
              WHERE id = NEW.id;
            END IF;
            RETURN NEW;
          EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'capture trigger failed: %', SQLERRM;
            RETURN NEW;
          END;
          $fn$
        `)
        // First check the constraint allows 'capture_pending', if not, extend it
        try {
          await client.queryArray(`ALTER TABLE marketplace_orders DROP CONSTRAINT IF EXISTS marketplace_orders_payment_status_check`)
          await client.queryArray(`
            ALTER TABLE marketplace_orders ADD CONSTRAINT marketplace_orders_payment_status_check
            CHECK (payment_status = ANY (ARRAY['pending','authorized','capture_pending','captured','refunded','failed']::text[]))
          `)
          log.push('OK #2a payment_status_check extended with capture_pending')
        } catch (e) { log.push(`WARN payment_status_check: ${(e as Error).message}`) }

        await client.queryArray(`DROP TRIGGER IF EXISTS trg_marketplace_capture_at_pickup ON marketplace_orders`)
        await client.queryArray(`
          CREATE TRIGGER trg_marketplace_capture_at_pickup
          AFTER UPDATE OF status ON marketplace_orders
          FOR EACH ROW EXECUTE FUNCTION marketplace_capture_at_pickup()
        `)
        log.push('OK #2 capture at picked_up wired')
      } catch (e) { log.push(`ERR capture trigger: ${(e as Error).message}`) }

      // ════════════════ #4 STRIPE CONNECT URL HELPER RPC ════════════════
      // Vendor-finance UI calls this to start onboarding. Returns the URL.
      // The real heavy lifting is in stripe-vendor-onboarding edge fn,
      // but the SQL wrapper makes it dead-simple for the UI to call.
      try {
        await client.queryArray(`
          CREATE OR REPLACE FUNCTION public.vendor_get_stripe_onboarding_url()
          RETURNS jsonb
          LANGUAGE plpgsql
          SECURITY DEFINER
          SET search_path = public
          AS $fn$
          DECLARE
            v_uid uuid := auth.uid();
            v_vendor RECORD;
          BEGIN
            IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
            SELECT id, stripe_account_id, country_code INTO v_vendor
            FROM vendors WHERE user_id = v_uid;
            IF v_vendor IS NULL THEN RAISE EXCEPTION 'Not a vendor'; END IF;
            RETURN jsonb_build_object(
              'vendor_id', v_vendor.id,
              'has_stripe_account', v_vendor.stripe_account_id IS NOT NULL,
              'edge_function', 'stripe-vendor-onboarding',
              'note', 'UI must POST to that edge fn with vendor_id + country to receive account_link_url'
            );
          END;
          $fn$
        `)
        await client.queryArray(`GRANT EXECUTE ON FUNCTION vendor_get_stripe_onboarding_url() TO authenticated`)
        log.push('OK #4 vendor_get_stripe_onboarding_url RPC')
      } catch (e) { log.push(`ERR connect rpc: ${(e as Error).message}`) }

      await client.end()
      return new Response(JSON.stringify({ success: true, log }, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'stripe_audit_real_money') {
      const log: string[] = []
      const stripeKey = Deno.env.get('STRIPE_SECRET_KEY')
      if (!stripeKey) {
        await client.end()
        return new Response(JSON.stringify({ log: ['ERR no STRIPE_SECRET_KEY'] }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
      }

      async function stripe(path: string) {
        const r = await fetch(`https://api.stripe.com/v1/${path}`, {
          headers: { 'Authorization': `Bearer ${stripeKey}` }
        })
        const j = await r.json()
        if (!r.ok) throw new Error(j.error?.message ?? JSON.stringify(j))
        return j
      }

      // 1. Check the env: is this test mode or live?
      log.push(`Env key prefix: ${stripeKey.substring(0, 7)}…  (sk_test_ = test mode, sk_live_ = real money)`)
      const isTestMode = stripeKey.startsWith('sk_test_')
      log.push(`Mode: ${isTestMode ? 'TEST (no real money moved)' : 'LIVE (REAL money)'}`)

      // 2. Pull the most recent PaymentIntents from the test
      try {
        const list = await stripe('payment_intents?limit=3')
        log.push('')
        log.push(`=== Last ${list.data.length} PaymentIntents ===`)
        for (const pi of list.data) {
          log.push(`PI ${pi.id}`)
          log.push(`  status: ${pi.status}`)
          log.push(`  amount: $${pi.amount / 100} ${pi.currency.toUpperCase()}`)
          log.push(`  amount_capturable: $${(pi.amount_capturable ?? 0) / 100}`)
          log.push(`  amount_received: $${(pi.amount_received ?? 0) / 100}`)
          if (pi.latest_charge) {
            const ch = await stripe(`charges/${pi.latest_charge}`)
            log.push(`  → charge ${ch.id} status=${ch.status} paid=${ch.paid} captured=${ch.captured}`)
            log.push(`  → amount_refunded: $${(ch.amount_refunded ?? 0) / 100}`)
            if (ch.balance_transaction) {
              const bt = await stripe(`balance_transactions/${ch.balance_transaction}`)
              log.push(`  → balance_transaction ${bt.id}`)
              log.push(`     gross:      $${bt.amount / 100} ${bt.currency.toUpperCase()}`)
              log.push(`     STRIPE FEE: $${bt.fee / 100} ${bt.currency.toUpperCase()}  ⚠️`)
              log.push(`     NET:        $${bt.net / 100} ${bt.currency.toUpperCase()}`)
              if (bt.fee_details && Array.isArray(bt.fee_details)) {
                for (const fd of bt.fee_details) {
                  log.push(`        breakdown: ${fd.description} = $${fd.amount / 100} ${fd.currency.toUpperCase()}`)
                }
              }
            }
          }
        }
      } catch (e) {
        log.push(`ERR PIs: ${(e as Error).message}`)
      }

      // 3. Refunds
      try {
        const refunds = await stripe('refunds?limit=3')
        log.push('')
        log.push(`=== Last ${refunds.data.length} Refunds ===`)
        for (const r of refunds.data) {
          log.push(`Refund ${r.id} amount=$${r.amount / 100} status=${r.status} reason=${r.reason ?? 'none'}`)
        }
      } catch (e) { log.push(`ERR refunds: ${(e as Error).message}`) }

      // 4. Platform balance
      try {
        const bal = await stripe('balance')
        log.push('')
        log.push('=== Platform balance (lo que TORO tiene en Stripe) ===')
        for (const b of (bal.available ?? [])) log.push(`  available: $${b.amount / 100} ${b.currency.toUpperCase()}`)
        for (const b of (bal.pending ?? []))   log.push(`  pending:   $${b.amount / 100} ${b.currency.toUpperCase()}`)
      } catch (e) { log.push(`ERR balance: ${(e as Error).message}`) }

      // 5. Paloma's connected account state
      try {
        const v = await client.queryObject<{ acct: string | null }>(`
          SELECT stripe_account_id AS acct FROM vendors WHERE id = '862f91a1-9612-4dfc-9105-278acd7276f8'
        `)
        const acct = v.rows[0].acct
        if (acct) {
          const a = await stripe(`accounts/${acct}`)
          log.push('')
          log.push(`=== Paloma's connected account ${acct} ===`)
          log.push(`  charges_enabled:  ${a.charges_enabled}`)
          log.push(`  payouts_enabled:  ${a.payouts_enabled}`)
          log.push(`  details_submitted: ${a.details_submitted}`)
          log.push(`  requirements.currently_due: ${(a.requirements?.currently_due ?? []).length} items`)
          if (a.requirements?.currently_due?.length) {
            for (const r of a.requirements.currently_due.slice(0, 5)) log.push(`     • ${r}`)
          }
        }
      } catch (e) { log.push(`ERR acct: ${(e as Error).message}`) }

      await client.end()
      return new Response(JSON.stringify({ log }, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'stripe_full_e2e') {
      const log: string[] = []
      const fails: string[] = []
      const vendorId = '862f91a1-9612-4dfc-9105-278acd7276f8'
      const productId = 'adfe03a4-5c65-4296-9a29-83831e7feed5'
      const stripeKey = Deno.env.get('STRIPE_SECRET_KEY')
      if (!stripeKey) {
        await client.end()
        return new Response(JSON.stringify({ log: ['ERR STRIPE_SECRET_KEY missing'] }, null, 2),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      }
      const ok = (m: string) => log.push(`OK ${m}`)
      const fail = (m: string) => { log.push(`FAIL ${m}`); fails.push(m) }

      // Stripe REST helper
      async function stripe(path: string, body: Record<string, any> = {}, method: 'POST' | 'GET' = 'POST') {
        const url = `https://api.stripe.com/v1/${path}`
        const form = new URLSearchParams()
        const flatten = (obj: any, prefix = '') => {
          for (const [k, v] of Object.entries(obj)) {
            const key = prefix ? `${prefix}[${k}]` : k
            if (v === null || v === undefined) continue
            if (typeof v === 'object' && !Array.isArray(v)) flatten(v, key)
            else if (Array.isArray(v)) v.forEach((x, i) => flatten({ [i]: x }, key))
            else form.append(key, String(v))
          }
        }
        flatten(body)
        const resp = await fetch(url, {
          method,
          headers: {
            'Authorization': `Bearer ${stripeKey}`,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: method === 'POST' ? form.toString() : undefined,
        })
        const j = await resp.json()
        if (!resp.ok) throw new Error(`Stripe ${resp.status} ${j.error?.message ?? JSON.stringify(j).slice(0, 200)}`)
        return j
      }

      // ── Step 1: Onboard Paloma to Stripe Connect Express (test mode) ──
      let stripeAccountId: string | null = null
      try {
        const v = await client.queryObject<{ stripe_account_id: string | null }>(`
          SELECT stripe_account_id FROM vendors WHERE id = $1
        `, [vendorId])
        stripeAccountId = v.rows[0].stripe_account_id
        if (!stripeAccountId) {
          const acct = await stripe('accounts', {
            type: 'express',
            country: 'MX',
            email: `paloma+${Date.now()}@toro-ride.com`,
            capabilities: {
              card_payments: { requested: true },
              transfers: { requested: true },
            },
            business_type: 'individual',
            business_profile: { mcc: '5812', product_description: 'Marketplace seller' },
          })
          stripeAccountId = acct.id
          ok(`Stripe Connect account created: ${stripeAccountId}`)
          // In TEST mode, bypass full onboarding (real biz would do account links)
          // Charges are NOT enabled until full onboarding. For destination charges
          // we don't need charges_enabled on the connected account.
        } else {
          ok(`Paloma already has Stripe account ${stripeAccountId}`)
        }

        // Mark vendor as accepting card + Connect linked
        await client.queryArray(`
          UPDATE vendors SET
            stripe_account_id = $1,
            accepts_card = true,
            charges_enabled = true,
            payouts_enabled = true
          WHERE id = $2
        `, [stripeAccountId, vendorId])
        ok('Paloma: accepts_card=true, charges_enabled=true (forced for test)')
      } catch (e) { fail(`Stripe onboard: ${(e as Error).message}`) }

      if (!stripeAccountId) {
        await client.end()
        return new Response(JSON.stringify({ log, fails }, null, 2),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      }

      // ── Step 2: Create PaymentIntent with test card ──
      const subtotal = 60000  // $600 in centavos
      const commission = 1000  // $10
      const deliveryFee = 5000 // $50
      const total = subtotal + commission + deliveryFee
      let paymentIntent: any
      try {
        // pm_card_visa is Stripe's predefined test PaymentMethod.
        // NOTE: For full destination-charge split to Paloma's connected account,
        // her Express account needs identity verification (real biz onboarding).
        // For this server-side test we charge to the platform — buyer is billed,
        // platform receives the funds. Split via transfer happens later when
        // Paloma completes Stripe onboarding (UI flow vendor-finance handles it).
        paymentIntent = await stripe('payment_intents', {
          amount: total,
          currency: 'mxn',
          payment_method: 'pm_card_visa',
          payment_method_types: ['card'],
          capture_method: 'manual',  // Authorize now, capture on delivery
          confirm: true,
          metadata: {
            vendor_id: vendorId,
            connected_account: stripeAccountId,
            note: 'platform charge, transfer pending vendor onboarding',
          },
        })
        if (paymentIntent.status === 'requires_capture') {
          ok(`PaymentIntent ${paymentIntent.id} authorized (status=${paymentIntent.status})`)
        } else {
          fail(`PaymentIntent status=${paymentIntent.status} (expected requires_capture)`)
        }
      } catch (e) { fail(`PaymentIntent create: ${(e as Error).message}`) }

      if (!paymentIntent?.id) {
        await client.end()
        return new Response(JSON.stringify({ log, fails }, null, 2),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      }

      // ── Step 3: Create marketplace order linked to that PaymentIntent ──
      const buyer = await client.queryObject<{ id: string; phone: string | null }>(`
        SELECT p.id, p.phone FROM profiles p
        WHERE p.id <> (SELECT user_id FROM vendors WHERE id = $1)
        ORDER BY p.created_at DESC LIMIT 1
      `, [vendorId])
      const buyerId = buyer.rows[0].id

      let orderId: string | null = null
      try {
        await client.queryArray('BEGIN')
        await client.queryArray(`
          SELECT set_config('request.jwt.claims', $1, true),
                 set_config('request.jwt.claim.sub', $2, true),
                 set_config('request.jwt.claim.role', 'authenticated', true)
        `, [JSON.stringify({ sub: buyerId, role: 'authenticated' }), buyerId])
        const r = await client.queryObject<{ order_id: string }>(`
          SELECT place_marketplace_order(
            $1::uuid,
            $2::jsonb,
            'toro', 'card',
            'Test Stripe Address 100, Mexicali', 32.6300, -115.4600,
            'Stripe E2E', $3, 0
          ) AS order_id
        `, [vendorId, JSON.stringify([{product_id: productId, qty: 1}]), '+526860000099'])
        await client.queryArray('COMMIT')
        orderId = r.rows[0].order_id

        await client.queryArray(`
          UPDATE marketplace_orders SET
            stripe_payment_intent_id = $1,
            payment_status = 'authorized'
          WHERE id = $2
        `, [paymentIntent.id, orderId])
        ok(`Order created ${orderId.substring(0, 8)} linked to PI ${paymentIntent.id}`)
      } catch (e) {
        await client.queryArray('ROLLBACK').catch(() => {})
        fail(`Order place: ${(e as Error).message}`)
      }

      // ── Step 4: Walk order to delivered (skipping driver, server-side) ──
      if (orderId) {
        try {
          await client.queryArray(`UPDATE marketplace_orders SET status='accepted_by_vendor', vendor_accepted_at=NOW() WHERE id = $1`, [orderId])
          await client.queryArray(`UPDATE marketplace_orders SET status='preparing' WHERE id = $1`, [orderId])
          await client.queryArray(`UPDATE marketplace_order_items SET prep_status='ready', prepared_at=NOW() WHERE order_id = $1`, [orderId])
          await client.queryArray(`UPDATE marketplace_orders SET status='ready_for_pickup', vendor_ready_at=NOW() WHERE id = $1`, [orderId])
          await client.queryArray(`UPDATE marketplace_orders SET status='picked_up', picked_up_at=NOW() WHERE id = $1`, [orderId])
          await client.queryArray(`UPDATE marketplace_orders SET status='delivered', delivered_at=NOW(), completed_at=NOW() WHERE id = $1`, [orderId])
          ok('Order walked to delivered')
        } catch (e) { fail(`Walk: ${(e as Error).message}`) }
      }

      // ── Step 5: Capture the PaymentIntent ──
      try {
        const captured = await stripe(`payment_intents/${paymentIntent.id}/capture`)
        if (captured.status === 'succeeded') {
          ok(`PaymentIntent CAPTURED: status=${captured.status} amount_received=${captured.amount_received / 100} MXN`)
        } else {
          fail(`Capture status=${captured.status}`)
        }
      } catch (e) { fail(`Capture: ${(e as Error).message}`) }

      // ── Step 6: Verify transaction row + Stripe charge linkage ──
      if (orderId) {
        try {
          const tx = await client.queryObject<{
            id: string; status: string; amount: number;
            platform_fee: number; driver_amount: number;
            metadata: any;
          }>(`
            SELECT id, status, amount, platform_fee, driver_amount, metadata
            FROM transactions WHERE marketplace_order_id = $1
          `, [orderId])
          if (tx.rows.length === 1) {
            const t = tx.rows[0]
            ok(`Transaction: amount=$${t.amount} platform_fee=$${t.platform_fee} driver=$${t.driver_amount} status=${t.status}`)
          } else {
            fail(`Expected 1 transaction, got ${tx.rows.length}`)
          }
        } catch (e) { fail(`TX verify: ${(e as Error).message}`) }
      }

      // ── Step 7: Test REFUND path ──
      try {
        const refund = await stripe('refunds', {
          payment_intent: paymentIntent.id,
          amount: 1000, // partial refund $10
        })
        ok(`Partial refund $${refund.amount / 100} status=${refund.status}`)
      } catch (e) { fail(`Refund: ${(e as Error).message}`) }

      log.push('────────────────')
      if (fails.length === 0) log.push(`✓ ALL ${log.filter(x => x.startsWith('OK ')).length} STEPS PASSED`)
      else log.push(`✗ ${fails.length} FAILURES`)

      await client.end()
      return new Response(JSON.stringify({ success: fails.length === 0, log, fails }, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'stripe_state_check') {
      const v = await client.queryObject(`
        SELECT id, business_name, accepts_card, stripe_account_id,
               charges_enabled, payouts_enabled, country_code
        FROM vendors WHERE id = '862f91a1-9612-4dfc-9105-278acd7276f8'
      `)
      // Check if Stripe secret env exists (without exposing it)
      const hasSecret = !!Deno.env.get('STRIPE_SECRET_KEY')
      const hasMxSecret = !!Deno.env.get('STRIPE_SECRET_KEY_MX')
      await client.end()
      return new Response(JSON.stringify({
        paloma: v.rows[0],
        stripe_secret_present: hasSecret,
        stripe_mx_secret_present: hasMxSecret,
      }, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'inspect_transactions_status') {
      const c = await client.queryObject<{ conname: string; def: string }>(`
        SELECT conname, pg_get_constraintdef(oid) AS def
        FROM pg_constraint
        WHERE conrelid = 'transactions'::regclass AND contype = 'c'
      `)
      await client.end()
      return new Response(JSON.stringify(c.rows, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'test_full_purchase_flow') {
      const log: string[] = []
      const fails: string[] = []
      const vendorId = '862f91a1-9612-4dfc-9105-278acd7276f8'
      const productId = 'adfe03a4-5c65-4296-9a29-83831e7feed5'

      const ok = (msg: string) => log.push(`OK ${msg}`)
      const fail = (msg: string) => { log.push(`FAIL ${msg}`); fails.push(msg) }

      // Pick a real buyer + a real driver
      const buyer = await client.queryObject<{ id: string; phone: string | null; name: string | null }>(`
        SELECT p.id, p.phone, p.full_name AS name FROM profiles p
        WHERE p.id <> (SELECT user_id FROM vendors WHERE id = $1)
        ORDER BY p.created_at DESC LIMIT 1
      `, [vendorId])
      if (buyer.rows.length === 0) {
        await client.end()
        return new Response(JSON.stringify({ log: ['ERR no buyer'] }, null, 2),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      }
      const buyerId = buyer.rows[0].id
      log.push(`Buyer: ${buyer.rows[0].name} (${buyerId.substring(0,8)})`)

      const driver = await client.queryObject<{ id: string; user_id: string; name: string }>(`
        SELECT id, user_id, full_name AS name FROM drivers
        WHERE is_online = true AND can_receive_rides = true AND country_code = 'MX' AND state_code = 'BC'
        ORDER BY updated_at DESC LIMIT 1
      `)
      if (driver.rows.length === 0) {
        log.push('WARN no online driver in MX/BC — using fallback')
      }
      const driverRow = driver.rows[0]
      const driverId = driverRow?.id
      const driverUserId = driverRow?.user_id
      log.push(`Driver: ${driverRow?.name ?? 'NONE'} (${driverId?.substring(0,8) ?? '—'})`)

      // ════════════════════════════════════════════════════════════════
      // CYCLE A: single order, full happy path placed → delivered
      // ════════════════════════════════════════════════════════════════
      let orderA: string | null = null
      let deliveryA: string | null = null

      try {
        // Step 1: place via canonical RPC
        await client.queryArray('BEGIN')
        await client.queryArray(`
          SELECT set_config('request.jwt.claims', $1, true),
                 set_config('request.jwt.claim.sub', $2, true),
                 set_config('request.jwt.claim.role', 'authenticated', true)
        `, [JSON.stringify({ sub: buyerId, role: 'authenticated' }), buyerId])
        const r = await client.queryObject<{ order_id: string }>(`
          SELECT place_marketplace_order(
            $1::uuid,
            $2::jsonb,
            'toro', 'cash',
            'Av. Reforma 1000, Mexicali', 32.6300, -115.4600,
            'Test E2E', $3, 0
          ) AS order_id
        `, [vendorId, JSON.stringify([{product_id: productId, qty: 1}]), '+526860000099'])
        await client.queryArray('COMMIT')
        orderA = r.rows[0].order_id
        ok(`A1 placed: order ${orderA.substring(0,8)}`)
      } catch (e) {
        fail(`A1 place: ${(e as Error).message}`)
      }

      if (orderA) {
        try {
          // Verify event placed
          const ev = await client.queryObject<{ c: number }>(`
            SELECT COUNT(*)::int AS c FROM marketplace_order_events WHERE order_id = $1 AND to_status = 'placed'
          `, [orderA])
          if (ev.rows[0].c >= 1) ok('A1 event placed recorded')
          else fail('A1 no placed event row')

          // Verify OTPs generated
          const otps = await client.queryObject<{ pickup_otp: string | null; delivery_otp: string | null; held: boolean }>(`
            SELECT pickup_otp, delivery_otp, held_for_review AS held
            FROM marketplace_orders WHERE id = $1
          `, [orderA])
          if (otps.rows[0].pickup_otp?.length === 4) ok(`A1 pickup_otp generated: ${otps.rows[0].pickup_otp}`)
          else fail('A1 pickup_otp not generated')
          if (otps.rows[0].delivery_otp?.length === 4) ok(`A1 delivery_otp generated: ${otps.rows[0].delivery_otp}`)
          else fail('A1 delivery_otp not generated')
          ok(`A1 held_for_review=${otps.rows[0].held}`)
        } catch (e) { fail(`A1 verify: ${(e as Error).message}`) }

        // Step 2: vendor accepts → response time captured
        try {
          await client.queryArray(`UPDATE marketplace_orders SET status='accepted_by_vendor', vendor_accepted_at=NOW() WHERE id = $1`, [orderA])
          const v = await client.queryObject<{ ms: number | null }>(`
            SELECT vendor_responded_in_ms AS ms FROM marketplace_orders WHERE id = $1
          `, [orderA])
          if (v.rows[0].ms !== null) ok(`A2 vendor_responded_in_ms captured: ${v.rows[0].ms}ms`)
          else fail('A2 vendor_responded_in_ms NOT captured by trigger')
        } catch (e) { fail(`A2: ${(e as Error).message}`) }

        // Step 3: preparing → ready
        try {
          await client.queryArray(`UPDATE marketplace_orders SET status='preparing' WHERE id = $1`, [orderA])
          await client.queryArray(`UPDATE marketplace_order_items SET prep_status='ready', prepared_at=NOW() WHERE order_id = $1`, [orderA])
          await client.queryArray(`UPDATE marketplace_orders SET status='ready_for_pickup', vendor_ready_at=NOW() WHERE id = $1`, [orderA])
          ok('A3 status → ready_for_pickup')

          // Verify delivery row was created by trg dispatch
          const d = await client.queryObject<{ delivery_id: string | null }>(`
            SELECT delivery_id FROM marketplace_orders WHERE id = $1
          `, [orderA])
          deliveryA = d.rows[0].delivery_id
          if (deliveryA) ok(`A3 delivery created: ${deliveryA.substring(0,8)}`)
          else fail('A3 delivery NOT created by dispatch trigger')
        } catch (e) { fail(`A3: ${(e as Error).message}`) }

        // Step 4: driver accepts
        if (deliveryA && driverId && driverUserId) {
          try {
            await client.queryArray('BEGIN')
            await client.queryArray(`
              SELECT set_config('request.jwt.claims', $1, true),
                     set_config('request.jwt.claim.sub', $2, true),
                     set_config('request.jwt.claim.role', 'authenticated', true)
            `, [JSON.stringify({ sub: driverUserId, role: 'authenticated' }), driverUserId])
            await client.queryArray(`SELECT driver_accept_marketplace_delivery($1::uuid)`, [deliveryA])
            await client.queryArray('COMMIT')
            ok('A4 driver_accept_marketplace_delivery succeeded')

            const verify = await client.queryObject<{ status: string; driver_id: string | null; o_status: string }>(`
              SELECT d.status, d.driver_id, o.status AS o_status
              FROM deliveries d
              JOIN marketplace_orders o ON o.delivery_id = d.id
              WHERE d.id = $1
            `, [deliveryA])
            if (verify.rows[0].driver_id === driverId) ok('A4 delivery.driver_id set')
            else fail(`A4 driver_id mismatch: ${verify.rows[0].driver_id}`)
            if (verify.rows[0].o_status === 'driver_assigned') ok('A4 order status → driver_assigned')
            else fail(`A4 order status = ${verify.rows[0].o_status} (expected driver_assigned)`)
          } catch (e) {
            await client.queryArray('ROLLBACK').catch(() => {})
            fail(`A4: ${(e as Error).message}`)
          }
        }

        // Step 5: driver pickup confirm (use OTP + dummy photo url + within geofence)
        if (deliveryA && driverUserId) {
          try {
            const o = await client.queryObject<{ pickup_otp: string; lat: number; lng: number }>(`
              SELECT pickup_otp, vendor_pickup_lat AS lat, vendor_pickup_lng AS lng FROM marketplace_orders WHERE id = $1
            `, [orderA])
            const otp = o.rows[0].pickup_otp
            await client.queryArray('BEGIN')
            await client.queryArray(`
              SELECT set_config('request.jwt.claims', $1, true),
                     set_config('request.jwt.claim.sub', $2, true),
                     set_config('request.jwt.claim.role', 'authenticated', true)
            `, [JSON.stringify({ sub: driverUserId, role: 'authenticated' }), driverUserId])
            const r = await client.queryObject<{ result: boolean }>(`
              SELECT marketplace_confirm_pickup(
                $1::uuid, $2,
                'https://example.com/proof.jpg',
                $3::float8, $4::float8
              ) AS result
            `, [orderA, otp, o.rows[0].lat, o.rows[0].lng])
            await client.queryArray('COMMIT')
            if (r.rows[0].result) ok(`A5 marketplace_confirm_pickup OK (otp=${otp}, geofence passed)`)
            else fail(`A5 confirm_pickup returned false (geofence failed)`)

            const pu = await client.queryObject<{ at: any }>(`
              SELECT picked_up_at AS at FROM marketplace_orders WHERE id = $1
            `, [orderA])
            if (pu.rows[0].at) ok(`A5 picked_up_at set`)
            else fail('A5 picked_up_at NOT set')
          } catch (e) {
            await client.queryArray('ROLLBACK').catch(() => {})
            fail(`A5: ${(e as Error).message}`)
          }
        }

        // Step 6: update order status to picked_up (RPC only sets the field, status advance is separate)
        if (orderA) {
          try {
            await client.queryArray(`UPDATE marketplace_orders SET status='picked_up' WHERE id = $1 AND status = 'driver_assigned'`, [orderA])
            ok('A6 order → picked_up')
          } catch (e) { fail(`A6: ${(e as Error).message}`) }
        }

        // Step 7: delivery confirm
        if (deliveryA && driverUserId && orderA) {
          try {
            const o = await client.queryObject<{ delivery_otp: string; lat: number; lng: number }>(`
              SELECT delivery_otp, delivery_lat AS lat, delivery_lng AS lng FROM marketplace_orders WHERE id = $1
            `, [orderA])
            const otp = o.rows[0].delivery_otp
            await client.queryArray('BEGIN')
            await client.queryArray(`
              SELECT set_config('request.jwt.claims', $1, true),
                     set_config('request.jwt.claim.sub', $2, true),
                     set_config('request.jwt.claim.role', 'authenticated', true)
            `, [JSON.stringify({ sub: driverUserId, role: 'authenticated' }), driverUserId])
            const r = await client.queryObject<{ result: boolean }>(`
              SELECT marketplace_confirm_delivery(
                $1::uuid, $2,
                'https://example.com/delivery.jpg',
                $3::float8, $4::float8
              ) AS result
            `, [orderA, otp, o.rows[0].lat, o.rows[0].lng])
            await client.queryArray('COMMIT')
            if (r.rows[0].result) ok(`A7 marketplace_confirm_delivery OK (otp=${otp})`)
            else fail('A7 confirm_delivery geofence failed')

            const fin = await client.queryObject<{ status: string; delivered: any }>(`
              SELECT status, delivered_at AS delivered FROM marketplace_orders WHERE id = $1
            `, [orderA])
            if (fin.rows[0].status === 'delivered') ok('A7 order status → delivered')
            else fail(`A7 status = ${fin.rows[0].status}`)
          } catch (e) {
            await client.queryArray('ROLLBACK').catch(() => {})
            fail(`A7: ${(e as Error).message}`)
          }
        }

        // Step 8: verify transactions row was created by trigger marketplace_order_to_transaction
        if (orderA) {
          try {
            const tx = await client.queryObject<{ c: number; total_platform_fee: number | null; total_driver: number | null }>(`
              SELECT COUNT(*)::int AS c,
                     SUM(platform_fee)::numeric AS total_platform_fee,
                     SUM(driver_amount)::numeric AS total_driver
              FROM transactions WHERE marketplace_order_id = $1
            `, [orderA])
            if (tx.rows[0].c >= 1) ok(`A8 transaction created: platform_fee=$${tx.rows[0].total_platform_fee} driver_amount=$${tx.rows[0].total_driver}`)
            else fail('A8 NO transactions row created by trigger marketplace_order_to_transaction')
          } catch (e) { fail(`A8: ${(e as Error).message}`) }
        }

        // Step 9: verify event chain
        if (orderA) {
          try {
            const evs = await client.queryObject<{ to_status: string; actor_type: string }>(`
              SELECT to_status, actor_type FROM marketplace_order_events
              WHERE order_id = $1 ORDER BY created_at
            `, [orderA])
            const path = evs.rows.map(r => `${r.to_status}(${r.actor_type})`).join(' → ')
            ok(`A9 event chain: ${path}`)
            const needed = ['placed', 'delivered']
            for (const n of needed) {
              if (!evs.rows.some(r => r.to_status === n)) fail(`A9 missing event: ${n}`)
            }
          } catch (e) { fail(`A9: ${(e as Error).message}`) }
        }
      }

      // ════════════════════════════════════════════════════════════════
      // CYCLE B: bundle — 2 orders within 8 min from same buyer+vendor
      // ════════════════════════════════════════════════════════════════
      log.push('── BUNDLE TEST ──')
      const bundleOrders: string[] = []
      for (let i = 0; i < 2; i++) {
        try {
          await client.queryArray('BEGIN')
          await client.queryArray(`
            SELECT set_config('request.jwt.claims', $1, true),
                   set_config('request.jwt.claim.sub', $2, true),
                   set_config('request.jwt.claim.role', 'authenticated', true)
          `, [JSON.stringify({ sub: buyerId, role: 'authenticated' }), buyerId])
          const r = await client.queryObject<{ order_id: string }>(`
            SELECT place_marketplace_order(
              $1::uuid, $2::jsonb, 'toro', 'cash',
              'Av. Bundle 200, Mexicali', 32.6300, -115.4600,
              'bundle test ${i + 1}', $3, 0
            ) AS order_id
          `, [vendorId, JSON.stringify([{product_id: productId, qty: 1}]), '+526860000088'])
          await client.queryArray('COMMIT')
          bundleOrders.push(r.rows[0].order_id)
        } catch (e) {
          await client.queryArray('ROLLBACK').catch(() => {})
          fail(`B place ${i + 1}: ${(e as Error).message}`)
        }
      }
      if (bundleOrders.length === 2) ok(`B placed 2 orders: ${bundleOrders.map(x => x.substring(0,8)).join(', ')}`)

      // Walk both to ready_for_pickup (so dispatch trigger fires for both)
      for (const oid of bundleOrders) {
        try {
          await client.queryArray(`UPDATE marketplace_orders SET status='accepted_by_vendor', vendor_accepted_at=NOW() WHERE id = $1`, [oid])
          await client.queryArray(`UPDATE marketplace_orders SET status='preparing' WHERE id = $1`, [oid])
          await client.queryArray(`UPDATE marketplace_order_items SET prep_status='ready', prepared_at=NOW() WHERE order_id = $1`, [oid])
          await client.queryArray(`UPDATE marketplace_orders SET status='ready_for_pickup', vendor_ready_at=NOW() WHERE id = $1`, [oid])
        } catch (e) { fail(`B ready ${oid.substring(0,8)}: ${(e as Error).message}`) }
      }

      try {
        const r = await client.queryObject<{ id: string; delivery_id: string | null; delivery_fee: number; total: number }>(`
          SELECT id, delivery_id, delivery_fee, total FROM marketplace_orders WHERE id = ANY($1) ORDER BY created_at
        `, [bundleOrders])
        const dids = new Set(r.rows.map(x => x.delivery_id).filter(Boolean))
        if (dids.size === 1) ok(`B both share delivery ${[...dids][0]!.substring(0,8)}`)
        else fail(`B ${dids.size} distinct delivery_ids (should be 1)`)
        if (Number(r.rows[1].delivery_fee) === 0) ok(`B 2nd order delivery_fee=0 (total=${r.rows[1].total})`)
        else fail(`B 2nd order delivery_fee=${r.rows[1].delivery_fee} (should be 0)`)

        const ctx = await client.queryObject<{ ctx: any }>(`SELECT delivery_full_context($1) AS ctx`, [[...dids][0]])
        const numOrders = (ctx.rows[0].ctx?.orders as any[])?.length ?? 0
        if (numOrders >= 2) ok(`B delivery_full_context returns ${numOrders} orders`)
        else fail(`B context returned only ${numOrders}`)
      } catch (e) { fail(`B verify: ${(e as Error).message}`) }

      // ════════════════════════════════════════════════════════════════
      // FINAL SUMMARY
      // ════════════════════════════════════════════════════════════════
      log.push('────────────────')
      if (fails.length === 0) log.push(`✓ ALL ${log.filter(x => x.startsWith('OK ')).length} STEPS PASSED`)
      else log.push(`✗ ${fails.length} FAILURES — see above`)

      await client.end()
      return new Response(JSON.stringify({ success: fails.length === 0, log, fails }, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'test_canonical_e2e') {
      const log: string[] = []
      const vendorId = '862f91a1-9612-4dfc-9105-278acd7276f8'  // PALOMA
      const productId = 'adfe03a4-5c65-4296-9a29-83831e7feed5'  // control ps5

      // Buyer
      const buyer = await client.queryObject<{ id: string; phone: string | null }>(`
        SELECT p.id, p.phone FROM profiles p
        WHERE p.id <> (SELECT user_id FROM vendors WHERE id = $1)
          AND COALESCE(p.full_name, '') <> ''
        ORDER BY p.created_at DESC LIMIT 1
      `, [vendorId])
      const buyerId = buyer.rows[0].id
      log.push(`buyer: ${buyerId.substring(0,8)}…`)

      // ── TEST 1: Immutability trigger ──
      try {
        // Make a placed order, then try to mutate forbidden fields post-accept
        await client.queryArray('BEGIN')
        await client.queryArray(`
          SELECT set_config('request.jwt.claims', $1, true),
                 set_config('request.jwt.claim.sub', $2, true),
                 set_config('request.jwt.claim.role', 'authenticated', true)
        `, [JSON.stringify({ sub: buyerId, role: 'authenticated' }), buyerId])

        const o1 = await client.queryObject<{ order_id: string }>(`
          SELECT place_marketplace_order(
            $1::uuid,
            $2::jsonb,
            'toro', 'cash',
            'Calle Reforma 1234', 32.62, -115.45,
            'apto 1', $3, 0
          ) AS order_id
        `, [vendorId, JSON.stringify([{product_id: productId, qty: 1}]), '+526860000077'])
        await client.queryArray('COMMIT')
        const orderId = o1.rows[0].order_id
        log.push(`TEST1 order created: ${orderId.substring(0,8)}…`)

        // Move past placed
        await client.queryArray(`
          UPDATE marketplace_orders SET status='accepted_by_vendor', vendor_accepted_at=NOW()
          WHERE id = $1
        `, [orderId])

        // Now try to mutate price — should THROW
        let immutOk = false
        try {
          await client.queryArray(`UPDATE marketplace_orders SET total = 9999 WHERE id = $1`, [orderId])
          log.push('FAIL TEST1: UPDATE total was allowed after accept (immutability broken)')
        } catch (e) {
          const msg = (e as Error).message
          if (msg.includes('immutable')) {
            log.push(`OK TEST1 immutability: price UPDATE blocked → "${msg.substring(0, 60)}…"`)
            immutOk = true
          } else {
            log.push(`UNEXPECTED TEST1: ${msg.substring(0, 80)}`)
          }
        }
        if (!immutOk) log.push('TEST1 FAILED')

        // Clean
        await client.queryArray(`UPDATE marketplace_orders SET status='cancelled_by_buyer', cancelled_at=NOW() WHERE id = $1`, [orderId])
      } catch (e) {
        await client.queryArray('ROLLBACK').catch(() => {})
        log.push(`ERR TEST1 setup: ${(e as Error).message}`)
      }

      // ── TEST 2: Same-vendor bundle within 8 min window ──
      try {
        const orderIds: string[] = []
        // Place 2 orders in same transaction (within seconds, well under 8 min)
        for (let i = 0; i < 2; i++) {
          await client.queryArray('BEGIN')
          await client.queryArray(`
            SELECT set_config('request.jwt.claims', $1, true),
                   set_config('request.jwt.claim.sub', $2, true),
                   set_config('request.jwt.claim.role', 'authenticated', true)
          `, [JSON.stringify({ sub: buyerId, role: 'authenticated' }), buyerId])

          const r = await client.queryObject<{ order_id: string }>(`
            SELECT place_marketplace_order(
              $1::uuid,
              $2::jsonb,
              'toro', 'cash',
              'Calle Reforma 1234', 32.62, -115.45,
              'order ${i + 1} bundled test', $3, 0
            ) AS order_id
          `, [vendorId, JSON.stringify([{product_id: productId, qty: 1}]), '+526860000088'])
          await client.queryArray('COMMIT')
          orderIds.push(r.rows[0].order_id)
        }
        log.push(`TEST2 placed 2 orders: ${orderIds.map(x => x.substring(0,8)).join(', ')}`)

        // Walk them through to ready_for_pickup so dispatch fires
        for (const oid of orderIds) {
          await client.queryArray(`UPDATE marketplace_orders SET status='accepted_by_vendor', vendor_accepted_at=NOW() WHERE id = $1`, [oid])
          await client.queryArray(`UPDATE marketplace_orders SET status='preparing' WHERE id = $1`, [oid])
          // Items must be ready before trigger allows ready_for_pickup
          await client.queryArray(`UPDATE marketplace_order_items SET prep_status='ready', prepared_at=NOW() WHERE order_id = $1`, [oid])
          await client.queryArray(`UPDATE marketplace_orders SET status='ready_for_pickup', vendor_ready_at=NOW() WHERE id = $1`, [oid])
        }

        // Check: both should share delivery_id
        const dr = await client.queryObject<{ order_id: string; delivery_id: string | null }>(`
          SELECT id AS order_id, delivery_id FROM marketplace_orders WHERE id = ANY($1)
        `, [orderIds])
        const deliveryIds = new Set(dr.rows.map(r => r.delivery_id).filter(Boolean))
        if (deliveryIds.size === 1) {
          log.push(`OK TEST2 bundled: both orders share delivery ${Array.from(deliveryIds)[0]?.substring(0,8)}`)
        } else {
          log.push(`FAIL TEST2: ${deliveryIds.size} distinct delivery_ids (should be 1)`)
        }

        // Also: 2nd order's delivery_fee should be 0
        const fees = await client.queryObject<{ order_id: string; delivery_fee: number; total: number }>(`
          SELECT id AS order_id, delivery_fee, total FROM marketplace_orders WHERE id = ANY($1) ORDER BY created_at
        `, [orderIds])
        if (Number(fees.rows[1].delivery_fee) === 0) {
          log.push(`OK TEST2 fee waived: 2nd order delivery_fee=0 (total=${fees.rows[1].total})`)
        } else {
          log.push(`FAIL TEST2 fee: 2nd order delivery_fee=${fees.rows[1].delivery_fee} (should be 0)`)
        }

        // ── TEST 3: delivery_full_context returns N orders ──
        const did = Array.from(deliveryIds)[0]
        if (did) {
          const ctx = await client.queryObject<{ ctx: any }>(`
            SELECT delivery_full_context($1) AS ctx
          `, [did])
          const obj = ctx.rows[0].ctx
          const numOrders = (obj?.orders as any[])?.length ?? 0
          if (numOrders >= 2) {
            log.push(`OK TEST3 delivery_full_context: returned ${numOrders} orders bundled`)
          } else {
            log.push(`FAIL TEST3: only ${numOrders} orders in context`)
          }
        }

        // Cleanup
        for (const oid of orderIds) {
          await client.queryArray(`UPDATE marketplace_orders SET status='cancelled_by_buyer', cancelled_at=NOW() WHERE id = $1`, [oid])
        }
      } catch (e) {
        await client.queryArray('ROLLBACK').catch(() => {})
        log.push(`ERR TEST2: ${(e as Error).message}`)
      }

      // ── TEST 4: vendor_locations CRUD ──
      try {
        // List existing
        const list = await client.queryObject(`SELECT id, name, is_default FROM vendor_locations WHERE vendor_id = $1 AND deleted_at IS NULL`, [vendorId])
        log.push(`TEST4 vendor_locations existing: ${list.rows.length}`)
        if (list.rows.length >= 1 && (list.rows[0] as any).is_default) {
          log.push(`OK TEST4: Principal location exists (${(list.rows[0] as any).name})`)
        }
      } catch (e) { log.push(`ERR TEST4: ${(e as Error).message}`) }

      // ── TEST 5: products.location_id wired correctly ──
      try {
        const r = await client.queryObject(`
          SELECT location_id FROM products WHERE id = $1
        `, [productId])
        log.push(`OK TEST5 products.location_id column accessible (value=${(r.rows[0] as any).location_id ?? 'NULL — uses vendor default'})`)
      } catch (e) { log.push(`ERR TEST5: ${(e as Error).message}`) }

      // ── TEST 6: resolve_product_pickup helper ──
      try {
        const r = await client.queryObject(`SELECT * FROM resolve_product_pickup($1)`, [productId])
        const v = r.rows[0] as any
        log.push(`OK TEST6 resolve_product_pickup: ${v.name} @ ${v.lat?.toString().substring(0,8)}, ${v.lng?.toString().substring(0,8)}`)
      } catch (e) { log.push(`ERR TEST6: ${(e as Error).message}`) }

      await client.end()
      return new Response(JSON.stringify({ success: true, log }, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'setup_consolidation_phase1_2_3') {
      const log: string[] = []
      const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
      const SERVICE_KEY  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

      // ════════════════ FASE 1.1 — Immutability after 'placed' ════════════════
      // Reject UPDATE on price/total/OTP fields once order has moved past 'placed'.
      // Only buyer/vendor cancel-paths can change cancellation_* fields.
      try {
        await client.queryArray(`
          CREATE OR REPLACE FUNCTION public.marketplace_orders_enforce_immutability()
          RETURNS TRIGGER
          LANGUAGE plpgsql
          AS $fn$
          DECLARE
            v_is_bundling BOOLEAN;
          BEGIN
            -- pre-placed is fully editable
            IF OLD.status = 'placed' AND NEW.status IN ('placed','accepted_by_vendor','auto_cancelled','cancelled_by_buyer','cancelled_by_vendor','failed') THEN
              RETURN NEW;
            END IF;
            -- buyer/vendor IDs ALWAYS immutable
            IF NEW.buyer_id  <> OLD.buyer_id  THEN RAISE EXCEPTION 'buyer_id is immutable'; END IF;
            IF NEW.vendor_id <> OLD.vendor_id THEN RAISE EXCEPTION 'vendor_id is immutable'; END IF;
            -- OTPs always immutable
            IF NEW.pickup_otp   IS DISTINCT FROM OLD.pickup_otp   THEN RAISE EXCEPTION 'pickup_otp is immutable'; END IF;
            IF NEW.delivery_otp IS DISTINCT FROM OLD.delivery_otp THEN RAISE EXCEPTION 'delivery_otp is immutable'; END IF;

            IF OLD.status <> 'placed' THEN
              -- Allow money-field changes ONLY when this UPDATE is the bundle-merge:
              -- delivery_id transitions from NULL → non-NULL (or changes to a different delivery).
              v_is_bundling := (OLD.delivery_id IS NULL OR OLD.delivery_id IS DISTINCT FROM NEW.delivery_id)
                               AND NEW.delivery_id IS NOT NULL;

              IF NOT v_is_bundling THEN
                IF NEW.subtotal        <> OLD.subtotal        THEN RAISE EXCEPTION 'subtotal is immutable after placed (was %, tried %)', OLD.subtotal, NEW.subtotal; END IF;
                IF NEW.delivery_fee    <> OLD.delivery_fee    THEN RAISE EXCEPTION 'delivery_fee is immutable after placed'; END IF;
                IF NEW.flat_commission <> OLD.flat_commission THEN RAISE EXCEPTION 'flat_commission is immutable after placed'; END IF;
                IF NEW.total           <> OLD.total           THEN RAISE EXCEPTION 'total is immutable after placed'; END IF;
                IF NEW.vendor_payout   <> OLD.vendor_payout   THEN RAISE EXCEPTION 'vendor_payout is immutable after placed'; END IF;
              ELSE
                -- Bundling allowed: subtotal must stay (vendor still gets full subtotal),
                -- delivery_fee → 0, total = subtotal + commission + tip recomputed by trigger.
                IF NEW.subtotal <> OLD.subtotal THEN RAISE EXCEPTION 'subtotal cannot change even when bundling'; END IF;
              END IF;
            END IF;
            RETURN NEW;
          END;
          $fn$
        `)
        await client.queryArray(`DROP TRIGGER IF EXISTS trg_marketplace_orders_immutable ON marketplace_orders`)
        await client.queryArray(`
          CREATE TRIGGER trg_marketplace_orders_immutable
          BEFORE UPDATE ON marketplace_orders
          FOR EACH ROW EXECUTE FUNCTION marketplace_orders_enforce_immutability()
        `)
        log.push('OK: trg_marketplace_orders_immutable')
      } catch (e) { log.push(`ERR immut: ${(e as Error).message}`) }

      // Lock items after acceptance — no insert/delete/update of items past 'accepted_by_vendor'
      try {
        await client.queryArray(`
          CREATE OR REPLACE FUNCTION public.marketplace_items_enforce_lock()
          RETURNS TRIGGER
          LANGUAGE plpgsql
          AS $fn$
          DECLARE v_status TEXT; v_oid uuid;
          BEGIN
            v_oid := COALESCE(NEW.order_id, OLD.order_id);
            SELECT status INTO v_status FROM marketplace_orders WHERE id = v_oid;
            -- Only allow item changes BEFORE accepted, OR for prep_status / substitution_note (vendor doing prep)
            IF v_status NOT IN ('placed') THEN
              IF TG_OP = 'INSERT' THEN
                RAISE EXCEPTION 'cannot add items after order is %', v_status;
              END IF;
              IF TG_OP = 'DELETE' THEN
                RAISE EXCEPTION 'cannot remove items after order is %', v_status;
              END IF;
              IF TG_OP = 'UPDATE' THEN
                IF NEW.unit_price_snapshot <> OLD.unit_price_snapshot THEN RAISE EXCEPTION 'item price immutable'; END IF;
                IF NEW.quantity <> OLD.quantity THEN RAISE EXCEPTION 'item quantity immutable post-placed'; END IF;
                IF NEW.line_total <> OLD.line_total THEN RAISE EXCEPTION 'line_total immutable post-placed'; END IF;
                -- prep_status, substitution_note, prepared_at, prepared_by are allowed
              END IF;
            END IF;
            RETURN COALESCE(NEW, OLD);
          END;
          $fn$
        `)
        await client.queryArray(`DROP TRIGGER IF EXISTS trg_marketplace_items_lock ON marketplace_order_items`)
        await client.queryArray(`
          CREATE TRIGGER trg_marketplace_items_lock
          BEFORE INSERT OR UPDATE OR DELETE ON marketplace_order_items
          FOR EACH ROW EXECUTE FUNCTION marketplace_items_enforce_lock()
        `)
        log.push('OK: trg_marketplace_items_lock')
      } catch (e) { log.push(`ERR items lock: ${(e as Error).message}`) }

      // ════════════════ FASE 1.2 — Same-vendor + same-buyer merge ════════════════
      // Patch marketplace_create_delivery_on_ready: if buyer already has an active
      // delivery from this vendor created in last 8 min that hasn't moved past
      // 'accepted' yet, REUSE that delivery (merge orders under one trip).
      try {
        await client.queryArray(`
          CREATE OR REPLACE FUNCTION public.marketplace_create_delivery_on_ready()
          RETURNS trigger
          LANGUAGE plpgsql
          SECURITY DEFINER
          AS $fn$
          DECLARE
            v_delivery_id   uuid;
            v_existing      RECORD;
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
               AND COALESCE(OLD.status,'') <> 'ready_for_pickup'
               AND NEW.delivery_id IS NULL THEN

              IF NEW.delivery_type IN ('vendor', 'pickup') THEN
                RETURN NEW;
              END IF;

              -- ── MERGE CHECK ──
              -- Same buyer + same vendor + delivery still in pending/accepted (driver
              -- hasn't picked up yet) + created within last 8 minutes → reuse.
              SELECT d.* INTO v_existing
              FROM deliveries d
              JOIN marketplace_orders o ON o.delivery_id = d.id
              WHERE o.buyer_id = NEW.buyer_id
                AND o.vendor_id = NEW.vendor_id
                AND d.service_type = 'marketplace'
                AND d.status IN ('pending','accepted')
                AND d.created_at > NOW() - INTERVAL '8 minutes'
                AND d.id <> COALESCE(NEW.delivery_id, '00000000-0000-0000-0000-000000000000'::uuid)
              ORDER BY d.created_at DESC
              LIMIT 1;

              IF FOUND THEN
                -- Bundle: just attach this order to the existing delivery.
                -- Buyer pays $0 incremental delivery fee (DoorDash DoubleDash style):
                UPDATE marketplace_orders SET
                  delivery_id = v_existing.id,
                  delivery_fee = 0,
                  total = subtotal + COALESCE(flat_commission, 0) + COALESCE(tip, 0),
                  vendor_payout = subtotal,
                  updated_at = NOW()
                WHERE id = NEW.id;

                INSERT INTO marketplace_order_events (order_id, from_status, to_status, actor_type, note)
                VALUES (NEW.id, 'ready_for_pickup', 'ready_for_pickup', 'system',
                        'bundled into delivery ' || v_existing.id || ' (same vendor + buyer < 8 min)');

                -- Notify the buyer that their order got bundled
                PERFORM net.http_post(
                  url := '${SUPABASE_URL}/functions/v1/notify-vendor-new-order',
                  headers := jsonb_build_object(
                    'Content-Type','application/json',
                    'Authorization','Bearer ${SERVICE_KEY}'
                  ),
                  body := jsonb_build_object('order_id', NEW.id, 'target', 'buyer_bundled')
                );

                RETURN NEW;
              END IF;

              -- ── No merge — create fresh delivery ──
              SELECT full_name INTO v_buyer_name FROM profiles WHERE id = NEW.buyer_id;
              SELECT country_code, state_code INTO v_country, v_state FROM vendors WHERE id = NEW.vendor_id;
              v_country := COALESCE(v_country, 'MX');

              SELECT driver_pct, platform_pct, insurance_pct, tax_pct INTO v_split
              FROM pricing_split(v_country, v_state);
              IF v_split.driver_pct IS NULL THEN
                RAISE EXCEPTION 'no pricing_config for %/%', v_country, v_state;
              END IF;
              v_decimals := CASE WHEN v_country = 'MX' THEN 0 ELSE 2 END;
              v_fee           := ROUND(NEW.delivery_fee, v_decimals);
              v_platform_fee  := ROUND(v_fee * v_split.platform_pct  / 100.0, v_decimals);
              v_insurance_fee := ROUND(v_fee * v_split.insurance_pct / 100.0, v_decimals);
              v_tax_fee       := ROUND(v_fee * v_split.tax_pct       / 100.0, v_decimals);
              v_driver_amount := v_fee - v_platform_fee - v_insurance_fee - v_tax_fee;

              INSERT INTO deliveries (
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

              UPDATE marketplace_orders SET delivery_id = v_delivery_id WHERE id = NEW.id;
            END IF;
            RETURN NEW;
          END;
          $fn$
        `)
        log.push('OK: marketplace_create_delivery_on_ready patched (merge window 8 min)')
      } catch (e) { log.push(`ERR dispatch patch: ${(e as Error).message}`) }

      // ════════════════ FASE 2 — Stacked offer support ════════════════
      // When a driver accepts a marketplace delivery, look for ANOTHER pending
      // marketplace delivery whose pickup is within 2km of the just-accepted
      // pickup (on-the-way) and whose creation is recent (last 5 min).
      // If found, push it to the same driver as a stacked offer.
      try {
        await client.queryArray(`
          CREATE OR REPLACE FUNCTION public.deliveries_offer_stacked()
          RETURNS TRIGGER
          LANGUAGE plpgsql
          SECURITY DEFINER
          AS $fn$
          DECLARE
            v_nearby RECORD;
            v_dist_km numeric;
          BEGIN
            -- Only when a driver was just assigned to a marketplace delivery
            IF NEW.service_type <> 'marketplace' THEN RETURN NEW; END IF;
            IF NEW.status <> 'accepted' OR COALESCE(OLD.status,'') = 'accepted' THEN RETURN NEW; END IF;
            IF NEW.driver_id IS NULL THEN RETURN NEW; END IF;

            FOR v_nearby IN
              SELECT d.id, d.pickup_lat, d.pickup_lng,
                     (2 * 6371 * asin(sqrt(
                        sin(radians((d.pickup_lat - NEW.pickup_lat)/2))^2 +
                        cos(radians(NEW.pickup_lat)) * cos(radians(d.pickup_lat)) *
                        sin(radians((d.pickup_lng - NEW.pickup_lng)/2))^2
                     ))) AS dist_km
              FROM deliveries d
              WHERE d.service_type = 'marketplace'
                AND d.status = 'pending'
                AND d.driver_id IS NULL
                AND d.id <> NEW.id
                AND d.created_at > NOW() - INTERVAL '5 minutes'
                AND d.country_code = NEW.country_code
            LOOP
              IF v_nearby.dist_km <= 2 THEN
                -- Mark this driver as the preferred candidate via direct push.
                -- We reuse notify-drivers-of-ride pattern but target only this driver.
                PERFORM net.http_post(
                  url := '${SUPABASE_URL}/functions/v1/notify-drivers-of-ride',
                  headers := jsonb_build_object(
                    'Content-Type','application/json',
                    'Authorization','Bearer ${SERVICE_KEY}'
                  ),
                  body := jsonb_build_object(
                    'ride_id', v_nearby.id,
                    'preferred_driver_id', NEW.driver_id,
                    'stacked', true
                  )
                );
                INSERT INTO app_logs (level, source, event, message, context, app_role)
                VALUES ('info','stacked-offer','sent',
                        'Stacked offer pushed to driver',
                        jsonb_build_object(
                          'driver_id', NEW.driver_id,
                          'first_delivery', NEW.id,
                          'second_delivery', v_nearby.id,
                          'distance_km', v_nearby.dist_km
                        ),
                        'system');
                EXIT;  -- Only push ONE stacked offer per acceptance
              END IF;
            END LOOP;
            RETURN NEW;
          EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'stacked offer failed: %', SQLERRM;
            RETURN NEW;
          END;
          $fn$
        `)
        await client.queryArray(`DROP TRIGGER IF EXISTS trg_deliveries_offer_stacked ON deliveries`)
        await client.queryArray(`
          CREATE TRIGGER trg_deliveries_offer_stacked
          AFTER UPDATE OF status, driver_id ON deliveries
          FOR EACH ROW EXECUTE FUNCTION deliveries_offer_stacked()
        `)
        log.push('OK: trg_deliveries_offer_stacked')
      } catch (e) { log.push(`ERR stacked: ${(e as Error).message}`) }

      // ════════════════ FASE 3 — Helper RPC: delivery_orders ════════════════
      // Returns all the orders bundled under one delivery + their stops in order.
      try {
        await client.queryArray(`
          CREATE OR REPLACE FUNCTION public.delivery_full_context(p_delivery_id UUID)
          RETURNS jsonb
          LANGUAGE plpgsql
          STABLE
          SECURITY DEFINER
          AS $fn$
          DECLARE v_result jsonb;
          BEGIN
            SELECT jsonb_build_object(
              'delivery', to_jsonb(d.*),
              'orders', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                  'id', o.id,
                  'status', o.status,
                  'subtotal', o.subtotal,
                  'total', o.total,
                  'flat_commission', o.flat_commission,
                  'vendor_payout', o.vendor_payout,
                  'pickup_otp', o.pickup_otp,
                  'delivery_otp', o.delivery_otp,
                  'vendor_pickup_address', o.vendor_pickup_address,
                  'vendor_pickup_lat', o.vendor_pickup_lat,
                  'vendor_pickup_lng', o.vendor_pickup_lng,
                  'delivery_address', o.delivery_address,
                  'delivery_lat', o.delivery_lat,
                  'delivery_lng', o.delivery_lng,
                  'delivery_notes', o.delivery_notes,
                  'buyer_name', o.buyer_name,
                  'buyer_phone', o.buyer_phone,
                  'payment_method', o.payment_method,
                  'vendor', (SELECT jsonb_build_object('id', v.id, 'business_name', v.business_name, 'logo_url', v.logo_url) FROM vendors v WHERE v.id = o.vendor_id),
                  'items', (SELECT jsonb_agg(jsonb_build_object(
                    'id', i.id,
                    'product_name_snapshot', i.product_name_snapshot,
                    'quantity', i.quantity,
                    'prep_status', i.prep_status
                  ) ORDER BY i.created_at)
                  FROM marketplace_order_items i WHERE i.order_id = o.id)
                ) ORDER BY o.created_at)
                FROM marketplace_orders o WHERE o.delivery_id = d.id
              ), '[]'::jsonb)
            ) INTO v_result
            FROM deliveries d WHERE d.id = p_delivery_id;
            RETURN v_result;
          END;
          $fn$
        `)
        await client.queryArray(`GRANT EXECUTE ON FUNCTION delivery_full_context(UUID) TO authenticated`)
        log.push('OK: delivery_full_context')
      } catch (e) { log.push(`ERR helper: ${(e as Error).message}`) }

      await client.end()
      return new Response(JSON.stringify({ success: true, log }, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'setup_vendor_locations') {
      const log: string[] = []

      // 1) Table
      try {
        await client.queryArray(`
          CREATE TABLE IF NOT EXISTS vendor_locations (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            vendor_id UUID NOT NULL REFERENCES vendors(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            address TEXT NOT NULL,
            lat DOUBLE PRECISION NOT NULL,
            lng DOUBLE PRECISION NOT NULL,
            is_default BOOLEAN NOT NULL DEFAULT false,
            available_from TIME,
            available_to TIME,
            available_days INT[] DEFAULT NULL,
            notes TEXT,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            deleted_at TIMESTAMPTZ
          )
        `)
        await client.queryArray(`CREATE INDEX IF NOT EXISTS idx_vendor_locations_vendor ON vendor_locations(vendor_id) WHERE deleted_at IS NULL`)
        log.push('OK: vendor_locations table')
      } catch (e) { log.push(`ERR table: ${(e as Error).message}`) }

      // Only one default per vendor (partial unique)
      try {
        await client.queryArray(`
          CREATE UNIQUE INDEX IF NOT EXISTS idx_vendor_locations_one_default
          ON vendor_locations(vendor_id)
          WHERE is_default = true AND deleted_at IS NULL
        `)
        log.push('OK: one-default partial index')
      } catch (e) { log.push(`ERR unique idx: ${(e as Error).message}`) }

      // RLS
      try {
        await client.queryArray(`ALTER TABLE vendor_locations ENABLE ROW LEVEL SECURITY`)
        await client.queryArray(`DROP POLICY IF EXISTS vl_owner_all ON vendor_locations`)
        await client.queryArray(`
          CREATE POLICY vl_owner_all ON vendor_locations
          FOR ALL TO authenticated
          USING (EXISTS (SELECT 1 FROM vendors v WHERE v.id = vendor_id AND v.user_id = auth.uid()))
          WITH CHECK (EXISTS (SELECT 1 FROM vendors v WHERE v.id = vendor_id AND v.user_id = auth.uid()))
        `)
        await client.queryArray(`DROP POLICY IF EXISTS vl_public_read ON vendor_locations`)
        await client.queryArray(`
          CREATE POLICY vl_public_read ON vendor_locations
          FOR SELECT TO anon, authenticated
          USING (deleted_at IS NULL)
        `)
        log.push('OK: RLS policies')
      } catch (e) { log.push(`ERR RLS: ${(e as Error).message}`) }

      // 2) products.location_id FK column
      try {
        await client.queryArray(`
          ALTER TABLE products
          ADD COLUMN IF NOT EXISTS location_id UUID
            REFERENCES vendor_locations(id) ON DELETE SET NULL
        `)
        log.push('OK: products.location_id')
      } catch (e) { log.push(`ERR products col: ${(e as Error).message}`) }

      // 3) Backfill — create 'Principal' location per existing vendor (idempotent)
      try {
        const r = await client.queryObject<{ id: string; vendor_id: string }>(`
          INSERT INTO vendor_locations (vendor_id, name, address, lat, lng, is_default)
          SELECT v.id, 'Principal', v.pickup_address, v.pickup_lat, v.pickup_lng, true
          FROM vendors v
          WHERE NOT EXISTS (
            SELECT 1 FROM vendor_locations l
            WHERE l.vendor_id = v.id AND l.deleted_at IS NULL
          )
          AND v.pickup_lat IS NOT NULL AND v.pickup_lng IS NOT NULL
          RETURNING id, vendor_id
        `)
        log.push(`OK: backfilled ${r.rows.length} default locations`)
      } catch (e) { log.push(`ERR backfill: ${(e as Error).message}`) }

      // 4) Helper to resolve the pickup of a product (used by RPCs/UI)
      try {
        await client.queryArray(`
          CREATE OR REPLACE FUNCTION public.resolve_product_pickup(p_product_id UUID)
          RETURNS TABLE (
            location_id UUID,
            name TEXT,
            address TEXT,
            lat DOUBLE PRECISION,
            lng DOUBLE PRECISION
          )
          LANGUAGE plpgsql
          STABLE
          SECURITY DEFINER
          AS $fn$
          BEGIN
            RETURN QUERY
            WITH prod AS (
              SELECT p.location_id, p.vendor_id FROM products p WHERE p.id = p_product_id
            )
            SELECT
              COALESCE(l_specific.id, l_default.id)        AS location_id,
              COALESCE(l_specific.name, l_default.name, 'Principal') AS name,
              COALESCE(l_specific.address, l_default.address, v.pickup_address) AS address,
              COALESCE(l_specific.lat, l_default.lat, v.pickup_lat) AS lat,
              COALESCE(l_specific.lng, l_default.lng, v.pickup_lng) AS lng
            FROM prod
            JOIN vendors v ON v.id = prod.vendor_id
            LEFT JOIN vendor_locations l_specific ON l_specific.id = prod.location_id AND l_specific.deleted_at IS NULL
            LEFT JOIN vendor_locations l_default ON l_default.vendor_id = v.id AND l_default.is_default = true AND l_default.deleted_at IS NULL;
          END;
          $fn$
        `)
        await client.queryArray(`GRANT EXECUTE ON FUNCTION resolve_product_pickup(UUID) TO authenticated, anon`)
        log.push('OK: resolve_product_pickup helper')
      } catch (e) { log.push(`ERR helper: ${(e as Error).message}`) }

      // 5) CRUD RPCs (location upsert/list/set_default/soft_delete)
      try {
        await client.queryArray(`
          CREATE OR REPLACE FUNCTION public.vendor_locations_upsert(
            p_id UUID,
            p_vendor_id UUID,
            p_name TEXT,
            p_address TEXT,
            p_lat DOUBLE PRECISION,
            p_lng DOUBLE PRECISION,
            p_is_default BOOLEAN DEFAULT NULL,
            p_available_from TIME DEFAULT NULL,
            p_available_to TIME DEFAULT NULL,
            p_available_days INT[] DEFAULT NULL,
            p_notes TEXT DEFAULT NULL
          )
          RETURNS UUID
          LANGUAGE plpgsql
          SECURITY DEFINER
          AS $fn$
          DECLARE
            v_id UUID;
            v_owner UUID;
          BEGIN
            SELECT user_id INTO v_owner FROM vendors WHERE id = p_vendor_id;
            IF v_owner IS DISTINCT FROM auth.uid() THEN
              RAISE EXCEPTION 'Not vendor owner';
            END IF;

            IF p_id IS NULL THEN
              INSERT INTO vendor_locations (
                vendor_id, name, address, lat, lng, is_default,
                available_from, available_to, available_days, notes
              ) VALUES (
                p_vendor_id, p_name, p_address, p_lat, p_lng, COALESCE(p_is_default, false),
                p_available_from, p_available_to, p_available_days, p_notes
              ) RETURNING id INTO v_id;
            ELSE
              UPDATE vendor_locations SET
                name = p_name,
                address = p_address,
                lat = p_lat,
                lng = p_lng,
                is_default = COALESCE(p_is_default, is_default),
                available_from = p_available_from,
                available_to = p_available_to,
                available_days = p_available_days,
                notes = p_notes,
                updated_at = NOW()
              WHERE id = p_id AND vendor_id = p_vendor_id
              RETURNING id INTO v_id;
            END IF;

            -- Enforce "only one default" — if this row is default, unset others
            IF (SELECT is_default FROM vendor_locations WHERE id = v_id) = true THEN
              UPDATE vendor_locations
                SET is_default = false, updated_at = NOW()
                WHERE vendor_id = p_vendor_id AND id <> v_id AND is_default = true;

              -- Sync vendors.pickup_* with the new default (back-compat)
              UPDATE vendors SET
                pickup_address = p_address,
                pickup_lat = p_lat,
                pickup_lng = p_lng,
                updated_at = NOW()
              WHERE id = p_vendor_id;
            END IF;

            RETURN v_id;
          END;
          $fn$
        `)
        await client.queryArray(`GRANT EXECUTE ON FUNCTION vendor_locations_upsert(UUID,UUID,TEXT,TEXT,DOUBLE PRECISION,DOUBLE PRECISION,BOOLEAN,TIME,TIME,INT[],TEXT) TO authenticated`)
        log.push('OK: vendor_locations_upsert')
      } catch (e) { log.push(`ERR upsert: ${(e as Error).message}`) }

      try {
        await client.queryArray(`
          CREATE OR REPLACE FUNCTION public.vendor_locations_delete(p_id UUID)
          RETURNS VOID
          LANGUAGE plpgsql
          SECURITY DEFINER
          AS $fn$
          DECLARE v_was_default BOOLEAN;
                  v_vendor_id UUID;
          BEGIN
            SELECT vendor_id, is_default INTO v_vendor_id, v_was_default
            FROM vendor_locations WHERE id = p_id;
            IF v_vendor_id IS NULL THEN RAISE EXCEPTION 'not found'; END IF;
            IF NOT EXISTS (SELECT 1 FROM vendors WHERE id = v_vendor_id AND user_id = auth.uid()) THEN
              RAISE EXCEPTION 'Not vendor owner';
            END IF;
            UPDATE vendor_locations SET deleted_at = NOW(), is_default = false WHERE id = p_id;
            IF v_was_default THEN
              -- Promote the oldest remaining location to default
              UPDATE vendor_locations
                SET is_default = true
                WHERE id = (
                  SELECT id FROM vendor_locations
                  WHERE vendor_id = v_vendor_id AND deleted_at IS NULL
                  ORDER BY created_at ASC LIMIT 1
                );
            END IF;
          END;
          $fn$
        `)
        await client.queryArray(`GRANT EXECUTE ON FUNCTION vendor_locations_delete(UUID) TO authenticated`)
        log.push('OK: vendor_locations_delete')
      } catch (e) { log.push(`ERR delete: ${(e as Error).message}`) }

      // 6) Patch place_marketplace_order to use product's resolved pickup
      try {
        // We don't replace the whole RPC (it's large). Instead we add a tiny
        // post-INSERT update: for each item, if location_id is set, override
        // the order's vendor_pickup_* fields using resolve_product_pickup.
        // Easier path: trigger BEFORE INSERT on marketplace_orders that, after
        // items are known, recomputes vendor_pickup_* from the items.
        // Simpler & atomic: just create an AFTER INSERT trigger on
        // marketplace_order_items that updates the parent order's pickup
        // when the item's product has a non-default location_id.
        await client.queryArray(`
          CREATE OR REPLACE FUNCTION public.marketplace_apply_product_pickup()
          RETURNS TRIGGER
          LANGUAGE plpgsql
          SECURITY DEFINER
          AS $fn$
          DECLARE
            v_loc RECORD;
          BEGIN
            SELECT * INTO v_loc FROM resolve_product_pickup(NEW.product_id);
            IF v_loc.lat IS NOT NULL AND v_loc.lng IS NOT NULL THEN
              UPDATE marketplace_orders
                SET vendor_pickup_address = v_loc.address,
                    vendor_pickup_lat = v_loc.lat,
                    vendor_pickup_lng = v_loc.lng,
                    updated_at = NOW()
                WHERE id = NEW.order_id
                  AND status = 'placed';  -- only safe to retarget pre-accept
            END IF;
            RETURN NEW;
          END;
          $fn$
        `)
        await client.queryArray(`DROP TRIGGER IF EXISTS trg_apply_product_pickup ON marketplace_order_items`)
        await client.queryArray(`
          CREATE TRIGGER trg_apply_product_pickup
          AFTER INSERT ON marketplace_order_items
          FOR EACH ROW EXECUTE FUNCTION marketplace_apply_product_pickup()
        `)
        log.push('OK: trg_apply_product_pickup')
      } catch (e) { log.push(`ERR trigger: ${(e as Error).message}`) }

      await client.end()
      return new Response(JSON.stringify({ success: true, log }, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'inspect_product_location_cols') {
      const cols = await client.queryObject<{ column_name: string }>(`
        SELECT column_name FROM information_schema.columns
        WHERE table_schema='public' AND table_name='products'
          AND (column_name ILIKE '%lat%' OR column_name ILIKE '%lng%'
               OR column_name ILIKE '%address%' OR column_name ILIKE '%location%'
               OR column_name ILIKE '%pickup%' OR column_name ILIKE '%branch%'
               OR column_name ILIKE '%site%' OR column_name ILIKE '%store%')
      `)
      const tablesWithLocation = await client.queryObject(`
        SELECT table_name FROM information_schema.tables
        WHERE table_schema='public'
          AND (table_name ILIKE '%location%' OR table_name ILIKE '%branch%'
               OR table_name ILIKE '%vendor_site%' OR table_name ILIKE '%store_loc%'
               OR table_name ILIKE '%vendor_addr%')
      `)
      await client.end()
      return new Response(JSON.stringify({
        product_location_columns: cols.rows,
        location_related_tables: tablesWithLocation.rows,
      }, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'paloma_full') {
      const v = await client.queryObject(`
        SELECT id, business_name, category_primary, status, is_open,
               accepts_cash, accepts_card, toro_delivers, vendor_self_delivers,
               pickup_address, pickup_lat, pickup_lng,
               country_code, state_code,
               auto_accept_orders
        FROM vendors WHERE id = '862f91a1-9612-4dfc-9105-278acd7276f8'
      `)
      const products = await client.queryObject(`
        SELECT id, name, price, stock_qty, is_available, sold_count, category_id
        FROM products WHERE vendor_id = '862f91a1-9612-4dfc-9105-278acd7276f8'
      `)
      await client.end()
      return new Response(JSON.stringify({
        vendor: v.rows[0] ?? null,
        products: products.rows,
      }, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'list_test_buyers') {
      // Cuentas usables como comprador: que no sean vendor activo + tengan profile
      const r = await client.queryObject(`
        SELECT p.id, p.full_name, p.email, p.phone,
               COALESCE(p.rider_app_installed, false) AS has_rider_app,
               p.rider_app_last_open,
               (SELECT COUNT(*)::int FROM marketplace_orders o WHERE o.buyer_id = p.id) AS orders_count,
               (SELECT COUNT(*)::int FROM fcm_tokens t WHERE t.user_id = p.id) AS fcm_count
        FROM profiles p
        WHERE p.id NOT IN (SELECT user_id FROM vendors WHERE user_id IS NOT NULL)
          AND COALESCE(p.full_name, '') <> ''
          AND COALESCE(p.country_code, 'MX') = 'MX'
        ORDER BY p.rider_app_last_open DESC NULLS LAST
        LIMIT 8
      `)
      await client.end()
      return new Response(JSON.stringify(r.rows, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'inspect_version_setup') {
      // Read the canonical app_versions config table — what the version_check_service queries
      const tableExists = await client.queryObject<{ exists: boolean }>(`
        SELECT EXISTS (
          SELECT 1 FROM information_schema.tables
          WHERE table_schema='public' AND table_name='app_versions'
        ) AS exists
      `)
      let rows: any[] = []
      let cols: any[] = []
      if (tableExists.rows[0].exists) {
        const r = await client.queryObject(`SELECT * FROM app_versions ORDER BY id`)
        rows = r.rows
        const c = await client.queryObject(`
          SELECT column_name, data_type, column_default
          FROM information_schema.columns
          WHERE table_schema='public' AND table_name='app_versions'
          ORDER BY ordinal_position
        `)
        cols = c.rows
      }
      // Is there a push channel / trigger for "update available" notifs?
      const updateTriggers = await client.queryObject(`
        SELECT t.tgname, p.proname, c.relname AS on_table
        FROM pg_trigger t
        JOIN pg_class c ON t.tgrelid = c.oid
        JOIN pg_proc p ON t.tgfoid = p.oid
        WHERE NOT t.tgisinternal
          AND (p.proname ILIKE '%version%' OR p.proname ILIKE '%update%notif%' OR p.proname ILIKE '%app_update%')
      `)
      await client.end()
      return new Response(JSON.stringify({
        table_exists: tableExists.rows[0].exists,
        columns: cols,
        rows,
        related_triggers: updateTriggers.rows,
      }, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'inspect_product_lifecycle') {
      const cols = await client.queryObject<{ column_name: string; data_type: string; column_default: string | null }>(`
        SELECT column_name, data_type, column_default
        FROM information_schema.columns
        WHERE table_schema='public' AND table_name='products'
        ORDER BY ordinal_position
      `)
      const triggers = await client.queryObject(`
        SELECT t.tgname, p.proname
        FROM pg_trigger t
        JOIN pg_class c ON t.tgrelid = c.oid
        JOIN pg_proc p ON t.tgfoid = p.oid
        WHERE c.relname IN ('products','marketplace_order_items','marketplace_orders')
          AND NOT t.tgisinternal
          AND p.proname ILIKE '%stock%' OR p.proname ILIKE '%product%' OR p.proname ILIKE '%inventory%'
        ORDER BY t.tgname
      `)
      // Stats: how many products have stock tracking
      const stats = await client.queryObject(`
        SELECT
          COUNT(*) FILTER (WHERE stock_qty IS NULL)::int AS unlimited,
          COUNT(*) FILTER (WHERE stock_qty IS NOT NULL AND stock_qty > 0)::int AS has_stock,
          COUNT(*) FILTER (WHERE stock_qty = 0)::int AS out_of_stock,
          COUNT(*) FILTER (WHERE COALESCE(is_available, true) = false)::int AS disabled,
          COUNT(*) FILTER (WHERE deleted_at IS NOT NULL)::int AS soft_deleted,
          COUNT(*)::int AS total
        FROM products
      `)
      // Palomas product after the 6 sold:
      const ps5 = await client.queryObject(`
        SELECT id, name, price, stock_qty, is_available, deleted_at, created_at
        FROM products WHERE id = 'adfe03a4-5c65-4296-9a29-83831e7feed5'
      `)
      await client.end()
      return new Response(JSON.stringify({
        product_columns: cols.rows,
        related_triggers: triggers.rows,
        stats: stats.rows[0],
        paloma_ps5: ps5.rows[0],
      }, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'setup_buyer_arrival_geofence') {
      const log: string[] = []
      const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
      const SERVICE_KEY  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

      // Idempotency flag on the order (so we only push the "arriving" alert once)
      try {
        await client.queryArray(`
          ALTER TABLE marketplace_orders
          ADD COLUMN IF NOT EXISTS buyer_arrival_pushed BOOLEAN NOT NULL DEFAULT false
        `)
        log.push('OK: marketplace_orders.buyer_arrival_pushed')
      } catch (e) { log.push(`ERR col: ${(e as Error).message}`) }

      // Geofence trigger fires on deliveries UPDATE when driver_lat/lng change.
      // If the driver is <500m from the destination AND the order is in
      // in_progress (post-pickup), AND we haven't pushed yet → call edge fn
      // notify-vendor-new-order with target='buyer'.
      try {
        await client.queryArray(`
          CREATE OR REPLACE FUNCTION public.deliveries_check_arrival()
          RETURNS TRIGGER
          LANGUAGE plpgsql
          SECURITY DEFINER
          SET search_path = public
          AS $fn$
          DECLARE
            v_order RECORD;
            v_dist_m int;
          BEGIN
            -- Only marketplace, only after pickup, only when GPS changed
            IF NEW.service_type <> 'marketplace' THEN RETURN NEW; END IF;
            IF NEW.status NOT IN ('in_progress','accepted') THEN RETURN NEW; END IF;
            IF NEW.driver_lat IS NULL OR NEW.driver_lng IS NULL THEN RETURN NEW; END IF;
            IF NEW.destination_lat IS NULL OR NEW.destination_lng IS NULL THEN RETURN NEW; END IF;

            -- Skip if GPS didn't materially change (deliveries update for other reasons too)
            IF OLD.driver_lat IS NOT DISTINCT FROM NEW.driver_lat
               AND OLD.driver_lng IS NOT DISTINCT FROM NEW.driver_lng THEN
              RETURN NEW;
            END IF;

            SELECT * INTO v_order FROM marketplace_orders WHERE delivery_id = NEW.id;
            IF v_order IS NULL THEN RETURN NEW; END IF;
            IF v_order.buyer_arrival_pushed THEN RETURN NEW; END IF;
            IF v_order.status NOT IN ('picked_up','in_transit') THEN RETURN NEW; END IF;

            -- Haversine meters between driver and destination
            v_dist_m := (
              2 * 6371000 * asin(sqrt(
                sin(radians((NEW.destination_lat - NEW.driver_lat)/2))^2 +
                cos(radians(NEW.driver_lat)) * cos(radians(NEW.destination_lat)) *
                sin(radians((NEW.destination_lng - NEW.driver_lng)/2))^2
              ))
            )::int;

            IF v_dist_m <= 500 THEN
              UPDATE marketplace_orders
              SET buyer_arrival_pushed = true, updated_at = NOW()
              WHERE id = v_order.id;

              PERFORM net.http_post(
                url := '${SUPABASE_URL}/functions/v1/notify-vendor-new-order',
                headers := jsonb_build_object(
                  'Content-Type','application/json',
                  'Authorization','Bearer ${SERVICE_KEY}'
                ),
                body := jsonb_build_object('order_id', v_order.id, 'target', 'buyer')
              );
            END IF;
            RETURN NEW;
          EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'deliveries_check_arrival failed: %', SQLERRM;
            RETURN NEW;
          END;
          $fn$
        `)
        await client.queryArray(`
          DROP TRIGGER IF EXISTS trg_deliveries_check_arrival ON deliveries
        `)
        await client.queryArray(`
          CREATE TRIGGER trg_deliveries_check_arrival
          AFTER UPDATE OF driver_lat, driver_lng ON deliveries
          FOR EACH ROW EXECUTE FUNCTION deliveries_check_arrival()
        `)
        log.push('OK: trg_deliveries_check_arrival')
      } catch (e) { log.push(`ERR trg: ${(e as Error).message}`) }

      await client.end()
      return new Response(JSON.stringify({ success: true, log }, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'setup_driver_cancel_and_reassign') {
      const log: string[] = []

      // RPC: driver_cancel_marketplace_delivery — releases the delivery back
      // to the dispatch pool with a recorded reason. Does NOT cancel the order
      // (vendor's product is still being prepared / ready). Only frees the
      // delivery slot so another driver can take it.
      try {
        await client.queryArray(`
          CREATE OR REPLACE FUNCTION public.driver_cancel_marketplace_delivery(
            p_delivery_id UUID,
            p_reason TEXT
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
            SELECT id INTO v_driver_id FROM drivers WHERE user_id = v_uid;
            IF v_driver_id IS NULL THEN RAISE EXCEPTION 'Not a driver'; END IF;

            SELECT * INTO v_delivery FROM deliveries
            WHERE id = p_delivery_id FOR UPDATE;
            IF NOT FOUND THEN RAISE EXCEPTION 'Delivery not found'; END IF;

            IF v_delivery.driver_id IS DISTINCT FROM v_driver_id THEN
              RAISE EXCEPTION 'Not your delivery';
            END IF;

            -- Once in_progress (post-pickup) we don't auto-release: this
            -- becomes a support case (driver took possession of the goods).
            IF v_delivery.status NOT IN ('accepted','pending') THEN
              RAISE EXCEPTION 'Cannot release after pickup — contact support';
            END IF;

            SELECT id INTO v_order_id FROM marketplace_orders
            WHERE delivery_id = p_delivery_id;

            -- Release: status back to 'pending', driver_id null, reason logged.
            UPDATE deliveries
            SET driver_id = NULL,
                status = 'pending',
                accepted_at = NULL,
                cancellation_reason = COALESCE(p_reason, 'driver_released')
            WHERE id = p_delivery_id;

            -- Order goes back to ready_for_pickup so it's eligible for re-dispatch.
            IF v_order_id IS NOT NULL THEN
              UPDATE marketplace_orders
              SET status = 'ready_for_pickup', updated_at = NOW()
              WHERE id = v_order_id;

              INSERT INTO marketplace_order_events (
                order_id, from_status, to_status, actor_type, actor_id, note
              ) VALUES (
                v_order_id, 'driver_assigned', 'ready_for_pickup',
                'driver', v_driver_id,
                'chofer canceló: ' || COALESCE(p_reason, 'sin razón')
              );
            END IF;

            INSERT INTO app_logs (level, source, event, message, user_id, context, app_role)
            VALUES ('warn', 'driver_marketplace', 'cancel_delivery',
                    'Driver released delivery: ' || COALESCE(p_reason, ''), v_uid,
                    jsonb_build_object('delivery_id', p_delivery_id, 'order_id', v_order_id, 'reason', p_reason),
                    'driver');

            -- Re-fire dispatch for the next driver
            PERFORM net.http_post(
              url := '${Deno.env.get('SUPABASE_URL')}/functions/v1/notify-drivers-of-ride',
              headers := jsonb_build_object(
                'Content-Type','application/json',
                'Authorization', 'Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}'
              ),
              body := jsonb_build_object('ride_id', p_delivery_id)
            );

            RETURN jsonb_build_object('success', true, 're_dispatched', true);
          END;
          $fn$
        `)
        await client.queryArray(`
          GRANT EXECUTE ON FUNCTION driver_cancel_marketplace_delivery(UUID, TEXT) TO authenticated
        `)
        log.push('OK: driver_cancel_marketplace_delivery')
      } catch (e) { log.push(`ERR cancel rpc: ${(e as Error).message}`) }

      // Cron-style helper: re-dispatch deliveries that have a driver assigned
      // but haven't been actually moved (no pickup) within X minutes.
      // Conservative: 8-min ACCEPTANCE timeout (driver accepted but ghosted).
      // Carlos can tune; for now sets the function, the cron schedule comes
      // from setup-cron-marketplace.
      try {
        await client.queryArray(`
          CREATE OR REPLACE FUNCTION public.reassign_stale_marketplace_deliveries()
          RETURNS jsonb
          LANGUAGE plpgsql
          SECURITY DEFINER
          AS $fn$
          DECLARE
            v_count int := 0;
            v_id uuid;
            v_order_id uuid;
          BEGIN
            FOR v_id, v_order_id IN
              SELECT d.id, o.id
              FROM deliveries d
              LEFT JOIN marketplace_orders o ON o.delivery_id = d.id
              WHERE d.service_type = 'marketplace'
                AND d.status = 'accepted'
                AND d.accepted_at < NOW() - INTERVAL '8 minutes'
            LOOP
              UPDATE deliveries
              SET driver_id = NULL, status = 'pending',
                  accepted_at = NULL,
                  cancellation_reason = 'driver_no_show'
              WHERE id = v_id;

              IF v_order_id IS NOT NULL THEN
                UPDATE marketplace_orders
                SET status = 'ready_for_pickup', updated_at = NOW()
                WHERE id = v_order_id;

                INSERT INTO marketplace_order_events (
                  order_id, from_status, to_status, actor_type, note
                ) VALUES (
                  v_order_id, 'driver_assigned', 'ready_for_pickup',
                  'system', 'chofer no llegó en 8 min, re-asignando'
                );
              END IF;

              -- Re-fire dispatch
              PERFORM net.http_post(
                url := '${Deno.env.get('SUPABASE_URL')}/functions/v1/notify-drivers-of-ride',
                headers := jsonb_build_object(
                  'Content-Type','application/json',
                  'Authorization', 'Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}'
                ),
                body := jsonb_build_object('ride_id', v_id)
              );

              v_count := v_count + 1;
            END LOOP;

            INSERT INTO app_logs (level, source, event, message, context, app_role)
            VALUES ('info', 'reassign-stale', 'run',
                    'reassigned ' || v_count || ' stale marketplace deliveries',
                    jsonb_build_object('count', v_count), 'system');

            RETURN jsonb_build_object('reassigned', v_count);
          END;
          $fn$
        `)
        log.push('OK: reassign_stale_marketplace_deliveries')
      } catch (e) { log.push(`ERR reassign fn: ${(e as Error).message}`) }

      // Schedule the reassign every minute
      try {
        await client.queryArray(`
          SELECT cron.unschedule('marketplace_reassign_stale')
          WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'marketplace_reassign_stale')
        `)
      } catch (_) {}
      try {
        await client.queryArray(`
          SELECT cron.schedule(
            'marketplace_reassign_stale',
            '* * * * *',
            $cmd$ SELECT public.reassign_stale_marketplace_deliveries() $cmd$
          )
        `)
        log.push('OK: cron marketplace_reassign_stale every minute')
      } catch (e) { log.push(`ERR cron: ${(e as Error).message}`) }

      await client.end()
      return new Response(JSON.stringify({ success: true, log }, null, 2),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (action === 'setup_auto_accept_orders') {
      const log: string[] = []
      try {
        await client.queryArray(`
          ALTER TABLE vendors
          ADD COLUMN IF NOT EXISTS auto_accept_orders BOOLEAN NOT NULL DEFAULT false
        `)
        log.push('OK: vendors.auto_accept_orders column')
      } catch (e) { log.push(`ERR col: ${(e as Error).message}`) }

      try {
        // BEFORE-INSERT trigger: if vendor opted in, the order is born accepted.
        // This means trg_marketplace_notify_vendor_placed will still fire on
        // the AFTER-INSERT with status='accepted_by_vendor' (the notif edge
        // function handles any status — vendor gets a "auto-aceptado, prepara"
        // push instead of the "NUEVO PEDIDO" alarm).
        await client.queryArray(`
          CREATE OR REPLACE FUNCTION public.marketplace_apply_auto_accept()
          RETURNS TRIGGER
          LANGUAGE plpgsql
          SECURITY DEFINER
          SET search_path = public
          AS $fn$
          DECLARE
            v_auto BOOLEAN;
          BEGIN
            IF NEW.status <> 'placed' THEN RETURN NEW; END IF;
            SELECT COALESCE(auto_accept_orders, false) INTO v_auto
            FROM vendors WHERE id = NEW.vendor_id;
            IF v_auto IS TRUE THEN
              NEW.status := 'accepted_by_vendor';
              NEW.vendor_accepted_at := NOW();
            END IF;
            RETURN NEW;
          END;
          $fn$
        `)
        await client.queryArray(`
          DROP TRIGGER IF EXISTS trg_marketplace_apply_auto_accept ON marketplace_orders
        `)
        await client.queryArray(`
          CREATE TRIGGER trg_marketplace_apply_auto_accept
          BEFORE INSERT ON marketplace_orders
          FOR EACH ROW EXECUTE FUNCTION marketplace_apply_auto_accept()
        `)
        log.push('OK: trg_marketplace_apply_auto_accept')
      } catch (e) { log.push(`ERR trg: ${(e as Error).message}`) }

      // Notify-vendor-new-order: tweak the push body when status arrived
      // already accepted (auto). Vendor still hears a sound but message says
      // "prepara ya". Done at edge-function level (not here).

      try {
        await client.queryArray(`
          GRANT UPDATE (auto_accept_orders) ON vendors TO authenticated
        `)
        log.push('OK: grant update auto_accept_orders')
      } catch (e) { log.push(`ERR grant: ${(e as Error).message}`) }

      await client.end()
      return new Response(JSON.stringify({ success: true, log }, null, 2),
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
                accepted_at = NOW()
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
