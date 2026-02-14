-- ============================================================================
-- TORO - MEXICO SUPPORT: CFDI Invoicing
-- Migration 007
-- ============================================================================

-- ============================================================================
-- CFDI INVOICES TABLE
-- Tracks all CFDI invoices generated for riders
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.cfdi_invoices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Transaction reference
    ride_id UUID REFERENCES public.rides(id) ON DELETE SET NULL,
    delivery_id UUID REFERENCES public.package_deliveries(id) ON DELETE SET NULL,

    -- Emisor (Platform)
    emisor_rfc TEXT NOT NULL,
    emisor_nombre TEXT NOT NULL,
    emisor_regimen TEXT NOT NULL, -- Régimen fiscal

    -- Receptor (Rider)
    rider_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    receptor_rfc TEXT NOT NULL,
    receptor_nombre TEXT NOT NULL,
    receptor_regimen TEXT NOT NULL, -- Régimen fiscal del receptor
    receptor_codigo_postal TEXT NOT NULL, -- CP para lugar de expedición
    receptor_uso_cfdi TEXT NOT NULL, -- G03, S01, etc.

    -- Invoice details
    serie TEXT,
    folio TEXT,
    uuid_fiscal TEXT UNIQUE, -- UUID del SAT (timbre fiscal)
    fecha_emision TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    fecha_timbrado TIMESTAMPTZ,

    -- Amounts
    subtotal DECIMAL(12,2) NOT NULL,
    iva_rate DECIMAL(5,4) NOT NULL DEFAULT 0.16, -- 16%
    iva_amount DECIMAL(12,2) NOT NULL,
    total DECIMAL(12,2) NOT NULL,
    currency TEXT NOT NULL DEFAULT 'MXN',

    -- Conceptos (stored as JSONB for flexibility)
    conceptos JSONB NOT NULL DEFAULT '[]',

    -- Files
    xml_url TEXT,
    pdf_url TEXT,

    -- Status
    status TEXT NOT NULL DEFAULT 'pending', -- 'pending', 'timbrado', 'cancelled', 'error'
    cancellation_reason TEXT,
    cancelled_at TIMESTAMPTZ,

    -- PAC info
    pac_provider TEXT, -- 'facturama', 'sw_sapien', etc.
    pac_response JSONB,

    -- Error tracking
    error_message TEXT,
    retry_count INTEGER DEFAULT 0,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_cfdi_ride ON public.cfdi_invoices(ride_id) WHERE ride_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cfdi_delivery ON public.cfdi_invoices(delivery_id) WHERE delivery_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cfdi_rider ON public.cfdi_invoices(rider_id);
CREATE INDEX IF NOT EXISTS idx_cfdi_receptor_rfc ON public.cfdi_invoices(receptor_rfc);
CREATE INDEX IF NOT EXISTS idx_cfdi_uuid ON public.cfdi_invoices(uuid_fiscal) WHERE uuid_fiscal IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cfdi_status ON public.cfdi_invoices(status);
CREATE INDEX IF NOT EXISTS idx_cfdi_fecha ON public.cfdi_invoices(fecha_emision DESC);

-- RLS
ALTER TABLE public.cfdi_invoices ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Riders can view own invoices" ON public.cfdi_invoices
    FOR SELECT USING (auth.uid() = rider_id);

-- ============================================================================
-- CFDI CATALOG: Uso CFDI
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.cfdi_uso_catalog (
    clave TEXT PRIMARY KEY,
    descripcion TEXT NOT NULL,
    aplica_fisica BOOLEAN DEFAULT TRUE,
    aplica_moral BOOLEAN DEFAULT TRUE,
    is_active BOOLEAN DEFAULT TRUE
);

INSERT INTO public.cfdi_uso_catalog (clave, descripcion, aplica_fisica, aplica_moral) VALUES
    ('G01', 'Adquisición de mercancías', TRUE, TRUE),
    ('G02', 'Devoluciones, descuentos o bonificaciones', TRUE, TRUE),
    ('G03', 'Gastos en general', TRUE, TRUE),
    ('I01', 'Construcciones', TRUE, TRUE),
    ('I02', 'Mobiliario y equipo de oficina por inversiones', TRUE, TRUE),
    ('I03', 'Equipo de transporte', TRUE, TRUE),
    ('I04', 'Equipo de cómputo y accesorios', TRUE, TRUE),
    ('I05', 'Dados, troqueles, moldes, matrices y herramental', TRUE, TRUE),
    ('I06', 'Comunicaciones telefónicas', TRUE, TRUE),
    ('I07', 'Comunicaciones satelitales', TRUE, TRUE),
    ('I08', 'Otra maquinaria y equipo', TRUE, TRUE),
    ('D01', 'Honorarios médicos, dentales y gastos hospitalarios', TRUE, FALSE),
    ('D02', 'Gastos médicos por incapacidad o discapacidad', TRUE, FALSE),
    ('D03', 'Gastos funerales', TRUE, FALSE),
    ('D04', 'Donativos', TRUE, FALSE),
    ('D05', 'Intereses reales efectivamente pagados por créditos hipotecarios', TRUE, FALSE),
    ('D06', 'Aportaciones voluntarias al SAR', TRUE, FALSE),
    ('D07', 'Primas por seguros de gastos médicos', TRUE, FALSE),
    ('D08', 'Gastos de transportación escolar obligatoria', TRUE, FALSE),
    ('D09', 'Depósitos en cuentas para el ahorro', TRUE, FALSE),
    ('D10', 'Pagos por servicios educativos', TRUE, FALSE),
    ('S01', 'Sin efectos fiscales', TRUE, TRUE),
    ('CP01', 'Pagos', TRUE, TRUE)
