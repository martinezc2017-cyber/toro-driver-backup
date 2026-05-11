// Edge Function: notify-drivers-of-ride
// Sends FCM push to online drivers in the SAME ZONE as the ride.
// Canonical order: country_code → state_code → operating_city → distance (haversine).
// A driver in Mexicali (MX/BC) NEVER receives a ride from CDMX (MX/CDMX) or Phoenix (US/AZ).

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface NotifyRequest {
  ride_id: string
  pickup_lat?: number
  pickup_lng?: number
  pickup_address?: string
  estimated_price?: number
  service_type?: string
  country_code?: string
  state_code?: string
  city?: string
  search_radius_km?: number
}

function fcmUrl(projectId: string) {
  return `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`
}

let _cachedToken: string | null = null
let _tokenExpiry = 0

async function base64url(input: string | ArrayBuffer): Promise<string> {
  const str = typeof input === 'string'
    ? btoa(input)
    : btoa(String.fromCharCode(...new Uint8Array(input)))
  return str.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem.replace(/-----BEGIN PRIVATE KEY-----/, '').replace(/-----END PRIVATE KEY-----/, '').replace(/\s/g, '')
  const binary = atob(b64)
  const buf = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) buf[i] = binary.charCodeAt(i)
  return buf.buffer
}

let _cachedProjectId: string | null = null

async function getAccessToken(): Promise<{ token: string; projectId: string } | null> {
  // Try multiple secret names for the Firebase service account
  let sa = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
    ?? Deno.env.get('FCM_SERVICE_ACCOUNT_JSON')

  // Fallback: base64-encoded variant
  if (!sa) {
    const b64 = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_B64')
    if (b64) {
      try { sa = atob(b64) } catch { /* ignore */ }
    }
  }
  if (!sa) return null

  let account: any
  try {
    account = JSON.parse(sa)
  } catch (e) {
    console.error('Service account JSON parse error:', e)
    return null
  }

  const projectId = account.project_id ?? Deno.env.get('FIREBASE_PROJECT_ID') ?? ''
  if (!projectId) {
    console.error('No project_id in service account or FIREBASE_PROJECT_ID env')
    return null
  }

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
    const key = await crypto.subtle.importKey(
      'pkcs8', pemToArrayBuffer(account.private_key),
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'],
    )
    const sigBuf = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, signingInput)
    const sig = await base64url(sigBuf)
    const jwt = `${header}.${payload}.${sig}`

    const tokenResp = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
    })
    const tokenJson = await tokenResp.json()
    if (!tokenJson.access_token) {
      console.error('OAuth token response missing access_token:', tokenJson)
      return null
    }
    _cachedToken = tokenJson.access_token
    _cachedProjectId = projectId
    _tokenExpiry = now + (tokenJson.expires_in ?? 3600)
    return { token: _cachedToken, projectId }
  } catch (e) {
    console.error('Token error:', e)
    return null
  }
}

// Haversine distance in km
function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371  // Earth radius km
  const dLat = (lat2 - lat1) * Math.PI / 180
  const dLng = (lng2 - lng1) * Math.PI / 180
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLng / 2) ** 2
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
}

