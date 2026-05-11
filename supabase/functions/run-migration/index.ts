import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const dbUrl = Deno.env.get('SUPABASE_DB_URL')!
    const results: string[] = []

    const { Client } = await import("https://deno.land/x/postgres@v0.17.0/mod.ts")
    const client = new Client(dbUrl)
    await client.connect()

    // 1) Fix: remove broken default 'car' from vehicle_type (it violates its own constraint)
    //    New drivers register WITHOUT a vehicle — they add it during onboarding
    try {
      await client.queryArray(`ALTER TABLE public.drivers ALTER COLUMN vehicle_type DROP DEFAULT`)
      results.push("OK: Dropped broken 'car' default from vehicle_type")
    } catch (e) {
      results.push(`ERR dropping default: ${e.message}`)
    }

    // 2) Update trigger — NO vehicle_type, just user basics
    const triggerSql = `
CREATE OR REPLACE FUNCTION public.handle_new_driver()
RETURNS trigger AS $$
BEGIN
  IF COALESCE(NEW.raw_user_meta_data->>'role', '') = 'driver' THEN
    INSERT INTO public.drivers (
      id, user_id, email, name, first_name, last_name, phone,
      country_code, rating, total_rides, total_earnings,
      is_online, is_verified, is_active, status, role,
      created_at, updated_at
    ) VALUES (
      NEW.id,
      NEW.id,
      NEW.email,
      TRIM(COALESCE(NEW.raw_user_meta_data->>'first_name', '') || ' ' || COALESCE(NEW.raw_user_meta_data->>'last_name', '')),
      NEW.raw_user_meta_data->>'first_name',
      NEW.raw_user_meta_data->>'last_name',
      COALESCE(NEW.raw_user_meta_data->>'phone', ''),
      'MX',
      0.0, 0, 0.0,
      false, false, true, 'pending',
      COALESCE(NEW.raw_user_meta_data->>'role', 'driver'),
      NOW(), NOW()
    )
    ON CONFLICT (id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created_driver ON auth.users;
CREATE TRIGGER on_auth_user_created_driver
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_driver();
    `

    try {
      await client.queryArray(triggerSql)
      results.push("OK: Updated trigger (no vehicle_type)")
    } catch (e) {
      results.push(`ERR trigger: ${e.message}`)
    }

    // 3) Backfill orphans
    try {
      await client.queryArray(`
INSERT INTO public.drivers (id, user_id, email, name, first_name, last_name, phone, country_code, rating, total_rides, total_earnings, is_online, is_verified, is_active, status, role, created_at, updated_at)
SELECT au.id, au.id, au.email,
  TRIM(COALESCE(au.raw_user_meta_data->>'first_name', '') || ' ' || COALESCE(au.raw_user_meta_data->>'last_name', '')),
  au.raw_user_meta_data->>'first_name', au.raw_user_meta_data->>'last_name',
  COALESCE(au.raw_user_meta_data->>'phone', ''), 'MX', 0.0, 0, 0.0, false, false, true, 'pending',
  COALESCE(au.raw_user_meta_data->>'role', 'driver'), au.created_at, au.created_at
FROM auth.users au
WHERE au.raw_user_meta_data->>'role' = 'driver'
  AND NOT EXISTS (SELECT 1 FROM public.drivers d WHERE d.id = au.id)
ON CONFLICT (id) DO NOTHING;
      `)
      results.push("OK: Backfilled orphans")
    } catch (e) {
      results.push(`ERR orphans: ${e.message}`)
    }

    await client.end()

    return new Response(
      JSON.stringify({ success: true, results }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ success: false, error: String(error) }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
    )
  }
})
