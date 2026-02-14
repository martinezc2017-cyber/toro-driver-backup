-- ============================================================================
-- MIGRATION: Add signup location tracking to profiles
-- Date: 2026-02-13
-- Purpose: Store GPS coordinates at registration so admin can verify
--          which country the account was created in, without guessing.
-- ============================================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS signup_lat DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS signup_lng DOUBLE PRECISION;

COMMENT ON COLUMN public.profiles.signup_lat IS 'GPS latitude at account creation';
COMMENT ON COLUMN public.profiles.signup_lng IS 'GPS longitude at account creation';
