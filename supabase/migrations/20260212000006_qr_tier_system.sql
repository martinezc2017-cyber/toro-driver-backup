-- ============================================================================
-- QR TIER SYSTEM - Configurable per state via pricing_config
-- ============================================================================
-- Adds QR tier columns to pricing_config so admin can control per state:
--   - qr_use_tiers: true = tier system (MX), false = linear (US)
--   - qr_max_level: max QR scans per week (30 for MX, 15 for US)
--   - qr_tier_X_max / qr_tier_X_bonus: tier breakpoints and bonus %
--
-- Linear mode (US default): bonus = qrLevel * qr_point_value
-- Tier mode (MX):  bonus = tier_bonus * qr_point_value
-- ============================================================================

-- QR tier mode toggle
ALTER TABLE public.pricing_config
ADD COLUMN IF NOT EXISTS qr_use_tiers BOOLEAN DEFAULT false;

-- Max QR scans per week
ALTER TABLE public.pricing_config
ADD COLUMN IF NOT EXISTS qr_max_level INTEGER DEFAULT 15;

-- Tier 1 breakpoint and bonus
ALTER TABLE public.pricing_config
ADD COLUMN IF NOT EXISTS qr_tier_1_max INTEGER DEFAULT 6;
ALTER TABLE public.pricing_config
ADD COLUMN IF NOT EXISTS qr_tier_1_bonus NUMERIC(5,2) DEFAULT 2.0;

-- Tier 2
ALTER TABLE public.pricing_config
ADD COLUMN IF NOT EXISTS qr_tier_2_max INTEGER DEFAULT 12;
ALTER TABLE public.pricing_config
ADD COLUMN IF NOT EXISTS qr_tier_2_bonus NUMERIC(5,2) DEFAULT 4.0;

-- Tier 3
ALTER TABLE public.pricing_config
ADD COLUMN IF NOT EXISTS qr_tier_3_max INTEGER DEFAULT 18;
ALTER TABLE public.pricing_config
ADD COLUMN IF NOT EXISTS qr_tier_3_bonus NUMERIC(5,2) DEFAULT 6.0;

-- Tier 4
ALTER TABLE public.pricing_config
ADD COLUMN IF NOT EXISTS qr_tier_4_max INTEGER DEFAULT 24;
ALTER TABLE public.pricing_config
ADD COLUMN IF NOT EXISTS qr_tier_4_bonus NUMERIC(5,2) DEFAULT 8.0;

-- Tier 5 (no max — everything above tier 4 max)
ALTER TABLE public.pricing_config
ADD COLUMN IF NOT EXISTS qr_tier_5_bonus NUMERIC(5,2) DEFAULT 10.0;

-- ============================================================================
-- MEXICO: Enable tier system for all MX states
-- ============================================================================
UPDATE public.pricing_config
SET
  qr_use_tiers = true,
  qr_max_level = 30,
  qr_tier_1_max = 6,
  qr_tier_1_bonus = 2.0,
  qr_tier_2_max = 12,
  qr_tier_2_bonus = 4.0,
  qr_tier_3_max = 18,
  qr_tier_3_bonus = 6.0,
  qr_tier_4_max = 24,
  qr_tier_4_bonus = 8.0,
  qr_tier_5_bonus = 10.0
WHERE country_code = 'MX';

-- ============================================================================
-- USA: Keep linear system (default values already correct)
-- Just ensure qr_use_tiers = false and qr_max_level = 15
-- ============================================================================
UPDATE public.pricing_config
SET
  qr_use_tiers = false,
  qr_max_level = 15
WHERE country_code = 'US' OR country_code IS NULL;

-- ============================================================================
-- QR SCAN TRACKING - Every QR scan event
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.qr_scans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID NOT NULL REFERENCES auth.users(id),
  scanned_by_rider_id UUID REFERENCES auth.users(id),
  ride_id UUID,
  state_code TEXT NOT NULL,
  city TEXT,
  country_code TEXT NOT NULL DEFAULT 'US',
  scanned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  week_start DATE NOT NULL DEFAULT date_trunc('week', now())::date,
  is_active BOOLEAN NOT NULL DEFAULT true,
  deactivated_at TIMESTAMPTZ,
  deactivation_reason TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index for fast weekly lookups per driver
CREATE INDEX IF NOT EXISTS idx_qr_scans_driver_week
  ON public.qr_scans(driver_id, week_start)
  WHERE is_active = true;

-- Index for state leaderboard
CREATE INDEX IF NOT EXISTS idx_qr_scans_state_week
  ON public.qr_scans(state_code, country_code, week_start)
  WHERE is_active = true;

-- Index for city leaderboard
CREATE INDEX IF NOT EXISTS idx_qr_scans_city_week
  ON public.qr_scans(city, state_code, country_code, week_start)
  WHERE is_active = true;

-- RLS
ALTER TABLE public.qr_scans ENABLE ROW LEVEL SECURITY;

-- Drivers can see their own scans
CREATE POLICY "Drivers can view own QR scans"
  ON public.qr_scans FOR SELECT
  USING (auth.uid() = driver_id);

