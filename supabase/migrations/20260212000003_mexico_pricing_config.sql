-- ============================================================================
-- MIGRATION: Mexico Pricing Config - Precios competitivos de mercado
-- Date: 2026-02-12
-- ============================================================================
-- Precios basados en investigación de mercado CDMX Feb 2026:
--   Uber:     base $7, km $3.57, min $1.80, mínima $35, plataforma 25%
--   Didi:     base $10, km $6.50, min $1.50, plataforma ~22%
--   Cabify:   base $25, km $8.50, min $2.50, plataforma ~25%
--   InDriver: km $4.40, negociado, plataforma 10-15%
--
-- Toro MX: Competitivo con Uber, driver gana más (+15% vs Uber)
-- Split: 20% plataforma + 16% IVA + 0% seguro + 64% driver = 100%
-- QR points: ACTIVADO para MX (qr_point_value = 1.0, igual que US)
-- Carpool: 15% descuento/asiento, máx 40%
-- ============================================================================

-- Ensure booking_type column exists (may have been added in a previous migration)
ALTER TABLE public.pricing_config
ADD COLUMN IF NOT EXISTS booking_type TEXT DEFAULT 'ride';

-- Ensure country_code column exists
ALTER TABLE public.pricing_config
ADD COLUMN IF NOT EXISTS country_code TEXT DEFAULT 'US';

-- Ensure carpool columns exist
ALTER TABLE public.pricing_config
ADD COLUMN IF NOT EXISTS carpool_discount_per_seat DECIMAL(5,2) DEFAULT 0;

ALTER TABLE public.pricing_config
ADD COLUMN IF NOT EXISTS carpool_max_discount DECIMAL(5,2) DEFAULT 0;

-- Ensure QR column exists
ALTER TABLE public.pricing_config
ADD COLUMN IF NOT EXISTS qr_point_value DECIMAL(5,2) DEFAULT 1.0;

-- Ensure TNC tax column exists
ALTER TABLE public.pricing_config
ADD COLUMN IF NOT EXISTS tnc_tax_per_trip DECIMAL(10,2) DEFAULT 0;

-- Ensure variable platform columns exist
ALTER TABLE public.pricing_config
ADD COLUMN IF NOT EXISTS variable_platform_enabled BOOLEAN DEFAULT false;

ALTER TABLE public.pricing_config
ADD COLUMN IF NOT EXISTS platform_tier_1_max_fare DECIMAL(10,2) DEFAULT 10.0;
ALTER TABLE public.pricing_config
ADD COLUMN IF NOT EXISTS platform_tier_1_percent DECIMAL(5,2) DEFAULT 5.0;
ALTER TABLE public.pricing_config
ADD COLUMN IF NOT EXISTS platform_tier_2_max_fare DECIMAL(10,2) DEFAULT 20.0;
ALTER TABLE public.pricing_config
ADD COLUMN IF NOT EXISTS platform_tier_2_percent DECIMAL(5,2) DEFAULT 15.0;
ALTER TABLE public.pricing_config
ADD COLUMN IF NOT EXISTS platform_tier_3_max_fare DECIMAL(10,2) DEFAULT 35.0;
ALTER TABLE public.pricing_config
ADD COLUMN IF NOT EXISTS platform_tier_3_percent DECIMAL(5,2) DEFAULT 23.4;
ALTER TABLE public.pricing_config
ADD COLUMN IF NOT EXISTS platform_tier_4_percent DECIMAL(5,2) DEFAULT 25.0;

-- Drop old unique constraint on state_code only (if exists)
-- and create composite unique on (state_code, booking_type)
DO $$
BEGIN
  -- Try to drop old unique constraint
  BEGIN
    ALTER TABLE public.pricing_config DROP CONSTRAINT IF EXISTS pricing_config_state_code_key;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  -- Create composite unique if not exists
  BEGIN
    ALTER TABLE public.pricing_config
    ADD CONSTRAINT pricing_config_state_booking_unique UNIQUE (state_code, booking_type);
  EXCEPTION WHEN duplicate_table THEN NULL;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
