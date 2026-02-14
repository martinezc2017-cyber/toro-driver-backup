import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../core/logging/app_logger.dart';

/// Driver QR Points Level data
/// Drivers can earn 0-N points (N = qr_max_level from pricing_config)
/// In tier mode (MX): bonus jumps at tier breakpoints
/// In linear mode (US): each point = +1% extra commission
class DriverQRPointsLevel {
  final int level; // 0 to qrMaxLevel
  final int
  qrsAccepted; // Number of referrals that completed first ride/approval
  final double
  bonusPercent; // Extra % on top of base commission (same as level)
  final DateTime weekStart; // Start of current week (Monday)
  final double totalBonusEarned; // Total $ earned from bonus this week

  DriverQRPointsLevel({
    this.level = 0,
    this.qrsAccepted = 0,
    this.bonusPercent = 0,
    this.totalBonusEarned = 0,
    DateTime? weekStart,
  }) : weekStart = weekStart ?? _getWeekStart();

  /// Get Monday of current week
  static DateTime getWeekStart([DateTime? date]) {
    final now = date ?? DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }

  static DateTime _getWeekStart([DateTime? date]) => getWeekStart(date);

  /// Get time until next Monday reset
  Duration get timeUntilReset {
    final nextMonday = weekStart.add(const Duration(days: 7));
    return nextMonday.difference(DateTime.now());
  }

  /// Check if we're in a new week
  bool get isNewWeek {
    final currentWeekStart = _getWeekStart();
    return weekStart.isBefore(currentWeekStart);
  }

  DriverQRPointsLevel copyWith({
    int? level,
    int? qrsAccepted,
    double? bonusPercent,
    DateTime? weekStart,
    double? totalBonusEarned,
  }) => DriverQRPointsLevel(
    level: level ?? this.level,
    qrsAccepted: qrsAccepted ?? this.qrsAccepted,
    bonusPercent: bonusPercent ?? this.bonusPercent,
    weekStart: weekStart ?? this.weekStart,
    totalBonusEarned: totalBonusEarned ?? this.totalBonusEarned,
  );

  Map<String, dynamic> toJson() => {
    'current_level': level,
    'qrs_accepted': qrsAccepted,
    'bonus_percent': bonusPercent,
    'week_start': weekStart.toIso8601String().split('T')[0],
    'total_bonus_earned': totalBonusEarned,
  };

