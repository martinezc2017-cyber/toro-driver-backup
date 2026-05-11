// Edge Function: setup-ride-notification-trigger
// Installs a pg_net-based trigger that fires `notify-drivers-of-ride` whenever
// a new pending delivery (ride) is inserted with no driver_id assigned.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const dbUrl = Deno.env.get('SUPABASE_DB_URL')!
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    const { Client } = await import("https://deno.land/x/postgres@v0.17.0/mod.ts")
    const client = new Client(dbUrl)
    await client.connect()
    const log: string[] = []

    // 1) Ensure pg_net extension
    try {
      await client.queryArray(`CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions`)
      log.push('OK: pg_net extension')
    } catch (e) {
      log.push(`pg_net: ${(e as Error).message}`)
    }

    // 2) Trigger function — fires after INSERT of a pending unassigned ride
    try {
      await client.queryArray(`
        CREATE OR REPLACE FUNCTION notify_drivers_on_new_ride()
        RETURNS TRIGGER AS $$
        DECLARE
          v_url TEXT := '${supabaseUrl}/functions/v1/notify-drivers-of-ride';
          v_anon TEXT := '${anonKey}';
          v_payload jsonb;
        BEGIN
          IF NEW.status <> 'pending' OR NEW.driver_id IS NOT NULL THEN
            RETURN NEW;
          END IF;

          v_payload := jsonb_build_object(
            'ride_id', NEW.id,
            'pickup_lat', NEW.pickup_lat,
            'pickup_lng', NEW.pickup_lng,
            'pickup_address', COALESCE(NEW.pickup_address, 'Pickup'),
            'estimated_price', COALESCE(NEW.estimated_price, 0),
            'service_type', COALESCE(NEW.service_type, 'ride'),
            'country_code', NEW.country_code,
            'state_code', NEW.state_code
          );

          PERFORM extensions.http_post(
            url := v_url,
            body := v_payload::text,
            headers := jsonb_build_object(
              'Content-Type', 'application/json',
              'apikey', v_anon,
              'Authorization', 'Bearer ' || v_anon
            )::jsonb
          );

          RETURN NEW;
        EXCEPTION WHEN OTHERS THEN
          RAISE NOTICE 'notify_drivers_on_new_ride failed: %', SQLERRM;
          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql SECURITY DEFINER
      `)
      log.push('OK: notify_drivers_on_new_ride function')
    } catch (e) {
      log.push(`fn create: ${(e as Error).message}`)
    }

    // 3) Trigger
    try {
      await client.queryArray(`DROP TRIGGER IF EXISTS on_new_ride_notify_drivers ON deliveries`)
      await client.queryArray(`
        CREATE TRIGGER on_new_ride_notify_drivers
          AFTER INSERT ON deliveries
          FOR EACH ROW
          EXECUTE FUNCTION notify_drivers_on_new_ride()
      `)
      log.push('OK: on_new_ride_notify_drivers trigger')
    } catch (e) {
      log.push(`trigger: ${(e as Error).message}`)
    }

    // 4) Verify
    const { rows: triggers } = await client.queryObject<{trigger_name: string}>(`
      SELECT trigger_name FROM information_schema.triggers
      WHERE event_object_table = 'deliveries' AND trigger_name LIKE 'on_new_ride%'
    `)
    log.push(`Trigger installed: ${triggers.length > 0 ? triggers[0].trigger_name : 'NONE'}`)

    await client.end()

    return new Response(
      JSON.stringify({ success: true, log }, null, 2),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ success: false, error: String(error) }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
    )
  }
})