async function sendFcm(
  token: string,
  accessToken: string,
  projectId: string,
  ride: { ride_id: string; pickup_address: string; estimated_price: number },
): Promise<{ ok: boolean; status?: number; error?: string; errorCode?: string }> {
  const message = {
    message: {
      token,
      notification: {
        title: '🚗 ¡Nuevo viaje disponible!',
        body: `${ride.pickup_address} • $${ride.estimated_price.toFixed(0)}`,
      },
      data: { type: 'new_ride', ride_id: ride.ride_id, click_action: 'FLUTTER_NOTIFICATION_CLICK' },
      android: {
        priority: 'HIGH',
        notification: { channel_id: 'rides_high', sound: 'default', default_vibrate_timings: true },
      },
      apns: {
        headers: { 'apns-priority': '10' },
        payload: { aps: { sound: 'default', 'content-available': 1, badge: 1 } },
      },
    },
  }
  const resp = await fetch(fcmUrl(projectId), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${accessToken}` },
    body: JSON.stringify(message),
  })
  if (!resp.ok) {
    const errText = await resp.text().catch(() => '')
    let errorCode = 'UNKNOWN'
    try {
      const errJson = JSON.parse(errText)
      errorCode = errJson?.error?.details?.[0]?.errorCode
        ?? errJson?.error?.status
        ?? 'UNKNOWN'
    } catch { /* not JSON */ }
    console.error(`FCM ${resp.status} ${errorCode}:`, errText.slice(0, 200))
    return { ok: false, status: resp.status, error: errText.slice(0, 300), errorCode }
  }
  return { ok: true, status: resp.status }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const client = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } }
    )

    const body = await req.json() as NotifyRequest
    const {
      ride_id,
      pickup_lat, pickup_lng,
      pickup_address = 'Pickup',
      estimated_price = 0,
      country_code, state_code, city,
      search_radius_km = 15,
    } = body

    if (!ride_id) {
      return new Response(
        JSON.stringify({ success: false, error: 'ride_id required' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    // Resolve zone fields if not provided — read from the delivery row itself
    let zoneCountry = country_code
    let zoneState = state_code
    let zoneCity = city
    let zoneLat = pickup_lat
    let zoneLng = pickup_lng

    if (!zoneCountry || !zoneState || zoneLat == null) {
      const { data: ride } = await client
        .from('deliveries')
        .select('country_code, state_code, pickup_lat, pickup_lng, pickup_address, estimated_price')
        .eq('id', ride_id)
        .maybeSingle()
      if (ride) {
        zoneCountry = zoneCountry ?? ride.country_code
        zoneState = zoneState ?? ride.state_code
        zoneLat = zoneLat ?? ride.pickup_lat
        zoneLng = zoneLng ?? ride.pickup_lng
      }
    }

    if (!zoneCountry || zoneLat == null || zoneLng == null) {
      return new Response(
        JSON.stringify({ success: false, error: 'Cannot determine ride zone (country_code + coords required)' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    // === CANONICAL ZONE FILTER ===
    // 1) country_code (MX vs US) — strict
    let query = client
      .from('drivers')
      .select('id, fcm_token, current_lat, current_lng, full_name, operating_city, operating_state, country_code, state_code')
      .eq('is_online', true)
      .eq('can_receive_rides', true)
      .eq('country_code', zoneCountry)
      .not('fcm_token', 'is', null)

    // 2) state_code (BC vs CDMX vs AZ) — strict if available
    if (zoneState) {
      query = query.or(`state_code.eq.${zoneState},operating_state.eq.${zoneState}`)
    }

    // 3) Geographic bounding box (degree approximation) — drops far-away drivers fast
    const degreeOffset = (search_radius_km + 5) / 111  // +5km buffer for the box
    query = query
      .gte('current_lat', zoneLat - degreeOffset)
      .lte('current_lat', zoneLat + degreeOffset)
      .gte('current_lng', zoneLng - degreeOffset)
      .lte('current_lng', zoneLng + degreeOffset)

    const { data: candidates, error: driversError } = await query.limit(50)

    if (driversError) {
      return new Response(
        JSON.stringify({ success: false, error: driversError.message }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
      )
    }

    // 4) Final precision filter: haversine distance (real km, not bounding box)
    const eligible = (candidates ?? []).filter(d => {
      if (d.current_lat == null || d.current_lng == null) return false
      const km = haversineKm(zoneLat!, zoneLng!, Number(d.current_lat), Number(d.current_lng))
      return km <= search_radius_km
    })

    if (eligible.length === 0) {
      return new Response(
        JSON.stringify({
          success: true,
          drivers_notified: 0,
          reason: 'No drivers in zone',
          zone: { country: zoneCountry, state: zoneState, lat: zoneLat, lng: zoneLng, radius_km: search_radius_km },
          candidates_before_distance_filter: candidates?.length ?? 0,
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
      )
    }

    // Send FCM
    const auth = await getAccessToken()
    let notified = 0
    const results: Array<{ driver_id: string; sent: boolean; distance_km: number; error?: string; errorCode?: string }> = []
    const tokensToInvalidate: string[] = []

    for (const d of eligible) {
      const distance = haversineKm(zoneLat!, zoneLng!, Number(d.current_lat), Number(d.current_lng))
      let sent = false
      let errorCode: string | undefined
      let errorMsg: string | undefined
      if (auth && d.fcm_token) {
        try {
          const fcmResult = await sendFcm(d.fcm_token, auth.token, auth.projectId, {
            ride_id, pickup_address, estimated_price,
          })
          sent = fcmResult.ok
          errorCode = fcmResult.errorCode
          errorMsg = fcmResult.error

          // Invalid/expired token — schedule clean-up
          if (!sent && (errorCode === 'UNREGISTERED' || errorCode === 'INVALID_ARGUMENT' || fcmResult.status === 404)) {
            tokensToInvalidate.push(d.id)
          }
        } catch (e) {
          console.error(`FCM send error for ${d.id}:`, e)
          errorMsg = String(e)
        }
      }

      // Always log to notifications table for in-app display
      try {
        await client.from('notifications').insert({
          user_id: d.id,
          type: 'new_ride',
          title: '🚗 ¡Nuevo viaje!',
          body: `${pickup_address} • $${estimated_price.toFixed(0)}`,
          data: { ride_id, type: 'new_ride', distance_km: distance.toFixed(1) },
          is_read: false,
        })
      } catch (_) { /* table may not exist */ }

      if (sent) notified++
      results.push({
        driver_id: d.id,
        sent,
        distance_km: Number(distance.toFixed(2)),
        ...(errorCode ? { errorCode } : {}),
        ...(errorMsg ? { error: errorMsg } : {}),
      })
    }

    // Auto-cleanup: clear invalid FCM tokens so we stop trying them
    if (tokensToInvalidate.length > 0) {
      try {
        await client
          .from('drivers')
          .update({ fcm_token: null })
          .in('id', tokensToInvalidate)
        console.log(`Cleared ${tokensToInvalidate.length} invalid FCM tokens`)
      } catch (e) {
        console.error('Token cleanup failed:', e)
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        zone: { country: zoneCountry, state: zoneState, lat: zoneLat, lng: zoneLng, radius_km: search_radius_km },
        drivers_in_zone: eligible.length,
        drivers_notified: notified,
        fcm_configured: !!auth,
        fcm_project: auth?.projectId,
        results: results.sort((a, b) => a.distance_km - b.distance_km),
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
