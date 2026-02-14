-- Make vehicle_id nullable in tourism_vehicle_bids
-- During bidding phase, driver may not have selected a specific vehicle yet
-- Vehicle gets assigned when bid is accepted (simbiosis)
ALTER TABLE tourism_vehicle_bids ALTER COLUMN vehicle_id DROP NOT NULL;
