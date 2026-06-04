// Edge Function: cron-auto-cancel-stale-orders
// Runs every 60 seconds. Cancels marketplace orders that have been in 'placed' status
// for more than 5 minutes (vendor didn't accept in time).
// Idempotent — safe to call multiple times.
// All cancellations logged to marketplace_order_events + app_logs.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const ACCEPT_TIMEOUT_MINUTES = 5

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const startTime = Date.now()
  try {
    const dbUrl = Deno.env.get('SUPABASE_DB_URL')!
    const { Client } = await import("https://deno.land/x/postgres@v0.17.0/mod.ts")
    const client = new Client(dbUrl)
    await client.connect()

    // Find stale orders
    const stale = await client.queryObject<{
      id: string; vendor_id: string; total: number; created_at: Date; payment_status: string;
    }>(`
      SELECT id, vendor_id, total, created_at, payment_status
      FROM marketplace_orders
      WHERE status = 'placed'
        AND created_at < NOW() - INTERVAL '${ACCEPT_TIMEOUT_MINUTES} minutes'
      ORDER BY created_at ASC
      LIMIT 50
    `)

    let cancelled = 0
    let errors = 0
    const details: any[] = []

    for (const order of stale.rows) {
      try {
        // Update to auto_cancelled (trigger marketplace_notify_status_trg will push to vendor + buyer)
        await client.queryArray(`
          UPDATE marketplace_orders
          SET status = 'auto_cancelled',
              cancelled_at = NOW(),
              cancellation_reason = $1,
              cancelled_by = 'system'
          WHERE id = $2 AND status = 'placed'
        `, [`Vendor no aceptó en ${ACCEPT_TIMEOUT_MINUTES} minutos`, order.id])

        // Add event in marketplace_order_events
        await client.queryArray(`
          INSERT INTO marketplace_order_events (order_id, from_status, to_status, actor_type, note)
          VALUES ($1, 'placed', 'auto_cancelled', 'system', $2)
        `, [order.id, `cron auto-cancel after ${ACCEPT_TIMEOUT_MINUTES}m`])

        // If payment was authorized (card), trigger refund.
        // payments_canonical_f7b already handles this via its own RPC,
        // but cron path needs to call stripe-marketplace-refund directly.
        if (order.payment_status === 'authorized' || order.payment_status === 'captured') {
          await client.queryArray(`
            SELECT extensions.http_post(
              url := $1,
              body := jsonb_build_object('order_id', $2, 'reason', 'auto_cancel_timeout')::text,
              headers := jsonb_build_object('Content-Type','application/json')::jsonb
            )
          `, [
            `${Deno.env.get('SUPABASE_URL')}/functions/v1/stripe-marketplace-refund`,
            order.id,
          ])
        }

        cancelled++
        details.push({ order_id: order.id, vendor_id: order.vendor_id, total: order.total })
      } catch (e) {
        errors++
        details.push({ order_id: order.id, error: (e as Error).message })
      }
    }

    // Persistent log of this cron run
    try {
      await client.queryArray(`
        INSERT INTO app_logs (level, source, event, message, context, app_role)
        VALUES ('info', 'cron-auto-cancel', 'run', $1, $2, 'system')
      `, [
        `Auto-cancelled ${cancelled} stale orders (${errors} errors)`,
        JSON.stringify({
          examined: stale.rows.length,
          cancelled,
          errors,
          details,
          latency_ms: Date.now() - startTime,
        }),
      ])
    } catch (_) { /* app_logs may not exist yet */ }

    await client.end()
    return new Response(
      JSON.stringify({
        success: true,
        examined: stale.rows.length,
        cancelled,
        errors,
        latency_ms: Date.now() - startTime,
        details,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    return new Response(JSON.stringify({ success: false, error: String(error) }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500
    })
  }
})
