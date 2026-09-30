import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../core/logging/app_logger.dart';
import 'live_pricing.dart';

/// ============================================================================
/// DRIVER QR POINTS SERVICE - COMMISSION REDUCTION MODEL (v2)
/// ============================================================================
/// QR tiers REDUCE platform commission, NOT add bonus %.
/// Base percentages loaded from pricing_config per state:
///   US/AZ: Platform 20.4%, Driver 57%
///   MX/CDMX: Platform 25%, Driver 75%
/// Each tier reduces platform by 1% and increases driver by 1%.
///   Insurance (17%) + Tax (5.6%) stay fixed.
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
/// QR scans reduce Toro's platform commission from 20% → 5% (Tier 5 max)
/// Each tier reduces platform by 4%, driver gains that 4%.
class DriverQRPointsService extends ChangeNotifier {
  final SupabaseClient _client = SupabaseConfig.client;

  // Tier config (loaded from pricing_config)
  int _qrMaxLevel = 30;
  // % 100% dinámicos: SIEMPRE de pricing_config (país + estado del driver).
  // Arrancan en 0 a propósito: antes traían los defaults de USA (20.4 / 57) y si
  // la carga no corría, a un chofer de México se le mostraba el % gringo.
  double _basePlatformPercent = 0;
  double _baseDriverPercent = 0;
  double _insurancePercent = 0;
  /// Fila de pricing_config del estado del chofer (para leer los saltos del QR).
  Map<String, dynamic>? _configRow;

  /// Escaneos que hacen falta para subir UN nivel. Sale de
  /// pricing_config.qr_scans_per_level. Decision del dueno el 29 sep 2026: 2,
  /// o sea el nivel 5 (maximo) a los 10 escaneos. MISMA formula que la RPC
  /// qr_nivel_de() y que el disparador de la base; si esto se desincroniza, el
  /// chofer ve un nivel y se le paga otro.
  int _escaneosPorNivel = 2;
  int get escaneosPorNivel => _escaneosPorNivel;
  double _ivaPercent = 0;

  // ESCALERA DE INVITADOS (30 sep 2026). El nivel del QR ya NO sube los viajes
  // normales: paga UNICAMENTE en viajes de pasajeros que ESTE chofer invito
  // (referred_by_driver). referral_tier_shares_json trae el % del chofer por
  // nivel semanal 0..5, y es la MISMA lista que usa la RPC
  // referral_share_for_ride: si esto se desincroniza, el chofer ve un numero
  // y se le paga otro. _loadQRConfig pisa estos valores con la fila viva.
  List<double> _referralShares = [70, 75, 80, 85, 90, 95]; // guardian-ok: valor inicial; _loadQRConfig lo pisa con referral_tier_shares_json
  double _firstRideSharePct = 100; // guardian-ok: valor inicial; _loadQRConfig lo pisa con referral_first_ride_share_pct

  // Lo que gana el INVITADO al escanear (para que el chofer lo pueda contar):
  // la promo de lanzamiento viva en pricing_config. Si esta apagada, la
  // tarjeta no se muestra y no se promete nada.
  bool _promoInvitadoActiva = false;
  double _descuentoInvitadoPct = 0;
  bool get promoInvitadoActiva =>
      _promoInvitadoActiva && _descuentoInvitadoPct > 0;
  double get descuentoInvitadoPct => _descuentoInvitadoPct;

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
  double get insurancePercent => _insurancePercent;
  double get ivaPercent => _ivaPercent;

  /// Get current tier number (0-5).
  /// current_level in driver_qr_points IS the tier (set by apply-referral-bonus).
  /// El nivel se calcula de los ESCANEOS, no de la columna `current_level`:
  /// tres escritores distintos la llenaron con cosas distintas (el conteo, el
  /// tier, y los puntos), asi que no se puede confiar en ella.
  int get currentTier {
    final n = _escaneosPorNivel > 0 ? _escaneosPorNivel : 2;
    final porEscaneos = _currentLevel.qrsAccepted ~/ n;
    return porEscaneos.clamp(0, 5);
  }

  /// Puntos EXTRA (sobre su base) que el nivel actual le da al chofer en los
  /// viajes de SUS invitados. En viajes normales el extra es CERO desde el
  /// 30 sep 2026: el reparto normal no se toca y el fondo del seguro queda
  /// intacto (de ahi sale el IMSS).
  double get currentCommissionReduction => reduccionRealForTier(currentTier);

  /// Comision base del pais (pricing_config), SIN la reduccion del tier.
  double get basePlatformPercent => _basePlatformPercent;

  /// % base del chofer (pricing_config), SIN el bono del tier.
  double get baseDriverPercent => _baseDriverPercent;

