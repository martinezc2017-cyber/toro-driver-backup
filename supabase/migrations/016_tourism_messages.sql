-- ============================================================================
-- 016: Tourism Event Messages (Chat)
-- Creates the tourism_messages table for public/private messaging
-- between organizer, driver, and passengers during tourism events.
-- ============================================================================

-- Messages table
CREATE TABLE IF NOT EXISTS tourism_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES tourism_events(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL,
  sender_type text NOT NULL DEFAULT 'passenger' CHECK (sender_type IN ('organizer', 'driver', 'passenger', 'system')),
  sender_name text,
  sender_avatar_url text,
  message text,
  message_type text NOT NULL DEFAULT 'text' CHECK (message_type IN ('text', 'image', 'location', 'announcement', 'call_to_bus', 'emergency', 'system')),
  image_url text,
  thumbnail_url text,
  lat double precision,
  lng double precision,
  location_name text,
  -- target_type: 'all' = public, 'individual' = private DM, 'organizer_only', 'driver_only'
  target_type text NOT NULL DEFAULT 'all' CHECK (target_type IN ('all', 'individual', 'organizer_only', 'driver_only')),
  target_user_id uuid,  -- non-null when target_type = 'individual'
  is_pinned boolean NOT NULL DEFAULT false,
  read_by jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_tourism_messages_event ON tourism_messages(event_id);
CREATE INDEX IF NOT EXISTS idx_tourism_messages_event_created ON tourism_messages(event_id, created_at);
CREATE INDEX IF NOT EXISTS idx_tourism_messages_sender ON tourism_messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_tourism_messages_target ON tourism_messages(target_type, target_user_id);
CREATE INDEX IF NOT EXISTS idx_tourism_messages_pinned ON tourism_messages(event_id, is_pinned) WHERE is_pinned = true;

-- RLS
ALTER TABLE tourism_messages ENABLE ROW LEVEL SECURITY;

-- Everyone can read public messages for events they participate in
CREATE POLICY "tourism_messages_select" ON tourism_messages
  FOR SELECT USING (
    target_type = 'all'
    OR sender_id = auth.uid()
    OR target_user_id = auth.uid()
    OR (target_type = 'driver_only' AND EXISTS (
      SELECT 1 FROM tourism_events te WHERE te.id = event_id AND te.driver_id = auth.uid()
    ))
    OR (target_type = 'organizer_only' AND EXISTS (
      SELECT 1 FROM tourism_events te WHERE te.id = event_id AND te.organizer_id = auth.uid()
    ))
  );

-- Authenticated users can insert messages
CREATE POLICY "tourism_messages_insert" ON tourism_messages
  FOR INSERT WITH CHECK (sender_id = auth.uid());

-- Sender can update their own messages (for pin toggle by organizer/driver)
CREATE POLICY "tourism_messages_update" ON tourism_messages
  FOR UPDATE USING (
    sender_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM tourism_events te
      WHERE te.id = event_id
      AND (te.organizer_id = auth.uid() OR te.driver_id = auth.uid())
    )
  );

-- Admin full access
CREATE POLICY "admin_tourism_messages_all" ON tourism_messages
  FOR ALL USING (EXISTS (SELECT 1 FROM drivers WHERE id = auth.uid() AND role = 'admin'));

-- Enable realtime for the table
ALTER PUBLICATION supabase_realtime ADD TABLE tourism_messages;
