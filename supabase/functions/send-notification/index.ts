// @ts-nocheck
// deno-lint-ignore-file
// Deno Edge Function for Supabase
// Uses FCM v1 API with service account OAuth2 (replaces legacy FCM server key)
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'
import { serve } from 'https://deno.land/std@0.194.0/http/server.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const client = createClient(supabaseUrl, supabaseKey)

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

interface SendNotificationRequest {
  userId: string
  title: string
  body: string
  type: string
  data?: Record<string, any>
}

// ---- FCM v1 API helpers (OAuth2 + service account JWT) ----

function base64url(data: string | ArrayBuffer): string {
  const str = typeof data === 'string'
    ? btoa(data)
    : btoa(String.fromCharCode(...new Uint8Array(data)))
  return str.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '')
  const binary = atob(b64)
  const buf = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) buf[i] = binary.charCodeAt(i)
  return buf.buffer
}

let _cachedAccessToken: string | null = null
let _tokenExpiry = 0

async function getAccessToken(serviceAccountJson: string): Promise<{ token: string; projectId: string }> {
  const now = Math.floor(Date.now() / 1000)
  const sa = JSON.parse(serviceAccountJson)

  // Return cached token if still valid (with 60s buffer)
  if (_cachedAccessToken && _tokenExpiry > now + 60) {
    return { token: _cachedAccessToken, projectId: sa.project_id }
  }

  const { client_email, private_key, project_id } = sa

  // Create JWT header + payload
  const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
  const payload = base64url(JSON.stringify({
    iss: client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }))

  const signingInput = new TextEncoder().encode(`${header}.${payload}`)

  // Import private key and sign
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, signingInput)
  const jwt = `${header}.${payload}.${base64url(signature)}`

  // Exchange JWT for access token
  const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}`,
  })

  const tokenData = await tokenResponse.json()
  if (!tokenData.access_token) {
    throw new Error(`OAuth2 error: ${JSON.stringify(tokenData)}`)
  }

  _cachedAccessToken = tokenData.access_token
  _tokenExpiry = now + (tokenData.expires_in || 3600)

  return { token: tokenData.access_token, projectId: project_id }
}

// Map notification type to custom sound file
function getSoundForType(type?: string): { ios: string; android: string } {
  switch (type) {
    case 'ride_request':
    case 'rideConfirmed':
    case 'driverAssigned':
    case 'rideStarted':
    case 'rideCompleted':
    case 'bid_request':
    case 'bid_won':
    case 'tourism_emergency_broadcast':
      return { ios: 'ride_alert.caf', android: 'ride_alert' }
    case 'newMessage':
    case 'new_message':
    case 'message':
    case 'chat':
      return { ios: 'message.caf', android: 'message_sound' }
    default:
      return { ios: 'notification.caf', android: 'notification_sound' }
  }
}

async function sendFcmV1(
  accessToken: string,
  projectId: string,
  fcmToken: string,
  title: string,
  body: string,
  data?: Record<string, any>,
  type?: string,
): Promise<{ ok: boolean; unregistered: boolean; error?: string }> {
  try {
    // Stringify all data values (FCM v1 requires string values in data)
    const stringData: Record<string, string> = {}
    if (data) {
      for (const [k, v] of Object.entries(data)) {
        stringData[k] = typeof v === 'string' ? v : JSON.stringify(v)
      }
    }
    stringData['click_action'] = 'FLUTTER_NOTIFICATION_CLICK'

    const sound = getSoundForType(type)

    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${accessToken}`,
        },
        body: JSON.stringify({
          message: {
            token: fcmToken,
            notification: { title, body },
            data: stringData,
            android: {
              priority: 'high',
              notification: {
                icon: 'ic_notification',
                color: '#FFD700',
                sound: sound.android,
              },
            },
            apns: {
              headers: {
                'apns-priority': '10',
              },
              payload: {
                aps: {
                  'content-available': 1,
                  sound: sound.ios,
                  badge: 1,
                },
              },
            },
          },
        }),
      },
    )

    if (response.ok) {
      return { ok: true, unregistered: false }
    }

    const errData = await response.json()
    const fcmErrorCode = errData.error?.details?.[0]?.errorCode || ''
    const errMsg = fcmErrorCode || errData.error?.message || errData.error?.status || `HTTP ${response.status}`
    const isUnregistered = errMsg.includes('UNREGISTERED') || errMsg.includes('INVALID_ARGUMENT') || errMsg.includes('NOT_FOUND') || errMsg.includes('not found')

    console.error('FCM v1 error:', errMsg)
    return { ok: false, unregistered: isUnregistered, error: errMsg }
  } catch (error) {
    console.error('Failed to send FCM v1 notification:', error)
    return { ok: false, unregistered: false, error: (error as Error).message }
  }
}

