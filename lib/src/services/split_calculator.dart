/// ============================================================================
/// SPLIT CALCULATOR - TORO DRIVER APP
/// ============================================================================
/// Single source of truth for ALL financial calculations.
/// This file handles the breakdown of ride payments:
///   GROSS → Platform Fee → Insurance → Tax → Driver Base → QR Bonus → Tips
///
/// MUST be kept in sync with:
/// - toro/lib/core/services/split_calculator.dart (rider app)
/// - supabase/functions/stripe-process-split/index.ts (edge function)
/// ============================================================================
library;

import 'dart:math' as math;

/// Split percentages from pricing_config
class SplitConfig {
  final double platformFeePercent;
  final double driverPercent;
  final double insurancePercent;
  final double taxPercent;
  final double qrPointValue; // Value per QR level (e.g., 1.0 = 1%)

  const SplitConfig({
    required this.platformFeePercent,
    required this.driverPercent,
    required this.insurancePercent,
    required this.taxPercent,
    this.qrPointValue = 1.0,
  });

  /// Validate that percentages add up correctly
  bool get isValid {
    final total =
        platformFeePercent + driverPercent + insurancePercent + taxPercent;
    return (total - 100).abs() < 0.01;
  }

  factory SplitConfig.fromJson(Map<String, dynamic> json) {
    return SplitConfig(
      platformFeePercent:
          (json['platform_fee_percent'] as num?)?.toDouble() ?? 0,
      driverPercent: (json['driver_percentage'] as num?)?.toDouble() ?? 0,
      insurancePercent: (json['insurance_percentage'] as num?)?.toDouble() ?? 0,
      taxPercent: (json['tax_percentage'] as num?)?.toDouble() ?? 0,
      qrPointValue: (json['qr_point_value'] as num?)?.toDouble() ?? 1.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'platform_fee_percent': platformFeePercent,
    'driver_percentage': driverPercent,
    'insurance_percentage': insurancePercent,
    'tax_percentage': taxPercent,
    'qr_point_value': qrPointValue,
  };
}

/// Complete breakdown of a payment split
class SplitBreakdown {
  final double grossAmount;
  final double tipAmount;
  final int driverQRLevel;
  final double platformFee;
  final double insuranceFee;
  final double taxFee;
  final double driverBase;
  final double qrBonus;
  final double driverTotalEarnings;
  final double riderPaid;

  const SplitBreakdown({
    required this.grossAmount,
    required this.tipAmount,
    required this.driverQRLevel,
    required this.platformFee,
    required this.insuranceFee,
    required this.taxFee,
    required this.driverBase,
    required this.qrBonus,
    required this.driverTotalEarnings,
    required this.riderPaid,
  });

  double get platformTotal => platformFee + insuranceFee + taxFee;

  double get driverSharePercent =>
      grossAmount > 0 ? (driverBase / grossAmount) * 100 : 0;

  bool get isValid {
    final calculatedGross = platformFee + insuranceFee + taxFee + driverBase;
    return (calculatedGross - grossAmount).abs() < 0.01;
  }

  Map<String, dynamic> toJson() => {
    'gross_amount': grossAmount,
    'tip_amount': tipAmount,
    'driver_qr_level': driverQRLevel,
    'platform_fee': platformFee,
    'insurance_fee': insuranceFee,
    'tax_fee': taxFee,
    'driver_base': driverBase,
    'qr_bonus': qrBonus,
    'driver_total_earnings': driverTotalEarnings,
    'rider_paid': riderPaid,
  };
}

/// ============================================================================
/// SPLIT CALCULATOR
/// ============================================================================
class SplitCalculator {
  final SplitConfig config;

  const SplitCalculator(this.config);

