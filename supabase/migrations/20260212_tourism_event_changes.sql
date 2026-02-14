-- Audit log for tourism event changes (itinerary add/remove/edit)
-- Used by admin to track organizer/driver activity for billing

CREATE TABLE IF NOT EXISTS tourism_event_changes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES tourism_events(id) ON DELETE CASCADE,
  changed_by UUID NOT NULL,
  change_type TEXT NOT NULL,
  change_summary TEXT NOT NULL,
  old_value JSONB,
  new_value JSONB,
  organizer_name TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tec_event ON tourism_event_changes(event_id, created_at DESC);

ALTER TABLE tourism_event_changes ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'tourism_event_changes' AND policyname = 'admin_all_tec') THEN
    CREATE POLICY admin_all_tec ON tourism_event_changes FOR ALL TO authenticated USING (true);
  END IF;
END $$;
