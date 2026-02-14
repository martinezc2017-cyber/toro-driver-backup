-- ============================================================================
-- 013: Tourism Payment System
-- Creates tables for the tourism credit/payment system where drivers and
-- organizers pay TORO weekly.
-- ============================================================================

-- Organizer credit accounts (tracks credit limit, balance, status)
CREATE TABLE IF NOT EXISTS organizer_credit_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organizer_id uuid NOT NULL REFERENCES organizers(id) ON DELETE CASCADE,
  credit_limit numeric(12,2) NOT NULL DEFAULT 50000,
  current_balance numeric(12,2) NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'blocked')),
  blocked_at timestamptz,
  blocked_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(organizer_id)
);

-- Weekly statements generated every Sunday
CREATE TABLE IF NOT EXISTS organizer_weekly_statements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organizer_id uuid NOT NULL REFERENCES organizers(id) ON DELETE CASCADE,
  week_start_date date NOT NULL,
  week_end_date date NOT NULL,
  total_events int NOT NULL DEFAULT 0,
  total_km numeric(10,2) NOT NULL DEFAULT 0,
  total_driver_cost numeric(12,2) NOT NULL DEFAULT 0,
  toro_commission_pct numeric(5,2) NOT NULL DEFAULT 18.00,
  amount_due numeric(12,2) NOT NULL DEFAULT 0,
  payment_status text NOT NULL DEFAULT 'pending' CHECK (payment_status IN ('pending', 'paid', 'overdue', 'waived')),
  paid_at timestamptz,
  admin_notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Payments submitted by organizers (proof of external payment)
CREATE TABLE IF NOT EXISTS organizer_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organizer_id uuid NOT NULL REFERENCES organizers(id) ON DELETE CASCADE,
  statement_id uuid REFERENCES organizer_weekly_statements(id),
  amount numeric(12,2) NOT NULL,
  payment_method text NOT NULL DEFAULT 'transfer',
  reference_number text,
  proof_url text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewed_by uuid,
  reviewed_at timestamptz,
  admin_notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Week reset requests: organizer/driver requests admin to clear their week
CREATE TABLE IF NOT EXISTS week_reset_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id uuid NOT NULL,
  requester_type text NOT NULL DEFAULT 'organizer' CHECK (requester_type IN ('organizer', 'driver')),
  organizer_id uuid REFERENCES organizers(id),
  statement_id uuid REFERENCES organizer_weekly_statements(id),
  amount_owed numeric(12,2) NOT NULL DEFAULT 0,
  message text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewed_by uuid,
  reviewed_at timestamptz,
  admin_notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Driver credit accounts (for drivers who are NOT organizers but owe TORO)
CREATE TABLE IF NOT EXISTS driver_credit_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id uuid NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  credit_limit numeric(12,2) NOT NULL DEFAULT 50000,
  current_balance numeric(12,2) NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'blocked')),
  blocked_at timestamptz,
  blocked_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(driver_id)
);

-- Driver weekly statements
CREATE TABLE IF NOT EXISTS driver_weekly_statements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id uuid NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  week_start_date date NOT NULL,
  week_end_date date NOT NULL,
  total_events int NOT NULL DEFAULT 0,
  total_km numeric(10,2) NOT NULL DEFAULT 0,
  total_earnings numeric(12,2) NOT NULL DEFAULT 0,
  toro_commission_pct numeric(5,2) NOT NULL DEFAULT 18.00,
  amount_due numeric(12,2) NOT NULL DEFAULT 0,
  payment_status text NOT NULL DEFAULT 'pending' CHECK (payment_status IN ('pending', 'paid', 'overdue', 'waived')),
  paid_at timestamptz,
  admin_notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_organizer_credit_accounts_organizer ON organizer_credit_accounts(organizer_id);
