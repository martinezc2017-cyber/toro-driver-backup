// Edge Function: check-marketplace-rls
// Audits RLS policies on marketplace tables to confirm vendor data isolation.

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

    const out: any = {}

    const tables = ['products', 'vendors', 'marketplace_orders', 'marketplace_order_items', 'product_variants']
    for (const t of tables) {
      const rls = await client.queryObject<{rls: boolean}>(`
        SELECT relrowsecurity AS rls FROM pg_class
        WHERE relname = $1 AND relnamespace = 'public'::regnamespace
      `, [t])
      const policies = await client.queryObject<any>(`
        SELECT policyname, cmd, qual::text AS using_expr, with_check::text AS with_check_expr, roles
        FROM pg_policies WHERE schemaname = 'public' AND tablename = $1
      `, [t])
      out[t] = {
        rls_enabled: rls.rows[0]?.rls ?? null,
        policies: policies.rows,
      }
    }

    await client.end()
    return new Response(JSON.stringify(out, null, 2), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  } catch (error) {
    return new Response(JSON.stringify({ success: false, error: String(error) }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500
    })
  }
})
