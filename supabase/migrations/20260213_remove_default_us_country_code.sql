-- ============================================================================
-- MIGRATION 20260213: Remove DEFAULT 'US' from country_code columns
-- Date: 2026-02-13
-- Purpose: Prevent MX users from being silently tagged as 'US'
-- ============================================================================
--
-- CONTEXT:
-- Migration 010_add_country_code.sql added country_code TEXT DEFAULT 'US' to
-- 7 tables. That default was correct at the time because all existing data was
-- from the United States. Now that Toro operates in Mexico, the default is
-- dangerous: any INSERT that omits country_code will silently receive 'US',
-- which corrupts pricing, tax, and regulatory logic for Mexican users.
--
-- By dropping the default, country_code becomes NULL on new rows unless the
-- application explicitly provides a value. This forces every code path to set
-- the correct country_code ('US' or 'MX') at insert time.
--
-- IMPORTANT:
-- - This migration does NOT modify any existing rows.
-- - Existing rows already have their country_code set correctly.
-- - Only NEW inserts are affected.
-- ============================================================================

-- 1. rides
ALTER TABLE public.rides
  ALTER COLUMN country_code DROP DEFAULT;

-- 2. deliveries
ALTER TABLE public.deliveries
  ALTER COLUMN country_code DROP DEFAULT;

-- 3. drivers
ALTER TABLE public.drivers
  ALTER COLUMN country_code DROP DEFAULT;

-- 4. profiles
ALTER TABLE public.profiles
  ALTER COLUMN country_code DROP DEFAULT;

-- 5. support_tickets
ALTER TABLE public.support_tickets
  ALTER COLUMN country_code DROP DEFAULT;

-- 6. share_ride_bookings
ALTER TABLE public.share_ride_bookings
  ALTER COLUMN country_code DROP DEFAULT;

-- 7. driver_earnings
ALTER TABLE public.driver_earnings
  ALTER COLUMN country_code DROP DEFAULT;
