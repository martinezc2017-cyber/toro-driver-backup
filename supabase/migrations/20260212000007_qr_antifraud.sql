-- ============================================================================
-- QR POINTS ANTI-FRAUD SYSTEM
-- Server-side validation to prevent client manipulation
-- ============================================================================

-- ============================================================================
-- 1. RLS: Riders can only READ their own qr_points, NOT directly update
-- ============================================================================

-- Drop existing permissive policies if any
DROP POLICY IF EXISTS "Riders can view own QR points" ON public.qr_points;
DROP POLICY IF EXISTS "Riders can update own QR points" ON public.qr_points;
DROP POLICY IF EXISTS "Riders can insert own QR points" ON public.qr_points;

-- Riders can READ their own records
CREATE POLICY "Riders can view own QR points"
  ON public.qr_points FOR SELECT
  USING (auth.uid() = rider_id);

-- Riders can INSERT their own initial record (for _createWeeklyRecord)
CREATE POLICY "Riders can insert own QR points"
  ON public.qr_points FOR INSERT
  WITH CHECK (auth.uid() = rider_id);

-- Riders can ONLY update share allocation (rider_share_percent, driver_share_percent)
-- NOT current_level, qrs_accepted, or discount_percent
CREATE POLICY "Riders can update own share allocation"
  ON public.qr_points FOR UPDATE
  USING (auth.uid() = rider_id)
  WITH CHECK (
    auth.uid() = rider_id
    -- Only allow updating share columns and updated_at
    -- The RPC handles level/qrs_accepted changes
  );

-- ============================================================================
-- 2. Server-side RPC: award_qr_point
-- Validates everything server-side, prevents client manipulation
-- ============================================================================
CREATE OR REPLACE FUNCTION public.award_qr_point(
  p_rider_id UUID,
  p_ride_id UUID,
  p_referrer_code TEXT DEFAULT NULL,
  p_max_level INT DEFAULT 10
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER -- Runs with elevated privileges
SET search_path = public
AS $$
DECLARE
  v_week_start DATE;
  v_current_level INT;
  v_current_qrs INT;
  v_new_level INT;
  v_ride_exists BOOLEAN;
  v_ride_paid BOOLEAN;
  v_ride_rider_id UUID;
  v_ride_driver_id UUID;
  v_daily_awards INT;
  v_referrer_id UUID;
BEGIN
  -- Calculate current week start (Monday)
  v_week_start := date_trunc('week', now())::date;

  -- ======== VALIDATION 1: Ride exists and is completed ========
  SELECT
    true,
    (status = 'completed' AND (payment_status = 'paid' OR payment_method = 'cash')),
    rider_id,
    driver_id
  INTO v_ride_exists, v_ride_paid, v_ride_rider_id, v_ride_driver_id
  FROM public.rides
  WHERE id = p_ride_id;

  IF NOT v_ride_exists THEN
    RETURN 'error:ride_not_found';
  END IF;

  IF NOT v_ride_paid THEN
    RETURN 'error:ride_not_paid';
  END IF;

  -- ======== VALIDATION 2: Rider matches the ride ========
  IF v_ride_rider_id != p_rider_id THEN
    RETURN 'error:rider_mismatch';
  END IF;

  -- ======== VALIDATION 3: Can't self-refer ========
  IF p_referrer_code IS NOT NULL THEN
    SELECT id INTO v_referrer_id
    FROM public.profiles
    WHERE referral_code = p_referrer_code
    LIMIT 1;

    IF v_referrer_id = p_rider_id THEN
      RETURN 'error:self_referral';
    END IF;
  END IF;

  -- ======== VALIDATION 4: Rate limit - max 5 QR awards per day ========
  SELECT COUNT(*)
  INTO v_daily_awards
  FROM public.qr_points_audit_log
  WHERE rider_id = p_rider_id
    AND awarded_at >= CURRENT_DATE
    AND awarded_at < CURRENT_DATE + INTERVAL '1 day';

  IF v_daily_awards >= 5 THEN
    RETURN 'error:daily_limit_reached';
  END IF;

  -- ======== VALIDATION 5: Ride not already used for a QR award ========
  IF EXISTS (
    SELECT 1 FROM public.qr_points_audit_log
    WHERE ride_id = p_ride_id AND rider_id = p_rider_id
  ) THEN
    RETURN 'error:ride_already_awarded';
  END IF;

  -- ======== VALIDATION 6: Check current level not at max ========
  SELECT current_level, qrs_accepted
  INTO v_current_level, v_current_qrs
  FROM public.qr_points
  WHERE rider_id = p_rider_id AND week_start = v_week_start;

  IF v_current_level IS NULL THEN
    -- No record for this week, create one
    INSERT INTO public.qr_points (rider_id, week_start, qrs_accepted, current_level, discount_percent)
    VALUES (p_rider_id, v_week_start, 0, 0, 0);
    v_current_level := 0;
    v_current_qrs := 0;
  END IF;

  IF v_current_level >= p_max_level THEN
    RETURN 'error:max_level_reached';
  END IF;

  -- ======== ALL VALIDATIONS PASSED - Award the point ========
  v_new_level := LEAST(v_current_qrs + 1, p_max_level);

  -- Set session flag so trigger allows this update
  PERFORM set_config('app.qr_rpc_active', 'true', true);

  UPDATE public.qr_points
  SET
    qrs_accepted = v_current_qrs + 1,
    current_level = v_new_level,
    discount_percent = v_new_level::DOUBLE PRECISION,
    updated_at = now()
  WHERE rider_id = p_rider_id AND week_start = v_week_start;

  -- Reset session flag
  PERFORM set_config('app.qr_rpc_active', 'false', true);

  -- ======== Log the award for audit ========
  INSERT INTO public.qr_points_audit_log (rider_id, ride_id, referrer_code, week_start, level_before, level_after)
  VALUES (p_rider_id, p_ride_id, p_referrer_code, v_week_start, v_current_level, v_new_level);

  RETURN 'ok';
END;
$$;

-- ============================================================================
-- 3. Audit log table for QR point awards
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.qr_points_audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rider_id UUID NOT NULL REFERENCES auth.users(id),
  ride_id UUID NOT NULL,
  referrer_code TEXT,
  week_start DATE NOT NULL,
  level_before INT NOT NULL,
  level_after INT NOT NULL,
  awarded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ip_address INET, -- Optional: for forensic analysis
  UNIQUE(rider_id, ride_id) -- One award per ride per rider
);

