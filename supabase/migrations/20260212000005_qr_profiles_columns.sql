-- ============================================================================
-- QR SYSTEM: Ensure profiles has required columns for QR allocation & referral
-- ============================================================================

-- qr_rider_share: Rider's persistent share preference (0-10)
-- Used by qr_points_service.dart to read/write rider's allocation choice
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS qr_rider_share INT DEFAULT 5
  CHECK (qr_rider_share >= 0 AND qr_rider_share <= 10);

-- referred_by: UUID of the user who referred this rider
-- Set by deep_link_service / referral_service when rider scans a driver QR
-- Used by on_ride_completed_award_qr trigger to award driver QR points
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS referred_by UUID REFERENCES auth.users(id);

-- referred_by_driver: UUID of driver who referred this rider (may differ from referred_by)
-- Used by driver_referral_service.dart
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS referred_by_driver UUID;

-- referral_code: The rider's own referral code for sharing
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS referral_code TEXT;

-- state_code and country_code on profiles (used by QR donation RPC)
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS state_code TEXT;

ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS country_code TEXT DEFAULT 'US';

-- email column (used by admin leaderboard)
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS email TEXT;

-- ============================================================================
-- Ensure driver_qr_points table exists (for driver side QR system)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.driver_qr_points (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID NOT NULL REFERENCES auth.users(id),
  week_start DATE NOT NULL,
  qrs_accepted INT NOT NULL DEFAULT 0,
  current_level INT NOT NULL DEFAULT 0,
  bonus_percent NUMERIC(5,2) NOT NULL DEFAULT 0,
  total_bonus_earned NUMERIC(10,2) NOT NULL DEFAULT 0,
  country_code TEXT NOT NULL DEFAULT 'US',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(driver_id, week_start)
);

ALTER TABLE public.driver_qr_points ENABLE ROW LEVEL SECURITY;

-- Drivers can see their own records
CREATE POLICY IF NOT EXISTS "Drivers can view own QR points"
  ON public.driver_qr_points FOR SELECT
  USING (auth.uid() = driver_id);

-- Drivers can insert their own records
CREATE POLICY IF NOT EXISTS "Drivers can insert own QR points"
  ON public.driver_qr_points FOR INSERT
  WITH CHECK (auth.uid() = driver_id);

-- Drivers can update their own records
CREATE POLICY IF NOT EXISTS "Drivers can update own QR points"
  ON public.driver_qr_points FOR UPDATE
  USING (auth.uid() = driver_id);

-- Service role can manage all
CREATE POLICY IF NOT EXISTS "Service role can manage driver QR points"
  ON public.driver_qr_points FOR ALL
  USING (auth.jwt() ->> 'role' = 'service_role');

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_driver_qr_points_driver_week
  ON public.driver_qr_points(driver_id, week_start);

CREATE INDEX IF NOT EXISTS idx_driver_qr_points_country
  ON public.driver_qr_points(country_code, week_start);

-- ============================================================================
-- Ensure qr_points table exists (for rider side QR system)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.qr_points (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rider_id UUID NOT NULL REFERENCES auth.users(id),
  week_start DATE NOT NULL,
  qrs_accepted INT NOT NULL DEFAULT 0,
  current_level INT NOT NULL DEFAULT 0,
  discount_percent DOUBLE PRECISION NOT NULL DEFAULT 0,
  rider_share_percent DOUBLE PRECISION DEFAULT 5.0,
  driver_share_percent DOUBLE PRECISION DEFAULT 5.0,
  country_code TEXT NOT NULL DEFAULT 'US',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(rider_id, week_start)
);

ALTER TABLE public.qr_points ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_qr_points_rider_week
  ON public.qr_points(rider_id, week_start);

CREATE INDEX IF NOT EXISTS idx_qr_points_country
  ON public.qr_points(country_code, week_start);

-- ============================================================================
-- Ensure qr_tip_history table exists (for driver tips tab)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.qr_tip_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rider_id UUID NOT NULL REFERENCES auth.users(id),
  driver_id UUID NOT NULL,
  ride_id UUID,
  points_spent INT NOT NULL DEFAULT 0,
  tip_amount NUMERIC(10,2) NOT NULL DEFAULT 0,
  original_price NUMERIC(10,2) NOT NULL DEFAULT 0,
  final_price NUMERIC(10,2) NOT NULL DEFAULT 0,
  week_start DATE NOT NULL,
  country_code TEXT NOT NULL DEFAULT 'US',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.qr_tip_history ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_qr_tip_history_driver
  ON public.qr_tip_history(driver_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_qr_tip_history_rider
  ON public.qr_tip_history(rider_id, created_at DESC);

-- ============================================================================
-- VERIFICATION
-- ============================================================================
-- Check profiles has required columns:
-- SELECT column_name FROM information_schema.columns
-- WHERE table_name = 'profiles' AND column_name IN ('qr_rider_share', 'referred_by', 'state_code', 'country_code');
--
-- Check driver_qr_points table:
-- SELECT * FROM driver_qr_points LIMIT 1;
