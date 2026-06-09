// Edge Function: ai-extract-product
// Receives photo + category_slug + user-provided fields.
// Reads category_field_schemas, asks Gemini to fill remaining fields + 3 description variants.
// Logs to ai_extraction_logs. Falls back to Groq when Gemini is rate-limited.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface ExtractRequest {
  vendor_id: string
  category_slug: string
  photo_urls: string[]            // one or more (we use up to 4)
  user_provided_fields?: Record<string, any>
  country_code?: string           // for price localization (default MX)
}

function extractJson(text: string): any {
  if (!text) return {}
  try { return JSON.parse(text) } catch {}
  const fenced = text.match(/```(?:json)?\s*([\s\S]+?)```/i)
  if (fenced) { try { return JSON.parse(fenced[1].trim()) } catch {} }
  const start = text.indexOf('{')
  const end = text.lastIndexOf('}')
  if (start !== -1 && end > start) {
    try { return JSON.parse(text.slice(start, end + 1)) } catch {}
  }
  return {}
}

// ━━━━━━━━━━ SANITIZATION ━━━━━━━━━━

// Reasonable price ceilings per category group (MXN). Anything above is clamped.
const PRICE_CEILING_MXN: Record<string, number> = {
  'automoviles': 5_000_000,
  'industrial': 5_000_000,
  'electronicos': 500_000,
  'hogar': 200_000,
  'comida-preparada': 5_000,
  'frutas-verduras': 2_000,
  'carniceria': 5_000,
  'abarrotes': 5_000,
  'postres': 3_000,
  'bebidas': 3_000,
  'ropa': 20_000,
  'calzado': 30_000,
  'belleza': 10_000,
  'salud': 20_000,
  'bebes-ninos': 30_000,
  'mascotas': 20_000,
  'autopartes': 200_000,
  'juguetes': 20_000,
  'deportes': 100_000,
  'videojuegos': 50_000,
  'servicios': 100_000,
  'otros': 100_000,
}

function clamp(n: number, min: number, max: number): number {
  if (!Number.isFinite(n)) return min
  return Math.max(min, Math.min(max, Math.round(n)))
}

function sanitizeExtraction(parsed: any, categorySlug: string): void {
  if (!parsed || typeof parsed !== 'object') return

  // 1) Trim title to 60 chars
  if (typeof parsed.title === 'string' && parsed.title.length > 60) {
    parsed.title = parsed.title.slice(0, 60).trim()
  }

  // 2) Clamp confidence to [0, 1]
  if (typeof parsed.confidence === 'number') {
    parsed.confidence = Math.max(0, Math.min(1, parsed.confidence))
  }

  // 3) Sanity-check prices: must be positive and within category ceiling
  const ceil = PRICE_CEILING_MXN[categorySlug] ?? 1_000_000
  for (const key of ['estimated_price_mxn', 'estimated_price_usd']) {
    const p = parsed[key]
    if (!p || typeof p !== 'object') continue
    const limit = key.endsWith('_usd') ? Math.round(ceil / 18) : ceil
    if (typeof p.min === 'number') p.min = clamp(p.min, 0, limit)
    if (typeof p.max === 'number') p.max = clamp(p.max, p.min ?? 0, limit)
    if (typeof p.suggested === 'number') p.suggested = clamp(p.suggested, p.min ?? 0, p.max ?? limit)
    // If max < min, swap
    if (typeof p.min === 'number' && typeof p.max === 'number' && p.max < p.min) {
      const t = p.min; p.min = p.max; p.max = t
    }
  }

  // 4) Cap tags array length and string length
  if (Array.isArray(parsed.tags)) {
    parsed.tags = parsed.tags
      .filter((t: any) => typeof t === 'string' && t.length > 0)
      .slice(0, 10)
      .map((t: string) => t.slice(0, 30))
  }

  // 5) Cap description_variants
  if (Array.isArray(parsed.description_variants)) {
    parsed.description_variants = parsed.description_variants
      .filter((d: any) => typeof d === 'string' && d.length > 0)
      .slice(0, 3)
      .map((d: string) => d.slice(0, 500))
  }

  // 6) Cap missing_info
  if (Array.isArray(parsed.missing_info)) {
    parsed.missing_info = parsed.missing_info
      .filter((m: any) => typeof m === 'string' && m.length > 0)
      .slice(0, 8)
  }

  // 7) Detect "not a product" — title contains words like cielo/paisaje/persona
  const notProductPatterns = /\b(cielo|paisaje|atardecer|persona|gente|selfie|nada|vacio|borroso)\b/i
  if (typeof parsed.title === 'string' && notProductPatterns.test(parsed.title)) {
    parsed.detected_product = false
    parsed.confidence = Math.min(parsed.confidence ?? 0.3, 0.3)
    parsed.missing_info = [
      'La foto no muestra un producto claro. Toma otra foto enfocando el producto, con buena luz y fondo neutro.',
      ...(Array.isArray(parsed.missing_info) ? parsed.missing_info : []),
    ].slice(0, 5)
  } else if (parsed.detected_product === undefined) {
    parsed.detected_product = (parsed.confidence ?? 0.5) >= 0.4
  }

  // 8) Default condition if missing
  if (!parsed.condition || typeof parsed.condition !== 'string') {
    parsed.condition = 'usado-bueno'
  }
}

