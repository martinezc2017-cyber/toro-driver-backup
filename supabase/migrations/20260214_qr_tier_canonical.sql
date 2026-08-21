-- ============================================================================
-- QR TIER IN CANONICAL ARCHITECTURE
-- ============================================================================
-- Every ride stores the driver's QR tier at time of completion.
-- This data flows: deliveries → transactions → transactions_canonical
-- Admin can see QR tier per ride in the rides table.
-- ============================================================================

-- 1. Add qr_tier columns to transactions table (if not exist)
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS driver_qr_tier integer DEFAULT 0;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS qr_commission_reduction numeric(5,2) DEFAULT 0;

-- 2. Recreate transactions_canonical VIEW with QR tier columns
DROP VIEW IF EXISTS transactions_canonical CASCADE;

CREATE VIEW transactions_canonical
WITH (security_invoker = on) AS
SELECT
    id,
    created_at,
    user_id,
    driver_id,
    type,
    booking_type,
    status,
    country_code,
    state_code,
    -- Keep original amount column
    amount,
    -- Canonical columns
    COALESCE(NULLIF(gross_fare, 0), amount, 0) as gross_fare,
    COALESCE(NULLIF(platform_fee_amount, 0), platform_fee, 0) as platform_fee_amount,
    COALESCE(NULLIF(platform_fee_amount, 0), platform_fee, 0) as platform_fee,
    COALESCE(NULLIF(driver_amount, 0), driver_earnings, 0) as driver_amount,
    COALESCE(NULLIF(driver_amount, 0), driver_earnings, 0) as driver_earnings,
    COALESCE(insurance_fee_amount, 0) as insurance_fee_amount,
    COALESCE(tax_fee_amount, 0) as tax_fee_amount,
    COALESCE(tip, 0) as tip,
    payment_method,
    stripe_payment_intent_id,
    delivery_id,
    carpool_id,
    ride_id,
    pickup_address,
    dropoff_address,
    pickup_lat,
    pickup_lng,
    dropoff_lat,
    dropoff_lng,
    -- QR tier data (canonical)
    COALESCE(driver_qr_tier, 0) as driver_qr_tier,
    COALESCE(qr_commission_reduction, 0) as qr_commission_reduction
FROM transactions;

GRANT SELECT ON transactions_canonical TO authenticated;
GRANT SELECT ON transactions_canonical TO anon;

-- 3. Recreate transactions_revenue VIEW (filtered for revenue-valid)
DROP VIEW IF EXISTS transactions_revenue;

CREATE VIEW transactions_revenue
WITH (security_invoker = on) AS
SELECT * FROM transactions_canonical
WHERE status IN ('success', 'completed')
   OR (status = 'cancelled' AND COALESCE(NULLIF(gross_fare, 0), amount, 0) > 0);

GRANT SELECT ON transactions_revenue TO authenticated;
GRANT SELECT ON transactions_revenue TO anon;

-- 4. Index for QR tier queries
CREATE INDEX IF NOT EXISTS idx_transactions_qr_tier
ON transactions(driver_qr_tier) WHERE driver_qr_tier > 0;

CREATE INDEX IF NOT EXISTS idx_deliveries_qr_tier
ON deliveries(driver_qr_tier) WHERE driver_qr_tier > 0;
