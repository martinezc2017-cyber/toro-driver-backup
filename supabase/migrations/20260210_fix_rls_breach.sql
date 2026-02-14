-- ============================================================================
-- Fix RLS breach: public_tourism_events view exposed to anon users
-- 2026-02-10
-- ============================================================================
-- The view was GRANT SELECT to anon, authenticated — this exposes
-- organizer phone/email and driver phone to unauthenticated users.
-- Only authenticated users should see event details.

REVOKE SELECT ON public_tourism_events FROM anon;

-- Ensure authenticated users still have access
GRANT SELECT ON public_tourism_events TO authenticated;
