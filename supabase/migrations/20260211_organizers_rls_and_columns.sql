-- Fix organizers table: add missing columns and RLS policies for profile editing

-- Ensure all profile columns exist
ALTER TABLE organizers ADD COLUMN IF NOT EXISTS company_name text;
ALTER TABLE organizers ADD COLUMN IF NOT EXISTS contact_phone text;
ALTER TABLE organizers ADD COLUMN IF NOT EXISTS contact_email text;
ALTER TABLE organizers ADD COLUMN IF NOT EXISTS website text;
ALTER TABLE organizers ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE organizers ADD COLUMN IF NOT EXISTS social_media jsonb DEFAULT '{}'::jsonb;
ALTER TABLE organizers ADD COLUMN IF NOT EXISTS company_logo_url text;
ALTER TABLE organizers ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

-- Enable RLS (idempotent)
ALTER TABLE organizers ENABLE ROW LEVEL SECURITY;

-- SELECT: users can read their own organizer profile
CREATE POLICY IF NOT EXISTS "users_read_own_organizer"
  ON organizers FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- UPDATE: users can update their own organizer profile
CREATE POLICY IF NOT EXISTS "users_update_own_organizer"
  ON organizers FOR UPDATE TO authenticated
  USING (user_id = auth.uid());

-- INSERT: authenticated users can create their own organizer profile
CREATE POLICY IF NOT EXISTS "users_insert_own_organizer"
  ON organizers FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

-- Allow other authenticated users to read organizer profiles (for event display)
CREATE POLICY IF NOT EXISTS "authenticated_read_organizers"
  ON organizers FOR SELECT TO authenticated
  USING (true);
