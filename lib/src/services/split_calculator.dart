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

  // Variable Platform Tiers (Toro Nivelar)
  final bool variablePlatformEnabled;
  final double platformTier1MaxFare;
  final double platformTier1Percent;
  final double platformTier2MaxFare;
  final double platformTier2Percent;
  final double platformTier3MaxFare;
  final double platformTier3Percent;
  final double platformTier4Percent;

  // QR Tier System (configurable per state from pricing_config)
  final bool qrUseTiers; // true = tier mode (MX), false = linear (US)
  final int qrMaxLevel; // max QR scans per week
  final int qrTier1Max;
  final double qrTier1Bonus;
  final int qrTier2Max;
  final double qrTier2Bonus;
  final int qrTier3Max;
  final double qrTier3Bonus;
  final int qrTier4Max;
  final double qrTier4Bonus;
  final double qrTier5Bonus;

  const SplitConfig({
    required this.platformFeePercent,
    required this.driverPercent,
    required this.insurancePercent,
    required this.taxPercent,
    this.qrPointValue = 1.0,
    this.variablePlatformEnabled = false,
    this.platformTier1MaxFare = 10.0,
    this.platformTier1Percent = 5.0,
    this.platformTier2MaxFare = 20.0,
    this.platformTier2Percent = 15.0,
    this.platformTier3MaxFare = 35.0,
    this.platformTier3Percent = 23.4,
    this.platformTier4Percent = 25.0,
    this.qrUseTiers = false,
    this.qrMaxLevel = 15,
    this.qrTier1Max = 6,
    this.qrTier1Bonus = 2.0,
    this.qrTier2Max = 12,
    this.qrTier2Bonus = 4.0,
    this.qrTier3Max = 18,
    this.qrTier3Bonus = 6.0,
    this.qrTier4Max = 24,
    this.qrTier4Bonus = 8.0,
    this.qrTier5Bonus = 10.0,
  });

  /// Get effective platform % based on fare amount
  /// When variable is disabled, returns flat platformFeePercent
  double getEffectivePlatformPercent(double fareAmount) {
    if (!variablePlatformEnabled) return platformFeePercent;
    if (fareAmount <= platformTier1MaxFare) return platformTier1Percent;
    if (fareAmount <= platformTier2MaxFare) return platformTier2Percent;
    if (fareAmount <= platformTier3MaxFare) return platformTier3Percent;
    return platformTier4Percent;
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
      qrPointValue: (json['qr_point_value'] as num?)?.toDouble() ?? 1.0,
      variablePlatformEnabled:
          json['variable_platform_enabled'] == true,
      platformTier1MaxFare:
          (json['platform_tier_1_max_fare'] as num?)?.toDouble() ?? 10.0,
      platformTier1Percent:
          (json['platform_tier_1_percent'] as num?)?.toDouble() ?? 5.0,
      platformTier2MaxFare:
          (json['platform_tier_2_max_fare'] as num?)?.toDouble() ?? 20.0,
      platformTier2Percent:
          (json['platform_tier_2_percent'] as num?)?.toDouble() ?? 15.0,
      platformTier3MaxFare:
          (json['platform_tier_3_max_fare'] as num?)?.toDouble() ?? 35.0,
      platformTier3Percent:
          (json['platform_tier_3_percent'] as num?)?.toDouble() ?? 23.4,
      platformTier4Percent:
          (json['platform_tier_4_percent'] as num?)?.toDouble() ?? 25.0,
      qrUseTiers: json['qr_use_tiers'] == true,
      qrMaxLevel: (json['qr_max_level'] as num?)?.toInt() ?? 15,
      qrTier1Max: (json['qr_tier_1_max'] as num?)?.toInt() ?? 6,
      qrTier1Bonus: (json['qr_tier_1_bonus'] as num?)?.toDouble() ?? 2.0,
      qrTier2Max: (json['qr_tier_2_max'] as num?)?.toInt() ?? 12,
      qrTier2Bonus: (json['qr_tier_2_bonus'] as num?)?.toDouble() ?? 4.0,
      qrTier3Max: (json['qr_tier_3_max'] as num?)?.toInt() ?? 18,
      qrTier3Bonus: (json['qr_tier_3_bonus'] as num?)?.toDouble() ?? 6.0,
      qrTier4Max: (json['qr_tier_4_max'] as num?)?.toInt() ?? 24,
      qrTier4Bonus: (json['qr_tier_4_bonus'] as num?)?.toDouble() ?? 8.0,
      qrTier5Bonus: (json['qr_tier_5_bonus'] as num?)?.toDouble() ?? 10.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'platform_fee_percent': platformFeePercent,
    'driver_percentage': driverPercent,
    'insurance_percentage': insurancePercent,
    'tax_percentage': taxPercent,
    'qr_point_value': qrPointValue,
    'variable_platform_enabled': variablePlatformEnabled,
    'platform_tier_1_max_fare': platformTier1MaxFare,
    'platform_tier_1_percent': platformTier1Percent,
    'platform_tier_2_max_fare': platformTier2MaxFare,
    'platform_tier_2_percent': platformTier2Percent,
    'platform_tier_3_max_fare': platformTier3MaxFare,
    'platform_tier_3_percent': platformTier3Percent,
    'platform_tier_4_percent': platformTier4Percent,
    'qr_use_tiers': qrUseTiers,
    'qr_max_level': qrMaxLevel,
    'qr_tier_1_max': qrTier1Max,
    'qr_tier_1_bonus': qrTier1Bonus,
    'qr_tier_2_max': qrTier2Max,
    'qr_tier_2_bonus': qrTier2Bonus,
    'qr_tier_3_max': qrTier3Max,
    'qr_tier_3_bonus': qrTier3Bonus,
    'qr_tier_4_max': qrTier4Max,
    'qr_tier_4_bonus': qrTier4Bonus,
    'qr_tier_5_bonus': qrTier5Bonus,
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
  ///
  /// Uses variable platform tiers when enabled:
  ///   Short trips → lower platform % → driver earns more
  ///   Long trips → normal/higher platform %
  SplitBreakdown calculate({
    required double grossAmount,
    double tipAmount = 0,
    int driverQRLevel = 0,
  }) {
    grossAmount = math.max(0, grossAmount);
    tipAmount = math.max(0, tipAmount);
    driverQRLevel = driverQRLevel.clamp(0, config.qrMaxLevel);

    // Use variable platform % based on fare tier (Toro Nivelar)
    final effectivePlatformPercent =
        config.getEffectivePlatformPercent(grossAmount);

    final platformFee = _round(grossAmount * (effectivePlatformPercent / 100));
    final insuranceFee = _round(grossAmount * (config.insurancePercent / 100));
    final taxFee = _round(grossAmount * (config.taxPercent / 100));
    final driverBase = _round(
      grossAmount - platformFee - insuranceFee - taxFee,
    );
    final qrBonus = _calculateQRBonus(driverBase, driverQRLevel);
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

  /// QR bonus = % extra de las GANANCIAS del driver (driverBase), NO del gross
  /// 5 Tiers × 6 QRs cada uno, máximo 30 QRs activos por semana
  /// Tier 1 (1-6 QRs) = +2%, Tier 2 (7-12) = +4%, Tier 3 (13-18) = +6%,
  /// Tier 4 (19-24) = +8%, Tier 5 (25-30) = +10%
  double _calculateQRBonus(double driverBaseEarnings, int qrLevel) {
    if (qrLevel <= 0) return 0;
    final bonusPercent = _getQRTierPercent(qrLevel) * config.qrPointValue;
    return _round(driverBaseEarnings * (bonusPercent / 100));
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
    final qrBonusPercent = _getQRTierPercent(driverQRLevel) * config.qrPointValue;
    // driverBaseWithoutTip = driverBase + qrBonus = driverBase * (1 + qrBonusPercent/100)
    final driverBase = qrBonusPercent > 0
        ? driverBaseWithoutTip / (1 + qrBonusPercent / 100)
        : driverBaseWithoutTip;
    // driverBase = gross * (driverPercent / 100)
    final estimatedGross = config.driverPercent > 0
        ? _round((driverBase * 100) / config.driverPercent)
        : 0.0;

    return calculate(
      grossAmount: estimatedGross,
      tipAmount: tipAmount,
      driverQRLevel: driverQRLevel,
    );
  }

  /// Returns the QR bonus percent for a given QR level
  /// Tier mode (MX): jumps at config breakpoints
  /// Linear mode (US): qrLevel * 1.0 (each QR = qrPointValue%)
  double _getQRTierPercent(int qrLevel) {
    if (qrLevel <= 0) return 0;
    if (!config.qrUseTiers) return qrLevel.toDouble(); // Linear: 1 QR = 1%
    // Tier mode: bonus jumps at configurable breakpoints
    if (qrLevel <= config.qrTier1Max) return config.qrTier1Bonus;
    if (qrLevel <= config.qrTier2Max) return config.qrTier2Bonus;
    if (qrLevel <= config.qrTier3Max) return config.qrTier3Bonus;
    if (qrLevel <= config.qrTier4Max) return config.qrTier4Bonus;
    return config.qrTier5Bonus;
  }

  double getDriverPercentage({int driverQRLevel = 0}) {
    return config.driverPercent + _getQRTierPercent(driverQRLevel) * config.qrPointValue;
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
