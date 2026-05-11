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

    // 1) Create bug_reports table
    try {
      await client.queryArray(`
        CREATE TABLE IF NOT EXISTS bug_reports (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id TEXT NOT NULL,
          description TEXT NOT NULL,
          screen_name TEXT NOT NULL,
          screenshot_url TEXT,
          severity TEXT NOT NULL DEFAULT 'medium',
          status TEXT NOT NULL DEFAULT 'open',
          device_info JSONB,
          extra_data JSONB,
          admin_notes TEXT,
          resolved_at TIMESTAMPTZ,
          resolved_by UUID,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
      `)
      results.push("OK: Created bug_reports table")
    } catch (e) {
      results.push(`ERR create table: ${(e as Error).message}`)
    }

    // 2) Create indexes
    try {
      await client.queryArray(`CREATE INDEX IF NOT EXISTS idx_bug_reports_user_id ON bug_reports(user_id)`)
      await client.queryArray(`CREATE INDEX IF NOT EXISTS idx_bug_reports_status ON bug_reports(status)`)
      await client.queryArray(`CREATE INDEX IF NOT EXISTS idx_bug_reports_severity ON bug_reports(severity)`)
      await client.queryArray(`CREATE INDEX IF NOT EXISTS idx_bug_reports_created_at ON bug_reports(created_at DESC)`)
      results.push("OK: Created indexes")
    } catch (e) {
      results.push(`ERR indexes: ${(e as Error).message}`)
    }

    // 3) Enable RLS
    try {
      await client.queryArray(`ALTER TABLE bug_reports ENABLE ROW LEVEL SECURITY`)
      results.push("OK: Enabled RLS")
    } catch (e) {
      results.push(`ERR rls: ${(e as Error).message}`)
    }

    // 4) Create policies
    try {
      await client.queryArray(`DROP POLICY IF EXISTS "anyone_can_insert_bugs" ON bug_reports`)
      await client.queryArray(`CREATE POLICY "anyone_can_insert_bugs" ON bug_reports FOR INSERT WITH CHECK (true)`)
      results.push("OK: Created insert policy")
    } catch (e) {
      results.push(`ERR insert policy: ${(e as Error).message}`)
    }

    try {
      await client.queryArray(`DROP POLICY IF EXISTS "users_view_own_bugs" ON bug_reports`)
      await client.queryArray(`CREATE POLICY "users_view_own_bugs" ON bug_reports FOR SELECT USING (true)`)
      results.push("OK: Created select policy")
    } catch (e) {
      results.push(`ERR select policy: ${(e as Error).message}`)
    }

    try {
      await client.queryArray(`DROP POLICY IF EXISTS "service_role_full_access" ON bug_reports`)
      await client.queryArray(`CREATE POLICY "service_role_full_access" ON bug_reports FOR ALL USING (auth.jwt() ->> 'role' = 'service_role')`)
      results.push("OK: Created service_role policy")
    } catch (e) {
      results.push(`ERR service_role policy: ${(e as Error).message}`)
    }

    // 5) Updated_at trigger
    try {
      await client.queryArray(`
        CREATE OR REPLACE FUNCTION update_bug_reports_updated_at()
        RETURNS TRIGGER AS $$
        BEGIN
          NEW.updated_at = NOW();
          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql
      `)
      await client.queryArray(`DROP TRIGGER IF EXISTS trigger_bug_reports_updated_at ON bug_reports`)
      await client.queryArray(`
        CREATE TRIGGER trigger_bug_reports_updated_at
        BEFORE UPDATE ON bug_reports
        FOR EACH ROW
        EXECUTE FUNCTION update_bug_reports_updated_at()
      `)
      results.push("OK: Created updated_at trigger")
    } catch (e) {
      results.push(`ERR trigger: ${(e as Error).message}`)
    }

    // 6) Verify by counting columns
    try {
      const verify = await client.queryObject<{count: bigint}>(`
        SELECT COUNT(*) as count FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'bug_reports'
      `)
      results.push(`OK: Table has ${verify.rows[0].count} columns`)
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
