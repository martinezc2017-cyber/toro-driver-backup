// Edge Function: ai-classify-bulk
// Classifies up to N photos into TORO marketplace categories using Gemini (primary)
// with Groq fallback. Enforces daily quota via check_and_increment_quota RPC.
// Logs every call to ai_extraction_logs + app_logs.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface ClassifyRequest {
  vendor_id: string
  photos: Array<{ url: string; id?: string }>  // photo URL (https or data:base64)
}

interface ClassifyResult {
  photo_id: string
  url: string
  category_slug: string | null
  confidence: number
  needs_review: boolean
  preview_caption: string
  error?: string
}

// Categories are grouped hierarchically to help the LLM stay specific.
// We classify into LEAF (child) categories; the parent group is derived after.
const CATEGORY_HIERARCHY: Record<string, { name: string; children: string[] }> = {
  'g-despensa': {
    name: 'Despensa y comida',
    children: ['comida-preparada', 'frutas-verduras', 'carniceria', 'abarrotes', 'postres', 'bebidas'],
  },
  'g-productos': {
    name: 'Productos generales',
    children: ['ropa', 'calzado', 'belleza', 'salud', 'bebes-ninos', 'mascotas', 'hogar', 'electronicos', 'juguetes', 'deportes', 'videojuegos'],
  },
  'g-vehiculos': {
    name: 'Vehículos',
    children: ['automoviles', 'autopartes'],
  },
  'g-otros': {
    name: 'Otros',
    children: ['servicios', 'industrial', 'otros'],
  },
}

const ALLOWED_SLUGS: string[] = Object.values(CATEGORY_HIERARCHY).flatMap(g => g.children)

const HIERARCHY_TEXT = Object.entries(CATEGORY_HIERARCHY)
  .map(([_, g]) => `  - ${g.name}: ${g.children.join(', ')}`)
  .join('\n')

const CLASSIFY_PROMPT = `Eres el clasificador del marketplace TORO (Mexicali, MX).

Estructura de categorias (grupo → hijas):
${HIERARCHY_TEXT}

Razona en 2 pasos:
1. Identifica primero el GRUPO al que pertenece la foto.
2. Luego escoge la HIJA mas especifica dentro de ese grupo.

Si la foto NO muestra un producto vendible (paisaje, persona, basura, etc), usa "otros".

Devuelve SOLO JSON sin markdown:
{
  "category_slug": "<una de las hijas>",
  "confidence": <0.0 a 1.0>,
  "preview_caption": "<descripcion corta del producto en 1 frase, max 80 chars>"
}`

/**
 * Jaccard-style similarity between two captions (0..1).
 * Used to detect when the same product is photographed multiple times,
 * so the UI can group them as ONE product with N photos instead of
 * creating N separate drafts.
 */
function captionSimilarity(a: string, b: string): number {
  return captionSimilarityDetailed(a, b).similarity
}

// List of short stopwords we never want to count as "shared meaning"
const STOPWORDS = new Set([
  'para','con','los','las','del','que','una','uno','est','esta','este','muy','pero',
  'cuando','tiene','tener','sobre','desde','como','hace','hacer','algo',
  'with','this','that','from','have','some','also','their','your',
])

function captionSimilarityDetailed(a: string, b: string): { similarity: number; sharedTokens: string[] } {
  if (!a || !b) return { similarity: 0, sharedTokens: [] }
  const norm = (s: string) => s.toLowerCase()
    .normalize('NFD').replace(/[̀-ͯ]/g, '')  // strip accents
    .replace(/[^a-z0-9\s]/g, ' ')
    .split(/\s+/)
    .filter(w => w.length >= 4 && !STOPWORDS.has(w))
  const tokensA = new Set(norm(a))
  const tokensB = new Set(norm(b))
  if (tokensA.size === 0 || tokensB.size === 0) return { similarity: 0, sharedTokens: [] }
  const shared: string[] = []
  for (const t of tokensA) if (tokensB.has(t)) shared.push(t)
  const union = tokensA.size + tokensB.size - shared.length
  return {
    similarity: union === 0 ? 0 : shared.length / union,
    sharedTokens: shared,
  }
}

