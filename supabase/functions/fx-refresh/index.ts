// Edge Function: fx-refresh
// Refreshes exchange rates from external API
// Should be called via cron every 1-3 hours

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface FxRefreshResponse {
  success: boolean
  data?: {
    rates_updated: number
    rates: Array<{
      base: string
      quote: string
      rate: number
    }>
    source: string
    timestamp: string
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

    // Get FX API key from environment
    const fxApiKey = Deno.env.get('FX_API_KEY')
    const fxApiUrl = Deno.env.get('FX_API_URL') || 'https://api.exchangerate-api.com/v4/latest'

    // Currencies we care about
    const baseCurrencies = ['MXN', 'USD']
    const quoteCurrencies = ['MXN', 'USD', 'EUR']

    const updatedRates: Array<{ base: string; quote: string; rate: number }> = []

    // Fetch rates for each base currency
    for (const base of baseCurrencies) {
      try {
        let url = `${fxApiUrl}/${base}`

        // If API requires key, add it
        if (fxApiKey) {
          url = `https://v6.exchangerate-api.com/v6/${fxApiKey}/latest/${base}`
        }

        const response = await fetch(url)

        if (!response.ok) {
          console.error(`Failed to fetch rates for ${base}: ${response.status}`)
          continue
        }

        const data = await response.json()
        const rates = data.rates || data.conversion_rates

        if (!rates) {
          console.error(`No rates in response for ${base}`)
          continue
        }

        // Insert rates for each quote currency
        for (const quote of quoteCurrencies) {
          if (quote === base) continue // Skip same currency

          const rate = rates[quote]
          if (!rate) continue

          // Insert into database
          const { error } = await supabaseClient
            .from('fx_rates')
            .insert({
              base_currency: base,
              quote_currency: quote,
              rate: rate,
              source: fxApiKey ? 'exchangerate-api-v6' : 'exchangerate-api-v4',
              fetched_at: new Date().toISOString()
            })

          if (!error) {
            updatedRates.push({ base, quote, rate })
          } else {
            console.error(`Error inserting rate ${base}/${quote}:`, error)
          }
        }

      } catch (fetchError) {
        console.error(`Error fetching rates for ${base}:`, fetchError)
      }
    }

    // Clean up old rates (keep last 100 per currency pair)
    for (const base of baseCurrencies) {
      for (const quote of quoteCurrencies) {
        if (quote === base) continue

        // Get count
        const { count } = await supabaseClient
          .from('fx_rates')
          .select('*', { count: 'exact', head: true })
          .eq('base_currency', base)
          .eq('quote_currency', quote)

        if (count && count > 100) {
          // Get the 100th newest record's timestamp
          const { data: oldestToKeep } = await supabaseClient
            .from('fx_rates')
            .select('fetched_at')
            .eq('base_currency', base)
            .eq('quote_currency', quote)
            .order('fetched_at', { ascending: false })
            .range(99, 99)
            .single()

          if (oldestToKeep) {
            // Delete older records
            await supabaseClient
              .from('fx_rates')
              .delete()
              .eq('base_currency', base)
              .eq('quote_currency', quote)
              .lt('fetched_at', oldestToKeep.fetched_at)
          }
        }
      }
    }

    const response: FxRefreshResponse = {
      success: true,
      data: {
        rates_updated: updatedRates.length,
        rates: updatedRates,
        source: fxApiKey ? 'exchangerate-api-v6' : 'exchangerate-api-v4',
        timestamp: new Date().toISOString()
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
