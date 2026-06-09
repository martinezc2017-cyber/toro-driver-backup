// Edge Function: setup-vendor-quota
// Creates vendor_daily_quota table + RPC to check & increment atomically.

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

    try {
      await client.queryArray(`
        CREATE TABLE IF NOT EXISTS vendor_daily_quota (
          vendor_id UUID NOT NULL,
          quota_date DATE NOT NULL DEFAULT CURRENT_DATE,
          bulk_uploads_used INT NOT NULL DEFAULT 0,
          ai_extractions_used INT NOT NULL DEFAULT 0,
          plan TEXT NOT NULL DEFAULT 'bootstrap',
          daily_limit INT NOT NULL DEFAULT 10,
          created_at TIMESTAMPTZ DEFAULT NOW(),
          updated_at TIMESTAMPTZ DEFAULT NOW(),
          PRIMARY KEY (vendor_id, quota_date)
        )
      `)
      log.push('vendor_daily_quota table: ready')
    } catch (e) {
      log.push(`table ERROR: ${(e as Error).message}`)
    }

    // RPC: atomically check & increment quota
    try {
      await client.queryArray(`
        CREATE OR REPLACE FUNCTION check_and_increment_quota(
          p_vendor_id UUID,
          p_count INT DEFAULT 1
        )
        RETURNS TABLE (allowed BOOLEAN, used INT, remaining INT, plan TEXT, daily_limit INT) AS $$
        DECLARE
          v_plan TEXT := 'bootstrap';
          v_limit INT := 10;
          v_used INT;
        BEGIN
          INSERT INTO vendor_daily_quota (vendor_id, quota_date, bulk_uploads_used, plan, daily_limit)
          VALUES (p_vendor_id, CURRENT_DATE, 0, v_plan, v_limit)
          ON CONFLICT (vendor_id, quota_date) DO NOTHING;

          SELECT q.plan, q.daily_limit, q.bulk_uploads_used INTO v_plan, v_limit, v_used
          FROM vendor_daily_quota q
          WHERE q.vendor_id = p_vendor_id AND q.quota_date = CURRENT_DATE
          FOR UPDATE;

          IF v_used + p_count > v_limit THEN
            RETURN QUERY SELECT false, v_used, v_limit - v_used, v_plan, v_limit;
            RETURN;
          END IF;

          UPDATE vendor_daily_quota
          SET bulk_uploads_used = bulk_uploads_used + p_count,
              updated_at = NOW()
          WHERE vendor_id = p_vendor_id AND quota_date = CURRENT_DATE;

          RETURN QUERY SELECT true, v_used + p_count, v_limit - (v_used + p_count), v_plan, v_limit;
        END;
        $$ LANGUAGE plpgsql SECURITY DEFINER
      `)
      log.push('check_and_increment_quota RPC: ready')
    } catch (e) {
      log.push(`RPC ERROR: ${(e as Error).message}`)
    }

    // RLS
    try {
      await client.queryArray(`ALTER TABLE vendor_daily_quota ENABLE ROW LEVEL SECURITY`)
      await client.queryArray(`DROP POLICY IF EXISTS "vendor_reads_own_quota" ON vendor_daily_quota`)
      await client.queryArray(`
        CREATE POLICY "vendor_reads_own_quota" ON vendor_daily_quota
        FOR SELECT
        USING (
          EXISTS (SELECT 1 FROM vendors v WHERE v.id = vendor_daily_quota.vendor_id AND v.user_id = auth.uid())
          OR auth.jwt() ->> 'role' = 'service_role'
        )
      `)
      log.push('vendor_daily_quota RLS: vendor reads own only')
    } catch (e) {
      log.push(`RLS ERROR: ${(e as Error).message}`)
    }

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