END $$;

-- ============================================================================
-- CLEAN EXISTING MX ENTRIES (fresh insert with correct market prices)
-- ============================================================================
DELETE FROM public.pricing_config WHERE country_code = 'MX';

-- ============================================================================
-- TIER 1: Ciudades grandes (CDMX, Monterrey, Guadalajara)
-- Precios competitivos con Uber: rider paga similar, driver gana +15% más
-- ============================================================================
INSERT INTO public.pricing_config (
  state_code, state_name, booking_type, country_code,
  base_fare, per_mile_rate, per_minute_rate, minimum_fare,
  service_fee, booking_fee, cancellation_fee,
  driver_percentage, platform_percentage, insurance_percentage, tax_percentage,
  peak_multiplier, night_multiplier, weekend_multiplier, demand_multiplier,
  carpool_discount_per_seat, carpool_max_discount,
  qr_point_value, tnc_tax_per_trip, variable_platform_enabled,
  is_active
) VALUES
  -- CDMX (Ciudad de México) - Mercado más grande
  ('CDMX', 'Ciudad de México', 'ride', 'MX',
   10.00, 4.50, 2.00, 38.00,
   0, 0, 30.00,
   64.00, 20.00, 0, 16.00,
   1.50, 1.25, 1.10, 1.00,
   15.00, 40.00,
   1.0, 0, false, true),

  ('CDMX', 'Ciudad de México', 'carpool', 'MX',
   8.00, 4.00, 1.80, 30.00,
   0, 0, 25.00,
   64.00, 20.00, 0, 16.00,
   1.50, 1.25, 1.10, 1.00,
   15.00, 40.00,
   1.0, 0, false, true),

  -- NL (Nuevo León / Monterrey)
  ('NL', 'Nuevo León', 'ride', 'MX',
   10.00, 4.50, 2.00, 38.00,
   0, 0, 30.00,
   64.00, 20.00, 0, 16.00,
   1.50, 1.20, 1.10, 1.00,
   15.00, 40.00,
   1.0, 0, false, true),

  ('NL', 'Nuevo León', 'carpool', 'MX',
   8.00, 4.00, 1.80, 30.00,
   0, 0, 25.00,
   64.00, 20.00, 0, 16.00,
   1.50, 1.20, 1.10, 1.00,
   15.00, 40.00,
   1.0, 0, false, true),

  -- JAL (Jalisco / Guadalajara)
  ('JAL', 'Jalisco', 'ride', 'MX',
   9.00, 4.20, 1.90, 36.00,
   0, 0, 28.00,
   64.00, 20.00, 0, 16.00,
   1.50, 1.20, 1.10, 1.00,
   15.00, 40.00,
   1.0, 0, false, true),

  ('JAL', 'Jalisco', 'carpool', 'MX',
   7.00, 3.80, 1.70, 28.00,
   0, 0, 22.00,
   64.00, 20.00, 0, 16.00,
   1.50, 1.20, 1.10, 1.00,
   15.00, 40.00,
   1.0, 0, false, true);

