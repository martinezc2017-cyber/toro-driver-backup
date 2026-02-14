-- Add missing columns for bid negotiation loop
-- negotiation_round: tracks how many rounds of counter-offers
-- organizer_proposed_price: price the organizer proposes in counter-offer
-- driver_proposed_price: price the driver proposes in counter-offer back
-- responded_at: when organizer responded to the bid

ALTER TABLE tourism_vehicle_bids ADD COLUMN IF NOT EXISTS negotiation_round integer DEFAULT 0;
ALTER TABLE tourism_vehicle_bids ADD COLUMN IF NOT EXISTS organizer_proposed_price numeric;
ALTER TABLE tourism_vehicle_bids ADD COLUMN IF NOT EXISTS driver_proposed_price numeric;
ALTER TABLE tourism_vehicle_bids ADD COLUMN IF NOT EXISTS responded_at timestamptz;

-- RLS: Allow drivers to UPDATE their own bids (for counter-offers and accepting)
CREATE POLICY IF NOT EXISTS "drivers_can_update_own_bids"
ON tourism_vehicle_bids FOR UPDATE
TO authenticated
USING (driver_id = auth.uid()::text)
WITH CHECK (driver_id = auth.uid()::text);

-- RLS: Allow organizers to UPDATE bids on their events (for counter-offers and selecting)
CREATE POLICY IF NOT EXISTS "organizers_can_update_event_bids"
ON tourism_vehicle_bids FOR UPDATE
TO authenticated
USING (
  event_id IN (
    SELECT id FROM tourism_events
    WHERE organizer_id IN (
      SELECT id FROM organizers WHERE user_id = auth.uid()
    )
  )
);

-- RLS: Allow organizers to SELECT bids on their events
CREATE POLICY IF NOT EXISTS "organizers_can_read_event_bids"
ON tourism_vehicle_bids FOR SELECT
TO authenticated
USING (
  event_id IN (
    SELECT id FROM tourism_events
    WHERE organizer_id IN (
      SELECT id FROM organizers WHERE user_id = auth.uid()
    )
  )
);

-- RLS: Allow drivers to SELECT their own bids
CREATE POLICY IF NOT EXISTS "drivers_can_read_own_bids"
ON tourism_vehicle_bids FOR SELECT
TO authenticated
USING (driver_id = auth.uid()::text);