  /// Calculate the complete split breakdown
  SplitBreakdown calculate({
    required double grossAmount,
    double tipAmount = 0,
    int driverQRLevel = 0,
  }) {
    grossAmount = math.max(0, grossAmount);
    tipAmount = math.max(0, tipAmount);
    driverQRLevel = driverQRLevel.clamp(0, 15);

    final platformFee = _round(grossAmount * (config.platformFeePercent / 100));
    final insuranceFee = _round(grossAmount * (config.insurancePercent / 100));
    final taxFee = _round(grossAmount * (config.taxPercent / 100));
    final driverBase = _round(
      grossAmount - platformFee - insuranceFee - taxFee,
    );
    final qrBonus = _calculateQRBonus(grossAmount, driverQRLevel);
    final driverTotalEarnings = _round(driverBase + qrBonus + tipAmount);
    final riderPaid = _round(grossAmount + tipAmount);

    return SplitBreakdown(
      grossAmount: grossAmount,
      tipAmount: tipAmount,
      driverQRLevel: driverQRLevel,
      platformFee: platformFee,
      insuranceFee: insuranceFee,
      taxFee: taxFee,
      driverBase: driverBase,
      qrBonus: qrBonus,
      driverTotalEarnings: driverTotalEarnings,
      riderPaid: riderPaid,
    );
  }

  double _calculateQRBonus(double grossAmount, int qrLevel) {
    if (qrLevel <= 0) return 0;
    final bonusPercent = qrLevel * config.qrPointValue;
    return _round(grossAmount * (bonusPercent / 100));
  }

  double _round(double value) {
    return double.parse(value.toStringAsFixed(2));
  }

  /// Calculate breakdown from driver's earnings (reverse calculation)
  SplitBreakdown calculateFromDriverEarnings({
    required double driverEarnings,
    double tipAmount = 0,
    int driverQRLevel = 0,
  }) {
    final driverBaseWithoutTip = driverEarnings - tipAmount;
    final effectiveDriverPercent =
        config.driverPercent + (driverQRLevel * config.qrPointValue);
    final estimatedGross = effectiveDriverPercent > 0
        ? _round((driverBaseWithoutTip * 100) / effectiveDriverPercent)
        : 0.0;

    return calculate(
      grossAmount: estimatedGross,
      tipAmount: tipAmount,
      driverQRLevel: driverQRLevel,
    );
  }

  double getDriverPercentage({int driverQRLevel = 0}) {
    return config.driverPercent + (driverQRLevel * config.qrPointValue);
  }

  double getPlatformTotalPercentage() {
    return config.platformFeePercent +
        config.insurancePercent +
        config.taxPercent;
  }
}

// ============================================================================
// CONVENIENCE FUNCTIONS
// ============================================================================

/// Calculate driver earnings from gross (simple version)
/// @deprecated Use SplitCalculator with config from StatePricingService
@Deprecated('Use SplitCalculator with config from StatePricingService')
double calculateDriverEarningsSimple(
  double grossAmount, {
  required double driverPercent, // REQUIRED - no default value
}) {
  return double.parse((grossAmount * (driverPercent / 100)).toStringAsFixed(2));
}

/// Calculate gross from driver earnings (reverse)
/// @deprecated Use SplitCalculator with config from StatePricingService
@Deprecated('Use SplitCalculator with config from StatePricingService')
double calculateGrossFromDriverEarnings(
  double driverEarnings, {
  required double driverPercent, // REQUIRED - no default value
}) {
  if (driverPercent <= 0) return 0;
  return double.parse(
    ((driverEarnings * 100) / driverPercent).toStringAsFixed(2),
  );
}

// ============================================================================
// NO DEFAULT SPLIT CONFIG - ALL VALUES MUST COME FROM PRICING_CONFIG
// ============================================================================
// Todos los valores de split DEBEN venir de pricing_config en Supabase.
// No hay valores por defecto - si no hay config, la app debe mostrar error.
//
// Uso correcto:
//   import 'state_pricing_service.dart';
//
//   final pricing = await StatePricingService.instance.getPricing(
//     stateCode: 'AZ',
//     bookingType: BookingType.ride,
//   );
//   final config = SplitConfig.fromJson(pricing.toSplitConfig());
//   final calculator = SplitCalculator(config);
//   final breakdown = calculator.calculate(grossAmount: 20.0);
// ============================================================================
