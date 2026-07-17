import '../config/stripe_config.dart';

/// Canonical geo utilities — single source of truth for country/border detection.
/// All country-from-coordinates checks must use this class.
class GeoUtils {
  GeoUtils._();

  /// Returns true if coordinates are in Mexico.
  /// Uses [StripeConfig.detectProviderFromLocation] which handles border zones correctly.
  static bool isMexico(double lat, double lng) {
    return StripeConfig.detectProviderFromLocation(lat, lng) == StripeProvider.mx;
  }

  /// Returns 'MX' or 'US' from coordinates.
  static String countryCode(double lat, double lng) {
    return isMexico(lat, lng) ? 'MX' : 'US';
  }

  /// Returns state code from coordinates (bounding box, no API call).
  /// For Mexico returns MX state (BC, SON, SIN, JAL, CDMX…).
  /// For US returns state (AZ, CA, TX, NV, NM, CO, UT…). Fallback: AZ.
  static String stateCode(double lat, double lng) {
    if (isMexico(lat, lng)) {
      if (lat >= 28.0 && lat <= 32.7 && lng >= -117.1 && lng <= -114.8) return 'BC';
      if (lat >= 26.0 && lat <= 30.5 && lng >= -115.0 && lng <= -109.5) return 'SON';
      if (lat >= 22.5 && lat <= 27.0 && lng >= -109.5 && lng <= -105.3) return 'SIN';
      if (lat >= 19.0 && lat <= 22.5 && lng >= -105.8 && lng <= -103.7) return 'JAL';
      if (lat >= 18.5 && lat <= 21.0 && lng >= -100.5 && lng <= -98.0)  return 'CDMX';
      return 'MX';
    }
    if (lat >= 31.3 && lat <= 37.0 && lng >= -115.0 && lng <= -109.0) return 'AZ';
    if (lat >= 32.5 && lat <= 42.0 && lng >= -124.5 && lng <= -114.0) return 'CA';
    if (lat >= 25.8 && lat <= 36.5 && lng >= -106.6 && lng <= -93.5)  return 'TX';
    if (lat >= 35.0 && lat <= 42.0 && lng >= -120.0 && lng <= -114.0) return 'NV';
    if (lat >= 31.3 && lat <= 37.0 && lng >= -109.0 && lng <= -103.0) return 'NM';
    if (lat >= 37.0 && lat <= 41.0 && lng >= -109.0 && lng <= -102.0) return 'CO';
    if (lat >= 37.0 && lat <= 42.0 && lng >= -114.0 && lng <= -109.0) return 'UT';
    return 'AZ';
  }
}
