-- ============================================================================
-- MIGRATION: Fix hardcoded 20/80 delivery split trigger
-- Date: 2026-02-13
-- ============================================================================
-- The original trigger in 002_rider_integration.sql hardcoded:
--   platform_fee  = estimated_price * 0.20
--   driver_earnings = estimated_price * 0.80
--
-- This migration replaces it with a dynamic lookup from pricing_config,
-- using the delivery's country_code to find the correct driver_percentage.
--
-- Lookup priority:
--   1. pricing_config WHERE country_code = NEW.country_code (first active row)
--   2. Fallback: 80% driver / 20% platform (preserves original behavior)
-- ============================================================================

-- Step 1: Drop the old trigger
DROP TRIGGER IF EXISTS calculate_fees ON public.package_deliveries;

-- Step 2: Replace the trigger function with dynamic pricing lookup
CREATE OR REPLACE FUNCTION calculate_delivery_fees()
RETURNS TRIGGER AS $$
DECLARE
    v_driver_pct DECIMAL(5,2);
BEGIN
    -- Attempt to get driver_percentage from pricing_config for this country
    SELECT driver_percentage INTO v_driver_pct
    FROM public.pricing_config
    WHERE country_code = COALESCE(NEW.country_code, 'US')
      AND is_active = TRUE
    ORDER BY state_code ASC
    LIMIT 1;

    -- Fallback: if no pricing_config row found, default to 80% driver
    IF v_driver_pct IS NULL THEN
        v_driver_pct := 80.00;
    END IF;

    -- Calculate split
    NEW.driver_earnings := ROUND(NEW.estimated_price * (v_driver_pct / 100), 2);
    NEW.platform_fee    := ROUND(NEW.estimated_price - NEW.driver_earnings, 2);

    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Step 3: Re-create the trigger on package_deliveries
CREATE TRIGGER calculate_fees
    BEFORE INSERT OR UPDATE ON public.package_deliveries
    FOR EACH ROW
    EXECUTE FUNCTION calculate_delivery_fees();
