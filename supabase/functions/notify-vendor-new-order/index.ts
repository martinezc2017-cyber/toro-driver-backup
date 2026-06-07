// Edge Function: notify-vendor-new-order
// Triggered by Postgres pg_net.http_post when a marketplace order enters 'placed'.
// Body: { order_id: string }
// Resolves vendor → user_id → fcm_tokens, sends FCM v1 push with vendor_new_order_high channel.
// All sends logged to app_logs. UNREGISTERED tokens auto-deleted.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface OrderRow {
  id: string; vendor_id: string; total: number;
  buyer_id: string; items_summary?: string;
}

async function getAccessToken(sa: { client_email: string; private_key: string }): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const header = btoa(JSON.stringify({ alg: 'RS256', typ: 'JWT' })).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')
  const payload = btoa(JSON.stringify({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now, exp: now + 3600,
  })).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')

  const pemHeader = '-----BEGIN PRIVATE KEY-----'
  const pemFooter = '-----END PRIVATE KEY-----'
  const pem = sa.private_key.replace(/\\n/g, '\n')
    .replace(pemHeader, '').replace(pemFooter, '').replace(/\s/g, '')
  const binary = Uint8Array.from(atob(pem), c => c.charCodeAt(0))
  const key = await crypto.subtle.importKey('pkcs8', binary,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'])
  const sigBuf = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key,
    new TextEncoder().encode(`${header}.${payload}`))
  const sig = btoa(String.fromCharCode(...new Uint8Array(sigBuf)))
    .replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')

  const resp = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${header}.${payload}.${sig}`,
  })
  const j = await resp.json()
  if (!j.access_token) throw new Error('No access_token: ' + JSON.stringify(j))
  return j.access_token
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const start = Date.now()
  try {
    const body = await req.json()
    const order_id: string | undefined = body?.order_id
    // target options:
    //   'vendor'         (default, new-order alarm)
    //   'buyer'          (driver-arriving)
    //   'buyer_bundled'  (your order was combined with another, $0 extra delivery)
    const rawTarget = body?.target
    const target: 'vendor' | 'buyer' | 'buyer_bundled' =
      rawTarget === 'buyer' ? 'buyer' :
      rawTarget === 'buyer_bundled' ? 'buyer_bundled' :
      'vendor'
    if (!order_id) return new Response(JSON.stringify({ error: 'order_id required' }), {
      status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })

    const dbUrl = Deno.env.get('SUPABASE_DB_URL')!
    const { Client } = await import("https://deno.land/x/postgres@v0.17.0/mod.ts")
    const client = new Client(dbUrl)
    await client.connect()

    // 1) Order + vendor user_id + items summary
    const orderRes = await client.queryObject<OrderRow & { user_id: string; vendor_name: string }>(`
      SELECT o.id, o.vendor_id, o.total, o.buyer_id,
             v.user_id, v.business_name AS vendor_name,
             (SELECT string_agg(
                CASE WHEN i.quantity > 1 THEN i.quantity || 'x ' ELSE '' END
                || COALESCE(NULLIF(i.product_name_snapshot, ''), 'producto'),
                ', '
              ) FROM marketplace_order_items i WHERE i.order_id = o.id) AS items_summary
      FROM marketplace_orders o
      JOIN vendors v ON v.id = o.vendor_id
      WHERE o.id = $1
    `, [order_id])

    if (orderRes.rows.length === 0) {
      await client.end()
      return new Response(JSON.stringify({ error: 'order not found' }), {
        status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    const order = orderRes.rows[0]

    // 2) Recipient FCM tokens — vendor's user_id (default) or buyer's (any 'buyer*' target)
    const recipientUserId =
      (target === 'buyer' || target === 'buyer_bundled') ? order.buyer_id : order.user_id
    const tokRes = await client.queryObject<{ token: string }>(`
      SELECT token FROM fcm_tokens WHERE user_id = $1 AND token IS NOT NULL
    `, [recipientUserId])
    const tokens = tokRes.rows.map(r => r.token)

    if (tokens.length === 0) {
      await client.queryArray(`
        INSERT INTO app_logs (level, source, event, message, context, app_role)
        VALUES ('warn', 'notify-vendor-new-order', 'no_tokens',
                'Vendor has no FCM tokens', $1, 'system')
      `, [JSON.stringify({ order_id, vendor_id: order.vendor_id, user_id: order.user_id })])
      await client.end()
      return new Response(JSON.stringify({ success: true, sent: 0, reason: 'no_tokens' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // 3) FCM v1 send
    const saJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON')!
    const sa = JSON.parse(saJson)
    const accessToken = await getAccessToken(sa)
    const projectId = sa.project_id

    const summary = order.items_summary || 'Pedido nuevo'
    const total = Number(order.total || 0).toFixed(0)

    // Message content + channel + deep-link depend on target
    const title =
      target === 'buyer'         ? '🚗 Tu chofer está llegando' :
      target === 'buyer_bundled' ? '🎁 Pedido combinado — $0 extra delivery' :
                                   '🔔 NUEVO PEDIDO'
    const bodyText =
      target === 'buyer'         ? `${order.vendor_name}: ${summary}` :
      target === 'buyer_bundled' ? `Tu pedido nuevo se combinó con el anterior de ${order.vendor_name}. Llega junto, no pagas delivery extra.` :
                                   `${summary} — $${total}`
    const dataType =
      target === 'buyer'         ? 'driver_arriving' :
      target === 'buyer_bundled' ? 'order_bundled' :
                                   'vendor_new_order'
    const deepLink =
      (target === 'buyer' || target === 'buyer_bundled') ? `/marketplace/order/${order_id}` :
                                                            '/marketplace/vendor-cascade'
    const androidChannel = target === 'vendor' ? 'vendor_new_order_high' : 'rides_high'
    const apnsSound      = target === 'vendor' ? 'vendor_new_order.caf'  : 'default'

    const results = await Promise.all(tokens.map(async (token) => {
      const body = {
        message: {
          token,
          notification: { title, body: bodyText },
          data: {
            type: dataType,
            order_id,
            vendor_id: order.vendor_id,
            deep_link: deepLink,
          },
          android: {
            priority: 'HIGH',
            notification: {
              channel_id: androidChannel,
              sound: target === 'buyer' ? 'default' : 'vendor_new_order',
              default_vibrate_timings: target === 'buyer',
              vibrate_timings: target === 'buyer' ? undefined : ['0s', '0.6s', '0.3s', '0.6s'],
            },
          },
          apns: {
            headers: { 'apns-priority': '10' },
            payload: {
              aps: {
                alert: { title, body: bodyText },
                sound: apnsSound,
                'interruption-level': 'time-sensitive',
                'content-available': 1,
              },
            },
          },
        },
      }
      const resp = await fetch(
        `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
        {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(body),
        }
      )
      const text = await resp.text()
      const ok = resp.ok
      // Auto-clean UNREGISTERED / INVALID_ARGUMENT
      if (!ok && (text.includes('UNREGISTERED') || text.includes('INVALID_ARGUMENT'))) {
        try {
          await client.queryArray(`DELETE FROM fcm_tokens WHERE token = $1`, [token])
        } catch (_) {}
      }
      return { token: token.substring(0, 16) + '…', ok, status: resp.status, body: ok ? null : text }
    }))

    const sent = results.filter(r => r.ok).length
    const failed = results.length - sent

    await client.queryArray(`
      INSERT INTO app_logs (level, source, event, message, context, app_role)
      VALUES ($1, 'notify-vendor-new-order', 'sent',
              $2, $3, 'system')
    `, [
      failed > 0 ? 'warn' : 'info',
      `Sent ${sent}/${tokens.length} pushes (${failed} failed)`,
      JSON.stringify({
        order_id, vendor_id: order.vendor_id, user_id: order.user_id,
        sent, failed, latency_ms: Date.now() - start, results,
      }),
    ])

    await client.end()
    return new Response(JSON.stringify({ success: true, sent, failed }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  } catch (err) {
    return new Response(JSON.stringify({ success: false, error: String(err) }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
})
