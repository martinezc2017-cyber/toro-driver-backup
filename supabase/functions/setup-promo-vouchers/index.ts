// Edge Function: setup-promo-vouchers
// Creates promo_vouchers table for post-ride discounts

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const dbUrl = Deno.env.get('SUPABASE_DB_URL')!
    const results: string[] = []

    const { Client } = await import("https://deno.land/x/postgres@v0.17.0/mod.ts")
    const client = new Client(dbUrl)
    await client.connect()

    // Inspect wallet_lots columns
    try {
      const cols = await client.queryObject<{column_name: string, data_type: string}>(`
        SELECT column_name, data_type FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'wallet_lots'
        ORDER BY ordinal_position
      `)
      results.push(`wallet_lots columns: ${cols.rows.map(r => r.column_name).join(', ')}`)
    } catch (e) {
      results.push(`ERR inspect wallet_lots: ${(e as Error).message}`)
    }

    // Create promo_vouchers
    try {
      await client.queryArray(`
        CREATE TABLE IF NOT EXISTS promo_vouchers (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id UUID NOT NULL,
          voucher_type TEXT NOT NULL,
          discount_pct INTEGER,
          discount_amount NUMERIC,
          country_code TEXT NOT NULL DEFAULT 'MX',
          source_ride_id UUID,
          expires_at TIMESTAMPTZ NOT NULL,
          redeemed_at TIMESTAMPTZ,
          redeemed_ride_id UUID,
          status TEXT NOT NULL DEFAULT 'active',
          notes TEXT,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
      `)
      results.push("OK: Created promo_vouchers table")
    } catch (e) {
      results.push(`ERR create table: ${(e as Error).message}`)
    }

    // Indexes
    try {
      await client.queryArray(`CREATE INDEX IF NOT EXISTS idx_vouchers_user_status ON promo_vouchers(user_id, status)`)
      await client.queryArray(`CREATE INDEX IF NOT EXISTS idx_vouchers_expires ON promo_vouchers(expires_at) WHERE status = 'active'`)
      await client.queryArray(`CREATE INDEX IF NOT EXISTS idx_vouchers_source_ride ON promo_vouchers(source_ride_id)`)
      results.push("OK: Created indexes")
    } catch (e) {
      results.push(`ERR indexes: ${(e as Error).message}`)
    }

    // RLS
    try {
      await client.queryArray(`ALTER TABLE promo_vouchers ENABLE ROW LEVEL SECURITY`)
      await client.queryArray(`DROP POLICY IF EXISTS "users_view_own_vouchers" ON promo_vouchers`)
      await client.queryArray(`CREATE POLICY "users_view_own_vouchers" ON promo_vouchers FOR SELECT USING (user_id = auth.uid() OR auth.jwt() ->> 'role' = 'service_role')`)
      await client.queryArray(`DROP POLICY IF EXISTS "service_role_full_access_vouchers" ON promo_vouchers`)
      await client.queryArray(`CREATE POLICY "service_role_full_access_vouchers" ON promo_vouchers FOR ALL USING (auth.jwt() ->> 'role' = 'service_role')`)
      results.push("OK: RLS + policies")
    } catch (e) {
      results.push(`ERR rls: ${(e as Error).message}`)
    }

    // Verify
    try {
      const verify = await client.queryObject<{count: bigint}>(`
        SELECT COUNT(*) as count FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'promo_vouchers'
      `)
      results.push(`OK: promo_vouchers has ${verify.rows[0].count} columns`)
    } catch (e) {
      results.push(`ERR verify: ${(e as Error).message}`)
    }

    await client.end()

    return new Response(
      JSON.stringify({ success: true, results }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ success: false, error: String(error) }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
    )
  }
})
