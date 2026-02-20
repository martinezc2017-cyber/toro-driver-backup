-- ============================================================================
-- Migration: Add agreement/contract columns to organizers table
-- Date: 2026-02-19
-- Purpose: Track organizer platform agreement signing with full audit trail
-- ============================================================================

-- Agreement audit columns (same pattern as drivers table)
ALTER TABLE organizers ADD COLUMN IF NOT EXISTS agreement_signed BOOLEAN DEFAULT FALSE;
ALTER TABLE organizers ADD COLUMN IF NOT EXISTS agreement_signed_at TIMESTAMPTZ;
ALTER TABLE organizers ADD COLUMN IF NOT EXISTS agreement_ip_address TEXT;
ALTER TABLE organizers ADD COLUMN IF NOT EXISTS agreement_device_info TEXT;
ALTER TABLE organizers ADD COLUMN IF NOT EXISTS agreement_user_agent TEXT;
ALTER TABLE organizers ADD COLUMN IF NOT EXISTS agreement_latitude DOUBLE PRECISION;
ALTER TABLE organizers ADD COLUMN IF NOT EXISTS agreement_longitude DOUBLE PRECISION;
ALTER TABLE organizers ADD COLUMN IF NOT EXISTS agreement_app_version TEXT;
ALTER TABLE organizers ADD COLUMN IF NOT EXISTS agreement_document_hash TEXT;
ALTER TABLE organizers ADD COLUMN IF NOT EXISTS agreement_session_id TEXT;
ALTER TABLE organizers ADD COLUMN IF NOT EXISTS agreement_timezone TEXT;
ALTER TABLE organizers ADD COLUMN IF NOT EXISTS agreement_country TEXT;
ALTER TABLE organizers ADD COLUMN IF NOT EXISTS agreement_state TEXT;
