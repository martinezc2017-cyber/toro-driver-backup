import 'package:flutter/foundation.dart';
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
  // US Stripe Account — LIVE (TORO USA 51SjZ6OR). Fallback if integration_config
  // RPC fails. Must match the pk_live in integration_config table.
  static const String publishableKeyUS =
      'pk_live_51SjZ6OR8wYuQaWnUJmQDgB6Dwp8yaF3ZurQEbsv85pJGss6rwKKnzdon4HOhzQRfbXQXi6hgqS4yJAQM68rPZGfh00PbhvMhXG';

  // Mexico Stripe Account — LIVE (TORO MEXICO 51SvLIZJL). Debe matchear la sk_live que
  // usan las funciones (STRIPE_MX_SECRET_KEY). La fuente REAL es integration_config en
  // runtime (loadServerPk); esto es SOLO el fallback si el server no responde -> aun asi
  // arranca en LIVE, nunca en test.
  static const String publishableKeyMX =
      'pk_live_51SvLIZJL6dZ5MsYqTRaH23owX5omYbKUoW83mHNw4qFzKC6CS2H3PEjgAJNu5O4KEWmdjWdrzmqmkQDMJGbXAn2N00CmGSJNbN';

  static const String merchantId = 'merchant.com.toro.driver';

  // Current active provider (can be changed at runtime)
  static StripeProvider _currentProvider = StripeProvider.us;

  /// pk traída de `integration_config` (FUENTE ÚNICA, editable en el admin sin
  /// recompilar). Si está seteada, gana sobre las hardcodeadas de arriba. Así se
  /// resuelve el TODO(single-source) y ya no puede driftear del server.
  static final Map<StripeProvider, String> _serverPks = {};

  /// Carga la pk activa desde integration_config (según modo test/live).
  static Future<void> loadServerPk(StripeProvider provider) async {
    try {
      final cfg = await Supabase.instance.client.rpc(
        'get_integration_config',
        params: {'p_country': provider == StripeProvider.mx ? 'MX' : 'US'},
      );
      final pk = (cfg is Map ? cfg['stripe_publishable_key'] as String? : null);
      if (pk != null && pk.isNotEmpty) _serverPks[provider] = pk;
    } catch (e) {
      debugPrint('STRIPE_CONFIG -> loadServerPk($provider) failed: $e — using hardcoded fallback');
    }
  }

  /// Get the current provider
  static StripeProvider get currentProvider => _currentProvider;

  /// Get publishable key for a specific provider
  static String getPublishableKey(StripeProvider provider) {
    final serverPk = _serverPks[provider];
    if (serverPk != null && serverPk.isNotEmpty) return serverPk;
    return provider == StripeProvider.mx ? publishableKeyMX : publishableKeyUS;
  }

  /// Get publishable key for current provider
  static String get publishableKey => getPublishableKey(_currentProvider);

  // 12 oct 2026: al abrir la app, DriverProvider llama switchProvider ANTES de que
  // PaymentService.initialize ponga la primera pk. switchProvider leía
  // `Stripe.publishableKey`, que TRUENA si aún no hay pk → tumbaba la carga del conductor
  // (driver = null: sin nombre, sin aviso de documentos, sin notificaciones). Y si
  // initialize terminaba después, dejaba la pk de US a un conductor de MX.
  // Ahora: se recuerda la pk aplicada (sin leer el getter) y gana la ÚLTIMA elección.
  static String? _appliedKey;
  static bool _paisElegido = false;
  static int _turno = 0;

  /// Initialize Stripe with default provider (US), salvo que el país del conductor ya se eligió.
  static Future<void> initialize() async {
    await _aplicar(_paisElegido ? _currentProvider : StripeProvider.us);
  }

  /// Initialize Stripe with a specific provider
  static Future<void> initializeWithProvider(StripeProvider provider) async {
    _paisElegido = true;
    await _aplicar(provider);
  }

  /// Switch to a different provider at runtime
  static Future<void> switchProvider(StripeProvider provider) async {
    _paisElegido = true;
    await _aplicar(provider);
  }

  static Future<void> _aplicar(StripeProvider provider) async {
    final turno = ++_turno;
    _currentProvider = provider;
    await loadServerPk(provider);
    if (turno != _turno) return; // llegó otra elección mientras cargaba: gana la última
    final key = getPublishableKey(provider);
    if (key.isEmpty) {
      debugPrint('STRIPE_CONFIG -> ERROR: No publishable key for $provider — Stripe will NOT work');
      return;
    }
    if (_appliedKey == key) return;
    Stripe.publishableKey = key;
    Stripe.merchantIdentifier = merchantId;
    await Stripe.instance.applySettings();
    _appliedKey = key;
    debugPrint('STRIPE_CONFIG -> Initialized with $provider (key=${key.substring(0, 12)}...)');
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

    if (lat >= mexicoLatMin &&
        lat <= mexicoLatMax &&
        lng >= mexicoLngMin &&
        lng <= mexicoLngMax) {
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
