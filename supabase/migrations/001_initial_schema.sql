-- ============================================================================
-- TORO DRIVER - COMPLETE DATABASE SCHEMA
-- Supabase PostgreSQL Migration
-- ============================================================================

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- ============================================================================
-- ENUM TYPES
-- ============================================================================

-- Ride status enum
CREATE TYPE ride_status AS ENUM (
  'pending',
  'accepted',
  'arrivedAtPickup',
  'inProgress',
  'completed',
  'cancelled'
);

-- Ride type enum
CREATE TYPE ride_type AS ENUM (
  'passenger',
  'package',
  'carpool'
);

-- Payment method enum
CREATE TYPE payment_method AS ENUM (
  'cash',
  'card',
  'wallet'
);

-- Vehicle status enum
CREATE TYPE vehicle_status AS ENUM (
  'active',
  'inactive',
  'pendingVerification',
  'rejected'
);

-- Document type enum
CREATE TYPE document_type AS ENUM (
  'driverLicense',
  'nationalId',
  'proofOfAddress',
  'criminalRecord',
  'taxId',
  'profilePhoto',
  'vehicleRegistration',
  'vehicleInsurance',
  'vehicleInspection',
  'vehiclePhoto'
);

-- Document status enum
CREATE TYPE document_status AS ENUM (
  'pending',
  'approved',
  'rejected',
  'expired'
);

-- Transaction type enum
CREATE TYPE transaction_type AS ENUM (
  'rideEarning',
  'tip',
  'bonus',
  'referralBonus',
  'withdrawal',
  'platformFee',
  'adjustment'
);

-- Message type enum
CREATE TYPE message_type AS ENUM (
  'text',
  'image',
  'location',
  'system',
  'quickResponse'
);

-- Referral status enum
CREATE TYPE referral_status AS ENUM (
  'pending',
  'completed',
  'expired'
);

-- ============================================================================
-- DRIVERS TABLE
-- ============================================================================