// ---- Load service account JSON from secrets ----

function getServiceAccountJson(): string {
  const saB64 = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_B64') || ''
  const saRaw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT') || ''
  return saB64 ? atob(saB64) : saRaw
}

// ---- Main handler ----

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    if (req.method === 'POST') {
      const body: SendNotificationRequest = await req.json()
      const { userId, title, body: notifBody, type, data } = body

      // Load service account and get OAuth2 access token
      const serviceAccountJson = getServiceAccountJson()
      if (!serviceAccountJson || serviceAccountJson.length < 10) {
        console.error('FIREBASE_SERVICE_ACCOUNT_B64 not configured, cannot send push notification')
        // Still store the notification in DB below, just skip FCM send
      }

      let accessToken: string | null = null
      let projectId: string | null = null

      if (serviceAccountJson && serviceAccountJson.length >= 10) {
        try {
          const auth = await getAccessToken(serviceAccountJson)
          accessToken = auth.token
          projectId = auth.projectId
        } catch (e) {
          console.error('Failed to get FCM access token:', (e as Error).message)
        }
      }

      // Try to find FCM token - check drivers table first, then auth metadata
      let fcmToken: string | null = null
      let isDriver = false

      // 1) Check drivers table (drivers store fcm_token directly)
      const { data: driverData } = await client
        .from('drivers')
        .select('id, email, fcm_token')
        .eq('id', userId)
        .maybeSingle()

      if (driverData?.fcm_token) {
        fcmToken = driverData.fcm_token
        isDriver = true
      }

      // 2) If not a driver (or no token), check auth metadata (riders)
      if (!fcmToken) {
        try {
          const { data: authData } = await client.auth.admin.getUserById(userId)
          fcmToken = authData?.user?.user_metadata?.['fcm_token'] || null
        } catch (_) {}
      }

      // 3) Also check fcm_tokens table
      if (!fcmToken) {
        const { data: tokenRow } = await client
          .from('fcm_tokens')
          .select('token')
          .eq('user_id', userId)
          .eq('is_active', true)
          .order('last_used_at', { ascending: false })
          .limit(1)
          .maybeSingle()
        if (tokenRow?.token) fcmToken = tokenRow.token
      }

      if (fcmToken && accessToken && projectId) {
        const sendResult = await sendFcmV1(accessToken, projectId, fcmToken, title, notifBody, data, type)

        // Clean up dead tokens (uninstalled app / expired token)
        if (sendResult.unregistered) {
          console.log(`Token UNREGISTERED for user ${userId}, cleaning up...`)
          // Deactivate in fcm_tokens table
          await client.from('fcm_tokens').update({ is_active: false }).eq('token', fcmToken).then(() => {}).catch(() => {})
          // Clear from drivers table if it was a driver token
          if (isDriver) {
            await client.from('drivers').update({ fcm_token: null }).eq('id', userId).then(() => {}).catch(() => {})
          }
        }
      } else if (fcmToken) {
        console.warn(`Have FCM token for user ${userId} but no access token - skipping push send`)
      }

      // Store notification in database for in-app display
      try {
        await client
          .from('notifications')
          .insert({
            user_id: userId,
            title,
            body: notifBody,
            type,
            data,
            created_at: new Date().toISOString(),
          })
      } catch (_) {
        // notifications table may not accept driver IDs, skip
      }

      return new Response(JSON.stringify({ success: true }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    return new Response(JSON.stringify({ error: 'Method not allowed' }), { status: 405, headers: corsHeaders })
  } catch (error) {
    console.error('Error:', error)
    const message = (error as Error)?.message ?? 'Unknown error'
    return new Response(JSON.stringify({ error: message }), { status: 500, headers: corsHeaders })
  }
})
