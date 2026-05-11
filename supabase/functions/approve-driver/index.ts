import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const url = Deno.env.get('SUPABASE_URL') ?? ''
    const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

    console.log('URL exists:', !!url)
    console.log('KEY exists:', !!key, 'length:', key.length)

    if (!url || !key) {
      return new Response(
        JSON.stringify({
          success: false,
          error: 'Missing env vars',
          hasUrl: !!url,
          hasKey: !!key
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
      )
    }

    const body = await req.json()
    console.log('Body received:', JSON.stringify(body))

    const driver_id = body.driver_id
    const grace_period_days = body.grace_period_days || 7
    const approved_by = body.approved_by || 'admin'
    const notes = body.notes || `${grace_period_days}-day grace period`

    if (!driver_id) {
      return new Response(
        JSON.stringify({ success: false, error: 'driver_id required' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    const client = createClient(url, key, {
      auth: { autoRefreshToken: false, persistSession: false }
    })

    const now = new Date()
    const gracePeriodEnds = new Date(now.getTime() + grace_period_days * 24 * 60 * 60 * 1000)

    const updateData: Record<string, any> = {
      admin_approved: true,
      admin_approved_at: now.toISOString(),
      status: 'active',
      can_receive_rides: true,
      onboarding_stage: 'approved',
      grace_period_ends: gracePeriodEnds.toISOString(),
      trial_mode_accepted: true,
      approval_notes: `${notes} (approved by: ${approved_by})`,
    }

    // Only set admin_approved_by if it's a valid UUID
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
    if (uuidRegex.test(approved_by)) {
      updateData.admin_approved_by = approved_by
    }

    const { data, error } = await client
      .from('drivers')
      .update(updateData)
      .eq('id', driver_id)
      .select()

    if (error) {
      console.error('DB Error:', JSON.stringify(error))
      return new Response(
        JSON.stringify({
          success: false,
          error: error.message,
          details: error.details,
          hint: error.hint,
          code: error.code,
          updateData
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
      )
    }

    return new Response(
      JSON.stringify({
        success: true,
        rowsUpdated: data?.length || 0,
        driver: data?.[0],
        grace_period_ends: gracePeriodEnds.toISOString(),
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    )

  } catch (error) {
    console.error('Function error:', error)
    return new Response(
      JSON.stringify({
        success: false,
        error: String(error),
        stack: error instanceof Error ? error.stack : undefined
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
    )
  }
})