CREATE TABLE drivers (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT UNIQUE NOT NULL,
  phone TEXT NOT NULL,
  first_name TEXT NOT NULL,
  last_name TEXT NOT NULL,
  username TEXT UNIQUE,
  license_number TEXT,
  profile_image_url TEXT,
  rating DECIMAL(3,2) DEFAULT 5.00,
  total_rides INTEGER DEFAULT 0,
  total_hours INTEGER DEFAULT 0,
  total_earnings DECIMAL(12,2) DEFAULT 0.00,
  acceptance_rate DECIMAL(3,2) DEFAULT 1.00,
  cancellation_rate DECIMAL(3,2) DEFAULT 0.00,
  is_online BOOLEAN DEFAULT FALSE,
  is_verified BOOLEAN DEFAULT FALSE,
  is_email_verified BOOLEAN DEFAULT FALSE,
  is_active BOOLEAN DEFAULT TRUE,
  current_vehicle_id UUID,
  referral_code TEXT UNIQUE,
  preferences JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for drivers
CREATE INDEX idx_drivers_email ON drivers(email);
CREATE INDEX idx_drivers_phone ON drivers(phone);
CREATE INDEX idx_drivers_is_online ON drivers(is_online);
CREATE INDEX idx_drivers_is_active ON drivers(is_active);
CREATE INDEX idx_drivers_referral_code ON drivers(referral_code);
CREATE INDEX idx_drivers_total_earnings ON drivers(total_earnings DESC);

-- ============================================================================
-- VEHICLES TABLE
-- ============================================================================

CREATE TABLE vehicles (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  driver_id UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  brand TEXT NOT NULL,
  model TEXT NOT NULL,
  year INTEGER NOT NULL,
  color TEXT NOT NULL,
  plate_number TEXT UNIQUE NOT NULL,
  vin TEXT,
  status vehicle_status DEFAULT 'pendingVerification',
  is_verified BOOLEAN DEFAULT FALSE,
  total_kilometers INTEGER DEFAULT 0,
  total_rides INTEGER DEFAULT 0,
  rating DECIMAL(3,2) DEFAULT 5.00,
  image_urls TEXT[] DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add foreign key to drivers for current vehicle
ALTER TABLE drivers ADD CONSTRAINT fk_current_vehicle
  FOREIGN KEY (current_vehicle_id) REFERENCES vehicles(id) ON DELETE SET NULL;

-- Indexes for vehicles
CREATE INDEX idx_vehicles_driver_id ON vehicles(driver_id);
CREATE INDEX idx_vehicles_plate_number ON vehicles(plate_number);
CREATE INDEX idx_vehicles_status ON vehicles(status);

-- ============================================================================
-- RIDES TABLE
-- ============================================================================

CREATE TABLE rides (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  driver_id UUID REFERENCES drivers(id) ON DELETE SET NULL,
  passenger_id TEXT NOT NULL,
  passenger_name TEXT NOT NULL,
  passenger_phone TEXT,
  passenger_image_url TEXT,
  passenger_rating DECIMAL(3,2) DEFAULT 5.00,
  type ride_type DEFAULT 'passenger',
  status ride_status DEFAULT 'pending',

  -- Pickup location
  pickup_latitude DECIMAL(10,8) NOT NULL,
  pickup_longitude DECIMAL(11,8) NOT NULL,
  pickup_address TEXT,

  -- Dropoff location
  dropoff_latitude DECIMAL(10,8) NOT NULL,
  dropoff_longitude DECIMAL(11,8) NOT NULL,
  dropoff_address TEXT,

  -- Ride details
  distance_km DECIMAL(10,2) NOT NULL,
  estimated_minutes INTEGER NOT NULL,
  fare DECIMAL(10,2) NOT NULL,
  tip DECIMAL(10,2) DEFAULT 0.00,
  platform_fee DECIMAL(10,2) NOT NULL,
  driver_earnings DECIMAL(10,2) NOT NULL,
  payment_method payment_method DEFAULT 'cash',
  is_paid BOOLEAN DEFAULT FALSE,
  notes TEXT,
  is_urgent BOOLEAN DEFAULT FALSE,

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  accepted_at TIMESTAMPTZ,
  arrived_at TIMESTAMPTZ,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  cancellation_reason TEXT
);

-- Indexes for rides
CREATE INDEX idx_rides_driver_id ON rides(driver_id);
CREATE INDEX idx_rides_passenger_id ON rides(passenger_id);
CREATE INDEX idx_rides_status ON rides(status);
CREATE INDEX idx_rides_created_at ON rides(created_at DESC);
CREATE INDEX idx_rides_completed_at ON rides(completed_at DESC);
CREATE INDEX idx_rides_pickup_location ON rides USING GIST (
  ST_SetSRID(ST_MakePoint(pickup_longitude, pickup_latitude), 4326)
);

-- ============================================================================
-- DOCUMENTS TABLE
-- ============================================================================

CREATE TABLE documents (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  driver_id UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  vehicle_id UUID REFERENCES vehicles(id) ON DELETE SET NULL,
  type document_type NOT NULL,
  name TEXT NOT NULL,
  file_url TEXT NOT NULL,
  status document_status DEFAULT 'pending',
  rejection_reason TEXT,
  expiration_date DATE,
  uploaded_at TIMESTAMPTZ DEFAULT NOW(),
  reviewed_at TIMESTAMPTZ
);

-- Indexes for documents
CREATE INDEX idx_documents_driver_id ON documents(driver_id);
CREATE INDEX idx_documents_vehicle_id ON documents(vehicle_id);
CREATE INDEX idx_documents_type ON documents(type);
CREATE INDEX idx_documents_status ON documents(status);
CREATE INDEX idx_documents_expiration ON documents(expiration_date);

-- ============================================================================
-- EARNINGS TABLE
-- ============================================================================

CREATE TABLE earnings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  driver_id UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  ride_id UUID REFERENCES rides(id) ON DELETE SET NULL,
  type transaction_type NOT NULL,
  amount DECIMAL(10,2) NOT NULL,
  description TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for earnings
CREATE INDEX idx_earnings_driver_id ON earnings(driver_id);
CREATE INDEX idx_earnings_ride_id ON earnings(ride_id);
CREATE INDEX idx_earnings_type ON earnings(type);
CREATE INDEX idx_earnings_created_at ON earnings(created_at DESC);

-- ============================================================================
-- DRIVER LOCATIONS TABLE (Real-time tracking)
-- ============================================================================

CREATE TABLE driver_locations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  driver_id UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  latitude DECIMAL(10,8) NOT NULL,
  longitude DECIMAL(11,8) NOT NULL,
  heading DECIMAL(5,2),
  speed DECIMAL(6,2),
  accuracy DECIMAL(6,2),
  is_online BOOLEAN DEFAULT TRUE,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Unique constraint - one location per driver
CREATE UNIQUE INDEX idx_driver_locations_driver_id ON driver_locations(driver_id);

-- Spatial index for location queries
CREATE INDEX idx_driver_locations_geom ON driver_locations USING GIST (
  ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)
);

-- ============================================================================
-- CONVERSATIONS TABLE
-- ============================================================================

CREATE TABLE conversations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  ride_id UUID REFERENCES rides(id) ON DELETE CASCADE,
  driver_id UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  passenger_id TEXT NOT NULL,
  last_message_at TIMESTAMPTZ DEFAULT NOW(),
  driver_unread_count INTEGER DEFAULT 0,
  passenger_unread_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for conversations
CREATE INDEX idx_conversations_ride_id ON conversations(ride_id);
CREATE INDEX idx_conversations_driver_id ON conversations(driver_id);
CREATE INDEX idx_conversations_last_message ON conversations(last_message_at DESC);

-- ============================================================================
-- MESSAGES TABLE
-- ============================================================================

CREATE TABLE messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id TEXT NOT NULL,
  receiver_id TEXT NOT NULL,
  type message_type DEFAULT 'text',
  content TEXT NOT NULL,
  latitude DECIMAL(10,8),
  longitude DECIMAL(11,8),
  is_read BOOLEAN DEFAULT FALSE,
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for messages
CREATE INDEX idx_messages_conversation_id ON messages(conversation_id);
CREATE INDEX idx_messages_sender_id ON messages(sender_id);
CREATE INDEX idx_messages_created_at ON messages(created_at DESC);

-- ============================================================================
-- RATINGS TABLE
-- ============================================================================

CREATE TABLE ratings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  ride_id UUID NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
  driver_id UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  passenger_id TEXT NOT NULL,
  driver_rating DECIMAL(2,1),
  driver_comment TEXT,
  passenger_rating DECIMAL(2,1),
  passenger_comment TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for ratings
CREATE INDEX idx_ratings_ride_id ON ratings(ride_id);
CREATE INDEX idx_ratings_driver_id ON ratings(driver_id);

-- ============================================================================
-- REFERRALS TABLE
-- ============================================================================

CREATE TABLE referrals (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  referrer_id UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  referred_id UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  code_used TEXT NOT NULL,
  status referral_status DEFAULT 'pending',
  bonus_amount DECIMAL(10,2) DEFAULT 0.00,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for referrals
CREATE INDEX idx_referrals_referrer_id ON referrals(referrer_id);
CREATE INDEX idx_referrals_referred_id ON referrals(referred_id);
CREATE INDEX idx_referrals_status ON referrals(status);

-- ============================================================================
-- NOTIFICATIONS TABLE
-- ============================================================================

CREATE TABLE notifications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  driver_id UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  data JSONB DEFAULT '{}',
  is_read BOOLEAN DEFAULT FALSE,
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for notifications
CREATE INDEX idx_notifications_driver_id ON notifications(driver_id);
CREATE INDEX idx_notifications_is_read ON notifications(is_read);
CREATE INDEX idx_notifications_created_at ON notifications(created_at DESC);

-- ============================================================================
-- WITHDRAWAL REQUESTS TABLE
-- ============================================================================

CREATE TABLE withdrawal_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  driver_id UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  amount DECIMAL(10,2) NOT NULL,
  status TEXT DEFAULT 'pending',
  payment_method TEXT NOT NULL,
  payment_details JSONB NOT NULL,
  processed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for withdrawals
CREATE INDEX idx_withdrawals_driver_id ON withdrawal_requests(driver_id);
CREATE INDEX idx_withdrawals_status ON withdrawal_requests(status);

-- ============================================================================
-- UPDATED_AT TRIGGER FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to relevant tables
CREATE TRIGGER update_drivers_updated_at
  BEFORE UPDATE ON drivers
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_vehicles_updated_at
  BEFORE UPDATE ON vehicles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_driver_locations_updated_at
  BEFORE UPDATE ON driver_locations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- ROW LEVEL SECURITY POLICIES
-- ============================================================================

-- Enable RLS on all tables
ALTER TABLE drivers ENABLE ROW LEVEL SECURITY;
ALTER TABLE vehicles ENABLE ROW LEVEL SECURITY;
ALTER TABLE rides ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE earnings ENABLE ROW LEVEL SECURITY;
ALTER TABLE driver_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE ratings ENABLE ROW LEVEL SECURITY;
ALTER TABLE referrals ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE withdrawal_requests ENABLE ROW LEVEL SECURITY;

-- Drivers policies
CREATE POLICY "Drivers can view own profile" ON drivers
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Drivers can update own profile" ON drivers
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Allow insert for authenticated users" ON drivers
  FOR INSERT WITH CHECK (auth.uid() = id);

-- Vehicles policies
CREATE POLICY "Drivers can view own vehicles" ON vehicles
  FOR SELECT USING (auth.uid() = driver_id);

CREATE POLICY "Drivers can manage own vehicles" ON vehicles
  FOR ALL USING (auth.uid() = driver_id);

-- Rides policies
CREATE POLICY "Drivers can view assigned rides" ON rides
  FOR SELECT USING (auth.uid() = driver_id OR driver_id IS NULL);

CREATE POLICY "Drivers can update assigned rides" ON rides
  FOR UPDATE USING (auth.uid() = driver_id);

CREATE POLICY "Anyone can view pending rides" ON rides
  FOR SELECT USING (status = 'pending' AND driver_id IS NULL);

-- Documents policies
CREATE POLICY "Drivers can view own documents" ON documents
  FOR SELECT USING (auth.uid() = driver_id);

CREATE POLICY "Drivers can manage own documents" ON documents
  FOR ALL USING (auth.uid() = driver_id);

-- Earnings policies
CREATE POLICY "Drivers can view own earnings" ON earnings
  FOR SELECT USING (auth.uid() = driver_id);

-- Driver locations policies
CREATE POLICY "Drivers can manage own location" ON driver_locations
  FOR ALL USING (auth.uid() = driver_id);

CREATE POLICY "Public can view online driver locations" ON driver_locations
  FOR SELECT USING (is_online = TRUE);

-- Conversations policies
CREATE POLICY "Drivers can view own conversations" ON conversations
  FOR SELECT USING (auth.uid() = driver_id);

-- Messages policies
CREATE POLICY "Users can view messages in their conversations" ON messages
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM conversations
      WHERE conversations.id = messages.conversation_id
      AND conversations.driver_id = auth.uid()
    )
  );