ON CONFLICT (clave) DO NOTHING;

-- ============================================================================
-- CFDI CATALOG: Régimen Fiscal
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.cfdi_regimen_catalog (
    clave TEXT PRIMARY KEY,
    descripcion TEXT NOT NULL,
    aplica_fisica BOOLEAN DEFAULT TRUE,
    aplica_moral BOOLEAN DEFAULT TRUE,
    is_active BOOLEAN DEFAULT TRUE
);

INSERT INTO public.cfdi_regimen_catalog (clave, descripcion, aplica_fisica, aplica_moral) VALUES
    ('601', 'General de Ley Personas Morales', FALSE, TRUE),
    ('603', 'Personas Morales con Fines no Lucrativos', FALSE, TRUE),
    ('605', 'Sueldos y Salarios e Ingresos Asimilados a Salarios', TRUE, FALSE),
    ('606', 'Arrendamiento', TRUE, FALSE),
    ('607', 'Régimen de Enajenación o Adquisición de Bienes', TRUE, FALSE),
    ('608', 'Demás ingresos', TRUE, FALSE),
    ('610', 'Residentes en el Extranjero sin Establecimiento Permanente en México', TRUE, TRUE),
    ('611', 'Ingresos por Dividendos', TRUE, FALSE),
    ('612', 'Personas Físicas con Actividades Empresariales y Profesionales', TRUE, FALSE),
    ('614', 'Ingresos por intereses', TRUE, FALSE),
    ('615', 'Régimen de los ingresos por obtención de premios', TRUE, FALSE),
    ('616', 'Sin obligaciones fiscales', TRUE, FALSE),
    ('620', 'Sociedades Cooperativas de Producción', FALSE, TRUE),
    ('621', 'Incorporación Fiscal', TRUE, FALSE),
    ('622', 'Actividades Agrícolas, Ganaderas, Silvícolas y Pesqueras', TRUE, TRUE),
    ('623', 'Opcional para Grupos de Sociedades', FALSE, TRUE),
    ('624', 'Coordinados', FALSE, TRUE),
    ('625', 'Régimen de las Actividades Empresariales con ingresos a través de Plataformas Tecnológicas', TRUE, FALSE),
    ('626', 'Régimen Simplificado de Confianza', TRUE, TRUE)
ON CONFLICT (clave) DO NOTHING;

-- ============================================================================
-- CFDI REQUEST TABLE
-- Queue for CFDI generation requests
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.cfdi_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Request info
    ride_id UUID REFERENCES public.rides(id) ON DELETE SET NULL,
    delivery_id UUID REFERENCES public.package_deliveries(id) ON DELETE SET NULL,
    rider_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,

    -- Receptor data
    receptor_rfc TEXT NOT NULL,
    receptor_nombre TEXT NOT NULL,
    receptor_regimen TEXT NOT NULL,
    receptor_codigo_postal TEXT NOT NULL,
    receptor_uso_cfdi TEXT NOT NULL,

    -- Status
    status TEXT NOT NULL DEFAULT 'pending', -- 'pending', 'processing', 'completed', 'failed'

    -- Result
    cfdi_invoice_id UUID REFERENCES public.cfdi_invoices(id),
    error_message TEXT,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    processed_at TIMESTAMPTZ
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_cfdi_requests_status ON public.cfdi_requests(status);
CREATE INDEX IF NOT EXISTS idx_cfdi_requests_rider ON public.cfdi_requests(rider_id);

-- RLS
ALTER TABLE public.cfdi_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Riders can view and create own requests" ON public.cfdi_requests
    FOR ALL USING (auth.uid() = rider_id);

-- ============================================================================
-- FUNCTION: Create CFDI request
-- ============================================================================

