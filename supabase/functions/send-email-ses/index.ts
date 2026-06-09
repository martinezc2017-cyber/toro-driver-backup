// Supabase Edge Function: send-email-ses
// Envía emails transaccionales via Resend (primary) o AWS SES (fallback)
// Deploy: supabase functions deploy send-email-ses
// Secrets: RESEND_API_KEY (primary), AWS_SES_ACCESS_KEY, AWS_SES_SECRET_KEY, AWS_SES_REGION (fallback)

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Resend Configuration (primary - domain verified, no sandbox)
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') || ''

// AWS SES Configuration (fallback)
const AWS_REGION = Deno.env.get('AWS_SES_REGION') || 'us-east-2'
const AWS_ACCESS_KEY = Deno.env.get('AWS_SES_ACCESS_KEY') || ''
const AWS_SECRET_KEY = Deno.env.get('AWS_SES_SECRET_KEY') || ''
const FROM_EMAIL = 'noreply@toro-ride.com'
const FROM_NAME = 'Toro Ride'

interface SendEmailRequest {
  to: string
  subject: string
  html: string
  text?: string
  replyTo?: string
  template?: 'earnings' | 'receipt' | 'summary' | 'payout' | 'notification' | 'welcome'
  templateData?: Record<string, unknown>
}

// ============================================================================
// AWS Signature V4 Implementation for SES
// ============================================================================

function toHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map(b => b.toString(16).padStart(2, '0'))
    .join('')
}

async function sha256(message: string): Promise<Uint8Array> {
  const encoder = new TextEncoder()
  const data = encoder.encode(message)
  const hashBuffer = await crypto.subtle.digest('SHA-256', data)
  return new Uint8Array(hashBuffer)
}

async function hmac(key: Uint8Array, message: string): Promise<Uint8Array> {
  const encoder = new TextEncoder()
  const cryptoKey = await crypto.subtle.importKey(
    'raw',
    key,
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  )
  const signature = await crypto.subtle.sign('HMAC', cryptoKey, encoder.encode(message))
  return new Uint8Array(signature)
}

async function getSignatureKey(
  key: string,
  dateStamp: string,
  regionName: string,
  serviceName: string
): Promise<Uint8Array> {
  const encoder = new TextEncoder()
  const kDate = await hmac(encoder.encode('AWS4' + key), dateStamp)
  const kRegion = await hmac(kDate, regionName)
  const kService = await hmac(kRegion, serviceName)
  const kSigning = await hmac(kService, 'aws4_request')
  return kSigning
}

function getAmzDate(): { amzDate: string; dateStamp: string } {
  const now = new Date()
  const amzDate = now.toISOString().replace(/[:-]|\.\d{3}/g, '')
  const dateStamp = amzDate.substring(0, 8)
  return { amzDate, dateStamp }
}

// ============================================================================
// Send Email via Resend API (Primary)
// ============================================================================

async function sendViaResend(
  to: string,
  subject: string,
  htmlBody: string,
  textBody: string,
  replyTo?: string
): Promise<{ success: boolean; messageId?: string; error?: string }> {
  if (!RESEND_API_KEY) {
    return { success: false, error: 'RESEND_API_KEY not configured' }
  }

  try {
    const payload: Record<string, unknown> = {
      from: `${FROM_NAME} <${FROM_EMAIL}>`,
      to: [to],
      subject,
      html: htmlBody,
    }
    if (textBody) payload.text = textBody
    if (replyTo) payload.reply_to = replyTo

    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    })

    const result = await response.json()

    if (response.ok) {
      console.log(`✅ Email sent via Resend to ${to}, id: ${result.id}`)
      return { success: true, messageId: result.id }
    } else {
      console.error('Resend Error:', JSON.stringify(result))
      return { success: false, error: result.message || 'Resend error' }
    }
  } catch (error) {
    console.error('Resend Request Error:', error)
    return { success: false, error: error.message }
  }
}

// ============================================================================
// Send Email via AWS SES API (Fallback)
// ============================================================================

