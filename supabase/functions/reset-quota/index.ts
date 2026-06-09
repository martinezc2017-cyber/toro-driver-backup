// Edge Function: reset-quota
// Resets a vendor's daily quota row (admin / testing).
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}
serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  const { vendor_id, daily_limit } = await req.json()
  const dbUrl = Deno.env.get('SUPABASE_DB_URL')!
  const { Client } = await import("https://deno.land/x/postgres@v0.17.0/mod.ts")
  const client = new Client(dbUrl)
  await client.connect()
  const r = await client.queryArray(`
    INSERT INTO vendor_daily_quota (vendor_id, quota_date, bulk_uploads_used, daily_limit)
    VALUES ($1, CURRENT_DATE, 0, $2)
    ON CONFLICT (vendor_id, quota_date) DO UPDATE
      SET bulk_uploads_used = 0, daily_limit = EXCLUDED.daily_limit
  `, [vendor_id, daily_limit ?? 100])
  await client.end()
  return new Response(JSON.stringify({ success: true, rows: r.rowCount }), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