const MAX_IMAGE_BYTES = 10 * 1024 * 1024
const MIN_IMAGE_BYTES = 5 * 1024
const ACCEPTED_MIMES = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'image/heic']

async function fetchImageAsBase64(url: string): Promise<{ data: string; mime: string }> {
  if (url.startsWith('data:')) {
    const m = url.match(/^data:([^;]+);base64,(.+)$/)
    if (!m) throw new Error('malformed data URL')
    const mime = m[1].toLowerCase()
    if (!ACCEPTED_MIMES.some(am => mime.startsWith(am))) {
      throw new Error(`unsupported image format: ${mime}`)
    }
    const data = m[2]
    const approxBytes = (data.length * 3) / 4
    if (approxBytes < MIN_IMAGE_BYTES) throw new Error('image too small')
    if (approxBytes > MAX_IMAGE_BYTES) throw new Error(`image too large (${Math.round(approxBytes / 1024 / 1024)}MB > 10MB)`)
    return { mime, data }
  }
  const resp = await fetch(url)
  if (!resp.ok) throw new Error(`fetch image failed: ${resp.status}`)
  const buf = await resp.arrayBuffer()
  if (buf.byteLength < MIN_IMAGE_BYTES) throw new Error('image too small')
  if (buf.byteLength > MAX_IMAGE_BYTES) throw new Error(`image too large (${Math.round(buf.byteLength / 1024 / 1024)}MB > 10MB)`)
  const mime = (resp.headers.get('content-type') ?? 'image/jpeg').toLowerCase()
  if (!ACCEPTED_MIMES.some(am => mime.startsWith(am))) {
    throw new Error(`unsupported image format: ${mime}`)
  }
  return { mime, data: btoa(String.fromCharCode(...new Uint8Array(buf))) }
}

function buildPrompt(opts: {
  category_slug: string
  schema: Array<any>           // kept as a SOFT HINT only, not a constraint
  user_fields: Record<string, any>
  country_code: string
}): string {
  const market = opts.country_code === 'US' ? 'Phoenix, AZ, USA' : 'Mexicali, BC, Mexico'
  const currency = opts.country_code === 'US' ? 'USD' : 'MXN'

  const hintFields = opts.schema.filter(f => f.ai_can_suggest).map(f => f.field_key).slice(0, 8)
  const hintsLine = hintFields.length
    ? `\nReferencia de campos comunes de esta categoria: ${hintFields.join(', ')}. NO te limites a estos, agrega los que apliquen al producto especifico.\n`
    : ''

  const userFieldsLine = Object.keys(opts.user_fields).length
    ? `\nEl vendedor ya escribio estos valores (NO los cambies, usalos como verdad):\n${JSON.stringify(opts.user_fields, null, 2)}\n`
    : ''

  return `Eres un experto valuador y catalogador del marketplace TORO en ${market}.
Categoria sugerida: "${opts.category_slug}" (es solo una pista).

INSTRUCCIONES:
1. Examina la foto en MAXIMO detalle. Identifica EXACTAMENTE que producto es:
   - Marca y modelo especifico (si es visible o reconocible)
   - Tipo/subtipo dentro de su categoria
   - Capacidad, tamaño, año, version, etc. todo lo que aplique
2. Genera los campos tecnicos QUE TENGAN SENTIDO para ESTE producto en particular.
   Un aire acondicionado tiene BTU + voltaje + refrigerante + tipo.
   Un telefono tiene RAM + almacenamiento + pantalla + chip.
   Un camion tiene marca + modelo + ano + transmision.
   Una molecula tendria formula + masa molar + estado.
   El sol tendria temperatura + composicion + tipo espectral.
   CADA producto es distinto. Inventa las keys que correspondan.
3. Estima precio de mercado REALISTA en ${market} basado en TODO lo que sabes del producto.
   Si reconoces modelo exacto, usa valor de mercado conocido. Si es generico, rango amplio.
4. Si la foto no muestra info critica (etiqueta, parte trasera, label de capacidad), dilo en missing_info.
${hintsLine}${userFieldsLine}
Devuelve SOLO JSON puro (sin markdown):
{
  "title": "<nombre corto y especifico del producto, max 60 chars>",
  "identified_product": "<descripcion tecnica de UNA frase, ej: 'Aire acondicionado de ventana LG modelo aproximado de 18,000 BTU' >",
  "confidence": <0.0 a 1.0>,
  "condition": "<nuevo|seminuevo|usado-bueno|usado-regular|para-reparar>",
  "attributes": {
    "<key1>": <value1>,
    "<key2>": <value2>,
    ...  // libre. Inventa las keys que correspondan al producto. Ejemplos:
         // AC: { "btu": 18000, "voltaje": "115V", "tipo": "ventana", "refrigerante": "R-410A" }
         // Telefono: { "ram_gb": 8, "storage_gb": 128, "chip": "A15", "color": "azul" }
         // Vehiculo: { "marca": "Kenworth", "modelo": "T680", "ano": 2018, "ejes": 3 }
  },
  "estimated_price_${currency.toLowerCase()}": { "min": <int>, "max": <int>, "suggested": <int> },
  "description_variants": [
    "<v1: ficha corta>",
    "<v2: anuncio largo>",
    "<v3: estilo redes sociales>"
  ],
  "tags": [<5-8 tags>],
  "missing_info": [<que info adicional pedirias al vendedor: "foto de etiqueta del modelo", "fecha de compra", "facturas", etc.>],
  "ai_notes": "<observacion clave en 1 frase>"
}`
}

