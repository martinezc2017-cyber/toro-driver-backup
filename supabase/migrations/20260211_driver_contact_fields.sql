-- Add driver credential / business card contact fields
-- Same fields as organizers: contact_email, contact_phone, contact_facebook
-- business_card_url already exists in some environments

ALTER TABLE drivers ADD COLUMN IF NOT EXISTS contact_email text;
ALTER TABLE drivers ADD COLUMN IF NOT EXISTS contact_phone text;
ALTER TABLE drivers ADD COLUMN IF NOT EXISTS contact_facebook text;
ALTER TABLE drivers ADD COLUMN IF NOT EXISTS business_card_url text;

-- Create storage bucket for driver credentials (logos, business cards)
INSERT INTO storage.buckets (id, name, public)
VALUES ('driver-credentials', 'driver-credentials', true)
ON CONFLICT (id) DO NOTHING;

-- Allow authenticated users to upload to their own folder
CREATE POLICY IF NOT EXISTS "drivers_upload_own_credentials"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'driver-credentials'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Allow public read access
CREATE POLICY IF NOT EXISTS "drivers_credentials_public_read"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'driver-credentials');
