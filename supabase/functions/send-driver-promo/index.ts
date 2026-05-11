// Edge Function: send-driver-promo
// Sends FCM push to drivers in a zone WITHOUT requiring is_online=true.
// Use cases: bonus campaigns, demand alerts, wallet expiry reminders, re-engagement.
// Differs from notify-drivers-of-ride which is online-only for actual ride dispatch.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

type AudienceFilter =
  | 'all'                  // every driver in zone with token
  | 'offline'              // only drivers offline (re-engagement)
  | 'online'               // only drivers online (already there, push extra info)
  | 'inactive_7d'          // no location update in 7 days
  | 'inactive_30d'         // dormant
  | 'has_wallet_balance'   // drivers with active wallet_lots

interface PromoRequest {
  title: string
  body: string
  audience?: AudienceFilter        // default 'all'
  country_code?: string            // strict zone filter
  state_code?: string
  operating_city?: string
  data?: Record<string, string>    // custom payload (deep links, promo_id, etc)
  notification_type?: string       // for in-app routing: 'promo' | 'bonus' | 'demand_alert' | 're_engage'
  dry_run?: boolean                // returns matched audience without sending
}

let _cachedToken: string | null = null
let _cachedProjectId: string | null = null
let _tokenExpiry = 0

async function base64url(input: string | ArrayBuffer): Promise<string> {
  const str = typeof input === 'string' ? btoa(input) : btoa(String.fromCharCode(...new Uint8Array(input)))
  return str.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem.replace(/-----BEGIN PRIVATE KEY-----/, '').replace(/-----END PRIVATE KEY-----/, '').replace(/\s/g, '')
  const binary = atob(b64)
  const buf = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) buf[i] = binary.charCodeAt(i)
  return buf.buffer
}

async function getAccessToken(): Promise<{ token: string; projectId: string } | null> {
  let sa = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
  if (!sa) {
    const b64 = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_B64')
    if (b64) { try { sa = atob(b64) } catch {} }
  }
  if (!sa) return null

  let account: any
  try { account = JSON.parse(sa) } catch { return null }
  const projectId = account.project_id ?? Deno.env.get('FIREBASE_PROJECT_ID') ?? ''
  if (!projectId) return null

  const now = Math.floor(Date.now() / 1000)
  if (_cachedToken && _tokenExpiry > now + 60 && _cachedProjectId === projectId) {
    return { token: _cachedToken, projectId }
  }

  try {
    const header = await base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
    const payload = await base64url(JSON.stringify({
      iss: account.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now, exp: now + 3600,
    }))
    const signingInput = new TextEncoder().encode(`${header}.${payload}`)
    const key = await crypto.subtle.importKey('pkcs8', pemToArrayBuffer(account.private_key),
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'])
    const sigBuf = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, signingInput)
    const sig = await base64url(sigBuf)
    const jwt = `${header}.${payload}.${sig}`

    const tokenResp = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
    })
    const tokenJson = await tokenResp.json()
    if (!tokenJson.access_token) return null
    _cachedToken = tokenJson.access_token
    _cachedProjectId = projectId
    _tokenExpiry = now + (tokenJson.expires_in ?? 3600)
    return { token: _cachedToken, projectId }
  } catch { return null }
}

