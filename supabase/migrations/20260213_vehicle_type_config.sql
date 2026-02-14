-- ============================================================================
-- Vehicle Type Configuration Table
-- Admin toggles vehicle types on/off per country. Rider app reads enabled types.
-- ============================================================================

-- 1. Create vehicle_type_config table
CREATE TABLE IF NOT EXISTS vehicle_type_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  country_code TEXT NOT NULL,
  vehicle_type TEXT NOT NULL,
  display_name TEXT NOT NULL,
  description TEXT,
  icon_name TEXT DEFAULT 'directions_car',
  max_passengers INT DEFAULT 4,
  is_enabled BOOLEAN DEFAULT false,
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(country_code, vehicle_type)
);

-- 2. Seed MX vehicle types (all disabled by default — admin enables via toggle)
INSERT INTO vehicle_type_config (country_code, vehicle_type, display_name, description, icon_name, max_passengers, is_enabled, sort_order)
VALUES
  ('MX', 'standard', 'Toro X',       'Viaje estándar',           'directions_car',  4,  false, 0),
  ('MX', 'moto',     'Toro Moto',    'Viaje en moto, económico', 'two_wheeler',     1,  false, 1),
  ('MX', 'xl',       'Toro XL',      'SUV o camioneta grande',   'airport_shuttle',  6,  false, 2),
  ('MX', 'premium',  'Toro Premium', 'Viaje premium',            'local_taxi',       4,  false, 3),
  ('MX', 'black',    'Toro Black',   'Viaje ejecutivo',          'directions_car',   4,  false, 4),
  ('MX', 'pickup',   'Toro Pickup',  'Camioneta pickup',         'local_shipping',   3,  false, 5),
  ('MX', 'bicycle',  'Toro Eco',     'Bicicleta, ecológico',     'pedal_bike',       1,  false, 6),
  ('MX', 'autobus',  'Toro Bus',     'Autobús o van grande',     'directions_bus',  20,  false, 7)
ON CONFLICT (country_code, vehicle_type) DO NOTHING;

-- 3. Seed US vehicle types (all disabled by default)
INSERT INTO vehicle_type_config (country_code, vehicle_type, display_name, description, icon_name, max_passengers, is_enabled, sort_order)
VALUES
  ('US', 'standard', 'Toro X',       'Standard ride',          'directions_car',  4,  false, 0),
  ('US', 'moto',     'Toro Moto',    'Motorcycle ride',        'two_wheeler',     1,  false, 1),
  ('US', 'xl',       'Toro XL',      'SUV or large vehicle',   'airport_shuttle',  6,  false, 2),
  ('US', 'premium',  'Toro Premium', 'Premium ride',           'local_taxi',       4,  false, 3),
  ('US', 'black',    'Toro Black',   'Black car service',      'directions_car',   4,  false, 4),
  ('US', 'pickup',   'Toro Pickup',  'Pickup truck',           'local_shipping',   3,  false, 5),
  ('US', 'bicycle',  'Toro Eco',     'Bicycle, eco-friendly',  'pedal_bike',       1,  false, 6),
  ('US', 'autobus',  'Toro Bus',     'Bus or large van',       'directions_bus',  20,  false, 7)
ON CONFLICT (country_code, vehicle_type) DO NOTHING;

-- 4. Add vehicle_type column to rides table (deliveries)
ALTER TABLE deliveries ADD COLUMN IF NOT EXISTS vehicle_type TEXT DEFAULT 'standard';

-- 5. RLS policies
ALTER TABLE vehicle_type_config ENABLE ROW LEVEL SECURITY;

-- Anyone authenticated can read (riders need to see enabled vehicle types)
CREATE POLICY "vehicle_type_config_select_authenticated"
  ON vehicle_type_config FOR SELECT
  TO authenticated
  USING (true);

-- Only service_role can modify (admin backend)
CREATE POLICY "vehicle_type_config_all_service_role"
  ON vehicle_type_config FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- 6. Enable realtime for vehicle_type_config (admin changes propagate immediately)
ALTER PUBLICATION supabase_realtime ADD TABLE vehicle_type_config;
