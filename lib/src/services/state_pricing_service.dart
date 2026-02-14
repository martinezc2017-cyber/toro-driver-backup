import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../core/logging/app_logger.dart';

// =============================================================================
// STATE-BASED PRICING SERVICE - DRIVER APP
// =============================================================================
// REGLAS ABSOLUTAS:
// 1. Apps SOLO pueden LEER precios - JAMÁS escribir
// 2. Pricing es PER-STATE (state_code + booking_type)
// 3. Si estado no tiene pricing activo → ERROR (no fallback global)
// 4. Driver App lee earnings de driver_earnings, pero necesita split config
// 5. Mantener sincronizado con toro/lib/core/services/state_pricing_service.dart
// =============================================================================

/// Error cuando un estado no tiene pricing configurado
class NoPricingConfiguredError implements Exception {
  final String stateCode;
  final String bookingType;
  final String message;

  NoPricingConfiguredError(this.stateCode, this.bookingType)
      : message = 'No pricing configured for state $stateCode and type $bookingType. '
            'Contact admin to configure pricing in Admin Web → Pricing.';

  @override
  String toString() => message;
}

/// Booking types soportados
enum BookingType {
  ride,
  carpool,
  delivery;

  String get value => name;

  static BookingType fromString(String s) {
    switch (s.toLowerCase()) {
      case 'ride':
        return BookingType.ride;
      case 'carpool':
        return BookingType.carpool;
      case 'delivery':
        return BookingType.delivery;
      default:
        return BookingType.ride;
    }
  }
}

/// Configuración de pricing por estado
/// Inmutable - representa un snapshot de pricing_config
@immutable
class StatePricing {
  final String stateCode;
  final String stateName;
  final String bookingType;
  final String countryCode;

  // === TARIFAS BASE ===
  final double baseFare;
  final double perMileRate;
  final double perMinuteRate;
  final double minimumFare;
  final double bookingFee;
  final double serviceFee;
  final double cancellationFee;

  // === SPLIT (%) ===
  final double driverPercentage;
  final double platformPercentage;
  final double insurancePercentage;
  final double taxPercentage;

  // === MULTIPLICADORES ===
  final double peakMultiplier;
  final double nightMultiplier;
  final double weekendMultiplier;

  // === CARPOOL ===
  final double carpoolDiscountPerSeat;
  final double carpoolMaxDiscount;

  // === QR POINTS ===
  final double qrPointValue;

  // === TNC TAX (Government Fee) ===
  // Flat fee per trip charged by government, separate from sales tax
  // Examples: CA $0.10-$0.35, Chicago $1.25-$3.00, NYC $2.75
  final double tncTaxPerTrip;

  // === VARIABLE PLATFORM TIERS (Toro Nivelar) ===
  final bool variablePlatformEnabled;
  final double platformTier1MaxFare;
  final double platformTier1Percent;
  final double platformTier2MaxFare;
  final double platformTier2Percent;
  final double platformTier3MaxFare;
  final double platformTier3Percent;
  final double platformTier4Percent;

  // === METADATA ===
  final bool isActive;
  final DateTime updatedAt;

  /// Whether per_mile_rate is actually per-km (true for MX)
  bool get usesKilometers => countryCode == 'MX';

  const StatePricing({
    required this.stateCode,
    required this.stateName,
    required this.bookingType,
    this.countryCode = 'MX',
    required this.baseFare,
    required this.perMileRate,
    required this.perMinuteRate,
    required this.minimumFare,
    required this.bookingFee,
    required this.serviceFee,
    required this.cancellationFee,
    required this.driverPercentage,
    required this.platformPercentage,
    required this.insurancePercentage,
    required this.taxPercentage,
    required this.peakMultiplier,
    required this.nightMultiplier,
    required this.weekendMultiplier,
    required this.carpoolDiscountPerSeat,
    required this.carpoolMaxDiscount,
    required this.qrPointValue,
    required this.tncTaxPerTrip,
    this.variablePlatformEnabled = false,
    this.platformTier1MaxFare = 10.0,
    this.platformTier1Percent = 5.0,
    this.platformTier2MaxFare = 20.0,
    this.platformTier2Percent = 15.0,
    this.platformTier3MaxFare = 35.0,
    this.platformTier3Percent = 23.4,
    this.platformTier4Percent = 25.0,
    required this.isActive,
    required this.updatedAt,
  });

