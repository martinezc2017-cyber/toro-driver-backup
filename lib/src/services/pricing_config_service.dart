import '../config/supabase_config.dart';
import '../core/logging/app_logger.dart';

/// Servicio para leer configuración de precios dinámicos desde Supabase
/// Los precios son configurados por el Admin y leídos en tiempo real
class PricingConfigService {
  static final PricingConfigService _instance = PricingConfigService._();
  static PricingConfigService get instance => _instance;
  PricingConfigService._();

  // Cache de configuración
  PricingConfig? _cachedConfig;
  DateTime? _lastFetch;
  static const Duration _cacheExpiry = Duration(minutes: 5);

  /// Obtener configuración de precios activa
  /// Lee de `pricing_config` en Supabase
  Future<PricingConfig> getConfig({String bookingType = 'ride'}) async {
    // Usar cache si es válido
    if (_cachedConfig != null && _lastFetch != null) {
      final elapsed = DateTime.now().difference(_lastFetch!);
      if (elapsed < _cacheExpiry) {
        return _cachedConfig!;
      }
    }

    try {
      final supabase = SupabaseConfig.client;

      final response = await supabase
          .from('pricing_config')
          .select()
          .eq('booking_type', bookingType)
          .eq('is_active', true)
          .maybeSingle();

      if (response != null) {
        _cachedConfig = PricingConfig.fromJson(response);
        _lastFetch = DateTime.now();
        AppLogger.log('PRICING -> Config loaded: ${_cachedConfig!.platformFeePercent}% platform fee');
        return _cachedConfig!;
      }

      // NO HAY FALLBACK - Error si no hay config
      AppLogger.log('PRICING -> ⚠️ NO CONFIG FOUND - Configure pricing in Admin Web');
      throw Exception('No pricing configured for $bookingType. Contact admin.');
    } catch (e) {
      AppLogger.log('PRICING -> Error loading config: $e');
      rethrow; // NO FALLBACK - propagar error
    }
  }

  /// Calcular tarifa de viaje
  Future<FareCalculation> calculateFare({
    required double distanceKm,
    required int estimatedMinutes,
    String bookingType = 'ride',
  }) async {
    final config = await getConfig(bookingType: bookingType);

    double fare = config.baseFare;
    fare += distanceKm * config.perKmRate;
    fare += estimatedMinutes * config.perMinuteRate;

    // Aplicar tarifa mínima
    if (fare < config.minimumFare) {
      fare = config.minimumFare;
    }

    // Calcular split
    final platformFee = fare * (config.platformFeePercent / 100);
    final driverEarnings = fare - platformFee;

    return FareCalculation(
      totalFare: fare,
      platformFee: platformFee,
      driverEarnings: driverEarnings,
      platformFeePercent: config.platformFeePercent,
    );
  }

  /// Calcular ganancias del driver desde una tarifa
  Future<double> calculateDriverEarnings(double fare, {String bookingType = 'ride'}) async {
    final config = await getConfig(bookingType: bookingType);
    final platformFee = fare * (config.platformFeePercent / 100);
    return fare - platformFee;
  }

  /// Invalidar cache (cuando Admin actualiza precios)
  void invalidateCache() {
    _cachedConfig = null;
    _lastFetch = null;
    AppLogger.log('PRICING -> Cache invalidated');
  }
}

/// Modelo de configuración de precios
class PricingConfig {
  final String bookingType;
  final double baseFare;
  final double perKmRate;
  final double perMinuteRate;
  final double minimumFare;
  final double platformFeePercent;
  final double cancellationFee;
  final bool isActive;

  PricingConfig({
    required this.bookingType,
    required this.baseFare,
    required this.perKmRate,
    required this.perMinuteRate,
    required this.minimumFare,
    required this.platformFeePercent,
    required this.cancellationFee,
    required this.isActive,
  });

  factory PricingConfig.fromJson(Map<String, dynamic> json) {
    return PricingConfig(
      bookingType: json['booking_type'] ?? 'ride',
      baseFare: _parseDouble(json['base_fare'] ?? json['ride_base_fare']),
      perKmRate: _parseDouble(json['per_km_rate'] ?? json['ride_per_mile']),
      perMinuteRate: _parseDouble(json['per_minute_rate'] ?? json['ride_per_minute']),
      minimumFare: _parseDouble(json['minimum_fare'] ?? json['ride_minimum_fare']),
      platformFeePercent: _parseDouble(json['platform_fee_percent'] ?? 20.0),
      cancellationFee: _parseDouble(json['cancellation_fee'] ?? json['ride_cancellation_fee']),
      isActive: json['is_active'] ?? true,
    );
  }

  /// @deprecated NO USAR - No hay fallbacks globales
  /// Si se necesita pricing, DEBE existir en pricing_config para el estado
  @Deprecated('NO FALLBACKS - Configure pricing in Admin Web for each state')
  factory PricingConfig.defaults() {
    throw UnimplementedError(
      'PricingConfig.defaults() is deprecated. '
      'All pricing must be configured per-state in Admin Web → Pricing.',
    );
  }

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  /// Porcentaje que gana el driver (100 - platformFee)
  double get driverPercent => 100 - platformFeePercent;
}

/// Resultado del cálculo de tarifa
class FareCalculation {
  final double totalFare;
  final double platformFee;
  final double driverEarnings;
  final double platformFeePercent;

  FareCalculation({
    required this.totalFare,
    required this.platformFee,
    required this.driverEarnings,
    required this.platformFeePercent,
  });

  @override
  String toString() {
    return 'Fare: \$${totalFare.toStringAsFixed(2)} | '
        'Platform: \$${platformFee.toStringAsFixed(2)} (${platformFeePercent.toStringAsFixed(0)}%) | '
        'Driver: \$${driverEarnings.toStringAsFixed(2)}';
  }
}
