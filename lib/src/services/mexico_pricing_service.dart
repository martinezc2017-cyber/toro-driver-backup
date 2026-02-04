import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

/// Service for handling Mexican pricing zones and rules
class MexicoPricingService {
  final SupabaseClient _client = SupabaseConfig.client;

  // Cache for pricing data
  static PricingQuote? _lastQuote;
  static DateTime? _lastQuoteTime;
  static const _quoteCacheDuration = Duration(minutes: 5);

  /// Get pricing quote for a ride in Mexico
  Future<PricingQuote> getQuote({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    required double distanceKm,
    required double durationMin,
    String serviceType = 'ride',
    String vehicleType = 'standard',
    double tolls = 0,
    String displayCurrency = 'MXN',
  }) async {
    try {
      final response = await _client.functions.invoke(
        'pricing-quote-mx',
        body: {
          'pickup_lat': pickupLat,
          'pickup_lng': pickupLng,
          'dropoff_lat': dropoffLat,
          'dropoff_lng': dropoffLng,
          'distance_km': distanceKm,
          'duration_min': durationMin,
          'service_type': serviceType,
          'vehicle_type': vehicleType,
          'tolls': tolls,
          'display_currency': displayCurrency,
        },
      );

      if (response.status != 200) {
        throw Exception('Error getting pricing quote: ${response.data}');
      }

      final data = response.data['data'];
      final quote = PricingQuote.fromJson(data);

      // Cache the quote
      _lastQuote = quote;
      _lastQuoteTime = DateTime.now();

      return quote;
    } catch (e) {
      rethrow;
    }
  }

  /// Get pricing for a specific location
  Future<ZonePricing?> getPricingForLocation({
    required double lat,
    required double lng,
    String serviceType = 'ride',
    String vehicleType = 'standard',
  }) async {
    try {
      final response = await _client.rpc(
        'get_pricing_for_location',
        params: {
          'p_lat': lat,
          'p_lng': lng,
          'p_service_type': serviceType,
          'p_vehicle_type': vehicleType,
        },
      );

      if (response == null || (response as List).isEmpty) {
        return null;
      }

      return ZonePricing.fromJson(response[0]);
    } catch (e) {
      rethrow;
    }
  }

  /// Get all pricing zones
  Future<List<PricingZone>> getAllZones() async {
    try {
      final response = await _client
          .from('pricing_zones_mx')
          .select()
          .eq('is_active', true)
          .order('state_code');

      return (response as List).map((data) {
        return PricingZone.fromJson(data);
      }).toList();
    } catch (e) {
      rethrow;
    }
  }

  /// Get pricing rules for a zone
  Future<List<PricingRule>> getZoneRules(int zoneId) async {
    try {
      final response = await _client
          .from('pricing_rules_mx')
          .select()
          .eq('zone_id', zoneId)
          .eq('is_active', true)
          .isFilter('effective_to', null);

      return (response as List).map((data) {
        return PricingRule.fromJson(data);
      }).toList();
    } catch (e) {
      rethrow;
    }
  }

  /// Get current FX rate
  Future<double> getFxRate(String baseCurrency, String quoteCurrency) async {
    try {
      final response = await _client
          .from('fx_rates')
          .select('rate')
          .eq('base_currency', baseCurrency)
          .eq('quote_currency', quoteCurrency)
          .order('fetched_at', ascending: false)
          .limit(1)
          .single();

      return (response['rate'] as num).toDouble();
    } catch (e) {
      return 1.0; // Default to 1 if not found
    }
  }

  /// Check if it's night time in Mexico (22:00 - 06:00)
  bool isNightTime() {
    final now = DateTime.now();
    final hour = now.hour;
    return hour >= 22 || hour < 6;
  }

  /// Check if it's weekend
  bool isWeekend() {
    final now = DateTime.now();
    return now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;
  }

  /// Format price in MXN
  String formatMxn(double amount) {
    return '\$${amount.toStringAsFixed(2)} MXN';
  }

  /// Format price in USD (for display)
  String formatUsd(double amount) {
    return '\$${amount.toStringAsFixed(2)} USD';
  }
}

/// Pricing quote result
class PricingQuote {
  final int zoneId;
  final String zoneName;
  final String currency;

  // Breakdown
  final double baseFare;
  final double distanceKm;
  final double distanceAmount;
  final double durationMin;
  final double timeAmount;
  final double bookingFee;

