-- ============================================================================
-- TOP DRIVER BONUSES - Weekly rewards for top-ranked QR drivers per state
-- ============================================================================
-- Admins configure bonus amounts per rank position per state.
-- Every Monday, the system (or admin) awards bonuses to top drivers.
--
-- Example config:
--   rank 1 → $500 MXN / $20 USD
--   rank 2 → $300 MXN / $12 USD
--   rank 3 → $200 MXN / $8 USD
-- ============================================================================

-- Configuration table: admin sets bonus amounts per state
CREATE TABLE IF NOT EXISTS top_driver_bonus_config (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  country_code text NOT NULL DEFAULT 'MX',
  state_code text NOT NULL,
  rank_position integer NOT NULL CHECK (rank_position BETWEEN 1 AND 10),
  bonus_amount numeric NOT NULL DEFAULT 0,
  currency text NOT NULL DEFAULT 'MXN',
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE (country_code, state_code, rank_position)
);

-- Awards table: tracks bonuses actually awarded to drivers
CREATE TABLE IF NOT EXISTS top_driver_bonus_awards (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  driver_id uuid NOT NULL REFERENCES drivers(id),
  country_code text NOT NULL DEFAULT 'MX',
  state_code text NOT NULL,
  rank_position integer NOT NULL,
  bonus_amount numeric NOT NULL,
  currency text NOT NULL DEFAULT 'MXN',
  week_start date NOT NULL,
  qr_level integer NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'pending', -- 'pending', 'paid', 'cancelled'
  paid_at timestamptz,
  created_at timestamptz DEFAULT now(),
  UNIQUE (driver_id, week_start)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_bonus_config_state
ON top_driver_bonus_config(country_code, state_code) WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_bonus_awards_driver
ON top_driver_bonus_awards(driver_id, week_start);

CREATE INDEX IF NOT EXISTS idx_bonus_awards_week
ON top_driver_bonus_awards(week_start, state_code);

-- RLS
ALTER TABLE top_driver_bonus_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE top_driver_bonus_awards ENABLE ROW LEVEL SECURITY;

-- Admin can read/write config
CREATE POLICY "Admin full access to bonus config"
ON top_driver_bonus_config FOR ALL
USING (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin', 'super_admin'))
);

-- Admin can read/write awards; drivers can read their own
CREATE POLICY "Admin full access to bonus awards"
ON top_driver_bonus_awards FOR ALL
USING (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin', 'super_admin'))
);

CREATE POLICY "Drivers can read own bonus awards"
ON top_driver_bonus_awards FOR SELECT
USING (driver_id = auth.uid());
