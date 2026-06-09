// Edge Function: log-event
// Receives app log events from rider/driver Flutter apps and stores in app_logs table.
// Use for tracking bugs, errors, milestones, anything you want to debug later.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface LogEntry {
  level: 'debug' | 'info' | 'warn' | 'error' | 'critical'
  source: string                // 'rider:add_product', 'driver:home_screen', etc
  event: string                 // 'photo_upload_failed', 'fcm_token_refresh'
  message?: string
  user_id?: string
  device_info?: Record<string, any>
  context?: Record<string, any>
  stack_trace?: string
  app_version?: string
  app_role?: 'rider' | 'driver' | 'admin'
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const client = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } }
    )

    const body = await req.json()
    // Accept either single entry or array (batch from offline buffer)
    const entries: LogEntry[] = Array.isArray(body) ? body : [body]

    if (entries.length === 0) {
      return new Response(
        JSON.stringify({ success: false, error: 'empty payload' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }
    if (entries.length > 100) {
      return new Response(
        JSON.stringify({ success: false, error: 'max 100 entries per request' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    const validLevels = ['debug', 'info', 'warn', 'error', 'critical']
    const rows = entries
      .filter(e => e.level && e.source && e.event)
      .map(e => ({
        level: validLevels.includes(e.level) ? e.level : 'info',
        source: String(e.source).slice(0, 100),
        event: String(e.event).slice(0, 100),
        message: e.message ? String(e.message).slice(0, 2000) : null,
        user_id: e.user_id ?? null,
        device_info: e.device_info ?? null,
        context: e.context ?? null,
        stack_trace: e.stack_trace ? String(e.stack_trace).slice(0, 5000) : null,
        app_version: e.app_version ?? null,
        app_role: e.app_role ?? null,
      }))

    if (rows.length === 0) {
      return new Response(
        JSON.stringify({ success: false, error: 'no valid entries (need level, source, event)' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    const { error } = await client.from('app_logs').insert(rows)
    if (error) {
      return new Response(
        JSON.stringify({ success: false, error: error.message }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
      )
    }

    return new Response(
      JSON.stringify({ success: true, logged: rows.length }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ success: false, error: String(error) }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
    )
  }
})
