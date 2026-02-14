-- =============================================================================
-- COMPETITIVE MX PRICING ALIGNMENT - Feb 2026
-- Aligns all 5 Mexico zones with Uber/DiDi market rates
-- =============================================================================
-- Source: Uber published rates per city, DiDi estimates, airport data
-- Strategy: Match Uber baseline, add booking_fee $5, free_wait 3min (Uber=2)
-- Moto: 0.85x (15% cheaper than standard, previously 0.80x was too cheap)
-- Tolls: passthrough to rider (same as Uber)
-- =============================================================================

-- CDMX (Zone: 01dd17ab) - Uber: Base $7, /km $3.57, /min $1.80, Min $35
UPDATE pricing_rules_mx SET
  base_fare = 8.00,
  per_km = 3.60,
  per_minute = 1.80,
  minimum_fare = 35.00,
  cancellation_fee = 35.00,
  airport_pickup_fee = 45,
  airport_dropoff_fee = 0,
  night_multiplier = 1.25,
  peak_multiplier = 1.50,
  weekend_multiplier = 1.10,
  holiday_multiplier = 1.30,
  bad_weather_multiplier = 1.25,
  max_surge_multiplier = 3.0,
  vehicle_moto_multiplier = 0.85,
  wait_per_minute = 1.80,
  free_wait_minutes = 3,
  booking_fee = 5,
  hourly_rate = 180,
  no_show_fee = 35,
  extra_stop_fee = 20,
  pet_fee = 35,
  toll_passthrough = true,
  updated_at = NOW()
WHERE zone_id = '01dd17ab-a741-4b1d-b1de-48044332f2ac';

-- Guadalajara (Zone: 742c1f71) - Uber: Base $8, /km $3.50, /min $1.70, Min $30
UPDATE pricing_rules_mx SET
  base_fare = 8.00,
  per_km = 3.50,
  per_minute = 1.70,
  minimum_fare = 30.00,
  cancellation_fee = 35.00,
  airport_pickup_fee = 45,
  airport_dropoff_fee = 0,
  night_multiplier = 1.20,
  peak_multiplier = 1.50,
  weekend_multiplier = 1.10,
  holiday_multiplier = 1.30,
  bad_weather_multiplier = 1.25,
  max_surge_multiplier = 3.0,
  vehicle_moto_multiplier = 0.85,
  wait_per_minute = 1.70,
  free_wait_minutes = 3,
  booking_fee = 5,
  hourly_rate = 160,
  no_show_fee = 35,
  extra_stop_fee = 20,
  pet_fee = 35,
  toll_passthrough = true,
  updated_at = NOW()
WHERE zone_id = '742c1f71-61bb-4a2b-81cd-c16e5ae10d79';

-- Monterrey (Zone: 4cd9e209) - Uber: Base $6.20, /km $4.25, /min $1.70, Min $29.41
UPDATE pricing_rules_mx SET
  base_fare = 6.50,
  per_km = 4.25,
  per_minute = 1.70,
  minimum_fare = 30.00,
  cancellation_fee = 30.00,
  airport_pickup_fee = 45,
  airport_dropoff_fee = 0,
  night_multiplier = 1.20,
  peak_multiplier = 1.50,
  weekend_multiplier = 1.10,
  holiday_multiplier = 1.30,
  bad_weather_multiplier = 1.25,
  max_surge_multiplier = 3.0,
  vehicle_moto_multiplier = 0.85,
  wait_per_minute = 1.70,
  free_wait_minutes = 3,
  booking_fee = 5,
  hourly_rate = 160,
  no_show_fee = 30,
  extra_stop_fee = 20,
  pet_fee = 35,
  toll_passthrough = true,
  updated_at = NOW()
WHERE zone_id = '4cd9e209-95ed-45e9-93b6-ef714119672e';

-- Tijuana (Zone: 9bdc6c9b) - Uber: Base $8.50, /km $4.70, /min $1.90, Min $35
UPDATE pricing_rules_mx SET
  base_fare = 8.50,
  per_km = 4.70,
  per_minute = 1.90,
  minimum_fare = 35.00,
  cancellation_fee = 30.00,
  airport_pickup_fee = 45,
  airport_dropoff_fee = 0,
  night_multiplier = 1.20,
  peak_multiplier = 1.50,
  weekend_multiplier = 1.10,
  holiday_multiplier = 1.30,
  bad_weather_multiplier = 1.25,
  max_surge_multiplier = 3.0,
  vehicle_moto_multiplier = 0.85,
  wait_per_minute = 1.90,
  free_wait_minutes = 3,
  booking_fee = 5,
  hourly_rate = 170,
  no_show_fee = 30,
  extra_stop_fee = 20,
  pet_fee = 35,
  toll_passthrough = true,
  updated_at = NOW()
WHERE zone_id = '9bdc6c9b-f726-48c2-bb94-693be4808257';