CREATE POLICY "Users can send messages" ON messages
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM conversations
      WHERE conversations.id = conversation_id
      AND conversations.driver_id = auth.uid()
    )
  );

-- Ratings policies
CREATE POLICY "Drivers can view and add ratings" ON ratings
  FOR ALL USING (auth.uid() = driver_id);

-- Referrals policies
CREATE POLICY "Drivers can view own referrals" ON referrals
  FOR SELECT USING (auth.uid() = referrer_id OR auth.uid() = referred_id);

-- Notifications policies
CREATE POLICY "Drivers can view own notifications" ON notifications
  FOR SELECT USING (auth.uid() = driver_id);

CREATE POLICY "Drivers can update own notifications" ON notifications
  FOR UPDATE USING (auth.uid() = driver_id);

-- Withdrawal requests policies
CREATE POLICY "Drivers can view and create own withdrawals" ON withdrawal_requests
  FOR ALL USING (auth.uid() = driver_id);

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Function to get driver's earnings summary
CREATE OR REPLACE FUNCTION get_driver_earnings_summary(p_driver_id UUID)
RETURNS TABLE (
  today_earnings DECIMAL,
  week_earnings DECIMAL,
  month_earnings DECIMAL,
  total_balance DECIMAL,
  today_rides INTEGER,
  week_rides INTEGER,
  today_tips DECIMAL,
  week_tips DECIMAL
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    COALESCE(SUM(CASE WHEN e.created_at >= CURRENT_DATE THEN e.amount ELSE 0 END), 0) as today_earnings,
    COALESCE(SUM(CASE WHEN e.created_at >= DATE_TRUNC('week', CURRENT_DATE) THEN e.amount ELSE 0 END), 0) as week_earnings,
    COALESCE(SUM(CASE WHEN e.created_at >= DATE_TRUNC('month', CURRENT_DATE) THEN e.amount ELSE 0 END), 0) as month_earnings,
    d.total_earnings as total_balance,
    (SELECT COUNT(*)::INTEGER FROM rides r WHERE r.driver_id = p_driver_id AND r.completed_at >= CURRENT_DATE) as today_rides,
    (SELECT COUNT(*)::INTEGER FROM rides r WHERE r.driver_id = p_driver_id AND r.completed_at >= DATE_TRUNC('week', CURRENT_DATE)) as week_rides,
    COALESCE(SUM(CASE WHEN e.type = 'tip' AND e.created_at >= CURRENT_DATE THEN e.amount ELSE 0 END), 0) as today_tips,
    COALESCE(SUM(CASE WHEN e.type = 'tip' AND e.created_at >= DATE_TRUNC('week', CURRENT_DATE) THEN e.amount ELSE 0 END), 0) as week_tips
  FROM drivers d
  LEFT JOIN earnings e ON e.driver_id = d.id
  WHERE d.id = p_driver_id
  GROUP BY d.id, d.total_earnings;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to find nearby available rides
CREATE OR REPLACE FUNCTION get_available_rides_nearby(
  p_latitude DECIMAL,
  p_longitude DECIMAL,
  p_radius_km DECIMAL DEFAULT 10
)
RETURNS SETOF rides AS $$
BEGIN
  RETURN QUERY
  SELECT r.*
  FROM rides r
  WHERE r.status = 'pending'
    AND r.driver_id IS NULL
    AND ST_DWithin(
      ST_SetSRID(ST_MakePoint(r.pickup_longitude, r.pickup_latitude), 4326)::geography,
      ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326)::geography,
      p_radius_km * 1000
    )
  ORDER BY
    ST_Distance(
      ST_SetSRID(ST_MakePoint(r.pickup_longitude, r.pickup_latitude), 4326)::geography,
      ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326)::geography
    )
  LIMIT 50;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to accept a ride
