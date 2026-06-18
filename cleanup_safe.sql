-- 🔒 SAFE CLEANUP: Solo viajes MUY antiguos (>24h sin actualizar)
-- Esto NO afectará viajes recientes

BEGIN;

-- 1️⃣ BEFORE: Contar viajes que se van a limpiar
WITH deliveries_to_clean AS (
  SELECT COUNT(*) as count
  FROM package_deliveries
  WHERE status IN ('accepted', 'in_progress')
  AND driver_id IS NOT NULL
  AND (NOW() - updated_at) > INTERVAL '24 hours'
  AND created_at < NOW() - INTERVAL '1 day'
),
carpools_to_clean AS (
  SELECT COUNT(*) as count
  FROM share_ride_bookings
  WHERE status IN ('accepted', 'in_progress', 'matched', 'driver_assigned')
  AND driver_id IS NOT NULL
  AND (NOW() - updated_at) > INTERVAL '24 hours'
  AND created_at < NOW() - INTERVAL '1 day'
)
SELECT
  'DELIVERIES TO CLEAN: ' || (SELECT count FROM deliveries_to_clean) as info
UNION ALL
SELECT
  'CARPOOLS TO CLEAN: ' || (SELECT count FROM carpools_to_clean) as info;

-- 2️⃣ CLEANUP: Liberar viajes fantasma de package_deliveries
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
  AND (NOW() - updated_at) > INTERVAL '24 hours'
  AND created_at < NOW() - INTERVAL '1 day';

-- 3️⃣ CLEANUP: Liberar viajes fantasma de share_ride_bookings
UPDATE share_ride_bookings
SET
  status = 'pending',
  driver_id = NULL,
  accepted_at = NULL,
  updated_at = NOW()
WHERE
  status IN ('accepted', 'in_progress', 'matched', 'driver_assigned')
  AND driver_id IS NOT NULL
  AND (NOW() - updated_at) > INTERVAL '24 hours'
  AND created_at < NOW() - INTERVAL '1 day';

-- 4️⃣ AFTER: Verificar limpieza
SELECT
  '✅ Cleanup complete!' as result
UNION ALL
SELECT
  'Check logs for updated rows count';

COMMIT;
