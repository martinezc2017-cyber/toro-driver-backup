-- Create driver_sessions table for tracking online time
CREATE TABLE IF NOT EXISTS driver_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ended_at TIMESTAMPTZ,
  duration_minutes DOUBLE PRECISION GENERATED ALWAYS AS (
    CASE
      WHEN ended_at IS NOT NULL THEN EXTRACT(EPOCH FROM (ended_at - started_at)) / 60
      ELSE NULL
    END
  ) STORED,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for fast queries by driver and date
CREATE INDEX IF NOT EXISTS idx_driver_sessions_driver_id ON driver_sessions(driver_id);
CREATE INDEX IF NOT EXISTS idx_driver_sessions_started_at ON driver_sessions(started_at);
CREATE INDEX IF NOT EXISTS idx_driver_sessions_driver_week ON driver_sessions(driver_id, started_at);

-- Enable RLS
ALTER TABLE driver_sessions ENABLE ROW LEVEL SECURITY;

-- Policy: Drivers can read their own sessions
CREATE POLICY "Drivers can view own sessions" ON driver_sessions
  FOR SELECT USING (auth.uid() = driver_id);

-- Policy: Drivers can insert their own sessions
CREATE POLICY "Drivers can insert own sessions" ON driver_sessions
  FOR INSERT WITH CHECK (auth.uid() = driver_id);

-- Policy: Drivers can update their own sessions
CREATE POLICY "Drivers can update own sessions" ON driver_sessions
  FOR UPDATE USING (auth.uid() = driver_id);

-- Function to get weekly online minutes for a driver
CREATE OR REPLACE FUNCTION get_driver_weekly_online_minutes(p_driver_id UUID)
RETURNS DOUBLE PRECISION AS $$
DECLARE
  total_minutes DOUBLE PRECISION;
  week_start TIMESTAMPTZ;
BEGIN
  -- Get start of current week (Monday)
  week_start := date_trunc('week', NOW());

  SELECT COALESCE(SUM(
    CASE
      WHEN ended_at IS NOT NULL THEN EXTRACT(EPOCH FROM (ended_at - started_at)) / 60
      ELSE EXTRACT(EPOCH FROM (NOW() - started_at)) / 60  -- For active session
    END
  ), 0)
  INTO total_minutes
  FROM driver_sessions
  WHERE driver_id = p_driver_id
    AND started_at >= week_start;

  RETURN total_minutes;
END;
$$ LANGUAGE plpgsql;
