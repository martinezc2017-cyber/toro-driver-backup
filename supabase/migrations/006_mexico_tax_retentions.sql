-- ============================================================================
-- TORO - MEXICO SUPPORT: Tax Retentions (ISR & IVA)
-- Migration 006
-- ============================================================================

-- ============================================================================
-- TAX RETENTIONS TABLE
-- Tracks ISR and IVA retentions per transaction for SAT reporting
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.tax_retentions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- References
    driver_id UUID NOT NULL REFERENCES public.drivers(id) ON DELETE CASCADE,
    ride_id UUID REFERENCES public.rides(id) ON DELETE SET NULL,
    delivery_id UUID REFERENCES public.package_deliveries(id) ON DELETE SET NULL,

    -- Transaction type
    transaction_type TEXT NOT NULL, -- 'ride', 'delivery', 'tip'

    -- Amounts
    gross_amount DECIMAL(10,2) NOT NULL, -- Monto bruto

    -- ISR Retention
    has_rfc BOOLEAN NOT NULL DEFAULT FALSE,
    isr_rate DECIMAL(5,4) NOT NULL, -- 0.025 or 0.20
    isr_amount DECIMAL(10,2) NOT NULL,

    -- IVA Retention
    iva_rate DECIMAL(5,4) NOT NULL DEFAULT 0.08, -- 8%
    iva_amount DECIMAL(10,2) NOT NULL,

    -- IVA that driver must pay directly to SAT (the other 8%)
    iva_driver_owes DECIMAL(10,2) NOT NULL,

    -- Net amount after retentions
    net_amount DECIMAL(10,2) NOT NULL,

    -- Period for reporting
    period_year INTEGER NOT NULL,
    period_month INTEGER NOT NULL,

    -- Currency
    currency TEXT NOT NULL DEFAULT 'MXN',

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_tax_retentions_driver ON public.tax_retentions(driver_id);
CREATE INDEX IF NOT EXISTS idx_tax_retentions_period ON public.tax_retentions(period_year, period_month);
CREATE INDEX IF NOT EXISTS idx_tax_retentions_ride ON public.tax_retentions(ride_id) WHERE ride_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tax_retentions_delivery ON public.tax_retentions(delivery_id) WHERE delivery_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tax_retentions_created ON public.tax_retentions(created_at DESC);

-- RLS
ALTER TABLE public.tax_retentions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Drivers can view own tax retentions" ON public.tax_retentions
    FOR SELECT USING (auth.uid() = driver_id);