async function sendViaSES(
  to: string,
  subject: string,
  htmlBody: string,
  textBody: string
): Promise<{ success: boolean; messageId?: string; error?: string }> {
  if (!AWS_ACCESS_KEY || !AWS_SECRET_KEY) {
    console.error('AWS SES credentials not configured')
    return { success: false, error: 'AWS SES not configured' }
  }

  const service = 'ses'
  const host = `email.${AWS_REGION}.amazonaws.com`
  const endpoint = `https://${host}/`
  const method = 'POST'

  // Build the request body
  const params = new URLSearchParams()
  params.append('Action', 'SendEmail')
  params.append('Version', '2010-12-01')
  params.append('Source', `${FROM_NAME} <${FROM_EMAIL}>`)
  params.append('Destination.ToAddresses.member.1', to)
  params.append('Message.Subject.Data', subject)
  params.append('Message.Subject.Charset', 'UTF-8')
  params.append('Message.Body.Html.Data', htmlBody)
  params.append('Message.Body.Html.Charset', 'UTF-8')
  params.append('Message.Body.Text.Data', textBody)
  params.append('Message.Body.Text.Charset', 'UTF-8')

  const requestBody = params.toString()
  const { amzDate, dateStamp } = getAmzDate()

  // Create canonical request
  const canonicalUri = '/'
  const canonicalQueryString = ''
  const payloadHash = toHex(await sha256(requestBody))

  const canonicalHeaders =
    `content-type:application/x-www-form-urlencoded\n` +
    `host:${host}\n` +
    `x-amz-date:${amzDate}\n`

  const signedHeaders = 'content-type;host;x-amz-date'

  const canonicalRequest =
    `${method}\n` +
    `${canonicalUri}\n` +
    `${canonicalQueryString}\n` +
    `${canonicalHeaders}\n` +
    `${signedHeaders}\n` +
    `${payloadHash}`

  // Create string to sign
  const algorithm = 'AWS4-HMAC-SHA256'
  const credentialScope = `${dateStamp}/${AWS_REGION}/${service}/aws4_request`
  const stringToSign =
    `${algorithm}\n` +
    `${amzDate}\n` +
    `${credentialScope}\n` +
    toHex(await sha256(canonicalRequest))

  // Calculate signature
  const signingKey = await getSignatureKey(AWS_SECRET_KEY, dateStamp, AWS_REGION, service)
  const signature = toHex(await hmac(signingKey, stringToSign))

  // Create authorization header
  const authorizationHeader =
    `${algorithm} Credential=${AWS_ACCESS_KEY}/${credentialScope}, ` +
    `SignedHeaders=${signedHeaders}, Signature=${signature}`

  try {
    const response = await fetch(endpoint, {
      method: method,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'X-Amz-Date': amzDate,
        'Authorization': authorizationHeader,
      },
      body: requestBody,
    })

    const responseText = await response.text()

    if (response.ok) {
      // Extract MessageId from XML response
      const messageIdMatch = responseText.match(/<MessageId>(.+?)<\/MessageId>/)
      const messageId = messageIdMatch ? messageIdMatch[1] : undefined

      console.log(`✅ Email sent to ${to}, MessageId: ${messageId}`)
      return { success: true, messageId }
    } else {
      console.error('SES Error Response:', responseText)
      const errorMatch = responseText.match(/<Message>(.+?)<\/Message>/)
      const errorMessage = errorMatch ? errorMatch[1] : 'Unknown SES error'
      return { success: false, error: errorMessage }
    }
  } catch (error) {
    console.error('SES Request Error:', error)
    return { success: false, error: error.message }
  }
}

// ============================================================================
// Email Templates
// ============================================================================

