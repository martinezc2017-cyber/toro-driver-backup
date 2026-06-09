// Edge Function: setup-category-hierarchy
// Adds parent_category_id + group_emoji to product_categories.
// Creates 4 parent group categories and assigns children.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Hierarchy:
// - "Despensa" (parent): comida-preparada, frutas-verduras, carniceria, abarrotes, postres, bebidas
// - "Productos" (parent): ropa, calzado, belleza, salud, bebes-ninos, mascotas, hogar, electronicos, juguetes, deportes, videojuegos
// - "Vehiculos" (parent): automoviles, autopartes
// - "Otros" (parent): servicios, industrial, otros
const PARENTS = [
  { slug: 'g-despensa', name_es: 'Despensa', name_en: 'Pantry', emoji: '🍴', sort_order: 1, group_emoji: '🍴' },
  { slug: 'g-productos', name_es: 'Productos', name_en: 'Products', emoji: '🛍️', sort_order: 2, group_emoji: '🛍️' },
  { slug: 'g-vehiculos', name_es: 'Vehículos', name_en: 'Vehicles', emoji: '🚗', sort_order: 3, group_emoji: '🚗' },
  { slug: 'g-otros', name_es: 'Otros', name_en: 'Other', emoji: '🛠️', sort_order: 4, group_emoji: '🛠️' },
]

const PARENT_ASSIGNMENTS: Record<string, string[]> = {
  'g-despensa': ['comida-preparada', 'frutas-verduras', 'carniceria', 'abarrotes', 'postres', 'bebidas'],
  'g-productos': ['ropa', 'calzado', 'belleza', 'salud', 'bebes-ninos', 'mascotas', 'hogar', 'electronicos', 'juguetes', 'deportes', 'videojuegos'],
  'g-vehiculos': ['automoviles', 'autopartes'],
  'g-otros': ['servicios', 'industrial', 'otros'],
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const dbUrl = Deno.env.get('SUPABASE_DB_URL')!
    const { Client } = await import("https://deno.land/x/postgres@v0.17.0/mod.ts")
    const client = new Client(dbUrl)
    await client.connect()
    const log: string[] = []

    // 1) ALTER columns
    try {
      await client.queryArray(`
        ALTER TABLE product_categories
        ADD COLUMN IF NOT EXISTS parent_category_id INT REFERENCES product_categories(id) ON DELETE SET NULL,
        ADD COLUMN IF NOT EXISTS group_emoji TEXT,
        ADD COLUMN IF NOT EXISTS is_group BOOLEAN DEFAULT false
      `)
      log.push('OK: parent_category_id, group_emoji, is_group columns added')
    } catch (e) {
      log.push(`ALTER ERROR: ${(e as Error).message}`)
    }

    try {
      await client.queryArray(`CREATE INDEX IF NOT EXISTS idx_cat_parent ON product_categories(parent_category_id)`)
      await client.queryArray(`CREATE INDEX IF NOT EXISTS idx_cat_is_group ON product_categories(is_group) WHERE is_group = true`)
      log.push('OK: indexes')
    } catch (e) {
      log.push(`INDEX ERROR: ${(e as Error).message}`)
    }

    // 2) Insert parent groups (high IDs to keep clear)
    const parentSlugToId = new Map<string, number>()
    for (const p of PARENTS) {
      try {
        const r = await client.queryObject<{ id: number }>(
          `INSERT INTO product_categories (id, slug, name_es, name_en, emoji, group_emoji, sort_order, is_active, is_group)
           VALUES ((SELECT GREATEST(COALESCE(MAX(id), 0), 99) + 1 FROM product_categories), $1, $2, $3, $4, $5, $6, true, true)
           ON CONFLICT (slug) DO UPDATE SET
             name_es = EXCLUDED.name_es,
             emoji = EXCLUDED.emoji,
             group_emoji = EXCLUDED.group_emoji,
             is_group = true,
             sort_order = EXCLUDED.sort_order
           RETURNING id`,
          [p.slug, p.name_es, p.name_en, p.emoji, p.group_emoji, p.sort_order],
        )
        const id = r.rows[0]?.id
        if (id) {
          parentSlugToId.set(p.slug, Number(id))
          log.push(`parent "${p.slug}" id=${id}`)
        }
      } catch (e) {
        log.push(`parent "${p.slug}" ERROR: ${(e as Error).message}`)
      }
    }

    // 3) Assign children to parents
    for (const [parentSlug, childSlugs] of Object.entries(PARENT_ASSIGNMENTS)) {
      const parentId = parentSlugToId.get(parentSlug)
      if (!parentId) {
        log.push(`SKIP children of "${parentSlug}": parent id missing`)
        continue
      }
      try {
        const r = await client.queryArray(
          `UPDATE product_categories
           SET parent_category_id = $1,
               is_group = false
           WHERE slug = ANY($2)`,
          [parentId, childSlugs],
        )
        log.push(`assigned ${r.rowCount} children to "${parentSlug}"`)
      } catch (e) {
        log.push(`assign "${parentSlug}" ERROR: ${(e as Error).message}`)
      }
    }

    // 4) Verify
    const groups = await client.queryObject<any>(`
      SELECT
        p.id as parent_id, p.slug as parent_slug, p.name_es as parent_name, p.group_emoji,
        COUNT(c.id)::int as child_count
      FROM product_categories p
      LEFT JOIN product_categories c ON c.parent_category_id = p.id
      WHERE p.is_group = true
      GROUP BY p.id, p.slug, p.name_es, p.group_emoji, p.sort_order
      ORDER BY p.sort_order
    `)
    log.push('')
    log.push('Final hierarchy:')
    for (const g of groups.rows) {
      log.push(`  ${g.group_emoji} ${g.parent_name} (id=${g.parent_id}) — ${g.child_count} hijas`)
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
