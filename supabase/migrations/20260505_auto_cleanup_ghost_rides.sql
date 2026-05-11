-- Migration: Auto-cleanup ghost rides trigger
-- Automatically resets rides in accepted/in_progress state for >24 hours

-- 1️⃣ Create cleanup function for deliveries
CREATE OR REPLACE FUNCTION cleanup_ghost_deliveries()
RETURNS void AS $$
BEGIN
  UPDATE deliveries
  SET
    status = 'pending',
    driver_id = NULL,
    accepted_at = NULL,
    started_at = NULL,
    updated_at = NOW()
  WHERE
    status IN ('accepted', 'in_progress')
    AND driver_id IS NOT NULL
    AND (NOW() - updated_at) > INTERVAL '24 hours';

  RAISE NOTICE '[CLEANUP] Deliveries cleanup completed at %', NOW();
END;
$$ LANGUAGE plpgsql;

-- 2️⃣ Create cleanup function for carpools
CREATE OR REPLACE FUNCTION cleanup_ghost_carpools()
RETURNS void AS $$
BEGIN
  UPDATE share_ride_bookings
  SET
    status = 'pending',
    driver_id = NULL,
    accepted_at = NULL,
    updated_at = NOW()
  WHERE
    status IN ('accepted', 'in_progress', 'matched', 'driver_assigned')
    AND driver_id IS NOT NULL
    AND (NOW() - updated_at) > INTERVAL '24 hours';

  RAISE NOTICE '[CLEANUP] Carpools cleanup completed at %', NOW();
END;
$$ LANGUAGE plpgsql;

-- 3️⃣ Create master cleanup function
CREATE OR REPLACE FUNCTION auto_cleanup_ghost_rides()
RETURNS void AS $$
BEGIN
  PERFORM cleanup_ghost_deliveries();
  PERFORM cleanup_ghost_carpools();

  INSERT INTO audit_log (action, details, created_at)
  VALUES (
    'auto_cleanup_ghost_rides',
    jsonb_build_object(
      'timestamp', NOW(),
      'message', 'Auto-cleanup executed'
    ),
    NOW()
  );
END;
$$ LANGUAGE plpgsql;

-- 4️⃣ Create cron job (runs every 6 hours)
-- Note: Requires pg_cron extension
SELECT cron.schedule(
  'auto-cleanup-ghost-rides',
  '0 */6 * * *',  -- Every 6 hours
  'SELECT auto_cleanup_ghost_rides()'
);

-- 5️⃣ Log creation
INSERT INTO audit_log (action, details, created_at)
VALUES (
  'cron_job_created',
  jsonb_build_object(
    'job_name', 'auto-cleanup-ghost-rides',
    'schedule', '0 */6 * * * (every 6 hours)',
    'created_at', NOW()
  ),
  NOW()
) ON CONFLICT DO NOTHING;
