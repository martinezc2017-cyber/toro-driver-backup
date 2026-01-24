import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../core/logging/app_logger.dart';

/// Driver QR Points Level data
/// Drivers can earn 0-15 points, each point = +1% extra commission
class DriverQRPointsLevel {
  final int level; // 0-15
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

/// Driver QR Points Service
/// Manages driver's QR points (0-15 max) and tip tracking
class DriverQRPointsService extends ChangeNotifier {
  final SupabaseClient _client = SupabaseConfig.client;

  DriverQRPointsLevel _currentLevel = DriverQRPointsLevel();
  List<QRTipReceived> _tipsReceived = [];
  bool _isLoading = true;
  String? _error;
  String? _driverId;
  RealtimeChannel? _realtimeChannel;
  RealtimeChannel? _tipsChannel;

  // Getters
  DriverQRPointsLevel get currentLevel => _currentLevel;
  List<QRTipReceived> get tipsReceived => _tipsReceived;
  bool get isLoading => _isLoading;
  String? get error => _error;

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

    await _loadFromSupabase();
    await _loadTipsHistory();
    _subscribeToUpdates();
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

    AppLogger.log('DRIVER_QR_POINTS -> Subscribed to real-time updates');
  }

  /// Increment level when a referral completes first ride or is approved as driver
  /// This should be called by the backend/admin when the condition is met
  Future<void> incrementLevel() async {
    if (_driverId == null) return;

    final weekStartStr = _currentLevel.weekStart.toIso8601String().split(
      'T',
    )[0];
    final newQrs = _currentLevel.qrsAccepted + 1;
    final newLevel = newQrs.clamp(0, 15); // Max 15 points for driver

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
  double calculateBonus(double ridePrice, double baseCommissionPercent) {
    if (_currentLevel.level == 0) return 0;

    // Extra bonus from QR points (level% extra on the ride price)
    return ridePrice * (_currentLevel.level / 100);
  }

  /// Get the total commission percent with bonus
  /// Example: base 50% + 10 QR points = 60%
  double getTotalCommissionPercent(double baseCommissionPercent) {
    return baseCommissionPercent + _currentLevel.level;
  }

  /// Refresh data from Supabase
  Future<void> refresh() async {
    _isLoading = true;
    notifyListeners();

    await _loadFromSupabase();
    await _loadTipsHistory();
  }

  /// Clean up resources
  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _tipsChannel?.unsubscribe();
    super.dispose();
  }
}
