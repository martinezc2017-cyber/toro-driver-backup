-- Fix notifications RLS: old policies referenced driver_id which no longer exists
-- The table was recreated with user_id column instead

-- Drop broken old policies that reference non-existent driver_id column
DROP POLICY IF EXISTS "Drivers can view own notifications" ON notifications;
DROP POLICY IF EXISTS "Drivers can update own notifications" ON notifications;

-- Ensure RLS is enabled
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Users can only read their own notifications
CREATE POLICY users_read_own_notifications ON notifications
  FOR SELECT TO authenticated USING (user_id = auth.uid());

-- Users can only update their own notifications (mark as read)
CREATE POLICY users_update_own_notifications ON notifications
  FOR UPDATE TO authenticated USING (user_id = auth.uid());

-- Any authenticated user can insert notifications (organizer notifies driver, etc.)
CREATE POLICY users_insert_notifications ON notifications
  FOR INSERT TO authenticated WITH CHECK (true);

-- Add tourism_vehicle_bids to Realtime publication for bid status updates
ALTER PUBLICATION supabase_realtime ADD TABLE tourism_vehicle_bids;
