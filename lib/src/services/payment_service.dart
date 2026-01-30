import 'dart:math';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../config/stripe_config.dart';
import '../models/earning_model.dart';

class PaymentService {
  final SupabaseClient _client = SupabaseConfig.client;

  // Initialize Stripe
  static Future<void> initialize() async {
    Stripe.publishableKey = StripeConfig.publishableKey;
    await Stripe.instance.applySettings();
  }

  // Helper to safely extract earnings from a delivery record
  // Prefers driver_earnings (NET amount with all deductions)
  // driver_earnings already INCLUDES tip - DO NOT add tip separately
  // ⚠️ NO FALLBACK - todos los viajes deben tener driver_earnings de BD
  double _getEarningsFromDelivery(Map<String, dynamic> item) {
    final driverEarnings = (item['driver_earnings'] as num?)?.toDouble();
    if (driverEarnings != null && driverEarnings > 0) {
      return driverEarnings;
    }

    // ⚠️ NO FALLBACK - Si no hay driver_earnings, el Edge Function no procesó el split
    return 0;
  }

  // Helper to get base fare from delivery
  double _getBaseFare(Map<String, dynamic> item) {
    return (item['base_fare'] as num?)?.toDouble() ??
           (item['base_price'] as num?)?.toDouble() ?? 0;
  }

  // Helper to get surge from delivery
  double _getSurgeAmount(Map<String, dynamic> item) {
    return (item['surge_amount'] as num?)?.toDouble() ??
           (item['surge_bonus'] as num?)?.toDouble() ?? 0;
  }

  // Helper to get promotions from delivery
  double _getPromotions(Map<String, dynamic> item) {
    return (item['promotion_amount'] as num?)?.toDouble() ??
           (item['promo_discount'] as num?)?.toDouble() ?? 0;
  }

  // Helper to get platform fee from delivery
  double _getPlatformFee(Map<String, dynamic> item) {
    return (item['platform_fee'] as num?)?.toDouble() ??
           (item['service_fee'] as num?)?.toDouble() ??
           (item['commission'] as num?)?.toDouble() ?? 0;
  }

  // Helper to get QR boost from delivery
  double _getQRBoost(Map<String, dynamic> item) {
    return (item['qr_boost'] as num?)?.toDouble() ?? 0;
  }

  // Helper to get peak hours bonus from delivery
  double _getPeakHoursBonus(Map<String, dynamic> item) {
    return (item['peak_hours_bonus'] as num?)?.toDouble() ?? 0;
  }

  // Helper to get damage fee from delivery
  double _getDamageFee(Map<String, dynamic> item) {
    return (item['damage_fee'] as num?)?.toDouble() ?? 0;
  }

  // Helper to get extra bonus from delivery
  double _getExtraBonus(Map<String, dynamic> item) {
    return (item['extra_bonus'] as num?)?.toDouble() ?? 0;
  }

  // Helper to get distance from delivery
  double _getDistanceMiles(Map<String, dynamic> item) {
    // Try direct miles field
    final miles = (item['distance_miles'] as num?)?.toDouble();
    if (miles != null && miles > 0) return miles;

    // Try km fields and convert
    final km = (item['distance_km'] as num?)?.toDouble() ??
               (item['distance'] as num?)?.toDouble() ??
               (item['estimated_distance'] as num?)?.toDouble();
    if (km != null && km > 0) return km * 0.621371;

    // Calculate from coordinates using Haversine
    final pickupLat = (item['pickup_lat'] as num?)?.toDouble();
    final pickupLng = (item['pickup_lng'] as num?)?.toDouble();
    final destLat = (item['destination_lat'] as num?)?.toDouble() ??
                    (item['dropoff_lat'] as num?)?.toDouble();
    final destLng = (item['destination_lng'] as num?)?.toDouble() ??
                    (item['dropoff_lng'] as num?)?.toDouble();

    if (pickupLat != null && pickupLng != null && destLat != null && destLng != null) {
      return _haversineDistance(pickupLat, pickupLng, destLat, destLng);
    }

    // Default estimate
    return 5.0;
  }