CREATE INDEX IF NOT EXISTS idx_organizer_weekly_statements_organizer ON organizer_weekly_statements(organizer_id);
CREATE INDEX IF NOT EXISTS idx_organizer_payments_organizer ON organizer_payments(organizer_id);
CREATE INDEX IF NOT EXISTS idx_week_reset_requests_status ON week_reset_requests(status);
CREATE INDEX IF NOT EXISTS idx_week_reset_requests_requester ON week_reset_requests(requester_id);
CREATE INDEX IF NOT EXISTS idx_driver_credit_accounts_driver ON driver_credit_accounts(driver_id);
CREATE INDEX IF NOT EXISTS idx_driver_weekly_statements_driver ON driver_weekly_statements(driver_id);

-- RLS policies
ALTER TABLE organizer_credit_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE organizer_weekly_statements ENABLE ROW LEVEL SECURITY;
ALTER TABLE organizer_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE week_reset_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE driver_credit_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE driver_weekly_statements ENABLE ROW LEVEL SECURITY;

-- Organizer credit accounts: organizer can read their own
CREATE POLICY "organizer_credit_accounts_select" ON organizer_credit_accounts
  FOR SELECT USING (
    organizer_id IN (SELECT id FROM organizers WHERE user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM drivers WHERE id = auth.uid() AND role = 'admin')
  );

-- Organizer weekly statements: organizer can read their own
CREATE POLICY "organizer_weekly_statements_select" ON organizer_weekly_statements
  FOR SELECT USING (
    organizer_id IN (SELECT id FROM organizers WHERE user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM drivers WHERE id = auth.uid() AND role = 'admin')
  );

-- Organizer payments: organizer can read and insert their own
CREATE POLICY "organizer_payments_select" ON organizer_payments
  FOR SELECT USING (
    organizer_id IN (SELECT id FROM organizers WHERE user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM drivers WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY "organizer_payments_insert" ON organizer_payments
  FOR INSERT WITH CHECK (
    organizer_id IN (SELECT id FROM organizers WHERE user_id = auth.uid())
  );

-- Week reset requests: requester can read/insert their own, admin can read/update all
CREATE POLICY "week_reset_requests_select" ON week_reset_requests
  FOR SELECT USING (
    requester_id = auth.uid()
    OR EXISTS (SELECT 1 FROM drivers WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY "week_reset_requests_insert" ON week_reset_requests
  FOR INSERT WITH CHECK (
    requester_id = auth.uid()
  );

CREATE POLICY "week_reset_requests_update" ON week_reset_requests
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM drivers WHERE id = auth.uid() AND role = 'admin')
  );

-- Driver credit accounts: driver can read their own
CREATE POLICY "driver_credit_accounts_select" ON driver_credit_accounts
  FOR SELECT USING (
    driver_id = auth.uid()
    OR EXISTS (SELECT 1 FROM drivers WHERE id = auth.uid() AND role = 'admin')
  );

-- Driver weekly statements: driver can read their own
CREATE POLICY "driver_weekly_statements_select" ON driver_weekly_statements
  FOR SELECT USING (
    driver_id = auth.uid()
    OR EXISTS (SELECT 1 FROM drivers WHERE id = auth.uid() AND role = 'admin')
  );

-- Admin full access policies
CREATE POLICY "admin_credit_accounts_all" ON organizer_credit_accounts
  FOR ALL USING (EXISTS (SELECT 1 FROM drivers WHERE id = auth.uid() AND role = 'admin'));

CREATE POLICY "admin_weekly_statements_all" ON organizer_weekly_statements
  FOR ALL USING (EXISTS (SELECT 1 FROM drivers WHERE id = auth.uid() AND role = 'admin'));

CREATE POLICY "admin_payments_update" ON organizer_payments
  FOR UPDATE USING (EXISTS (SELECT 1 FROM drivers WHERE id = auth.uid() AND role = 'admin'));

CREATE POLICY "admin_driver_credit_all" ON driver_credit_accounts
  FOR ALL USING (EXISTS (SELECT 1 FROM drivers WHERE id = auth.uid() AND role = 'admin'));

CREATE POLICY "admin_driver_statements_all" ON driver_weekly_statements
  FOR ALL USING (EXISTS (SELECT 1 FROM drivers WHERE id = auth.uid() AND role = 'admin'));
