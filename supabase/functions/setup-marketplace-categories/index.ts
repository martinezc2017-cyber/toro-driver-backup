// Edge Function: setup-marketplace-categories
// Adds missing categories and sets up app_logs + ai_extraction_logs tables.

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

    // 1) Add the 4 missing categories
    const newCats = [
      { slug: 'juguetes',     name_es: 'Juguetes',           name_en: 'Toys',          emoji: '🧸', sort_order: 19 },
      { slug: 'autopartes',   name_es: 'Autopartes',         name_en: 'Auto parts',    emoji: '🔧', sort_order: 20 },
      { slug: 'deportes',     name_es: 'Deportes',           name_en: 'Sports',        emoji: '⚽', sort_order: 21 },
      { slug: 'videojuegos',  name_es: 'Videojuegos',        name_en: 'Video games',   emoji: '🎮', sort_order: 22 },
    ]
    for (const c of newCats) {
      try {
        // product_categories.id is NOT NULL without sequence → compute next id manually
        const r = await client.queryArray(
          `INSERT INTO product_categories (id, slug, name_es, name_en, emoji, sort_order, is_active)
           VALUES ((SELECT COALESCE(MAX(id), 0) + 1 FROM product_categories), $1, $2, $3, $4, $5, true)
           ON CONFLICT (slug) DO NOTHING`,
          [c.slug, c.name_es, c.name_en, c.emoji, c.sort_order]
        )
        log.push(`category "${c.slug}": ${r.rowCount ? 'inserted' : 'already exists'}`)
      } catch (e) {
        log.push(`category "${c.slug}" ERROR: ${(e as Error).message}`)
      }
    }

    // 2) Create category_field_schemas table (dynamic fields per category)
    try {
      await client.queryArray(`
        CREATE TABLE IF NOT EXISTS category_field_schemas (
          id SERIAL PRIMARY KEY,
          category_id INT NOT NULL REFERENCES product_categories(id) ON DELETE CASCADE,
          field_key TEXT NOT NULL,
          field_label_es TEXT NOT NULL,
          field_label_en TEXT,
          field_type TEXT NOT NULL CHECK (field_type IN ('text','number','select','multi_select','date','boolean','textarea')),
          options JSONB,
          placeholder_es TEXT,
          is_required BOOLEAN DEFAULT false,
          user_must_fill BOOLEAN DEFAULT false,
          ai_can_suggest BOOLEAN DEFAULT true,
          ai_variants_count INT DEFAULT 1,
          sort_order INT DEFAULT 0,
          created_at TIMESTAMPTZ DEFAULT NOW(),
          UNIQUE (category_id, field_key)
        )
      `)
      log.push('category_field_schemas table: ready')
    } catch (e) {
      log.push(`schemas table ERROR: ${(e as Error).message}`)
    }

    // 3) Create ai_extraction_logs (for AI calls)
    try {
      await client.queryArray(`
        CREATE TABLE IF NOT EXISTS ai_extraction_logs (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          vendor_id UUID,
          product_id UUID,
          category_slug TEXT,
          photo_urls TEXT[],
          user_provided_fields JSONB,
          ai_provider TEXT,
          ai_model TEXT,
          ai_response JSONB,
          tokens_used INT,
          latency_ms INT,
          success BOOLEAN DEFAULT false,
          error_message TEXT,
          fallback_triggered BOOLEAN DEFAULT false,
          created_at TIMESTAMPTZ DEFAULT NOW()
        )
      `)
      await client.queryArray(`CREATE INDEX IF NOT EXISTS idx_ai_logs_created ON ai_extraction_logs(created_at DESC)`)
      await client.queryArray(`CREATE INDEX IF NOT EXISTS idx_ai_logs_success ON ai_extraction_logs(success, created_at DESC)`)
      log.push('ai_extraction_logs table: ready')
    } catch (e) {
      log.push(`ai_extraction_logs ERROR: ${(e as Error).message}`)
    }

    // 4) Create app_logs (general logging for ANY code event — bugs, errors, milestones)
    try {
      await client.queryArray(`
        CREATE TABLE IF NOT EXISTS app_logs (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          level TEXT NOT NULL CHECK (level IN ('debug','info','warn','error','critical')),
          source TEXT NOT NULL,
          event TEXT NOT NULL,
          message TEXT,
          user_id UUID,
          device_info JSONB,
          context JSONB,
          stack_trace TEXT,
          app_version TEXT,
          app_role TEXT,
          created_at TIMESTAMPTZ DEFAULT NOW()
        )
      `)
      await client.queryArray(`CREATE INDEX IF NOT EXISTS idx_app_logs_level_created ON app_logs(level, created_at DESC)`)
      await client.queryArray(`CREATE INDEX IF NOT EXISTS idx_app_logs_source ON app_logs(source, created_at DESC)`)
      await client.queryArray(`CREATE INDEX IF NOT EXISTS idx_app_logs_user ON app_logs(user_id, created_at DESC) WHERE user_id IS NOT NULL`)
      log.push('app_logs table: ready')
    } catch (e) {
      log.push(`app_logs ERROR: ${(e as Error).message}`)
    }

    // 5) RLS — allow inserts from anyone (logs need to capture even unauthed events)
    try {
      await client.queryArray(`ALTER TABLE app_logs ENABLE ROW LEVEL SECURITY`)
      await client.queryArray(`DROP POLICY IF EXISTS "anyone_can_insert_logs" ON app_logs`)
      await client.queryArray(`CREATE POLICY "anyone_can_insert_logs" ON app_logs FOR INSERT WITH CHECK (true)`)
      await client.queryArray(`DROP POLICY IF EXISTS "service_role_reads_logs" ON app_logs`)
      await client.queryArray(`CREATE POLICY "service_role_reads_logs" ON app_logs FOR SELECT USING (auth.jwt() ->> 'role' = 'service_role')`)
      log.push('app_logs RLS: insert open, select admin only')
    } catch (e) {
      log.push(`app_logs RLS ERROR: ${(e as Error).message}`)
    }

    try {
      await client.queryArray(`ALTER TABLE ai_extraction_logs ENABLE ROW LEVEL SECURITY`)
      await client.queryArray(`DROP POLICY IF EXISTS "anyone_can_insert_ai_logs" ON ai_extraction_logs`)
      await client.queryArray(`CREATE POLICY "anyone_can_insert_ai_logs" ON ai_extraction_logs FOR INSERT WITH CHECK (true)`)
      await client.queryArray(`DROP POLICY IF EXISTS "service_role_reads_ai_logs" ON ai_extraction_logs`)
      await client.queryArray(`CREATE POLICY "service_role_reads_ai_logs" ON ai_extraction_logs FOR SELECT USING (auth.jwt() ->> 'role' = 'service_role')`)
      log.push('ai_extraction_logs RLS: insert open, select admin only')
    } catch (e) {
      log.push(`ai_extraction_logs RLS ERROR: ${(e as Error).message}`)
    }

    // 6) Verify counts
    const catCount = await client.queryObject<{c: bigint}>(`SELECT COUNT(*)::bigint as c FROM product_categories WHERE is_active = true`)
    log.push(`active categories now: ${Number(catCount.rows[0].c)}`)

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
