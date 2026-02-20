-- ============================================================================
-- Migration: Add trial mode columns to drivers table
-- Date: 2026-02-19
-- Purpose: Track driver trial mode acceptance with audit trail
-- ============================================================================

-- Trial mode acceptance flag
ALTER TABLE drivers ADD COLUMN IF NOT EXISTS trial_mode_accepted BOOLEAN DEFAULT FALSE;

-- Timestamp of when trial mode was accepted
ALTER TABLE drivers ADD COLUMN IF NOT EXISTS trial_accepted_at TIMESTAMPTZ;