async function callGemini(prompt: string, imgs: Array<{data: string; mime: string}>, apiKey: string) {
  const parts: any[] = [{ text: prompt }]
  for (const img of imgs) parts.push({ inline_data: { mime_type: img.mime, data: img.data } })

  const body = {
    contents: [{ parts }],
    generation_config: {
      response_mime_type: 'application/json',
      temperature: 0.3,
      // Enough for the model to "think" through product identification
      // and produce a complete JSON with technical attributes.
      max_output_tokens: 4000,
      thinking_config: { thinking_budget: 1500 },
    },
  }
  const resp = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`,
    { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) },
  )
  const json = await resp.json()
  if (!resp.ok) {
    const code = json?.error?.code
    const msg = json?.error?.message ?? 'gemini error'
    throw new Error(`gemini ${code}: ${msg}`)
  }
  const text = json.candidates?.[0]?.content?.parts?.[0]?.text ?? '{}'
  return {
    parsed: extractJson(text),
    tokens: (json.usageMetadata?.promptTokenCount ?? 0) + (json.usageMetadata?.candidatesTokenCount ?? 0),
    raw: text,
  }
}

async function callGroq(prompt: string, imgs: Array<{data: string; mime: string}>, apiKey: string) {
  const content: any[] = [{ type: 'text', text: prompt }]
  for (const img of imgs) {
    content.push({ type: 'image_url', image_url: { url: `data:${img.mime};base64,${img.data}` } })
  }
  const body = {
    model: 'meta-llama/llama-4-scout-17b-16e-instruct',
    messages: [{ role: 'user', content }],
    max_tokens: 2000,
    temperature: 0.2,
    response_format: { type: 'json_object' },
  }
  const resp = await fetch('https://api.groq.com/openai/v1/chat/completions', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
  const json = await resp.json()
  if (!resp.ok) throw new Error(`groq: ${json?.error?.message ?? resp.status}`)
  return {
    parsed: extractJson(json.choices?.[0]?.message?.content ?? '{}'),
    tokens: json.usage?.total_tokens ?? 0,
    raw: json.choices?.[0]?.message?.content,
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  const startTime = Date.now()
  const client = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    { auth: { autoRefreshToken: false, persistSession: false } }
  )

  try {
    const body = await req.json() as ExtractRequest

    if (!body.vendor_id || !body.category_slug) {
      return new Response(
        JSON.stringify({ success: false, error: 'vendor_id and category_slug required' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }
    const urls = (body.photo_urls ?? []).slice(0, 4)
    if (urls.length === 0) {
      return new Response(
        JSON.stringify({ success: false, error: 'photo_urls required' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    // 1) Load category + its parent group (for schema inheritance)
    const { data: cat, error: catErr } = await client
      .from('product_categories')
      .select('id, name_es, slug, parent_category_id')
      .eq('slug', body.category_slug)
      .maybeSingle()
    if (catErr || !cat) {
      return new Response(
        JSON.stringify({ success: false, error: `category ${body.category_slug} not found` }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 404 }
      )
    }

    // Pull fields from THIS category and (if any) its parent group — parent first, then child overrides
    const categoryIds: number[] = []
    if (cat.parent_category_id) categoryIds.push(cat.parent_category_id)
    categoryIds.push(cat.id)

    const { data: rawSchema, error: schemaErr } = await client
      .from('category_field_schemas')
      .select('field_key, field_label_es, field_type, options, is_required, user_must_fill, ai_can_suggest, ai_variants_count, category_id')
      .in('category_id', categoryIds)
      .order('sort_order')

    // Child fields override parent's when same field_key
    const fieldMap = new Map<string, any>()
    for (const f of (rawSchema ?? [])) {
      const existing = fieldMap.get(f.field_key)
      if (!existing || f.category_id === cat.id) {
        fieldMap.set(f.field_key, f)
      }
    }
    const schema = Array.from(fieldMap.values())

    if (schemaErr || schema.length === 0) {
      return new Response(
        JSON.stringify({
          success: false,
          error: `no schema defined for ${body.category_slug}. Run seed-category-schemas first.`,
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 404 }
      )
    }

    // 2) Build prompt + load images
    const prompt = buildPrompt({
      category_slug: body.category_slug,
      schema,
      user_fields: body.user_provided_fields ?? {},
      country_code: body.country_code ?? 'MX',
    })
    const imgs = await Promise.all(urls.map(fetchImageAsBase64))

    // 3) Call Gemini, fallback to Groq on rate limit
    const geminiKey = Deno.env.get('GEMINI_API_KEY') ?? ''
    const groqKey = Deno.env.get('GROQ_API_KEY') ?? ''

    let provider: 'gemini' | 'groq' = 'gemini'
    let fallback = false
    let result: { parsed: any; tokens: number; raw: any }
    let retries = 0
    const MAX_GEMINI_RETRIES = 2

    // Try Gemini with up to 2 retries on transient errors (with backoff),
    // then fall back to Groq only if all Gemini attempts failed.
    while (true) {
      try {
        if (!geminiKey) throw new Error('no gemini key')
        result = await callGemini(prompt, imgs, geminiKey)
        break
      } catch (e) {
        const msg = String(e).toLowerCase()
        const isTransient = msg.includes('503') || msg.includes('overloaded') || msg.includes('high demand')
          || msg.includes('unavailable') || msg.includes('500') || msg.includes('timeout')
        const isQuota = msg.includes('429') || msg.includes('quota') || msg.includes('rate')

        if (isTransient && retries < MAX_GEMINI_RETRIES) {
          retries++
          await new Promise(r => setTimeout(r, 1000 * retries))  // 1s, 2s backoff
          continue
        }
        // Fall back to Groq for any AI error if Gemini keeps failing
        if (groqKey && (isTransient || isQuota || msg.includes('no gemini key'))) {
          provider = 'groq'
          fallback = true
          result = await callGroq(prompt, imgs, groqKey)
          break
        }
        throw e
      }
    }

    // ━━━━━━━━━━ POST-PROCESSING & VALIDATION ━━━━━━━━━━
    sanitizeExtraction(result.parsed, body.category_slug)

    // 4) Merge user-provided fields (they win over AI)
    const merged = { ...result.parsed, ...(body.user_provided_fields ?? {}) }

    // 5) Log success
    try {
      await client.from('ai_extraction_logs').insert({
        vendor_id: body.vendor_id,
        category_slug: body.category_slug,
        photo_urls: urls,
        user_provided_fields: body.user_provided_fields ?? {},
        ai_provider: provider,
        ai_model: provider === 'gemini' ? 'gemini-2.5-flash' : 'meta-llama/llama-4-scout-17b-16e-instruct',
        ai_response: result.parsed,
        tokens_used: result.tokens,
        latency_ms: Date.now() - startTime,
        success: true,
        fallback_triggered: fallback,
      })
    } catch (_) { /* swallow */ }

    return new Response(
      JSON.stringify({
        success: true,
        category: cat,
        schema,
        fields: merged,
        provider,
        fallback_triggered: fallback,
        tokens_used: result.tokens,
        latency_ms: Date.now() - startTime,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    try {
      await client.from('ai_extraction_logs').insert({
        success: false,
        error_message: String(error),
        latency_ms: Date.now() - startTime,
      })
    } catch (_) {}
    return new Response(
      JSON.stringify({ success: false, error: String(error) }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
    )
  }
})