async function sendFcm(token: string, accessToken: string, projectId: string, payload: {
  title: string; body: string; data: Record<string, string>; notificationType: string;
}): Promise<{ ok: boolean; errorCode?: string }> {
  const message = {
    message: {
      token,
      notification: { title: payload.title, body: payload.body },
      data: { ...payload.data, type: payload.notificationType, click_action: 'FLUTTER_NOTIFICATION_CLICK' },
      android: {
        priority: 'NORMAL',  // promos are not as urgent as ride dispatches
        notification: { channel_id: 'promotions', sound: 'default' },
      },
      apns: {
        headers: { 'apns-priority': '5' },
        payload: { aps: { sound: 'default', badge: 1 } },
      },
    },
  }
  const resp = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${accessToken}` },
    body: JSON.stringify(message),
  })
  if (!resp.ok) {
    const errText = await resp.text().catch(() => '')
    let errorCode = 'UNKNOWN'
    try {
      const errJson = JSON.parse(errText)
      errorCode = errJson?.error?.details?.[0]?.errorCode ?? 'UNKNOWN'
    } catch {}
    return { ok: false, errorCode }
  }
  return { ok: true }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const client = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } }
    )

    const body = await req.json() as PromoRequest
    const {
      title, body: notifBody, audience = 'all',
      country_code, state_code, operating_city,
      data = {}, notification_type = 'promo', dry_run = false,
    } = body

    if (!title || !notifBody) {
      return new Response(
        JSON.stringify({ success: false, error: 'title and body are required' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    // Build audience query — note: NOT requiring is_online here
    let q = client.from('drivers')
      .select('id, fcm_token, is_online, location_updated_at, full_name, operating_city')
      .not('fcm_token', 'is', null)

    if (country_code) q = q.eq('country_code', country_code)
    if (state_code) q = q.or(`state_code.eq.${state_code},operating_state.eq.${state_code}`)
    if (operating_city) q = q.eq('operating_city', operating_city)

    switch (audience) {
      case 'online':
        q = q.eq('is_online', true)
        break
      case 'offline':
        q = q.eq('is_online', false)
        break
      case 'inactive_7d': {
        const cutoff = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString()
        q = q.lt('location_updated_at', cutoff)
        break
      }
      case 'inactive_30d': {
        const cutoff = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString()
        q = q.lt('location_updated_at', cutoff)
        break
      }
      case 'has_wallet_balance':
        // Inner join via separate query — we'll filter post-fetch
        break
      // 'all' = no extra filter
    }

    const { data: drivers, error } = await q.limit(500)
    if (error) {
      return new Response(
        JSON.stringify({ success: false, error: error.message }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
      )
    }

    let targets = drivers ?? []

    // For 'has_wallet_balance' filter, intersect with active wallet_lots
    if (audience === 'has_wallet_balance' && targets.length > 0) {
      const ids = targets.map(d => d.id)
      const { data: lots } = await client
        .from('wallet_lots')
        .select('user_id')
        .in('user_id', ids)
        .eq('status', 'active')
        .gt('remaining_amount', 0)
      const usersWithBalance = new Set((lots ?? []).map(l => l.user_id))
      targets = targets.filter(d => usersWithBalance.has(d.id))
    }

    if (dry_run) {
      return new Response(
        JSON.stringify({
          success: true,
          dry_run: true,
          audience,
          would_target: targets.length,
          sample: targets.slice(0, 5).map(d => ({
            id: d.id, full_name: d.full_name,
            is_online: d.is_online, operating_city: d.operating_city,
          })),
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
      )
    }

    // Send pushes
    const auth = await getAccessToken()
    if (!auth) {
      return new Response(
        JSON.stringify({ success: false, error: 'FCM not configured' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
      )
    }

    let sent = 0
    let invalid = 0
    const tokensToInvalidate: string[] = []

    for (const d of targets) {
      if (!d.fcm_token) continue
      const r = await sendFcm(d.fcm_token, auth.token, auth.projectId, {
        title, body: notifBody, data, notificationType: notification_type,
      })
      if (r.ok) {
        sent++
        // Also log to in-app notifications
        try {
          await client.from('notifications').insert({
            user_id: d.id, type: notification_type, title, body: notifBody, data, is_read: false,
          })
        } catch {}
      } else {
        if (r.errorCode === 'UNREGISTERED' || r.errorCode === 'INVALID_ARGUMENT') {
          tokensToInvalidate.push(d.id)
          invalid++
        }
      }
    }

    if (tokensToInvalidate.length > 0) {
      await client.from('drivers').update({ fcm_token: null }).in('id', tokensToInvalidate)
    }

    return new Response(
      JSON.stringify({
        success: true,
        audience,
        targets: targets.length,
        sent,
        invalid_tokens_cleaned: invalid,
        zone: { country_code, state_code, operating_city },
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ success: false, error: String(error) }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
    )
  }
})
