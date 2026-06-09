// Edge Function: seed-category-schemas
// Seeds category_field_schemas for the 8 core categories.
// Also verifies storage bucket marketplace-products has proper policies.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Field schemas per category slug.
// Fields marked user_must_fill=true → vendor escribe (no AI invent)
// Fields marked ai_can_suggest=true → AI completa (vendor revisa)
const SCHEMAS: Record<string, Array<{
  field_key: string
  field_label_es: string
  field_label_en?: string
  field_type: 'text' | 'number' | 'select' | 'multi_select' | 'date' | 'boolean' | 'textarea'
  options?: string[]
  placeholder_es?: string
  is_required?: boolean
  user_must_fill?: boolean
  ai_can_suggest?: boolean
  ai_variants_count?: number
  sort_order: number
}>> = {
  // ━━━━━━━━━━ AUTOMOVILES ━━━━━━━━━━
  'automoviles': [
    { field_key: 'marca', field_label_es: 'Marca', field_label_en: 'Make', field_type: 'select',
      options: ['Ford','Chevrolet','Toyota','Honda','Nissan','Mazda','Hyundai','Kia','Volkswagen','Jeep','Dodge','Ram','GMC','Kenworth','Peterbilt','Freightliner','Volvo','International','Mack','Hino','Mercedes-Benz','BMW','Audi','Otro'],
      is_required: true, user_must_fill: true, ai_can_suggest: true, sort_order: 1 },
    { field_key: 'modelo', field_label_es: 'Modelo', field_type: 'text', placeholder_es: 'Ej: F-150, T680, Civic',
      is_required: true, user_must_fill: true, ai_can_suggest: true, sort_order: 2 },
    { field_key: 'ano', field_label_es: 'Año', field_type: 'number', placeholder_es: '2018',
      is_required: true, user_must_fill: true, ai_can_suggest: true, sort_order: 3 },
    { field_key: 'kilometraje', field_label_es: 'Kilometraje', field_type: 'number', placeholder_es: '125000',
      user_must_fill: true, ai_can_suggest: false, sort_order: 4 },
    { field_key: 'transmision', field_label_es: 'Transmisión', field_type: 'select',
      options: ['Automática','Estándar','Automatizada (AMT)','CVT'],
      user_must_fill: false, ai_can_suggest: true, sort_order: 5 },
    { field_key: 'combustible', field_label_es: 'Combustible', field_type: 'select',
      options: ['Gasolina','Diésel','Híbrido','Eléctrico','GNV/GLP'],
      ai_can_suggest: true, sort_order: 6 },
    { field_key: 'color', field_label_es: 'Color', field_type: 'text',
      ai_can_suggest: true, sort_order: 7 },
    { field_key: 'condicion', field_label_es: 'Condición', field_type: 'select',
      options: ['Nuevo','Seminuevo','Usado - excelente','Usado - bueno','Usado - regular','Para reparar'],
      ai_can_suggest: true, sort_order: 8 },
    { field_key: 'tipo_carroceria', field_label_es: 'Tipo de carrocería', field_type: 'select',
      options: ['Sedán','SUV','Pickup','Van','Tractocamión','Caja seca','Plataforma','Volteo','Motocicleta','Otro'],
      ai_can_suggest: true, sort_order: 9 },
    { field_key: 'descripcion', field_label_es: 'Descripción', field_type: 'textarea',
      ai_can_suggest: true, ai_variants_count: 3, sort_order: 10 },
  ],

  // ━━━━━━━━━━ COMIDA PREPARADA ━━━━━━━━━━
  'comida-preparada': [
    { field_key: 'nombre_platillo', field_label_es: 'Nombre del platillo', field_type: 'text',
      is_required: true, user_must_fill: true, ai_can_suggest: true, sort_order: 1 },
    { field_key: 'porciones', field_label_es: 'Porciones', field_type: 'number', placeholder_es: '1',
      is_required: true, user_must_fill: true, sort_order: 2 },
    { field_key: 'tipo', field_label_es: 'Tipo', field_type: 'select',
      options: ['Desayuno','Comida','Cena','Snack','Postre','Bebida'],
      ai_can_suggest: true, sort_order: 3 },
    { field_key: 'ingredientes_detectados', field_label_es: 'Ingredientes', field_type: 'multi_select',
      ai_can_suggest: true, sort_order: 4 },
    { field_key: 'alergenos', field_label_es: 'Alérgenos', field_type: 'multi_select',
      options: ['Lácteos','Gluten','Huevo','Frutos secos','Soya','Mariscos','Pescado'],
      ai_can_suggest: true, sort_order: 5 },
    { field_key: 'calorias_estimadas', field_label_es: 'Calorías (aprox)', field_type: 'number',
      ai_can_suggest: true, sort_order: 6 },
    { field_key: 'tiempo_prep_min', field_label_es: 'Tiempo de preparación (min)', field_type: 'number',
      ai_can_suggest: true, sort_order: 7 },
    { field_key: 'picante', field_label_es: 'Nivel de picante', field_type: 'select',
      options: ['No pica','Suave','Medio','Picoso','Muy picoso'],
      ai_can_suggest: true, sort_order: 8 },
    { field_key: 'vegetariano', field_label_es: 'Apto vegetariano', field_type: 'boolean',
      ai_can_suggest: true, sort_order: 9 },
    { field_key: 'descripcion', field_label_es: 'Descripción', field_type: 'textarea',
      ai_can_suggest: true, ai_variants_count: 3, sort_order: 10 },
  ],

  // ━━━━━━━━━━ ELECTRONICOS ━━━━━━━━━━
  'electronicos': [
    { field_key: 'marca', field_label_es: 'Marca', field_type: 'text', placeholder_es: 'Apple, Samsung, etc',
      is_required: true, user_must_fill: true, ai_can_suggest: true, sort_order: 1 },
    { field_key: 'modelo', field_label_es: 'Modelo', field_type: 'text', placeholder_es: 'iPhone 13, Galaxy S22',
      is_required: true, user_must_fill: true, ai_can_suggest: true, sort_order: 2 },
    { field_key: 'tipo', field_label_es: 'Tipo', field_type: 'select',
      options: ['Smartphone','Laptop','Tablet','TV','Audio','Cámara','Consola','Accesorio','Otro'],
      ai_can_suggest: true, sort_order: 3 },
    { field_key: 'condicion', field_label_es: 'Condición', field_type: 'select',
      options: ['Nuevo sellado','Como nuevo','Usado - excelente','Usado - bueno','Usado - regular','Para piezas'],
      is_required: true, user_must_fill: true, sort_order: 4 },
    { field_key: 'capacidad', field_label_es: 'Capacidad / GB', field_type: 'text', placeholder_es: '128GB',
      ai_can_suggest: true, sort_order: 5 },
    { field_key: 'color', field_label_es: 'Color', field_type: 'text',
      ai_can_suggest: true, sort_order: 6 },
    { field_key: 'incluye_accesorios', field_label_es: 'Accesorios incluidos', field_type: 'multi_select',
      options: ['Cargador','Cable','Audífonos','Caja original','Funda','Mica','Otro'],
      ai_can_suggest: true, sort_order: 7 },
    { field_key: 'liberado', field_label_es: 'Liberado / sin SIM lock', field_type: 'boolean',
      ai_can_suggest: false, sort_order: 8 },
    { field_key: 'descripcion', field_label_es: 'Descripción', field_type: 'textarea',
      ai_can_suggest: true, ai_variants_count: 3, sort_order: 9 },
  ],

  // ━━━━━━━━━━ ROPA ━━━━━━━━━━
  'ropa': [
    { field_key: 'prenda', field_label_es: 'Tipo de prenda', field_type: 'select',
      options: ['Camisa','Camiseta','Sudadera','Pantalón','Jean','Short','Vestido','Falda','Chamarra','Saco','Traje','Conjunto','Ropa interior','Pijama','Deportiva','Otro'],
      ai_can_suggest: true, sort_order: 1 },
    { field_key: 'talla', field_label_es: 'Talla', field_type: 'select',
      options: ['XS','S','M','L','XL','XXL','XXXL','Única'],
      is_required: true, user_must_fill: true, sort_order: 2 },
    { field_key: 'genero', field_label_es: 'Género', field_type: 'select',
      options: ['Hombre','Mujer','Niño','Niña','Bebé','Unisex'],
      ai_can_suggest: true, sort_order: 3 },
    { field_key: 'marca', field_label_es: 'Marca', field_type: 'text',
      ai_can_suggest: true, sort_order: 4 },
    { field_key: 'condicion', field_label_es: 'Condición', field_type: 'select',
      options: ['Nuevo con etiqueta','Nuevo sin etiqueta','Usado - excelente','Usado - bueno','Usado - regular'],
      is_required: true, user_must_fill: true, sort_order: 5 },
    { field_key: 'color', field_label_es: 'Color', field_type: 'text',
      ai_can_suggest: true, sort_order: 6 },
    { field_key: 'material', field_label_es: 'Material', field_type: 'text', placeholder_es: 'Algodón, mezclilla',
      ai_can_suggest: true, sort_order: 7 },
    { field_key: 'descripcion', field_label_es: 'Descripción', field_type: 'textarea',
      ai_can_suggest: true, ai_variants_count: 3, sort_order: 8 },
  ],

  // ━━━━━━━━━━ HOGAR ━━━━━━━━━━
  'hogar': [
    { field_key: 'tipo', field_label_es: 'Tipo de artículo', field_type: 'select',
      options: ['Muebles','Decoración','Cocina','Electrodoméstico','Jardín','Limpieza','Iluminación','Textil','Herramientas','Otro'],
      is_required: true, user_must_fill: true, ai_can_suggest: true, sort_order: 1 },
    { field_key: 'marca', field_label_es: 'Marca', field_type: 'text',
      ai_can_suggest: true, sort_order: 2 },
    { field_key: 'modelo', field_label_es: 'Modelo', field_type: 'text',
      ai_can_suggest: true, sort_order: 3 },
    { field_key: 'condicion', field_label_es: 'Condición', field_type: 'select',
      options: ['Nuevo','Como nuevo','Usado - bueno','Usado - regular','Para reparar'],
      is_required: true, user_must_fill: true, sort_order: 4 },
    { field_key: 'color', field_label_es: 'Color', field_type: 'text',
      ai_can_suggest: true, sort_order: 5 },
    { field_key: 'dimensiones', field_label_es: 'Dimensiones aprox', field_type: 'text', placeholder_es: '120x80x60 cm',
      ai_can_suggest: true, sort_order: 6 },
    { field_key: 'material', field_label_es: 'Material', field_type: 'text',
      ai_can_suggest: true, sort_order: 7 },
    { field_key: 'descripcion', field_label_es: 'Descripción', field_type: 'textarea',
      ai_can_suggest: true, ai_variants_count: 3, sort_order: 8 },
  ],

  // ━━━━━━━━━━ AUTOPARTES ━━━━━━━━━━
  'autopartes': [
    { field_key: 'tipo_parte', field_label_es: 'Tipo de parte', field_type: 'select',
      options: ['Motor','Transmisión','Suspensión','Frenos','Carrocería','Eléctrico','Filtro','Llantas','Rines','Llaves','Bujías','Banda','Bomba','Batería','Faro','Espejo','Otro'],
      is_required: true, user_must_fill: true, ai_can_suggest: true, sort_order: 1 },
    { field_key: 'marca_parte', field_label_es: 'Marca de la parte', field_type: 'text', placeholder_es: 'K&N, Bosch, ACDelco',
      user_must_fill: true, ai_can_suggest: true, sort_order: 2 },
    { field_key: 'numero_parte', field_label_es: 'Número de parte (OEM/NPN)', field_type: 'text', placeholder_es: 'HP-2009',
      user_must_fill: true, ai_can_suggest: true, sort_order: 3 },
    { field_key: 'marca_vehiculo_compatible', field_label_es: 'Marca de vehículo compatible', field_type: 'text',
      placeholder_es: 'Toyota, Honda, Ford', user_must_fill: true, ai_can_suggest: true, sort_order: 4 },
    { field_key: 'modelos_compatibles', field_label_es: 'Modelos compatibles', field_type: 'text',
      placeholder_es: 'Civic 06-11, Accord 08-12', ai_can_suggest: true, sort_order: 5 },
    { field_key: 'condicion', field_label_es: 'Condición', field_type: 'select',
      options: ['Nuevo','Reconstruido','Usado - funcional','Usado - garantía','Para piezas'],
      is_required: true, user_must_fill: true, sort_order: 6 },
    { field_key: 'descripcion', field_label_es: 'Descripción técnica', field_type: 'textarea',
      ai_can_suggest: true, ai_variants_count: 2, sort_order: 7 },
  ],

  // ━━━━━━━━━━ JUGUETES ━━━━━━━━━━
  'juguetes': [
    { field_key: 'nombre_juguete', field_label_es: 'Nombre del juguete', field_type: 'text',
      is_required: true, user_must_fill: true, ai_can_suggest: true, sort_order: 1 },
    { field_key: 'marca', field_label_es: 'Marca', field_type: 'text', placeholder_es: 'Lego, Hot Wheels, Mattel',
      ai_can_suggest: true, sort_order: 2 },
    { field_key: 'edad_recomendada', field_label_es: 'Edad recomendada', field_type: 'select',
      options: ['0-1 año','1-3 años','3-5 años','5-7 años','7-12 años','12+','Todas las edades'],
      is_required: true, user_must_fill: true, ai_can_suggest: true, sort_order: 3 },
    { field_key: 'tipo', field_label_es: 'Tipo', field_type: 'select',
      options: ['Educativo','Bloques','Muñecas','Vehículos','Acción','Peluche','Juego de mesa','Electrónico','Exterior','Arte','Otro'],
      ai_can_suggest: true, sort_order: 4 },
    { field_key: 'usa_baterias', field_label_es: 'Usa baterías', field_type: 'boolean',
      ai_can_suggest: true, sort_order: 5 },
    { field_key: 'condicion', field_label_es: 'Condición', field_type: 'select',
      options: ['Nuevo en caja','Como nuevo','Usado - excelente','Usado - bueno','Usado - regular'],
      is_required: true, user_must_fill: true, sort_order: 6 },
    { field_key: 'descripcion', field_label_es: 'Descripción', field_type: 'textarea',
      ai_can_suggest: true, ai_variants_count: 3, sort_order: 7 },
  ],

  // ━━━━━━━━━━ BELLEZA ━━━━━━━━━━
  'belleza': [
    { field_key: 'tipo_producto', field_label_es: 'Tipo de producto', field_type: 'select',
      options: ['Maquillaje','Skincare','Cabello','Perfume','Uñas','Herramienta','Higiene','Otro'],
      is_required: true, user_must_fill: true, ai_can_suggest: true, sort_order: 1 },
    { field_key: 'marca', field_label_es: 'Marca', field_type: 'text', placeholder_es: 'MAC, Maybelline, etc',
      user_must_fill: true, ai_can_suggest: true, sort_order: 2 },
    { field_key: 'nombre_producto', field_label_es: 'Nombre del producto', field_type: 'text',
      is_required: true, user_must_fill: true, ai_can_suggest: true, sort_order: 3 },
    { field_key: 'cantidad_volumen', field_label_es: 'Cantidad / volumen', field_type: 'text', placeholder_es: '100ml, 30g',
      ai_can_suggest: true, sort_order: 4 },
    { field_key: 'condicion', field_label_es: 'Condición', field_type: 'select',
      options: ['Nuevo sellado','Nuevo sin caja','Usado <30%','Usado 30-50%','Usado >50%'],
      is_required: true, user_must_fill: true, sort_order: 5 },
    { field_key: 'tono_color', field_label_es: 'Tono / color', field_type: 'text',
      ai_can_suggest: true, sort_order: 6 },
    { field_key: 'caducidad', field_label_es: 'Caducidad', field_type: 'date',
      user_must_fill: false, ai_can_suggest: false, sort_order: 7 },
    { field_key: 'descripcion', field_label_es: 'Descripción', field_type: 'textarea',
      ai_can_suggest: true, ai_variants_count: 2, sort_order: 8 },
  ],
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const dbUrl = Deno.env.get('SUPABASE_DB_URL')!
    const { Client } = await import("https://deno.land/x/postgres@v0.17.0/mod.ts")
    const client = new Client(dbUrl)
    await client.connect()
    const log: string[] = []

    // Get category_id for each slug
    const cats = await client.queryObject<{id: number; slug: string}>(`
      SELECT id, slug FROM product_categories
      WHERE slug = ANY($1)
    `, [Object.keys(SCHEMAS)])

    const slugToId = new Map(cats.rows.map(c => [c.slug, c.id]))

    for (const [slug, fields] of Object.entries(SCHEMAS)) {
      const catId = slugToId.get(slug)
      if (!catId) {
        log.push(`SKIP "${slug}": category not found`)
        continue
      }

      let inserted = 0
      let skipped = 0
      for (const f of fields) {
        try {
          const r = await client.queryArray(
            `INSERT INTO category_field_schemas
             (category_id, field_key, field_label_es, field_label_en, field_type, options,
              placeholder_es, is_required, user_must_fill, ai_can_suggest, ai_variants_count, sort_order)
             VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
             ON CONFLICT (category_id, field_key) DO UPDATE SET
               field_label_es = EXCLUDED.field_label_es,
               field_type = EXCLUDED.field_type,
               options = EXCLUDED.options,
               placeholder_es = EXCLUDED.placeholder_es,
               is_required = EXCLUDED.is_required,
               user_must_fill = EXCLUDED.user_must_fill,
               ai_can_suggest = EXCLUDED.ai_can_suggest,
               ai_variants_count = EXCLUDED.ai_variants_count,
               sort_order = EXCLUDED.sort_order`,
            [
              catId, f.field_key, f.field_label_es, f.field_label_en ?? null, f.field_type,
              f.options ? JSON.stringify(f.options) : null,
              f.placeholder_es ?? null,
              f.is_required ?? false, f.user_must_fill ?? false, f.ai_can_suggest ?? true,
              f.ai_variants_count ?? 1, f.sort_order,
            ]
          )
          if (r.rowCount) inserted++
          else skipped++
        } catch (e) {
          log.push(`  "${slug}.${f.field_key}" ERROR: ${(e as Error).message}`)
        }
      }
      log.push(`${slug}: ${fields.length} fields (${inserted} inserted/updated)`)
    }

    // Verify storage bucket policies on marketplace-products
    try {
      const policies = await client.queryObject<{policyname: string; cmd: string}>(`
        SELECT policyname, cmd FROM pg_policies
        WHERE schemaname = 'storage' AND tablename = 'objects'
        AND (qual::text LIKE '%marketplace-products%' OR with_check::text LIKE '%marketplace-products%')
      `)
      log.push('')
      log.push(`storage bucket marketplace-products policies: ${policies.rows.length}`)
      for (const p of policies.rows) {
        log.push(`  ${p.policyname} (${p.cmd})`)
      }
      if (policies.rows.length === 0) {
        log.push('  WARNING: no specific policies — fotos podrian no estar protegidas')
      }
    } catch (e) {
      log.push(`storage check error: ${(e as Error).message}`)
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
