-- Add passenger_count column to tourism_join_requests
-- This tracks how many passengers are in a single boarding request
ALTER TABLE tourism_join_requests
  ADD COLUMN IF NOT EXISTS passenger_count INTEGER DEFAULT 1;

COMMENT ON COLUMN tourism_join_requests.passenger_count
  IS 'Number of passengers in this boarding request (multiplies estimated_total_price)';
