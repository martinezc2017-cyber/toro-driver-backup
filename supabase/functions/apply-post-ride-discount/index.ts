// Edge Function: apply-post-ride-discount
// Issues a post-ride discount voucher to a rider after they complete a paid ride.
// Reads discount % and validity from promo_phases for the country.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface ApplyDiscountRequest {
  rider_id: string
  ride_id: string
  country_code?: string
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const client = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } }
    )

    const { rider_id, ride_id, country_code = 'MX' } = await req.json() as ApplyDiscountRequest

    if (!rider_id || !ride_id) {
      return new Response(
        JSON.stringify({ success: false, error: 'rider_id and ride_id are required' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    // 1) Read active phase
    const { data: phase, error: phaseError } = await client
      .from('promo_phases')
      .select('post_ride_discount_pct, post_ride_validity_hours, phase, is_active')
      .eq('country_code', country_code)
      .eq('is_active', true)
      .maybeSingle()

    if (phaseError || !phase) {
      return new Response(
        JSON.stringify({ success: false, error: 'No active promo phase', country_code }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 404 }
      )
    }

    const discountPct = Number(phase.post_ride_discount_pct)
    const validityHours = Number(phase.post_ride_validity_hours)

    if (discountPct <= 0 || validityHours <= 0) {
      return new Response(
        JSON.stringify({ success: true, skipped: true, reason: 'Phase has no post-ride discount', phase: phase.phase }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
      )
    }

    // 2) Idempotency: ensure we haven't already issued a voucher for this ride
    const { data: existing } = await client
      .from('promo_vouchers')
      .select('id')
      .eq('source_ride_id', ride_id)
      .eq('voucher_type', 'post_ride_discount')
      .limit(1)

    if (existing && existing.length > 0) {
      return new Response(
        JSON.stringify({ success: true, skipped: true, reason: 'Voucher already issued for this ride' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
      )
    }

    // 3) Issue voucher
    const now = new Date()
    const expiresAt = new Date(now.getTime() + validityHours * 60 * 60 * 1000)

    const { data: voucher, error: insertError } = await client
      .from('promo_vouchers')
      .insert({
        user_id: rider_id,
        voucher_type: 'post_ride_discount',
        discount_pct: discountPct,
        country_code,
        source_ride_id: ride_id,
        expires_at: expiresAt.toISOString(),
        status: 'active',
        notes: `Post-ride ${discountPct}% off, valid ${validityHours}h (phase: ${phase.phase})`,
      })
      .select()
      .single()

    if (insertError) {
      return new Response(
        JSON.stringify({
          success: false,
          error: insertError.message,
          details: insertError.details,
          hint: insertError.hint,
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
      )
    }

    return new Response(
      JSON.stringify({
        success: true,
        data: {
          voucher_id: voucher.id,
          rider_id,
          ride_id,
          discount_pct: discountPct,
          expires_at: expiresAt.toISOString(),
          phase: phase.phase,
        },
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