function getEarningsEmailTemplate(data: {
  driverName: string
  tripId: string
  totalAmount: number
  platformFee: number
  platformFeePercent?: number // Dynamic from admin panel
  driverEarnings: number
  tipAmount?: number
  pickupAddress?: string
  dropoffAddress?: string
  date: string
  currentBalance: number
}): { subject: string; html: string; text: string } {
  // Platform fee percent is dynamic - no hardcoded values
  const feePercent = data.platformFeePercent || Math.round((data.platformFee / data.totalAmount) * 100)
  const subject = `Toro: Ganaste $${data.driverEarnings.toFixed(2)} del viaje #${data.tripId.substring(0, 8)}`

  const html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Toro - Earnings Notification</title>
</head>
<body style="margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; background-color: #0a0a0a; color: #ffffff;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #0a0a0a; padding: 40px 20px;">
    <tr>
      <td align="center">
        <table width="600" cellpadding="0" cellspacing="0" style="background-color: #141414; border-left: 3px solid #22C55E;">
          <!-- Header -->
          <tr>
            <td style="padding: 30px; border-bottom: 1px solid #2A2A2A;">
              <table width="100%">
                <tr>
                  <td>
                    <h1 style="margin: 0; color: #22C55E; font-size: 24px; font-weight: 700;">TORO</h1>
                    <p style="margin: 5px 0 0 0; color: #9CA3AF; font-size: 12px;">Driver Earnings Notification</p>
                  </td>
                  <td align="right">
                    <span style="background: linear-gradient(135deg, #22C55E 0%, #16A34A 100%); color: white; padding: 8px 16px; font-size: 20px; font-weight: 700;">
                      +$${data.driverEarnings.toFixed(2)}
                    </span>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- Greeting -->
          <tr>
            <td style="padding: 30px 30px 20px 30px;">
              <p style="margin: 0; color: #ffffff; font-size: 16px;">
                Hola <strong>${data.driverName}</strong>,
              </p>
              <p style="margin: 10px 0 0 0; color: #9CA3AF; font-size: 14px;">
                Has completado un viaje exitosamente. Aquí está el desglose:
              </p>
            </td>
          </tr>

          <!-- Breakdown -->
          <tr>
            <td style="padding: 0 30px;">
              <table width="100%" style="background-color: #1a1a1a; border: 1px solid #2A2A2A;">
                <tr>
                  <td colspan="2" style="padding: 15px; border-bottom: 1px solid #2A2A2A;">
                    <span style="color: #9CA3AF; font-size: 11px; text-transform: uppercase; letter-spacing: 1px;">BREAKDOWN DEL VIAJE</span>
                  </td>
                </tr>
                <tr>
                  <td style="padding: 12px 15px; color: #9CA3AF; font-size: 14px;">Total cobrado al rider</td>
                  <td align="right" style="padding: 12px 15px; color: #ffffff; font-size: 14px; font-weight: 600;">$${data.totalAmount.toFixed(2)}</td>
                </tr>
                <tr>
                  <td style="padding: 12px 15px; color: #9CA3AF; font-size: 14px; border-top: 1px solid #2A2A2A;">Platform fee (${feePercent}%)</td>
                  <td align="right" style="padding: 12px 15px; color: #EF4444; font-size: 14px; border-top: 1px solid #2A2A2A;">-$${data.platformFee.toFixed(2)}</td>
                </tr>
                ${data.tipAmount && data.tipAmount > 0 ? `
                <tr>
                  <td style="padding: 12px 15px; color: #9CA3AF; font-size: 14px; border-top: 1px solid #2A2A2A;">Propina (100% tuya)</td>
                  <td align="right" style="padding: 12px 15px; color: #22C55E; font-size: 14px; border-top: 1px solid #2A2A2A;">+$${data.tipAmount.toFixed(2)}</td>
                </tr>
                ` : ''}
                <tr style="background-color: #22C55E10;">
                  <td style="padding: 15px; color: #22C55E; font-size: 16px; font-weight: 700; border-top: 2px solid #22C55E;">TU GANANCIA</td>
                  <td align="right" style="padding: 15px; color: #22C55E; font-size: 20px; font-weight: 700; border-top: 2px solid #22C55E;">$${data.driverEarnings.toFixed(2)}</td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- Trip Details -->
          ${data.pickupAddress || data.dropoffAddress ? `
          <tr>
            <td style="padding: 20px 30px;">
              <table width="100%" style="background-color: #1a1a1a; border: 1px solid #2A2A2A;">
                <tr>
                  <td colspan="2" style="padding: 15px; border-bottom: 1px solid #2A2A2A;">
                    <span style="color: #9CA3AF; font-size: 11px; text-transform: uppercase; letter-spacing: 1px;">DETALLES DEL VIAJE</span>
                  </td>
                </tr>
                ${data.pickupAddress ? `
                <tr>
                  <td style="padding: 12px 15px; color: #9CA3AF; font-size: 14px;">Origen</td>
                  <td style="padding: 12px 15px; color: #ffffff; font-size: 14px;">${data.pickupAddress}</td>
                </tr>
                ` : ''}
                ${data.dropoffAddress ? `
                <tr>
                  <td style="padding: 12px 15px; color: #9CA3AF; font-size: 14px; border-top: 1px solid #2A2A2A;">Destino</td>
                  <td style="padding: 12px 15px; color: #ffffff; font-size: 14px; border-top: 1px solid #2A2A2A;">${data.dropoffAddress}</td>
                </tr>
                ` : ''}
                <tr>
                  <td style="padding: 12px 15px; color: #9CA3AF; font-size: 14px; border-top: 1px solid #2A2A2A;">Fecha</td>
                  <td style="padding: 12px 15px; color: #ffffff; font-size: 14px; border-top: 1px solid #2A2A2A;">${data.date}</td>
                </tr>
              </table>
            </td>
          </tr>
          ` : ''}

          <!-- Current Balance -->
          <tr>
            <td style="padding: 0 30px 30px 30px;">
              <table width="100%" style="background: linear-gradient(135deg, #3B82F620 0%, #1D4ED820 100%); border-left: 3px solid #3B82F6;">
                <tr>
                  <td style="padding: 20px;">
                    <p style="margin: 0; color: #9CA3AF; font-size: 12px; text-transform: uppercase; letter-spacing: 1px;">BALANCE DISPONIBLE</p>
                    <p style="margin: 5px 0 0 0; color: #3B82F6; font-size: 28px; font-weight: 700;">$${data.currentBalance.toFixed(2)}</p>
                    <p style="margin: 10px 0 0 0; color: #9CA3AF; font-size: 12px;">Solicita tu payout cuando quieras desde la app.</p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="padding: 20px 30px; background-color: #0a0a0a; border-top: 1px solid #2A2A2A;">
              <p style="margin: 0; color: #6B7280; font-size: 12px; text-align: center;">
                Este es un email automático de Toro. No respondas a este mensaje.
              </p>
              <p style="margin: 10px 0 0 0; color: #6B7280; font-size: 11px; text-align: center;">
                Trip ID: ${data.tripId} | ${data.date}
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
`

  const text = `
TORO - Driver Earnings Notification

Hola ${data.driverName},

Has completado un viaje exitosamente.

BREAKDOWN:
- Total cobrado: $${data.totalAmount.toFixed(2)}
- Platform fee (${feePercent}%): -$${data.platformFee.toFixed(2)}
${data.tipAmount ? `- Propina: +$${data.tipAmount.toFixed(2)}` : ''}
- TU GANANCIA: $${data.driverEarnings.toFixed(2)}

${data.pickupAddress ? `Origen: ${data.pickupAddress}` : ''}
${data.dropoffAddress ? `Destino: ${data.dropoffAddress}` : ''}
Fecha: ${data.date}

BALANCE DISPONIBLE: $${data.currentBalance.toFixed(2)}

Solicita tu payout cuando quieras desde la app.

---
Trip ID: ${data.tripId}
Este es un email automático de Toro.
`

  return { subject, html, text }
}

function getPayoutEmailTemplate(data: {
  driverName: string
  amount: number
  payoutId: string
  method: string
  status: string
  arrivalDate?: string
}): { subject: string; html: string; text: string } {
  const subject = `Toro: Payout de $${data.amount.toFixed(2)} ${data.status === 'paid' ? 'enviado' : 'procesando'}`

  const html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Toro - Payout Notification</title>
</head>
<body style="margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif; background-color: #0a0a0a; color: #ffffff;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #0a0a0a; padding: 40px 20px;">
    <tr>
      <td align="center">
        <table width="600" cellpadding="0" cellspacing="0" style="background-color: #141414; border-left: 3px solid #8B5CF6;">
          <tr>
            <td style="padding: 30px;">
              <h1 style="margin: 0; color: #8B5CF6; font-size: 24px;">TORO</h1>
              <p style="color: #9CA3AF; font-size: 12px;">Payout Notification</p>
            </td>
          </tr>
          <tr>
            <td style="padding: 0 30px 30px 30px;">
              <p style="color: #ffffff;">Hola ${data.driverName},</p>
              <p style="color: #9CA3AF;">Tu payout de <strong style="color: #8B5CF6; font-size: 20px;">$${data.amount.toFixed(2)}</strong> está ${data.status === 'paid' ? 'en camino' : 'procesándose'}.</p>
              <table width="100%" style="background-color: #1a1a1a; margin-top: 20px;">
                <tr>
                  <td style="padding: 15px; color: #9CA3AF;">Método</td>
                  <td style="padding: 15px; color: #ffffff;">${data.method === 'instant' ? 'Instant Payout' : 'Standard Payout'}</td>
                </tr>
                <tr>
                  <td style="padding: 15px; color: #9CA3AF; border-top: 1px solid #2A2A2A;">Estado</td>
                  <td style="padding: 15px; color: ${data.status === 'paid' ? '#22C55E' : '#EAB308'}; border-top: 1px solid #2A2A2A;">${data.status === 'paid' ? 'Enviado' : 'Procesando'}</td>
                </tr>
                ${data.arrivalDate ? `
                <tr>
                  <td style="padding: 15px; color: #9CA3AF; border-top: 1px solid #2A2A2A;">Llegada estimada</td>
                  <td style="padding: 15px; color: #ffffff; border-top: 1px solid #2A2A2A;">${data.arrivalDate}</td>
                </tr>
                ` : ''}
              </table>
            </td>
          </tr>
          <tr>
            <td style="padding: 20px 30px; background-color: #0a0a0a; border-top: 1px solid #2A2A2A;">
              <p style="color: #6B7280; font-size: 12px; text-align: center;">Payout ID: ${data.payoutId}</p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
`

  const text = `
TORO - Payout Notification

Hola ${data.driverName},

Tu payout de $${data.amount.toFixed(2)} está ${data.status === 'paid' ? 'en camino' : 'procesándose'}.

Método: ${data.method === 'instant' ? 'Instant Payout' : 'Standard Payout'}
Estado: ${data.status === 'paid' ? 'Enviado' : 'Procesando'}
${data.arrivalDate ? `Llegada estimada: ${data.arrivalDate}` : ''}

Payout ID: ${data.payoutId}
`

  return { subject, html, text }
}

