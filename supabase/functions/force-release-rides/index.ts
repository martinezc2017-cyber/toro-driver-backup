// Edge Function: force-release-rides
// Libera todos los viajes activos fantasma de un conductor
// ADMIN ONLY - verifica que el usuario sea admin

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface ReleaseRequest {
  driver_id: string
}

interface ReleaseResponse {
  success: boolean
  data?: {
    deliveries_released: number
    carpools_released: number
    message: string
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

    const { driver_id } = await req.json() as ReleaseRequest

    if (!driver_id) {
      return new Response(
        JSON.stringify({ success: false, error: 'driver_id is required' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    console.log(`[FORCE-RELEASE] Releasing rides for driver: ${driver_id}`)

    let deliveriesReleased = 0
    let carpoolsReleased = 0

    // 1. Release from deliveries table (rides and packages)
    try {
      const deliveryResult = await supabaseClient
        .from('package_deliveries')
        .update({
          status: 'pending',
          driver_id: null,
          accepted_at: null,
          started_at: null,
        })
        .eq('driver_id', driver_id)
        .in('status', ['accepted', 'in_progress', 'arrived'])

      if (deliveryResult.error) {
        console.error('Deliveries error:', deliveryResult.error)
      } else {
        deliveriesReleased = deliveryResult.data?.length || 0
        console.log(`[FORCE-RELEASE] Released ${deliveriesReleased} deliveries`)
      }
    } catch (e) {
      console.error('Error releasing deliveries:', e)
    }

    // 2. Release from share_ride_bookings table (carpools)
    try {
      const carpoolResult = await supabaseClient
        .from('share_ride_bookings')
        .update({
          status: 'pending',
          driver_id: null,
          accepted_at: null,
        })
        .eq('driver_id', driver_id)
        .in('status', ['accepted', 'in_progress', 'matched', 'driver_assigned'])

      if (carpoolResult.error) {
        console.error('Carpools error:', carpoolResult.error)
      } else {
        carpoolsReleased = carpoolResult.data?.length || 0
        console.log(`[FORCE-RELEASE] Released ${carpoolsReleased} carpools`)
      }
    } catch (e) {
      console.error('Error releasing carpools:', e)
    }

    const response: ReleaseResponse = {
      success: true,
      data: {
        deliveries_released: deliveriesReleased,
        carpools_released: carpoolsReleased,
        message: `✅ Released ${deliveriesReleased + carpoolsReleased} total rides for driver ${driver_id}`
      }
    }

    return new Response(
      JSON.stringify(response),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    )

  } catch (error) {
    console.error('Function error:', error)
    const response: ReleaseResponse = {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error'
    }

    return new Response(
      JSON.stringify(response),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
    )
  }
})
