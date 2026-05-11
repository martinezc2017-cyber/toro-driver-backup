// Edge Function: apply-referral-bonus
// Triggered when a referred rider completes their first ride.
// Credits both referrer and referee with wallet_lots bonus that expires.
// Reads parameters from promo_phases for the country.
// Idempotent via unique partial index on (user_id, source_ride_id) WHERE lot_type='referral'.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface ApplyReferralRequest {
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

    const { rider_id, ride_id, country_code = 'MX' } = await req.json() as ApplyReferralRequest

    if (!rider_id || !ride_id) {
      return new Response(
        JSON.stringify({ success: false, error: 'rider_id and ride_id are required' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    // 1) Read active promo phase
    const { data: phase, error: phaseError } = await client
      .from('promo_phases')
      .select('referral_bonus_amount, referral_expiry_hours, phase, is_active')
      .eq('country_code', country_code)
      .eq('is_active', true)
      .maybeSingle()

    if (phaseError || !phase) {
      return new Response(
        JSON.stringify({ success: false, error: 'No active promo phase', country_code }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 404 }
      )
    }

    const bonusAmount = Number(phase.referral_bonus_amount)
    const expiryHours = Number(phase.referral_expiry_hours)

    if (bonusAmount <= 0) {
      return new Response(
        JSON.stringify({ success: true, skipped: true, reason: 'Phase has 0 bonus', phase: phase.phase }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
      )
    }

    // 2) Check this is rider's FIRST completed ride (anti-abuse)
    const { data: firstRideCheck } = await client
      .rpc('is_first_completed_ride', { p_user_id: rider_id, p_ride_id: ride_id })

    if (firstRideCheck === false) {
      return new Response(
        JSON.stringify({ success: true, skipped: true, reason: 'Not rider first completed ride' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
      )
    }

    // 3) Look up rider's referrer
    const { data: rider, error: riderError } = await client
      .from('profiles')
      .select('id, referred_by')
      .eq('id', rider_id)
      .maybeSingle()

    if (riderError || !rider) {
      return new Response(
        JSON.stringify({ success: false, error: 'Rider not found', rider_id }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 404 }
      )
    }

    if (!rider.referred_by) {
      return new Response(
        JSON.stringify({ success: true, skipped: true, reason: 'Rider has no referrer' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
      )
    }

    // 4) Resolve referrer (referred_by could be code or UUID)
    let referrerId: string | null = null
    const { data: byCode } = await client
      .from('profiles')
      .select('id')
      .eq('referral_code', rider.referred_by)
      .maybeSingle()

    if (byCode) {
      referrerId = byCode.id
    } else {
      // Try as UUID directly
      const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
      if (uuidRegex.test(rider.referred_by)) {
        const { data: byId } = await client
          .from('profiles')
          .select('id')
          .eq('id', rider.referred_by)
          .maybeSingle()
        if (byId) referrerId = byId.id
      }
    }

    if (!referrerId) {
      return new Response(
        JSON.stringify({ success: false, error: 'Referrer not found', referred_by: rider.referred_by }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 404 }
      )
    }

    // 5) Get/create wallets for both
    const { data: refWallet } = await client.rpc('get_or_create_wallet', { p_user_id: referrerId, p_country: country_code })
    const { data: riderWallet } = await client.rpc('get_or_create_wallet', { p_user_id: rider_id, p_country: country_code })

    if (!refWallet || !riderWallet) {
      return new Response(
        JSON.stringify({ success: false, error: 'Wallet creation failed' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
      )
    }

    // 6) Insert wallet_lots (idempotent via unique index)
    const now = new Date()
    const expiresAt = new Date(now.getTime() + expiryHours * 60 * 60 * 1000)

    const lots = [
      {
        wallet_id: refWallet,
        user_id: referrerId,
        original_amount: bonusAmount,
        remaining_amount: bonusAmount,
        purchased_amount: 0,
        bonus_amount: bonusAmount,
        lot_type: 'referral',
        priority_order: 1,
        expires_at: expiresAt.toISOString(),
        status: 'active',
        source_ride_id: ride_id,
        country_code,
        notes: `Referral bonus: rider ${rider_id} completed first ride`,
      },
      {
        wallet_id: riderWallet,
        user_id: rider_id,
        original_amount: bonusAmount,
        remaining_amount: bonusAmount,
        purchased_amount: 0,
        bonus_amount: bonusAmount,
        lot_type: 'referral',
        priority_order: 1,
        expires_at: expiresAt.toISOString(),
        status: 'active',
        source_ride_id: ride_id,
        country_code,
        notes: `Welcome referral: invited by ${referrerId}`,
      },
    ]

    // Upsert with onConflict on the unique index — idempotent
    const { data: insertedLots, error: insertError } = await client
      .from('wallet_lots')
      .upsert(lots, { onConflict: 'user_id,source_ride_id', ignoreDuplicates: true })
      .select()

    if (insertError) {
      return new Response(
        JSON.stringify({
          success: false,
          error: insertError.message,
          details: insertError.details,
          hint: insertError.hint,
          code: insertError.code,
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
      )
    }

    return new Response(
      JSON.stringify({
        success: true,
        data: {
          referrer_id: referrerId,
          rider_id,
          ride_id,
          bonus_amount: bonusAmount,
          expires_at: expiresAt.toISOString(),
          phase: phase.phase,
          lots_created: insertedLots?.length ?? 0,
          already_existed: (insertedLots?.length ?? 0) === 0,
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
