-- 📋 VERIFY: Ver viajes fantasma ANTES de limpiar
-- Ejecutar en Supabase SQL Editor para VER qué se va a limpiar

-- 1️⃣ Viajes en estado activo (accepted/in_progress)
SELECT
  'package_deliveries' as table_name,
  id,
  driver_id,
  status,
  created_at,
  updated_at,
  EXTRACT(HOURS FROM (NOW() - updated_at)) as hours_since_update,
  passenger_name,
  pickup_location,
  dropoff_location
FROM package_deliveries
WHERE status IN ('accepted', 'in_progress')
AND driver_id IS NOT NULL
AND (NOW() - updated_at) > INTERVAL '2 hours'
ORDER BY updated_at ASC
LIMIT 20;

-- 2️⃣ Carpools en estado activo
SELECT
  'share_ride_bookings' as table_name,
  id,
  driver_id,
  status,
  created_at,
  updated_at,
  EXTRACT(HOURS FROM (NOW() - updated_at)) as hours_since_update
FROM share_ride_bookings
WHERE status IN ('accepted', 'in_progress', 'matched', 'driver_assigned')
AND driver_id IS NOT NULL
AND (NOW() - updated_at) > INTERVAL '2 hours'
ORDER BY updated_at ASC
LIMIT 20;
