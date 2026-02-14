-- ============================================================================
-- QR WEEKLY DONATION SYSTEM
-- Accumulates rider driverShare donations per ride, determines weekly #1 driver
-- per state, and provides RPCs for recording and querying.
-- ============================================================================

-- ============================================================================
-- 1. Table: qr_ride_donations
-- One row per completed ride where the rider had driverShare > 0
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.qr_ride_donations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id UUID NOT NULL,
  rider_id UUID NOT NULL REFERENCES auth.users(id),
  driver_id UUID NOT NULL REFERENCES auth.users(id),
  state_code TEXT NOT NULL,
  country_code TEXT NOT NULL DEFAULT 'US',
  week_start DATE NOT NULL DEFAULT date_trunc('week', now())::date,
  ride_price NUMERIC(10,2) NOT NULL,          -- Original ride price
  donation_percent NUMERIC(5,2) NOT NULL,     -- donationToTop1Percent applied
  donation_amount NUMERIC(10,2) NOT NULL,     -- Actual $ amount donated
  rider_qr_level INT NOT NULL DEFAULT 0,      -- Rider's QR level at time of ride
  rider_share INT NOT NULL DEFAULT 0,         -- Rider's allocation (0-10)
  driver_share INT NOT NULL DEFAULT 0,        -- Donation allocation (0-10)
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(ride_id, rider_id)                   -- One donation per ride per rider
);

-- Index for weekly aggregation by driver per state
CREATE INDEX IF NOT EXISTS idx_qr_donations_driver_week
  ON public.qr_ride_donations(driver_id, state_code, country_code, week_start);

-- Index for weekly aggregation by state (for leaderboard)
CREATE INDEX IF NOT EXISTS idx_qr_donations_state_week
  ON public.qr_ride_donations(state_code, country_code, week_start);

-- Index for rider lookups
CREATE INDEX IF NOT EXISTS idx_qr_donations_rider
  ON public.qr_ride_donations(rider_id, week_start);

-- RLS
ALTER TABLE public.qr_ride_donations ENABLE ROW LEVEL SECURITY;

-- Riders can see their own donations
CREATE POLICY "Riders can view own donations"
  ON public.qr_ride_donations FOR SELECT
  USING (auth.uid() = rider_id);

-- Drivers can see donations received
CREATE POLICY "Drivers can view received donations"
  ON public.qr_ride_donations FOR SELECT
  USING (auth.uid() = driver_id);

-- Only service role / RPCs can insert (SECURITY DEFINER RPCs bypass RLS)
-- No direct INSERT/UPDATE/DELETE for regular users

-- ============================================================================
-- 2. View: weekly_top_drivers_by_state
-- Shows accumulated donations per driver per state per week, ranked
-- ============================================================================
CREATE OR REPLACE VIEW public.weekly_top_drivers_by_state AS
SELECT
  d.driver_id,
  d.state_code,
  d.country_code,
  d.week_start,
  SUM(d.donation_amount) AS total_donations,
  COUNT(*) AS donation_count,
  p.full_name AS driver_name,
  p.avatar_url AS driver_avatar,
  RANK() OVER (
    PARTITION BY d.state_code, d.country_code, d.week_start
    ORDER BY SUM(d.donation_amount) DESC
  ) AS rank_position
FROM public.qr_ride_donations d
LEFT JOIN public.profiles p ON p.id = d.driver_id
GROUP BY d.driver_id, d.state_code, d.country_code, d.week_start,
         p.full_name, p.avatar_url;