  factory DriverQRPointsLevel.fromJson(Map<String, dynamic> json) {
    final weekStartStr = json['week_start'];
    DateTime weekStart;
    if (weekStartStr is String) {
      weekStart = DateTime.parse(weekStartStr);
    } else {
      weekStart = DriverQRPointsLevel._getWeekStart();
    }

    return DriverQRPointsLevel(
      level: (json['current_level'] as num?)?.toInt() ?? 0,
      qrsAccepted: (json['qrs_accepted'] as num?)?.toInt() ?? 0,
      bonusPercent: (json['bonus_percent'] as num?)?.toDouble() ?? 0,
      weekStart: weekStart,
      totalBonusEarned: (json['total_bonus_earned'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Tip received by driver from QR points
class QRTipReceived {
  final String id;
  final String riderId;
  final String? rideId;
  final int pointsSpent;
  final double tipAmount;
  final double originalPrice;
  final double finalPrice;
  final DateTime weekStart;
  final DateTime createdAt;

  QRTipReceived({
    required this.id,
    required this.riderId,
    this.rideId,
    required this.pointsSpent,
    required this.tipAmount,
    required this.originalPrice,
    required this.finalPrice,
    required this.weekStart,
    required this.createdAt,
  });

  factory QRTipReceived.fromJson(Map<String, dynamic> json) {
    return QRTipReceived(
      id: json['id'] ?? '',
      riderId: json['rider_id'] ?? '',
      rideId: json['ride_id'],
      pointsSpent: (json['points_spent'] as num?)?.toInt() ?? 0,
      tipAmount: (json['tip_amount'] as num?)?.toDouble() ?? 0,
      originalPrice: (json['original_price'] as num?)?.toDouble() ?? 0,
      finalPrice: (json['final_price'] as num?)?.toDouble() ?? 0,
      weekStart: DateTime.tryParse(json['week_start'] ?? '') ?? DateTime.now(),
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }
}

/// Donation received by driver from rider's QR driverShare allocation
class QRDonationReceived {
  final String id;
  final String riderId;
  final String? riderName;
  final String? rideId;
  final String stateCode;
  final double ridePrice;
  final double donationPercent;
  final double donationAmount;
  final int riderQrLevel;
  final int riderShare;
  final int driverShare;
  final DateTime weekStart;
  final DateTime createdAt;

  QRDonationReceived({
    required this.id,
    required this.riderId,
    this.riderName,
    this.rideId,
    required this.stateCode,
    required this.ridePrice,
    required this.donationPercent,
    required this.donationAmount,
    required this.riderQrLevel,
    required this.riderShare,
    required this.driverShare,
    required this.weekStart,
    required this.createdAt,
  });

  factory QRDonationReceived.fromJson(Map<String, dynamic> json) {
    return QRDonationReceived(
      id: json['id'] ?? '',
      riderId: json['rider_id'] ?? '',
      riderName: json['rider_name'],
      rideId: json['ride_id'],
      stateCode: json['state_code'] ?? '',
      ridePrice: (json['ride_price'] as num?)?.toDouble() ?? 0,
      donationPercent: (json['donation_percent'] as num?)?.toDouble() ?? 0,
      donationAmount: (json['donation_amount'] as num?)?.toDouble() ?? 0,
      riderQrLevel: (json['rider_qr_level'] as num?)?.toInt() ?? 0,
      riderShare: (json['rider_share'] as num?)?.toInt() ?? 0,
      driverShare: (json['driver_share'] as num?)?.toInt() ?? 0,
      weekStart: DateTime.tryParse(json['week_start'] ?? '') ?? DateTime.now(),
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }
}

/// Driver QR Points Service
/// Manages driver's QR points and tip tracking
/// Max level comes from pricing_config.qr_max_level (default 15 US, 30 MX)
class DriverQRPointsService extends ChangeNotifier {
  final SupabaseClient _client = SupabaseConfig.client;
  int _qrMaxLevel = 15; // Updated from pricing_config on initialize
  bool _qrUseTiers = false; // true = MX tier mode, false = US linear
  int _qrTier1Max = 6;
  double _qrTier1Bonus = 2.0;
  int _qrTier2Max = 12;
  double _qrTier2Bonus = 4.0;
  int _qrTier3Max = 18;
  double _qrTier3Bonus = 6.0;
  int _qrTier4Max = 24;
  double _qrTier4Bonus = 8.0;
  double _qrTier5Bonus = 10.0;

  DriverQRPointsLevel _currentLevel = DriverQRPointsLevel();
  List<QRTipReceived> _tipsReceived = [];
  List<QRDonationReceived> _donationsReceived = [];
  bool _isLoading = true;
  String? _error;
  String? _driverId;
  RealtimeChannel? _realtimeChannel;
  RealtimeChannel? _tipsChannel;
  RealtimeChannel? _donationsChannel;

  // Getters
  DriverQRPointsLevel get currentLevel => _currentLevel;
  List<QRTipReceived> get tipsReceived => _tipsReceived;
  List<QRDonationReceived> get donationsReceived => _donationsReceived;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get qrMaxLevel => _qrMaxLevel;
  bool get qrUseTiers => _qrUseTiers;

  /// Get current tier number (1-5) or 0 if no tier / linear mode
  int get currentTier {
    if (!_qrUseTiers) return 0;
    final level = _currentLevel.level;
    if (level <= 0) return 0;
    if (level <= _qrTier1Max) return 1;
    if (level <= _qrTier2Max) return 2;
    if (level <= _qrTier3Max) return 3;
    if (level <= _qrTier4Max) return 4;
    return 5;
  }

  /// Get the bonus % for current tier
  double get currentTierBonusPercent {
    if (!_qrUseTiers) return _currentLevel.bonusPercent;
    switch (currentTier) {
      case 1: return _qrTier1Bonus;
      case 2: return _qrTier2Bonus;
      case 3: return _qrTier3Bonus;
      case 4: return _qrTier4Bonus;
      case 5: return _qrTier5Bonus;
      default: return 0;
    }
  }

  /// Get QRs needed for next tier (0 if already max)
  int get qrsForNextTier {
    if (!_qrUseTiers) return 0;
    final level = _currentLevel.level;
    if (level < _qrTier1Max) return _qrTier1Max;
    if (level < _qrTier2Max) return _qrTier2Max;
    if (level < _qrTier3Max) return _qrTier3Max;
    if (level < _qrTier4Max) return _qrTier4Max;
    if (level < _qrMaxLevel) return _qrMaxLevel;
    return 0; // Already at max
  }

  /// Tier breakpoints for display
  List<(int max, double bonus)> get tierBreakpoints => [
    (_qrTier1Max, _qrTier1Bonus),
    (_qrTier2Max, _qrTier2Bonus),
    (_qrTier3Max, _qrTier3Bonus),
    (_qrTier4Max, _qrTier4Bonus),
    (_qrMaxLevel, _qrTier5Bonus),
  ];

  /// Total tips received this week
  double get weeklyTipsTotal => _tipsReceived
      .where((t) => t.weekStart == _currentLevel.weekStart)
      .fold(0.0, (sum, t) => sum + t.tipAmount);

  /// Total tips received all time
  double get allTimeTipsTotal =>
      _tipsReceived.fold(0.0, (sum, t) => sum + t.tipAmount);

  /// Total donations received this week
  double get weeklyDonationsTotal {
    final weekStart = _currentLevel.weekStart;
    final weekStartStr = weekStart.toIso8601String().split('T')[0];
    return _donationsReceived
        .where((d) => d.weekStart.toIso8601String().split('T')[0] == weekStartStr)
        .fold(0.0, (sum, d) => sum + d.donationAmount);
  }

  /// Total donations received all time
  double get allTimeDonationsTotal =>
      _donationsReceived.fold(0.0, (sum, d) => sum + d.donationAmount);

  /// Initialize service for a driver
  Future<void> initialize(String driverId) async {
    _driverId = driverId;
    _isLoading = true;
    _error = null;
    notifyListeners();

    await _loadQRMaxLevel();
    await _loadFromSupabase();
    await _loadTipsHistory();
    await _loadDonationsHistory();
    _subscribeToUpdates();
  }

  /// Load qr_max_level from pricing_config based on driver's state
  Future<void> _loadQRMaxLevel() async {
    try {
      // Get driver's country code to determine max level
      final driverData = await _client
          .from('drivers')
          .select('country_code, state_code')
          .eq('id', _driverId!)
          .maybeSingle();

      final countryCode = driverData?['country_code'] ?? 'MX';
      final stateCode = driverData?['state_code'];

      // Load from pricing_config for this state
      if (stateCode != null) {
        final config = await _client
            .from('pricing_config')
            .select('qr_max_level, qr_use_tiers, qr_tier_1_max, qr_tier_1_bonus, qr_tier_2_max, qr_tier_2_bonus, qr_tier_3_max, qr_tier_3_bonus, qr_tier_4_max, qr_tier_4_bonus, qr_tier_5_bonus')
            .eq('state_code', stateCode)
            .eq('country_code', countryCode)
            .eq('booking_type', 'ride')
            .maybeSingle();

        if (config != null) {
          _qrMaxLevel = (config['qr_max_level'] as num?)?.toInt() ?? 15;
          _qrUseTiers = config['qr_use_tiers'] == true;
          _qrTier1Max = (config['qr_tier_1_max'] as num?)?.toInt() ?? 6;
          _qrTier1Bonus = (config['qr_tier_1_bonus'] as num?)?.toDouble() ?? 2.0;
          _qrTier2Max = (config['qr_tier_2_max'] as num?)?.toInt() ?? 12;
          _qrTier2Bonus = (config['qr_tier_2_bonus'] as num?)?.toDouble() ?? 4.0;
          _qrTier3Max = (config['qr_tier_3_max'] as num?)?.toInt() ?? 18;
          _qrTier3Bonus = (config['qr_tier_3_bonus'] as num?)?.toDouble() ?? 6.0;
          _qrTier4Max = (config['qr_tier_4_max'] as num?)?.toInt() ?? 24;
          _qrTier4Bonus = (config['qr_tier_4_bonus'] as num?)?.toDouble() ?? 8.0;
          _qrTier5Bonus = (config['qr_tier_5_bonus'] as num?)?.toDouble() ?? 10.0;
        }
      }

      // Fallback by country
      if (_qrMaxLevel == 15 && countryCode == 'MX') {
        _qrMaxLevel = 30;
        _qrUseTiers = true;
      }

      AppLogger.log('DRIVER_QR_POINTS -> Max QR level: $_qrMaxLevel, tiers: $_qrUseTiers');
    } catch (e) {
      AppLogger.log('DRIVER_QR_POINTS -> Error loading max level: $e');
    }
  }

  /// Load current level from Supabase
  Future<void> _loadFromSupabase() async {
    if (_driverId == null) {
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      final weekStart = DriverQRPointsLevel.getWeekStart();
      final weekStartStr = weekStart.toIso8601String().split('T')[0];

      // Try to get existing record for this week
      final response = await _client
          .from('driver_qr_points')
          .select()
          .eq('driver_id', _driverId!)
          .eq('week_start', weekStartStr)
          .maybeSingle();

      if (response != null) {
        _currentLevel = DriverQRPointsLevel.fromJson(response);
        AppLogger.log(
          'DRIVER_QR_POINTS -> Loaded level ${_currentLevel.level} for week $weekStartStr',
        );
      } else {
        // Create new record for this week
        await _createWeeklyRecord(weekStartStr);
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      AppLogger.log('DRIVER_QR_POINTS -> Error loading: $e');
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Create a new weekly record
  Future<void> _createWeeklyRecord(String weekStartStr) async {
    if (_driverId == null) return;

    try {
      await _client.from('driver_qr_points').insert({
        'driver_id': _driverId,
        'week_start': weekStartStr,
        'qrs_accepted': 0,
        'current_level': 0,
        'bonus_percent': 0,
        'total_bonus_earned': 0,
      });

      _currentLevel = DriverQRPointsLevel();
      AppLogger.log('DRIVER_QR_POINTS -> Created new week record');
    } catch (e) {
      AppLogger.log('DRIVER_QR_POINTS -> Error creating record: $e');
    }
  }

  /// Load tips history
  Future<void> _loadTipsHistory() async {
    if (_driverId == null) return;

    try {
      final response = await _client
          .from('qr_tip_history')
          .select()
          .eq('driver_id', _driverId!)
          .order('created_at', ascending: false)
          .limit(100);

      _tipsReceived = (response as List)
          .map((e) => QRTipReceived.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      AppLogger.log('DRIVER_QR_POINTS -> Loaded ${_tipsReceived.length} tips');
      notifyListeners();
    } catch (e) {
      AppLogger.log('DRIVER_QR_POINTS -> Error loading tips: $e');
    }
  }

  /// Load donations received from riders' driverShare allocation
  Future<void> _loadDonationsHistory() async {
    if (_driverId == null) return;

    try {
      final response = await _client
          .from('qr_ride_donations')
          .select('*, profiles:rider_id(full_name)')
          .eq('driver_id', _driverId!)
          .order('created_at', ascending: false)
          .limit(100);

      _donationsReceived = (response as List).map((e) {
        final map = Map<String, dynamic>.from(e);
        // Extract rider name from joined profiles
        final profiles = map['profiles'];
        if (profiles is Map) {
          map['rider_name'] = profiles['full_name'];
        }
        return QRDonationReceived.fromJson(map);
      }).toList();

      AppLogger.log('DRIVER_QR_POINTS -> Loaded ${_donationsReceived.length} donations');
      notifyListeners();
    } catch (e) {
      AppLogger.log('DRIVER_QR_POINTS -> Error loading donations: $e');
    }
  }

  /// Subscribe to real-time updates
  void _subscribeToUpdates() {
    if (_driverId == null) return;

    // Subscribe to QR points updates
    _realtimeChannel = _client
        .channel('driver_qr_points_$_driverId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'driver_qr_points',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'driver_id',
            value: _driverId!,
          ),
          callback: (payload) {
            AppLogger.log('DRIVER_QR_POINTS -> Real-time update received');
            final newData = payload.newRecord;
            if (newData.isNotEmpty) {
              _currentLevel = DriverQRPointsLevel.fromJson(newData);
              notifyListeners();
              AppLogger.log(
                'DRIVER_QR_POINTS -> Updated to level ${_currentLevel.level}',
              );
            }
          },
        )
        .subscribe();

    // Subscribe to tips updates
    _tipsChannel = _client
        .channel('driver_tips_$_driverId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'qr_tip_history',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'driver_id',
            value: _driverId!,
          ),
          callback: (payload) {
            AppLogger.log('DRIVER_QR_POINTS -> New tip received!');
            final newData = payload.newRecord;
            if (newData.isNotEmpty) {
              final tip = QRTipReceived.fromJson(newData);
              _tipsReceived.insert(0, tip);
              notifyListeners();
            }
          },
        )
        .subscribe();

    // Subscribe to donations updates
    _donationsChannel = _client
        .channel('driver_donations_$_driverId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'qr_ride_donations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'driver_id',
            value: _driverId!,
          ),
          callback: (payload) {
            AppLogger.log('DRIVER_QR_POINTS -> New donation received!');
            final newData = payload.newRecord;
            if (newData.isNotEmpty) {
              final donation = QRDonationReceived.fromJson(newData);
              _donationsReceived.insert(0, donation);
              notifyListeners();
            }
          },
        )
        .subscribe();

    AppLogger.log('DRIVER_QR_POINTS -> Subscribed to real-time updates');
  }

  /// Validate that a trip meets minimum requirements for QR point awarding
  /// Requires: distance >= 0.8km AND duration >= 3 minutes
  Future<bool> validateCompletedTrip({
    required double distanceKm,
    required double durationMin,
  }) async {
    try {
      final result = await _client.rpc('validate_completed_trip', params: {
        'p_distance_km': distanceKm,
        'p_duration_min': durationMin,
      });

      final isValid = result as bool? ?? false;
      AppLogger.log(
        'DRIVER_QR_POINTS -> Trip validation: distance=${distanceKm}km, duration=${durationMin}min, valid=$isValid',
      );
      return isValid;
    } catch (e) {
      AppLogger.log('DRIVER_QR_POINTS -> Trip validation error: $e');
      // If validation fails due to error, don't award points (fail safe)
      return false;
    }
  }

  /// Increment level when a referral completes first ride or is approved as driver
  /// This should be called by the backend/admin when the condition is met
  /// IMPORTANT: Call validateCompletedTrip() BEFORE calling this method!
  Future<void> incrementLevel({
    double? distanceKm,
    double? durationMin,
  }) async {
    if (_driverId == null) return;

    // If trip data is provided, validate before awarding points
    if (distanceKm != null && durationMin != null) {
      final isValidTrip = await validateCompletedTrip(
        distanceKm: distanceKm,
        durationMin: durationMin,
      );

      if (!isValidTrip) {
        AppLogger.log(
          'DRIVER_QR_POINTS -> Trip validation failed - not awarding points',
        );
        return;
      }
    }

    final weekStartStr = _currentLevel.weekStart.toIso8601String().split(
      'T',
    )[0];
    final newQrs = _currentLevel.qrsAccepted + 1;
    final newLevel = newQrs.clamp(0, _qrMaxLevel);

    try {
      await _client
          .from('driver_qr_points')
          .update({
            'qrs_accepted': newQrs,
            'current_level': newLevel,
            'bonus_percent': newLevel.toDouble(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('driver_id', _driverId!)
          .eq('week_start', weekStartStr);

      _currentLevel = _currentLevel.copyWith(
        qrsAccepted: newQrs,
        level: newLevel,
        bonusPercent: newLevel.toDouble(),
      );

      notifyListeners();
      AppLogger.log('DRIVER_QR_POINTS -> Level incremented to $newLevel');
    } catch (e) {
      AppLogger.log('DRIVER_QR_POINTS -> Error incrementing level: $e');
    }
  }

  /// Calculate bonus for a ride based on current level
  /// Returns extra $ amount driver earns
  /// Uses SplitCalculator for the actual tier/linear logic
  double calculateBonus(double ridePrice, double baseCommissionPercent) {
    if (_currentLevel.level == 0) return 0;

    // The actual bonus % is calculated by SplitCalculator._getQRTierPercent
    // This is a simplified version for display purposes
    return ridePrice * (_currentLevel.bonusPercent / 100);
  }

  /// Get the total commission percent with bonus
  double getTotalCommissionPercent(double baseCommissionPercent) {
    return baseCommissionPercent + _currentLevel.bonusPercent;
  }

  /// Refresh data from Supabase
  Future<void> refresh() async {
    _isLoading = true;
    notifyListeners();

    await _loadFromSupabase();
    await _loadTipsHistory();
    await _loadDonationsHistory();
  }

  /// Clean up resources
  @override
  void dispose() {
    if (_realtimeChannel != null) {
      _client.removeChannel(_realtimeChannel!);
      _realtimeChannel = null;
    }
    if (_tipsChannel != null) {
      _client.removeChannel(_tipsChannel!);
      _tipsChannel = null;
    }
    if (_donationsChannel != null) {
      _client.removeChannel(_donationsChannel!);
      _donationsChannel = null;
    }
    super.dispose();
  }
}