  // Haversine formula to calculate distance in miles
  double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadiusMiles = 3958.8;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = (sin(dLat / 2) * sin(dLat / 2)) +
              (cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
               sin(dLon / 2) * sin(dLon / 2));
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusMiles * c * 1.3; // * 1.3 for road distance approximation
  }

  double _toRadians(double degree) => degree * pi / 180;

  // Helper to get duration minutes from delivery
  double _getDurationMinutes(Map<String, dynamic> item) {
    // Try direct duration fields first
    final directDuration = (item['duration_minutes'] as num?)?.toDouble() ??
                          (item['duration'] as num?)?.toDouble() ??
                          (item['estimated_duration'] as num?)?.toDouble();
    if (directDuration != null && directDuration > 0) return directDuration;

    // Calculate from timestamps
    final startedAt = DateTime.tryParse(item['started_at'] as String? ?? '');
    final deliveredAt = DateTime.tryParse(item['delivered_at'] as String? ?? '') ??
                        DateTime.tryParse(item['completed_at'] as String? ?? '');
    if (startedAt != null && deliveredAt != null) {
      return deliveredAt.difference(startedAt).inMinutes.toDouble();
    }

    // Estimate from distance (assume avg 25 mph = 2.4 min/mile)
    final miles = _getDistanceMiles(item);
    if (miles > 0) return miles * 2.4;

    // Default estimate per delivery
    return 15.0;
  }

  // Get driver's earnings summary - calculates from completed deliveries
  Future<EarningsSummary> getEarningsSummary(String driverId) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final startOfWeek = startOfDay.subtract(Duration(days: now.weekday - 1));
    final startOfMonth = DateTime(now.year, now.month, 1);

    // Initialize all counters
    double todayEarnings = 0, weekEarnings = 0, monthEarnings = 0, totalBalance = 0;
    double todayTips = 0, weekTips = 0, monthTips = 0;
    int todayRides = 0, weekRides = 0, monthRides = 0;

    // Week breakdown
    double weekBaseFare = 0, weekSurgeBonus = 0, weekPromotions = 0, weekPlatformFees = 0;
    double weekQRBoost = 0, weekPeakHoursBonus = 0, weekDamageFee = 0, weekExtraBonus = 0;
    double weekOnlineMinutes = 0, weekDrivingMinutes = 0, weekTotalMiles = 0;

    // Driver stats
    double acceptanceRate = 0, cancellationRate = 0, weeklyGoal = 500;
    int weekPoints = 0;

    try {
      // Get today's deliveries - try delivered_at first, then completed_at
      var todayResponse = await _client
          .from(SupabaseConfig.packageDeliveriesTable)
          .select()
          .eq('driver_id', driverId)
          .inFilter('status', ['completed', 'delivered'])
          .gte('delivered_at', startOfDay.toIso8601String());

      // If no results with delivered_at, try completed_at
      if ((todayResponse as List).isEmpty) {
        todayResponse = await _client
            .from(SupabaseConfig.packageDeliveriesTable)
            .select()
            .eq('driver_id', driverId)
            .inFilter('status', ['completed', 'delivered'])
            .gte('completed_at', startOfDay.toIso8601String());
      }

      // ═══════════════════════════════════════════════════════════════
      // CALCULAR todayEarnings INCLUYENDO TODOS LOS BONUSES
      // ═══════════════════════════════════════════════════════════════
      // PROPÓSITO: todayEarnings debe ser el TOTAL que el driver recibe HOY
      // INCLUYE: base earnings + QR boost + peak hours + damage fee + extra bonus + tips
      // PARA QUÉ: Mostrar el total correcto en home screen (card "Hoy")
      // ═══════════════════════════════════════════════════════════════
      for (var item in todayResponse) {
        final earnings = _getEarningsFromDelivery(item);
        final tips = (item['tip_amount'] as num?)?.toDouble() ?? 0;
        final itemQRBoost = _getQRBoost(item);
        final itemPeakHours = _getPeakHoursBonus(item);
        final itemDamageFee = _getDamageFee(item);
        final itemExtraBonus = _getExtraBonus(item);

        final totalForToday = earnings + itemQRBoost + itemPeakHours + itemDamageFee + itemExtraBonus + tips;
        todayEarnings += totalForToday;
        todayTips += tips;
      }
      todayRides = todayResponse.length;

      // Get week's deliveries - try delivered_at first, then completed_at
      var weekResponse = await _client
          .from(SupabaseConfig.packageDeliveriesTable)
          .select()
          .eq('driver_id', driverId)
          .inFilter('status', ['completed', 'delivered'])
          .gte('delivered_at', startOfWeek.toIso8601String());

      // If no results with delivered_at, try completed_at
      if ((weekResponse as List).isEmpty) {
        weekResponse = await _client
            .from(SupabaseConfig.packageDeliveriesTable)
            .select()
            .eq('driver_id', driverId)
            .inFilter('status', ['completed', 'delivered'])
            .gte('completed_at', startOfWeek.toIso8601String());
      }

      for (var item in weekResponse) {
        final earnings = _getEarningsFromDelivery(item);
        final tips = (item['tip_amount'] as num?)?.toDouble() ?? 0;

        // Detailed breakdown - NO FALLBACKS, solo valores de BD
        final baseFare = _getBaseFare(item);
        weekBaseFare += baseFare; // Sin fallback - valor real de BD o 0

        // QR Boost: calculated on driver earnings, not gross (handled by backend)
        final qrBoost = _getSurgeAmount(item);
        weekSurgeBonus += qrBoost; // No fallback - comes from database

        final promotions = _getPromotions(item);
        weekPromotions += promotions;

        final platformFee = _getPlatformFee(item);
        weekPlatformFees += platformFee; // Sin fallback - valor real de BD o 0

        // New breakdown fields - extract values first
        final itemQRBoost = _getQRBoost(item);
        final itemPeakHours = _getPeakHoursBonus(item);
        final itemDamageFee = _getDamageFee(item);
        final itemExtraBonus = _getExtraBonus(item);

        weekQRBoost += itemQRBoost;
        weekPeakHoursBonus += itemPeakHours;
        weekDamageFee += itemDamageFee;
        weekExtraBonus += itemExtraBonus;

        // ═══════════════════════════════════════════════════════════════
        // CALCULAR weekEarnings INCLUYENDO TODOS LOS BONUSES
        // ═══════════════════════════════════════════════════════════════
        // PROPÓSITO: weekEarnings debe ser el TOTAL que el driver recibe
        // INCLUYE: base earnings + QR boost + peak hours + damage fee + extra bonus + tips
        // PARA QUÉ: Mostrar el total correcto en home screen y sincronizar con earnings screen
        // ═══════════════════════════════════════════════════════════════
        final totalEarningsForTrip = earnings + itemQRBoost + itemPeakHours + itemDamageFee + itemExtraBonus + tips;
        weekEarnings += totalEarningsForTrip;
        weekTips += tips;

        weekTotalMiles += _getDistanceMiles(item);
        weekDrivingMinutes += _getDurationMinutes(item);
      }
      weekRides = weekResponse.length;

      // Get month's deliveries - try delivered_at first, then completed_at
      var monthResponse = await _client
          .from(SupabaseConfig.packageDeliveriesTable)
          .select()
          .eq('driver_id', driverId)
          .inFilter('status', ['completed', 'delivered'])
          .gte('delivered_at', startOfMonth.toIso8601String());

      // If no results with delivered_at, try completed_at
      if ((monthResponse as List).isEmpty) {
        monthResponse = await _client
            .from(SupabaseConfig.packageDeliveriesTable)
            .select()
            .eq('driver_id', driverId)
            .inFilter('status', ['completed', 'delivered'])
            .gte('completed_at', startOfMonth.toIso8601String());
      }

      // ═══════════════════════════════════════════════════════════════
      // CALCULAR monthEarnings INCLUYENDO TODOS LOS BONUSES
      // ═══════════════════════════════════════════════════════════════
      for (var item in monthResponse) {
        final earnings = _getEarningsFromDelivery(item);
        final tips = (item['tip_amount'] as num?)?.toDouble() ?? 0;
        final itemQRBoost = _getQRBoost(item);
        final itemPeakHours = _getPeakHoursBonus(item);
        final itemDamageFee = _getDamageFee(item);
        final itemExtraBonus = _getExtraBonus(item);

        final totalForMonth = earnings + itemQRBoost + itemPeakHours + itemDamageFee + itemExtraBonus + tips;
        monthEarnings += totalForMonth;
        monthTips += tips;
      }
      monthRides = monthResponse.length;

      // Get total balance (all time completed)
      final totalResponse = await _client
          .from(SupabaseConfig.packageDeliveriesTable)
          .select()
          .eq('driver_id', driverId)
          .inFilter('status', ['completed', 'delivered']);

      // ═══════════════════════════════════════════════════════════════
      // CALCULAR totalBalance INCLUYENDO TODOS LOS BONUSES (All time)
      // ═══════════════════════════════════════════════════════════════
      for (var item in totalResponse) {
        final earnings = _getEarningsFromDelivery(item);
        final tips = (item['tip_amount'] as num?)?.toDouble() ?? 0;
        final itemQRBoost = _getQRBoost(item);
        final itemPeakHours = _getPeakHoursBonus(item);
        final itemDamageFee = _getDamageFee(item);
        final itemExtraBonus = _getExtraBonus(item);

        final totalForTrip = earnings + itemQRBoost + itemPeakHours + itemDamageFee + itemExtraBonus + tips;
        totalBalance += totalForTrip;
      }

      // Get driver stats from drivers table
      final driverStats = await _client
          .from('drivers')
          .select('acceptance_rate, weekly_goal')
          .eq('id', driverId)
          .maybeSingle();

      if (driverStats != null) {
        final rateFromDb = (driverStats['acceptance_rate'] as num?)?.toDouble() ?? 0;
        acceptanceRate = rateFromDb > 0 ? rateFromDb * 100 : 95.0;
        weeklyGoal = (driverStats['weekly_goal'] as num?)?.toDouble() ?? 500.0;
      }

      // Get online minutes from driver_sessions table (real tracking)
      final sessions = await _client
          .from('driver_sessions')
          .select('started_at, ended_at')
          .eq('driver_id', driverId)
          .gte('started_at', startOfWeek.toIso8601String());

      for (var session in sessions) {
        final startedAt = DateTime.parse(session['started_at']);
        final endedAt = session['ended_at'] != null
            ? DateTime.parse(session['ended_at'])
            : DateTime.now();
        weekOnlineMinutes += endedAt.difference(startedAt).inMinutes;
      }

      // Try to get more data from driver_rankings table
      final rankings = await _client
          .from('driver_rankings')
          .select()
          .eq('driver_id', driverId)
          .maybeSingle();

      if (rankings != null) {
        final rankAcceptance = (rankings['acceptance_rate'] as num?)?.toDouble() ?? 0;
        if (rankAcceptance > 0) acceptanceRate = rankAcceptance;

        final rankCancellation = (rankings['cancellation_rate'] as num?)?.toDouble() ?? 0;
        if (rankCancellation > 0) cancellationRate = rankCancellation;

        final rankMiles = (rankings['week_miles'] as num?)?.toDouble() ?? 0;
        if (rankMiles > 0) weekTotalMiles = rankMiles;

        // Only use rankings online hours if sessions are empty
        if (weekOnlineMinutes == 0) {
          final rankOnlineHours = (rankings['week_online_hours'] as num?)?.toDouble() ?? 0;
          if (rankOnlineHours > 0) weekOnlineMinutes = rankOnlineHours * 60;
        }
      }

      // Final fallback for online minutes
      if (weekOnlineMinutes == 0 && weekRides > 0) {
        weekOnlineMinutes = weekRides * 25; // Estimate 25 min per ride
      }

      // Miles: estimate from rides if not tracked
      if (weekTotalMiles == 0 && weekRides > 0) {
        weekTotalMiles = weekRides * 5.0; // Estimate 5 miles per ride
      }

      // Acceptance rate: default to 100% for new drivers
      if (acceptanceRate == 0) acceptanceRate = 100.0;

      // Cancellation rate: default to 0% for new drivers
      if (cancellationRate == 0 && weekRides > 0) cancellationRate = 2.0;

      // Get QR points from driver_qr_points table (WB - Weekly Bonus)
      final qrPoints = await _client
          .from('driver_qr_points')
          .select('qrs_accepted, current_level')
          .eq('driver_id', driverId)
          .gte('week_start', startOfWeek.toIso8601String())
          .maybeSingle();

      if (qrPoints != null) {
        weekPoints = (qrPoints['qrs_accepted'] as num?)?.toInt() ??
                     (qrPoints['current_level'] as num?)?.toInt() ?? 0;
      }

    } catch (e) {
      // Error getting earnings
    }

    return EarningsSummary(
      todayEarnings: todayEarnings,
      weekEarnings: weekEarnings,
      monthEarnings: monthEarnings,
      totalBalance: totalBalance,
      todayRides: todayRides,
      weekRides: weekRides,
      monthRides: monthRides,
      todayTips: todayTips,
      weekTips: weekTips,
      monthTips: monthTips,
      weekBaseFare: weekBaseFare,
      weekSurgeBonus: weekSurgeBonus,
      weekPromotions: weekPromotions,
      weekPlatformFees: weekPlatformFees,
      weekQRBoost: weekQRBoost,
      weekPeakHoursBonus: weekPeakHoursBonus,
      weekDamageFee: weekDamageFee,
      weekExtraBonus: weekExtraBonus,
      weekOnlineMinutes: weekOnlineMinutes,
      weekDrivingMinutes: weekDrivingMinutes,
      weekTotalMiles: weekTotalMiles,
      acceptanceRate: acceptanceRate,
      cancellationRate: cancellationRate,
      weekPoints: weekPoints,
      weeklyGoal: weeklyGoal,
    );
  }

  // Get earnings history - reads from deliveries table
  Future<List<EarningModel>> getEarningsHistory(
    String driverId, {
    int limit = 50,
    int offset = 0,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      // Try with delivered_at first
      var query = _client
          .from(SupabaseConfig.packageDeliveriesTable)
          .select()
          .eq('driver_id', driverId)
          .inFilter('status', ['completed', 'delivered']);

      if (startDate != null) {
        query = query.gte('delivered_at', startDate.toIso8601String());
      }
      if (endDate != null) {
        query = query.lte('delivered_at', endDate.toIso8601String());
      }

      var response = await query
          .order('delivered_at', ascending: false)
          .range(offset, offset + limit - 1);

      // If no results and no date filter, try ordering by completed_at
      if ((response as List).isEmpty && startDate == null && endDate == null) {
        response = await _client
            .from(SupabaseConfig.packageDeliveriesTable)
            .select()
            .eq('driver_id', driverId)
            .inFilter('status', ['completed', 'delivered'])
            .order('completed_at', ascending: false)
            .range(offset, offset + limit - 1);
      }

      return response.map((delivery) {
        // driver_earnings already includes tip - DO NOT add tip separately
        final amount = _getEarningsFromDelivery(delivery);
        final serviceType = delivery['service_type'] as String? ?? 'ride';

        // Use delivered_at or completed_at for date
        final dateStr = delivery['delivered_at'] as String? ?? delivery['completed_at'] as String? ?? '';

        return EarningModel(
          id: delivery['id'] as String,
          driverId: driverId,
          rideId: delivery['id'] as String,
          type: serviceType == 'package' ? TransactionType.rideEarning : TransactionType.rideEarning,
          amount: amount, // driver_earnings already includes tip
          description: serviceType == 'package'
              ? 'Entrega de paquete'
              : serviceType == 'carpool'
                  ? 'Viaje compartido'
                  : 'Viaje completado',
          createdAt: DateTime.tryParse(dateStr) ?? DateTime.now(),
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  // Get weekly earnings breakdown - reads from deliveries table
  Future<List<DailyEarning>> getWeeklyBreakdown(String driverId) async {
    final now = DateTime.now();
    final startOfWeek = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));

    List<DailyEarning> weeklyEarnings = [];

    for (int i = 0; i < 7; i++) {
      final dayStart = startOfWeek.add(Duration(days: i));
      final dayEnd = dayStart.add(const Duration(days: 1));

      try {
        // Try delivered_at first
        var response = await _client
            .from(SupabaseConfig.packageDeliveriesTable)
            .select()
            .eq('driver_id', driverId)
            .inFilter('status', ['completed', 'delivered'])
            .gte('delivered_at', dayStart.toIso8601String())
            .lt('delivered_at', dayEnd.toIso8601String());

        // If no results, try completed_at
        if ((response as List).isEmpty) {
          response = await _client
              .from(SupabaseConfig.packageDeliveriesTable)
              .select()
              .eq('driver_id', driverId)
              .inFilter('status', ['completed', 'delivered'])
              .gte('completed_at', dayStart.toIso8601String())
              .lt('completed_at', dayEnd.toIso8601String());
        }

        double dayTotal = 0;
        for (var item in response) {
          // driver_earnings already includes tip - DO NOT add tip separately
          dayTotal += _getEarningsFromDelivery(item);
        }

        weeklyEarnings.add(DailyEarning(
          date: dayStart,
          amount: dayTotal,
          ridesCount: response.length,
        ));
      } catch (e) {
        weeklyEarnings.add(DailyEarning(
          date: dayStart,
          amount: 0,
          ridesCount: 0,
        ));
      }
    }

    return weeklyEarnings;
  }

  // Record earning from completed ride
  Future<void> recordEarning({
    required String driverId,
    required String rideId,
    required double amount,
    required double tip,
    required TransactionType type,
  }) async {
    await _client.from(SupabaseConfig.earningsTable).insert({
      'driver_id': driverId,
      'ride_id': rideId,
      'amount': amount,
      'tip': tip,
      'type': type.name,
      'description': _getTransactionDescription(type, amount),
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  String _getTransactionDescription(TransactionType type, double amount) {
    switch (type) {
      case TransactionType.rideEarning:
        return 'Ganancia por viaje';
      case TransactionType.tip:
        return 'Propina recibida';
      case TransactionType.bonus:
        return 'Bono de incentivo';
      case TransactionType.referralBonus:
        return 'Bono por referido';
      case TransactionType.withdrawal:
        return 'Retiro a cuenta bancaria';
      case TransactionType.platformFee:
        return 'Comisión de plataforma';
      case TransactionType.adjustment:
        return 'Ajuste de balance';
    }
  }

  // Request payout
  Future<Map<String, dynamic>> requestPayout({
    required String driverId,
    required double amount,
    required String bankAccountId,
  }) async {
    final response = await _client.functions.invoke(
      'process-driver-payout',
      body: {
        'driver_id': driverId,
        'amount': amount,
        'bank_account_id': bankAccountId,
      },
    );

    if (response.status != 200) {
      throw Exception('Error al procesar el retiro: ${response.data}');
    }

    return response.data as Map<String, dynamic>;
  }

  // Get payout history
  Future<List<Map<String, dynamic>>> getPayoutHistory(String driverId) async {
    final response = await _client
        .from(SupabaseConfig.payoutsTable)
        .select()
        .eq('driver_id', driverId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  // Add bank account for payouts
  Future<Map<String, dynamic>> addBankAccount({
    required String driverId,
    required String accountNumber,
    required String routingNumber,
    required String accountHolderName,
  }) async {
    final response = await _client.functions.invoke(
      'add-bank-account',
      body: {
        'driver_id': driverId,
        'account_number': accountNumber,
        'routing_number': routingNumber,
        'account_holder_name': accountHolderName,
      },
    );

    if (response.status != 200) {
      throw Exception('Error al agregar cuenta bancaria: ${response.data}');
    }

    return response.data as Map<String, dynamic>;
  }

  // Get saved bank accounts
  Future<List<Map<String, dynamic>>> getBankAccounts(String driverId) async {
    final response = await _client
        .from(SupabaseConfig.bankAccountsTable)
        .select()
        .eq('driver_id', driverId)
        .eq('is_active', true);

    return List<Map<String, dynamic>>.from(response);
  }

  // Delete bank account
  Future<void> deleteBankAccount(String accountId) async {
    await _client
        .from(SupabaseConfig.bankAccountsTable)
        .update({'is_active': false})
        .eq('id', accountId);
  }

  // Set default bank account
  Future<void> setDefaultBankAccount(String driverId, String accountId) async {
    await _client
        .from(SupabaseConfig.bankAccountsTable)
        .update({'is_default': false})
        .eq('driver_id', driverId);

    await _client
        .from(SupabaseConfig.bankAccountsTable)
        .update({'is_default': true})
        .eq('id', accountId);
  }

  // Get Stripe Connect onboarding link
  Future<String> getStripeOnboardingLink(String driverId) async {
    final response = await _client.functions.invoke(
      'create-stripe-connect-link',
      body: {'driver_id': driverId},
    );

    if (response.status != 200) {
      throw Exception('Error al obtener link de Stripe: ${response.data}');
    }

    return response.data['url'] as String;
  }

  // Check Stripe Connect status
  Future<StripeConnectStatus> getStripeConnectStatus(String driverId) async {
    final response = await _client
        .from(SupabaseConfig.stripeAccountsTable)
        .select()
        .eq('driver_id', driverId)
        .maybeSingle();

    if (response == null) {
      return StripeConnectStatus.notConnected;
    }

    final chargesEnabled = response['charges_enabled'] as bool? ?? false;
    final payoutsEnabled = response['payouts_enabled'] as bool? ?? false;

    if (chargesEnabled && payoutsEnabled) {
      return StripeConnectStatus.active;
    } else if (response['stripe_account_id'] != null) {
      return StripeConnectStatus.pending;
    }

    return StripeConnectStatus.notConnected;
  }

  // Get transaction details
  Future<EarningModel?> getTransactionDetails(String transactionId) async {
    final response = await _client
        .from(SupabaseConfig.earningsTable)
        .select()
        .eq('id', transactionId)
        .maybeSingle();

    if (response == null) return null;
    return EarningModel.fromJson(response);
  }

  // Get earnings by date range
  Future<double> getEarningsByDateRange({
    required String driverId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final response = await _client
        .from(SupabaseConfig.earningsTable)
        .select('amount')
        .eq('driver_id', driverId)
        .gte('created_at', startDate.toIso8601String())
        .lte('created_at', endDate.toIso8601String());

    double total = 0;
    for (var item in response) {
      total += (item['amount'] as num).toDouble();
    }

    return total;
  }

  // Get driver rankings (leaderboard) - national
  Future<List<DriverRanking>> getDriverRankings({
    int limit = 50,
    String sortBy = 'points',
  }) async {
    try {
      final response = await _client
          .from('driver_rankings')
          .select('*, drivers!inner(first_name, last_name, profile_image_url)')
          .order(sortBy, ascending: false)
          .limit(limit);

      return (response as List).map((item) {
        return DriverRanking.fromJson(
          item,
          driver: item['drivers'] as Map<String, dynamic>?,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  // Get driver rankings by state
  Future<List<DriverRanking>> getDriverRankingsByState({
    required String state,
    int limit = 50,
    String sortBy = 'points',
  }) async {
    try {
      final response = await _client
          .from('driver_rankings')
          .select('*, drivers!inner(first_name, last_name, profile_image_url)')
          .eq('driver_state', state)
          .order(sortBy, ascending: false)
          .limit(limit);

      return (response as List).map((item) {
        return DriverRanking.fromJson(
          item,
          driver: item['drivers'] as Map<String, dynamic>?,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  // Get current driver's ranking position
  Future<DriverRanking?> getDriverRanking(String driverId) async {
    try {
      final response = await _client
          .from('driver_rankings')
          .select('*, drivers!inner(first_name, last_name, profile_image_url)')
          .eq('driver_id', driverId)
          .maybeSingle();

      if (response == null) return null;

      return DriverRanking.fromJson(
        response,
        driver: response['drivers'] as Map<String, dynamic>?,
      );
    } catch (e) {
      return null;
    }
  }

  // Get tips total
  Future<double> getTipsTotal(String driverId, {DateTime? since}) async {
    var query = _client
        .from(SupabaseConfig.earningsTable)
        .select('tip')
        .eq('driver_id', driverId);

    if (since != null) {
      query = query.gte('created_at', since.toIso8601String());
    }

    final response = await query;

    double total = 0;
    for (var item in response) {
      total += (item['tip'] as num?)?.toDouble() ?? 0;
    }

    return total;
  }
}

// Helper class for daily earnings
class DailyEarning {
  final DateTime date;
  final double amount;
  final int ridesCount;

  DailyEarning({
    required this.date,
    required this.amount,
    this.ridesCount = 0,
  });
}

enum StripeConnectStatus {
  notConnected,
  pending,
  active,
}

// Driver ranking model for leaderboard
class DriverRanking {
  final String driverId;
  final String? driverName;
  final String? avatarUrl;
  final int totalTrips;
  final double totalEarnings;
  final double totalTips;
  final double averageRating;
  final double acceptanceRate;
  final int points;
  final int? stateRank;
  final int? usaRank;
  final String? driverState;

  DriverRanking({
    required this.driverId,
    this.driverName,
    this.avatarUrl,
    this.totalTrips = 0,
    this.totalEarnings = 0,
    this.totalTips = 0,
    this.averageRating = 5.0,
    this.acceptanceRate = 100,
    this.points = 0,
    this.stateRank,
    this.usaRank,
    this.driverState,
  });

  factory DriverRanking.fromJson(Map<String, dynamic> json, {Map<String, dynamic>? driver}) {
    return DriverRanking(
      driverId: json['driver_id'] as String,
      driverName: driver?['first_name'] != null
          ? '${driver!['first_name']} ${driver['last_name'] ?? ''}'.trim()
          : null,
      avatarUrl: driver?['profile_image_url'] as String?,
      totalTrips: json['total_trips'] as int? ?? 0,
      totalEarnings: (json['total_earnings'] as num?)?.toDouble() ?? 0,
      totalTips: (json['total_tips'] as num?)?.toDouble() ?? 0,
      averageRating: (json['average_rating'] as num?)?.toDouble() ?? 5.0,
      acceptanceRate: (json['acceptance_rate'] as num?)?.toDouble() ?? 100,
      points: json['points'] as int? ?? 0,
      stateRank: json['state_rank'] as int?,
      usaRank: json['usa_rank'] as int?,
      driverState: json['driver_state'] as String?,
    );
  }
}
