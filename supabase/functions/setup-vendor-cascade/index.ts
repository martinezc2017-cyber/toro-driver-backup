// Edge Function: setup-vendor-cascade
// Creates the schema needed for the vendor sales cascade:
//   - vendor_responded_in_ms column on marketplace_orders
//   - vendor_pause_state table
//   - vendor_app_sessions table
//   - vendor_sales_cascade(...) RPC
//   - vendor_pause / vendor_resume RPCs
//   - vendor_log_session_open / vendor_log_session_close RPCs
//   - Trigger to compute vendor_responded_in_ms automatically

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const dbUrl = Deno.env.get('SUPABASE_DB_URL')!
    const { Client } = await import("https://deno.land/x/postgres@v0.17.0/mod.ts")
    const client = new Client(dbUrl)
    await client.connect()
    const log: string[] = []

    // ───────────────────── 1) COLUMN ─────────────────────
    try {
      await client.queryArray(`
        ALTER TABLE marketplace_orders
        ADD COLUMN IF NOT EXISTS vendor_responded_in_ms INT
      `)
      log.push('OK: marketplace_orders.vendor_responded_in_ms')
    } catch (e) { log.push(`ERR col: ${(e as Error).message}`) }

    // ───────────────────── 2) vendor_pause_state ─────────────────────
    try {
      await client.queryArray(`
        CREATE TABLE IF NOT EXISTS vendor_pause_state (
          vendor_id UUID PRIMARY KEY REFERENCES vendors(id) ON DELETE CASCADE,
          paused_until TIMESTAMPTZ,
          reason TEXT,
          paused_at TIMESTAMPTZ DEFAULT NOW()
        )
      `)
      await client.queryArray(`ALTER TABLE vendor_pause_state ENABLE ROW LEVEL SECURITY`)
      await client.queryArray(`DROP POLICY IF EXISTS vps_vendor_reads ON vendor_pause_state`)
      await client.queryArray(`
        CREATE POLICY vps_vendor_reads ON vendor_pause_state FOR SELECT
        USING (
          EXISTS (SELECT 1 FROM vendors v WHERE v.id = vendor_pause_state.vendor_id AND v.user_id = auth.uid())
          OR auth.jwt() ->> 'role' = 'service_role'
        )
      `)
      log.push('OK: vendor_pause_state + RLS')
    } catch (e) { log.push(`ERR pause: ${(e as Error).message}`) }

    // ───────────────────── 3) vendor_app_sessions ─────────────────────
    try {
      await client.queryArray(`
        CREATE TABLE IF NOT EXISTS vendor_app_sessions (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          vendor_id UUID REFERENCES vendors(id) ON DELETE CASCADE,
          user_id UUID,
          opened_at TIMESTAMPTZ DEFAULT NOW(),
          last_active_at TIMESTAMPTZ DEFAULT NOW(),
          closed_at TIMESTAMPTZ,
          app_version TEXT,
          platform TEXT,
          device_info JSONB
        )
      `)
      await client.queryArray(`CREATE INDEX IF NOT EXISTS idx_vas_vendor_opened ON vendor_app_sessions(vendor_id, opened_at DESC)`)
      await client.queryArray(`ALTER TABLE vendor_app_sessions ENABLE ROW LEVEL SECURITY`)
      await client.queryArray(`DROP POLICY IF EXISTS vas_vendor_rw ON vendor_app_sessions`)
      await client.queryArray(`
        CREATE POLICY vas_vendor_rw ON vendor_app_sessions FOR ALL
        USING (user_id = auth.uid() OR auth.jwt() ->> 'role' = 'service_role')
        WITH CHECK (user_id = auth.uid() OR auth.jwt() ->> 'role' = 'service_role')
      `)
      log.push('OK: vendor_app_sessions + RLS')
    } catch (e) { log.push(`ERR sessions: ${(e as Error).message}`) }

    // ───────────────────── 4) Trigger: auto-compute vendor_responded_in_ms ─────────────────────
    try {
      await client.queryArray(`
        CREATE OR REPLACE FUNCTION compute_vendor_responded_in_ms()
        RETURNS TRIGGER AS $$
        BEGIN
          -- When the order transitions OUT of 'placed' (accepted, cancelled by vendor, etc),
          -- compute the response time once.
          IF NEW.status <> 'placed'
             AND OLD.status = 'placed'
             AND NEW.vendor_responded_in_ms IS NULL THEN
            NEW.vendor_responded_in_ms := GREATEST(
              0,
              (EXTRACT(EPOCH FROM (NOW() - NEW.created_at)) * 1000)::INT
            );
          END IF;
          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql
      `)
      await client.queryArray(`DROP TRIGGER IF EXISTS trg_vendor_response_time ON marketplace_orders`)
      await client.queryArray(`
        CREATE TRIGGER trg_vendor_response_time
        BEFORE UPDATE OF status ON marketplace_orders
        FOR EACH ROW EXECUTE FUNCTION compute_vendor_responded_in_ms()
      `)
      log.push('OK: trg_vendor_response_time')
    } catch (e) { log.push(`ERR trigger: ${(e as Error).message}`) }

    // ───────────────────── 5) RPC vendor_sales_cascade ─────────────────────
    // Returns the full feed grouped: active (live), today, yesterday, this_week, older
    try {
      await client.queryArray(`
        CREATE OR REPLACE FUNCTION vendor_sales_cascade(
          p_vendor_id UUID,
          p_history_days INT DEFAULT 7
        )
        RETURNS TABLE (
          bucket TEXT,
          order_id UUID,
          status TEXT,
          buyer_name TEXT,
          buyer_phone TEXT,
          items_summary TEXT,
          items_count INT,
          total NUMERIC,
          vendor_payout NUMERIC,
          payment_method TEXT,
          delivery_type TEXT,
          created_at TIMESTAMPTZ,
          vendor_accepted_at TIMESTAMPTZ,
          vendor_ready_at TIMESTAMPTZ,
          delivered_at TIMESTAMPTZ,
          completed_at TIMESTAMPTZ,
          cancelled_at TIMESTAMPTZ,
          cancellation_reason TEXT,
          seconds_since_placed INT,
          seconds_until_auto_cancel INT,
          first_image_url TEXT,
          all_items JSONB
        )
        LANGUAGE plpgsql
        SECURITY DEFINER
        AS $$
        BEGIN
          IF NOT EXISTS (SELECT 1 FROM vendors v WHERE v.id = p_vendor_id AND (v.user_id = auth.uid() OR auth.jwt() ->> 'role' = 'service_role')) THEN
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
              WHEN COALESCE(o.completed_at, o.cancelled_at, o.delivered_at) > NOW() - INTERVAL '7 days' THEN 'this_week'
              ELSE 'older'
            END AS bucket,
            o.id AS order_id,
            o.status,
            o.buyer_name,
            o.buyer_phone,
            COALESCE(items.items_summary, '') AS items_summary,
            COALESCE(items.items_count, 0) AS items_count,
            o.total,
            o.vendor_payout,
            o.payment_method,
            o.delivery_type,
            o.created_at,
            o.vendor_accepted_at,
            o.vendor_ready_at,
            o.delivered_at,
            o.completed_at,
            o.cancelled_at,
            o.cancellation_reason,
            EXTRACT(EPOCH FROM (NOW() - o.created_at))::INT AS seconds_since_placed,
            CASE
              WHEN o.status = 'placed' THEN GREATEST(0, 300 - EXTRACT(EPOCH FROM (NOW() - o.created_at))::INT)
              ELSE NULL
            END AS seconds_until_auto_cancel,
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
            CASE
              WHEN o.status IN ('placed','accepted_by_vendor','preparing','ready_for_pickup','driver_assigned','picked_up','in_transit') THEN 0
              ELSE 1
            END,
            o.created_at DESC;
        END;
        $$
      `)
      log.push('OK: vendor_sales_cascade RPC')
    } catch (e) { log.push(`ERR RPC cascade: ${(e as Error).message}`) }

    // ───────────────────── 6) RPC vendor_pause / vendor_resume ─────────────────────
    try {
      await client.queryArray(`
        CREATE OR REPLACE FUNCTION vendor_pause(
          p_vendor_id UUID,
          p_minutes INT,
          p_reason TEXT DEFAULT NULL
        )
        RETURNS vendor_pause_state
        LANGUAGE plpgsql
        SECURITY DEFINER
        AS $$
        DECLARE v_result vendor_pause_state;
        BEGIN
          IF NOT EXISTS (SELECT 1 FROM vendors v WHERE v.id = p_vendor_id AND v.user_id = auth.uid()) THEN
            RAISE EXCEPTION 'not vendor owner';
          END IF;
          INSERT INTO vendor_pause_state (vendor_id, paused_until, reason, paused_at)
          VALUES (p_vendor_id, NOW() + (p_minutes || ' minutes')::INTERVAL, p_reason, NOW())
          ON CONFLICT (vendor_id) DO UPDATE
            SET paused_until = EXCLUDED.paused_until,
                reason = EXCLUDED.reason,
                paused_at = NOW()
          RETURNING * INTO v_result;

          -- Audit
          INSERT INTO vendor_audit_log (vendor_id, action, entity_type, entity_id, metadata, actor_type, actor_id)
          VALUES (p_vendor_id, 'paused', 'vendor', p_vendor_id, jsonb_build_object('minutes', p_minutes, 'reason', p_reason), 'vendor', auth.uid());

          RETURN v_result;
        END;
        $$
      `)
      await client.queryArray(`
        CREATE OR REPLACE FUNCTION vendor_resume(p_vendor_id UUID)
        RETURNS VOID
        LANGUAGE plpgsql
        SECURITY DEFINER
        AS $$
        BEGIN
          IF NOT EXISTS (SELECT 1 FROM vendors v WHERE v.id = p_vendor_id AND v.user_id = auth.uid()) THEN
            RAISE EXCEPTION 'not vendor owner';
          END IF;
          DELETE FROM vendor_pause_state WHERE vendor_id = p_vendor_id;
          INSERT INTO vendor_audit_log (vendor_id, action, entity_type, entity_id, metadata, actor_type, actor_id)
          VALUES (p_vendor_id, 'resumed', 'vendor', p_vendor_id, '{}'::JSONB, 'vendor', auth.uid());
        END;
        $$
      `)
      log.push('OK: vendor_pause / vendor_resume RPCs')
    } catch (e) { log.push(`ERR pause RPC: ${(e as Error).message}`) }

    // ───────────────────── 7) RPC vendor_log_session_open / close ─────────────────────
    try {
      await client.queryArray(`
        CREATE OR REPLACE FUNCTION vendor_log_session_open(
          p_vendor_id UUID,
          p_app_version TEXT DEFAULT NULL,
          p_platform TEXT DEFAULT NULL,
          p_device_info JSONB DEFAULT NULL
        )
        RETURNS UUID
        LANGUAGE plpgsql
        SECURITY DEFINER
        AS $$
        DECLARE v_id UUID;
        BEGIN
          INSERT INTO vendor_app_sessions (vendor_id, user_id, app_version, platform, device_info)
          VALUES (p_vendor_id, auth.uid(), p_app_version, p_platform, p_device_info)
          RETURNING id INTO v_id;
          RETURN v_id;
        END;
        $$
      `)
      await client.queryArray(`
        CREATE OR REPLACE FUNCTION vendor_log_session_close(p_session_id UUID)
        RETURNS VOID
        LANGUAGE plpgsql
        SECURITY DEFINER
        AS $$
        BEGIN
          UPDATE vendor_app_sessions
          SET closed_at = NOW()
          WHERE id = p_session_id AND user_id = auth.uid() AND closed_at IS NULL;
        END;
        $$
      `)
      log.push('OK: vendor_log_session_open/close RPCs')
    } catch (e) { log.push(`ERR session RPC: ${(e as Error).message}`) }

    // ───────────────────── 8) Trigger: notify vendor on new order ─────────────────────
    try {
      await client.queryArray(`CREATE EXTENSION IF NOT EXISTS pg_net`)
      const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
      const SERVICE_KEY  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
      const url  = `${SUPABASE_URL}/functions/v1/notify-vendor-new-order`
      const auth = `Bearer ${SERVICE_KEY}`

      await client.queryArray(`
        CREATE OR REPLACE FUNCTION marketplace_notify_vendor_placed_f()
        RETURNS TRIGGER
        LANGUAGE plpgsql
        SECURITY DEFINER
        SET search_path = public
        AS $fn$
        DECLARE
          v_fire BOOLEAN := FALSE;
        BEGIN
          IF TG_OP = 'INSERT' THEN
            v_fire := NEW.status = 'placed';
          ELSIF TG_OP = 'UPDATE' THEN
            v_fire := NEW.status = 'placed' AND COALESCE(OLD.status, '') <> 'placed';
          END IF;
          IF v_fire THEN
            PERFORM net.http_post(
              url := '${url}',
              headers := jsonb_build_object(
                'Content-Type','application/json',
                'Authorization','${auth}'
              ),
              body := jsonb_build_object('order_id', NEW.id)
            );
          END IF;
          RETURN NEW;
        END;
        $fn$
      `)

      await client.queryArray(`
        DROP TRIGGER IF EXISTS trg_marketplace_notify_vendor_placed ON marketplace_orders
      `)
      await client.queryArray(`
        CREATE TRIGGER trg_marketplace_notify_vendor_placed
        AFTER INSERT OR UPDATE OF status ON marketplace_orders
        FOR EACH ROW
        EXECUTE FUNCTION marketplace_notify_vendor_placed_f()
      `)
      log.push('OK: trigger trg_marketplace_notify_vendor_placed')
    } catch (e) { log.push(`ERR notif trigger: ${(e as Error).message}`) }

    await client.end()
    return new Response(JSON.stringify({ success: true, log }, null, 2), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  } catch (error) {
    return new Response(JSON.stringify({ success: false, error: String(error) }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500
    })
  }
})
