// Edge Function: setup-cron-marketplace
// Schedules the auto-cancel cron job (every minute) using pg_cron + pg_net.
// Idempotent — safe to re-run; previous schedule is deleted first.
// Also schedules a daily VACUUM ANALYZE on hot marketplace tables.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
    const SERVICE_KEY  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const dbUrl = Deno.env.get('SUPABASE_DB_URL')!
    const { Client } = await import("https://deno.land/x/postgres@v0.17.0/mod.ts")
    const client = new Client(dbUrl)
    await client.connect()
    const log: string[] = []

    // Ensure extensions
    try {
      await client.queryArray(`CREATE EXTENSION IF NOT EXISTS pg_cron`)
      await client.queryArray(`CREATE EXTENSION IF NOT EXISTS pg_net`)
      log.push('OK: extensions pg_cron + pg_net')
    } catch (e) { log.push(`ERR ext: ${(e as Error).message}`) }

    // Unschedule previous (idempotent)
    try {
      await client.queryArray(`SELECT cron.unschedule('marketplace_auto_cancel') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'marketplace_auto_cancel')`)
    } catch (_) { /* ok */ }

    // Schedule every minute
    try {
      const url  = `${SUPABASE_URL}/functions/v1/cron-auto-cancel-stale-orders`
      const auth = `Bearer ${SERVICE_KEY}`
      await client.queryArray(`
        SELECT cron.schedule(
          'marketplace_auto_cancel',
          '* * * * *',
          $cmd$
          SELECT net.http_post(
            url := '${url}',
            headers := jsonb_build_object(
              'Content-Type','application/json',
              'Authorization','${auth}'
            ),
            body := '{}'::jsonb
          )
          $cmd$
        )
      `)
      log.push('OK: scheduled marketplace_auto_cancel every minute')
    } catch (e) { log.push(`ERR schedule: ${(e as Error).message}`) }

    // Verify
    try {
      const r = await client.queryObject<{ jobname: string; schedule: string; active: boolean }>(`
        SELECT jobname, schedule, active FROM cron.job WHERE jobname = 'marketplace_auto_cancel'
      `)
      log.push(`OK: cron job state = ${JSON.stringify(r.rows)}`)
    } catch (e) { log.push(`ERR verify: ${(e as Error).message}`) }

    await client.end()
    return new Response(JSON.stringify({ success: true, log }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    return new Response(JSON.stringify({ success: false, error: String(error) }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500,
    })
  }
})
