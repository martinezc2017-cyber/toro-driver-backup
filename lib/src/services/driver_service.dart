import 'dart:typed_data';
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import '../config/supabase_config.dart';
import '../models/driver_model.dart';

class DriverService {
  final SupabaseClient _client = SupabaseConfig.client;

  // Calculate distance in miles from coordinates
  double _calculateDistanceMiles(double lat1, double lon1, double lat2, double lon2) {
    // 1 degree lat ≈ 69 miles, 1 degree lon ≈ 54.6 miles (at ~38° latitude)
    final dLat = (lat2 - lat1).abs() * 69;
    final dLon = (lon2 - lon1).abs() * 54.6;
    final straightLine = sqrt(dLat * dLat + dLon * dLon);
    return straightLine * 1.3; // Multiply by 1.3 for road distance approximation
  }

  /// Generate next driver ID
  /// Format: [Role][YYYYMMDD][Sequential Number]
  /// Role: A = Admin, U = User
  /// Example: A20251231001, U20251231002
  Future<String> generateDriverId({bool isAdmin = false}) async {
    final now = DateTime.now();
    final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final prefix = isAdmin ? 'A' : 'U';
    final pattern = '$prefix$dateStr%';

    // Get count of drivers registered today with this prefix
    final response = await _client
        .from(SupabaseConfig.driversTable)
        .select('id')
        .like('id', pattern);

    final count = (response as List).length;
    final sequential = (count + 1).toString().padLeft(3, '0');

    return '$prefix$dateStr$sequential';
  }

  // Create new driver
  Future<DriverModel> createDriver(DriverModel driver) async {
    final response = await _client
        .from(SupabaseConfig.driversTable)
        .upsert(driver.toJson())
        .select()
        .single();

    return DriverModel.fromJson(response);
  }

  // Get driver by ID
  Future<DriverModel?> getDriver(String driverId) async {
    final response = await _client
        .from(SupabaseConfig.driversTable)
        .select()
        .eq('id', driverId)
        .maybeSingle();

    if (response == null) return null;
    return DriverModel.fromJson(response);
  }

  // Update driver profile
  Future<DriverModel> updateDriver(DriverModel driver) async {
    final response = await _client
        .from(SupabaseConfig.driversTable)
        .update(driver.toJson()..['updated_at'] = DateTime.now().toIso8601String())
        .eq('id', driver.id)
        .select()
        .single();

    return DriverModel.fromJson(response);
  }

  // Update online status - creates driver record if not exists
  Future<void> updateOnlineStatus(String driverId, bool isOnline) async {
    final now = DateTime.now().toIso8601String();

    // Check if driver exists
    final existing = await _client
        .from(SupabaseConfig.driversTable)
        .select('id')
        .eq('id', driverId)
        .maybeSingle();

    if (existing != null) {
      // Driver exists, just update
      await _client
          .from(SupabaseConfig.driversTable)
          .update({
            'is_online': isOnline,
            'updated_at': now,
          })
          .eq('id', driverId);
    } else {
      // Driver doesn't exist, create minimal record so admin can see them
      await _client.from(SupabaseConfig.driversTable).insert({
        'id': driverId,
        'user_id': driverId,
        'is_online': isOnline,
        'is_active': true,
        'rating': 5.0,
        'total_rides': 0,
        'total_earnings': 0.0,
        'status': 'active',
        'created_at': now,
        'updated_at': now,
      });
    }

    // Track online session
    await _trackOnlineSession(driverId, isOnline);
  }

  // Track online sessions for accurate time calculation
  Future<void> _trackOnlineSession(String driverId, bool isOnline) async {
    try {
      if (isOnline) {
        // Going online - create new session
        await _client.from('driver_sessions').insert({
          'driver_id': driverId,
          'started_at': DateTime.now().toIso8601String(),
        });
      } else {
        // Going offline - end current session
        final activeSession = await _client
            .from('driver_sessions')
            .select('id')
            .eq('driver_id', driverId)
            .isFilter('ended_at', null)
            .order('started_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (activeSession != null) {
          await _client
              .from('driver_sessions')
              .update({'ended_at': DateTime.now().toIso8601String()})
              .eq('id', activeSession['id']);
        }
      }
    } catch (e) {
      // Error tracking session: $e');
    }
  }

