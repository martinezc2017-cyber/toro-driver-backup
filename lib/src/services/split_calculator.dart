/// ============================================================================
/// SPLIT CALCULATOR - TORO DRIVER APP
/// ============================================================================
/// Single source of truth for ALL financial calculations.
/// This file handles the breakdown of ride payments:
///   GROSS → Platform Fee → Insurance → Tax → Driver Base → Tips
///
/// NEW QR MODEL (v2):
///   QR tiers REDUCE platform commission, NOT add bonus %.
///   Tier 0: base (20%) | Tier 1: 19% | Tier 2: 18% | Tier 3: 17% |
///   Tier 4: 16% | Tier 5: 15%
///   Driver gets the difference (64% → up to 69%).
///   Tax (IVA 16%) stays fixed.
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

  // QR Commission Reduction Tiers (replaces old bonus % system)
  // Each tier reduces platform commission by 1% (configurable)
  final int qrMaxLevel; // max QR scans per week (30 for MX)
  final int qrTier1Max;
  final double qrTier1CommissionReduction; // 1% = platform goes from 20→19
  final int qrTier2Max;
  final double qrTier2CommissionReduction; // 2%
  final int qrTier3Max;
  final double qrTier3CommissionReduction; // 3%
  final int qrTier4Max;
  final double qrTier4CommissionReduction; // 4%
  final double qrTier5CommissionReduction; // 5% (max, platform = 15%)

  const SplitConfig({
    required this.platformFeePercent,
    required this.driverPercent,
    required this.insurancePercent,
    required this.taxPercent,
    this.qrMaxLevel = 30,
    this.qrTier1Max = 6,
    this.qrTier1CommissionReduction = 1.0,
    this.qrTier2Max = 12,
    this.qrTier2CommissionReduction = 2.0,
    this.qrTier3Max = 18,
    this.qrTier3CommissionReduction = 3.0,
    this.qrTier4Max = 24,
    this.qrTier4CommissionReduction = 4.0,
    this.qrTier5CommissionReduction = 5.0,
  });

  /// Get effective platform % after QR tier commission reduction
  /// Tier 0: base (20%) | Tier 5: base - 5% (15%)
  double getEffectivePlatformPercent({int driverQRLevel = 0}) {
    final reduction = getQRCommissionReduction(driverQRLevel);
    // Minimum 15% platform fee (safety floor)
    return math.max(15.0, platformFeePercent - reduction);
  }

  /// Get the commission reduction for a given QR level
  double getQRCommissionReduction(int qrLevel) {
    if (qrLevel <= 0) return 0;
    if (qrLevel <= qrTier1Max) return qrTier1CommissionReduction;
    if (qrLevel <= qrTier2Max) return qrTier2CommissionReduction;
    if (qrLevel <= qrTier3Max) return qrTier3CommissionReduction;
    if (qrLevel <= qrTier4Max) return qrTier4CommissionReduction;
    return qrTier5CommissionReduction;
  }

  /// Get driver's effective percentage after QR reduction
  double getEffectiveDriverPercent({int driverQRLevel = 0}) {
    final reduction = getQRCommissionReduction(driverQRLevel);
    return driverPercent + reduction;
  }

  /// Get the QR tier number (0-5) for a given level
  int getQRTier(int qrLevel) {
    if (qrLevel <= 0) return 0;
    if (qrLevel <= qrTier1Max) return 1;
    if (qrLevel <= qrTier2Max) return 2;
    if (qrLevel <= qrTier3Max) return 3;
    if (qrLevel <= qrTier4Max) return 4;
    return 5;
  }

  /// Validate that percentages add up correctly (flat mode)
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
      qrMaxLevel: (json['qr_max_level'] as num?)?.toInt() ?? 30,
      qrTier1Max: (json['qr_tier_1_max'] as num?)?.toInt() ?? 6,
      qrTier1CommissionReduction: (json['qr_tier_1_bonus'] as num?)?.toDouble() ?? 1.0,
      qrTier2Max: (json['qr_tier_2_max'] as num?)?.toInt() ?? 12,
      qrTier2CommissionReduction: (json['qr_tier_2_bonus'] as num?)?.toDouble() ?? 2.0,
      qrTier3Max: (json['qr_tier_3_max'] as num?)?.toInt() ?? 18,
      qrTier3CommissionReduction: (json['qr_tier_3_bonus'] as num?)?.toDouble() ?? 3.0,
      qrTier4Max: (json['qr_tier_4_max'] as num?)?.toInt() ?? 24,
      qrTier4CommissionReduction: (json['qr_tier_4_bonus'] as num?)?.toDouble() ?? 4.0,
      qrTier5CommissionReduction: (json['qr_tier_5_bonus'] as num?)?.toDouble() ?? 5.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'platform_fee_percent': platformFeePercent,
    'driver_percentage': driverPercent,
    'insurance_percentage': insurancePercent,
    'tax_percentage': taxPercent,
    'qr_max_level': qrMaxLevel,
    'qr_tier_1_max': qrTier1Max,
    'qr_tier_1_bonus': qrTier1CommissionReduction,
    'qr_tier_2_max': qrTier2Max,
    'qr_tier_2_bonus': qrTier2CommissionReduction,
    'qr_tier_3_max': qrTier3Max,
    'qr_tier_3_bonus': qrTier3CommissionReduction,
    'qr_tier_4_max': qrTier4Max,
    'qr_tier_4_bonus': qrTier4CommissionReduction,
    'qr_tier_5_bonus': qrTier5CommissionReduction,
  };
}