CREATE OR REPLACE FUNCTION accept_ride(p_ride_id UUID, p_driver_id UUID)
RETURNS rides AS $$
DECLARE
  v_ride rides;
BEGIN
  UPDATE rides
  SET
    driver_id = p_driver_id,
    status = 'accepted',
    accepted_at = NOW()
  WHERE id = p_ride_id
    AND status = 'pending'
    AND driver_id IS NULL
  RETURNING * INTO v_ride;

  IF v_ride IS NULL THEN
    RAISE EXCEPTION 'Ride not available';
  END IF;

  RETURN v_ride;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to complete a ride
CREATE OR REPLACE FUNCTION complete_ride(p_ride_id UUID, p_tip DECIMAL DEFAULT 0)
RETURNS rides AS $$
DECLARE
  v_ride rides;
BEGIN
  UPDATE rides
  SET
    status = 'completed',
    completed_at = NOW(),
    tip = p_tip,
    is_paid = TRUE
  WHERE id = p_ride_id
    AND status = 'inProgress'
  RETURNING * INTO v_ride;

  IF v_ride IS NULL THEN
    RAISE EXCEPTION 'Ride not in progress';
  END IF;

  -- Add earning record
  INSERT INTO earnings (driver_id, ride_id, type, amount, description)
  VALUES (v_ride.driver_id, v_ride.id, 'rideEarning', v_ride.driver_earnings, 'Viaje completado');

  -- Add tip if present
  IF p_tip > 0 THEN
    INSERT INTO earnings (driver_id, ride_id, type, amount, description)
    VALUES (v_ride.driver_id, v_ride.id, 'tip', p_tip, 'Propina');
  END IF;

  -- Update driver stats
  UPDATE drivers
  SET
    total_rides = total_rides + 1,
    total_earnings = total_earnings + v_ride.driver_earnings + p_tip
  WHERE id = v_ride.driver_id;

  RETURN v_ride;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- REALTIME SUBSCRIPTIONS
-- ============================================================================

-- Enable realtime for relevant tables
ALTER PUBLICATION supabase_realtime ADD TABLE rides;
ALTER PUBLICATION supabase_realtime ADD TABLE drivers;
ALTER PUBLICATION supabase_realtime ADD TABLE driver_locations;
ALTER PUBLICATION supabase_realtime ADD TABLE messages;
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;

-- ============================================================================
-- STORAGE BUCKETS (Run in Supabase Dashboard or via API)
-- ============================================================================

-- Note: Storage buckets need to be created via Supabase Dashboard or API
-- - profile-images (public)
-- - documents (private)
-- - vehicle-images (public)
