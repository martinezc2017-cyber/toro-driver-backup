-- Enable QR point bonuses for Mexico (same as US: 1% per QR level)
-- SplitCalculator._calculateQRBonus() multiplies by qr_point_value
-- Each QR level = 1% extra earnings on driver's base
UPDATE pricing_config SET qr_point_value = 1.0 WHERE country_code = 'MX';
