-- ============================================================================
-- TORO - MEXICO SUPPORT: Driver Documents for Mexico
-- Migration 005
-- ============================================================================

-- ============================================================================
-- DOCUMENT TYPES FOR MEXICO (extend existing enum)
-- ============================================================================

-- Add new document types for Mexico
DO $$
BEGIN
    -- Check if the enum value exists before adding
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'ine' AND enumtypid = 'document_type'::regtype) THEN
        ALTER TYPE document_type ADD VALUE 'ine';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'licenciaE1' AND enumtypid = 'document_type'::regtype) THEN
        ALTER TYPE document_type ADD VALUE 'licenciaE1';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'tarjeton' AND enumtypid = 'document_type'::regtype) THEN
        ALTER TYPE document_type ADD VALUE 'tarjeton';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'constanciaSemovi' AND enumtypid = 'document_type'::regtype) THEN
        ALTER TYPE document_type ADD VALUE 'constanciaSemovi';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'constanciaVehicular' AND enumtypid = 'document_type'::regtype) THEN
        ALTER TYPE document_type ADD VALUE 'constanciaVehicular';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'seguroERT' AND enumtypid = 'document_type'::regtype) THEN
        ALTER TYPE document_type ADD VALUE 'seguroERT';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'rfcConstancia' AND enumtypid = 'document_type'::regtype) THEN
        ALTER TYPE document_type ADD VALUE 'rfcConstancia';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'comprobanteDomicilio' AND enumtypid = 'document_type'::regtype) THEN
        ALTER TYPE document_type ADD VALUE 'comprobanteDomicilio';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'cartaNoAntecedentes' AND enumtypid = 'document_type'::regtype) THEN
        ALTER TYPE document_type ADD VALUE 'cartaNoAntecedentes';
    END IF;
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- ============================================================================
-- DRIVER DOCUMENTS MEXICO TABLE (Specific tracking for MX documents)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.driver_documents_mx (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    driver_id UUID NOT NULL REFERENCES public.drivers(id) ON DELETE CASCADE,

    -- Document info
    document_type TEXT NOT NULL, -- 'ine', 'licencia_e1', 'tarjeton', 'rfc', 'seguro_ert', etc.
    document_number TEXT, -- Numero de documento

    -- Dates
    issue_date DATE,
    expiry_date DATE,

    -- Files
    front_file_url TEXT,
    back_file_url TEXT,

    -- Verification
    verification_status TEXT DEFAULT 'pending', -- 'pending', 'approved', 'rejected'
    rejection_reason TEXT,
    verified_at TIMESTAMPTZ,
    verified_by UUID, -- Admin who verified

    -- Metadata
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_driver_docs_mx_driver ON public.driver_documents_mx(driver_id);
CREATE INDEX IF NOT EXISTS idx_driver_docs_mx_type ON public.driver_documents_mx(document_type);
CREATE INDEX IF NOT EXISTS idx_driver_docs_mx_status ON public.driver_documents_mx(verification_status);
CREATE INDEX IF NOT EXISTS idx_driver_docs_mx_expiry ON public.driver_documents_mx(expiry_date);

-- Unique constraint: one document per type per driver
CREATE UNIQUE INDEX IF NOT EXISTS idx_driver_docs_mx_unique
ON public.driver_documents_mx(driver_id, document_type);

-- RLS
ALTER TABLE public.driver_documents_mx ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Drivers can view own MX documents" ON public.driver_documents_mx
    FOR SELECT USING (auth.uid() = driver_id);

CREATE POLICY "Drivers can insert own MX documents" ON public.driver_documents_mx
    FOR INSERT WITH CHECK (auth.uid() = driver_id);

CREATE POLICY "Drivers can update own MX documents" ON public.driver_documents_mx
    FOR UPDATE USING (auth.uid() = driver_id);

-- ============================================================================
-- DOCUMENT REQUIREMENTS BY COUNTRY
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.document_requirements (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    country_code TEXT NOT NULL REFERENCES public.countries(code),
    state_code TEXT, -- NULL means applies to all states in country
    document_type TEXT NOT NULL,
    is_required BOOLEAN DEFAULT TRUE,
    display_name TEXT NOT NULL,
    description TEXT,
    has_expiry BOOLEAN DEFAULT TRUE,
    expiry_warning_days INTEGER DEFAULT 30, -- Days before expiry to warn
    display_order INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE
);

-- Insert Mexico document requirements
INSERT INTO public.document_requirements
(country_code, state_code, document_type, is_required, display_name, description, has_expiry, display_order)
VALUES
    ('MX', NULL, 'ine', TRUE, 'INE/IFE', 'Credencial para votar vigente', TRUE, 1),
    ('MX', NULL, 'rfcConstancia', TRUE, 'Constancia RFC', 'Constancia de situación fiscal del SAT', FALSE, 2),
    ('MX', 'CDMX', 'licenciaE1', TRUE, 'Licencia E1', 'Licencia de conducir tipo E1 para CDMX', TRUE, 3),
    ('MX', 'CDMX', 'tarjeton', TRUE, 'Tarjetón de Conductor', 'Tarjetón expedido por SEMOVI', TRUE, 4),
    ('MX', 'CDMX', 'constanciaSemovi', TRUE, 'Constancia SEMOVI', 'Constancia de registro de conductor', TRUE, 5),
    ('MX', 'CDMX', 'constanciaVehicular', TRUE, 'Constancia Vehicular', 'Constancia de registro vehicular SEMOVI', TRUE, 6),
    ('MX', NULL, 'seguroERT', TRUE, 'Seguro ERT', 'Póliza de seguro para plataformas de transporte', TRUE, 7),
    ('MX', NULL, 'comprobanteDomicilio', TRUE, 'Comprobante de Domicilio', 'Recibo de servicios no mayor a 3 meses', TRUE, 8),
    ('MX', NULL, 'cartaNoAntecedentes', FALSE, 'Carta de No Antecedentes', 'Carta de no antecedentes penales', TRUE, 9),
    -- Non-CDMX states - simpler requirements
    ('MX', 'JAL', 'driverLicense', TRUE, 'Licencia de Conducir', 'Licencia tipo A o B vigente', TRUE, 3),
    ('MX', 'NL', 'driverLicense', TRUE, 'Licencia de Conducir', 'Licencia tipo A o B vigente', TRUE, 3)
ON CONFLICT DO NOTHING;

-- Insert US document requirements (existing)
INSERT INTO public.document_requirements
(country_code, state_code, document_type, is_required, display_name, description, has_expiry, display_order)
VALUES
    ('US', NULL, 'driverLicense', TRUE, 'Driver License', 'Valid driver license', TRUE, 1),
    ('US', NULL, 'vehicleInsurance', TRUE, 'Vehicle Insurance', 'Valid auto insurance', TRUE, 2),
    ('US', NULL, 'vehicleRegistration', TRUE, 'Vehicle Registration', 'Current registration', TRUE, 3),
    ('US', NULL, 'profilePhoto', TRUE, 'Profile Photo', 'Clear photo of your face', FALSE, 4)
ON CONFLICT DO NOTHING;

-- ============================================================================
-- HELPER FUNCTION: Get required documents for driver
-- ============================================================================

CREATE OR REPLACE FUNCTION get_required_documents(
    p_country_code TEXT,
    p_state_code TEXT DEFAULT NULL
)
RETURNS TABLE (
    document_type TEXT,
    display_name TEXT,
    description TEXT,
    is_required BOOLEAN,
    has_expiry BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT ON (dr.document_type)
        dr.document_type,
        dr.display_name,
        dr.description,
        dr.is_required,
        dr.has_expiry
    FROM public.document_requirements dr
    WHERE dr.country_code = p_country_code
    AND dr.is_active = TRUE
    AND (dr.state_code IS NULL OR dr.state_code = p_state_code)
    ORDER BY dr.document_type, dr.state_code NULLS LAST, dr.display_order;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- HELPER FUNCTION: Check if driver has all required documents
-- ============================================================================

CREATE OR REPLACE FUNCTION check_driver_documents_complete(p_driver_id UUID)
RETURNS TABLE (
    is_complete BOOLEAN,
    missing_documents TEXT[],
    expiring_soon TEXT[]
) AS $$
DECLARE
    v_driver public.drivers;
    v_missing TEXT[] := '{}';
    v_expiring TEXT[] := '{}';
    v_required RECORD;
BEGIN
    -- Get driver info
    SELECT * INTO v_driver FROM public.drivers WHERE id = p_driver_id;

    -- Check each required document
    FOR v_required IN
        SELECT * FROM get_required_documents(v_driver.country_code, v_driver.state_code)
        WHERE is_required = TRUE
    LOOP
        -- Check if document exists and is approved
        IF NOT EXISTS (
            SELECT 1 FROM public.driver_documents_mx
            WHERE driver_id = p_driver_id
            AND document_type = v_required.document_type
            AND verification_status = 'approved'
        ) AND NOT EXISTS (
            SELECT 1 FROM public.documents
            WHERE driver_id = p_driver_id
            AND type::TEXT = v_required.document_type
            AND status = 'approved'
        ) THEN
            v_missing := array_append(v_missing, v_required.document_type);
        END IF;

        -- Check if document is expiring soon (within 30 days)
        IF v_required.has_expiry THEN
            IF EXISTS (
                SELECT 1 FROM public.driver_documents_mx
                WHERE driver_id = p_driver_id
                AND document_type = v_required.document_type
                AND expiry_date IS NOT NULL
                AND expiry_date <= CURRENT_DATE + INTERVAL '30 days'
            ) THEN
                v_expiring := array_append(v_expiring, v_required.document_type);
            END IF;
        END IF;
    END LOOP;

    RETURN QUERY SELECT
        array_length(v_missing, 1) IS NULL OR array_length(v_missing, 1) = 0,
        v_missing,
        v_expiring;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- HELPER FUNCTION: Validate RFC format
-- ============================================================================

CREATE OR REPLACE FUNCTION validate_rfc(p_rfc TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    -- RFC persona física: 4 letras + 6 dígitos + 3 homoclave = 13 chars
    -- RFC persona moral: 3 letras + 6 dígitos + 3 homoclave = 12 chars
    IF p_rfc IS NULL OR length(p_rfc) < 12 OR length(p_rfc) > 13 THEN
        RETURN FALSE;
    END IF;

    -- Basic format validation (simplified)
    -- Real validation would check valid date, homoclave algorithm, etc.
    IF length(p_rfc) = 13 THEN
        -- Persona física: AAAA######XXX
        RETURN p_rfc ~ '^[A-ZÑ&]{4}[0-9]{6}[A-Z0-9]{3}$';
    ELSE
        -- Persona moral: AAA######XXX
        RETURN p_rfc ~ '^[A-ZÑ&]{3}[0-9]{6}[A-Z0-9]{3}$';
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- TRIGGER: Validate RFC before saving
-- ============================================================================

CREATE OR REPLACE FUNCTION validate_driver_rfc()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.rfc IS NOT NULL AND NEW.country_code = 'MX' THEN
        IF NOT validate_rfc(UPPER(NEW.rfc)) THEN
            RAISE EXCEPTION 'Invalid RFC format: %', NEW.rfc;
        END IF;
        NEW.rfc := UPPER(NEW.rfc);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_validate_driver_rfc
    BEFORE INSERT OR UPDATE OF rfc ON public.drivers
    FOR EACH ROW
    EXECUTE FUNCTION validate_driver_rfc();

-- ============================================================================
-- Realtime
-- ============================================================================

ALTER PUBLICATION supabase_realtime ADD TABLE public.driver_documents_mx;
