// Edge Function: pricing-quote-mx
// Calculate ride/delivery pricing for Mexico

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface PricingQuoteRequest {
  pickup_lat: number
  pickup_lng: number
  dropoff_lat: number
  dropoff_lng: number
  distance_km: number
  duration_min: number
  service_type?: string // 'ride' | 'delivery' | 'carpool'
  vehicle_type?: string // 'standard' | 'premium' | 'moto'
  tolls?: number
  display_currency?: string // 'MXN' | 'USD'
}

interface PricingQuoteResponse {
  success: boolean
  data?: {
    zone_id: number
    zone_name: string
    currency: string

    // Breakdown
    base_fare: number
    distance_km: number
    distance_amount: number
    duration_min: number
    time_amount: number
    booking_fee: number

    // Multipliers
    is_night: boolean
    night_multiplier: number
    is_weekend: boolean
    weekend_multiplier: number
    surge_multiplier: number
    surge_amount: number

    // Extras
    tolls: number

    // Totals
    subtotal: number
    tax_rate: number
    tax_amount: number
    total: number

    // Split
    platform_fee: number
    driver_earnings: number

    // For display in other currency
    fx_rate?: number
    total_display?: number
    display_currency?: string

    // Flags
    min_fare_applied: boolean
  }
  error?: string
}

serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false
        }
      }
    )

    const body: PricingQuoteRequest = await req.json()
    const {
      pickup_lat,
      pickup_lng,
      dropoff_lat,
      dropoff_lng,
      distance_km,
      duration_min,
      service_type = 'ride',
      vehicle_type = 'standard',
      tolls = 0,
      display_currency = 'MXN'
    } = body

    // Validate required fields
    if (!pickup_lat || !pickup_lng || !distance_km || !duration_min) {
      return new Response(
        JSON.stringify({ success: false, error: 'pickup_lat, pickup_lng, distance_km, and duration_min are required' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    // Get pricing for location (from pricing_rules_mx via spatial lookup)
    const { data: pricingData, error: pricingError } = await supabaseClient
      .rpc('get_pricing_for_location', {
        p_lat: pickup_lat,
        p_lng: pickup_lng,
        p_service_type: service_type,
        p_vehicle_type: vehicle_type
      })

    // Fallback defaults (aligned with CDMX Uber rates Feb 2026)
    const defaults = {
      zone_id: 0,
      zone_name: 'Default',
      state_code: 'MX',
      base_fare: 8.00,
      per_km: 3.60,
      per_min: 1.80,
      min_fare: 35.00,
      booking_fee: 5,
      night_multiplier: 1.25,
      weekend_multiplier: 1.10,
      max_surge_multiplier: 3.00,
      platform_fee_percent: 20.00,
      currency: 'MXN'
    }

    let pricing = pricingData?.[0] || null

    // If spatial lookup failed, try pricing_config table by state/service
    if (!pricing) {
      try {
        const { data: configData } = await supabaseClient
          .from('pricing_config')
          .select('state_code, base_fare, per_mile_rate, per_minute_rate, minimum_fare, booking_fee, night_multiplier, weekend_multiplier, peak_multiplier, platform_percentage')
          .eq('country_code', 'MX')
          .eq('booking_type', service_type)
          .eq('is_active', true)
          .limit(1)
          .single()

        if (configData) {
          pricing = {
            zone_id: 0,
            zone_name: configData.state_code,
            state_code: configData.state_code,
            base_fare: configData.base_fare,
            per_km: configData.per_mile_rate,
            per_min: configData.per_minute_rate,
            min_fare: configData.minimum_fare,
            booking_fee: configData.booking_fee || 0,
            night_multiplier: configData.night_multiplier || 1.25,
            weekend_multiplier: configData.weekend_multiplier || 1.10,
            max_surge_multiplier: configData.peak_multiplier || 2.00,
            platform_fee_percent: configData.platform_percentage ?? 20.00,
            currency: 'MXN'
          }
        }
      } catch (_e) {
        // pricing_config lookup failed, will use defaults below
        console.error('pricing_config fallback query failed:', _e)
      }
    }

    // Final fallback to hardcoded defaults
    if (!pricing) {
      pricing = defaults
    }

    // Check if it's night time (22:00 - 06:00)
    const now = new Date()
    const hour = now.getHours()
    const isNight = hour >= 22 || hour < 6

    // Check if it's weekend
    const dayOfWeek = now.getDay()
    const isWeekend = dayOfWeek === 0 || dayOfWeek === 6

    // TODO: Get surge multiplier from demand calculation
    const surgeMultiplier = 1.0

    // Calculate base amounts
    const baseFare = pricing.base_fare
    const distanceAmount = Math.round(distance_km * pricing.per_km * 100) / 100
    const timeAmount = Math.round(duration_min * pricing.per_min * 100) / 100
    const bookingFee = pricing.booking_fee

    let subtotalPreMultipliers = baseFare + distanceAmount + timeAmount + bookingFee

    // Apply multipliers
    const nightMult = isNight ? pricing.night_multiplier : 1.0
    const weekendMult = isWeekend ? pricing.weekend_multiplier : 1.0
    const cappedSurge = Math.min(surgeMultiplier, pricing.max_surge_multiplier)

    let subtotal = subtotalPreMultipliers * nightMult * weekendMult * cappedSurge
    const surgeAmount = subtotal - (subtotalPreMultipliers * nightMult * weekendMult)

    // Add tolls
    subtotal = subtotal + tolls

    // Apply minimum fare
    let minFareApplied = false
    if (subtotal < pricing.min_fare) {
      subtotal = pricing.min_fare
      minFareApplied = true
    }

    // Round subtotal
    subtotal = Math.round(subtotal * 100) / 100

    // Calculate tax (IVA 16%)
    const taxRate = 0.16
    const taxAmount = Math.round(subtotal * taxRate * 100) / 100
    const total = Math.round((subtotal + taxAmount) * 100) / 100

    // Calculate split
    const platformFee = Math.round(subtotal * (pricing.platform_fee_percent / 100) * 100) / 100
    const driverEarnings = Math.round((subtotal - platformFee) * 100) / 100

    // Get FX rate if displaying in different currency
    let fxRate: number | undefined
    let totalDisplay: number | undefined

    if (display_currency && display_currency !== 'MXN') {
      const { data: fxData } = await supabaseClient
        .from('fx_rates')
        .select('rate')
        .eq('base_currency', 'MXN')
        .eq('quote_currency', display_currency)
        .order('fetched_at', { ascending: false })
        .limit(1)
        .single()

      if (fxData) {
        fxRate = fxData.rate
        totalDisplay = Math.round(total * fxRate * 100) / 100
      }
    }

    const response: PricingQuoteResponse = {
      success: true,
      data: {
        zone_id: pricing.zone_id,
        zone_name: pricing.zone_name,
        currency: 'MXN',

        base_fare: baseFare,
        distance_km,
        distance_amount: distanceAmount,
        duration_min,
        time_amount: timeAmount,
        booking_fee: bookingFee,

        is_night: isNight,
        night_multiplier: nightMult,
        is_weekend: isWeekend,
        weekend_multiplier: weekendMult,
        surge_multiplier: cappedSurge,
        surge_amount: surgeAmount,

        tolls,

        subtotal,
        tax_rate: taxRate,
        tax_amount: taxAmount,
        total,

        platform_fee: platformFee,
        driver_earnings: driverEarnings,

        fx_rate: fxRate,
        total_display: totalDisplay,
        display_currency: display_currency !== 'MXN' ? display_currency : undefined,

        min_fare_applied: minFareApplied
      }
    }

    return new Response(
      JSON.stringify(response),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error:', error)
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
    )
  }
})
