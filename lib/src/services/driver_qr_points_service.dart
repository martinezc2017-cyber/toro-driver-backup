import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../core/logging/app_logger.dart';

/// ============================================================================
/// DRIVER QR POINTS SERVICE - COMMISSION REDUCTION MODEL (v2)
/// ============================================================================
/// QR tiers REDUCE platform commission, NOT add bonus %.
///   Tier 0 (0 QRs):    Toro 20%, Driver 64%
///   Tier 1 (1-6 QRs):  Toro 19%, Driver 65%
///   Tier 2 (7-12 QRs): Toro 18%, Driver 66%
///   Tier 3 (13-18 QRs):Toro 17%, Driver 67%
///   Tier 4 (19-24 QRs):Toro 16%, Driver 68%
///   Tier 5 (25-30 QRs):Toro 15%, Driver 69%
///   IVA (16%) stays fixed.
/// ============================================================================

/// Driver QR Points Level data
/// Drivers earn 0-30 points per week via QR scans
/// Each tier reduces Toro's platform commission by 1%
class DriverQRPointsLevel {
  final int level; // 0 to qrMaxLevel (30)
  final int qrsAccepted; // Number of QR scans completed this week
  final DateTime weekStart; // Start of current week (Monday)

  DriverQRPointsLevel({
    this.level = 0,
    this.qrsAccepted = 0,
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
    DateTime? weekStart,
  }) => DriverQRPointsLevel(
    level: level ?? this.level,
    qrsAccepted: qrsAccepted ?? this.qrsAccepted,
    weekStart: weekStart ?? this.weekStart,
  );

