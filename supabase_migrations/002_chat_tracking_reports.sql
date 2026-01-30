-- ============================================================================
-- TORO DRIVER APP - Chat, Tracking, and Reports Tables
-- Run this migration in Supabase SQL Editor
-- ============================================================================

-- ============================================================================
-- 1. CONVERSATIONS TABLE - Chat sessions between driver and rider
-- ============================================================================

CREATE TABLE IF NOT EXISTS conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id UUID NOT NULL,
    driver_id UUID NOT NULL,
    passenger_id UUID NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    -- One conversation per ride
    UNIQUE(ride_id)
);

-- Indexes for conversations
CREATE INDEX IF NOT EXISTS idx_conversations_driver_id ON conversations(driver_id);
CREATE INDEX IF NOT EXISTS idx_conversations_passenger_id ON conversations(passenger_id);
CREATE INDEX IF NOT EXISTS idx_conversations_ride_id ON conversations(ride_id);

-- RLS for conversations
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;

-- Drivers can see their conversations
CREATE POLICY "Drivers can view own conversations" ON conversations
    FOR SELECT
    USING (driver_id = auth.uid() OR passenger_id = auth.uid());

-- Drivers can create conversations
CREATE POLICY "Drivers can create conversations" ON conversations
    FOR INSERT
    WITH CHECK (driver_id = auth.uid() OR passenger_id = auth.uid());

-- ============================================================================
-- 2. MESSAGES TABLE - Chat messages
-- ============================================================================

CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL,
    receiver_id UUID NOT NULL,
    content TEXT NOT NULL,
    type VARCHAR(20) DEFAULT 'text', -- text, image, location, system, quickResponse
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    is_read BOOLEAN DEFAULT FALSE,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for messages
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_messages_sender_id ON messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_messages_receiver_id ON messages(receiver_id);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at);
CREATE INDEX IF NOT EXISTS idx_messages_is_read ON messages(is_read);

-- RLS for messages
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- Users can see messages where they are sender or receiver
CREATE POLICY "Users can view own messages" ON messages
    FOR SELECT
    USING (sender_id = auth.uid() OR receiver_id = auth.uid());

-- Users can send messages
CREATE POLICY "Users can send messages" ON messages
    FOR INSERT
    WITH CHECK (sender_id = auth.uid());

-- Users can mark messages as read
CREATE POLICY "Users can mark messages as read" ON messages
    FOR UPDATE
    USING (receiver_id = auth.uid());

-- ============================================================================
-- 3. DRIVER_LOCATIONS TABLE - Real-time driver tracking
-- ============================================================================

CREATE TABLE IF NOT EXISTS driver_locations (
    driver_id UUID PRIMARY KEY,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    heading DOUBLE PRECISION,
    speed DOUBLE PRECISION,
    accuracy DOUBLE PRECISION,
    is_online BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for location queries
CREATE INDEX IF NOT EXISTS idx_driver_locations_updated_at ON driver_locations(updated_at);
CREATE INDEX IF NOT EXISTS idx_driver_locations_is_online ON driver_locations(is_online);

-- RLS for driver_locations
ALTER TABLE driver_locations ENABLE ROW LEVEL SECURITY;

-- Anyone can read online driver locations (for rider app)
CREATE POLICY "Anyone can view online driver locations" ON driver_locations
    FOR SELECT
    USING (is_online = TRUE);

-- Drivers can update their own location
CREATE POLICY "Drivers can update own location" ON driver_locations
    FOR ALL
    USING (driver_id = auth.uid());

-- ============================================================================
-- 4. ADD DRIVER TRACKING COLUMNS TO DELIVERIES
-- ============================================================================

-- Add columns to deliveries for real-time driver location tracking
ALTER TABLE deliveries ADD COLUMN IF NOT EXISTS driver_lat DOUBLE PRECISION;
ALTER TABLE deliveries ADD COLUMN IF NOT EXISTS driver_lng DOUBLE PRECISION;
ALTER TABLE deliveries ADD COLUMN IF NOT EXISTS driver_heading DOUBLE PRECISION;
ALTER TABLE deliveries ADD COLUMN IF NOT EXISTS driver_speed DOUBLE PRECISION;
ALTER TABLE deliveries ADD COLUMN IF NOT EXISTS driver_location_updated_at TIMESTAMPTZ;

-- ============================================================================
-- 5. DRIVER_REPORTS TABLE - Reports from drivers about riders
-- ============================================================================

CREATE TABLE IF NOT EXISTS driver_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id UUID NOT NULL,
    ride_id UUID NOT NULL,
    rider_id UUID NOT NULL,
    rider_name VARCHAR(255),
    reason VARCHAR(50) NOT NULL, -- rude, no_show, wrong_address, unsafe, intoxicated, damage, harassment, other
    details TEXT,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    status VARCHAR(20) DEFAULT 'pending', -- pending, reviewed, resolved, dismissed
    admin_notes TEXT,
    reviewed_at TIMESTAMPTZ,
    reviewed_by UUID,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for driver_reports
CREATE INDEX IF NOT EXISTS idx_driver_reports_driver_id ON driver_reports(driver_id);
CREATE INDEX IF NOT EXISTS idx_driver_reports_ride_id ON driver_reports(ride_id);
CREATE INDEX IF NOT EXISTS idx_driver_reports_rider_id ON driver_reports(rider_id);
CREATE INDEX IF NOT EXISTS idx_driver_reports_status ON driver_reports(status);
CREATE INDEX IF NOT EXISTS idx_driver_reports_created_at ON driver_reports(created_at);

-- RLS for driver_reports
ALTER TABLE driver_reports ENABLE ROW LEVEL SECURITY;

-- Drivers can create reports
CREATE POLICY "Drivers can create reports" ON driver_reports
    FOR INSERT
    WITH CHECK (driver_id = auth.uid());

-- Drivers can view their own reports
CREATE POLICY "Drivers can view own reports" ON driver_reports
    FOR SELECT
    USING (driver_id = auth.uid());

-- Admins can manage all reports
CREATE POLICY "Admins can manage reports" ON driver_reports
    FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE profiles.id = auth.uid()
            AND profiles.role = 'admin'
        )
    );

