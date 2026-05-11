// Edge Function: auto-cleanup-rides
// Auto-cleanup ghost rides every 6 hours (scheduled via cron)
// Cleans rides that have been in accepted/in_progress state for >24 hours

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface CleanupResponse {
  success: boolean
  data?: {
    deliveries_cleaned: number
    carpools_cleaned: number
    total_cleaned: number
    message: string
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

    console.log('[AUTO-CLEANUP] Starting ghost ride cleanup...')
    const startTime = new Date()

    let deliveriesCleaned = 0
    let carpoolsCleaned = 0

    // 1️⃣ Clean deliveries (rides/packages older than 24 hours)
    try {
      console.log('[AUTO-CLEANUP] Cleaning deliveries...')
      const deliveryResult = await supabaseClient
        .from('deliveries')
        .update({
          status: 'pending',
          driver_id: null,
          accepted_at: null,
          started_at: null,
        })
        .in('status', ['accepted', 'in_progress'])
        .not('driver_id', 'is', null)
        .lte('updated_at', new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString())

      if (deliveryResult.error) {
        console.error('[AUTO-CLEANUP] Deliveries error:', deliveryResult.error)
      } else {
        deliveriesCleaned = deliveryResult.data?.length || 0
        console.log(`[AUTO-CLEANUP] Cleaned ${deliveriesCleaned} deliveries`)
      }
    } catch (e) {
      console.error('[AUTO-CLEANUP] Error cleaning deliveries:', e)
    }

    // 2️⃣ Clean carpools (share_ride_bookings older than 24 hours)
    try {
      console.log('[AUTO-CLEANUP] Cleaning carpools...')
      const carpoolResult = await supabaseClient
        .from('share_ride_bookings')
        .update({
          status: 'pending',
          driver_id: null,
          accepted_at: null,
        })
        .in('status', ['accepted', 'in_progress', 'matched', 'driver_assigned'])
        .not('driver_id', 'is', null)
        .lte('updated_at', new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString())

      if (carpoolResult.error) {
        console.error('[AUTO-CLEANUP] Carpools error:', carpoolResult.error)
      } else {
        carpoolsCleaned = carpoolResult.data?.length || 0
        console.log(`[AUTO-CLEANUP] Cleaned ${carpoolsCleaned} carpools`)
      }
    } catch (e) {
      console.error('[AUTO-CLEANUP] Error cleaning carpools:', e)
    }

    const endTime = new Date()
    const duration = (endTime.getTime() - startTime.getTime()) / 1000

    const response: CleanupResponse = {
      success: true,
      data: {
        deliveries_cleaned: deliveriesCleaned,
        carpools_cleaned: carpoolsCleaned,
        total_cleaned: deliveriesCleaned + carpoolsCleaned,
        message: `✅ Auto-cleanup complete: ${deliveriesCleaned + carpoolsCleaned} rides reset to pending (>24h old)`,
        timestamp: new Date().toISOString()
      }
    }

    console.log(`[AUTO-CLEANUP] Completed in ${duration}s: ${deliveriesCleaned + carpoolsCleaned} rides cleaned`)

    return new Response(
      JSON.stringify(response),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    )

  } catch (error) {
    console.error('[AUTO-CLEANUP] Function error:', error)
    const response: CleanupResponse = {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error'
    }

    return new Response(
      JSON.stringify(response),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
    )
  }
})
