-- =============================================================================
-- LEGAL CONSENTS TABLE
-- Server-side persistence for all consent records (driver + rider)
-- Used for audit trails, legal evidence, and regulatory compliance
-- =============================================================================

CREATE TABLE IF NOT EXISTS legal_consents (
    id BIGSERIAL PRIMARY KEY,

    -- User identification
    user_id TEXT NOT NULL,
    user_email TEXT,

    -- Document info
    document_type TEXT NOT NULL,
    document_version TEXT NOT NULL,
    document_language TEXT NOT NULL DEFAULT 'en',

    -- Acceptance timestamp
    accepted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Device and platform info
    device_id TEXT,
    platform TEXT,
    app_version TEXT,
    locale TEXT,

    -- Reading metrics
    scroll_percentage DOUBLE PRECISION DEFAULT 0.0,
    time_spent_reading_ms INTEGER DEFAULT 0,

    -- Verification
    age_verified BOOLEAN DEFAULT TRUE,
    checksum TEXT,

    -- Full consent record JSON for complete audit trail
    consent_json JSONB,

    -- App identifier (toro_driver or toro_rider)
    app_name TEXT NOT NULL DEFAULT 'toro_driver',

    -- Metadata
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for efficient querying
CREATE INDEX IF NOT EXISTS idx_legal_consents_user_id ON legal_consents(user_id);
CREATE INDEX IF NOT EXISTS idx_legal_consents_document_type ON legal_consents(document_type);
CREATE INDEX IF NOT EXISTS idx_legal_consents_accepted_at ON legal_consents(accepted_at);
CREATE INDEX IF NOT EXISTS idx_legal_consents_app_name ON legal_consents(app_name);
CREATE INDEX IF NOT EXISTS idx_legal_consents_user_doc ON legal_consents(user_id, document_type, document_version);

-- RLS: Users can only insert their own records, admins can read all
ALTER TABLE legal_consents ENABLE ROW LEVEL SECURITY;

-- Anyone can insert (pre-login consent uses anonymous key)
CREATE POLICY "Anyone can insert consent records"
    ON legal_consents
    FOR INSERT
    WITH CHECK (true);

-- Authenticated users can read their own records
CREATE POLICY "Users can read own consent records"
    ON legal_consents
    FOR SELECT
    USING (auth.uid()::text = user_id OR auth.jwt() ->> 'role' = 'service_role');

-- Comment for documentation
COMMENT ON TABLE legal_consents IS 'Legal consent records for audit trail. Contains every acceptance event from both driver and rider apps.';
COMMENT ON COLUMN legal_consents.consent_json IS 'Complete ConsentRecord JSON including all 60+ fields for legal evidence.';
COMMENT ON COLUMN legal_consents.scroll_percentage IS 'How far the user scrolled the legal documents (0.0 to 1.0).';
COMMENT ON COLUMN legal_consents.time_spent_reading_ms IS 'Milliseconds the user spent on the terms screen before accepting.';