-- ============================================================================
-- 6. NOTIFICATIONS TABLE - Driver notifications
-- ============================================================================

CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id UUID NOT NULL,
    type VARCHAR(50) NOT NULL, -- ride_request, message, earning, payout, system
    title VARCHAR(255) NOT NULL,
    body TEXT,
    data JSONB,
    is_read BOOLEAN DEFAULT FALSE,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for notifications
CREATE INDEX IF NOT EXISTS idx_notifications_driver_id ON notifications(driver_id);
CREATE INDEX IF NOT EXISTS idx_notifications_type ON notifications(type);
CREATE INDEX IF NOT EXISTS idx_notifications_is_read ON notifications(is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON notifications(created_at);

-- RLS for notifications
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Drivers can view their own notifications
CREATE POLICY "Drivers can view own notifications" ON notifications
    FOR SELECT
    USING (driver_id = auth.uid());

-- Drivers can mark notifications as read
CREATE POLICY "Drivers can update own notifications" ON notifications
    FOR UPDATE
    USING (driver_id = auth.uid());

-- ============================================================================
-- 7. RATINGS TABLE - Ratings between drivers and passengers
-- ============================================================================

CREATE TABLE IF NOT EXISTS ratings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id UUID NOT NULL,
    rater_id UUID NOT NULL,
    rated_id UUID NOT NULL,
    rated_by VARCHAR(20) NOT NULL, -- 'driver' or 'passenger'
    rating DECIMAL(2,1) NOT NULL CHECK (rating >= 1 AND rating <= 5),
    comment TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for ratings
CREATE INDEX IF NOT EXISTS idx_ratings_ride_id ON ratings(ride_id);
CREATE INDEX IF NOT EXISTS idx_ratings_rater_id ON ratings(rater_id);
CREATE INDEX IF NOT EXISTS idx_ratings_rated_id ON ratings(rated_id);
CREATE INDEX IF NOT EXISTS idx_ratings_created_at ON ratings(created_at);

-- RLS for ratings
ALTER TABLE ratings ENABLE ROW LEVEL SECURITY;

-- Users can create ratings for rides they participated in
CREATE POLICY "Users can create ratings" ON ratings
    FOR INSERT
    WITH CHECK (rater_id = auth.uid());

-- Users can view ratings where they are involved
CREATE POLICY "Users can view own ratings" ON ratings
    FOR SELECT
    USING (rater_id = auth.uid() OR rated_id = auth.uid());

-- ============================================================================
-- 8. HELPER FUNCTIONS
-- ============================================================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to conversations
DROP TRIGGER IF EXISTS update_conversations_updated_at ON conversations;
CREATE TRIGGER update_conversations_updated_at
    BEFORE UPDATE ON conversations
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Apply trigger to driver_locations
DROP TRIGGER IF EXISTS update_driver_locations_updated_at ON driver_locations;
CREATE TRIGGER update_driver_locations_updated_at
    BEFORE UPDATE ON driver_locations
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- 9. REALTIME SUBSCRIPTIONS
-- ============================================================================

-- Enable realtime for messages (for live chat)
ALTER PUBLICATION supabase_realtime ADD TABLE messages;

-- Enable realtime for driver_locations (for live tracking)
ALTER PUBLICATION supabase_realtime ADD TABLE driver_locations;

-- Enable realtime for notifications
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;

-- ============================================================================
-- END OF MIGRATION
-- ============================================================================
