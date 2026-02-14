-- ============================================================================
-- QR AUTO-AWARD SYSTEM
-- Automatically awards driver QR points when their referral completes a ride.
-- Also awards rider QR points via award_qr_point when ride completes.
-- ============================================================================

-- ============================================================================
-- 1. Trigger function: on ride completion, award driver QR point
-- Fires when rides.status changes to 'completed'
-- ============================================================================
CREATE OR REPLACE FUNCTION public.on_ride_completed_award_qr()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rider_id UUID;
  v_driver_id UUID;
  v_referred_by UUID;
  v_rider_first_ride BOOLEAN;
  v_week_start DATE;
  v_driver_state TEXT;
  v_driver_country TEXT;
  v_current_qrs INT;
  v_current_level INT;
  v_max_level INT;
  v_new_level INT;
BEGIN
  -- Only fire when status changes TO 'completed'
  IF NEW.status != 'completed' THEN
    RETURN NEW;
  END IF;
  IF OLD.status = 'completed' THEN
    RETURN NEW; -- Already completed, skip
  END IF;

  v_rider_id := NEW.rider_id;
  v_driver_id := NEW.driver_id;

  -- ======== DRIVER QR: Check if rider was referred by a driver ========
  SELECT referred_by INTO v_referred_by
  FROM public.profiles
  WHERE id = v_rider_id;

  IF v_referred_by IS NOT NULL THEN
    -- Check if this is the rider's first completed ride
    SELECT NOT EXISTS (
      SELECT 1 FROM public.rides
      WHERE rider_id = v_rider_id
        AND status = 'completed'
        AND id != NEW.id
      LIMIT 1
    ) INTO v_rider_first_ride;

    IF v_rider_first_ride THEN
      -- Get the referring driver's state/country for pricing config lookup
      SELECT state_code, COALESCE(country_code, 'US')
      INTO v_driver_state, v_driver_country
      FROM public.drivers
      WHERE id = v_referred_by;

      -- Get max level from pricing_config
      SELECT COALESCE(qr_max_level, 15)
      INTO v_max_level
      FROM public.pricing_config
      WHERE state_code = v_driver_state
        AND country_code = v_driver_country
        AND booking_type = 'ride'
      LIMIT 1;

      IF v_max_level IS NULL THEN
        v_max_level := 15;
      END IF;

      v_week_start := date_trunc('week', now())::date;

      -- Get or create driver's weekly QR record
      SELECT qrs_accepted, current_level
      INTO v_current_qrs, v_current_level
      FROM public.driver_qr_points
      WHERE driver_id = v_referred_by AND week_start = v_week_start;

      IF v_current_qrs IS NULL THEN
        -- Create new weekly record
        INSERT INTO public.driver_qr_points (driver_id, week_start, qrs_accepted, current_level, bonus_percent, total_bonus_earned)
        VALUES (v_referred_by, v_week_start, 0, 0, 0, 0)
        ON CONFLICT DO NOTHING;
        v_current_qrs := 0;
        v_current_level := 0;
      END IF;

      -- Increment if not at max
      IF v_current_level < v_max_level THEN
        v_new_level := LEAST(v_current_qrs + 1, v_max_level);

        UPDATE public.driver_qr_points
        SET
          qrs_accepted = v_current_qrs + 1,
          current_level = v_new_level,
          bonus_percent = v_new_level,
          updated_at = now()
        WHERE driver_id = v_referred_by AND week_start = v_week_start;

        -- Also record a QR scan entry for tracking
        INSERT INTO public.qr_scans (driver_id, scanned_by_rider_id, ride_id, state_code, country_code, week_start)
        VALUES (v_referred_by, v_rider_id, NEW.id, COALESCE(v_driver_state, ''), COALESCE(v_driver_country, 'US'), v_week_start)
        ON CONFLICT DO NOTHING;
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Create the trigger on rides table
DROP TRIGGER IF EXISTS trg_ride_completed_award_qr ON public.rides;
CREATE TRIGGER trg_ride_completed_award_qr
  AFTER UPDATE ON public.rides
  FOR EACH ROW
  WHEN (NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed')
  EXECUTE FUNCTION public.on_ride_completed_award_qr();

-- ============================================================================
-- VERIFICATION
-- ============================================================================
-- When a ride's status changes to 'completed':
--   1. If the rider has profiles.referred_by pointing to a driver
--   2. AND this is the rider's first completed ride
--   3. THEN the referring driver's driver_qr_points.current_level increments
--   4. AND a qr_scans entry is created for tracking
--
-- Test: Update a test ride to completed
-- UPDATE rides SET status = 'completed' WHERE id = 'test-ride-uuid';
-- Then check: SELECT * FROM driver_qr_points WHERE driver_id = 'referring-driver-uuid';