  // Multipliers
  final bool isNight;
  final double nightMultiplier;
  final bool isWeekend;
  final double weekendMultiplier;
  final double surgeMultiplier;
  final double surgeAmount;

  // Extras
  final double tolls;

  // Totals
  final double subtotal;
  final double taxRate;
  final double taxAmount;
  final double total;

  // Split
  final double platformFee;
  final double driverEarnings;

  // Display currency
  final double? fxRate;
  final double? totalDisplay;
  final String? displayCurrency;

  // Flags
  final bool minFareApplied;

  PricingQuote({
    required this.zoneId,
    required this.zoneName,
    required this.currency,
    required this.baseFare,
    required this.distanceKm,
    required this.distanceAmount,
    required this.durationMin,
    required this.timeAmount,
    required this.bookingFee,
    required this.isNight,
    required this.nightMultiplier,
    required this.isWeekend,
    required this.weekendMultiplier,
    required this.surgeMultiplier,
    required this.surgeAmount,
    required this.tolls,
    required this.subtotal,
    required this.taxRate,
    required this.taxAmount,
    required this.total,
    required this.platformFee,
    required this.driverEarnings,
    this.fxRate,
    this.totalDisplay,
    this.displayCurrency,
    required this.minFareApplied,
  });

  factory PricingQuote.fromJson(Map<String, dynamic> json) {
    return PricingQuote(
      zoneId: json['zone_id'] as int,
      zoneName: json['zone_name'] as String,
      currency: json['currency'] as String,
      baseFare: (json['base_fare'] as num).toDouble(),
      distanceKm: (json['distance_km'] as num).toDouble(),
      distanceAmount: (json['distance_amount'] as num).toDouble(),
      durationMin: (json['duration_min'] as num).toDouble(),
      timeAmount: (json['time_amount'] as num).toDouble(),
      bookingFee: (json['booking_fee'] as num).toDouble(),
      isNight: json['is_night'] as bool,
      nightMultiplier: (json['night_multiplier'] as num).toDouble(),
      isWeekend: json['is_weekend'] as bool,
      weekendMultiplier: (json['weekend_multiplier'] as num).toDouble(),
      surgeMultiplier: (json['surge_multiplier'] as num).toDouble(),
      surgeAmount: (json['surge_amount'] as num).toDouble(),
      tolls: (json['tolls'] as num).toDouble(),
      subtotal: (json['subtotal'] as num).toDouble(),
      taxRate: (json['tax_rate'] as num).toDouble(),
      taxAmount: (json['tax_amount'] as num).toDouble(),
      total: (json['total'] as num).toDouble(),
      platformFee: (json['platform_fee'] as num).toDouble(),
      driverEarnings: (json['driver_earnings'] as num).toDouble(),
      fxRate: json['fx_rate'] != null
          ? (json['fx_rate'] as num).toDouble()
          : null,
      totalDisplay: json['total_display'] != null
          ? (json['total_display'] as num).toDouble()
          : null,
      displayCurrency: json['display_currency'] as String?,
      minFareApplied: json['min_fare_applied'] as bool,
    );
  }

  /// Get formatted total
  String get formattedTotal => '\$${total.toStringAsFixed(2)} $currency';

  /// Get IVA percentage
  String get taxPercentage => '${(taxRate * 100).toInt()}%';

  /// Has active multipliers
  bool get hasMultipliers =>
      nightMultiplier > 1 || weekendMultiplier > 1 || surgeMultiplier > 1;
}

/// Pricing zone
class PricingZone {
  final int id;
  final String name;
  final String stateCode;
  final double? centerLat;
  final double? centerLng;
  final String? description;
  final bool isActive;

  PricingZone({
    required this.id,
    required this.name,
    required this.stateCode,
    this.centerLat,
    this.centerLng,
    this.description,
    required this.isActive,
  });

  factory PricingZone.fromJson(Map<String, dynamic> json) {
    return PricingZone(
      id: json['id'] as int,
      name: json['name'] as String,
      stateCode: json['state_code'] as String,
      centerLat: json['center_lat'] != null
          ? (json['center_lat'] as num).toDouble()
          : null,
      centerLng: json['center_lng'] != null
          ? (json['center_lng'] as num).toDouble()
          : null,
      description: json['description'] as String?,
      isActive: json['is_active'] as bool,
    );
  }
}