-- ============================================================================
-- 3. RPC: record_qr_ride_donation
-- Called when a ride completes. Records the donation portion.
-- SECURITY DEFINER: runs with elevated privileges to bypass RLS.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.record_qr_ride_donation(
  p_ride_id UUID,
  p_rider_id UUID,
  p_ride_price NUMERIC,
  p_rider_qr_level INT,
  p_rider_share INT,       -- 0-10
  p_driver_share INT        -- 0-10
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_driver_id UUID;
  v_state_code TEXT;
  v_country_code TEXT;
  v_week_start DATE;
  v_donation_percent NUMERIC;
  v_donation_amount NUMERIC;
BEGIN
  -- No donation if driver_share is 0
  IF p_driver_share <= 0 OR p_rider_qr_level <= 0 THEN
    RETURN 'skip:no_donation';
  END IF;

  -- Get ride info
  SELECT driver_id INTO v_driver_id
  FROM public.rides
  WHERE id = p_ride_id AND rider_id = p_rider_id;

  IF v_driver_id IS NULL THEN
    RETURN 'error:ride_not_found';
  END IF;

  -- Get rider's state from profile
  SELECT state_code, COALESCE(country_code, 'US')
  INTO v_state_code, v_country_code
  FROM public.profiles
  WHERE id = p_rider_id;

  IF v_state_code IS NULL THEN
    RETURN 'error:no_state';
  END IF;

  -- Calculate donation
  v_week_start := date_trunc('week', now())::date;
  -- donation_percent = qr_level * (driver_share / 10)
  -- e.g., level 7 with driver_share 6 → 7 * 0.6 = 4.2%
  v_donation_percent := p_rider_qr_level * (p_driver_share::NUMERIC / 10.0);
  v_donation_amount := p_ride_price * (v_donation_percent / 100.0);

  -- Don't record micro-donations under $0.01
  IF v_donation_amount < 0.01 THEN
    RETURN 'skip:amount_too_small';
  END IF;

  -- Insert donation (upsert: if ride already donated, skip)
  INSERT INTO public.qr_ride_donations (
    ride_id, rider_id, driver_id, state_code, country_code,
    week_start, ride_price, donation_percent, donation_amount,
    rider_qr_level, rider_share, driver_share
  )
  VALUES (
    p_ride_id, p_rider_id, v_driver_id, v_state_code, v_country_code,
    v_week_start, p_ride_price, v_donation_percent, v_donation_amount,
    p_rider_qr_level, p_rider_share, p_driver_share
  )
  ON CONFLICT (ride_id, rider_id) DO NOTHING;

  RETURN 'ok';
END;
$$;

-- ============================================================================
-- 4. RPC: get_weekly_top_driver
-- Returns the current #1 driver for a given state this week.
-- Callable by any authenticated user (riders need this info).
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_weekly_top_driver(
  p_state_code TEXT,
  p_country_code TEXT DEFAULT 'US'
)
RETURNS TABLE (
  driver_id UUID,
  driver_name TEXT,
  driver_avatar TEXT,
  total_donations NUMERIC,
  donation_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_week_start DATE;
BEGIN
  v_week_start := date_trunc('week', now())::date;

  RETURN QUERY
  SELECT
    d.driver_id,
    COALESCE(p.full_name, 'Conductor') AS driver_name,
    p.avatar_url AS driver_avatar,
    SUM(d.donation_amount) AS total_donations,
    COUNT(*) AS donation_count
  FROM public.qr_ride_donations d
  LEFT JOIN public.profiles p ON p.id = d.driver_id
  WHERE d.state_code = p_state_code
    AND d.country_code = p_country_code
    AND d.week_start = v_week_start
  GROUP BY d.driver_id, p.full_name, p.avatar_url
  ORDER BY SUM(d.donation_amount) DESC
  LIMIT 1;
END;
$$;

-- ============================================================================
-- 5. RPC: get_weekly_top_drivers_leaderboard
-- Returns top 5 drivers for a given state this week (for admin/rider info).
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_weekly_top_drivers_leaderboard(
  p_state_code TEXT,
  p_country_code TEXT DEFAULT 'US',
  p_limit INT DEFAULT 5
)
RETURNS TABLE (
  rank_position BIGINT,
  driver_id UUID,
  driver_name TEXT,
  driver_avatar TEXT,
  total_donations NUMERIC,
  donation_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_week_start DATE;
BEGIN
  v_week_start := date_trunc('week', now())::date;

  RETURN QUERY
  SELECT
    ROW_NUMBER() OVER (ORDER BY SUM(d.donation_amount) DESC) AS rank_position,
    d.driver_id,
    COALESCE(p.full_name, 'Conductor') AS driver_name,
    p.avatar_url AS driver_avatar,
    SUM(d.donation_amount) AS total_donations,
    COUNT(*) AS donation_count
  FROM public.qr_ride_donations d
  LEFT JOIN public.profiles p ON p.id = d.driver_id
  WHERE d.state_code = p_state_code
    AND d.country_code = p_country_code
    AND d.week_start = v_week_start
  GROUP BY d.driver_id, p.full_name, p.avatar_url
  ORDER BY SUM(d.donation_amount) DESC
  LIMIT p_limit;
END;
$$;

-- ============================================================================
-- VERIFICATION
-- ============================================================================
-- Test: Record a donation
-- SELECT record_qr_ride_donation('ride-uuid', 'rider-uuid', 25.00, 7, 4, 6);
-- Expected: 'ok' (7 * 0.6 = 4.2% → $1.05 donated)
--
-- Test: Get weekly top driver
-- SELECT * FROM get_weekly_top_driver('CA', 'US');
-- Expected: driver with most accumulated donations this week
--
-- Test: No donation when driver_share = 0
-- SELECT record_qr_ride_donation('ride-uuid', 'rider-uuid', 25.00, 7, 10, 0);
-- Expected: 'skip:no_donation'
