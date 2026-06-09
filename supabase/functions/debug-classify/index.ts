// Quick debug: call Gemini directly with the truck image and return raw text
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const reqBody = await req.json()
  const apiKey = Deno.env.get('GEMINI_API_KEY') ?? ''

  let mime = 'image/jpeg'
  let data = ''
  if (reqBody.base64) {
    data = reqBody.base64
    mime = reqBody.mime ?? 'image/jpeg'
  } else if (reqBody.url) {
    const fetchImg = await fetch(reqBody.url)
    const buf = await fetchImg.arrayBuffer()
    mime = fetchImg.headers.get('content-type') ?? 'image/jpeg'
    data = btoa(String.fromCharCode(...new Uint8Array(buf)))
  }

  const ALLOWED = [
    'comida-preparada','frutas-verduras','carniceria','abarrotes','postres','bebidas',
    'ropa','calzado','belleza','salud','bebes-ninos','mascotas','hogar',
    'electronicos','servicios','otros','automoviles','industrial',
    'juguetes','autopartes','deportes','videojuegos',
  ]

  const body = {
    contents: [{
      parts: [
        { text: `Clasifica esta foto en UNA de: ${ALLOWED.join(', ')}.\nResponde SOLO JSON: {"category_slug":"<slug>","confidence":0.95,"preview_caption":"<frase corta>"}` },
        { inline_data: { mime_type: mime, data } },
      ],
    }],
    generation_config: { response_mime_type: 'application/json', temperature: 0.1, max_output_tokens: 200 },
  }

  const resp = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`,
    { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) },
  )
  const json = await resp.json()
  const text = json.candidates?.[0]?.content?.parts?.[0]?.text ?? null

  return new Response(JSON.stringify({
    status: resp.status,
    raw_text: text,
    full_response: json,
  }, null, 2), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
})
