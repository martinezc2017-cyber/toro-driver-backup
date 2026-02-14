-- ============================================================================
-- RIDE NEGOTIATION - Didi-style price negotiation for QR-tier drivers
-- ============================================================================
-- Drivers at QR Tier 1+ can propose a different (higher) price to the rider.
-- The rider can accept or reject the proposed price.
-- If rejected, the ride goes back to pending for other drivers.
--
-- Negotiation limits by QR tier:
--   Tier 0: Cannot negotiate (accept/reject only)
--   Tier 1: Up to +10%
--   Tier 2: Up to +15%
--   Tier 3: Up to +20%
--   Tier 4: Up to +25%
--   Tier 5: Up to +30%
-- ============================================================================

-- Add negotiation columns to deliveries table
ALTER TABLE deliveries ADD COLUMN IF NOT EXISTS driver_proposed_price numeric;
ALTER TABLE deliveries ADD COLUMN IF NOT EXISTS negotiation_status text; -- null, 'proposed', 'accepted', 'rejected'
ALTER TABLE deliveries ADD COLUMN IF NOT EXISTS proposing_driver_id text;
ALTER TABLE deliveries ADD COLUMN IF NOT EXISTS negotiation_expires_at timestamptz;
ALTER TABLE deliveries ADD COLUMN IF NOT EXISTS driver_qr_tier integer DEFAULT 0;

-- Add same columns to share_ride_bookings (carpools)
ALTER TABLE share_ride_bookings ADD COLUMN IF NOT EXISTS driver_proposed_price numeric;
ALTER TABLE share_ride_bookings ADD COLUMN IF NOT EXISTS negotiation_status text;
ALTER TABLE share_ride_bookings ADD COLUMN IF NOT EXISTS proposing_driver_id text;
ALTER TABLE share_ride_bookings ADD COLUMN IF NOT EXISTS negotiation_expires_at timestamptz;
ALTER TABLE share_ride_bookings ADD COLUMN IF NOT EXISTS driver_qr_tier integer DEFAULT 0;

-- Index for finding rides with active negotiations
CREATE INDEX IF NOT EXISTS idx_deliveries_negotiation_status
ON deliveries(negotiation_status) WHERE negotiation_status IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_share_ride_negotiation_status
ON share_ride_bookings(negotiation_status) WHERE negotiation_status IS NOT NULL;