  Map<String, dynamic> toJson() => {
    'current_level': level,
    'qrs_accepted': qrsAccepted,
    'week_start': weekStart.toIso8601String().split('T')[0],
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
      weekStart: weekStart,
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

/// State ranking entry for leaderboard
class StateRankEntry {
  final String driverId;
  final String driverName;
  final int qrLevel;
  final int tier;
  final int rank;
  final bool isMe;

  const StateRankEntry({
    required this.driverId,
    required this.driverName,
    required this.qrLevel,
    required this.tier,
    required this.rank,
    this.isMe = false,
  });
}

/// Driver QR Points Service - Commission Reduction Model
/// QR scans reduce Toro's platform commission from 20% → 15%
class DriverQRPointsService extends ChangeNotifier {
  final SupabaseClient _client = SupabaseConfig.client;

  // Tier config (loaded from pricing_config)
  int _qrMaxLevel = 30;
  static const double _basePlatformPercent = 20.0;
  int _qrTier1Max = 6;
  double _qrTier1Reduction = 1.0; // 20% → 19%
  int _qrTier2Max = 12;
  double _qrTier2Reduction = 2.0; // 20% → 18%
  int _qrTier3Max = 18;
  double _qrTier3Reduction = 3.0; // 20% → 17%
  int _qrTier4Max = 24;
  double _qrTier4Reduction = 4.0; // 20% → 16%
  double _qrTier5Reduction = 5.0; // 20% → 15%

  DriverQRPointsLevel _currentLevel = DriverQRPointsLevel();
  List<QRTipReceived> _tipsReceived = [];
  List<StateRankEntry> _stateRanking = [];
  int _myStateRank = 0; // 0 = not ranked
  String _stateCode = '';
  bool _isLoading = true;
  String? _error;
  String? _driverId;
  RealtimeChannel? _realtimeChannel;
  RealtimeChannel? _tipsChannel;

  // Getters
  DriverQRPointsLevel get currentLevel => _currentLevel;
  List<QRTipReceived> get tipsReceived => _tipsReceived;
  List<StateRankEntry> get stateRanking => _stateRanking;
  int get myStateRank => _myStateRank;
  String get stateCode => _stateCode;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get qrMaxLevel => _qrMaxLevel;

  /// Get current tier number (0-5) based on QR level
  int get currentTier {
    final level = _currentLevel.level;
    if (level <= 0) return 0;
    if (level <= _qrTier1Max) return 1;
    if (level <= _qrTier2Max) return 2;
    if (level <= _qrTier3Max) return 3;
    if (level <= _qrTier4Max) return 4;
    return 5;
  }

  /// Get the commission reduction % for current tier
  /// Tier 0: 0% | Tier 1: 1% | ... | Tier 5: 5%
  double get currentCommissionReduction {
    switch (currentTier) {
      case 1: return _qrTier1Reduction;
      case 2: return _qrTier2Reduction;
      case 3: return _qrTier3Reduction;
      case 4: return _qrTier4Reduction;
      case 5: return _qrTier5Reduction;
      default: return 0;
    }
  }

  /// Get effective platform commission % after QR reduction
  /// Tier 0: 20% | Tier 5: 15%
  double get effectivePlatformPercent =>
      _basePlatformPercent - currentCommissionReduction;

  /// Get effective driver % after QR reduction
  /// Tier 0: 64% | Tier 5: 69% (base 64% + 5% from reduced commission)
  double get effectiveDriverPercent =>
      64.0 + currentCommissionReduction;

  /// Get QRs needed for next tier (0 if already max)
  int get qrsForNextTier {
    final level = _currentLevel.level;
    if (level < _qrTier1Max) return _qrTier1Max;
    if (level < _qrTier2Max) return _qrTier2Max;
    if (level < _qrTier3Max) return _qrTier3Max;
    if (level < _qrTier4Max) return _qrTier4Max;
    if (level < _qrMaxLevel) return _qrMaxLevel;
    return 0; // Already at max
  }

  /// Tier breakpoints for display: (maxQRs, commissionReduction, platformPercent)
  List<({int max, double reduction, double platformPercent})> get tierBreakpoints => [
    (max: _qrTier1Max, reduction: _qrTier1Reduction, platformPercent: _basePlatformPercent - _qrTier1Reduction),
    (max: _qrTier2Max, reduction: _qrTier2Reduction, platformPercent: _basePlatformPercent - _qrTier2Reduction),
    (max: _qrTier3Max, reduction: _qrTier3Reduction, platformPercent: _basePlatformPercent - _qrTier3Reduction),
    (max: _qrTier4Max, reduction: _qrTier4Reduction, platformPercent: _basePlatformPercent - _qrTier4Reduction),
    (max: _qrMaxLevel, reduction: _qrTier5Reduction, platformPercent: _basePlatformPercent - _qrTier5Reduction),
  ];

  /// Total tips received this week
  double get weeklyTipsTotal => _tipsReceived
      .where((t) => t.weekStart == _currentLevel.weekStart)
      .fold(0.0, (sum, t) => sum + t.tipAmount);

  /// Total tips received all time
  double get allTimeTipsTotal =>
      _tipsReceived.fold(0.0, (sum, t) => sum + t.tipAmount);

  /// Initialize service for a driver
  Future<void> initialize(String driverId) async {
    _driverId = driverId;
    _isLoading = true;
    _error = null;
    notifyListeners();

    await _loadQRConfig();
    await _loadFromSupabase();
    await Future.wait([_loadTipsHistory(), _loadStateRanking()]);
    _subscribeToUpdates();
  }

  /// Load QR tier config from pricing_config based on driver's state
  Future<void> _loadQRConfig() async {
    try {
      final driverData = await _client
          .from('drivers')
          .select('country_code, state_code')
          .eq('id', _driverId!)
          .maybeSingle();

      final countryCode = driverData?['country_code'] ?? 'MX';
      final stateCode = driverData?['state_code'];
      _stateCode = stateCode ?? '';

      if (stateCode != null) {
        final config = await _client
            .from('pricing_config')
            .select('qr_max_level, qr_tier_1_max, qr_tier_1_bonus, qr_tier_2_max, qr_tier_2_bonus, qr_tier_3_max, qr_tier_3_bonus, qr_tier_4_max, qr_tier_4_bonus, qr_tier_5_bonus')
            .eq('state_code', stateCode)
            .eq('country_code', countryCode)
            .eq('booking_type', 'ride')
            .maybeSingle();

        if (config != null) {
          _qrMaxLevel = (config['qr_max_level'] as num?)?.toInt() ?? 30;
          _qrTier1Max = (config['qr_tier_1_max'] as num?)?.toInt() ?? 6;
          _qrTier1Reduction = (config['qr_tier_1_bonus'] as num?)?.toDouble() ?? 1.0;
          _qrTier2Max = (config['qr_tier_2_max'] as num?)?.toInt() ?? 12;
          _qrTier2Reduction = (config['qr_tier_2_bonus'] as num?)?.toDouble() ?? 2.0;
          _qrTier3Max = (config['qr_tier_3_max'] as num?)?.toInt() ?? 18;
          _qrTier3Reduction = (config['qr_tier_3_bonus'] as num?)?.toDouble() ?? 3.0;
          _qrTier4Max = (config['qr_tier_4_max'] as num?)?.toInt() ?? 24;
          _qrTier4Reduction = (config['qr_tier_4_bonus'] as num?)?.toDouble() ?? 4.0;
          _qrTier5Reduction = (config['qr_tier_5_bonus'] as num?)?.toDouble() ?? 5.0;
        }
      }

      // Fallback for MX
      if (_qrMaxLevel < 30 && countryCode == 'MX') {
        _qrMaxLevel = 30;
      }

      AppLogger.log('DRIVER_QR -> Config loaded: max=$_qrMaxLevel, tier reductions: $_qrTier1Reduction-$_qrTier5Reduction%');
    } catch (e) {
      AppLogger.log('DRIVER_QR -> Error loading config: $e');
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

      final response = await _client
          .from('driver_qr_points')
          .select()
          .eq('driver_id', _driverId!)
          .eq('week_start', weekStartStr)
          .maybeSingle();

      if (response != null) {
        _currentLevel = DriverQRPointsLevel.fromJson(response);
        AppLogger.log(
          'DRIVER_QR -> Loaded level ${_currentLevel.level} (Tier $currentTier, commission $effectivePlatformPercent%)',
        );
      } else {
        await _createWeeklyRecord(weekStartStr);
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      AppLogger.log('DRIVER_QR -> Error loading: $e');
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
        'bonus_percent': 0, // Legacy column, kept for DB compat
        'total_bonus_earned': 0,
      });

      _currentLevel = DriverQRPointsLevel();
      AppLogger.log('DRIVER_QR -> Created new week record');
    } catch (e) {
      AppLogger.log('DRIVER_QR -> Error creating record: $e');
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

      AppLogger.log('DRIVER_QR -> Loaded ${_tipsReceived.length} tips');
      notifyListeners();
    } catch (e) {
      AppLogger.log('DRIVER_QR -> Error loading tips: $e');
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
            AppLogger.log('DRIVER_QR -> Real-time update received');
            final newData = payload.newRecord;
            if (newData.isNotEmpty) {
              _currentLevel = DriverQRPointsLevel.fromJson(newData);
              notifyListeners();
              AppLogger.log(
                'DRIVER_QR -> Updated to level ${_currentLevel.level} (Tier $currentTier)',
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
            AppLogger.log('DRIVER_QR -> New tip received!');
            final newData = payload.newRecord;
            if (newData.isNotEmpty) {
              final tip = QRTipReceived.fromJson(newData);
              _tipsReceived.insert(0, tip);
              notifyListeners();
            }
          },
        )
        .subscribe();

    AppLogger.log('DRIVER_QR -> Subscribed to real-time updates');
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
        'DRIVER_QR -> Trip validation: distance=${distanceKm}km, duration=${durationMin}min, valid=$isValid',
      );
      return isValid;
    } catch (e) {
      AppLogger.log('DRIVER_QR -> Trip validation error: $e');
      return false;
    }
  }

