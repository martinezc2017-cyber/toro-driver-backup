enum TransactionType {
  rideEarning,
  tip,
  bonus,
  referralBonus,
  withdrawal,
  platformFee,
  adjustment,
}

class EarningModel {
  final String id;
  final String driverId;
  final String? rideId;
  final TransactionType type;
  final double amount;
  final String description;
  final DateTime createdAt;

  EarningModel({
    required this.id,
    required this.driverId,
    this.rideId,
    required this.type,
    required this.amount,
    required this.description,
    required this.createdAt,
  });

  bool get isPositive => amount >= 0;

  factory EarningModel.fromJson(Map<String, dynamic> json) {
    return EarningModel(
      id: json['id'] as String,
      driverId: json['driver_id'] as String,
      rideId: json['ride_id'] as String?,
      type: TransactionType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => TransactionType.rideEarning,
      ),
      amount: (json['amount'] as num).toDouble(),
      description: json['description'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'driver_id': driverId,
      'ride_id': rideId,
      'type': type.name,
      'amount': amount,
      'description': description,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class EarningsSummary {
  // Totals by period
  final double todayEarnings;
  final double weekEarnings;
  final double monthEarnings;
  final double totalBalance;

  // Rides count
  final int todayRides;
  final int weekRides;
  final int monthRides;

  // Tips
  final double todayTips;
  final double weekTips;
  final double monthTips;

  // Detailed breakdown (week)
  final double weekBaseFare;
  final double weekSurgeBonus;
  final double weekPromotions;
  final double weekPlatformFees;
  final double weekQRBoost;
  final double weekPeakHoursBonus;
  final double weekDamageFee;
  final double weekExtraBonus;

  // Performance metrics
  final double weekOnlineMinutes;
  final double weekDrivingMinutes;
  final double weekTotalMiles;
  final double acceptanceRate;
  final double cancellationRate;

  // QR Points (from driver_qr_points table)
  final int weekPoints;

  // Goals
  final double weeklyGoal;

  EarningsSummary({
    this.todayEarnings = 0.0,
    this.weekEarnings = 0.0,
    this.monthEarnings = 0.0,
    this.totalBalance = 0.0,
    this.todayRides = 0,
    this.weekRides = 0,
    this.monthRides = 0,
    this.todayTips = 0.0,
    this.weekTips = 0.0,
    this.monthTips = 0.0,
    this.weekBaseFare = 0.0,
    this.weekSurgeBonus = 0.0,
    this.weekPromotions = 0.0,
    this.weekPlatformFees = 0.0,
    this.weekQRBoost = 0.0,
    this.weekPeakHoursBonus = 0.0,
    this.weekDamageFee = 0.0,
    this.weekExtraBonus = 0.0,
    this.weekOnlineMinutes = 0.0,
    this.weekDrivingMinutes = 0.0,
    this.weekTotalMiles = 0.0,
    this.acceptanceRate = 0.0,
    this.cancellationRate = 0.0,
    this.weekPoints = 0,
    this.weeklyGoal = 500.0,
  });

  // Computed properties
  double get weekOnlineHours => weekOnlineMinutes / 60;
  double get weekDrivingHours => weekDrivingMinutes / 60;
  double get weekNetEarnings => weekEarnings + weekTips - weekPlatformFees;
  double get perTripAverage => weekRides > 0 ? weekEarnings / weekRides : 0;
  double get perHourAverage => weekOnlineHours > 0 ? weekEarnings / weekOnlineHours : 0;
  double get perMileAverage => weekTotalMiles > 0 ? weekEarnings / weekTotalMiles : 0;
  double get weeklyGoalProgress => weeklyGoal > 0 ? (weekEarnings / weeklyGoal).clamp(0.0, 1.0) : 0;

  factory EarningsSummary.fromJson(Map<String, dynamic> json) {
    return EarningsSummary(
      todayEarnings: (json['today_earnings'] as num?)?.toDouble() ?? 0.0,
      weekEarnings: (json['week_earnings'] as num?)?.toDouble() ?? 0.0,
      monthEarnings: (json['month_earnings'] as num?)?.toDouble() ?? 0.0,
      totalBalance: (json['total_balance'] as num?)?.toDouble() ?? 0.0,
      todayRides: json['today_rides'] as int? ?? 0,
      weekRides: json['week_rides'] as int? ?? 0,
      monthRides: json['month_rides'] as int? ?? 0,
      todayTips: (json['today_tips'] as num?)?.toDouble() ?? 0.0,
      weekTips: (json['week_tips'] as num?)?.toDouble() ?? 0.0,
      monthTips: (json['month_tips'] as num?)?.toDouble() ?? 0.0,
      weekBaseFare: (json['week_base_fare'] as num?)?.toDouble() ?? 0.0,
      weekSurgeBonus: (json['week_surge_bonus'] as num?)?.toDouble() ?? 0.0,
      weekPromotions: (json['week_promotions'] as num?)?.toDouble() ?? 0.0,
      weekPlatformFees: (json['week_platform_fees'] as num?)?.toDouble() ?? 0.0,
      weekQRBoost: (json['week_qr_boost'] as num?)?.toDouble() ?? 0.0,
      weekPeakHoursBonus: (json['week_peak_hours_bonus'] as num?)?.toDouble() ?? 0.0,
      weekDamageFee: (json['week_damage_fee'] as num?)?.toDouble() ?? 0.0,
      weekExtraBonus: (json['week_extra_bonus'] as num?)?.toDouble() ?? 0.0,
      weekOnlineMinutes: (json['week_online_minutes'] as num?)?.toDouble() ?? 0.0,
      weekDrivingMinutes: (json['week_driving_minutes'] as num?)?.toDouble() ?? 0.0,
      weekTotalMiles: (json['week_total_miles'] as num?)?.toDouble() ?? 0.0,
      acceptanceRate: (json['acceptance_rate'] as num?)?.toDouble() ?? 0.0,
      cancellationRate: (json['cancellation_rate'] as num?)?.toDouble() ?? 0.0,
      weekPoints: (json['week_points'] as num?)?.toInt() ?? 0,
      weeklyGoal: (json['weekly_goal'] as num?)?.toDouble() ?? 500.0,
    );
  }
}
