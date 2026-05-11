-- Migration: Create bug_reports table for in-app bug reporting

CREATE TABLE IF NOT EXISTS bug_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  description TEXT NOT NULL,
  screen_name TEXT NOT NULL,
  screenshot_url TEXT,
  severity TEXT NOT NULL DEFAULT 'medium' CHECK (severity IN ('low', 'medium', 'high', 'critical')),
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'resolved', 'wont_fix', 'duplicate')),
  device_info JSONB,
  extra_data JSONB,
  admin_notes TEXT,
  resolved_at TIMESTAMPTZ,
  resolved_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_bug_reports_user_id ON bug_reports(user_id);
CREATE INDEX IF NOT EXISTS idx_bug_reports_status ON bug_reports(status);
CREATE INDEX IF NOT EXISTS idx_bug_reports_severity ON bug_reports(severity);
CREATE INDEX IF NOT EXISTS idx_bug_reports_created_at ON bug_reports(created_at DESC);

-- RLS
ALTER TABLE bug_reports ENABLE ROW LEVEL SECURITY;

-- Anyone can insert their own bug reports
CREATE POLICY "Users can submit bug reports"
  ON bug_reports
  FOR INSERT
  WITH CHECK (true);

-- Users can view their own reports
CREATE POLICY "Users can view own reports"
  ON bug_reports
  FOR SELECT
  USING (user_id = auth.uid()::text OR auth.jwt() ->> 'role' = 'service_role');

-- Only service_role can update/delete
CREATE POLICY "Only admin can update reports"
  ON bug_reports
  FOR UPDATE
  USING (auth.jwt() ->> 'role' = 'service_role');

CREATE POLICY "Only admin can delete reports"
  ON bug_reports
  FOR DELETE
  USING (auth.jwt() ->> 'role' = 'service_role');

-- Storage bucket for screenshots
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'bug-reports',
  'bug-reports',
  true,
  5242880, -- 5MB max
  ARRAY['image/png', 'image/jpeg', 'image/jpg']
)
ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = 5242880,
  allowed_mime_types = ARRAY['image/png', 'image/jpeg', 'image/jpg'];

-- Storage policies
CREATE POLICY "Users can upload bug screenshots"
  ON storage.objects
  FOR INSERT
  WITH CHECK (bucket_id = 'bug-reports');

CREATE POLICY "Bug screenshots are public readable"
  ON storage.objects
  FOR SELECT
  USING (bucket_id = 'bug-reports');

-- Updated_at trigger
CREATE OR REPLACE FUNCTION update_bug_reports_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_bug_reports_updated_at
  BEFORE UPDATE ON bug_reports
  FOR EACH ROW
  EXECUTE FUNCTION update_bug_reports_updated_at();