/// Complete breakdown of a payment split
class SplitBreakdown {
  final double grossAmount;
  final double tipAmount;
  final int driverQRLevel;
  final int driverQRTier;
  final double platformFee;
  final double platformPercent;
  final double insuranceFee;
  final double taxFee;
  final double driverBase;
  final double driverPercent;
  final double qrCommissionReduction;
  final double driverTotalEarnings;
  final double riderPaid;

  const SplitBreakdown({
    required this.grossAmount,
    required this.tipAmount,
    required this.driverQRLevel,
    required this.driverQRTier,
    required this.platformFee,
    required this.platformPercent,
    required this.insuranceFee,
    required this.taxFee,
    required this.driverBase,
    required this.driverPercent,
    required this.qrCommissionReduction,
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
    'driver_qr_tier': driverQRTier,
    'platform_fee': platformFee,
    'platform_percent': platformPercent,
    'insurance_fee': insuranceFee,
    'tax_fee': taxFee,
    'driver_base': driverBase,
    'driver_percent': driverPercent,
    'qr_commission_reduction': qrCommissionReduction,
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
  ///
  /// QR tiers reduce platform commission:
  ///   More QR scans → lower platform % → driver earns more
  ///   Tax (IVA) stays fixed at configured rate
  SplitBreakdown calculate({
    required double grossAmount,
    double tipAmount = 0,
    int driverQRLevel = 0,
  }) {
    grossAmount = math.max(0, grossAmount);
    tipAmount = math.max(0, tipAmount);
    driverQRLevel = driverQRLevel.clamp(0, config.qrMaxLevel);

    // QR tiers reduce platform commission
    final effectivePlatformPercent =
        config.getEffectivePlatformPercent(driverQRLevel: driverQRLevel);
    final qrReduction = config.getQRCommissionReduction(driverQRLevel);
    final qrTier = config.getQRTier(driverQRLevel);

    final platformFee = _round(grossAmount * (effectivePlatformPercent / 100));
    final insuranceFee = _round(grossAmount * (config.insurancePercent / 100));
    final taxFee = _round(grossAmount * (config.taxPercent / 100));
    final driverBase = _round(
      grossAmount - platformFee - insuranceFee - taxFee,
    );
    final effectiveDriverPercent = grossAmount > 0
        ? (driverBase / grossAmount) * 100
        : config.driverPercent;
    final driverTotalEarnings = _round(driverBase + tipAmount);
    final riderPaid = _round(grossAmount + tipAmount);

    return SplitBreakdown(
      grossAmount: grossAmount,
      tipAmount: tipAmount,
      driverQRLevel: driverQRLevel,
      driverQRTier: qrTier,
      platformFee: platformFee,
      platformPercent: effectivePlatformPercent,
      insuranceFee: insuranceFee,
      taxFee: taxFee,
      driverBase: driverBase,
      driverPercent: effectiveDriverPercent,
      qrCommissionReduction: qrReduction,
      driverTotalEarnings: driverTotalEarnings,
      riderPaid: riderPaid,
    );
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
        config.getEffectiveDriverPercent(driverQRLevel: driverQRLevel);
    final estimatedGross = effectiveDriverPercent > 0
        ? _round((driverBaseWithoutTip * 100) / effectiveDriverPercent)
        : 0.0;

    return calculate(
      grossAmount: estimatedGross,
      tipAmount: tipAmount,
      driverQRLevel: driverQRLevel,
    );
  }

  /// Get driver's effective percentage including QR tier benefit
  double getDriverPercentage({int driverQRLevel = 0}) {
    return config.getEffectiveDriverPercent(driverQRLevel: driverQRLevel);
  }

  /// Get platform's effective percentage including QR tier reduction
  double getPlatformPercentage({int driverQRLevel = 0}) {
    return config.getEffectivePlatformPercent(driverQRLevel: driverQRLevel);
  }

  double getPlatformTotalPercentage({int driverQRLevel = 0}) {
    return config.getEffectivePlatformPercent(driverQRLevel: driverQRLevel) +
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
//   final breakdown = calculator.calculate(grossAmount: 20.0, driverQRLevel: 8);
//   // breakdown.platformPercent == 18% (Tier 2 reduction)
//   // breakdown.driverPercent == 66%
// ============================================================================
