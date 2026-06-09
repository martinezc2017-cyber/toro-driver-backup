// Edge Function: seed-remaining-schemas
// Seeds the 14 categories that didn't get a schema in the initial seed.
// Pairs with seed-category-schemas (8 core categories already seeded).

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

type Field = {
  field_key: string
  field_label_es: string
  field_type: 'text' | 'number' | 'select' | 'multi_select' | 'date' | 'boolean' | 'textarea'
  options?: string[]
  placeholder_es?: string
  is_required?: boolean
  user_must_fill?: boolean
  ai_can_suggest?: boolean
  ai_variants_count?: number
  sort_order: number
}

const SCHEMAS: Record<string, Field[]> = {
  // ━━━━━━━━━━ CALZADO ━━━━━━━━━━
  'calzado': [
    { field_key: 'tipo_calzado', field_label_es: 'Tipo de calzado', field_type: 'select',
      options: ['Deportivo','Casual','Formal','Bota','Sandalia','Tacón','Infantil','Trabajo','Otro'],
      ai_can_suggest: true, sort_order: 1 },
    { field_key: 'marca', field_label_es: 'Marca', field_type: 'text', placeholder_es: 'Nike, Adidas, Vans',
      ai_can_suggest: true, sort_order: 2 },
    { field_key: 'modelo', field_label_es: 'Modelo / línea', field_type: 'text', placeholder_es: 'Air Force 1, Stan Smith',
      ai_can_suggest: true, sort_order: 3 },
    { field_key: 'talla_us', field_label_es: 'Talla (US)', field_type: 'text', placeholder_es: '9.5',
      is_required: true, user_must_fill: true, sort_order: 4 },
    { field_key: 'talla_mx', field_label_es: 'Talla (MX)', field_type: 'text',
      ai_can_suggest: true, sort_order: 5 },
    { field_key: 'genero', field_label_es: 'Género', field_type: 'select',
      options: ['Hombre','Mujer','Unisex','Niño','Niña'], ai_can_suggest: true, sort_order: 6 },
    { field_key: 'color_principal', field_label_es: 'Color principal', field_type: 'text',
      ai_can_suggest: true, sort_order: 7 },
    { field_key: 'condicion', field_label_es: 'Condición', field_type: 'select',
      options: ['Nuevo con caja','Nuevo sin caja','Como nuevo','Usado - excelente','Usado - bueno','Usado - regular'],
      is_required: true, user_must_fill: true, sort_order: 8 },
    { field_key: 'descripcion', field_label_es: 'Descripción', field_type: 'textarea',
      ai_can_suggest: true, ai_variants_count: 3, sort_order: 9 },
  ],

  // ━━━━━━━━━━ VIDEOJUEGOS ━━━━━━━━━━
  'videojuegos': [
    { field_key: 'tipo', field_label_es: 'Tipo', field_type: 'select',
      options: ['Consola','Videojuego','Control','Accesorio','VR','Retro / Vintage','Combo / Setup'],
      is_required: true, user_must_fill: true, ai_can_suggest: true, sort_order: 1 },
    { field_key: 'plataforma', field_label_es: 'Plataforma', field_type: 'select',
      options: ['PS5','PS4','PS3','Xbox Series X/S','Xbox One','Xbox 360','Nintendo Switch','Nintendo 3DS','PC','Otro'],
      ai_can_suggest: true, sort_order: 2 },
    { field_key: 'marca', field_label_es: 'Marca', field_type: 'text',
      placeholder_es: 'Sony, Microsoft, Nintendo',
      ai_can_suggest: true, sort_order: 3 },
    { field_key: 'modelo', field_label_es: 'Modelo específico', field_type: 'text',
      placeholder_es: 'PS4 Pro 1TB, Switch OLED',
      ai_can_suggest: true, sort_order: 4 },
    { field_key: 'condicion', field_label_es: 'Condición', field_type: 'select',
      options: ['Nuevo sellado','Como nuevo','Usado - excelente','Usado - bueno','Usado - regular','Para reparar'],
      is_required: true, user_must_fill: true, sort_order: 5 },
    { field_key: 'incluye', field_label_es: 'Incluye accesorios', field_type: 'multi_select',
      options: ['Cable HDMI','Cable poder','1 control','2 controles','Caja original','Juegos','Headset','Memory card'],
      ai_can_suggest: true, sort_order: 6 },
    { field_key: 'descripcion', field_label_es: 'Descripción', field_type: 'textarea',
      ai_can_suggest: true, ai_variants_count: 3, sort_order: 7 },
  ],

  // ━━━━━━━━━━ DEPORTES ━━━━━━━━━━
  'deportes': [
    { field_key: 'tipo_deporte', field_label_es: 'Deporte', field_type: 'select',
      options: ['Fútbol','Béisbol','Baloncesto','Gym/Fitness','Ciclismo','Boxeo','Yoga','Natación','Tenis','Camping/Outdoor','Pesca','Caza','Otro'],
      is_required: true, user_must_fill: true, ai_can_suggest: true, sort_order: 1 },
    { field_key: 'tipo_articulo', field_label_es: 'Tipo de artículo', field_type: 'select',
      options: ['Pelota / balón','Ropa','Calzado deportivo','Equipo de protección','Pesas / mancuernas','Bicicleta','Patines','Raqueta','Casco','Otro'],
      ai_can_suggest: true, sort_order: 2 },
    { field_key: 'marca', field_label_es: 'Marca', field_type: 'text',
      ai_can_suggest: true, sort_order: 3 },
    { field_key: 'condicion', field_label_es: 'Condición', field_type: 'select',
      options: ['Nuevo','Como nuevo','Usado - bueno','Usado - regular','Para reparar'],
      is_required: true, user_must_fill: true, sort_order: 4 },
    { field_key: 'talla', field_label_es: 'Talla / tamaño', field_type: 'text',
      ai_can_suggest: true, sort_order: 5 },
    { field_key: 'descripcion', field_label_es: 'Descripción', field_type: 'textarea',
      ai_can_suggest: true, ai_variants_count: 3, sort_order: 6 },
  ],

  // ━━━━━━━━━━ SALUD Y FARMACIA ━━━━━━━━━━
  'salud': [
    { field_key: 'tipo_producto', field_label_es: 'Tipo', field_type: 'select',
      options: ['Suplemento','Vitamina','Medicamento OTC','Material médico','Higiene','Cuidado personal','Equipo médico','Otro'],
      is_required: true, user_must_fill: true, ai_can_suggest: true, sort_order: 1 },
    { field_key: 'marca', field_label_es: 'Marca', field_type: 'text',
      ai_can_suggest: true, sort_order: 2 },
    { field_key: 'nombre_producto', field_label_es: 'Nombre del producto', field_type: 'text',
      is_required: true, user_must_fill: true, ai_can_suggest: true, sort_order: 3 },
    { field_key: 'presentacion', field_label_es: 'Presentación', field_type: 'text',
      placeholder_es: '60 cápsulas, 100ml',
      ai_can_suggest: true, sort_order: 4 },
    { field_key: 'caducidad', field_label_es: 'Caducidad', field_type: 'date',
      user_must_fill: true, ai_can_suggest: false, sort_order: 5 },
    { field_key: 'condicion', field_label_es: 'Condición', field_type: 'select',
      options: ['Nuevo sellado','Nuevo sin caja','Usado'],
      is_required: true, user_must_fill: true, sort_order: 6 },
    { field_key: 'descripcion', field_label_es: 'Descripción', field_type: 'textarea',
      ai_can_suggest: true, ai_variants_count: 2, sort_order: 7 },
  ],

  // ━━━━━━━━━━ MASCOTAS ━━━━━━━━━━
  'mascotas': [
    { field_key: 'animal', field_label_es: 'Para qué animal', field_type: 'select',
      options: ['Perro','Gato','Ave','Pez','Roedor','Reptil','Conejo','Caballo','Otro'],
      is_required: true, user_must_fill: true, ai_can_suggest: true, sort_order: 1 },
    { field_key: 'tipo', field_label_es: 'Tipo de artículo', field_type: 'select',
      options: ['Comida / alimento','Juguete','Cama / casa','Correa / arnés','Higiene','Acuario / jaula','Comedero','Medicamento','Otro'],
      ai_can_suggest: true, sort_order: 2 },
    { field_key: 'marca', field_label_es: 'Marca', field_type: 'text',
      ai_can_suggest: true, sort_order: 3 },
    { field_key: 'tamano', field_label_es: 'Talla / tamaño', field_type: 'select',
      options: ['XS','S','M','L','XL','N/A'],
      ai_can_suggest: true, sort_order: 4 },
    { field_key: 'condicion', field_label_es: 'Condición', field_type: 'select',
      options: ['Nuevo','Como nuevo','Usado - bueno','Usado - regular'],
      is_required: true, user_must_fill: true, sort_order: 5 },
    { field_key: 'descripcion', field_label_es: 'Descripción', field_type: 'textarea',
      ai_can_suggest: true, ai_variants_count: 2, sort_order: 6 },
  ],

  // ━━━━━━━━━━ BEBÉS Y NIÑOS ━━━━━━━━━━
  'bebes-ninos': [
    { field_key: 'tipo_articulo', field_label_es: 'Tipo', field_type: 'select',
      options: ['Ropa','Carriola','Cuna','Silla auto','Juguete','Pañal','Biberón','Mochila','Comida bebé','Otro'],
      is_required: true, user_must_fill: true, ai_can_suggest: true, sort_order: 1 },
    { field_key: 'edad_rango', field_label_es: 'Edad recomendada', field_type: 'select',
      options: ['Recién nacido','0-6 meses','6-12 meses','1-2 años','2-4 años','4-8 años','8-12 años','12+'],
      ai_can_suggest: true, sort_order: 2 },
    { field_key: 'marca', field_label_es: 'Marca', field_type: 'text',
      ai_can_suggest: true, sort_order: 3 },
    { field_key: 'condicion', field_label_es: 'Condición', field_type: 'select',
      options: ['Nuevo','Como nuevo','Usado - excelente','Usado - bueno','Usado - regular'],
      is_required: true, user_must_fill: true, sort_order: 4 },
    { field_key: 'descripcion', field_label_es: 'Descripción', field_type: 'textarea',
      ai_can_suggest: true, ai_variants_count: 3, sort_order: 5 },
  ],

  // ━━━━━━━━━━ FRUTAS Y VERDURAS ━━━━━━━━━━
  'frutas-verduras': [
    { field_key: 'producto', field_label_es: 'Producto', field_type: 'text',
      placeholder_es: 'Mango, lechuga, tomate',
      is_required: true, user_must_fill: true, ai_can_suggest: true, sort_order: 1 },
    { field_key: 'tipo', field_label_es: 'Tipo', field_type: 'select',
      options: ['Fruta','Verdura','Hierba','Otro'], ai_can_suggest: true, sort_order: 2 },
    { field_key: 'origen', field_label_es: 'Origen', field_type: 'select',
      options: ['Local','Regional','Importado','Orgánico'], ai_can_suggest: true, sort_order: 3 },
    { field_key: 'unidad_venta', field_label_es: 'Unidad de venta', field_type: 'select',
      options: ['Pieza','Kilo','Manojo','Bolsa','Caja','Atado'],
      is_required: true, user_must_fill: true, sort_order: 4 },
    { field_key: 'cantidad_disponible', field_label_es: 'Cantidad disponible', field_type: 'number',
      user_must_fill: true, sort_order: 5 },
    { field_key: 'descripcion', field_label_es: 'Descripción', field_type: 'textarea',
      ai_can_suggest: true, ai_variants_count: 2, sort_order: 6 },
  ],

  // ━━━━━━━━━━ CARNICERÍA ━━━━━━━━━━
  'carniceria': [
    { field_key: 'tipo_carne', field_label_es: 'Tipo de carne', field_type: 'select',
      options: ['Res','Cerdo','Pollo','Pavo','Borrego','Cabra','Pescado','Mariscos','Otra'],
      is_required: true, user_must_fill: true, ai_can_suggest: true, sort_order: 1 },
    { field_key: 'corte', field_label_es: 'Corte', field_type: 'text',
      placeholder_es: 'Arrachera, costilla, milanesa',
      ai_can_suggest: true, sort_order: 2 },
    { field_key: 'unidad_venta', field_label_es: 'Unidad', field_type: 'select',
      options: ['Kilo','½ Kilo','Pieza','Bandeja'], is_required: true, user_must_fill: true, sort_order: 3 },
    { field_key: 'estado', field_label_es: 'Estado', field_type: 'select',
      options: ['Fresco','Congelado','Marinado','Cocido'], ai_can_suggest: true, sort_order: 4 },
    { field_key: 'descripcion', field_label_es: 'Descripción', field_type: 'textarea',
      ai_can_suggest: true, ai_variants_count: 2, sort_order: 5 },
  ],

  // ━━━━━━━━━━ ABARROTES ━━━━━━━━━━
  'abarrotes': [
    { field_key: 'nombre_producto', field_label_es: 'Nombre', field_type: 'text',
      is_required: true, user_must_fill: true, ai_can_suggest: true, sort_order: 1 },
    { field_key: 'marca', field_label_es: 'Marca', field_type: 'text',
      ai_can_suggest: true, sort_order: 2 },
    { field_key: 'tipo', field_label_es: 'Tipo', field_type: 'select',
      options: ['Lácteo','Embutido','Conservas','Pasta / arroz','Granos','Limpieza','Aceite','Especias','Cereales','Otro'],
      ai_can_suggest: true, sort_order: 3 },
    { field_key: 'presentacion', field_label_es: 'Presentación', field_type: 'text',
      placeholder_es: '500g, 1L, paquete 6 pzs',
      ai_can_suggest: true, sort_order: 4 },
    { field_key: 'caducidad', field_label_es: 'Caducidad', field_type: 'date',
      user_must_fill: true, ai_can_suggest: false, sort_order: 5 },
    { field_key: 'descripcion', field_label_es: 'Descripción', field_type: 'textarea',
      ai_can_suggest: true, ai_variants_count: 2, sort_order: 6 },
  ],

  // ━━━━━━━━━━ POSTRES ━━━━━━━━━━
  'postres': [
    { field_key: 'nombre_postre', field_label_es: 'Nombre del postre', field_type: 'text',
      is_required: true, user_must_fill: true, ai_can_suggest: true, sort_order: 1 },
    { field_key: 'tipo', field_label_es: 'Tipo', field_type: 'select',
      options: ['Pastel','Gelatina','Galleta','Cupcake','Pay','Helado','Postre tradicional','Otro'],
      ai_can_suggest: true, sort_order: 2 },
    { field_key: 'porciones', field_label_es: 'Porciones', field_type: 'number',
      is_required: true, user_must_fill: true, sort_order: 3 },
    { field_key: 'sabor_principal', field_label_es: 'Sabor', field_type: 'text',
      placeholder_es: 'Chocolate, fresa, vainilla', ai_can_suggest: true, sort_order: 4 },
    { field_key: 'alergenos', field_label_es: 'Alérgenos', field_type: 'multi_select',
      options: ['Gluten','Lácteos','Huevo','Nueces','Soya'], ai_can_suggest: true, sort_order: 5 },
    { field_key: 'descripcion', field_label_es: 'Descripción', field_type: 'textarea',
      ai_can_suggest: true, ai_variants_count: 3, sort_order: 6 },
  ],

  // ━━━━━━━━━━ BEBIDAS ━━━━━━━━━━
  'bebidas': [
    { field_key: 'tipo_bebida', field_label_es: 'Tipo', field_type: 'select',
      options: ['Agua','Refresco','Jugo natural','Smoothie','Café','Té','Cerveza','Vino','Licor','Otra'],
      is_required: true, user_must_fill: true, ai_can_suggest: true, sort_order: 1 },
    { field_key: 'marca', field_label_es: 'Marca', field_type: 'text',
      ai_can_suggest: true, sort_order: 2 },
    { field_key: 'tamano_ml', field_label_es: 'Tamaño (ml)', field_type: 'number',
      ai_can_suggest: true, sort_order: 3 },
    { field_key: 'contiene_alcohol', field_label_es: 'Contiene alcohol', field_type: 'boolean',
      ai_can_suggest: true, sort_order: 4 },
    { field_key: 'descripcion', field_label_es: 'Descripción', field_type: 'textarea',
      ai_can_suggest: true, ai_variants_count: 2, sort_order: 5 },
  ],

  // ━━━━━━━━━━ SERVICIOS ━━━━━━━━━━
  'servicios': [
    { field_key: 'tipo_servicio', field_label_es: 'Tipo de servicio', field_type: 'select',
      options: ['Plomería','Electricidad','Mecánica','Limpieza','Belleza','Construcción','Jardinería','Cómputo','Mudanza','Clases / tutorías','Médico','Otro'],
      is_required: true, user_must_fill: true, sort_order: 1 },
    { field_key: 'nombre_servicio', field_label_es: 'Nombre / título', field_type: 'text',
      is_required: true, user_must_fill: true, sort_order: 2 },
    { field_key: 'cobertura', field_label_es: 'Cobertura', field_type: 'select',
      options: ['A domicilio','En mi taller / local','Ambas'],
      ai_can_suggest: true, sort_order: 3 },
    { field_key: 'precio_unidad', field_label_es: 'Unidad de cobro', field_type: 'select',
      options: ['Por hora','Por servicio','Por proyecto','Por visita','Por kg / pieza'],
      is_required: true, user_must_fill: true, sort_order: 4 },
    { field_key: 'experiencia_anos', field_label_es: 'Años de experiencia', field_type: 'number',
      user_must_fill: true, sort_order: 5 },
    { field_key: 'descripcion', field_label_es: 'Descripción', field_type: 'textarea',
      ai_can_suggest: true, ai_variants_count: 3, sort_order: 6 },
  ],

  // ━━━━━━━━━━ INDUSTRIAL ━━━━━━━━━━
  'industrial': [
    { field_key: 'tipo', field_label_es: 'Tipo de equipo', field_type: 'select',
      options: ['Maquinaria','Herramienta industrial','Material de construcción','Tubería','Andamio','Soldadura','Compresor','Generador','Refrigeración industrial','Otro'],
      is_required: true, user_must_fill: true, ai_can_suggest: true, sort_order: 1 },
    { field_key: 'marca', field_label_es: 'Marca', field_type: 'text',
      ai_can_suggest: true, sort_order: 2 },
    { field_key: 'modelo', field_label_es: 'Modelo', field_type: 'text',
      ai_can_suggest: true, sort_order: 3 },
    { field_key: 'capacidad_o_potencia', field_label_es: 'Capacidad / potencia', field_type: 'text',
      placeholder_es: '5HP, 220V, 100 kg/h',
      ai_can_suggest: true, sort_order: 4 },
    { field_key: 'condicion', field_label_es: 'Condición', field_type: 'select',
      options: ['Nuevo','Seminuevo','Usado - bueno','Usado - regular','Para reparar'],
      is_required: true, user_must_fill: true, sort_order: 5 },
    { field_key: 'descripcion', field_label_es: 'Descripción técnica', field_type: 'textarea',
      ai_can_suggest: true, ai_variants_count: 2, sort_order: 6 },
  ],

  // ━━━━━━━━━━ OTROS (fallback genérico) ━━━━━━━━━━
  'otros': [
    { field_key: 'nombre_producto', field_label_es: 'Nombre del producto', field_type: 'text',
      is_required: true, user_must_fill: true, ai_can_suggest: true, sort_order: 1 },
    { field_key: 'marca', field_label_es: 'Marca', field_type: 'text',
      ai_can_suggest: true, sort_order: 2 },
    { field_key: 'condicion', field_label_es: 'Condición', field_type: 'select',
      options: ['Nuevo','Como nuevo','Usado - bueno','Usado - regular','Para reparar'],
      is_required: true, user_must_fill: true, sort_order: 3 },
    { field_key: 'color', field_label_es: 'Color', field_type: 'text',
      ai_can_suggest: true, sort_order: 4 },
    { field_key: 'descripcion', field_label_es: 'Descripción', field_type: 'textarea',
      ai_can_suggest: true, ai_variants_count: 2, sort_order: 5 },
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

    const cats = await client.queryObject<{ id: number; slug: string }>(`
      SELECT id, slug FROM product_categories WHERE slug = ANY($1)
    `, [Object.keys(SCHEMAS)])
    const slugToId = new Map(cats.rows.map(c => [c.slug, c.id]))

    for (const [slug, fields] of Object.entries(SCHEMAS)) {
      const catId = slugToId.get(slug)
      if (!catId) { log.push(`SKIP "${slug}": category not found`); continue }
      let inserted = 0
      for (const f of fields) {
        try {
          const r = await client.queryArray(
            `INSERT INTO category_field_schemas
             (category_id, field_key, field_label_es, field_type, options, placeholder_es,
              is_required, user_must_fill, ai_can_suggest, ai_variants_count, sort_order)
             VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
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
              catId, f.field_key, f.field_label_es, f.field_type,
              f.options ? JSON.stringify(f.options) : null,
              f.placeholder_es ?? null,
              f.is_required ?? false, f.user_must_fill ?? false,
              f.ai_can_suggest ?? true, f.ai_variants_count ?? 1, f.sort_order,
            ]
          )
          if (r.rowCount) inserted++
        } catch (e) {
          log.push(`ERR "${slug}.${f.field_key}": ${(e as Error).message}`)
        }
      }
      log.push(`${slug}: ${fields.length} fields (${inserted} touched)`)
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