  /// Crear desde JSON de pricing_config
  factory StatePricing.fromJson(Map<String, dynamic> json) {
    return StatePricing(
      stateCode: json['state_code']?.toString() ?? '',
      stateName: json['state_name']?.toString() ?? '',
      bookingType: json['booking_type']?.toString() ?? 'ride',
      countryCode: json['country_code']?.toString() ?? 'MX',
      baseFare: (json['base_fare'] as num?)?.toDouble() ?? 0,
      perMileRate: (json['per_mile_rate'] as num?)?.toDouble() ?? 0,
      perMinuteRate: (json['per_minute_rate'] as num?)?.toDouble() ?? 0,
      minimumFare: (json['minimum_fare'] as num?)?.toDouble() ?? 0,
      bookingFee: (json['booking_fee'] as num?)?.toDouble() ?? 0,
      serviceFee: (json['service_fee'] as num?)?.toDouble() ?? 0,
      cancellationFee: (json['cancellation_fee'] as num?)?.toDouble() ?? 0,
      driverPercentage: (json['driver_percentage'] as num?)?.toDouble() ?? 0,
      platformPercentage: (json['platform_percentage'] as num?)?.toDouble() ?? 0,
      insurancePercentage: (json['insurance_percentage'] as num?)?.toDouble() ?? 0,
      taxPercentage: (json['tax_percentage'] as num?)?.toDouble() ?? 0,
      peakMultiplier: (json['peak_multiplier'] as num?)?.toDouble() ?? 1.0,
      nightMultiplier: (json['night_multiplier'] as num?)?.toDouble() ?? 1.0,
      weekendMultiplier: (json['weekend_multiplier'] as num?)?.toDouble() ?? 1.0,
      carpoolDiscountPerSeat: (json['carpool_discount_per_seat'] as num?)?.toDouble() ?? 0,
      carpoolMaxDiscount: (json['carpool_max_discount'] as num?)?.toDouble() ?? 0,
      qrPointValue: (json['qr_point_value'] as num?)?.toDouble() ?? 1,
      tncTaxPerTrip: (json['tnc_tax_per_trip'] as num?)?.toDouble() ?? 0,
      variablePlatformEnabled: json['variable_platform_enabled'] == true,
      platformTier1MaxFare: (json['platform_tier_1_max_fare'] as num?)?.toDouble() ?? 10.0,
      platformTier1Percent: (json['platform_tier_1_percent'] as num?)?.toDouble() ?? 5.0,
      platformTier2MaxFare: (json['platform_tier_2_max_fare'] as num?)?.toDouble() ?? 20.0,
      platformTier2Percent: (json['platform_tier_2_percent'] as num?)?.toDouble() ?? 15.0,
      platformTier3MaxFare: (json['platform_tier_3_max_fare'] as num?)?.toDouble() ?? 35.0,
      platformTier3Percent: (json['platform_tier_3_percent'] as num?)?.toDouble() ?? 23.4,
      platformTier4Percent: (json['platform_tier_4_percent'] as num?)?.toDouble() ?? 25.0,
      isActive: json['is_active'] == true,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'].toString())
          : DateTime.now(),
    );
  }

  /// Convertir a snapshot para guardar en transactions
  Map<String, dynamic> toSnapshot() {
    return {
      'state_code': stateCode,
      'state_name': stateName,
      'booking_type': bookingType,
      'country_code': countryCode,
      'base_fare': baseFare,
      'per_mile_rate': perMileRate,
      'per_minute_rate': perMinuteRate,
      'minimum_fare': minimumFare,
      'booking_fee': bookingFee,
      'service_fee': serviceFee,
      'cancellation_fee': cancellationFee,
      'driver_percentage': driverPercentage,
      'platform_percentage': platformPercentage,
      'insurance_percentage': insurancePercentage,
      'tax_percentage': taxPercentage,
      'peak_multiplier': peakMultiplier,
      'night_multiplier': nightMultiplier,
      'weekend_multiplier': weekendMultiplier,
      'carpool_discount_per_seat': carpoolDiscountPerSeat,
      'carpool_max_discount': carpoolMaxDiscount,
      'qr_point_value': qrPointValue,
      'tnc_tax_per_trip': tncTaxPerTrip,
      'captured_at': DateTime.now().toIso8601String(),
    };
  }

  /// Validar que el split suma 100%
  bool get isValidSplit {
    final total = driverPercentage + platformPercentage + insurancePercentage + taxPercentage;
    return (total - 100).abs() < 0.01; // Tolerancia de 0.01%
  }

  /// Convertir a SplitConfig para uso con SplitCalculator
  Map<String, dynamic> toSplitConfig() {
    return {
      'platform_fee_percent': platformPercentage,
      'driver_percentage': driverPercentage,
      'insurance_percentage': insurancePercentage,
      'tax_percentage': taxPercentage,
      'qr_point_value': qrPointValue,
      'tnc_tax_per_trip': tncTaxPerTrip,
      'variable_platform_enabled': variablePlatformEnabled,
      'platform_tier_1_max_fare': platformTier1MaxFare,
      'platform_tier_1_percent': platformTier1Percent,
      'platform_tier_2_max_fare': platformTier2MaxFare,
      'platform_tier_2_percent': platformTier2Percent,
      'platform_tier_3_max_fare': platformTier3MaxFare,
      'platform_tier_3_percent': platformTier3Percent,
      'platform_tier_4_percent': platformTier4Percent,
    };
  }
}