/// Zone pricing configuration
class ZonePricing {
  final int zoneId;
  final String zoneName;
  final String stateCode;
  final double baseFare;
  final double perKm;
  final double perMin;
  final double minFare;
  final double bookingFee;
  final double nightMultiplier;
  final double weekendMultiplier;
  final double maxSurgeMultiplier;
  final double platformFeePercent;
  final String currency;

  ZonePricing({
    required this.zoneId,
    required this.zoneName,
    required this.stateCode,
    required this.baseFare,
    required this.perKm,
    required this.perMin,
    required this.minFare,
    required this.bookingFee,
    required this.nightMultiplier,
    required this.weekendMultiplier,
    required this.maxSurgeMultiplier,
    required this.platformFeePercent,
    required this.currency,
  });

  factory ZonePricing.fromJson(Map<String, dynamic> json) {
    return ZonePricing(
      zoneId: json['zone_id'] as int,
      zoneName: json['zone_name'] as String,
      stateCode: json['state_code'] as String,
      baseFare: (json['base_fare'] as num).toDouble(),
      perKm: (json['per_km'] as num).toDouble(),
      perMin: (json['per_min'] as num).toDouble(),
      minFare: (json['min_fare'] as num).toDouble(),
      bookingFee: (json['booking_fee'] as num).toDouble(),
      nightMultiplier: (json['night_multiplier'] as num).toDouble(),
      weekendMultiplier: (json['weekend_multiplier'] as num).toDouble(),
      maxSurgeMultiplier: (json['max_surge_multiplier'] as num).toDouble(),
      platformFeePercent: (json['platform_fee_percent'] as num).toDouble(),
      currency: json['currency'] as String,
    );
  }
}

/// Pricing rule
class PricingRule {
  final int id;
  final int zoneId;
  final String serviceType;
  final String vehicleType;
  final double baseFare;
  final double perKm;
  final double perMin;
  final double minFare;
  final double bookingFee;
  final double cancellationFee;
  final double nightMultiplier;
  final int nightStartHour;
  final int nightEndHour;
  final double weekendMultiplier;
  final double maxSurgeMultiplier;
  final double platformFeePercent;
  final double driverPercent;
  final String currency;
  final DateTime effectiveFrom;
  final DateTime? effectiveTo;

  PricingRule({
    required this.id,
    required this.zoneId,
    required this.serviceType,
    required this.vehicleType,
    required this.baseFare,
    required this.perKm,
    required this.perMin,
    required this.minFare,
    required this.bookingFee,
    required this.cancellationFee,
    required this.nightMultiplier,
    required this.nightStartHour,
    required this.nightEndHour,
    required this.weekendMultiplier,
    required this.maxSurgeMultiplier,
    required this.platformFeePercent,
    required this.driverPercent,
    required this.currency,
    required this.effectiveFrom,
    this.effectiveTo,
  });

  factory PricingRule.fromJson(Map<String, dynamic> json) {
    return PricingRule(
      id: json['id'] as int,
      zoneId: json['zone_id'] as int,
      serviceType: json['service_type'] as String,
      vehicleType: json['vehicle_type'] as String,
      baseFare: (json['base_fare'] as num).toDouble(),
      perKm: (json['per_km'] as num).toDouble(),
      perMin: (json['per_min'] as num).toDouble(),
      minFare: (json['min_fare'] as num).toDouble(),
      bookingFee: (json['booking_fee'] as num).toDouble(),
      cancellationFee: (json['cancellation_fee'] as num).toDouble(),
      nightMultiplier: (json['night_multiplier'] as num).toDouble(),
      nightStartHour: json['night_start_hour'] as int,
      nightEndHour: json['night_end_hour'] as int,
      weekendMultiplier: (json['weekend_multiplier'] as num).toDouble(),
      maxSurgeMultiplier: (json['max_surge_multiplier'] as num).toDouble(),
      platformFeePercent: (json['platform_fee_percent'] as num).toDouble(),
      driverPercent: (json['driver_percent'] as num).toDouble(),
      currency: json['currency'] as String,
      effectiveFrom: DateTime.parse(json['effective_from']),
      effectiveTo: json['effective_to'] != null
          ? DateTime.parse(json['effective_to'])
          : null,
    );
  }
}