  /// Increment level when a QR scan is accepted
  /// Call validateCompletedTrip() BEFORE calling this method!
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
        AppLogger.log('DRIVER_QR -> Trip validation failed - not awarding points');
        return;
      }
    }

    final weekStartStr = _currentLevel.weekStart.toIso8601String().split('T')[0];
    final newQrs = _currentLevel.qrsAccepted + 1;
    final newLevel = newQrs.clamp(0, _qrMaxLevel);

    try {
      await _client
          .from('driver_qr_points')
          .update({
            'qrs_accepted': newQrs,
            'current_level': newLevel,
            'bonus_percent': 0, // Legacy column - no longer used
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('driver_id', _driverId!)
          .eq('week_start', weekStartStr);

      _currentLevel = _currentLevel.copyWith(
        qrsAccepted: newQrs,
        level: newLevel,
      );

      notifyListeners();
      AppLogger.log('DRIVER_QR -> Level incremented to $newLevel (Tier $currentTier, platform $effectivePlatformPercent%)');
    } catch (e) {
      AppLogger.log('DRIVER_QR -> Error incrementing level: $e');
    }
  }

  /// Load state ranking - top drivers by QR level this week
  Future<void> _loadStateRanking() async {
    if (_driverId == null || _stateCode.isEmpty) return;

    try {
      final weekStart = DriverQRPointsLevel.getWeekStart();
      final weekStartStr = weekStart.toIso8601String().split('T')[0];

      // Get top 20 drivers in this state for this week, ordered by level desc
      final response = await _client
          .from('driver_qr_points')
          .select('driver_id, current_level, drivers!inner(full_name, state_code)')
          .eq('week_start', weekStartStr)
          .eq('drivers.state_code', _stateCode)
          .gt('current_level', 0)
          .order('current_level', ascending: false)
          .limit(20);

      final entries = <StateRankEntry>[];
      int rank = 0;
      int lastLevel = -1;

      for (final row in (response as List)) {
        final driverId = row['driver_id'] as String? ?? '';
        final level = (row['current_level'] as num?)?.toInt() ?? 0;
        final drivers = row['drivers'];
        final name = drivers is Map ? (drivers['full_name'] as String? ?? 'Driver') : 'Driver';

        // Same level = same rank
        if (level != lastLevel) {
          rank = entries.length + 1;
          lastLevel = level;
        }

        final tier = _getTierForLevel(level);

        entries.add(StateRankEntry(
          driverId: driverId,
          driverName: name,
          qrLevel: level,
          tier: tier,
          rank: rank,
          isMe: driverId == _driverId,
        ));
      }

      _stateRanking = entries;

      // Find my rank
      final myEntry = entries.where((e) => e.isMe).firstOrNull;
      _myStateRank = myEntry?.rank ?? 0;

      AppLogger.log('DRIVER_QR -> Ranking loaded: ${entries.length} drivers, my rank: $_myStateRank');
      notifyListeners();
    } catch (e) {
      AppLogger.log('DRIVER_QR -> Error loading ranking: $e');
    }
  }

  /// Helper to get tier for any level
  int _getTierForLevel(int level) {
    if (level <= 0) return 0;
    if (level <= _qrTier1Max) return 1;
    if (level <= _qrTier2Max) return 2;
    if (level <= _qrTier3Max) return 3;
    if (level <= _qrTier4Max) return 4;
    return 5;
  }

  /// Refresh data from Supabase
  Future<void> refresh() async {
    _isLoading = true;
    notifyListeners();

    await _loadFromSupabase();
    await Future.wait([_loadTipsHistory(), _loadStateRanking()]);
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
    super.dispose();
  }
}