  /// % de TORO en viajes NORMALES. El nivel del QR ya no lo mueve.
  double get effectivePlatformPercent => _basePlatformPercent;

  /// % del chofer en viajes NORMALES. El nivel del QR ya no lo mueve:
  /// el premio del nivel vive en shareForTier(), solo en viajes de invitados.
  double get effectiveDriverPercent => _baseDriverPercent;

  /// % del chofer en viajes de SUS invitados para un nivel dado (0-5).
  /// MISMOS candados que la RPC referral_share_for_ride: nunca menos que el
  /// reparto normal, nunca mas de 100.
  double shareForTier(int tier) {
    final t = tier.clamp(0, 5);
    final crudo = t < _referralShares.length
        ? _referralShares[t]
        : _baseDriverPercent;
    return crudo.clamp(_baseDriverPercent, 100.0);
  }

  /// % del chofer en viajes de invitados en su nivel actual.
  double get currentShare => shareForTier(currentTier);

  /// El primer viaje de cada invitado (bono del gancho): 100 %.
  double get firstRideSharePct => _firstRideSharePct;

  /// Puntos extra sobre la base para un nivel, en viajes de invitados.
  double reductionForTier(int tier) => shareForTier(tier) - _baseDriverPercent;

  /// Alias historico: hoy es lo mismo que reductionForTier (los candados ya
  /// van dentro de shareForTier). Lo consumen home y earnings.
  double reduccionRealForTier(int tier) => reductionForTier(tier);

  /// % de TORO en viajes de INVITADOS para un nivel (el fondo va apagado en
  /// esos viajes, asi que TORO es simplemente el residuo del chofer).
  double platformPercentForTier(int tier) =>
      (100 - shareForTier(tier)).clamp(0, 100).toDouble();

  /// % del chofer en viajes de INVITADOS para un nivel (para los anillos).
  double driverPercentForTier(int tier) => shareForTier(tier);

  /// Get QRs needed for next tier (0 if already max).
  /// Uses qrsAccepted (actual count) with apply-referral-bonus breakpoints:
  /// T1: 1-4, T2: 5-9, T3: 10-19, T4: 20-34, T5: 35+
  /// Escaneos que le faltan para el siguiente nivel. 0 si ya esta al tope.
  /// Antes devolvia 4 / 9 / 19 / 34, metas de un diseno que ningun otro lado
  /// compartia: le decia "te faltan 4" cuando con 2 ya subia.
  int get qrsForNextTier {
    if (currentTier >= 5) return 0;
    final n = _escaneosPorNivel > 0 ? _escaneosPorNivel : 2;
    return (currentTier + 1) * n;
  }

  /// Escaneos para llegar al tope (nivel 5). Para pintar la barra.
  int get escaneosParaElTope => 5 * (_escaneosPorNivel > 0 ? _escaneosPorNivel : 2);


  /// Tier breakpoints for display: (maxQRs, commissionReduction, platformPercent)
  /// Escaneos por nivel y % de invitados, todo de pricing_config.
  List<({int max, double reduction, double platformPercent})> get tierBreakpoints {
    final n = _escaneosPorNivel > 0 ? _escaneosPorNivel : 2;
    return [
      for (var t = 1; t <= 5; t++)
        (
          max: t * n,
          reduction: reductionForTier(t),
          platformPercent: platformPercentForTier(t),
        ),
    ];
  }

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

      final countryCode = driverData?['country_code'] ?? 'US';
      final stateCode = driverData?['state_code'];
      _stateCode = stateCode ?? '';

      // % base: MISMA fuente que el resto de la app, con caida a la fila DEFAULT
      // del pais. Antes se buscaba solo por state_code exacto y, como los
      // choferes traen el estado vacio, no encontraba fila y la comision se
      // quedaba en 0 ("Comision Toro: 0%" en el home).
      final live = await LivePricing.load(
        countryCode: countryCode,
        stateCode: stateCode as String?,
      );
      if (live != null) {
        _baseDriverPercent = live.driver;
        _insurancePercent = live.insurance;
        _ivaPercent = live.iva;
        // OJO: la columna platform_commission (12 % en MX BC) NO es lo que se
        // queda TORO. El motor le da el RESIDUO: gross - chofer - fondo, o sea
        // 20 %. Con la columna, el nivel 5 pintaba TORO en -3 %, un numero
        // imposible. Se usa el residuo, que es lo que de verdad reparte
        // stripe-process-split, y si no cuadra se cae a la columna.
        final residuo = 100 - live.driver - live.insurance;
        _basePlatformPercent = residuo > 0 ? residuo : live.platform;
      }