-- ============================================================================
-- MONTHLY TAX SUMMARY TABLE
-- Aggregated monthly totals for easier reporting
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.tax_monthly_summary (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    driver_id UUID NOT NULL REFERENCES public.drivers(id) ON DELETE CASCADE,
    period_year INTEGER NOT NULL,
    period_month INTEGER NOT NULL,

    -- Totals
    total_gross DECIMAL(12,2) DEFAULT 0.00,
    total_isr_retained DECIMAL(12,2) DEFAULT 0.00,
    total_iva_retained DECIMAL(12,2) DEFAULT 0.00,
    total_iva_driver_owes DECIMAL(12,2) DEFAULT 0.00,
    total_net DECIMAL(12,2) DEFAULT 0.00,

    -- Counts
    transaction_count INTEGER DEFAULT 0,

    -- RFC status at end of period
    had_rfc BOOLEAN DEFAULT FALSE,

    -- Constancia generated
    constancia_url TEXT,
    constancia_generated_at TIMESTAMPTZ,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(driver_id, period_year, period_month)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_tax_monthly_driver ON public.tax_monthly_summary(driver_id);
CREATE INDEX IF NOT EXISTS idx_tax_monthly_period ON public.tax_monthly_summary(period_year, period_month);

-- RLS
ALTER TABLE public.tax_monthly_summary ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Drivers can view own tax summary" ON public.tax_monthly_summary
    FOR SELECT USING (auth.uid() = driver_id);

-- ============================================================================
-- FUNCTION: Calculate tax retention
-- ============================================================================

CREATE OR REPLACE FUNCTION calculate_tax_retention(
    p_driver_id UUID,
    p_gross_amount DECIMAL,
    p_ride_id UUID DEFAULT NULL,
    p_delivery_id UUID DEFAULT NULL,
    p_transaction_type TEXT DEFAULT 'ride'
)
RETURNS TABLE (
    isr_amount DECIMAL,
    iva_amount DECIMAL,
    iva_driver_owes DECIMAL,
    net_amount DECIMAL,
    isr_rate DECIMAL,
    has_rfc BOOLEAN
) AS $$
DECLARE
    v_driver public.drivers;
    v_country public.countries;
    v_has_rfc BOOLEAN;
    v_isr_rate DECIMAL;
    v_iva_rate DECIMAL := 0.08;
    v_isr_amount DECIMAL;
    v_iva_amount DECIMAL;
    v_iva_driver_owes DECIMAL;
    v_net_amount DECIMAL;
BEGIN
    -- Get driver
    SELECT * INTO v_driver FROM public.drivers WHERE id = p_driver_id;

    -- Only calculate for Mexico
    IF v_driver.country_code != 'MX' THEN
        RETURN QUERY SELECT 0::DECIMAL, 0::DECIMAL, 0::DECIMAL, p_gross_amount, 0::DECIMAL, FALSE;
        RETURN;
    END IF;

    -- Get country config
    SELECT * INTO v_country FROM public.countries WHERE code = 'MX';

    -- Check if driver has validated RFC
    v_has_rfc := v_driver.rfc IS NOT NULL AND v_driver.rfc_validated = TRUE;

    -- Determine ISR rate
    IF v_has_rfc THEN
        v_isr_rate := v_country.isr_rate_with_rfc; -- 2.5%
    ELSE
        v_isr_rate := v_country.isr_rate_without_rfc; -- 20%
    END IF;

    -- Calculate amounts
    v_isr_amount := ROUND(p_gross_amount * v_isr_rate, 2);
    v_iva_amount := ROUND(p_gross_amount * v_iva_rate, 2); -- 8% retenido por plataforma
    v_iva_driver_owes := ROUND(p_gross_amount * v_iva_rate, 2); -- 8% que driver paga al SAT
    v_net_amount := p_gross_amount - v_isr_amount - v_iva_amount;

    -- Insert retention record
    INSERT INTO public.tax_retentions (
        driver_id, ride_id, delivery_id, transaction_type,
        gross_amount, has_rfc, isr_rate, isr_amount,
        iva_rate, iva_amount, iva_driver_owes, net_amount,
        period_year, period_month, currency
    ) VALUES (
        p_driver_id, p_ride_id, p_delivery_id, p_transaction_type,
        p_gross_amount, v_has_rfc, v_isr_rate, v_isr_amount,
        v_iva_rate, v_iva_amount, v_iva_driver_owes, v_net_amount,
        EXTRACT(YEAR FROM NOW())::INTEGER,
        EXTRACT(MONTH FROM NOW())::INTEGER,
        'MXN'
    );

    -- Update monthly summary
    INSERT INTO public.tax_monthly_summary (
        driver_id, period_year, period_month,
        total_gross, total_isr_retained, total_iva_retained,
        total_iva_driver_owes, total_net, transaction_count, had_rfc
    ) VALUES (
        p_driver_id,
        EXTRACT(YEAR FROM NOW())::INTEGER,
        EXTRACT(MONTH FROM NOW())::INTEGER,
        p_gross_amount, v_isr_amount, v_iva_amount,
        v_iva_driver_owes, v_net_amount, 1, v_has_rfc
    )
    ON CONFLICT (driver_id, period_year, period_month)
    DO UPDATE SET
        total_gross = tax_monthly_summary.total_gross + p_gross_amount,
        total_isr_retained = tax_monthly_summary.total_isr_retained + v_isr_amount,
        total_iva_retained = tax_monthly_summary.total_iva_retained + v_iva_amount,
        total_iva_driver_owes = tax_monthly_summary.total_iva_driver_owes + v_iva_driver_owes,
        total_net = tax_monthly_summary.total_net + v_net_amount,
        transaction_count = tax_monthly_summary.transaction_count + 1,
        had_rfc = v_has_rfc,
        updated_at = NOW();

    RETURN QUERY SELECT v_isr_amount, v_iva_amount, v_iva_driver_owes, v_net_amount, v_isr_rate, v_has_rfc;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FUNCTION: Get driver tax summary for period
-- ============================================================================

CREATE OR REPLACE FUNCTION get_driver_tax_summary(
    p_driver_id UUID,
    p_year INTEGER,
    p_month INTEGER DEFAULT NULL
)
RETURNS TABLE (
    period TEXT,
    total_gross DECIMAL,
    total_isr DECIMAL,
    total_iva_retained DECIMAL,
    total_iva_owes DECIMAL,
    total_net DECIMAL,
    transactions INTEGER,
    had_rfc BOOLEAN
) AS $$
BEGIN
    IF p_month IS NOT NULL THEN
        -- Single month
        RETURN QUERY
        SELECT
            p_year::TEXT || '-' || LPAD(p_month::TEXT, 2, '0'),
            COALESCE(tms.total_gross, 0.00),
            COALESCE(tms.total_isr_retained, 0.00),
            COALESCE(tms.total_iva_retained, 0.00),
            COALESCE(tms.total_iva_driver_owes, 0.00),
            COALESCE(tms.total_net, 0.00),
            COALESCE(tms.transaction_count, 0),
            COALESCE(tms.had_rfc, FALSE)
        FROM public.tax_monthly_summary tms
        WHERE tms.driver_id = p_driver_id
        AND tms.period_year = p_year
        AND tms.period_month = p_month;
    ELSE
        -- Full year
        RETURN QUERY
        SELECT
            p_year::TEXT,
            COALESCE(SUM(tms.total_gross), 0.00),
            COALESCE(SUM(tms.total_isr_retained), 0.00),
            COALESCE(SUM(tms.total_iva_retained), 0.00),
            COALESCE(SUM(tms.total_iva_driver_owes), 0.00),
            COALESCE(SUM(tms.total_net), 0.00),
            COALESCE(SUM(tms.transaction_count), 0)::INTEGER,
            bool_or(tms.had_rfc)
        FROM public.tax_monthly_summary tms
        WHERE tms.driver_id = p_driver_id
        AND tms.period_year = p_year;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FUNCTION: Get detailed retentions for period (for constancia)
-- ============================================================================

CREATE OR REPLACE FUNCTION get_retention_details(
    p_driver_id UUID,
    p_year INTEGER,
    p_month INTEGER
)
RETURNS TABLE (
    transaction_date TIMESTAMPTZ,
    transaction_type TEXT,
    gross_amount DECIMAL,
    isr_rate DECIMAL,
    isr_amount DECIMAL,
    iva_amount DECIMAL,
    net_amount DECIMAL,
    ride_id UUID,
    delivery_id UUID
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        tr.created_at,
        tr.transaction_type,
        tr.gross_amount,
        tr.isr_rate,
        tr.isr_amount,
        tr.iva_amount,
        tr.net_amount,
        tr.ride_id,
        tr.delivery_id
    FROM public.tax_retentions tr
    WHERE tr.driver_id = p_driver_id
    AND tr.period_year = p_year
    AND tr.period_month = p_month
    ORDER BY tr.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- VIEW: Driver pending tax obligations
-- ============================================================================

CREATE OR REPLACE VIEW public.driver_tax_obligations AS
SELECT
    d.id AS driver_id,
    d.first_name || ' ' || d.last_name AS driver_name,
    d.rfc,
    d.rfc_validated,
    tms.period_year,
    tms.period_month,
    tms.total_gross,
    tms.total_isr_retained,
    tms.total_iva_retained,
    tms.total_iva_driver_owes,
    tms.constancia_url,
    CASE
        WHEN tms.constancia_url IS NOT NULL THEN 'generated'
        ELSE 'pending'
    END AS constancia_status
FROM public.drivers d
JOIN public.tax_monthly_summary tms ON d.id = tms.driver_id
WHERE d.country_code = 'MX';
