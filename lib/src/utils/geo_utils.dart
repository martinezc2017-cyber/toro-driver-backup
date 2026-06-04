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
}