// ============================================================================
// Trip Receipt Template (Rider) - Viaje completado o cancelado
// ============================================================================

// Waypoint/stop for multi-destination trips
interface TripWaypoint {
  name: string
  arrivalTime?: string
  waitMinutes?: number
  waitFee?: number
}

// Leg/segment pricing for multi-destination trips
interface TripLeg {
  from: string
  to: string
  distance: string
  duration: string
  amount: number
}

function getTripReceiptTemplate(data: {
  riderName: string
  userId: string
  userEmail: string
  tripId: string
  ticketNumber: number
  date: string
  time: string
  origin: string
  destination: string
  waypoints?: TripWaypoint[] // Intermediate stops
  legs?: TripLeg[] // Per-leg pricing breakdown
  rideAmount: number
  waitFeeTotal?: number // Total wait time fees
  tipAmount?: number
  totalAmount: number
  paymentMethod: string // "Visa •••• 4242"
  status: 'completed' | 'cancelled'
}): { subject: string; html: string; text: string } {
  const statusText = data.status === 'completed' ? 'completado' : 'cancelado'
  const subject = `TORO - Tu recibo de viaje #${data.ticketNumber}`
  const hasMultipleStops = data.waypoints && data.waypoints.length > 0

  // Build route display (A → B → C → D)
  let routeHtml = ''
  let routeText = ''
  if (hasMultipleStops) {
    const stops = [data.origin, ...data.waypoints!.map(w => w.name), data.destination]
    routeHtml = stops.map((stop, i) => {
      const letter = String.fromCharCode(65 + i) // A, B, C, D...
      const isLast = i === stops.length - 1
      const color = i === 0 ? '#00FF66' : (isLast ? '#FF0066' : '#00BFFF')
      return `<div style="display:flex;align-items:center;margin:4px 0"><span style="display:inline-block;width:20px;height:20px;border-radius:50%;background:${color};color:#fff;text-align:center;line-height:20px;font-size:11px;font-weight:bold;margin-right:8px">${letter}</span><span style="color:#1a1a1a;font-size:13px">${stop}</span></div>`
    }).join('')
    routeText = stops.map((stop, i) => `${String.fromCharCode(65 + i)}: ${stop}`).join('\n')
  } else {
    routeHtml = `<p style="margin:0;color:#666;font-size:13px">${data.origin} → ${data.destination}</p>`
    routeText = `${data.origin} → ${data.destination}`
  }

  // Build charges rows with per-leg breakdown
  let chargesHtml = ''
  let chargesText = ''

  if (data.status === 'completed') {
    // Show per-leg breakdown if available
    if (data.legs && data.legs.length > 0) {
      chargesHtml = data.legs.map((leg, i) => `
        <tr><td style="padding:8px 0;color:#666;font-size:13px;border-bottom:1px solid #f0f0f0">${leg.from} → ${leg.to}<br><span style="font-size:11px;color:#999">${leg.distance} • ${leg.duration}</span></td><td align="right" style="padding:8px 0;color:#1a1a1a;font-size:14px;border-bottom:1px solid #f0f0f0">$${leg.amount.toFixed(2)}</td></tr>
      `).join('')
      chargesText = data.legs.map(leg => `${leg.from} → ${leg.to}: $${leg.amount.toFixed(2)}`).join('\n')

      // Add wait time fees if any
      if (data.waitFeeTotal && data.waitFeeTotal > 0) {
        chargesHtml += `<tr><td style="padding:8px 0;color:#666;font-size:13px;border-bottom:1px solid #f0f0f0">Wait time fee</td><td align="right" style="padding:8px 0;color:#F59E0B;font-size:14px;border-bottom:1px solid #f0f0f0">$${data.waitFeeTotal.toFixed(2)}</td></tr>`
        chargesText += `\nWait time fee: $${data.waitFeeTotal.toFixed(2)}`
      }
    } else {
      // Simple ride without breakdown
      chargesHtml = `<tr><td style="padding:12px 0;color:#666;font-size:14px;border-bottom:1px solid #f0f0f0">Ride</td><td align="right" style="padding:12px 0;color:#1a1a1a;font-size:14px;border-bottom:1px solid #f0f0f0">$${data.rideAmount.toFixed(2)}</td></tr>`
      chargesText = `Ride: $${data.rideAmount.toFixed(2)}`
    }

    // Add tip if present
    if (data.tipAmount && data.tipAmount > 0) {
      chargesHtml += `<tr><td style="padding:12px 0;color:#666;font-size:14px;border-bottom:1px solid #f0f0f0">Tip</td><td align="right" style="padding:12px 0;color:#22C55E;font-size:14px;border-bottom:1px solid #f0f0f0">$${data.tipAmount.toFixed(2)}</td></tr>`
      chargesText += `\nTip: $${data.tipAmount.toFixed(2)}`
    }
  } else {
    // Cancelled - show cancellation fee
    chargesHtml = `
      <tr><td style="padding:12px 0;color:#666;font-size:14px;border-bottom:1px solid #f0f0f0">Cancellation Fee</td><td align="right" style="padding:12px 0;color:#EF4444;font-size:14px;border-bottom:1px solid #f0f0f0">$${data.rideAmount.toFixed(2)}</td></tr>
    `
    chargesText = `Cancellation Fee: $${data.rideAmount.toFixed(2)}`
  }

  // Short user ID for display
  const shortUserId = data.userId.substring(0, 8).toUpperCase()

  const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"></head><body style="margin:0;padding:0;font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Arial,sans-serif;background:#f0f0f0"><table width="100%" cellpadding="0" cellspacing="0" style="background:#f0f0f0;padding:20px 0"><tr><td align="center"><table width="400" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,0.1)"><tr><td style="background:linear-gradient(180deg,#ffffff 0%,#f8f8f8 100%);padding:16px;text-align:center;border-bottom:1px solid #e0e0e0"><table width="100%"><tr><td align="center"><div style="width:44px;height:44px;background:linear-gradient(135deg,#00BFFF 0%,#0099FF 50%,#0066CC 100%);border-radius:10px;display:inline-block;line-height:44px;font-size:24px;font-weight:800;color:#ffffff;font-family:Arial Black,sans-serif">T</div></td></tr><tr><td align="center" style="padding-top:8px"><p style="margin:0;color:#0099FF;font-size:10px;text-transform:uppercase;letter-spacing:2px">Trip Receipt</p></td></tr></table></td></tr><tr><td style="padding:24px;background:#ffffff"><table width="100%" style="margin-bottom:16px;background:#f8f9fa;border-radius:8px;padding:12px"><tr><td style="padding:4px 0;color:#999;font-size:11px">User ID:</td><td style="padding:4px 0;color:#1a1a1a;font-size:12px;font-weight:500">${shortUserId}</td></tr><tr><td style="padding:4px 0;color:#999;font-size:11px">Name:</td><td style="padding:4px 0;color:#1a1a1a;font-size:12px;font-weight:500">${data.riderName}</td></tr><tr><td style="padding:4px 0;color:#999;font-size:11px">Email:</td><td style="padding:4px 0;color:#1a1a1a;font-size:12px;font-weight:500">${data.userEmail}</td></tr><tr><td style="padding:4px 0;color:#999;font-size:11px">Date:</td><td style="padding:4px 0;color:#1a1a1a;font-size:12px;font-weight:500">${data.date}</td></tr></table><table width="100%"><tr><td style="padding-bottom:20px;border-bottom:1px solid #e8e8e8"><p style="margin:0;color:#999;font-size:10px;text-transform:uppercase;letter-spacing:1px">Trip Summary</p><p style="margin:10px 0 6px 0;color:#1a1a1a;font-size:14px;font-weight:600">${data.date} at ${data.time}</p>${routeHtml}</td></tr></table><table width="100%" style="margin-top:20px">${chargesHtml}</table><table width="100%" style="margin-top:16px;border-top:2px solid #0099FF;padding-top:16px"><tr><td style="color:#1a1a1a;font-size:16px;font-weight:600">Total</td><td align="right" style="color:#0099FF;font-size:32px;font-weight:700">$${data.totalAmount.toFixed(2)}</td></tr><tr><td colspan="2" align="right" style="padding-top:8px"><p style="margin:0;color:#666;font-size:14px;font-weight:500">${data.paymentMethod}</p></td></tr></table><table width="100%" style="margin-top:24px;background:#f0fff4;border-radius:10px;border:1px solid #22C55E40"><tr><td style="padding:16px"><p style="margin:0;color:#666;font-size:12px;line-height:1.6;text-align:center">Gracias por apoyar la economía local.<br><span style="color:#22C55E">Nos esforzamos por pagar lo mejor a nuestros drivers.</span></p></td></tr></table></td></tr><tr><td style="background:#fafafa;padding:16px;border-top:1px solid #e8e8e8"><table width="100%"><tr><td style="color:#888;font-size:12px">Receipt #${data.ticketNumber}</td></tr><tr><td style="padding-top:10px;text-align:center"><p style="margin:0;font-size:14px"><a href="https://toro-ride.com" style="color:#0099FF;text-decoration:none;font-weight:500">toro-ride.com</a></p><p style="margin:6px 0 0 0;font-size:14px"><a href="mailto:support@toro-ride.com" style="color:#0099FF;text-decoration:none;font-weight:500">support@toro-ride.com</a></p></td></tr></table></td></tr></table></td></tr></table></body></html>`

  const text = `TORO - Trip Receipt #${data.ticketNumber}

User ID: ${shortUserId}
Name: ${data.riderName}
Email: ${data.userEmail}
Date: ${data.date}

Trip Summary
${data.date} at ${data.time}
${routeText}

${chargesText}

Total: $${data.totalAmount.toFixed(2)}
${data.paymentMethod}

Gracias por apoyar la economia local.

toro-ride.com
support@toro-ride.com`

  return { subject, html, text }
}

