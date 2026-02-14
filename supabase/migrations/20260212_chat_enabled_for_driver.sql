-- Add chat_enabled_for_driver column to tourism_events
-- Organizer can toggle this to hide/show chat for the assigned driver
ALTER TABLE tourism_events ADD COLUMN IF NOT EXISTS chat_enabled_for_driver boolean DEFAULT true;
COMMENT ON COLUMN tourism_events.chat_enabled_for_driver IS 'Organizer can disable chat visibility for driver';
