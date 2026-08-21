/// Canonical money formatter for TORO driver app.
///
/// MX/MXN displays whole pesos (no centavos). US/USD displays 2 decimals.
/// Currency symbol is `$` for both (currency disambiguation lives in column
/// headers or chips, not next to every value).
///
/// Usage:
///   formatMoney(123.0, country: 'MX')      → '$123'
///   formatMoney(123.45, country: 'US')     → '$123.45'
///   formatMoney(123.45, country: 'MX')     → '$123'  (rounded)
///   formatMoney(null)                       → '$0'
library;

/// Currency decimal places by country code.
int currencyDecimals(String? countryCode) {
  return (countryCode?.toUpperCase() ?? userCountry()) == 'MX' ? 0 : 2;
}

/// App-level current user country. Set after driver profile loads.
String _cachedUserCountry = 'US';

/// Read the cached driver country (defaults to US).
String userCountry() => _cachedUserCountry;

/// Set the current driver country. Call after profile load / sign-in.
void setUserCountry(String? code) {
  if (code == null || code.isEmpty) return;
  _cachedUserCountry = code.toUpperCase();
}

/// Format an amount as canonical money string for the given country.
String formatMoney(num? amount, {String? country}) {
  final v = (amount ?? 0).toDouble();
  final d = currencyDecimals(country);
  return '\$${v.toStringAsFixed(d)}';
}

/// Format with a thousands separator.
String formatMoneyGrouped(num? amount, {String? country}) {
  final v = (amount ?? 0).toDouble();
  final d = currencyDecimals(country);
  final fixed = v.toStringAsFixed(d);
  final parts = fixed.split('.');
  final intPart = parts[0];
  final buffer = StringBuffer();
  for (int i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0 && intPart[i] != '-') {
      buffer.write(',');
    }
    buffer.write(intPart[i]);
  }
  if (parts.length > 1) {
    buffer.write('.');
    buffer.write(parts[1]);
  }
  return '\$$buffer';
}

/// Format an amount as percentage with sensible decimals.
String formatPercent(num? value, {int decimals = 1}) {
  return '${(value ?? 0).toStringAsFixed(decimals)}%';
}

String currencyCode({String? country}) =>
    (country?.toUpperCase() ?? userCountry()) == 'MX' ? 'MXN' : 'USD';

String distanceUnit({String? country}) =>
    (country?.toUpperCase() ?? userCountry()) == 'MX' ? 'km' : 'mi';

/// Convert a canonical kilometer value to the user's display unit.
double distanceFromKilometers(num? kilometers, {String? country}) {
  final km = (kilometers ?? 0).toDouble();
  final isMx = (country?.toUpperCase() ?? userCountry()) == 'MX';
  return isMx ? km : km * 0.621371;
}

/// Convert a canonical price-per-kilometer value to the local display unit.
///
/// Pricing remains stored per kilometer in Supabase. US drivers enter and see
/// a price per mile, while MX drivers continue to use a price per kilometer.
double pricePerKilometerToDisplay(num? pricePerKilometer, {String? country}) {
  final perKm = (pricePerKilometer ?? 0).toDouble();
  final isMx = (country?.toUpperCase() ?? userCountry()) == 'MX';
  return isMx ? perKm : perKm / 0.621371;
}

/// Convert a locally displayed price back to canonical price per kilometer.
double displayPriceToPerKilometer(num? displayedPrice, {String? country}) {
  final localPrice = (displayedPrice ?? 0).toDouble();
  final isMx = (country?.toUpperCase() ?? userCountry()) == 'MX';
  return isMx ? localPrice : localPrice * 0.621371;
}

/// Format a canonical price per kilometer using the user's local unit.
String formatPricePerDistance(num? pricePerKilometer, {String? country}) {
  final localPrice = pricePerKilometerToDisplay(
    pricePerKilometer,
    country: country,
  );
  return '${formatMoney(localPrice, country: country)} '
      '${currencyCode(country: country)}/${distanceUnit(country: country)}';
}

/// Format a distance value. Input is always kilometers.
/// MX shows km, US shows miles. Always 1 decimal.
String formatDistance(num? kilometers, {String? country, int decimals = 1}) {
  final isMx = (country?.toUpperCase() ?? userCountry()) == 'MX';
  final value = distanceFromKilometers(kilometers, country: country);
  return '${value.toStringAsFixed(decimals)} ${isMx ? 'km' : 'mi'}';
}

/// Format a distance whose canonical input is meters.
///
/// MX uses meters/kilometers. US uses feet/miles so turn-by-turn navigation
/// never shows metric instructions to a US driver.
String formatDistanceFromMeters(
  num? meters, {
  String? country,
  int decimals = 1,
}) {
  final valueMeters = (meters ?? 0).toDouble();
  final isMx = (country?.toUpperCase() ?? userCountry()) == 'MX';
  if (isMx) {
    if (valueMeters < 1000) return '${valueMeters.round()} m';
    return '${(valueMeters / 1000).toStringAsFixed(decimals)} km';
  }

  if (valueMeters < 1609.344) {
    return '${(valueMeters * 3.28084).round()} ft';
  }
  return '${(valueMeters / 1609.344).toStringAsFixed(decimals)} mi';
}

/// Format a distance value where input is in miles.
/// MX converts to km, US keeps miles. Always 1 decimal.
String formatDistanceFromMiles(
  num? miles, {
  String? country,
  int decimals = 1,
}) {
  final mi = (miles ?? 0).toDouble();
  final isMx = (country?.toUpperCase() ?? userCountry()) == 'MX';
  if (isMx) return '${(mi / 0.621371).toStringAsFixed(decimals)} km';
  return '${mi.toStringAsFixed(decimals)} mi';
}
