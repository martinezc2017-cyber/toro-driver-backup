-- ============================================================================
-- MIGRATION 010: Add country_code to all tables
-- Date: 2026-01-30
-- Purpose: Support multi-country operations (USA + Mexico)
-- ============================================================================

-- ============================================================================
-- ADD COUNTRY_CODE COLUMNS
-- ============================================================================

-- Rides
ALTER TABLE public.rides
ADD COLUMN IF NOT EXISTS country_code TEXT DEFAULT 'US';

COMMENT ON COLUMN public.rides.country_code IS 'Country code: US, MX, etc.';

-- Deliveries
ALTER TABLE public.deliveries
ADD COLUMN IF NOT EXISTS country_code TEXT DEFAULT 'US';

COMMENT ON COLUMN public.deliveries.country_code IS 'Country code: US, MX, etc.';

-- Drivers
ALTER TABLE public.drivers
ADD COLUMN IF NOT EXISTS country_code TEXT DEFAULT 'US';

COMMENT ON COLUMN public.drivers.country_code IS 'Country code: US, MX, etc.';

-- Profiles (riders)
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS country_code TEXT DEFAULT 'US';

COMMENT ON COLUMN public.profiles.country_code IS 'Country code: US, MX, etc.';

-- Support tickets
ALTER TABLE public.support_tickets
ADD COLUMN IF NOT EXISTS country_code TEXT DEFAULT 'US';

COMMENT ON COLUMN public.support_tickets.country_code IS 'Country code: US, MX, etc.';

-- Share ride bookings (carpools)
ALTER TABLE public.share_ride_bookings
ADD COLUMN IF NOT EXISTS country_code TEXT DEFAULT 'US';

COMMENT ON COLUMN public.share_ride_bookings.country_code IS 'Country code: US, MX, etc.';

-- Driver earnings
ALTER TABLE public.driver_earnings
ADD COLUMN IF NOT EXISTS country_code TEXT DEFAULT 'US';

COMMENT ON COLUMN public.driver_earnings.country_code IS 'Country code: US, MX, etc.';


-- ============================================================================
-- CREATE INDEXES FOR PERFORMANCE
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_rides_country
ON public.rides(country_code);

CREATE INDEX IF NOT EXISTS idx_rides_country_status
ON public.rides(country_code, status);

CREATE INDEX IF NOT EXISTS idx_deliveries_country
ON public.deliveries(country_code);

CREATE INDEX IF NOT EXISTS idx_drivers_country
ON public.drivers(country_code);

CREATE INDEX IF NOT EXISTS idx_drivers_country_status
ON public.drivers(country_code, status);

CREATE INDEX IF NOT EXISTS idx_profiles_country
ON public.profiles(country_code);

CREATE INDEX IF NOT EXISTS idx_support_tickets_country
ON public.support_tickets(country_code);

CREATE INDEX IF NOT EXISTS idx_share_ride_bookings_country
ON public.share_ride_bookings(country_code);

CREATE INDEX IF NOT EXISTS idx_driver_earnings_country
ON public.driver_earnings(country_code);


-- ============================================================================
-- UPDATE EXISTING DATA TO 'US'
-- ============================================================================

-- Set all existing records to US (they are all USA data)
UPDATE public.rides SET country_code = 'US' WHERE country_code IS NULL;
UPDATE public.deliveries SET country_code = 'US' WHERE country_code IS NULL;
UPDATE public.drivers SET country_code = 'US' WHERE country_code IS NULL;
UPDATE public.profiles SET country_code = 'US' WHERE country_code IS NULL;
UPDATE public.support_tickets SET country_code = 'US' WHERE country_code IS NULL;
UPDATE public.share_ride_bookings SET country_code = 'US' WHERE country_code IS NULL;
UPDATE public.driver_earnings SET country_code = 'US' WHERE country_code IS NULL;


-- ============================================================================
-- UPDATE RLS POLICIES (if needed)
-- ============================================================================

-- Note: RLS policies remain the same for now
-- They filter by user auth, not by country
-- Country filtering happens at application level


-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- Uncomment to verify after migration:
-- SELECT 'rides' as table_name, country_code, COUNT(*) FROM public.rides GROUP BY country_code;
-- SELECT 'deliveries' as table_name, country_code, COUNT(*) FROM public.deliveries GROUP BY country_code;
-- SELECT 'drivers' as table_name, country_code, COUNT(*) FROM public.drivers GROUP BY country_code;
-- SELECT 'profiles' as table_name, country_code, COUNT(*) FROM public.profiles GROUP BY country_code;
