// Edge Function: setup-promo-system
// Adds source_ride_id to wallet_lots for idempotency, ensures wallets exist on demand,
// creates ride_count helper view, and creates trigger for driver notifications.

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
    const results: string[] = []

    // 1) Add source_ride_id + country_code to wallet_lots if missing
    try {
      await client.queryArray(`ALTER TABLE wallet_lots ADD COLUMN IF NOT EXISTS source_ride_id UUID`)
      await client.queryArray(`ALTER TABLE wallet_lots ADD COLUMN IF NOT EXISTS country_code TEXT`)
      await client.queryArray(`ALTER TABLE wallet_lots ADD COLUMN IF NOT EXISTS notes TEXT`)
      results.push("OK: wallet_lots augmented with source_ride_id, country_code, notes")
    } catch (e) {
      results.push(`ERR augment wallet_lots: ${(e as Error).message}`)
    }

    // 2) Unique partial index for referral idempotency (one referral lot per user per ride)
    try {
      await client.queryArray(`
        CREATE UNIQUE INDEX IF NOT EXISTS idx_wallet_lots_referral_unique
        ON wallet_lots(user_id, source_ride_id)
        WHERE lot_type = 'referral' AND source_ride_id IS NOT NULL
      `)
      results.push("OK: unique referral index")
    } catch (e) {
      results.push(`ERR referral idx: ${(e as Error).message}`)
    }

    // 3) Helper function: get_or_create_wallet
    try {
      await client.queryArray(`
        CREATE OR REPLACE FUNCTION get_or_create_wallet(p_user_id UUID, p_country TEXT DEFAULT 'MX')
        RETURNS UUID AS $$
        DECLARE
          v_wallet_id UUID;
        BEGIN
          SELECT id INTO v_wallet_id FROM wallets WHERE user_id = p_user_id LIMIT 1;
          IF v_wallet_id IS NULL THEN
            INSERT INTO wallets (user_id, country_code, balance, created_at, updated_at)
            VALUES (p_user_id, p_country, 0, NOW(), NOW())
            RETURNING id INTO v_wallet_id;
          END IF;
          RETURN v_wallet_id;
        END;
        $$ LANGUAGE plpgsql SECURITY DEFINER
      `)
      results.push("OK: get_or_create_wallet function")
    } catch (e) {
      results.push(`ERR fn wallet: ${(e as Error).message}`)
    }

    // 4) View: rider_ride_count — counts completed rides per user (for promo eligibility)
    try {
      await client.queryArray(`
        CREATE OR REPLACE VIEW rider_ride_count AS
        SELECT
          user_id,
          COUNT(*) FILTER (WHERE status = 'completed') AS completed_rides,
          COUNT(*) FILTER (WHERE status = 'completed' AND completed_at >= NOW() - INTERVAL '7 days') AS rides_last_7d,
          COUNT(*) FILTER (WHERE status = 'completed' AND completed_at >= NOW() - INTERVAL '30 days') AS rides_last_30d,
          MAX(completed_at) AS last_ride_at,
          MIN(created_at) FILTER (WHERE status = 'completed') AS first_ride_at
        FROM deliveries
        WHERE user_id IS NOT NULL
        GROUP BY user_id
      `)
      results.push("OK: rider_ride_count view")
    } catch (e) {
      results.push(`ERR view: ${(e as Error).message}`)
    }

    // 5) Function to check if user is eligible for first-ride promo
    try {
      await client.queryArray(`
        CREATE OR REPLACE FUNCTION is_first_completed_ride(p_user_id UUID, p_ride_id UUID)
        RETURNS BOOLEAN AS $$
        DECLARE
          v_count INT;
        BEGIN
          SELECT COUNT(*) INTO v_count
          FROM deliveries
          WHERE user_id = p_user_id
            AND status = 'completed'
            AND id <> p_ride_id;
          RETURN v_count = 0;
        END;
        $$ LANGUAGE plpgsql SECURITY DEFINER
      `)
      results.push("OK: is_first_completed_ride function")
    } catch (e) {
      results.push(`ERR fn first ride: ${(e as Error).message}`)
    }

    // 6) Inspect wallets table columns (so we know if it exists)
    try {
      const cols = await client.queryObject<{column_name: string}>(`
        SELECT column_name FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'wallets'
        ORDER BY ordinal_position
      `)
      if (cols.rows.length === 0) {
        results.push("WARN: wallets table missing — creating minimal one")
        await client.queryArray(`
          CREATE TABLE IF NOT EXISTS wallets (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id UUID NOT NULL UNIQUE,
            country_code TEXT NOT NULL DEFAULT 'MX',
            balance NUMERIC NOT NULL DEFAULT 0,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
          )
        `)
        results.push("OK: created wallets table")
      } else {
        results.push(`wallets columns: ${cols.rows.map(r => r.column_name).join(', ')}`)
      }
    } catch (e) {
      results.push(`ERR wallets inspect: ${(e as Error).message}`)
    }

    await client.end()

    return new Response(JSON.stringify({ success: true, results }, null, 2), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  } catch (error) {
    return new Response(JSON.stringify({ success: false, error: String(error) }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500
    })
  }
})
