-- =============================================================================
-- GENERAL ABUSE REPORTS & INCIDENT TRACKING SYSTEM
-- For all ride types (regular rides, carpools, deliveries, tourism)
-- Supports: reports, appeals, enforcement actions, user scoring
-- =============================================================================

-- Report type enum
DO $$ BEGIN
  CREATE TYPE report_category AS ENUM (
    'sexual_misconduct',
    'harassment',
    'violence',
    'threats',
    'discrimination',
    'substance_impairment',
    'unsafe_driving',
    'fraud',
    'theft',
    'vehicle_condition',
    'route_deviation',
    'overcharging',
    'no_show',
    'cancellation_abuse',
    'other'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Report severity
DO $$ BEGIN
  CREATE TYPE report_severity AS ENUM ('low', 'medium', 'high', 'critical');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Report status
DO $$ BEGIN
  CREATE TYPE report_status AS ENUM (
    'pending',
    'under_review',
    'investigating',
    'resolved_warning',
    'resolved_suspension',
    'resolved_deactivation',
    'resolved_no_action',
    'dismissed',
    'appealed',
    'appeal_accepted',
    'appeal_denied',
    'escalated'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Reporter role
DO $$ BEGIN
  CREATE TYPE reporter_role AS ENUM ('rider', 'driver', 'admin', 'system');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Enforcement action type
DO $$ BEGIN
  CREATE TYPE enforcement_action AS ENUM (
    'warning',
    'temporary_suspension',
    'permanent_deactivation',
    'account_restriction',
    'fine',
    'no_action'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- =============================================================================
-- MAIN REPORTS TABLE
-- =============================================================================

CREATE TABLE IF NOT EXISTS abuse_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Who is reporting
    reporter_id UUID NOT NULL,
    reporter_role reporter_role NOT NULL DEFAULT 'rider',
    reporter_name TEXT,
    reporter_email TEXT,
    reporter_phone TEXT,

    -- Who is being reported
    reported_user_id UUID,
    reported_user_role reporter_role,
    reported_user_name TEXT,

    -- Context
    ride_id UUID,
    delivery_id UUID,
    event_id UUID,
    ride_type TEXT, -- 'ride', 'carpool', 'delivery', 'tourism', 'bus'

    -- Report details
    category report_category NOT NULL,
    severity report_severity NOT NULL DEFAULT 'medium',
    status report_status NOT NULL DEFAULT 'pending',
    title TEXT,
    description TEXT NOT NULL,

    -- Evidence
    evidence_urls TEXT[] DEFAULT '{}',
    gps_data JSONB,
    has_audio_evidence BOOLEAN DEFAULT FALSE,
    has_video_evidence BOOLEAN DEFAULT FALSE,

    -- Location at time of incident
    incident_latitude DOUBLE PRECISION,
    incident_longitude DOUBLE PRECISION,
    incident_address TEXT,
    incident_at TIMESTAMPTZ,

    -- Resolution
    assigned_admin_id UUID,
    admin_notes TEXT,
    resolution_summary TEXT,
    resolved_by UUID,
    resolved_at TIMESTAMPTZ,
    enforcement enforcement_action,

    -- Appeal
    appeal_id UUID,
    has_appeal BOOLEAN DEFAULT FALSE,

    -- User scoring impact
    user_score_impact INTEGER DEFAULT 0, -- negative = bad, 0 = neutral

    -- Metadata
    app_name TEXT NOT NULL DEFAULT 'toro_rider', -- which app reported
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- APPEALS TABLE
-- =============================================================================

CREATE TABLE IF NOT EXISTS report_appeals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Link to original report
    report_id UUID NOT NULL REFERENCES abuse_reports(id) ON DELETE CASCADE,

    -- Who is appealing (the reported user)
    appellant_id UUID NOT NULL,
    appellant_role reporter_role NOT NULL,

    -- Appeal details
    reason TEXT NOT NULL,
    evidence_urls TEXT[] DEFAULT '{}',
    counter_description TEXT,

    -- Status
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'under_review', 'accepted', 'denied')),
    reviewed_by UUID,
    reviewed_at TIMESTAMPTZ,
    review_notes TEXT,

    -- Metadata
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- ENFORCEMENT ACTIONS LOG
-- =============================================================================

CREATE TABLE IF NOT EXISTS enforcement_actions_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Who is affected
    user_id UUID NOT NULL,
    user_role reporter_role NOT NULL,

    -- Action taken
    action enforcement_action NOT NULL,
    reason TEXT NOT NULL,
    report_id UUID REFERENCES abuse_reports(id),

    -- Duration (for temporary suspensions)
    suspension_start TIMESTAMPTZ,
    suspension_end TIMESTAMPTZ,
    is_permanent BOOLEAN DEFAULT FALSE,

    -- Admin who took action
    admin_id UUID,
    admin_notes TEXT,

    -- Metadata
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- USER SAFETY SCORE
-- Tracks cumulative safety/trust score per user
-- =============================================================================

CREATE TABLE IF NOT EXISTS user_safety_scores (
    user_id UUID PRIMARY KEY,
    role reporter_role NOT NULL DEFAULT 'rider',
    score INTEGER NOT NULL DEFAULT 100, -- starts at 100, goes down with incidents
    total_reports_filed INTEGER DEFAULT 0,
    total_reports_received INTEGER DEFAULT 0,
    total_reports_dismissed INTEGER DEFAULT 0,
    total_warnings INTEGER DEFAULT 0,
    total_suspensions INTEGER DEFAULT 0,
    is_flagged BOOLEAN DEFAULT FALSE,
    flag_reason TEXT,
    last_incident_at TIMESTAMPTZ,
    last_reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- REPORT STATUS HISTORY (Audit Trail)
-- =============================================================================

CREATE TABLE IF NOT EXISTS report_status_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id UUID NOT NULL REFERENCES abuse_reports(id) ON DELETE CASCADE,
    old_status report_status,
    new_status report_status NOT NULL,
    changed_by UUID,
    changed_by_role reporter_role DEFAULT 'admin',
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- INDEXES
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_abuse_reports_reporter ON abuse_reports(reporter_id);
CREATE INDEX IF NOT EXISTS idx_abuse_reports_reported ON abuse_reports(reported_user_id);
CREATE INDEX IF NOT EXISTS idx_abuse_reports_status ON abuse_reports(status);
CREATE INDEX IF NOT EXISTS idx_abuse_reports_severity ON abuse_reports(severity);
CREATE INDEX IF NOT EXISTS idx_abuse_reports_category ON abuse_reports(category);
CREATE INDEX IF NOT EXISTS idx_abuse_reports_ride ON abuse_reports(ride_id);
CREATE INDEX IF NOT EXISTS idx_abuse_reports_created ON abuse_reports(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_abuse_reports_app ON abuse_reports(app_name);

CREATE INDEX IF NOT EXISTS idx_appeals_report ON report_appeals(report_id);
CREATE INDEX IF NOT EXISTS idx_appeals_appellant ON report_appeals(appellant_id);
CREATE INDEX IF NOT EXISTS idx_appeals_status ON report_appeals(status);

CREATE INDEX IF NOT EXISTS idx_enforcement_user ON enforcement_actions_log(user_id);
CREATE INDEX IF NOT EXISTS idx_enforcement_action ON enforcement_actions_log(action);

CREATE INDEX IF NOT EXISTS idx_safety_score ON user_safety_scores(score);
CREATE INDEX IF NOT EXISTS idx_safety_flagged ON user_safety_scores(is_flagged) WHERE is_flagged = TRUE;

CREATE INDEX IF NOT EXISTS idx_status_history_report ON report_status_history(report_id);

-- =============================================================================
-- ROW LEVEL SECURITY
-- =============================================================================

ALTER TABLE abuse_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE report_appeals ENABLE ROW LEVEL SECURITY;
ALTER TABLE enforcement_actions_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_safety_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE report_status_history ENABLE ROW LEVEL SECURITY;

-- Anyone can submit a report
CREATE POLICY "Anyone can create abuse reports"
    ON abuse_reports FOR INSERT WITH CHECK (true);

-- Users can view their own reports (filed or received)
CREATE POLICY "Users see own reports"
    ON abuse_reports FOR SELECT
    USING (
        auth.uid()::text = reporter_id::text
        OR auth.uid()::text = reported_user_id::text
        OR auth.jwt() ->> 'role' = 'service_role'
    );

-- Only admins/service_role can update reports
CREATE POLICY "Admins can update reports"
    ON abuse_reports FOR UPDATE
    USING (auth.jwt() ->> 'role' = 'service_role');

-- Appeals: reported user can create, both parties can view
CREATE POLICY "Reported users can appeal"
    ON report_appeals FOR INSERT
    WITH CHECK (auth.uid()::text = appellant_id::text);

CREATE POLICY "Parties can view appeals"
    ON report_appeals FOR SELECT
    USING (
        auth.uid()::text = appellant_id::text
        OR auth.jwt() ->> 'role' = 'service_role'
    );

-- Enforcement log: service_role only for insert, user can view own
CREATE POLICY "Service role manages enforcement"
    ON enforcement_actions_log FOR INSERT
    WITH CHECK (auth.jwt() ->> 'role' = 'service_role');

CREATE POLICY "Users see own enforcement"
    ON enforcement_actions_log FOR SELECT
    USING (
        auth.uid()::text = user_id::text
        OR auth.jwt() ->> 'role' = 'service_role'
    );

-- Safety scores: service_role manages, user can view own
CREATE POLICY "Users see own safety score"
    ON user_safety_scores FOR SELECT
    USING (
        auth.uid()::text = user_id::text
        OR auth.jwt() ->> 'role' = 'service_role'
    );

CREATE POLICY "Service role manages scores"
    ON user_safety_scores FOR ALL
    USING (auth.jwt() ->> 'role' = 'service_role');

-- Status history: service_role manages, parties can view
CREATE POLICY "Parties can view status history"
    ON report_status_history FOR SELECT
    USING (auth.jwt() ->> 'role' = 'service_role');

CREATE POLICY "Service role logs status changes"
    ON report_status_history FOR INSERT
    WITH CHECK (auth.jwt() ->> 'role' = 'service_role');

-- =============================================================================
-- ADMIN VIEWS
-- =============================================================================

CREATE OR REPLACE VIEW v_admin_all_reports AS
SELECT
    ar.*,
    ra.id AS appeal_id_ref,
    ra.status AS appeal_status,
    ra.reason AS appeal_reason,
    ra.created_at AS appeal_created_at,
    uss_reporter.score AS reporter_safety_score,
    uss_reported.score AS reported_user_safety_score,
    uss_reported.total_reports_received AS reported_total_reports,
    uss_reported.is_flagged AS reported_is_flagged
FROM abuse_reports ar
LEFT JOIN report_appeals ra ON ra.report_id = ar.id AND ra.status != 'denied'
LEFT JOIN user_safety_scores uss_reporter ON uss_reporter.user_id = ar.reporter_id
LEFT JOIN user_safety_scores uss_reported ON uss_reported.user_id = ar.reported_user_id
ORDER BY
    CASE ar.severity
        WHEN 'critical' THEN 1
        WHEN 'high' THEN 2
        WHEN 'medium' THEN 3
        WHEN 'low' THEN 4
    END,
    ar.created_at DESC;

-- =============================================================================
-- FUNCTIONS
-- =============================================================================

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION fn_update_abuse_report_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_abuse_reports_updated
    BEFORE UPDATE ON abuse_reports
    FOR EACH ROW EXECUTE FUNCTION fn_update_abuse_report_timestamp();

CREATE TRIGGER trg_appeals_updated
    BEFORE UPDATE ON report_appeals
    FOR EACH ROW EXECUTE FUNCTION fn_update_abuse_report_timestamp();

CREATE TRIGGER trg_safety_scores_updated
    BEFORE UPDATE ON user_safety_scores
    FOR EACH ROW EXECUTE FUNCTION fn_update_abuse_report_timestamp();

-- Auto-flag users with low safety scores
CREATE OR REPLACE FUNCTION fn_auto_flag_user()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.score <= 50 AND NOT NEW.is_flagged THEN
        NEW.is_flagged = TRUE;
        NEW.flag_reason = 'Auto-flagged: safety score below 50';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_auto_flag_user
    BEFORE UPDATE ON user_safety_scores
    FOR EACH ROW EXECUTE FUNCTION fn_auto_flag_user();

-- Log status changes automatically
CREATE OR REPLACE FUNCTION fn_log_report_status_change()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO report_status_history (report_id, old_status, new_status, notes)
        VALUES (NEW.id, OLD.status, NEW.status, NEW.admin_notes);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_log_status_change
    AFTER UPDATE ON abuse_reports
    FOR EACH ROW EXECUTE FUNCTION fn_log_report_status_change();

-- Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE abuse_reports;
ALTER PUBLICATION supabase_realtime ADD TABLE report_appeals;

-- =============================================================================
-- COMMENTS
-- =============================================================================

COMMENT ON TABLE abuse_reports IS 'General abuse/incident reports from any ride type. Supports rider-to-driver and driver-to-rider reports.';
COMMENT ON TABLE report_appeals IS 'Appeals submitted by reported users to contest abuse reports.';
COMMENT ON TABLE enforcement_actions_log IS 'Log of all enforcement actions (warnings, suspensions, deactivations) taken against users.';
COMMENT ON TABLE user_safety_scores IS 'Cumulative safety/trust score per user. Starts at 100, decreases with incidents.';
COMMENT ON TABLE report_status_history IS 'Audit trail of all status changes on abuse reports.';
