// Edge Function: fix-driver-zones
// Bulk UPDATE drivers with zone fields based on current_lat/current_lng.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const dbUrl = Deno.env.get('SUPABASE_DB_URL')!
    const { Client } = await import("https://deno.land/x/postgres@v0.17.0/mod.ts")
    const client = new Client(dbUrl)
    await client.connect()
    const log: string[] = []

    // Widen any narrow state-related VARCHAR columns (handles CDMX, JAL longer codes)
    const widenTargets = [
      ['drivers', 'state_code'],
      ['drivers', 'operating_state'],
      ['drivers', 'state'],
      ['deliveries', 'state_code'],
      ['profiles', 'state_code'],
    ]
    for (const [t, c] of widenTargets) {
      try {
        await client.queryArray(`ALTER TABLE ${t} ALTER COLUMN ${c} TYPE VARCHAR(32)`)
        log.push(`${t}.${c} -> VARCHAR(32)`)
      } catch (e) {
        const msg = (e as Error).message
        if (!msg.includes('does not exist')) {
          log.push(`${t}.${c} alter: ${msg}`)
        }
      }
    }

    // Mexicali, BC, MX
    const r1 = await client.queryArray(`
      UPDATE drivers
      SET country_code='MX', state_code='BC', operating_city='Mexicali', operating_state='Baja California', updated_at=NOW()
      WHERE current_lat BETWEEN 32.40 AND 32.90
        AND current_lng BETWEEN -115.80 AND -115.20
    `)
    log.push(`Mexicali: ${r1.rowCount ?? 0} drivers updated`)

    // Tijuana, BC, MX
    const r2 = await client.queryArray(`
      UPDATE drivers
      SET country_code='MX', state_code='BC', operating_city='Tijuana', operating_state='Baja California', updated_at=NOW()
      WHERE current_lat BETWEEN 32.40 AND 32.65
        AND current_lng BETWEEN -117.20 AND -116.85
    `)
    log.push(`Tijuana: ${r2.rowCount ?? 0} drivers updated`)

    // Ensenada, BC, MX
    const r3 = await client.queryArray(`
      UPDATE drivers
      SET country_code='MX', state_code='BC', operating_city='Ensenada', operating_state='Baja California', updated_at=NOW()
      WHERE current_lat BETWEEN 31.70 AND 31.95
        AND current_lng BETWEEN -116.75 AND -116.45
    `)
    log.push(`Ensenada: ${r3.rowCount ?? 0} drivers updated`)

    // Guadalajara, JAL, MX
    const r4 = await client.queryArray(`
      UPDATE drivers
      SET country_code='MX', state_code='JAL', operating_city='Guadalajara', operating_state='Jalisco', updated_at=NOW()
      WHERE current_lat BETWEEN 20.50 AND 20.85
        AND current_lng BETWEEN -103.55 AND -103.20
    `)
    log.push(`Guadalajara: ${r4.rowCount ?? 0} drivers updated`)

    // CDMX
    const r5 = await client.queryArray(`
      UPDATE drivers
      SET country_code='MX', state_code='CDMX', operating_city='Ciudad de México', operating_state='CDMX', updated_at=NOW()
      WHERE current_lat BETWEEN 19.20 AND 19.60
        AND current_lng BETWEEN -99.40 AND -98.95
    `)
    log.push(`CDMX: ${r5.rowCount ?? 0} drivers updated`)

    // Phoenix, AZ, US
    const r6 = await client.queryArray(`
      UPDATE drivers
      SET country_code='US', state_code='AZ', operating_city='Phoenix', operating_state='Arizona', updated_at=NOW()
      WHERE current_lat BETWEEN 33.30 AND 33.85
        AND current_lng BETWEEN -112.40 AND -111.85
    `)
    log.push(`Phoenix: ${r6.rowCount ?? 0} drivers updated`)

    // Los Angeles, CA, US
    const r7 = await client.queryArray(`
      UPDATE drivers
      SET country_code='US', state_code='CA', operating_city='Los Angeles', operating_state='California', updated_at=NOW()
      WHERE current_lat BETWEEN 33.70 AND 34.30
        AND current_lng BETWEEN -118.70 AND -118.10
    `)
    log.push(`Los Angeles: ${r7.rowCount ?? 0} drivers updated`)

    // San Diego, CA, US
    const r8 = await client.queryArray(`
      UPDATE drivers
      SET country_code='US', state_code='CA', operating_city='San Diego', operating_state='California', updated_at=NOW()
      WHERE current_lat BETWEEN 32.55 AND 33.10
        AND current_lng BETWEEN -117.30 AND -116.90
    `)
    log.push(`San Diego: ${r8.rowCount ?? 0} drivers updated`)

    // Backfill deliveries with state_code='BC' if pickup is in Mexicali
    const rd = await client.queryArray(`
      UPDATE deliveries
      SET state_code='BC', country_code='MX'
      WHERE pickup_lat BETWEEN 32.40 AND 32.90
        AND pickup_lng BETWEEN -115.80 AND -115.20
        AND (state_code IS NULL OR state_code = '')
    `)
    log.push(`Mexicali deliveries backfilled: ${rd.rowCount ?? 0}`)

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