/// Servicio de pricing por estado - DRIVER APP
/// SOLO LECTURA - jamás escribe en pricing_config
class StatePricingService {
  static final StatePricingService _instance = StatePricingService._internal();
  static StatePricingService get instance => _instance;
  StatePricingService._internal();

  // Cache por state_code + booking_type
  final Map<String, StatePricing> _cache = {};
  DateTime? _lastCacheRefresh;
  static const _cacheMaxAge = Duration(minutes: 5);
  RealtimeChannel? _realtimeChannel;

  /// Obtener pricing para un estado y tipo de booking
  /// LANZA NoPricingConfiguredError si no existe
  Future<StatePricing> getPricing({
    required String stateCode,
    required BookingType bookingType,
  }) async {
    final cacheKey = '${stateCode}_${bookingType.value}';

    // Verificar cache
    if (_isCacheValid() && _cache.containsKey(cacheKey)) {
      AppLogger.log('STATE_PRICING_DRV -> Cache hit: $cacheKey');
      return _cache[cacheKey]!;
    }

    // Fetch de Supabase
    AppLogger.log('STATE_PRICING_DRV -> Fetching: $stateCode / ${bookingType.value}');

    final response = await SupabaseConfig.client
        .from('pricing_config')
        .select()
        .eq('state_code', stateCode.toUpperCase())
        .eq('booking_type', bookingType.value)
        .eq('is_active', true)
        .maybeSingle();

    if (response == null) {
      AppLogger.log('STATE_PRICING_DRV -> ⚠️ NO PRICING for $stateCode/${bookingType.value}');
      throw NoPricingConfiguredError(stateCode, bookingType.value);
    }

    final pricing = StatePricing.fromJson(response);

    // Validar split
    if (!pricing.isValidSplit) {
      AppLogger.log(
        'STATE_PRICING_DRV -> ⚠️ Invalid split for $stateCode: '
        'DRV=${pricing.driverPercentage}% + PLAT=${pricing.platformPercentage}% + '
        'INS=${pricing.insurancePercentage}% + TAX=${pricing.taxPercentage}% != 100%'
      );
    }

    // Guardar en cache
    _cache[cacheKey] = pricing;
    _lastCacheRefresh = DateTime.now();

    AppLogger.log(
      'STATE_PRICING_DRV -> Loaded: $stateCode/${bookingType.value} '
      '(drv=${pricing.driverPercentage}%, plat=${pricing.platformPercentage}%)'
    );

    return pricing;
  }

  /// Verificar si un estado tiene pricing configurado (sin lanzar error)
  Future<bool> hasPricing({
    required String stateCode,
    required BookingType bookingType,
  }) async {
    try {
      await getPricing(stateCode: stateCode, bookingType: bookingType);
      return true;
    } on NoPricingConfiguredError {
      return false;
    }
  }

  /// Obtener multiplicador de tiempo actual (PÚBLICO para uso externo)
  double getTimeMultiplier(StatePricing pricing) {
    final now = DateTime.now();
    final hour = now.hour;
    final isWeekend = now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;

    // Peak hours: 7-9 AM, 4-7 PM
    final isPeak = (hour >= 7 && hour <= 9) || (hour >= 16 && hour <= 19);

    // Night: 10 PM - 5 AM
    final isNight = hour >= 22 || hour <= 5;

    if (isPeak) return pricing.peakMultiplier;
    if (isNight) return pricing.nightMultiplier;
    if (isWeekend) return pricing.weekendMultiplier;
    return 1.0;
  }

  /// Verificar si cache es válido
  bool _isCacheValid() {
    if (_lastCacheRefresh == null) return false;
    return DateTime.now().difference(_lastCacheRefresh!) < _cacheMaxAge;
  }

  /// Limpiar cache (forzar refresh)
  void clearCache() {
    _cache.clear();
    _lastCacheRefresh = null;
    AppLogger.log('STATE_PRICING_DRV -> Cache cleared');
  }

  /// Subscribir a cambios en pricing_config (realtime)
  void subscribeToUpdates() {
    // Clean up previous channel if any
    if (_realtimeChannel != null) {
      SupabaseConfig.client.removeChannel(_realtimeChannel!);
      _realtimeChannel = null;
    }

    _realtimeChannel = SupabaseConfig.client
        .channel('state_pricing_updates_driver')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pricing_config',
          callback: (payload) {
            AppLogger.log('STATE_PRICING_DRV -> Realtime update, clearing cache');
            clearCache();
          },
        )
        .subscribe();

    AppLogger.log('STATE_PRICING_DRV -> Subscribed to realtime updates');
  }

  /// Clean up realtime channel
  void dispose() {
    if (_realtimeChannel != null) {
      SupabaseConfig.client.removeChannel(_realtimeChannel!);
      _realtimeChannel = null;
    }
  }
}