const MAX_IMAGE_BYTES = 10 * 1024 * 1024  // 10 MB hard cap
const MIN_IMAGE_BYTES = 5 * 1024            // <5KB is almost certainly junk
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
    // base64 length ≈ bytes * 4/3
    const approxBytes = (data.length * 3) / 4
    if (approxBytes < MIN_IMAGE_BYTES) throw new Error('image too small (likely corrupted)')
    if (approxBytes > MAX_IMAGE_BYTES) throw new Error(`image too large (${Math.round(approxBytes / 1024 / 1024)}MB > 10MB)`)
    return { mime, data }
  }
  const resp = await fetch(url)
  if (!resp.ok) throw new Error(`fetch image failed: ${resp.status}`)
  const buf = await resp.arrayBuffer()
  if (buf.byteLength < MIN_IMAGE_BYTES) throw new Error('image too small (likely corrupted)')
  if (buf.byteLength > MAX_IMAGE_BYTES) throw new Error(`image too large (${Math.round(buf.byteLength / 1024 / 1024)}MB > 10MB)`)
  const mime = (resp.headers.get('content-type') ?? 'image/jpeg').toLowerCase()
  if (!ACCEPTED_MIMES.some(am => mime.startsWith(am))) {
    throw new Error(`unsupported image format: ${mime}`)
  }
  return { mime, data: btoa(String.fromCharCode(...new Uint8Array(buf))) }
}