CREATE OR REPLACE FUNCTION request_cfdi(
    p_rider_id UUID,
    p_ride_id UUID DEFAULT NULL,
    p_delivery_id UUID DEFAULT NULL,
    p_receptor_rfc TEXT DEFAULT NULL,
    p_receptor_nombre TEXT DEFAULT NULL,
    p_receptor_regimen TEXT DEFAULT NULL,
    p_receptor_codigo_postal TEXT DEFAULT NULL,
    p_receptor_uso_cfdi TEXT DEFAULT 'G03'
)
RETURNS UUID AS $$
DECLARE
    v_profile public.profiles;
    v_request_id UUID;
    v_rfc TEXT;
    v_nombre TEXT;
    v_regimen TEXT;
    v_cp TEXT;
BEGIN
    -- Get rider profile
    SELECT * INTO v_profile FROM public.profiles WHERE id = p_rider_id;

    -- Use provided values or fall back to profile
    v_rfc := COALESCE(p_receptor_rfc, v_profile.rfc);
    v_nombre := COALESCE(p_receptor_nombre, v_profile.full_name);
    v_regimen := COALESCE(p_receptor_regimen, v_profile.regimen_fiscal);
    v_cp := COALESCE(p_receptor_codigo_postal, v_profile.codigo_postal);

    -- Validate required fields
    IF v_rfc IS NULL THEN
        RAISE EXCEPTION 'RFC is required for CFDI';
    END IF;
    IF v_regimen IS NULL THEN
        RAISE EXCEPTION 'Régimen fiscal is required for CFDI';
    END IF;
    IF v_cp IS NULL THEN
        RAISE EXCEPTION 'Código postal is required for CFDI';
    END IF;

    -- Validate RFC format
    IF NOT validate_rfc(v_rfc) THEN
        RAISE EXCEPTION 'Invalid RFC format: %', v_rfc;
    END IF;

    -- Create request
    INSERT INTO public.cfdi_requests (
        rider_id, ride_id, delivery_id,
        receptor_rfc, receptor_nombre, receptor_regimen,
        receptor_codigo_postal, receptor_uso_cfdi
    ) VALUES (
        p_rider_id, p_ride_id, p_delivery_id,
        UPPER(v_rfc), v_nombre, v_regimen,
        v_cp, p_receptor_uso_cfdi
    )
    RETURNING id INTO v_request_id;

    -- Update profile with fiscal data if not set
    UPDATE public.profiles
    SET
        rfc = COALESCE(rfc, UPPER(v_rfc)),
        regimen_fiscal = COALESCE(regimen_fiscal, v_regimen),
        codigo_postal = COALESCE(codigo_postal, v_cp)
    WHERE id = p_rider_id;

    RETURN v_request_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FUNCTION: Get rider's invoices
-- ============================================================================

CREATE OR REPLACE FUNCTION get_rider_invoices(
    p_rider_id UUID,
    p_limit INTEGER DEFAULT 50,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    invoice_id UUID,
    uuid_fiscal TEXT,
    fecha_emision TIMESTAMPTZ,
    subtotal DECIMAL,
    iva_amount DECIMAL,
    total DECIMAL,
    status TEXT,
    xml_url TEXT,
    pdf_url TEXT,
    ride_id UUID,
    delivery_id UUID
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        ci.id,
        ci.uuid_fiscal,
        ci.fecha_emision,
        ci.subtotal,
        ci.iva_amount,
        ci.total,
        ci.status,
        ci.xml_url,
        ci.pdf_url,
        ci.ride_id,
        ci.delivery_id
    FROM public.cfdi_invoices ci
    WHERE ci.rider_id = p_rider_id
    ORDER BY ci.fecha_emision DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- PLATFORM CFDI CONFIG
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.cfdi_platform_config (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    country_code TEXT NOT NULL REFERENCES public.countries(code),

    -- Emisor info
    emisor_rfc TEXT NOT NULL,
    emisor_nombre TEXT NOT NULL,
    emisor_regimen TEXT NOT NULL,
    emisor_codigo_postal TEXT NOT NULL,

    -- PAC configuration
    pac_provider TEXT NOT NULL, -- 'facturama', 'sw_sapien'
    pac_user TEXT,
    pac_sandbox BOOLEAN DEFAULT TRUE,

    -- Certificate info (encrypted or reference)
    certificate_number TEXT,

    -- Default values
    lugar_expedicion TEXT NOT NULL,
    metodo_pago TEXT DEFAULT 'PUE', -- Pago en Una Exhibición
    forma_pago TEXT DEFAULT '03', -- Transferencia electrónica

    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert default Mexico config (to be updated with real values)
INSERT INTO public.cfdi_platform_config (
    country_code, emisor_rfc, emisor_nombre, emisor_regimen,
    emisor_codigo_postal, pac_provider, lugar_expedicion
) VALUES (
    'MX', 'XAXX010101000', 'TORO MOBILITY MEXICO SA DE CV', '601',
    '06600', 'facturama', '06600'
) ON CONFLICT DO NOTHING;
