-- Add bid_visibility column to tourism_events
-- 'public' = any driver can see and bid
-- 'private' = only invited drivers can bid
ALTER TABLE tourism_events ADD COLUMN IF NOT EXISTS bid_visibility text DEFAULT 'public';