-- Index for rate limiting check
CREATE INDEX IF NOT EXISTS idx_qr_audit_rider_day
  ON public.qr_points_audit_log(rider_id, awarded_at);

-- RLS: Only service role can write, riders can read own
ALTER TABLE public.qr_points_audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Riders can view own audit log"
  ON public.qr_points_audit_log FOR SELECT
  USING (auth.uid() = rider_id);

-- No INSERT/UPDATE/DELETE for riders - only the RPC function (SECURITY DEFINER) can write

-- ============================================================================
-- 4. Prevent direct level manipulation via trigger
-- ============================================================================
CREATE OR REPLACE FUNCTION public.protect_qr_level_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Allow updates from server-side RPCs (flagged via session variable)
  IF current_setting('app.qr_rpc_active', true) = 'true' THEN
    RETURN NEW;
  END IF;

  -- If a rider is trying to update their own record directly (not via RPC)
  -- Only allow changes to share allocation columns
  IF auth.uid() = NEW.rider_id THEN
    -- Preserve server-controlled fields (prevent client manipulation)
    NEW.current_level := OLD.current_level;
    NEW.qrs_accepted := OLD.qrs_accepted;
    NEW.discount_percent := OLD.discount_percent;
    -- Allow changes to: rider_share_percent, driver_share_percent, updated_at
  END IF;

  RETURN NEW;
END;
$$;

-- Drop if exists, then create
DROP TRIGGER IF EXISTS protect_qr_level ON public.qr_points;
CREATE TRIGGER protect_qr_level
  BEFORE UPDATE ON public.qr_points
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_qr_level_update();

-- ============================================================================
-- VERIFICATION
-- ============================================================================
-- Test: Try to manually increment level (should be blocked by trigger)
-- UPDATE qr_points SET current_level = 999 WHERE rider_id = auth.uid();
-- Expected: current_level stays at OLD value
--
-- Test: Call RPC with fake ride ID (should fail)
-- SELECT award_qr_point('rider-uuid', 'fake-ride-uuid');
-- Expected: 'error:ride_not_found'
