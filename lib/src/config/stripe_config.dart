import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  static const String publishableKeyUS = 'pk_test_51Ti6y0JjHJ2LZ4e2BXcAfNfud1ZYhSkhLDT5JM9PUAMY6Svda8IiGUwS3FhoDyy5nSKn4cHcDlktiBqWz4ovMB0X00QZLD93rY';

  // Mexico Stripe Account — MUST match STRIPE_MX_SECRET_KEY (the account that runs
  // charges, vendor + driver Connect, and where PALOMA's money lands). That account is
  // 51Ti6y0... (object fragment JjHJ2LZ4e2). It was baked as 51TgufO — a STALE account
  // the apps kept while the server moved to Ti6y0 — causing "No such payment_intent"
  // and driver Connect onboarding/payouts drifting to the wrong platform.
  // TODO(single-source): fetch this from get-stripe-config at runtime so it can never
  // drift from the server account again (no hardcoded key in any app).
  static const String publishableKeyMX = 'pk_test_51Ti6y0JjHJ2LZ4e2BXcAfNfud1ZYhSkhLDT5JM9PUAMY6Svda8IiGUwS3FhoDyy5nSKn4cHcDlktiBqWz4ovMB0X00QZLD93rY';

  static const String merchantId = 'merchant.com.toro.driver';

  // Current active provider (can be changed at runtime)
  static StripeProvider _currentProvider = StripeProvider.us;

  /// pk traída de `integration_config` (FUENTE ÚNICA, editable en el admin sin
  /// recompilar). Si está seteada, gana sobre las hardcodeadas de arriba. Así se
  /// resuelve el TODO(single-source) y ya no puede driftear del server.
  static String? _serverPk;

  /// Carga la pk activa desde integration_config (según modo test/live).
  static Future<void> loadServerPk() async {
    try {
      final cfg = await Supabase.instance.client.rpc('get_integration_config');
      final pk = (cfg is Map ? cfg['stripe_publishable_key'] as String? : null);
      if (pk != null && pk.isNotEmpty) _serverPk = pk;
    } catch (_) {/* si falla, usa las hardcodeadas de fallback */}
  }

  /// Get the current provider
  static StripeProvider get currentProvider => _currentProvider;

  /// Get publishable key for a specific provider
  static String getPublishableKey(StripeProvider provider) {
    if (_serverPk != null && _serverPk!.isNotEmpty) return _serverPk!;
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
    await loadServerPk(); // fuente única: pk desde integration_config
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

  /// Detect provider from coordinates (Mexico or USA).
  /// KEEP IN SYNC with rider app `UnifiedPricingService._detectCountryImpl`
  /// (toro-rider-web/lib/core/services/unified_pricing_service.dart).
  /// Border bounds must match across apps or a single trip will be classified
  /// differently by rider vs driver, causing pricing/currency mismatch.
  static StripeProvider detectProviderFromLocation(double lat, double lng) {
    const mexicoLatMin = 14.5;
    const mexicoLatMax = 32.7;
    const mexicoLngMin = -118.4;
    const mexicoLngMax = -86.7;

    if (lat >= mexicoLatMin && lat <= mexicoLatMax &&
        lng >= mexicoLngMin && lng <= mexicoLngMax) {
      // Border refinement — must match rider app exactly.
      // Texas/NM/AZ southern band (below 31.8°, west of -97°)
      if (lat < 31.8 && lng < -97.0) return StripeProvider.mx;
      // Baja California (Tijuana ~32.5, Mexicali ~32.67)
      if (lat < 32.72 && lng < -114.7) return StripeProvider.mx;
      // Central/Southern Mexico (below 25°)
      if (lat < 25.0) return StripeProvider.mx;
    }

    return StripeProvider.us;
  }
}
