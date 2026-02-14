-- ============================================================================
-- 014: Tourism Hub System
-- Tables for saved items, free area drivers, and free area ride requests.
-- ============================================================================

-- Saved items (riders save events, routes, drivers for quick access)
CREATE TABLE IF NOT EXISTS tourism_saved_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  item_type text NOT NULL CHECK (item_type IN ('event', 'route', 'driver', 'organizer')),
  item_id text NOT NULL,
  item_name text,
  item_meta jsonb DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, item_type, item_id)
);

-- Free area drivers (drivers available by zone, no fixed itinerary)
CREATE TABLE IF NOT EXISTS free_area_drivers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id uuid NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  lat double precision NOT NULL DEFAULT 0,
  lng double precision NOT NULL DEFAULT 0,
  radius_km numeric(8,2) NOT NULL DEFAULT 50,
  is_available boolean NOT NULL DEFAULT true,
  vehicle_id uuid REFERENCES bus_vehicles(id),
  country_code text NOT NULL DEFAULT 'MX',
  state_code text,
  price_per_km numeric(8,2) NOT NULL DEFAULT 85.00,
  bio text,
  last_location_update timestamptz DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(driver_id)
);

-- Free area ride requests (rider requests a ride from a free area driver)
CREATE TABLE IF NOT EXISTS free_area_ride_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  rider_id uuid NOT NULL,
  driver_id uuid NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  pickup_address text,
  pickup_lat double precision,
  pickup_lng double precision,
  destination_address text,
  destination_lat double precision,
  destination_lng double precision,
  estimated_km numeric(8,2),
  estimated_price numeric(12,2),
  message text,
  passengers_count int NOT NULL DEFAULT 1,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected', 'cancelled', 'completed')),
  driver_response_at timestamptz,
  driver_notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_tourism_saved_items_user ON tourism_saved_items(user_id);
CREATE INDEX IF NOT EXISTS idx_tourism_saved_items_type ON tourism_saved_items(user_id, item_type);
CREATE INDEX IF NOT EXISTS idx_free_area_drivers_available ON free_area_drivers(is_available) WHERE is_available = true;
CREATE INDEX IF NOT EXISTS idx_free_area_drivers_location ON free_area_drivers(lat, lng);
CREATE INDEX IF NOT EXISTS idx_free_area_drivers_country ON free_area_drivers(country_code, state_code);
CREATE INDEX IF NOT EXISTS idx_free_area_ride_requests_rider ON free_area_ride_requests(rider_id);
CREATE INDEX IF NOT EXISTS idx_free_area_ride_requests_driver ON free_area_ride_requests(driver_id);
CREATE INDEX IF NOT EXISTS idx_free_area_ride_requests_status ON free_area_ride_requests(status);

-- RLS
ALTER TABLE tourism_saved_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE free_area_drivers ENABLE ROW LEVEL SECURITY;
ALTER TABLE free_area_ride_requests ENABLE ROW LEVEL SECURITY;

-- Saved items: user can CRUD their own
CREATE POLICY "saved_items_select" ON tourism_saved_items
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "saved_items_insert" ON tourism_saved_items
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "saved_items_delete" ON tourism_saved_items
  FOR DELETE USING (user_id = auth.uid());

-- Free area drivers: anyone can read available, driver can manage their own
CREATE POLICY "free_area_drivers_select" ON free_area_drivers
  FOR SELECT USING (is_available = true OR driver_id = auth.uid());

CREATE POLICY "free_area_drivers_insert" ON free_area_drivers
  FOR INSERT WITH CHECK (
    driver_id IN (SELECT id FROM drivers WHERE user_id = auth.uid())
    OR driver_id = auth.uid()
  );

CREATE POLICY "free_area_drivers_update" ON free_area_drivers
  FOR UPDATE USING (
    driver_id IN (SELECT id FROM drivers WHERE user_id = auth.uid())
    OR driver_id = auth.uid()
  );

CREATE POLICY "free_area_drivers_delete" ON free_area_drivers
  FOR DELETE USING (
    driver_id IN (SELECT id FROM drivers WHERE user_id = auth.uid())
    OR driver_id = auth.uid()
  );

-- Free area ride requests: rider can CRUD their own, driver can read/update theirs
CREATE POLICY "free_area_requests_rider_select" ON free_area_ride_requests
  FOR SELECT USING (rider_id = auth.uid() OR driver_id = auth.uid());

CREATE POLICY "free_area_requests_rider_insert" ON free_area_ride_requests
  FOR INSERT WITH CHECK (rider_id = auth.uid());

CREATE POLICY "free_area_requests_update" ON free_area_ride_requests
  FOR UPDATE USING (rider_id = auth.uid() OR driver_id = auth.uid());

-- Admin full access
CREATE POLICY "admin_saved_items_all" ON tourism_saved_items
  FOR ALL USING (EXISTS (SELECT 1 FROM drivers WHERE id = auth.uid() AND role = 'admin'));

CREATE POLICY "admin_free_area_drivers_all" ON free_area_drivers
  FOR ALL USING (EXISTS (SELECT 1 FROM drivers WHERE id = auth.uid() AND role = 'admin'));

CREATE POLICY "admin_free_area_requests_all" ON free_area_ride_requests
  FOR ALL USING (EXISTS (SELECT 1 FROM drivers WHERE id = auth.uid() AND role = 'admin'));