-- ============================================================================
-- TIER 2: Ciudades medianas (QRO, PUE, GTO, MEX, BC, QROO, SIN, SON, COAH)
-- ~10% más baratas que Tier 1
-- ============================================================================
INSERT INTO public.pricing_config (
  state_code, state_name, booking_type, country_code,
  base_fare, per_mile_rate, per_minute_rate, minimum_fare,
  service_fee, booking_fee, cancellation_fee,
  driver_percentage, platform_percentage, insurance_percentage, tax_percentage,
  peak_multiplier, night_multiplier, weekend_multiplier, demand_multiplier,
  carpool_discount_per_seat, carpool_max_discount,
  qr_point_value, tnc_tax_per_trip, variable_platform_enabled,
  is_active
) VALUES
  ('QRO', 'Querétaro', 'ride', 'MX', 8.00, 4.00, 1.80, 35.00, 0, 0, 28.00, 64.00, 20.00, 0, 16.00, 1.50, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('QRO', 'Querétaro', 'carpool', 'MX', 6.50, 3.50, 1.60, 28.00, 0, 0, 22.00, 64.00, 20.00, 0, 16.00, 1.50, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),

  ('PUE', 'Puebla', 'ride', 'MX', 8.00, 4.00, 1.80, 35.00, 0, 0, 28.00, 64.00, 20.00, 0, 16.00, 1.50, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('PUE', 'Puebla', 'carpool', 'MX', 6.50, 3.50, 1.60, 28.00, 0, 0, 22.00, 64.00, 20.00, 0, 16.00, 1.50, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),

  ('GTO', 'Guanajuato', 'ride', 'MX', 8.00, 4.00, 1.80, 35.00, 0, 0, 28.00, 64.00, 20.00, 0, 16.00, 1.50, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('GTO', 'Guanajuato', 'carpool', 'MX', 6.50, 3.50, 1.60, 28.00, 0, 0, 22.00, 64.00, 20.00, 0, 16.00, 1.50, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),

  ('MEX', 'Estado de México', 'ride', 'MX', 8.00, 4.00, 1.80, 35.00, 0, 0, 28.00, 64.00, 20.00, 0, 16.00, 1.50, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('MEX', 'Estado de México', 'carpool', 'MX', 6.50, 3.50, 1.60, 28.00, 0, 0, 22.00, 64.00, 20.00, 0, 16.00, 1.50, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),

  ('BC', 'Baja California', 'ride', 'MX', 8.50, 4.20, 1.90, 36.00, 0, 0, 28.00, 64.00, 20.00, 0, 16.00, 1.50, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('BC', 'Baja California', 'carpool', 'MX', 7.00, 3.80, 1.70, 28.00, 0, 0, 22.00, 64.00, 20.00, 0, 16.00, 1.50, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),

  ('QROO', 'Quintana Roo', 'ride', 'MX', 9.00, 4.50, 2.00, 38.00, 0, 0, 30.00, 64.00, 20.00, 0, 16.00, 1.50, 1.25, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('QROO', 'Quintana Roo', 'carpool', 'MX', 7.50, 4.00, 1.80, 30.00, 0, 0, 25.00, 64.00, 20.00, 0, 16.00, 1.50, 1.25, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),

  ('SIN', 'Sinaloa', 'ride', 'MX', 8.00, 4.00, 1.80, 35.00, 0, 0, 28.00, 64.00, 20.00, 0, 16.00, 1.50, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('SIN', 'Sinaloa', 'carpool', 'MX', 6.50, 3.50, 1.60, 28.00, 0, 0, 22.00, 64.00, 20.00, 0, 16.00, 1.50, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),

  ('SON', 'Sonora', 'ride', 'MX', 8.00, 4.00, 1.80, 35.00, 0, 0, 28.00, 64.00, 20.00, 0, 16.00, 1.50, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('SON', 'Sonora', 'carpool', 'MX', 6.50, 3.50, 1.60, 28.00, 0, 0, 22.00, 64.00, 20.00, 0, 16.00, 1.50, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),

  ('COAH', 'Coahuila', 'ride', 'MX', 8.00, 4.00, 1.80, 35.00, 0, 0, 28.00, 64.00, 20.00, 0, 16.00, 1.50, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('COAH', 'Coahuila', 'carpool', 'MX', 6.50, 3.50, 1.60, 28.00, 0, 0, 22.00, 64.00, 20.00, 0, 16.00, 1.50, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true);

-- ============================================================================
-- TIER 3: Resto de México (~20% más baratas que Tier 1)
-- ============================================================================
INSERT INTO public.pricing_config (
  state_code, state_name, booking_type, country_code,
  base_fare, per_mile_rate, per_minute_rate, minimum_fare,
  service_fee, booking_fee, cancellation_fee,
  driver_percentage, platform_percentage, insurance_percentage, tax_percentage,
  peak_multiplier, night_multiplier, weekend_multiplier, demand_multiplier,
  carpool_discount_per_seat, carpool_max_discount,
  qr_point_value, tnc_tax_per_trip, variable_platform_enabled,
  is_active
) VALUES
  ('AGS', 'Aguascalientes', 'ride', 'MX', 7.00, 3.50, 1.50, 30.00, 0, 0, 25.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('BCS', 'Baja California Sur', 'ride', 'MX', 8.00, 4.00, 1.80, 35.00, 0, 0, 28.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('CAM', 'Campeche', 'ride', 'MX', 7.00, 3.50, 1.50, 30.00, 0, 0, 25.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('CHIS', 'Chiapas', 'ride', 'MX', 6.00, 3.00, 1.30, 28.00, 0, 0, 22.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('CHIH', 'Chihuahua', 'ride', 'MX', 7.50, 3.80, 1.70, 32.00, 0, 0, 26.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('COL', 'Colima', 'ride', 'MX', 7.00, 3.50, 1.50, 30.00, 0, 0, 25.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('DGO', 'Durango', 'ride', 'MX', 7.00, 3.50, 1.50, 30.00, 0, 0, 25.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('GRO', 'Guerrero', 'ride', 'MX', 7.00, 3.50, 1.50, 30.00, 0, 0, 25.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('HGO', 'Hidalgo', 'ride', 'MX', 7.00, 3.50, 1.50, 30.00, 0, 0, 25.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('MICH', 'Michoacán', 'ride', 'MX', 7.00, 3.50, 1.50, 30.00, 0, 0, 25.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('MOR', 'Morelos', 'ride', 'MX', 7.00, 3.50, 1.50, 30.00, 0, 0, 25.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('NAY', 'Nayarit', 'ride', 'MX', 7.00, 3.50, 1.50, 30.00, 0, 0, 25.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('OAX', 'Oaxaca', 'ride', 'MX', 6.50, 3.20, 1.40, 28.00, 0, 0, 22.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('SLP', 'San Luis Potosí', 'ride', 'MX', 7.00, 3.50, 1.50, 30.00, 0, 0, 25.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('TAB', 'Tabasco', 'ride', 'MX', 7.00, 3.50, 1.50, 30.00, 0, 0, 25.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('TAMPS', 'Tamaulipas', 'ride', 'MX', 7.50, 3.80, 1.70, 32.00, 0, 0, 26.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('TLAX', 'Tlaxcala', 'ride', 'MX', 6.50, 3.20, 1.40, 28.00, 0, 0, 22.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('VER', 'Veracruz', 'ride', 'MX', 7.00, 3.50, 1.50, 30.00, 0, 0, 25.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('YUC', 'Yucatán', 'ride', 'MX', 7.50, 3.80, 1.70, 32.00, 0, 0, 26.00, 64.00, 20.00, 0, 16.00, 1.40, 1.25, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('ZAC', 'Zacatecas', 'ride', 'MX', 6.50, 3.20, 1.40, 28.00, 0, 0, 22.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true);

-- ============================================================================
-- TIER 3: Carpool para todos los estados Tier 3 (~20% menos que ride)
-- ============================================================================
INSERT INTO public.pricing_config (
  state_code, state_name, booking_type, country_code,
  base_fare, per_mile_rate, per_minute_rate, minimum_fare,
  service_fee, booking_fee, cancellation_fee,
  driver_percentage, platform_percentage, insurance_percentage, tax_percentage,
  peak_multiplier, night_multiplier, weekend_multiplier, demand_multiplier,
  carpool_discount_per_seat, carpool_max_discount,
  qr_point_value, tnc_tax_per_trip, variable_platform_enabled,
  is_active
) VALUES
  ('AGS', 'Aguascalientes', 'carpool', 'MX', 5.50, 3.00, 1.30, 24.00, 0, 0, 20.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('BCS', 'Baja California Sur', 'carpool', 'MX', 6.50, 3.50, 1.60, 28.00, 0, 0, 22.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('CAM', 'Campeche', 'carpool', 'MX', 5.50, 3.00, 1.30, 24.00, 0, 0, 20.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('CHIS', 'Chiapas', 'carpool', 'MX', 5.00, 2.50, 1.10, 22.00, 0, 0, 18.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('CHIH', 'Chihuahua', 'carpool', 'MX', 6.00, 3.30, 1.50, 26.00, 0, 0, 21.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('COL', 'Colima', 'carpool', 'MX', 5.50, 3.00, 1.30, 24.00, 0, 0, 20.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('DGO', 'Durango', 'carpool', 'MX', 5.50, 3.00, 1.30, 24.00, 0, 0, 20.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('GRO', 'Guerrero', 'carpool', 'MX', 5.50, 3.00, 1.30, 24.00, 0, 0, 20.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('HGO', 'Hidalgo', 'carpool', 'MX', 5.50, 3.00, 1.30, 24.00, 0, 0, 20.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('MICH', 'Michoacán', 'carpool', 'MX', 5.50, 3.00, 1.30, 24.00, 0, 0, 20.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('MOR', 'Morelos', 'carpool', 'MX', 5.50, 3.00, 1.30, 24.00, 0, 0, 20.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('NAY', 'Nayarit', 'carpool', 'MX', 5.50, 3.00, 1.30, 24.00, 0, 0, 20.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('OAX', 'Oaxaca', 'carpool', 'MX', 5.00, 2.70, 1.20, 22.00, 0, 0, 18.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('SLP', 'San Luis Potosí', 'carpool', 'MX', 5.50, 3.00, 1.30, 24.00, 0, 0, 20.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('TAB', 'Tabasco', 'carpool', 'MX', 5.50, 3.00, 1.30, 24.00, 0, 0, 20.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('TAMPS', 'Tamaulipas', 'carpool', 'MX', 6.00, 3.30, 1.50, 26.00, 0, 0, 21.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('TLAX', 'Tlaxcala', 'carpool', 'MX', 5.00, 2.70, 1.20, 22.00, 0, 0, 18.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('VER', 'Veracruz', 'carpool', 'MX', 5.50, 3.00, 1.30, 24.00, 0, 0, 20.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('YUC', 'Yucatán', 'carpool', 'MX', 6.00, 3.30, 1.50, 26.00, 0, 0, 21.00, 64.00, 20.00, 0, 16.00, 1.40, 1.25, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true),
  ('ZAC', 'Zacatecas', 'carpool', 'MX', 5.00, 2.70, 1.20, 22.00, 0, 0, 18.00, 64.00, 20.00, 0, 16.00, 1.40, 1.20, 1.10, 1.00, 15.00, 40.00, 1.0, 0, false, true);

-- ============================================================================
-- SYNC: Update old pricing_rules_mx table (backward compatibility)
-- The rider app's MexicoPricingService may still fall back to these tables.
-- Update existing rows to match new market-competitive prices.
-- ============================================================================

-- Update CDMX ride rules
UPDATE public.pricing_rules_mx pr
SET base_fare = 10.00,
    per_km = 4.50,
    per_min = 2.00,
    min_fare = 38.00,
    booking_fee = 0,
    cancellation_fee = 30.00,
    night_multiplier = 1.25,
    weekend_multiplier = 1.10,
    platform_fee_percent = 20.00,
    driver_percent = 64.00,
    updated_at = NOW()
FROM public.pricing_zones_mx z
WHERE pr.zone_id = z.id
  AND z.state_code = 'CDMX'
  AND pr.service_type = 'ride';

-- Update CDMX carpool rules
UPDATE public.pricing_rules_mx pr
SET base_fare = 8.00,
    per_km = 4.00,
    per_min = 1.80,
    min_fare = 30.00,
    booking_fee = 0,
    cancellation_fee = 25.00,
    night_multiplier = 1.25,
    weekend_multiplier = 1.10,
    platform_fee_percent = 20.00,
    driver_percent = 64.00,
    updated_at = NOW()
FROM public.pricing_zones_mx z
WHERE pr.zone_id = z.id
  AND z.state_code = 'CDMX'
  AND pr.service_type = 'carpool';

-- Update CDMX delivery rules
UPDATE public.pricing_rules_mx pr
SET base_fare = 9.00,
    per_km = 4.20,
    per_min = 1.90,
    min_fare = 35.00,
    booking_fee = 0,
    cancellation_fee = 28.00,
    platform_fee_percent = 20.00,
    driver_percent = 64.00,
    updated_at = NOW()
FROM public.pricing_zones_mx z
WHERE pr.zone_id = z.id
  AND z.state_code = 'CDMX'
  AND pr.service_type = 'delivery';

-- Update JAL (Guadalajara) rules
UPDATE public.pricing_rules_mx pr
SET base_fare = 9.00,
    per_km = 4.20,
    per_min = 1.90,
    min_fare = 36.00,
    booking_fee = 0,
    cancellation_fee = 28.00,
    night_multiplier = 1.20,
    weekend_multiplier = 1.10,
    platform_fee_percent = 20.00,
    driver_percent = 64.00,
    updated_at = NOW()
FROM public.pricing_zones_mx z
WHERE pr.zone_id = z.id
  AND z.state_code = 'JAL';

-- Update NL (Monterrey) rules
UPDATE public.pricing_rules_mx pr
SET base_fare = 10.00,
    per_km = 4.50,
    per_min = 2.00,
    min_fare = 38.00,
    booking_fee = 0,
    cancellation_fee = 30.00,
    night_multiplier = 1.20,
    weekend_multiplier = 1.10,
    platform_fee_percent = 20.00,
    driver_percent = 64.00,
    updated_at = NOW()
FROM public.pricing_zones_mx z
WHERE pr.zone_id = z.id
  AND z.state_code = 'NL';

-- Update the calculate_ride_fare function defaults to match new prices
CREATE OR REPLACE FUNCTION calculate_ride_fare(
    p_pickup_lat DECIMAL,
    p_pickup_lng DECIMAL,
    p_dropoff_lat DECIMAL,
    p_dropoff_lng DECIMAL,
    p_distance_km DECIMAL,
    p_duration_min DECIMAL,
    p_service_type TEXT DEFAULT 'ride',
    p_vehicle_type TEXT DEFAULT 'standard',
    p_is_night BOOLEAN DEFAULT FALSE,
    p_is_weekend BOOLEAN DEFAULT FALSE,
    p_surge_multiplier DECIMAL DEFAULT 1.00,
    p_tolls DECIMAL DEFAULT 0.00
)
RETURNS TABLE (
    zone_id BIGINT,
    zone_name TEXT,
    currency TEXT,
    base_fare DECIMAL,
    distance_amount DECIMAL,
    time_amount DECIMAL,
    booking_fee DECIMAL,
    subtotal_before_multipliers DECIMAL,
    night_multiplier DECIMAL,
    weekend_multiplier DECIMAL,
    surge_multiplier DECIMAL,
    surge_amount DECIMAL,
    tolls DECIMAL,
    subtotal DECIMAL,
    tax_rate DECIMAL,
    tax_amount DECIMAL,
    total DECIMAL,
    platform_fee DECIMAL,
    driver_earnings DECIMAL,
    min_fare_applied BOOLEAN
) AS $$
DECLARE
    v_pricing RECORD;
    v_base DECIMAL;
    v_distance_amount DECIMAL;
    v_time_amount DECIMAL;
    v_subtotal_pre DECIMAL;
    v_night_mult DECIMAL := 1.00;
    v_weekend_mult DECIMAL := 1.00;
    v_surge_amount DECIMAL := 0.00;
    v_subtotal DECIMAL;
    v_tax_rate DECIMAL := 0.16;
    v_tax DECIMAL;
    v_total DECIMAL;
    v_platform_fee DECIMAL;
    v_driver_earnings DECIMAL;
    v_min_fare_applied BOOLEAN := FALSE;
BEGIN
    -- Get pricing for pickup location
    SELECT * INTO v_pricing
    FROM get_pricing_for_location(p_pickup_lat, p_pickup_lng, p_service_type, p_vehicle_type);

    IF v_pricing IS NULL THEN
        -- Default pricing with NEW market-competitive values
        v_pricing := ROW(
            0::BIGINT, 'Default'::TEXT, 'MX'::TEXT,
            10.00, 4.50, 2.00, 38.00, 0.00,
            1.25, 1.10, 2.00, 20.00, 'MXN'::TEXT
        );
    END IF;

    -- Calculate base amounts
    v_base := v_pricing.base_fare;
    v_distance_amount := p_distance_km * v_pricing.per_km;
    v_time_amount := p_duration_min * v_pricing.per_min;
    v_subtotal_pre := v_base + v_distance_amount + v_time_amount + v_pricing.booking_fee;

    -- Apply multipliers
    IF p_is_night THEN
        v_night_mult := v_pricing.night_multiplier;
    END IF;

    IF p_is_weekend THEN
        v_weekend_mult := v_pricing.weekend_multiplier;
    END IF;

    -- Apply surge (capped at max)
    IF p_surge_multiplier > v_pricing.max_surge_multiplier THEN
        p_surge_multiplier := v_pricing.max_surge_multiplier;
    END IF;

    -- Calculate subtotal with multipliers
    v_subtotal := v_subtotal_pre * v_night_mult * v_weekend_mult * p_surge_multiplier;
    v_surge_amount := v_subtotal - (v_subtotal_pre * v_night_mult * v_weekend_mult);

    -- Add tolls
    v_subtotal := v_subtotal + p_tolls;

    -- Apply minimum fare
    IF v_subtotal < v_pricing.min_fare THEN
        v_subtotal := v_pricing.min_fare;
        v_min_fare_applied := TRUE;
    END IF;

    -- Calculate tax
    v_tax := ROUND(v_subtotal * v_tax_rate, 2);
    v_total := v_subtotal + v_tax;

    -- Calculate split (driver 64%, platform 20% - tax is separate via IVA)
    v_platform_fee := ROUND(v_subtotal * (v_pricing.platform_fee_percent / 100), 2);
    v_driver_earnings := v_subtotal - v_platform_fee;

    RETURN QUERY SELECT
        v_pricing.zone_id,
        v_pricing.zone_name,
        v_pricing.currency,
        v_base,
        v_distance_amount,
        v_time_amount,
        v_pricing.booking_fee,
        v_subtotal_pre,
        v_night_mult,
        v_weekend_mult,
        p_surge_multiplier,
        v_surge_amount,
        p_tolls,
        v_subtotal,
        v_tax_rate,
        v_tax,
        v_total,
        v_platform_fee,
        v_driver_earnings,
        v_min_fare_applied;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- VERIFICATION
-- ============================================================================
-- SELECT state_code, state_name, booking_type, country_code, base_fare, per_mile_rate, per_minute_rate, minimum_fare, driver_percentage, platform_percentage, tax_percentage, qr_point_value, carpool_discount_per_seat
-- FROM pricing_config WHERE country_code = 'MX' ORDER BY state_code, booking_type;
--
-- Expected: 32 states × 2 types (ride + carpool) = 64 rows
-- Total: ~64 MX entries in pricing_config