-- Cancun (Zone: 23c3715b) - Tourist premium zone, Uber avg $150-250 airport rides
UPDATE pricing_rules_mx SET
  base_fare = 10.00,
  per_km = 5.00,
  per_minute = 2.20,
  minimum_fare = 42.00,
  cancellation_fee = 35.00,
  airport_pickup_fee = 60,
  airport_dropoff_fee = 0,
  night_multiplier = 1.25,
  peak_multiplier = 1.50,
  weekend_multiplier = 1.15,
  holiday_multiplier = 1.35,
  bad_weather_multiplier = 1.25,
  max_surge_multiplier = 3.0,
  vehicle_moto_multiplier = 0.85,
  wait_per_minute = 2.20,
  free_wait_minutes = 3,
  booking_fee = 5,
  hourly_rate = 200,
  no_show_fee = 35,
  extra_stop_fee = 25,
  pet_fee = 40,
  toll_passthrough = true,
  updated_at = NOW()
WHERE zone_id = '23c3715b-919e-46e0-8c01-f2aba9ff858c';

-- =============================================================================
-- PRICING_CONFIG TABLE (fallback used by Flutter services)
-- =============================================================================

-- Global MX updates: moto 0.80→0.85, booking_fee 0→5, free_wait 5→3
UPDATE pricing_config SET
  vehicle_moto_multiplier = 0.85,
  booking_fee = 5,
  free_wait_minutes = 3,
  updated_at = NOW()
WHERE country_code = 'MX';

-- CDMX ride rates
UPDATE pricing_config SET
  base_fare = 8.00, per_mile_rate = 3.60, per_minute_rate = 1.80,
  minimum_fare = 35.00, cancellation_fee = 35.00, airport_fee = 45, wait_per_minute = 1.80
WHERE state_code = 'CDMX' AND country_code = 'MX' AND booking_type = 'ride';

-- CDMX carpool (~20% below ride)
UPDATE pricing_config SET
  base_fare = 6.50, per_mile_rate = 3.00, per_minute_rate = 1.50,
  minimum_fare = 28.00, cancellation_fee = 25.00, airport_fee = 45, wait_per_minute = 1.50
WHERE state_code = 'CDMX' AND country_code = 'MX' AND booking_type = 'carpool';

-- JAL ride rates
UPDATE pricing_config SET
  base_fare = 8.00, per_mile_rate = 3.50, per_minute_rate = 1.70,
  minimum_fare = 30.00, cancellation_fee = 35.00, airport_fee = 45, wait_per_minute = 1.70
WHERE state_code = 'JAL' AND country_code = 'MX' AND booking_type = 'ride';

-- JAL carpool
UPDATE pricing_config SET
  base_fare = 6.50, per_mile_rate = 2.90, per_minute_rate = 1.40,
  minimum_fare = 25.00, cancellation_fee = 25.00, airport_fee = 45, wait_per_minute = 1.40
WHERE state_code = 'JAL' AND country_code = 'MX' AND booking_type = 'carpool';

-- NL ride rates
UPDATE pricing_config SET
  base_fare = 6.50, per_mile_rate = 4.25, per_minute_rate = 1.70,
  minimum_fare = 30.00, cancellation_fee = 30.00, airport_fee = 45, wait_per_minute = 1.70
WHERE state_code = 'NL' AND country_code = 'MX' AND booking_type = 'ride';

-- NL carpool
UPDATE pricing_config SET
  base_fare = 5.50, per_mile_rate = 3.50, per_minute_rate = 1.40,
  minimum_fare = 25.00, cancellation_fee = 25.00, airport_fee = 45, wait_per_minute = 1.40
WHERE state_code = 'NL' AND country_code = 'MX' AND booking_type = 'carpool';

-- BC ride rates (Tijuana)
UPDATE pricing_config SET
  base_fare = 8.50, per_mile_rate = 4.70, per_minute_rate = 1.90,
  minimum_fare = 35.00, cancellation_fee = 30.00, airport_fee = 45, wait_per_minute = 1.90
WHERE state_code = 'BC' AND country_code = 'MX' AND booking_type = 'ride';

-- BC carpool
UPDATE pricing_config SET
  base_fare = 7.00, per_mile_rate = 3.90, per_minute_rate = 1.60,
  minimum_fare = 28.00, cancellation_fee = 25.00, airport_fee = 45, wait_per_minute = 1.60
WHERE state_code = 'BC' AND country_code = 'MX' AND booking_type = 'carpool';

-- QROO ride rates (Cancun - tourist premium)
UPDATE pricing_config SET
  base_fare = 10.00, per_mile_rate = 5.00, per_minute_rate = 2.20,
  minimum_fare = 42.00, cancellation_fee = 35.00, airport_fee = 60, wait_per_minute = 2.20
WHERE state_code = 'QROO' AND country_code = 'MX' AND booking_type = 'ride';

-- QROO carpool
UPDATE pricing_config SET
  base_fare = 8.00, per_mile_rate = 4.00, per_minute_rate = 1.80,
  minimum_fare = 34.00, cancellation_fee = 25.00, airport_fee = 60, wait_per_minute = 1.80
WHERE state_code = 'QROO' AND country_code = 'MX' AND booking_type = 'carpool';
