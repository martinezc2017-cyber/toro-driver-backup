import 'package:flutter_stripe/flutter_stripe.dart';

/// Stripe provider for multi-country support
enum StripeProvider {
  us,
  mx;

  String get code => name;
  String get displayName => this == us ? 'United States' : 'México';
  String get currency => this == us ? 'USD' : 'MXN';
}

class StripeConfig {
  // USA Stripe Account
  static const String publishableKeyUS = 'pk_test_51SjZ6ZJkPkRlUpHxaozvdbpgbP8lRScfj5dLpcKv0AuUrjpcv73TnXrGk4Pq6NJzFU0vepYKxXiF0hHZBXXlPnWy009dN2qG0E';

  // Mexico Stripe Account
  static const String publishableKeyMX = 'pk_test_51SvLIZJL6dZ5MsYqvDAUIhO74kK7r93XLcYSlTLP5oupLb6lwhLe4XppoSOUWuhkNenCvcdo6xQ7DBkLO3yWRpVT000m01MebB';

  static const String merchantId = 'merchant.com.toro.driver';

  // Current active provider (can be changed at runtime)
  static StripeProvider _currentProvider = StripeProvider.us;

  /// Get the current provider
  static StripeProvider get currentProvider => _currentProvider;

  /// Get publishable key for a specific provider
  static String getPublishableKey(StripeProvider provider) {
    return provider == StripeProvider.mx ? publishableKeyMX : publishableKeyUS;
  }

  /// Get publishable key for current provider
  static String get publishableKey => getPublishableKey(_currentProvider);

  /// Initialize Stripe with default provider (US)
  static Future<void> initialize() async {
    await initializeWithProvider(StripeProvider.us);
  }

  /// Initialize Stripe with a specific provider
  static Future<void> initializeWithProvider(StripeProvider provider) async {
    _currentProvider = provider;
    Stripe.publishableKey = getPublishableKey(provider);
    Stripe.merchantIdentifier = merchantId;
    await Stripe.instance.applySettings();
  }

  /// Switch to a different provider at runtime
  static Future<void> switchProvider(StripeProvider provider) async {
    if (_currentProvider != provider) {
      _currentProvider = provider;
      Stripe.publishableKey = getPublishableKey(provider);
      await Stripe.instance.applySettings();
    }
  }

  /// Detect provider from coordinates (Mexico or USA)
  static StripeProvider detectProviderFromLocation(double lat, double lng) {
    // Mexico bounds (approximate)
    const mexicoLatMin = 14.5;
    const mexicoLatMax = 32.7;
    const mexicoLngMin = -118.4;
    const mexicoLngMax = -86.7;

    if (lat >= mexicoLatMin && lat <= mexicoLatMax &&
        lng >= mexicoLngMin && lng <= mexicoLngMax) {
      // More precise check for border areas
      if (lat < 31.5 && lng < -97.0) return StripeProvider.mx;
      if (lat < 32.5 && lng < -114.0) return StripeProvider.mx;
      if (lat < 25.0) return StripeProvider.mx;
    }

    return StripeProvider.us;
  }
}