// ============================================================================
// Trip Summary Report Template (Download/Share all trips)
// ============================================================================

interface TripItem {
  number: number
  date: string
  origin: string
  destination: string
  amount: number
  status: 'completed' | 'cancelled'
}

function getTripSummaryTemplate(data: {
  riderName: string
  userId: string
  userEmail: string
  year: number
  totalTrips: number
  completedTrips: number
  cancelledTrips: number
  totalAmount: number
  trips: TripItem[]
  generatedDate: string
}): { subject: string; html: string; text: string } {
  const subject = `TORO - Resumen de Viajes ${data.year}`

  // Short user ID for display
  const shortUserId = data.userId.substring(0, 8).toUpperCase()

  // Build trips table rows
  let tripsHtml = ''
  let tripsText = ''
  const displayTrips = data.trips.slice(0, 10) // Show first 10 in email
  const remainingTrips = data.totalTrips - displayTrips.length

  displayTrips.forEach((trip, index) => {
    const bgColor = index % 2 === 0 ? '#ffffff' : '#fafafa'
    const statusBg = trip.status === 'completed' ? '#DCFCE7' : '#FEE2E2'
    const statusColor = trip.status === 'completed' ? '#22C55E' : '#EF4444'
    const statusText = trip.status === 'completed' ? 'COMPLETADO' : 'CANCELADO'

    // Shorten addresses for table
    const shortOrigin = trip.origin.length > 15 ? trip.origin.substring(0, 15) + '...' : trip.origin
    const shortDest = trip.destination.length > 15 ? trip.destination.substring(0, 15) + '...' : trip.destination

    tripsHtml += `<tr style="background:${bgColor}"><td style="padding:10px;font-size:12px;color:#1a1a1a;border-bottom:1px solid #f0f0f0">#${trip.number}</td><td style="padding:10px;font-size:12px;color:#666;border-bottom:1px solid #f0f0f0">${trip.date}</td><td style="padding:10px;font-size:11px;color:#666;border-bottom:1px solid #f0f0f0">${shortOrigin} → ${shortDest}</td><td align="right" style="padding:10px;font-size:12px;color:#1a1a1a;font-weight:500;border-bottom:1px solid #f0f0f0">$${trip.amount.toFixed(2)}</td><td align="center" style="padding:10px;border-bottom:1px solid #f0f0f0"><span style="background:${statusBg};color:${statusColor};padding:2px 8px;border-radius:4px;font-size:10px">${statusText}</span></td></tr>`

    tripsText += `#${trip.number} - ${trip.date} - ${trip.origin} → ${trip.destination} - $${trip.amount.toFixed(2)} - ${statusText}\n`
  })

  if (remainingTrips > 0) {
    tripsHtml += `<tr style="background:#f8f9fa"><td colspan="5" style="padding:12px;text-align:center;color:#999;font-size:11px">... y ${remainingTrips} viajes más</td></tr>`
    tripsText += `... y ${remainingTrips} viajes más\n`
  }

  const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"></head><body style="margin:0;padding:0;font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Arial,sans-serif;background:#f0f0f0"><table width="100%" cellpadding="0" cellspacing="0" style="background:#f0f0f0;padding:20px 0"><tr><td align="center"><table width="600" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,0.1)"><tr><td style="background:linear-gradient(180deg,#ffffff 0%,#f8f8f8 100%);padding:20px;text-align:center;border-bottom:1px solid #e0e0e0"><table width="100%"><tr><td align="center"><div style="width:44px;height:44px;background:linear-gradient(135deg,#00BFFF 0%,#0099FF 50%,#0066CC 100%);border-radius:10px;display:inline-block;line-height:44px;font-size:24px;font-weight:800;color:#ffffff;font-family:Arial Black,sans-serif">T</div></td></tr><tr><td align="center" style="padding-top:8px"><p style="margin:0;color:#0099FF;font-size:10px;text-transform:uppercase;letter-spacing:2px">Trip Summary Report</p></td></tr></table></td></tr><tr><td style="padding:24px;background:#ffffff"><table width="100%" style="margin-bottom:16px;background:#f8f9fa;border-radius:8px;padding:12px"><tr><td style="padding:4px 0;color:#999;font-size:11px">User ID:</td><td style="padding:4px 0;color:#1a1a1a;font-size:12px;font-weight:500">${shortUserId}</td></tr><tr><td style="padding:4px 0;color:#999;font-size:11px">Name:</td><td style="padding:4px 0;color:#1a1a1a;font-size:12px;font-weight:500">${data.riderName}</td></tr><tr><td style="padding:4px 0;color:#999;font-size:11px">Email:</td><td style="padding:4px 0;color:#1a1a1a;font-size:12px;font-weight:500">${data.userEmail}</td></tr><tr><td style="padding:4px 0;color:#999;font-size:11px">Date:</td><td style="padding:4px 0;color:#1a1a1a;font-size:12px;font-weight:500">${data.generatedDate}</td></tr></table><table width="100%" style="margin-bottom:20px;background:#f8f9fa;border-radius:12px;padding:16px"><tr><td colspan="2" style="padding-bottom:12px;border-bottom:1px solid #e8e8e8"><p style="margin:0;color:#999;font-size:10px;text-transform:uppercase;letter-spacing:1px">Resumen Financiero - ${data.year}</p></td></tr><tr><td style="padding:12px 0;color:#666;font-size:14px">Total Viajes</td><td align="right" style="padding:12px 0;color:#1a1a1a;font-size:14px;font-weight:600">${data.totalTrips}</td></tr><tr><td style="padding:12px 0;color:#666;font-size:14px">Completados</td><td align="right" style="padding:12px 0;color:#22C55E;font-size:14px;font-weight:600">${data.completedTrips}</td></tr><tr><td style="padding:12px 0;color:#666;font-size:14px">Cancelados</td><td align="right" style="padding:12px 0;color:#EF4444;font-size:14px;font-weight:600">${data.cancelledTrips}</td></tr><tr><td colspan="2" style="padding:16px 0 8px 0;border-top:2px solid #0099FF"></td></tr><tr><td style="color:#1a1a1a;font-size:16px;font-weight:600">Total Gastado</td><td align="right" style="color:#0099FF;font-size:24px;font-weight:700">$${data.totalAmount.toFixed(2)}</td></tr></table><table width="100%" style="border:1px solid #e8e8e8;border-radius:8px;overflow:hidden"><tr style="background:#f8f9fa"><td style="padding:10px;font-size:11px;color:#666;font-weight:600;border-bottom:1px solid #e8e8e8">#</td><td style="padding:10px;font-size:11px;color:#666;font-weight:600;border-bottom:1px solid #e8e8e8">Fecha</td><td style="padding:10px;font-size:11px;color:#666;font-weight:600;border-bottom:1px solid #e8e8e8">Ruta</td><td align="right" style="padding:10px;font-size:11px;color:#666;font-weight:600;border-bottom:1px solid #e8e8e8">Total</td><td align="center" style="padding:10px;font-size:11px;color:#666;font-weight:600;border-bottom:1px solid #e8e8e8">Estado</td></tr>${tripsHtml}</table><table width="100%" style="margin-top:24px;background:#f0fff4;border-radius:10px;border:1px solid #22C55E40"><tr><td style="padding:16px"><p style="margin:0;color:#666;font-size:12px;line-height:1.6;text-align:center">Gracias por apoyar la economía local.<br><span style="color:#22C55E">Nos esforzamos por pagar lo mejor a nuestros drivers.</span></p></td></tr></table></td></tr><tr><td style="background:#fafafa;padding:16px;border-top:1px solid #e8e8e8"><table width="100%"><tr><td style="color:#888;font-size:12px">Generado: ${data.generatedDate}</td></tr><tr><td style="padding-top:10px;text-align:center"><p style="margin:0;font-size:14px"><a href="https://toro-ride.com" style="color:#0099FF;text-decoration:none;font-weight:500">toro-ride.com</a></p><p style="margin:6px 0 0 0;font-size:14px"><a href="mailto:support@toro-ride.com" style="color:#0099FF;text-decoration:none;font-weight:500">support@toro-ride.com</a></p></td></tr></table></td></tr></table></td></tr></table></body></html>`

  const text = `TORO - Trip Summary Report ${data.year}

User ID: ${shortUserId}
Name: ${data.riderName}
Email: ${data.userEmail}
Date: ${data.generatedDate}

Resumen Financiero
Total Viajes: ${data.totalTrips}
Completados: ${data.completedTrips}
Cancelados: ${data.cancelledTrips}
Total Gastado: $${data.totalAmount.toFixed(2)}

Viajes:
${tripsText}
Generado: ${data.generatedDate}

toro-ride.com
support@toro-ride.com`

  return { subject, html, text }
}

