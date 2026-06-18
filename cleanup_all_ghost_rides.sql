-- 🔧 SQL Script: Clean ALL ghost rides
-- Ejecutar en Supabase SQL Editor
-- Limpia viajes en estado 'accepted' o 'in_progress' sin actividad reciente

-- 1️⃣ Liberar viajes fantasma en package_deliveries (más de 6 horas sin actualizar)
UPDATE package_deliveries
SET
  status = 'pending',
  driver_id = NULL,
  accepted_at = NULL,
  started_at = NULL,
  updated_at = NOW()
WHERE
  status IN ('accepted', 'in_progress')
  AND driver_id IS NOT NULL
  AND (NOW() - updated_at) > INTERVAL '6 hours'
  AND created_at < NOW() - INTERVAL '1 day';

-- 2️⃣ Liberar viajes fantasma en share_ride_bookings (carpools)
UPDATE share_ride_bookings
SET
  status = 'pending',
  driver_id = NULL,
  accepted_at = NULL,
  updated_at = NOW()
WHERE
  status IN ('accepted', 'in_progress', 'matched', 'driver_assigned')
  AND driver_id IS NOT NULL
  AND (NOW() - updated_at) > INTERVAL '6 hours'
  AND created_at < NOW() - INTERVAL '1 day';

-- 3️⃣ Verificar viajes liberados
SELECT
  'Deliveries cleaned' as action,
  COUNT(*) as count
FROM package_deliveries
WHERE status = 'pending' AND driver_id IS NULL AND updated_at > NOW() - INTERVAL '1 minute'
UNION ALL
SELECT
  'Carpools cleaned' as action,
  COUNT(*) as count
FROM share_ride_bookings
WHERE status = 'pending' AND driver_id IS NULL AND updated_at > NOW() - INTERVAL '1 minute';
