// Edge Function: calculate-tax-retention
// Calculates ISR and IVA retention for Mexican drivers

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface TaxRetentionRequest {
  driver_id: string
  gross_amount: number
  ride_id?: string
  delivery_id?: string
  transaction_type?: string // 'ride' | 'delivery' | 'tip'
}

interface TaxRetentionResponse {
  success: boolean
  data?: {
    gross_amount: number
    has_rfc: boolean
    isr_rate: number
    isr_amount: number
    iva_rate: number
    iva_amount: number
    iva_driver_owes: number
    net_amount: number
    currency: string
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

    const body: TaxRetentionRequest = await req.json()
    const { driver_id, gross_amount, ride_id, delivery_id, transaction_type = 'ride' } = body

    // Validate required fields
    if (!driver_id || !gross_amount) {
      return new Response(
        JSON.stringify({ success: false, error: 'driver_id and gross_amount are required' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    // Get driver info
    const { data: driver, error: driverError } = await supabaseClient
      .from('drivers')
      .select('id, country_code, rfc, rfc_validated')
      .eq('id', driver_id)
      .single()

    if (driverError || !driver) {
      return new Response(
        JSON.stringify({ success: false, error: 'Driver not found' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 404 }
      )
    }

    // Determine currency from country_code
    const currencyByCountry: Record<string, string> = {
      'MX': 'MXN',
      'US': 'USD',
    }
    const driverCurrency = currencyByCountry[driver.country_code] || 'USD'

    // Only calculate tax retention for Mexico
    if (driver.country_code !== 'MX') {
      return new Response(
        JSON.stringify({
          success: true,
          data: {
            gross_amount,
            has_rfc: false,
            isr_rate: 0,
            isr_amount: 0,
            iva_rate: 0,
            iva_amount: 0,
            iva_driver_owes: 0,
            net_amount: gross_amount,
            currency: driverCurrency
          }
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get country config
    const { data: countryConfig } = await supabaseClient
      .from('countries')
      .select('*')
      .eq('code', 'MX')
      .single()

    // Check if driver has validated RFC
    const hasRfc = driver.rfc && driver.rfc_validated === true

    // Determine rates
    const isrRate = hasRfc
      ? (countryConfig?.isr_rate_with_rfc || 0.025)
      : (countryConfig?.isr_rate_without_rfc || 0.20)
    const ivaRate = countryConfig?.iva_retention_rate || 0.08

    // Calculate amounts
    const isrAmount = Math.round(gross_amount * isrRate * 100) / 100
    const ivaAmount = Math.round(gross_amount * ivaRate * 100) / 100
    const ivaDriverOwes = ivaAmount // The other 8% driver must pay to SAT
    const netAmount = Math.round((gross_amount - isrAmount - ivaAmount) * 100) / 100

    // Insert retention record
    const { error: insertError } = await supabaseClient
      .from('tax_retentions')
      .insert({
        driver_id,
        ride_id: ride_id || null,
        delivery_id: delivery_id || null,
        transaction_type,
        gross_amount,
        has_rfc: hasRfc,
        isr_rate: isrRate,
        isr_amount: isrAmount,
        iva_rate: ivaRate,
        iva_amount: ivaAmount,
        iva_driver_owes: ivaDriverOwes,
        net_amount: netAmount,
        period_year: new Date().getFullYear(),
        period_month: new Date().getMonth() + 1,
        currency: 'MXN'
      })

    if (insertError) {
      console.error('Error inserting retention:', insertError)
    }

    // Update monthly summary
    const year = new Date().getFullYear()
    const month = new Date().getMonth() + 1

    const { data: existingSummary } = await supabaseClient
      .from('tax_monthly_summary')
      .select('*')
      .eq('driver_id', driver_id)
      .eq('period_year', year)
      .eq('period_month', month)
      .single()

    if (existingSummary) {
      await supabaseClient
        .from('tax_monthly_summary')
        .update({
          total_gross: existingSummary.total_gross + gross_amount,
          total_isr_retained: existingSummary.total_isr_retained + isrAmount,
          total_iva_retained: existingSummary.total_iva_retained + ivaAmount,
          total_iva_driver_owes: existingSummary.total_iva_driver_owes + ivaDriverOwes,
          total_net: existingSummary.total_net + netAmount,
          transaction_count: existingSummary.transaction_count + 1,
          had_rfc: hasRfc,
          updated_at: new Date().toISOString()
        })
        .eq('id', existingSummary.id)
    } else {
      await supabaseClient
        .from('tax_monthly_summary')
        .insert({
          driver_id,
          period_year: year,
          period_month: month,
          total_gross: gross_amount,
          total_isr_retained: isrAmount,
          total_iva_retained: ivaAmount,
          total_iva_driver_owes: ivaDriverOwes,
          total_net: netAmount,
          transaction_count: 1,
          had_rfc: hasRfc
        })
    }

    // Update ride or delivery with retention info
    if (ride_id) {
      await supabaseClient
        .from('rides')
        .update({
          isr_retained: isrAmount,
          iva_retained: ivaAmount
        })
        .eq('id', ride_id)
    }

    if (delivery_id) {
      await supabaseClient
        .from('package_deliveries')
        .update({
          isr_retained: isrAmount,
          iva_retained: ivaAmount
        })
        .eq('id', delivery_id)
    }

    const response: TaxRetentionResponse = {
      success: true,
      data: {
        gross_amount,
        has_rfc: hasRfc,
        isr_rate: isrRate,
        isr_amount: isrAmount,
        iva_rate: ivaRate,
        iva_amount: ivaAmount,
        iva_driver_owes: ivaDriverOwes,
        net_amount: netAmount,
        currency: 'MXN'
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