-- Service role can insert (edge functions handle scan logic)
CREATE POLICY "Service role can manage QR scans"
  ON public.qr_scans FOR ALL
  USING (auth.jwt() ->> 'role' = 'service_role');

-- ============================================================================
-- QR DRIVER WEEKLY SUMMARY VIEW
-- Admin can see: driver X has Y active QRs this week = Tier Z
-- ============================================================================
CREATE OR REPLACE VIEW public.driver_qr_weekly_summary AS
SELECT
  qs.driver_id,
  qs.state_code,
  qs.city,
  qs.country_code,
  qs.week_start,
  COUNT(*) FILTER (WHERE qs.is_active) AS active_qr_count,
  COUNT(*) AS total_qr_count,
  -- Determine tier based on active count and pricing_config
  CASE
    WHEN pc.qr_use_tiers = true THEN
      CASE
        WHEN COUNT(*) FILTER (WHERE qs.is_active) <= COALESCE(pc.qr_tier_1_max, 6) THEN 1
        WHEN COUNT(*) FILTER (WHERE qs.is_active) <= COALESCE(pc.qr_tier_2_max, 12) THEN 2
        WHEN COUNT(*) FILTER (WHERE qs.is_active) <= COALESCE(pc.qr_tier_3_max, 18) THEN 3
        WHEN COUNT(*) FILTER (WHERE qs.is_active) <= COALESCE(pc.qr_tier_4_max, 24) THEN 4
        ELSE 5
      END
    ELSE 0 -- Linear mode, no tier
  END AS current_tier,
  -- Bonus percentage
  CASE
    WHEN pc.qr_use_tiers = true THEN
      CASE
        WHEN COUNT(*) FILTER (WHERE qs.is_active) <= COALESCE(pc.qr_tier_1_max, 6) THEN COALESCE(pc.qr_tier_1_bonus, 2.0)
        WHEN COUNT(*) FILTER (WHERE qs.is_active) <= COALESCE(pc.qr_tier_2_max, 12) THEN COALESCE(pc.qr_tier_2_bonus, 4.0)
        WHEN COUNT(*) FILTER (WHERE qs.is_active) <= COALESCE(pc.qr_tier_3_max, 18) THEN COALESCE(pc.qr_tier_3_bonus, 6.0)
        WHEN COUNT(*) FILTER (WHERE qs.is_active) <= COALESCE(pc.qr_tier_4_max, 24) THEN COALESCE(pc.qr_tier_4_bonus, 8.0)
        ELSE COALESCE(pc.qr_tier_5_bonus, 10.0)
      END
    ELSE COUNT(*) FILTER (WHERE qs.is_active) * COALESCE(pc.qr_point_value, 1.0)
  END AS bonus_percent,
  MIN(qs.scanned_at) AS first_scan,
  MAX(qs.scanned_at) AS last_scan
FROM public.qr_scans qs
LEFT JOIN public.pricing_config pc
  ON pc.state_code = qs.state_code
  AND pc.country_code = qs.country_code
  AND pc.booking_type = 'ride'
GROUP BY qs.driver_id, qs.state_code, qs.city, qs.country_code, qs.week_start,
         pc.qr_use_tiers, pc.qr_tier_1_max, pc.qr_tier_2_max, pc.qr_tier_3_max,
         pc.qr_tier_4_max, pc.qr_tier_1_bonus, pc.qr_tier_2_bonus, pc.qr_tier_3_bonus,
         pc.qr_tier_4_bonus, pc.qr_tier_5_bonus, pc.qr_point_value;

-- ============================================================================
-- QR TIER CHANGE LOG - Track when drivers move between tiers
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.qr_tier_changes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID NOT NULL REFERENCES auth.users(id),
  state_code TEXT NOT NULL,
  country_code TEXT NOT NULL DEFAULT 'US',
  week_start DATE NOT NULL,
  previous_tier INTEGER NOT NULL DEFAULT 0,
  new_tier INTEGER NOT NULL,
  previous_qr_count INTEGER NOT NULL DEFAULT 0,
  new_qr_count INTEGER NOT NULL,
  bonus_percent NUMERIC(5,2) NOT NULL,
  notification_sent BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_qr_tier_changes_driver
  ON public.qr_tier_changes(driver_id, created_at DESC);

ALTER TABLE public.qr_tier_changes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Drivers can view own tier changes"
  ON public.qr_tier_changes FOR SELECT
  USING (auth.uid() = driver_id);

CREATE POLICY "Service role can manage tier changes"
  ON public.qr_tier_changes FOR ALL
  USING (auth.jwt() ->> 'role' = 'service_role');

-- ============================================================================
-- VERIFICATION
-- ============================================================================
-- Check MX states have tiers enabled:
-- SELECT state_code, qr_use_tiers, qr_max_level, qr_tier_1_max, qr_tier_1_bonus,
--        qr_tier_5_bonus FROM pricing_config WHERE country_code = 'MX' LIMIT 5;
--
-- Check US states have linear mode:
-- SELECT state_code, qr_use_tiers, qr_max_level, qr_point_value
--        FROM pricing_config WHERE country_code = 'US' LIMIT 5;