// ============================================================================
// Main Handler
// ============================================================================

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseKey)

    const body: SendEmailRequest = await req.json()
    const { to, subject, html, text, template, templateData } = body

    if (!to) {
      return new Response(
        JSON.stringify({ error: 'Recipient email (to) is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    let finalSubject = subject
    let finalHtml = html
    let finalText = text || ''

    // Use template if specified
    if (template && templateData) {
      switch (template) {
        case 'earnings': {
          const emailContent = getEarningsEmailTemplate(templateData as Parameters<typeof getEarningsEmailTemplate>[0])
          finalSubject = emailContent.subject
          finalHtml = emailContent.html
          finalText = emailContent.text
          break
        }
        case 'payout': {
          const emailContent = getPayoutEmailTemplate(templateData as Parameters<typeof getPayoutEmailTemplate>[0])
          finalSubject = emailContent.subject
          finalHtml = emailContent.html
          finalText = emailContent.text
          break
        }
        case 'receipt': {
          const emailContent = getTripReceiptTemplate(templateData as Parameters<typeof getTripReceiptTemplate>[0])
          finalSubject = emailContent.subject
          finalHtml = emailContent.html
          finalText = emailContent.text
          break
        }
        case 'summary': {
          const emailContent = getTripSummaryTemplate(templateData as Parameters<typeof getTripSummaryTemplate>[0])
          finalSubject = emailContent.subject
          finalHtml = emailContent.html
          finalText = emailContent.text
          break
        }
        default:
          // Use provided subject/html/text
          break
      }
    }

    if (!finalSubject || !finalHtml) {
      return new Response(
        JSON.stringify({ error: 'Subject and HTML body are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Send email: try Resend first, fall back to SES
    let result = await sendViaResend(to, finalSubject, finalHtml, finalText, body.replyTo)
    const resendError = result.success ? null : result.error
    const provider = result.success ? 'resend' : 'resend_failed'

    // Fallback to SES if Resend fails
    if (!result.success) {
      console.warn(`Resend failed (${result.error}), trying SES fallback...`)
      result = await sendViaSES(to, finalSubject, finalHtml, finalText)
    }

    // Log email in database (non-blocking)
    try {
      await supabase.from('email_log').insert({
        to_email: to,
        subject: finalSubject,
        template: template || 'custom',
        status: result.success ? 'sent' : 'failed',
        message_id: result.messageId,
        error: result.error,
        sent_at: new Date().toISOString(),
      }).then(() => {}).catch(() => {})
    } catch (logError) {
      console.warn('Could not log email:', logError)
    }

    if (result.success) {
      return new Response(
        JSON.stringify({
          success: true,
          messageId: result.messageId,
          to,
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    } else {
      return new Response(
        JSON.stringify({
          success: false,
          error: result.error,
          resend_error: resendError,
          ses_error: result.error,
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

  } catch (error) {
    console.error('Send Email Error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
