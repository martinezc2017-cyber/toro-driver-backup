-- Allow ALL authenticated users to read tourism_events with status='draft' and bid_visibility='public'
-- This is needed so drivers can see open events to bid on (not just their own events)
-- Without this, RLS blocks drivers from seeing other organizers' events

-- First, allow any authenticated user to SELECT tourism_events (for bidding)
CREATE POLICY IF NOT EXISTS "drivers_can_read_public_draft_events"
ON tourism_events FOR SELECT
TO authenticated
USING (
  status = 'draft'
  AND (bid_visibility IS NULL OR bid_visibility = 'public')
  AND driver_id IS NULL
);

-- Also allow drivers to read events they are assigned to (driver_id matches)
CREATE POLICY IF NOT EXISTS "drivers_can_read_assigned_events"
ON tourism_events FOR SELECT
TO authenticated
USING (
  driver_id = auth.uid()::text
);

-- Organizers can always read their own events
CREATE POLICY IF NOT EXISTS "organizers_can_read_own_events"
ON tourism_events FOR SELECT
TO authenticated
USING (
  organizer_id IN (
    SELECT id FROM organizers WHERE user_id = auth.uid()
  )
);