async function classifyViaGemini(
  imgData: string,
  imgMime: string,
  apiKey: string,
): Promise<{ category_slug: string; confidence: number; preview_caption: string; tokens: number }> {
  const body = {
    contents: [{
      parts: [
        { text: CLASSIFY_PROMPT },
        { inline_data: { mime_type: imgMime, data: imgData } },
      ],
    }],
    generation_config: {
      response_mime_type: 'application/json',
      temperature: 0.1,
      max_output_tokens: 500,
      // Disable thinking for fast classification — no reasoning needed
      thinking_config: { thinking_budget: 0 },
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
  const parsed = extractJson(text)
  return {
    category_slug: ALLOWED_SLUGS.includes(parsed.category_slug) ? parsed.category_slug : 'otros',
    confidence: typeof parsed.confidence === 'number' ? parsed.confidence : 0.5,
    preview_caption: String(parsed.preview_caption ?? '').slice(0, 80),
    tokens: (json.usageMetadata?.promptTokenCount ?? 0) + (json.usageMetadata?.candidatesTokenCount ?? 0),
  }
}

// Robust JSON extractor: tolerates leading/trailing prose, markdown fences, etc.
function extractJson(text: string): any {
  if (!text) return {}
  // Try direct parse first (fast path when model respects JSON mode)
  try { return JSON.parse(text) } catch {}
  // Strip markdown fences
  const fenced = text.match(/```(?:json)?\s*([\s\S]+?)```/i)
  if (fenced) {
    try { return JSON.parse(fenced[1].trim()) } catch {}
  }
  // Find first { ... } balanced block
  const start = text.indexOf('{')
  const end = text.lastIndexOf('}')
  if (start !== -1 && end > start) {
    try { return JSON.parse(text.slice(start, end + 1)) } catch {}
  }
  return {}
}

async function classifyViaGroq(
  imgData: string,
  imgMime: string,
  apiKey: string,
): Promise<{ category_slug: string; confidence: number; preview_caption: string; tokens: number }> {
  const body = {
    model: 'meta-llama/llama-4-scout-17b-16e-instruct',
    messages: [{
      role: 'user',
      content: [
        { type: 'text', text: CLASSIFY_PROMPT },
        { type: 'image_url', image_url: { url: `data:${imgMime};base64,${imgData}` } },
      ],
    }],
    max_tokens: 200,
    temperature: 0.1,
    response_format: { type: 'json_object' },
  }
  const resp = await fetch('https://api.groq.com/openai/v1/chat/completions', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
  const json = await resp.json()
  if (!resp.ok) throw new Error(`groq: ${json?.error?.message ?? resp.status}`)
  const parsed = extractJson(json.choices?.[0]?.message?.content ?? '{}')
  return {
    category_slug: ALLOWED_SLUGS.includes(parsed.category_slug) ? parsed.category_slug : 'otros',
    confidence: typeof parsed.confidence === 'number' ? parsed.confidence : 0.5,
    preview_caption: String(parsed.preview_caption ?? '').slice(0, 80),
    tokens: json.usage?.total_tokens ?? 0,
  }
}

async function logToDb(
  client: any,
  entry: Record<string, any>,
): Promise<void> {
  try {
    await client.from('ai_extraction_logs').insert(entry)
  } catch (_) { /* swallow */ }
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
    const body = await req.json() as ClassifyRequest

    if (!body.vendor_id) {
      return new Response(
        JSON.stringify({ success: false, error: 'vendor_id required' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }
    const photos = Array.isArray(body.photos) ? body.photos : []
    if (photos.length === 0) {
      return new Response(
        JSON.stringify({ success: false, error: 'photos array required' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }
    if (photos.length > 10) {
      return new Response(
        JSON.stringify({
          success: false,
          error: 'max 10 photos per request',
          received: photos.length,
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    // === 1. Quota check ===
    const { data: quotaRows, error: quotaErr } = await client.rpc('check_and_increment_quota', {
      p_vendor_id: body.vendor_id,
      p_count: photos.length,
    })

    if (quotaErr) {
      return new Response(
        JSON.stringify({ success: false, error: `quota check failed: ${quotaErr.message}` }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
      )
    }
    const quota = quotaRows?.[0]
    if (!quota?.allowed) {
      return new Response(
        JSON.stringify({
          success: false,
          paywall: true,
          quota: {
            used: quota?.used ?? 0,
            remaining: quota?.remaining ?? 0,
            daily_limit: quota?.daily_limit ?? 10,
            plan: quota?.plan ?? 'bootstrap',
          },
          message: `Cuota diaria agotada (${quota?.daily_limit ?? 10}/dia en plan ${quota?.plan}). Actualiza tu plan para subir mas fotos.`,
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 429 }
      )
    }

    // === 2. Classify each photo (parallel) ===
    const geminiKey = Deno.env.get('GEMINI_API_KEY') ?? ''
    const groqKey = Deno.env.get('GROQ_API_KEY') ?? ''

    if (!geminiKey && !groqKey) {
      return new Response(
        JSON.stringify({ success: false, error: 'no AI provider configured (set GEMINI_API_KEY or GROQ_API_KEY)' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
      )
    }

    const results = await Promise.all(photos.map(async (p, idx) => {
      const photoId = p.id ?? `photo_${idx + 1}`
      const out: ClassifyResult = {
        photo_id: photoId, url: p.url,
        category_slug: null, confidence: 0,
        needs_review: true, preview_caption: '',
      }

      try {
        const img = await fetchImageAsBase64(p.url)
        let used: 'gemini' | 'groq' = 'gemini'
        let r
        let fallback = false

        if (geminiKey) {
          try {
            r = await classifyViaGemini(img.data, img.mime, geminiKey)
          } catch (e) {
            const msg = String(e).toLowerCase()
            const isRecoverable = msg.includes('429') || msg.includes('quota') || msg.includes('rate')
              || msg.includes('503') || msg.includes('overloaded') || msg.includes('high demand')
              || msg.includes('unavailable') || msg.includes('500')
            if (isRecoverable && groqKey) {
              fallback = true
              used = 'groq'
              r = await classifyViaGroq(img.data, img.mime, groqKey)
            } else { throw e }
          }
        } else {
          used = 'groq'
          r = await classifyViaGroq(img.data, img.mime, groqKey)
        }

        out.category_slug = r.category_slug
        out.confidence = r.confidence
        out.preview_caption = r.preview_caption
        out.needs_review = r.confidence < 0.85

        await logToDb(client, {
          vendor_id: body.vendor_id,
          category_slug: r.category_slug,
          photo_urls: [p.url],
          ai_provider: used,
          ai_model: used === 'gemini' ? 'gemini-2.5-flash' : 'meta-llama/llama-4-scout-17b-16e-instruct',
          ai_response: { category_slug: r.category_slug, confidence: r.confidence, caption: r.preview_caption },
          tokens_used: r.tokens,
          latency_ms: Date.now() - startTime,
          success: true,
          fallback_triggered: fallback,
        })
      } catch (e) {
        out.error = String(e)
        await logToDb(client, {
          vendor_id: body.vendor_id,
          photo_urls: [p.url],
          ai_provider: null,
          success: false,
          error_message: out.error,
          latency_ms: Date.now() - startTime,
        })
      }

      return out
    }))

    // === 3. Duplicate detection (same product photographed multiple times) ===
    // Two photos likely show the same product if:
    //   (a) caption similarity (Jaccard tokens >= 0.30), AND
    //   (b) their categories are the same OR share a strong product noun
    //       (e.g. both contain "frikko", "lg", "iphone", etc).
    // This is ADVISORY — UI can show as suggestion ("¿agrupar como mismo producto?").
    const duplicateGroups: Array<{ representative: string; photo_ids: string[]; reason: string }> = []
    const assigned = new Set<string>()

    for (let i = 0; i < results.length; i++) {
      if (assigned.has(results[i].photo_id)) continue
      const a = results[i]
      if (!a.category_slug || a.error) continue

      const group: string[] = [a.photo_id]
      const sharedTokensSet = new Set<string>()
      for (let j = i + 1; j < results.length; j++) {
        const b = results[j]
        if (assigned.has(b.photo_id)) continue
        if (b.error) continue

        const { similarity, sharedTokens } = captionSimilarityDetailed(a.preview_caption, b.preview_caption)
        // Strong product-noun match (brand/model) — even cross-category counts
        const hasStrongMatch = sharedTokens.some(t => t.length >= 5)
        const sameCategory = b.category_slug === a.category_slug

        if ((sameCategory && similarity >= 0.30) || (hasStrongMatch && similarity >= 0.25)) {
          group.push(b.photo_id)
          assigned.add(b.photo_id)
          for (const t of sharedTokens) sharedTokensSet.add(t)
        }
      }
      if (group.length > 1) {
        duplicateGroups.push({
          representative: a.photo_id,
          photo_ids: group,
          reason: `Captions comparten: ${Array.from(sharedTokensSet).slice(0, 4).join(', ')}`,
        })
        for (const id of group.slice(1)) {
          const r = results.find(x => x.photo_id === id)
          if (r) (r as any).same_product_as = a.photo_id
        }
      }
      assigned.add(a.photo_id)
    }

    // === 4. Group results by category for UI ===
    const groups: Record<string, ClassifyResult[]> = {}
    for (const r of results) {
      const key = r.error ? 'error' : (r.needs_review ? 'needs_review' : (r.category_slug ?? 'otros'))
      if (!groups[key]) groups[key] = []
      groups[key].push(r)
    }

    return new Response(
      JSON.stringify({
        success: true,
        total: results.length,
        quota: {
          used: quota.used,
          remaining: quota.remaining,
          daily_limit: quota.daily_limit,
          plan: quota.plan,
        },
        results,
        groups,
        duplicate_groups: duplicateGroups,  // photos that look like same product
        latency_ms: Date.now() - startTime,
      }, null, 2),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ success: false, error: String(error) }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
    )
  }
})
