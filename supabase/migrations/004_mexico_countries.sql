-- ============================================================================
-- TORO - MEXICO SUPPORT: Countries & Multi-Region Foundation
-- Migration 004
-- ============================================================================

-- ============================================================================
-- COUNTRIES TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.countries (
    code TEXT PRIMARY KEY, -- 'MX', 'US'
    name TEXT NOT NULL,
    currency TEXT NOT NULL, -- 'MXN', 'USD'
    currency_symbol TEXT NOT NULL DEFAULT '$',
    tax_rate DECIMAL(5,4) NOT NULL DEFAULT 0.00, -- 0.16 for Mexico (IVA 16%)
    isr_rate_with_rfc DECIMAL(5,4) DEFAULT 0.025, -- 2.5% ISR con RFC
    isr_rate_without_rfc DECIMAL(5,4) DEFAULT 0.20, -- 20% ISR sin RFC
    iva_retention_rate DECIMAL(5,4) DEFAULT 0.08, -- 8% IVA retencion
    stripe_provider TEXT, -- 'stripe_us', 'stripe_mx'
    requires_rfc BOOLEAN DEFAULT FALSE,
    requires_cfdi BOOLEAN DEFAULT FALSE,
    phone_prefix TEXT, -- '+52', '+1'
    phone_format TEXT, -- 'XX XXXX XXXX'
    timezone TEXT DEFAULT 'UTC',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert default countries
INSERT INTO public.countries (code, name, currency, currency_symbol, tax_rate, isr_rate_with_rfc, isr_rate_without_rfc, iva_retention_rate, stripe_provider, requires_rfc, requires_cfdi, phone_prefix, timezone)
VALUES
    ('US', 'United States', 'USD', '$', 0.00, 0.00, 0.00, 0.00, 'stripe_us', FALSE, FALSE, '+1', 'America/Phoenix'),
    ('MX', 'México', 'MXN', '$', 0.16, 0.025, 0.20, 0.08, 'stripe_mx', TRUE, TRUE, '+52', 'America/Mexico_City')
ON CONFLICT (code) DO NOTHING;

-- ============================================================================
-- MEXICAN STATES (ENTIDADES FEDERATIVAS)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.mexican_states (
    code TEXT PRIMARY KEY, -- 'CDMX', 'JAL', 'NL'
    name TEXT NOT NULL,
    timezone TEXT NOT NULL DEFAULT 'America/Mexico_City',
    is_active BOOLEAN DEFAULT TRUE
);

INSERT INTO public.mexican_states (code, name, timezone) VALUES
    ('CDMX', 'Ciudad de México', 'America/Mexico_City'),
    ('AGS', 'Aguascalientes', 'America/Mexico_City'),
    ('BC', 'Baja California', 'America/Tijuana'),
    ('BCS', 'Baja California Sur', 'America/Mazatlan'),
    ('CAM', 'Campeche', 'America/Mexico_City'),
    ('CHIS', 'Chiapas', 'America/Mexico_City'),
    ('CHIH', 'Chihuahua', 'America/Chihuahua'),
    ('COAH', 'Coahuila', 'America/Mexico_City'),
    ('COL', 'Colima', 'America/Mexico_City'),
    ('DGO', 'Durango', 'America/Mexico_City'),
    ('GTO', 'Guanajuato', 'America/Mexico_City'),
    ('GRO', 'Guerrero', 'America/Mexico_City'),
    ('HGO', 'Hidalgo', 'America/Mexico_City'),
    ('JAL', 'Jalisco', 'America/Mexico_City'),
    ('MEX', 'Estado de México', 'America/Mexico_City'),
    ('MICH', 'Michoacán', 'America/Mexico_City'),
    ('MOR', 'Morelos', 'America/Mexico_City'),
    ('NAY', 'Nayarit', 'America/Mazatlan'),
    ('NL', 'Nuevo León', 'America/Mexico_City'),
    ('OAX', 'Oaxaca', 'America/Mexico_City'),
    ('PUE', 'Puebla', 'America/Mexico_City'),
    ('QRO', 'Querétaro', 'America/Mexico_City'),
    ('QROO', 'Quintana Roo', 'America/Cancun'),
    ('SLP', 'San Luis Potosí', 'America/Mexico_City'),
    ('SIN', 'Sinaloa', 'America/Mazatlan'),
    ('SON', 'Sonora', 'America/Hermosillo'),
    ('TAB', 'Tabasco', 'America/Mexico_City'),
    ('TAMPS', 'Tamaulipas', 'America/Mexico_City'),
    ('TLAX', 'Tlaxcala', 'America/Mexico_City'),
    ('VER', 'Veracruz', 'America/Mexico_City'),
    ('YUC', 'Yucatán', 'America/Mexico_City'),
    ('ZAC', 'Zacatecas', 'America/Mexico_City')
ON CONFLICT (code) DO NOTHING;

-- ============================================================================
-- MODIFY DRIVERS TABLE - Add Mexico fields
-- ============================================================================

ALTER TABLE public.drivers
ADD COLUMN IF NOT EXISTS country_code TEXT DEFAULT 'US' REFERENCES public.countries(code),
ADD COLUMN IF NOT EXISTS state_code TEXT, -- 'CDMX', 'JAL', 'AZ', 'TX'
ADD COLUMN IF NOT EXISTS rfc TEXT, -- RFC para Mexico
ADD COLUMN IF NOT EXISTS rfc_validated BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS curp TEXT, -- CURP para Mexico
ADD COLUMN IF NOT EXISTS license_type TEXT, -- 'E1', 'A', 'B' para MX; 'standard' para US
ADD COLUMN IF NOT EXISTS insurance_policy_number TEXT,
ADD COLUMN IF NOT EXISTS insurance_provider TEXT,
ADD COLUMN IF NOT EXISTS insurance_expiry DATE,
ADD COLUMN IF NOT EXISTS semovi_constancia TEXT, -- Numero de constancia SEMOVI
ADD COLUMN IF NOT EXISTS semovi_constancia_expiry DATE,
ADD COLUMN IF NOT EXISTS semovi_vehicular TEXT, -- Constancia vehicular SEMOVI
ADD COLUMN IF NOT EXISTS semovi_vehicular_expiry DATE;

-- Index for country queries
CREATE INDEX IF NOT EXISTS idx_drivers_country ON public.drivers(country_code);
CREATE INDEX IF NOT EXISTS idx_drivers_state ON public.drivers(state_code);
CREATE INDEX IF NOT EXISTS idx_drivers_rfc ON public.drivers(rfc) WHERE rfc IS NOT NULL;

-- ============================================================================
-- MODIFY RIDES TABLE - Add currency and country
-- ============================================================================

ALTER TABLE public.rides
ADD COLUMN IF NOT EXISTS country_code TEXT DEFAULT 'US' REFERENCES public.countries(code),
ADD COLUMN IF NOT EXISTS currency TEXT DEFAULT 'USD',
ADD COLUMN IF NOT EXISTS fx_rate_applied DECIMAL(12,6),
ADD COLUMN IF NOT EXISTS isr_retained DECIMAL(10,2) DEFAULT 0.00,
ADD COLUMN IF NOT EXISTS iva_retained DECIMAL(10,2) DEFAULT 0.00,
ADD COLUMN IF NOT EXISTS gross_fare DECIMAL(10,2), -- Tarifa antes de impuestos
ADD COLUMN IF NOT EXISTS tax_amount DECIMAL(10,2) DEFAULT 0.00; -- IVA cobrado

CREATE INDEX IF NOT EXISTS idx_rides_country ON public.rides(country_code);
CREATE INDEX IF NOT EXISTS idx_rides_currency ON public.rides(currency);

-- ============================================================================
-- MODIFY PACKAGE_DELIVERIES TABLE - Add currency and country
-- ============================================================================

ALTER TABLE public.package_deliveries
ADD COLUMN IF NOT EXISTS country_code TEXT DEFAULT 'US' REFERENCES public.countries(code),
ADD COLUMN IF NOT EXISTS currency TEXT DEFAULT 'USD',
ADD COLUMN IF NOT EXISTS fx_rate_applied DECIMAL(12,6),
ADD COLUMN IF NOT EXISTS isr_retained DECIMAL(10,2) DEFAULT 0.00,
ADD COLUMN IF NOT EXISTS iva_retained DECIMAL(10,2) DEFAULT 0.00,
ADD COLUMN IF NOT EXISTS tax_amount DECIMAL(10,2) DEFAULT 0.00;

CREATE INDEX IF NOT EXISTS idx_deliveries_country ON public.package_deliveries(country_code);

-- ============================================================================
-- MODIFY EARNINGS TABLE - Add currency
-- ============================================================================

ALTER TABLE public.earnings
ADD COLUMN IF NOT EXISTS currency TEXT DEFAULT 'USD',
ADD COLUMN IF NOT EXISTS country_code TEXT DEFAULT 'US';

-- ============================================================================
-- MODIFY DRIVER_STRIPE_ACCOUNTS - Support multiple accounts per driver
-- ============================================================================

-- First drop the existing unique constraint on driver_id
ALTER TABLE public.driver_stripe_accounts
DROP CONSTRAINT IF EXISTS driver_stripe_accounts_driver_id_key;

-- Add provider column
ALTER TABLE public.driver_stripe_accounts
ADD COLUMN IF NOT EXISTS provider TEXT DEFAULT 'us'; -- 'us', 'mx'

-- Create new composite unique constraint
ALTER TABLE public.driver_stripe_accounts
ADD CONSTRAINT driver_stripe_accounts_driver_provider_unique
UNIQUE (driver_id, provider);

-- Index for provider queries
CREATE INDEX IF NOT EXISTS idx_stripe_accounts_provider
ON public.driver_stripe_accounts(provider);

-- ============================================================================
-- FX RATES TABLE (Exchange rates)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.fx_rates (
    id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    base_currency TEXT NOT NULL,
    quote_currency TEXT NOT NULL,
    rate DECIMAL(12,6) NOT NULL,
    source TEXT, -- 'exchangerate-api', 'manual', etc.
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_fx_rates_currencies
ON public.fx_rates(base_currency, quote_currency, fetched_at DESC);

-- Insert initial rates
INSERT INTO public.fx_rates (base_currency, quote_currency, rate, source)
VALUES
    ('MXN', 'USD', 0.058824, 'initial_seed'),
    ('USD', 'MXN', 17.00, 'initial_seed')
ON CONFLICT DO NOTHING;

-- RLS for fx_rates
ALTER TABLE public.fx_rates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read fx_rates" ON public.fx_rates
    FOR SELECT USING (true);

-- ============================================================================
-- PROFILES TABLE - Add country support
-- ============================================================================

ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS country_code TEXT DEFAULT 'US',
ADD COLUMN IF NOT EXISTS rfc TEXT, -- Para facturacion
ADD COLUMN IF NOT EXISTS regimen_fiscal TEXT, -- Regimen fiscal SAT
ADD COLUMN IF NOT EXISTS codigo_postal TEXT; -- CP para CFDI

-- ============================================================================
-- HELPER FUNCTION: Get current FX rate
-- ============================================================================

CREATE OR REPLACE FUNCTION get_fx_rate(
    p_base_currency TEXT,
    p_quote_currency TEXT
)
RETURNS DECIMAL AS $$
DECLARE
    v_rate DECIMAL;
BEGIN
    SELECT rate INTO v_rate
    FROM public.fx_rates
    WHERE base_currency = p_base_currency
    AND quote_currency = p_quote_currency
    ORDER BY fetched_at DESC
    LIMIT 1;

    RETURN COALESCE(v_rate, 1.0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- HELPER FUNCTION: Get country config
-- ============================================================================

CREATE OR REPLACE FUNCTION get_country_config(p_country_code TEXT)
RETURNS public.countries AS $$
DECLARE
    v_country public.countries;
BEGIN
    SELECT * INTO v_country
    FROM public.countries
    WHERE code = p_country_code;

    RETURN v_country;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- TRIGGER: Update country on drivers based on state
-- ============================================================================

CREATE OR REPLACE FUNCTION set_driver_country_from_state()
RETURNS TRIGGER AS $$
BEGIN
    -- If state is a Mexican state, set country to MX
    IF EXISTS (SELECT 1 FROM public.mexican_states WHERE code = NEW.state_code) THEN
        NEW.country_code := 'MX';
    ELSE
        NEW.country_code := 'US';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_set_driver_country
    BEFORE INSERT OR UPDATE OF state_code ON public.drivers
    FOR EACH ROW
    EXECUTE FUNCTION set_driver_country_from_state();

-- ============================================================================
-- REALTIME for new tables
-- ============================================================================

ALTER PUBLICATION supabase_realtime ADD TABLE public.fx_rates;