      // qr_max_level, con el mismo criterio: estado del chofer -> DEFAULT.
      final rows = await _client
          .from('pricing_config')
          .select('state_code, qr_max_level, qr_scans_per_level, '
              'referral_tier_shares_json, referral_first_ride_share_pct, '
              'promo_active, first_ride_discount')
          .eq('country_code', countryCode)
          .eq('is_active', true);
      final list = (rows as List).cast<Map<String, dynamic>>();
      if (list.isNotEmpty) {
        final state = (stateCode ?? '').toString();
        Map<String, dynamic>? row;
        for (final r in list) {
          if (state.isNotEmpty && (r['state_code']?.toString() ?? '') == state) {
            row = r;
            break;
          }
        }
        row ??= list.firstWhere(
          (r) => (r['state_code']?.toString() ?? '') == 'DEFAULT',
          orElse: () => list.first,
        );
        _qrMaxLevel = (row['qr_max_level'] as num?)?.toInt() ?? 30;
        _configRow = row;
        _escaneosPorNivel =
            (row['qr_scans_per_level'] as num?)?.toInt() ?? 2;
      }

      // ESCALERA DE INVITADOS: % del chofer por nivel (0..5) en viajes de
      // pasajeros que EL invito. Sale de referral_tier_shares_json, la MISMA
      // lista que reparte la RPC referral_share_for_ride. La escala vieja
      // (qr_tier_reductions_json, bono sobre TODOS los viajes) quedo RETIRADA
      // en la base (en ceros) el 30 sep 2026.
      final escalera = (_configRow?['referral_tier_shares_json'] as List?)
          ?.map((e) => (e as num).toDouble())
          .toList();
      if (escalera != null && escalera.length >= 6) {
        _referralShares = escalera;
      }
      final primerViaje =
          (_configRow?['referral_first_ride_share_pct'] as num?)?.toDouble();
      if (primerViaje != null && primerViaje > 0) {
        _firstRideSharePct = primerViaje;
      }

      // Promo del invitado (la MISMA palanca que aplica el rider al cobrar:
      // promo_active + first_ride_discount, con su tope). Solo para contarlo.
      _promoInvitadoActiva = _configRow?['promo_active'] == true;
      _descuentoInvitadoPct =
          (_configRow?['first_ride_discount'] as num?)?.toDouble() ?? 0;

      // OJO: aqui habia un override que forzaba _qrMaxLevel = 30 para MX. Eso
      // pisaba el valor del admin (hoy qr_max_level = 10) y la pantalla decia
      // "0/30" cuando el maximo real es 10. Manda pricing_config, punto.

      AppLogger.log('DRIVER_QR -> Config loaded: max=$_qrMaxLevel, escalera de invitados: $_referralShares');
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
    final oldTier = currentTier;

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

      // Detect tier change and notify
      final newTier = currentTier;
      if (newTier > oldTier) {
        _onTierUp(oldTier, newTier);
      }
    } catch (e) {
      AppLogger.log('DRIVER_QR -> Error incrementing level: $e');
    }
  }

  /// Called when driver reaches a higher tier. Records audit + sends notification.
  Future<void> _onTierUp(int oldTier, int newTier) async {
    final newPlatform = platformPercentForTier(newTier);
    final newDriver = driverPercentForTier(newTier);

    AppLogger.log('DRIVER_QR -> TIER UP! $oldTier → $newTier (platform ${newPlatform.toStringAsFixed(0)}%, driver ${newDriver.toStringAsFixed(0)}%)');

    // Record tier change in notifications table for in-app display
    try {
      await _client.from('notifications').insert({
        'user_id': _driverId,
        'type': 'qr_tier_change',
        'title': 'Tier $newTier Unlocked!',
        'body': 'Commission reduced to ${newPlatform.toStringAsFixed(0)}%. You now earn ${newDriver.toStringAsFixed(0)}% of every ride.',
        'read': false,
        'data': {
          'old_tier': oldTier,
          'new_tier': newTier,
          'effective_platform_pct': newPlatform,
          'effective_driver_pct': newDriver,
        },
      });
    } catch (e) {
      AppLogger.log('DRIVER_QR -> Error recording tier notification: $e');
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

  /// Nivel (0-5) para un numero de escaneos: la MISMA formula que la RPC
  /// qr_nivel_de (2 escaneos por nivel). Antes usaba metas 4/9/19/34 de un
  /// diseno viejo que nadie mas compartia.
  int _getTierForLevel(int level) {
    if (level <= 0) return 0;
    final n = _escaneosPorNivel > 0 ? _escaneosPorNivel : 2;
    return (level ~/ n).clamp(0, 5);
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