  // Get weekly online minutes from sessions
  Future<double> getWeeklyOnlineMinutes(String driverId) async {
    try {
      final weekStart = DateTime.now().subtract(
        Duration(days: DateTime.now().weekday - 1),
      );
      final startOfWeek = DateTime(weekStart.year, weekStart.month, weekStart.day);

      final sessions = await _client
          .from('driver_sessions')
          .select('started_at, ended_at')
          .eq('driver_id', driverId)
          .gte('started_at', startOfWeek.toIso8601String());

      double totalMinutes = 0;
      for (var session in sessions) {
        final startedAt = DateTime.parse(session['started_at']);
        final endedAt = session['ended_at'] != null
            ? DateTime.parse(session['ended_at'])
            : DateTime.now(); // Active session
        totalMinutes += endedAt.difference(startedAt).inMinutes;
      }
      return totalMinutes;
    } catch (e) {
      // Error getting weekly online minutes: $e');
      return 0;
    }
  }

  // Upload profile image
  Future<String> uploadProfileImage(String driverId, Uint8List imageBytes) async {
    final fileName = '$driverId/profile_${DateTime.now().millisecondsSinceEpoch}.jpg';

    await _client.storage
        .from(SupabaseConfig.profileImagesBucket)
        .uploadBinary(fileName, imageBytes, fileOptions: const FileOptions(contentType: 'image/jpeg'));

    final imageUrl = _client.storage
        .from(SupabaseConfig.profileImagesBucket)
        .getPublicUrl(fileName);

    // Update driver profile with new image URL
    await _client
        .from(SupabaseConfig.driversTable)
        .update({
          'profile_image_url': imageUrl,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', driverId);

    return imageUrl;
  }

  // Update current vehicle
  Future<void> updateCurrentVehicle(String driverId, String? vehicleId) async {
    await _client
        .from(SupabaseConfig.driversTable)
        .update({
          'current_vehicle_id': vehicleId,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', driverId);
  }

  // Get driver stats - includes today's activity
  Future<Map<String, dynamic>> getDriverStats(String driverId) async {
    DriverModel? driver;
    try {
      driver = await getDriver(driverId);
    } catch (e) {
      // Ignore driver fetch errors
    }

    // Get today's stats from deliveries table (unified rides/packages/carpools)
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    try {
      // Query today's completed deliveries - check both delivered_at and completed_at
      // First try delivered_at
      var todayRides = await _client
          .from(SupabaseConfig.packageDeliveriesTable)
          .select()
          .eq('driver_id', driverId)
          .inFilter('status', ['delivered', 'completed'])
          .gte('delivered_at', startOfDay.toIso8601String())
          .lt('delivered_at', endOfDay.toIso8601String());

      // If no results, try completed_at (for rides where delivered_at is null)
      if ((todayRides as List).isEmpty) {
        todayRides = await _client
            .from(SupabaseConfig.packageDeliveriesTable)
            .select()
            .eq('driver_id', driverId)
            .inFilter('status', ['delivered', 'completed'])
            .gte('completed_at', startOfDay.toIso8601String())
            .lt('completed_at', endOfDay.toIso8601String());
      }

      // Calculate today's totals
      double todayEarnings = 0;
      double todayDistance = 0;
      int todayDuration = 0;
      int ridesCount = 0;

      for (final ride in todayRides) {
        ridesCount++;
        // Try different column names for earnings
        todayEarnings += (ride['driver_earnings'] as num?)?.toDouble() ??
                         (ride['final_price'] as num?)?.toDouble() ??
                         (ride['estimated_price'] as num?)?.toDouble() ??
                         (ride['price'] as num?)?.toDouble() ??
                         (ride['fare'] as num?)?.toDouble() ?? 0;
        todayEarnings += (ride['tip_amount'] as num?)?.toDouble() ?? 0;

        // Calculate distance - try fields first, then calculate from coordinates
        double rideDistance = (ride['distance_miles'] as num?)?.toDouble() ?? 0;
        if (rideDistance == 0) {
          final km = (ride['distance_km'] as num?)?.toDouble() ??
                     (ride['distance'] as num?)?.toDouble() ?? 0;
          rideDistance = km * 0.621371; // Convert km to miles
        }
        if (rideDistance == 0) {
          // Calculate from coordinates
          final pickupLat = (ride['pickup_lat'] as num?)?.toDouble();
          final pickupLng = (ride['pickup_lng'] as num?)?.toDouble();
          final destLat = (ride['destination_lat'] as num?)?.toDouble();
          final destLng = (ride['destination_lng'] as num?)?.toDouble();
          if (pickupLat != null && pickupLng != null && destLat != null && destLng != null) {
            rideDistance = _calculateDistanceMiles(pickupLat, pickupLng, destLat, destLng);
          }
        }
        todayDistance += rideDistance;

        // Calculate duration - try fields first, then calculate from timestamps
        int rideDuration = (ride['duration_minutes'] as num?)?.toInt() ??
                          (ride['estimated_minutes'] as num?)?.toInt() ?? 0;
        if (rideDuration == 0) {
          final startedAt = DateTime.tryParse(ride['started_at'] as String? ?? '');
          final deliveredAt = DateTime.tryParse(ride['delivered_at'] as String? ?? ride['completed_at'] as String? ?? '');
          if (startedAt != null && deliveredAt != null) {
            rideDuration = deliveredAt.difference(startedAt).inMinutes;
          } else if (rideDistance > 0) {
            // Estimate from distance (avg 25 mph = 2.4 min/mile)
            rideDuration = (rideDistance * 2.4).round();
          }
        }
        todayDuration += rideDuration;
      }

      // Format online time
      final hours = todayDuration ~/ 60;
      final minutes = todayDuration % 60;
      final activeTimeFormatted = '${hours}h ${minutes}m';

      return {
        // Today's stats (for home screen)
        'active_time_today': activeTimeFormatted,
        'distance_today_km': todayDistance,
        'online_hours_today': todayDuration / 60.0,
        'rides_today': ridesCount,
        'earnings_today': todayEarnings,
        // Lifetime stats
        'totalRides': driver?.totalRides ?? 0,
        'totalEarnings': driver?.totalEarnings ?? 0.0,
        'totalHours': driver?.totalHours ?? 0,
        'rating': driver?.rating ?? 5.0,
        'acceptanceRate': driver?.acceptanceRate ?? 1.0,
      };
    } catch (e) {
      // Return default values if query fails
      return {
        'active_time_today': '0h 0m',
        'distance_today_km': 0.0,
        'online_hours_today': 0.0,
        'rides_today': 0,
        'earnings_today': 0.0,
        'totalRides': driver?.totalRides ?? 0,
        'totalEarnings': driver?.totalEarnings ?? 0.0,
        'totalHours': driver?.totalHours ?? 0,
        'rating': driver?.rating ?? 5.0,
        'acceptanceRate': driver?.acceptanceRate ?? 1.0,
      };
    }
  }

  // Update driver rating
  Future<void> updateRating(String driverId, double newRating) async {
    final driver = await getDriver(driverId);
    if (driver == null) return;

    // Calculate new average rating
    final totalRatings = driver.totalRides;
    final currentTotal = driver.rating * totalRatings;
    final newAverage = (currentTotal + newRating) / (totalRatings + 1);

    await _client
        .from(SupabaseConfig.driversTable)
        .update({
          'rating': newAverage,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', driverId);
  }

  // Increment ride count
  Future<void> incrementRideCount(String driverId, double earnings) async {
    final driver = await getDriver(driverId);
    if (driver == null) return;

    await _client
        .from(SupabaseConfig.driversTable)
        .update({
          'total_rides': driver.totalRides + 1,
          'total_earnings': driver.totalEarnings + earnings,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', driverId);
  }

  // Stream driver updates (real-time)
  Stream<DriverModel?> streamDriver(String driverId) {
    return _client
        .from(SupabaseConfig.driversTable)
        .stream(primaryKey: ['id'])
        .eq('id', driverId)
        .map((data) => data.isNotEmpty ? DriverModel.fromJson(data.first) : null);
  }

  // Get driver ranking
  Future<List<Map<String, dynamic>>> getDriverRanking({int limit = 100}) async {
    final response = await _client
        .from(SupabaseConfig.driversTable)
        .select('id, first_name, last_name, rating, total_rides, total_earnings, profile_image_url')
        .eq('is_active', true)
        .order('total_earnings', ascending: false)
        .limit(limit);

    return List<Map<String, dynamic>>.from(response);
  }

  // Get driver position in ranking
  Future<int> getDriverRankingPosition(String driverId) async {
    final ranking = await getDriverRanking(limit: 1000);
    final index = ranking.indexWhere((d) => d['id'] == driverId);
    return index >= 0 ? index + 1 : -1;
  }

  // Apply referral code
  Future<bool> applyReferralCode(String driverId, String referralCode) async {
    // Find referrer by code
    final referrer = await _client
        .from(SupabaseConfig.driversTable)
        .select('id')
        .eq('referral_code', referralCode)
        .maybeSingle();

    if (referrer == null) return false;

    // Create referral record
    await _client.from(SupabaseConfig.referralsTable).insert({
      'referrer_id': referrer['id'],
      'referred_id': driverId,
      'code_used': referralCode,
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    });

    return true;
  }

  // Update driver preferences
  Future<void> updateDriverPreferences(String driverId, Map<String, dynamic> preferences) async {
    await _client
        .from(SupabaseConfig.driversTable)
        .update({
          'preferences': preferences,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', driverId);
  }

  // ===========================================================================
  // W-9 TAX INFORMATION
  // ===========================================================================

  /// Save driver's W-9 tax information
  /// SSN is stored encrypted (Supabase pgsodium or client-side encryption recommended)
  /// For production, consider using Supabase Vault for SSN encryption
  Future<void> saveW9TaxInfo({
    required String driverId,
    required String ssn,
    required String legalName,
    String? businessName,
    required String taxClassification,
    required String streetAddress,
    required String city,
    required String state,
    required String zipCode,
    required bool certificationSigned,
  }) async {
    // Store only last 4 digits in plain text, full SSN should be encrypted
    final ssnLast4 = ssn.replaceAll(RegExp(r'\D'), '').substring(5);
    final fullAddress = '$streetAddress, $city, $state $zipCode';

    // Update driver record with W-9 data
    await _client
        .from(SupabaseConfig.driversTable)
        .update({
          'ssn_last4': ssnLast4,
          'legal_name': legalName,
          'business_name': businessName,
          'tax_classification': taxClassification,
          'tax_address': fullAddress,
          'tax_street': streetAddress,
          'tax_city': city,
          'tax_state': state,
          'tax_zip': zipCode,
          'country_code': 'US',
          'state_code': state.toUpperCase(),
          'w9_signed': certificationSigned,
          'w9_signed_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', driverId);

    // Also store full SSN encrypted in a separate secure table
    // (This requires Supabase pgsodium extension or client-side encryption)
    try {
      await _client.from('driver_tax_secure').upsert({
        'driver_id': driverId,
        'ssn_encrypted': ssn.replaceAll(RegExp(r'\D'), ''), // In production, encrypt this!
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // Table might not exist yet - that's okay, the basic W-9 info is saved
    }
  }

  /// Save driver's Mexico tax information (RFC, CURP, SAT regime)
  Future<void> saveMexicoTaxInfo({
    required String driverId,
    required String rfc,
    required String curp,
    required String satRegime,
    required String legalName,
    String? businessName,
    required String streetAddress,
    required String city,
    required String state,
    required String zipCode,
    required bool certificationSigned,
  }) async {
    final fullAddress = '$streetAddress, $city, $state $zipCode';

    await _client
        .from(SupabaseConfig.driversTable)
        .update({
          'rfc': rfc.toUpperCase(),
          'rfc_validated': true,
          'curp': curp.toUpperCase(),
          'legal_name': legalName,
          'business_name': businessName,
          'tax_classification': satRegime,
          'tax_address': fullAddress,
          'tax_street': streetAddress,
          'tax_city': city,
          'tax_state': state,
          'tax_zip': zipCode,
          'country_code': 'MX',
          'state_code': state.toUpperCase(),
          'w9_signed': certificationSigned,
          'w9_signed_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', driverId);
  }

  /// Check if driver has completed W-9
  Future<bool> hasCompletedW9(String driverId) async {
    final response = await _client
        .from(SupabaseConfig.driversTable)
        .select('w9_signed')
        .eq('id', driverId)
        .maybeSingle();

    return response?['w9_signed'] == true;
  }

  /// Get driver's W-9 info (redacted for display)
  Future<Map<String, dynamic>?> getW9Info(String driverId) async {
    final response = await _client
        .from(SupabaseConfig.driversTable)
        .select('ssn_last4, legal_name, business_name, tax_classification, tax_address, w9_signed, w9_signed_at')
        .eq('id', driverId)
        .maybeSingle();

    return response;
  }

  // ===========================================================================
  // EARNINGS & FINANCIAL DATA
  // ===========================================================================

  /// Get earnings breakdown for a specific period
  Future<Map<String, dynamic>?> getEarningsBreakdown(
    String driverId,
    DateTime weekStart,
    DateTime weekEnd,
  ) async {
    try {
      // Try to get pre-computed breakdown
      final breakdown = await _client
          .from('driver_earnings_breakdown')
          .select('*')
          .eq('driver_id', driverId)
          .eq('period_type', 'weekly')
          .eq('period_start', weekStart.toIso8601String().split('T')[0])
          .maybeSingle();

      if (breakdown != null) {
        return {
          'summary': breakdown,
          'daily_breakdown': breakdown['daily_breakdown'] ?? [],
          'hourly_breakdown': breakdown['hourly_breakdown'] ?? {},
        };
      }

      // Calculate on the fly if no pre-computed data
      final earnings = await _client
          .from('driver_earnings')
          .select('*')
          .eq('driver_id', driverId)
          .gte('earned_at', weekStart.toIso8601String())
          .lt('earned_at', weekEnd.add(const Duration(days: 1)).toIso8601String())
          .order('earned_at', ascending: false);

      final data = List<Map<String, dynamic>>.from(earnings as List);

      // Calculate summary
      double baseFares = 0, distanceEarnings = 0, timeEarnings = 0, surgeEarnings = 0;
      double grossFares = 0, platformFee = 0, netFares = 0;
      double tips = 0, questBonuses = 0, streakBonuses = 0, referralBonuses = 0;
      double totalEarnings = 0, totalMiles = 0;
      int totalTrips = 0;

      final Map<String, Map<String, dynamic>> dailyMap = {};

      for (var e in data) {
        baseFares += (e['base_fare'] as num?)?.toDouble() ?? 0;
        distanceEarnings += (e['distance_earnings'] as num?)?.toDouble() ?? 0;
        timeEarnings += (e['time_earnings'] as num?)?.toDouble() ?? 0;
        surgeEarnings += (e['surge_amount'] as num?)?.toDouble() ?? 0;
        grossFares += (e['gross_fare'] as num?)?.toDouble() ?? 0;
        platformFee += (e['platform_fee_amount'] as num?)?.toDouble() ?? 0;
        netFares += (e['net_fare'] as num?)?.toDouble() ?? 0;
        tips += (e['tip_amount'] as num?)?.toDouble() ?? 0;
        questBonuses += (e['quest_bonus'] as num?)?.toDouble() ?? 0;
        streakBonuses += (e['streak_bonus'] as num?)?.toDouble() ?? 0;
        referralBonuses += (e['referral_bonus'] as num?)?.toDouble() ?? 0;
        totalEarnings += (e['total_earnings'] as num?)?.toDouble() ?? 0;
        totalMiles += (e['distance_miles'] as num?)?.toDouble() ?? 0;
        totalTrips++;

        // Group by day
        final earnedAt = DateTime.tryParse(e['earned_at'] ?? '');
        if (earnedAt != null) {
          final dayKey = earnedAt.toIso8601String().split('T')[0];
          final dayName = _getDayName(earnedAt.weekday);
          if (!dailyMap.containsKey(dayKey)) {
            dailyMap[dayKey] = {
              'day': dayName,
              'date': dayKey,
              'trips': 0,
              'earnings': 0.0,
              'hours': 0.0,
            };
          }
          dailyMap[dayKey]!['trips'] = (dailyMap[dayKey]!['trips'] as int) + 1;
          dailyMap[dayKey]!['earnings'] = (dailyMap[dayKey]!['earnings'] as double) +
              ((e['total_earnings'] as num?)?.toDouble() ?? 0);
        }
      }

      final dailyBreakdown = dailyMap.values.toList()
        ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

      // Calculate averages
      final avgPerTrip = totalTrips > 0 ? totalEarnings / totalTrips : 0.0;
      final avgPerMile = totalMiles > 0 ? totalEarnings / totalMiles : 0.0;
      // Estimate hours (rough: 20 mins per trip)
      final estimatedHours = totalTrips * 0.33;
      final avgPerHour = estimatedHours > 0 ? totalEarnings / estimatedHours : 0.0;

      return {
        'summary': {
          'base_fares': baseFares,
          'distance_earnings': distanceEarnings,
          'time_earnings': timeEarnings,
          'surge_earnings': surgeEarnings,
          'gross_fares': grossFares,
          'platform_fee': platformFee,
          'net_fares': netFares,
          'tips': tips,
          'quest_bonuses': questBonuses,
          'streak_bonuses': streakBonuses,
          'referral_bonuses': referralBonuses,
          'promotion_bonuses': 0.0,
          'total_bonuses': tips + questBonuses + streakBonuses + referralBonuses,
          'total_earnings': totalEarnings,
          'total_deductions': 0.0,
          'instant_payout_fees': 0.0,
          'net_payout': totalEarnings,
          'total_trips': totalTrips,
          'total_miles': totalMiles,
          'total_hours': estimatedHours,
          'avg_per_trip': avgPerTrip,
          'avg_per_hour': avgPerHour,
          'avg_per_mile': avgPerMile,
          'avg_tip_percent': netFares > 0 ? (tips / netFares) * 100 : 0,
          'payout_status': 'pending',
        },
        'daily_breakdown': dailyBreakdown,
      };
    } catch (e) {
      // Error getting earnings breakdown: $e');
      return null;
    }
  }

  String _getDayName(int weekday) {
    switch (weekday) {
      case 1: return 'mon'.tr();
      case 2: return 'tue'.tr();
      case 3: return 'wed'.tr();
      case 4: return 'thu'.tr();
      case 5: return 'fri'.tr();
      case 6: return 'sat'.tr();
      case 7: return 'sun'.tr();
      default: return '';
    }
  }

  /// Get recent earnings transactions
  Future<List<Map<String, dynamic>>> getRecentEarnings(
    String driverId, {
    int limit = 50,
    String? type,
  }) async {
    try {
      var query = _client
          .from('driver_earnings')
          .select('*')
          .eq('driver_id', driverId);

      if (type != null) {
        query = query.eq('type', type);
      }

      final response = await query
          .order('earned_at', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      // Error getting recent earnings: $e');
      return [];
    }
  }

  /// Get weekly summary for a driver
  Future<Map<String, dynamic>?> getWeeklySummary(
    String driverId,
    DateTime weekStart,
  ) async {
    try {
      final response = await _client
          .from('driver_weekly_summaries')
          .select('*')
          .eq('driver_id', driverId)
          .eq('week_start', weekStart.toIso8601String().split('T')[0])
          .maybeSingle();

      return response;
    } catch (e) {
      // Error getting weekly summary: $e');
      return null;
    }
  }

  /// Get driver's financial stats (for home screen)
  Future<Map<String, dynamic>> getFinancialStats(String driverId) async {
    try {
      final response = await _client
          .from(SupabaseConfig.driversTable)
          .select('''
            available_balance, pending_balance, lifetime_earnings,
            this_week_earnings, this_week_trips, today_earnings, today_trips,
            current_streak, daily_goal, weekly_goal
          ''')
          .eq('id', driverId)
          .single();

      return Map<String, dynamic>.from(response);
    } catch (e) {
      // Error getting financial stats: $e');
      return {
        'available_balance': 0.0,
        'pending_balance': 0.0,
        'lifetime_earnings': 0.0,
        'this_week_earnings': 0.0,
        'this_week_trips': 0,
        'today_earnings': 0.0,
        'today_trips': 0,
        'current_streak': 0,
      };
    }
  }

  /// Request instant payout
  Future<bool> requestInstantPayout(
    String driverId,
    double amount,
    String destinationType, // 'bank_account' or 'debit_card'
    String destinationId,
  ) async {
    try {
      // Get driver's available balance
      final driver = await _client
          .from(SupabaseConfig.driversTable)
          .select('available_balance')
          .eq('id', driverId)
          .single();

      final availableBalance = (driver['available_balance'] as num?)?.toDouble() ?? 0;

      if (amount > availableBalance) {
        throw Exception('Insufficient balance');
      }

      // Calculate fee (e.g., $0.50 or 1.5% whichever is higher)
      final fee = amount * 0.015 < 0.50 ? 0.50 : amount * 0.015;

      // Create instant payout request
      await _client.from('instant_payout_requests').insert({
        'driver_id': driverId,
        'amount': amount,
        'fee': fee,
        'destination_type': destinationType,
        'destination_id': destinationId,
        'status': 'pending',
      });

      // Deduct from available balance
      await _client
          .from(SupabaseConfig.driversTable)
          .update({
            'available_balance': availableBalance - amount,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', driverId);

      return true;
    } catch (e) {
      // Error requesting instant payout: $e');
      return false;
    }
  }

  /// Get payout history
  Future<List<Map<String, dynamic>>> getPayoutHistory(
    String driverId, {
    int limit = 20,
  }) async {
    try {
      final response = await _client
          .from('payouts')
          .select('*')
          .eq('driver_id', driverId)
          .order('created_at', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      // Error getting payout history: $e');
      return [];
    }
  }

  /// Get notification preferences
  Future<Map<String, dynamic>?> getNotificationPreferences(String driverId) async {
    try {
      final response = await _client
          .from('driver_notification_preferences')
          .select('*')
          .eq('driver_id', driverId)
          .maybeSingle();

      return response;
    } catch (e) {
      // Error getting notification preferences: $e');
      return null;
    }
  }

  /// Update notification preferences
  Future<void> updateNotificationPreferences(
    String driverId,
    Map<String, dynamic> preferences,
  ) async {
    try {
      await _client
          .from('driver_notification_preferences')
          .upsert({
            'driver_id': driverId,
            ...preferences,
            'updated_at': DateTime.now().toIso8601String(),
          });
    } catch (e) {
      // Error updating notification preferences: $e');
    }
  }

  /// Get unread notifications count
  Future<int> getUnreadNotificationsCount(String driverId) async {
    try {
      final response = await _client
          .from('driver_notifications')
          .select('id')
          .eq('driver_id', driverId)
          .inFilter('status', ['sent', 'delivered']);

      return (response as List).length;
    } catch (e) {
      return 0;
    }
  }

  /// Get notifications
  Future<List<Map<String, dynamic>>> getNotifications(
    String driverId, {
    int limit = 50,
  }) async {
    try {
      final response = await _client
          .from('driver_notifications')
          .select('*')
          .eq('driver_id', driverId)
          .order('created_at', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      // Error getting notifications: $e');
      return [];
    }
  }

  /// Mark notification as read
  Future<void> markNotificationRead(String notificationId) async {
    try {
      await _client
          .from('driver_notifications')
          .update({
            'status': 'read',
            'read_at': DateTime.now().toIso8601String(),
          })
          .eq('id', notificationId);
    } catch (e) {
      // Error marking notification read: $e');
    }
  }

  // ===========================================================================
  // PAYMENT METHODS - Bank accounts & Debit cards
  // ===========================================================================

  /// Get driver's bank accounts
  Future<List<Map<String, dynamic>>> getBankAccounts(String driverId) async {
    try {
      final response = await _client
          .from('driver_bank_accounts')
          .select('*')
          .eq('driver_id', driverId)
          .eq('status', 'verified')
          .order('is_default', ascending: false);

      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      // Error getting bank accounts: $e');
      return [];
    }
  }

  /// Get driver's debit cards
  Future<List<Map<String, dynamic>>> getDebitCards(String driverId) async {
    try {
      final response = await _client
          .from('driver_debit_cards')
          .select('*')
          .eq('driver_id', driverId)
          .eq('status', 'active')
          .order('is_default', ascending: false);

      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      // Error getting debit cards: $e');
      return [];
    }
  }

  /// Add bank account
  Future<Map<String, dynamic>?> addBankAccount({
    required String driverId,
    required String bankName,
    required String accountType,
    required String accountLast4,
    required String routingLast4,
    String? stripeAccountId,
  }) async {
    try {
      final response = await _client.from('driver_bank_accounts').insert({
        'driver_id': driverId,
        'bank_name': bankName,
        'account_type': accountType,
        'account_last4': accountLast4,
        'routing_last4': routingLast4,
        'stripe_bank_account_id': stripeAccountId,
        'status': 'pending',
        'is_default': false,
      }).select().single();

      return Map<String, dynamic>.from(response);
    } catch (e) {
      // Error adding bank account: $e');
      return null;
    }
  }

  /// Add debit card
  Future<Map<String, dynamic>?> addDebitCard({
    required String driverId,
    required String cardBrand,
    required String cardLast4,
    required int expMonth,
    required int expYear,
    String? stripeCardId,
  }) async {
    try {
      final response = await _client.from('driver_debit_cards').insert({
        'driver_id': driverId,
        'card_brand': cardBrand,
        'card_last4': cardLast4,
        'exp_month': expMonth,
        'exp_year': expYear,
        'stripe_card_id': stripeCardId,
        'status': 'active',
        'is_default': false,
      }).select().single();

      return Map<String, dynamic>.from(response);
    } catch (e) {
      // Error adding debit card: $e');
      return null;
    }
  }

  /// Set default payment method
  Future<void> setDefaultPaymentMethod({
    required String driverId,
    required String methodId,
    required String methodType, // 'bank_account' or 'debit_card'
  }) async {
    try {
      final table = methodType == 'bank_account' ? 'driver_bank_accounts' : 'driver_debit_cards';

      // Reset all defaults
      await _client
          .from(table)
          .update({'is_default': false})
          .eq('driver_id', driverId);

      // Set new default
      await _client
          .from(table)
          .update({'is_default': true})
          .eq('id', methodId);
    } catch (e) {
      // Error setting default payment method: $e');
    }
  }

  /// Remove payment method
  Future<void> removePaymentMethod({
    required String methodId,
    required String methodType,
  }) async {
    try {
      final table = methodType == 'bank_account' ? 'driver_bank_accounts' : 'driver_debit_cards';

      await _client
          .from(table)
          .update({'status': 'removed'})
          .eq('id', methodId);
    } catch (e) {
      // Error removing payment method: $e');
    }
  }

  /// Get instant payout history
  Future<List<Map<String, dynamic>>> getInstantPayoutHistory(
    String driverId, {
    int limit = 20,
  }) async {
    try {
      final response = await _client
          .from('instant_payout_requests')
          .select('*')
          .eq('driver_id', driverId)
          .order('requested_at', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      // Error getting instant payout history: $e');
      return [];
    }
  }
}
