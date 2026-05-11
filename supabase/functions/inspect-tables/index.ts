// Quick inspection function
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  const dbUrl = Deno.env.get('SUPABASE_DB_URL')!
  const { Client } = await import("https://deno.land/x/postgres@v0.17.0/mod.ts")
  const client = new Client(dbUrl)
  await client.connect()

  const tablesToInspect = ['profiles', 'wallet_lots', 'drivers', 'deliveries', 'wallets']
  const result: Record<string, string[]> = {}

  for (const t of tablesToInspect) {
    try {
      const r = await client.queryObject<{column_name: string}>(`
        SELECT column_name FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = $1
        ORDER BY ordinal_position
      `, [t])
      result[t] = r.rows.map(x => x.column_name)
    } catch (e) {
      result[t] = [`ERR: ${(e as Error).message}`]
    }
  }

  // Sample wallet_lots row
  try {
    const sample = await client.queryObject(`SELECT * FROM wallet_lots LIMIT 1`)
    result['_wallet_lots_sample'] = sample.rows.length > 0 ? [JSON.stringify(sample.rows[0])] : ['(empty)']
  } catch (e) {
    result['_wallet_lots_sample'] = [`ERR: ${(e as Error).message}`]
  }

  await client.end()

  return new Response(JSON.stringify(result, null, 2), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
})
