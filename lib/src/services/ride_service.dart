import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/ride_model.dart';
import 'notification_service.dart';
import 'state_pricing_service.dart';
import 'location_service.dart';

class RideService {
  final SupabaseClient _client = SupabaseConfig.client;
  final LocationService _locationService = LocationService();

  // Get available rides for driver
  Future<List<RideModel>> getAvailableRides({
    double? latitude,
    double? longitude,
    double radiusKm = 10.0,
    String? driverId, // NEW: Filter out rides rejected by this driver
  }) async {
    // Use SQL function if location is provided for geo-queries
    if (latitude != null && longitude != null) {
      final response = await _client.rpc(
        'get_available_rides_nearby',
        params: {
          'p_latitude': latitude,
          'p_longitude': longitude,
          'p_radius_km': radiusKm,
        },
      );

      var rides = (response as List).map((json) => RideModel.fromJson(json)).toList();

      // Filter out rejected rides for this driver
      if (driverId != null) {
        rides = await filterRejectedRides(rides, driverId);
      }

      return rides;
    }

    // === 1. Query deliveries table (rides and packages) ===
    debugPrint('RIDES_QUERY: Fetching pending deliveries...');
    final deliveriesResponse = await _client
        .from(SupabaseConfig.packageDeliveriesTable)
        .select('*')
        .eq('status', statusToDatabase(RideStatus.pending))
        .isFilter('driver_id', null)
        .order('created_at', ascending: false)
        .limit(20);
    debugPrint('RIDES_QUERY: Found ${(deliveriesResponse as List).length} pending deliveries');

    // === 2. Query share_ride_bookings table (carpools) ===
    List<dynamic> carpoolsResponse = [];
    try {
      carpoolsResponse = await _client
          .from('share_ride_bookings')
          .select('*')
          .inFilter('status', ['pending', 'matched']) // Carpools waiting for driver
          .isFilter('driver_id', null)
          .order('pickup_time', ascending: true) // Ordenar por hora de pickup
          .limit(20);
    } catch (e) {
      // Error fetching carpools
    }

    // === 3. Combine and parse all rides ===
    final rides = <RideModel>[];

    // Process deliveries (rides and packages)
    for (final json in (deliveriesResponse as List)) {
      final ride = await _parseAndCalculateSplit(json as Map<String, dynamic>);
      rides.add(ride);
    }

    // Process carpools - add service_type for proper parsing
    for (final json in carpoolsResponse) {
      final carpoolJson = Map<String, dynamic>.from(json as Map);
      carpoolJson['service_type'] = 'carpool'; // Ensure it's recognized as carpool
      final ride = await _parseAndCalculateSplit(carpoolJson);
      rides.add(ride);
    }

    // Filter out rejected rides for this driver
    if (driverId != null) {
      return await filterRejectedRides(rides, driverId);
    }

    return rides;
  }

  // Filter out rides that this driver has rejected
  // Public method to filter rejected rides - used by provider
  Future<List<RideModel>> filterRejectedRides(List<RideModel> rides, String driverId) async {
    try {
      // Get all rejected ride IDs for this driver
      final rejectedResponse = await _client
          .from('ride_requests')
          .select('reference_id')
          .eq('driver_id', driverId)
          .eq('status', 'rejected');

      final rejectedIds = (rejectedResponse as List)
          .map((r) => r['reference_id'] as String)
          .toSet();

      // Filter out rejected rides
      return rides.where((ride) => !rejectedIds.contains(ride.id)).toList();
    } catch (e) {
      debugPrint('Error filtering rejected rides: $e');
      // On error, return all rides (fail-safe)
      return rides;
    }
  }

  // Fetch rider profile separately and enrich the JSON
  Future<void> _enrichWithRiderProfile(Map<String, dynamic> json, String? userId) async {
    if (userId == null || userId.isEmpty) return;
    try {
      final profile = await _client
          .from('profiles')
          .select('full_name, avatar_url, rating, phone')
          .eq('id', userId)
          .maybeSingle();
      if (profile != null) {
        json['passenger_name'] = profile['full_name'];
        json['passenger_image_url'] = profile['avatar_url'];
        json['passenger_rating'] = profile['rating'];
        final phone = profile['phone'] as String?;
        if (phone != null && phone.isNotEmpty) {
          json['passenger_phone'] = phone;
        }
      }
    } catch (e) {
      // Profile fetch failed - ride will show default name
    }
  }

  // Helper to parse ride and calculate split if needed
  Future<RideModel> _parseAndCalculateSplit(Map<String, dynamic> originalJson) async {
    // Make a mutable copy (Supabase returns UnmodifiableMapView)
    final json = Map<String, dynamic>.from(originalJson);
    // Fetch rider profile separately
    final userId = json['user_id'] as String? ?? json['rider_id'] as String?;
    await _enrichWithRiderProfile(json, userId);

    final ride = RideModel.fromJson(json);

    // Calculate preview split if driverEarnings is 0
    if (ride.driverEarnings == 0 && ride.fare > 0) {
      final rideWithSplit = await _calculatePreviewSplit(ride);
      return rideWithSplit;
    }
    return ride;
  }

  // Get ride by ID - searches both deliveries and share_ride_bookings
  Future<RideModel?> getRide(String rideId) async {
    // Try deliveries first (rides and packages)
    var response = await _client
        .from(SupabaseConfig.packageDeliveriesTable)
        .select('*')
        .eq('id', rideId)
        .maybeSingle();

    if (response != null) {
      final json = Map<String, dynamic>.from(response);
      // Fetch rider profile separately if user_id exists
      await _enrichWithRiderProfile(json, json['user_id'] as String?);
      return RideModel.fromJson(json);
    }

    // Try share_ride_bookings (carpools)
    response = await _client
        .from('share_ride_bookings')
        .select('*')
        .eq('id', rideId)
        .maybeSingle();

    if (response != null) {
      final carpoolJson = Map<String, dynamic>.from(response);
      carpoolJson['service_type'] = 'carpool';
      // Fetch rider profile separately
      await _enrichWithRiderProfile(carpoolJson, carpoolJson['rider_id'] as String? ?? carpoolJson['user_id'] as String?);
      return RideModel.fromJson(carpoolJson);
    }

    return null;
  }

  // Accept ride - uses SQL function for atomicity, supports both tables
  Future<RideModel> acceptRide(String rideId, String driverId, {String serviceType = 'ride'}) async {
    // Track acceptance in ride_requests for acceptance rate calculation
    try {
      await _trackRideResponse(driverId, rideId, serviceType, 'accepted');
    } catch (e) {
      debugPrint('Warning: Could not track ride response: $e');
    }

    // Direct update - works for both pending and already-assigned rides
    try {
      if (serviceType == 'carpool') {
        await _client
            .from('share_ride_bookings')
            .update({
              'driver_id': driverId,
              'status': 'confirmed',
              'confirmed_at': DateTime.now().toIso8601String(),
            })
            .eq('id', rideId)
            .inFilter('status', ['pending', 'matched', 'accepted']);
      } else {
        // Accept ride - handles both pending (new) and accepted (pre-assigned by assign-driver)
        await _client
            .from(SupabaseConfig.packageDeliveriesTable)
            .update({
              'driver_id': driverId,
              'status': statusToDatabase(RideStatus.accepted),
              'accepted_at': DateTime.now().toIso8601String(),
            })
            .eq('id', rideId)
            .inFilter('status', ['pending', 'accepted', 'searching']);
      }
    } catch (e) {
      debugPrint('Warning: Update failed (ride may already be accepted): $e');
    }

    // Always fetch the ride after attempting accept
    final ride = await getRide(rideId);
    if (ride != null) return ride;
    throw Exception('Ride not found after accept');
  }

  // Reject ride - driver declines the ride offer
  Future<void> rejectRide(String rideId, String driverId, {String serviceType = 'ride'}) async {
    await _trackRideResponse(driverId, rideId, serviceType, 'rejected');
  }

  // Track ride timeout - called when driver doesn't respond in time
  Future<void> trackRideTimeout(String rideId, String driverId, {String serviceType = 'ride'}) async {
    await _trackRideResponse(driverId, rideId, serviceType, 'timeout');
  }

  // Internal: Track ride response for acceptance rate calculation
  Future<void> _trackRideResponse(String driverId, String referenceId, String serviceType, String status) async {
    try {
      // Check if request already exists
      final existing = await _client
          .from('ride_requests')
          .select('id')
          .eq('driver_id', driverId)
          .eq('reference_id', referenceId)
          .maybeSingle();

      if (existing != null) {
        // Update existing request
        await _client
            .from('ride_requests')
            .update({
              'status': status,
              'responded_at': DateTime.now().toIso8601String(),
            })
            .eq('id', existing['id']);
        debugPrint('✅ Ride response tracked (UPDATE): $status for $referenceId');
      } else {
        // Insert new request with response
        await _client.from('ride_requests').insert({
          'driver_id': driverId,
          'service_type': serviceType,
          'reference_id': referenceId,
          'status': status,
          'responded_at': DateTime.now().toIso8601String(),
        });
        debugPrint('✅ Ride response tracked (INSERT): $status for $referenceId');
      }
    } catch (e) {
      // Log error but don't throw - this is non-critical for the ride flow
      debugPrint('❌ ERROR tracking ride response: $e');
      debugPrint('   driver=$driverId, ride=$referenceId, type=$serviceType, status=$status');
    }
  }

  // Create pending ride request when offering to driver
  Future<String?> createRideRequest(String driverId, String referenceId, String serviceType) async {
    try {
      final response = await _client.from('ride_requests').insert({
        'driver_id': driverId,
        'service_type': serviceType,
        'reference_id': referenceId,
        'status': 'pending',
      }).select('id').single();

      return response['id'] as String;
    } catch (e) {
      return null;
    }
  }

  // Arrive at pickup - uses deliveries table (unified)
  Future<RideModel> arriveAtPickup(String rideId) async {
    final response = await _client
        .from(SupabaseConfig.packageDeliveriesTable)
        .update({
          'status': statusToDatabase(RideStatus.arrivedAtPickup), // 'picked_up'
          'picked_up_at': DateTime.now().toIso8601String(),
        })
        .eq('id', rideId)
        .select()
        .single();

    return RideModel.fromJson(response);
  }

  // Start ride - uses deliveries table (unified)
  Future<RideModel> startRide(String rideId) async {
    final response = await _client
        .from(SupabaseConfig.packageDeliveriesTable)
        .update({
          'status': statusToDatabase(RideStatus.inProgress), // 'in_transit'
          'started_at': DateTime.now().toIso8601String(),
        })
        .eq('id', rideId)
        .select()
        .single();

    return RideModel.fromJson(response);
  }

  // Complete ride - uses direct update to handle cash payments properly
  Future<RideModel> completeRide(String rideId, {double? tip}) async {
    // Get the ride first to check payment method
    final ride = await getRide(rideId);
    if (ride == null) throw Exception('Ride not found');

    // For CASH payments, skip RPC and use direct update (to set payment_status in same call)
    // For CARD payments, try RPC first
    if (ride.paymentMethod != PaymentMethod.cash) {
      try {
        final response = await _client.rpc(
          'complete_ride',
          params: {
            'p_ride_id': rideId,
            'p_tip': tip ?? 0,
          },
        );
        return RideModel.fromJson(response);
      } catch (e) {
        // Fall through to direct update
        debugPrint('RPC complete_ride failed, using direct update: $e');
      }
    }

    final now = DateTime.now();

    // ========================================================================
    // PRICING PER-STATE - Leer de pricing_config por estado
    // Prioridad: 1) GPS coordinates, 2) fallback AZ
    // ========================================================================
    String stateCode = 'AZ';
    if (ride.pickupLocation.latitude != 0) {
      // Get state from pickup coordinates
      stateCode = await _locationService.getStateCodeFromCoordinates(
        ride.pickupLocation.latitude,
        ride.pickupLocation.longitude,
      );
    }

    StatePricing statePricing;
    try {
      statePricing = await StatePricingService.instance.getPricing(
        stateCode: stateCode,
        bookingType: BookingType.ride,
      );
    } on NoPricingConfiguredError {
      rethrow; // Propagar error - no hay fallback
    }

    final driverCommissionPercent = statePricing.driverPercentage.toInt();
    final platformFeePercent = statePricing.platformPercentage;
    final taxPercent = statePricing.taxPercentage;
    final insurancePercent = statePricing.insurancePercentage;

    // Calculate driver earnings using ADMIN-defined percentage + tip
    final fare = ride.fare > 0 ? ride.fare : statePricing.minimumFare;
    final basedriverEarnings = fare * (driverCommissionPercent / 100);
    final totalDriverEarnings = basedriverEarnings + (tip ?? 0);

    // Calculate breakdown for records
    final platformAmount = fare * (platformFeePercent / 100);
    final taxAmount = fare * (taxPercent / 100);
    final insuranceAmount = fare * (insurancePercent / 100);

    // Calculate duration from timestamps
    int durationMinutes = ride.estimatedMinutes;
    if (ride.startedAt != null) {
      durationMinutes = now.difference(ride.startedAt!).inMinutes;
      if (durationMinutes < 1) durationMinutes = 1;
    }

    // Calculate distance in miles
    double distanceMiles = ride.distanceKm * 0.621371;
    if (distanceMiles == 0 && ride.pickupLocation.latitude != 0) {
      // Calculate from coordinates using simple approximation
      final latDiff = (ride.dropoffLocation.latitude - ride.pickupLocation.latitude).abs();
      final lngDiff = (ride.dropoffLocation.longitude - ride.pickupLocation.longitude).abs();
      distanceMiles = ((latDiff * 69) + (lngDiff * 54.6)) * 1.3; // approx road distance
      if (distanceMiles < 0.5) distanceMiles = 0.5;
    }

    // NOTE: Only update columns that EXIST in the deliveries table
    // CRITICAL: For CASH payments, we MUST set payment_status = 'paid' in the SAME update
    // as the status change, otherwise the database trigger will reject the transition
    final updateData = <String, dynamic>{
      'status': statusToDatabase(RideStatus.completed),
      'completed_at': now.toIso8601String(),
      'delivered_at': now.toIso8601String(), // CRITICAL: needed for earnings queries
      'final_price': fare,
      'driver_earnings': totalDriverEarnings,
      'state_code': stateCode,
      'platform_fee': platformAmount,
      'tax_amount': taxAmount,
      'payment_status': 'paid',  // ALWAYS mark as paid when completing
      // === COMPLETE FINANCIAL AUDIT FIELDS ===
      'insurance_amount': insuranceAmount,
      'base_driver_earnings': basedriverEarnings,
      'effective_platform_percent': platformFeePercent,
      'variable_platform_active': statePricing.variablePlatformEnabled,
      'actual_distance_miles': distanceMiles,
      'actual_duration_minutes': durationMinutes,
      'driver_percent_applied': driverCommissionPercent,
      'insurance_percent_applied': insurancePercent,
      'tax_percent_applied': taxPercent,
    };

    // For cash payments, also set cash confirmation fields
    if (ride.paymentMethod == PaymentMethod.cash) {
      updateData['cash_payment_confirmed'] = true;
      updateData['cash_payment_confirmed_at'] = now.toIso8601String();
    }

    if (tip != null && tip > 0) {
      updateData['tip_amount'] = tip;
    }

    // Update the correct table based on ride type
    Map<String, dynamic> response;
    if (ride.type == RideType.carpool) {
      // Update share_ride_bookings for carpools
      response = await _client
          .from('share_ride_bookings')
          .update(updateData)
          .eq('id', rideId)
          .select()
          .single();
      response['service_type'] = 'carpool'; // Ensure type is preserved
    } else {
      // Update deliveries for rides and packages
      response = await _client
          .from(SupabaseConfig.packageDeliveriesTable)
          .update(updateData)
          .eq('id', rideId)
          .select()
          .single();
    }

    final completedRide = RideModel.fromJson(response);

    // ========================================================================
    // CAPTURE STRIPE PAYMENT - Critical: charge the rider's card
    // The pre-auth was created when rider booked, now we capture the funds
    // ========================================================================
    await _captureStripePayment(
      rideId: rideId,
      paymentIntentId: ride.stripePaymentIntentId,
      amount: fare,
      driverId: ride.driverId,
      tipAmount: tip ?? 0,
      stateCode: stateCode,
      pickupAddress: ride.pickupLocation.address,
      dropoffAddress: ride.dropoffLocation.address,
      bookingType: ride.type == RideType.carpool ? 'carpool' :
                   ride.type == RideType.package ? 'package' : 'ride',
    );

    // ========================================================================
    // LOCAL NOTIFICATION: Show earnings breakdown to driver
    // ========================================================================
    try {
      final notifService = NotificationService();
      await notifService.showRideEarningNotification(
        totalEarnings: totalDriverEarnings,
        baseFare: basedriverEarnings,
        tip: tip ?? 0,
      );
    } catch (e) {
      debugPrint('Notification error (non-fatal): $e');
    }

    return completedRide;
  }

  /// Capture Stripe payment when ride completes
  /// Calls the stripe-capture-payment Edge Function to charge the rider
  Future<void> _captureStripePayment({
    required String rideId,
    String? paymentIntentId,
    required double amount,
    String? driverId,
    double tipAmount = 0,
    String stateCode = 'AZ',
    String? pickupAddress,
    String? dropoffAddress,
    String bookingType = 'ride',
  }) async {
    if (paymentIntentId == null || paymentIntentId.isEmpty) {
      return;
    }

    try {

      final captureResponse = await _client.functions.invoke(
        'stripe-capture-payment',
        body: {
          'paymentIntentId': paymentIntentId,
          'amount': amount + tipAmount, // Total to capture
          'bookingId': rideId,
          'driverId': driverId,
          'tipAmount': tipAmount,
          'bookingType': bookingType,
          'stateCode': stateCode,
          'pickupAddress': pickupAddress,
          'dropoffAddress': dropoffAddress,
          'processSplit': true,  // Process driver/platform split
          'notifyDriver': true,  // Send notification to driver
        },
      );

      if (captureResponse.status != 200) {
        // Don't throw - ride is already marked complete, payment can be retried
      }
    } catch (e) {
      // Don't throw - ride is already marked complete
      // Payment capture can be retried via admin or cron job
    }
  }

  // Cancel ride - RESETS to pending so other drivers can accept (Uber-style)
  // Does NOT cancel the ride - just releases it back to the pool
  Future<RideModel> cancelRide(String rideId, String reason) async {
    final response = await _client
        .from(SupabaseConfig.packageDeliveriesTable)
        .update({
          'status': 'pending',  // Reset to pending - NOT cancelled
          'driver_id': null,    // Clear driver so others can accept
          'accepted_at': null,  // Clear acceptance time
          'started_at': null,   // Clear start time
          // Note: We don't set cancelled_at because ride is not cancelled
        })
        .eq('id', rideId)
        .select()
        .single();

    return RideModel.fromJson(response);
  }

  // Force release ALL active rides for a driver - use for stuck/ghost rides
  // Tries both deliveries and share_ride_bookings tables
  Future<bool> forceReleaseAllActiveRides(String driverId) async {
    bool success = false;

    // 1. Release from deliveries table
    try {
      await _client
          .from(SupabaseConfig.packageDeliveriesTable)
          .update({
            'status': 'pending',
            'driver_id': null,
            'accepted_at': null,
            'started_at': null,
          })
          .eq('driver_id', driverId)
          .inFilter('status', ['accepted', 'in_progress', 'arrived']);
      success = true;
    } catch (e) {
      debugPrint('Error releasing deliveries: $e');
    }

    // 2. Release from share_ride_bookings table (carpools)
    try {
      await _client
          .from('share_ride_bookings')
          .update({
            'status': 'pending',
            'driver_id': null,
            'accepted_at': null,
          })
          .eq('driver_id', driverId)
          .inFilter('status', ['accepted', 'in_progress', 'matched', 'driver_assigned']);
      success = true;
    } catch (e) {
      debugPrint('Error releasing carpools: $e');
    }

    return success;
  }

  // Get driver's active ride - checks both deliveries and share_ride_bookings
  Future<RideModel?> getActiveRide(String driverId) async {
    debugPrint('🔍 getActiveRide: Checking for driver $driverId');

    // 1. Check deliveries table (standard rides)
    try {
      final deliveryResponse = await _client
          .from(SupabaseConfig.packageDeliveriesTable)
          .select()
          .eq('driver_id', driverId)
          .inFilter('status', ['accepted', 'in_progress'])
          .order('created_at', ascending: false)
          .limit(1);

      if (deliveryResponse.isNotEmpty) {
        debugPrint('✅ getActiveRide: Found active delivery: ${deliveryResponse.first['id']}');
        return RideModel.fromJson(deliveryResponse.first);
      }
    } catch (e) {
      debugPrint('⚠️ getActiveRide deliveries error: $e');
    }

    // 2. Check share_ride_bookings table (carpools)
    try {
      final carpoolResponse = await _client
          .from('share_ride_bookings')
          .select()
          .eq('driver_id', driverId)
          .inFilter('status', ['accepted', 'in_progress', 'matched', 'driver_assigned'])
          .order('created_at', ascending: false)
          .limit(1);

      if (carpoolResponse.isNotEmpty) {
        debugPrint('✅ getActiveRide: Found active carpool: ${carpoolResponse.first['id']}');
        return RideModel.fromJson(carpoolResponse.first);
      }
    } catch (e) {
      debugPrint('⚠️ getActiveRide carpools error: $e');
    }

    debugPrint('ℹ️ getActiveRide: No active ride found for driver $driverId');
    return null;
  }

  // Get driver's ride history
  Future<List<RideModel>> getRideHistory(
    String driverId, {
    int limit = 50,
    int offset = 0,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      var query = _client
          .from(SupabaseConfig.packageDeliveriesTable)
          .select()
          .eq('driver_id', driverId)
          .inFilter('status', [statusToDatabase(RideStatus.completed), statusToDatabase(RideStatus.cancelled)]);

      if (startDate != null) {
        query = query.gte('created_at', startDate.toIso8601String());
      }
      if (endDate != null) {
        query = query.lte('created_at', endDate.toIso8601String());
      }

      final response = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return (response as List).map((json) => RideModel.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  // ========================================================================
  // FARE CALCULATION - Usar StatePricingService (ASYNC, PER-STATE)
  // ========================================================================

  /// Calculate fare using StatePricingService
  /// ASYNC porque necesita leer de BD - NO hay fallback síncrono
  /// Si stateCode es null, intenta obtenerlo del GPS
  Future<double> calculateFareAsync({
    required double distanceKm,
    required int estimatedMinutes,
    String? stateCode,
    double? pickupLat,
    double? pickupLng,
    BookingType bookingType = BookingType.ride,
  }) async {
    // Resolve stateCode: parameter > GPS > fallback AZ
    String resolvedStateCode = stateCode ?? 'AZ';
    if (stateCode == null && pickupLat != null && pickupLng != null) {
      resolvedStateCode = await _locationService.getStateCodeFromCoordinates(pickupLat, pickupLng);
    } else if (stateCode == null) {
      resolvedStateCode = await _locationService.getStateCodeFromGPS();
    }

    final pricing = await StatePricingService.instance.getPricing(
      stateCode: resolvedStateCode,
      bookingType: bookingType,
    );

    // MX: per_mile_rate is actually per-km, no conversion needed
    final distance = pricing.usesKilometers ? distanceKm : distanceKm * 0.621371;
    double fare = pricing.baseFare;
    fare += distance * pricing.perMileRate;
    fare += estimatedMinutes * pricing.perMinuteRate;
    fare += pricing.bookingFee;
    fare += pricing.serviceFee;

    // Apply minimum
    if (fare < pricing.minimumFare) {
      fare = pricing.minimumFare;
    }

    // Apply time multiplier
    fare *= StatePricingService.instance.getTimeMultiplier(pricing);

    return fare;
  }

  /// Calculate driver earnings using StatePricingService
  /// ASYNC porque necesita leer de BD - NO hay fallback síncrono
  /// Si stateCode es null, intenta obtenerlo del GPS
  Future<double> calculateDriverEarningsAsync(
    double fare, {
    String? stateCode,
    BookingType bookingType = BookingType.ride,
  }) async {
    // Resolve stateCode: parameter > GPS > fallback AZ
    String resolvedStateCode = stateCode ?? await _locationService.getStateCodeFromGPS();

    final pricing = await StatePricingService.instance.getPricing(
      stateCode: resolvedStateCode,
      bookingType: bookingType,
    );

    return fare * (pricing.driverPercentage / 100);
  }

  // Stream available rides (real-time) - listens to deliveries table
  // Lightweight: parse JSON directly without async HTTP calls to avoid ANR
  // Profile enrichment + split calculation happen in getAvailableRides() periodic backup
  Stream<List<RideModel>> streamAvailableRides() {
    _fetchInitialPendingRides();

    return _client
        .from(SupabaseConfig.packageDeliveriesTable)
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((dynamic data) {
          if (data == null) return <RideModel>[];

          final List<dynamic> dataList = data is List ? data : [];

          try {
            final filtered = dataList.where((json) {
              final status = json['status'] as String?;
              final driverId = json['driver_id'];
              return status == 'pending' && driverId == null;
            }).toList();

            // Lightweight parse - no HTTP calls, no async
            // Profile names + split preview come from periodic getAvailableRides()
            return filtered.map((json) {
              final mutableJson = Map<String, dynamic>.from(json as Map);
              return RideModel.fromJson(mutableJson);
            }).toList();
          } catch (e) {
            return <RideModel>[];
          }
        });
  }

  // Calculate preview split for a ride based on pricing_config
  Future<RideModel> _calculatePreviewSplit(RideModel ride) async {
    try {
      // Determine booking type from ride type
      final bookingType = ride.type == RideType.package
          ? BookingType.delivery
          : ride.type == RideType.carpool
              ? BookingType.carpool
              : BookingType.ride;

      // Get state code from pickup location
      String stateCode = 'AZ'; // Default fallback
      if (ride.pickupLocation.latitude != 0 && ride.pickupLocation.longitude != 0) {
        try {
          stateCode = await _locationService.getStateCodeFromCoordinates(
            ride.pickupLocation.latitude,
            ride.pickupLocation.longitude,
          );
        } catch (e) {
          // Error getting state code, using AZ
        }
      }

      // Get pricing config for state
      final pricing = await StatePricingService.instance.getPricing(
        stateCode: stateCode,
        bookingType: bookingType,
      );

      // Calculate preview split
      // IMPORTANT: TNC tax is subtracted FIRST, then the remaining fare is split
      // TNC tax goes 100% to government (not part of revenue split)
      final tncTax = pricing.tncTaxPerTrip;
      final fareAfterTncTax = (ride.fare - tncTax).clamp(0.0, double.infinity);

      final driverEarnings = fareAfterTncTax * (pricing.driverPercentage / 100);
      final platformFee = fareAfterTncTax * (pricing.platformPercentage / 100);

      return ride.copyWith(
        driverEarnings: driverEarnings,
        platformFee: platformFee,
      );
    } catch (e) {
      // REGLA: NO hardcodear porcentajes. Reintentar con AZ como fallback.
      try {
        final fallbackPricing = await StatePricingService.instance.getPricing(
          stateCode: 'AZ',
          bookingType: BookingType.ride,
        );
        // Apply TNC tax from fallback pricing too
        final tncTax = fallbackPricing.tncTaxPerTrip;
        final fareAfterTncTax = (ride.fare - tncTax).clamp(0.0, double.infinity);
        final driverEarnings = fareAfterTncTax * (fallbackPricing.driverPercentage / 100);
        final platformFee = fareAfterTncTax * (fallbackPricing.platformPercentage / 100);
        return ride.copyWith(
          driverEarnings: driverEarnings,
          platformFee: platformFee,
        );
      } catch (fallbackError) {
        // Si ni AZ funciona, retornar sin split (UI mostrará solo fare)
        return ride;
      }
    }
  }

  // Fetch initial pending rides to check database
  Future<void> _fetchInitialPendingRides() async {
    try {
      // First fetch ALL to see what statuses exist
      await _client
          .from(SupabaseConfig.packageDeliveriesTable)
          .select()
          .order('created_at', ascending: false)
          .limit(10);
    } catch (e) {
      // Error fetching rides
    }
  }

  // Stream current ride (real-time) - supports both deliveries and carpools
  Stream<RideModel?> streamRide(String rideId) {
    // Try deliveries table first
    return _client
        .from(SupabaseConfig.packageDeliveriesTable)
        .stream(primaryKey: ['id'])
        .eq('id', rideId)
        .asyncMap((dynamic data) async {
          if (data == null) return null;
          final List<dynamic> dataList = data is List ? data : [];

          if (dataList.isNotEmpty) {
            final json = Map<String, dynamic>.from(dataList.first as Map<String, dynamic>);
            // Enrich with rider profile (name, photo, rating)
            final userId = json['user_id'] as String? ?? json['rider_id'] as String?;
            await _enrichWithRiderProfile(json, userId);
            return RideModel.fromJson(json);
          }

          // If not found in deliveries, try share_ride_bookings (carpools)
          try {
            final carpoolData = await _client
                .from('share_ride_bookings')
                .select()
                .eq('id', rideId)
                .maybeSingle();

            if (carpoolData != null) {
              final carpoolJson = Map<String, dynamic>.from(carpoolData);
              carpoolJson['service_type'] = 'carpool';
              final userId = carpoolJson['user_id'] as String? ?? carpoolJson['rider_id'] as String?;
              await _enrichWithRiderProfile(carpoolJson, userId);
              return RideModel.fromJson(carpoolJson);
            }
          } catch (e) {
            debugPrint('Error checking carpool: $e');
          }

          return null;
        });
  }

  // Stream carpool ride (real-time) - for share_ride_bookings table
  Stream<RideModel?> streamCarpoolRide(String rideId) {
    return _client
        .from('share_ride_bookings')
        .stream(primaryKey: ['id'])
        .eq('id', rideId)
        .asyncMap((dynamic data) async {
          if (data == null) return null;
          final List<dynamic> dataList = data is List ? data : [];
          if (dataList.isNotEmpty) {
            final carpoolJson = Map<String, dynamic>.from(dataList.first as Map<String, dynamic>);
            carpoolJson['service_type'] = 'carpool';
            final userId = carpoolJson['user_id'] as String? ?? carpoolJson['rider_id'] as String?;
            await _enrichWithRiderProfile(carpoolJson, userId);
            return RideModel.fromJson(carpoolJson);
          }
          return null;
        });
  }

  // Get today's rides count
  Future<int> getTodayRidesCount(String driverId) async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);

      final response = await _client
          .from(SupabaseConfig.packageDeliveriesTable)
          .select('id')
          .eq('driver_id', driverId)
          .eq('status', statusToDatabase(RideStatus.completed))
          .gte('completed_at', startOfDay.toIso8601String());

      return (response as List).length;
    } catch (e) {
      return 0;
    }
  }

  // Rate passenger
  Future<void> ratePassenger(String rideId, double rating, String? comment) async {
    await _client.from(SupabaseConfig.ratingsTable).insert({
      'ride_id': rideId,
      'rating': rating,
      'comment': comment,
      'rated_by': 'driver',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // ============================================================================
  // CASH PAYMENT CONFIRMATION
  // When a ride is paid in cash, the driver must confirm they received the money
  // ============================================================================

  /// Confirm cash payment received from rider
  /// This marks the delivery as paid and creates a cash_payment transaction
  Future<RideModel> confirmCashPayment({
    required String rideId,
    required String driverId,
    required double amount,
    String? stateCode,
  }) async {
    final now = DateTime.now();

    // Get the ride to verify it's a cash payment
    final ride = await getRide(rideId);
    if (ride == null) {
      throw Exception('Ride not found');
    }

    // Verify payment method is cash
    if (ride.paymentMethod != PaymentMethod.cash) {
      throw Exception('This ride is not a cash payment');
    }

    // Get state code for pricing if not provided
    String resolvedStateCode = stateCode ?? 'AZ';
    if (stateCode == null && ride.pickupLocation.latitude != 0) {
      resolvedStateCode = await _locationService.getStateCodeFromCoordinates(
        ride.pickupLocation.latitude,
        ride.pickupLocation.longitude,
      );
    }

    // Get pricing config for the state
    StatePricing statePricing;
    try {
      statePricing = await StatePricingService.instance.getPricing(
        stateCode: resolvedStateCode,
        bookingType: ride.type == RideType.carpool ? BookingType.carpool :
                     ride.type == RideType.package ? BookingType.delivery : BookingType.ride,
      );
    } on NoPricingConfiguredError {
      rethrow;
    }

    // Calculate driver earnings using pricing config
    final fare = amount > 0 ? amount : ride.fare;
    final driverCommissionPercent = statePricing.driverPercentage.toInt();
    final platformFeePercent = statePricing.platformPercentage;
    final driverEarnings = fare * (driverCommissionPercent / 100);
    final platformAmount = fare * (platformFeePercent / 100);

    // Update the delivery with cash payment confirmed
    // NOTE: payment_status = 'paid' is REQUIRED for the trigger to allow status → completed
    final updateData = <String, dynamic>{
      'final_price': fare,
      'driver_earnings': driverEarnings,
      'platform_fee': platformAmount,
      'state_code': resolvedStateCode,
      'payment_status': 'paid',  // CRITICAL: Trigger checks this before allowing completion
      'cash_payment_confirmed': true,
      'cash_payment_confirmed_at': now.toIso8601String(),
      'cash_payment_confirmed_by': driverId,
    };

    // Update the correct table based on ride type
    Map<String, dynamic> response;
    if (ride.type == RideType.carpool) {
      response = await _client
          .from('share_ride_bookings')
          .update(updateData)
          .eq('id', rideId)
          .select()
          .single();
      response['service_type'] = 'carpool';
    } else {
      response = await _client
          .from(SupabaseConfig.packageDeliveriesTable)
          .update(updateData)
          .eq('id', rideId)
          .select()
          .single();
    }

    // Create a cash_payment transaction record
    try {
      await _client.from('transactions').insert({
        'booking_id': rideId,
        'driver_id': driverId,
        'user_id': ride.passengerId,
        'type': 'cash_payment',
        'amount': fare,
        'driver_amount': driverEarnings,
        'platform_amount': platformAmount,
        'status': 'success',
        'payment_method': 'cash',
        'state_code': resolvedStateCode,
        'description': 'Cash payment confirmed by driver',
        'created_at': now.toIso8601String(),
        'processed_at': now.toIso8601String(),
      });
    } catch (e) {
      // Transaction creation is non-critical, don't fail the whole operation
      debugPrint('Warning: Could not create cash_payment transaction: $e');
    }

    // =========================================================================
    // CRITICAL: Process split for cash payments (driver_earnings + balance)
    // Cash rides don't go through Stripe, so we must process the split manually
    // =========================================================================
    try {
      final splitResponse = await _client.functions.invoke(
        'process-cash-split',
        body: {
          'booking_id': rideId,
          'driver_id': driverId,
          'gross_amount': fare,
          'tip_amount': 0.0, // Cash tips are not tracked in app
          'state_code': resolvedStateCode,
          'booking_type': ride.type == RideType.carpool ? 'carpool' : 'ride',
          'pickup_address': ride.pickupLocation.address,
          'dropoff_address': ride.dropoffLocation.address,
        },
      );
      final splitData = splitResponse.data as Map<String, dynamic>?;
      if (splitData?['success'] == true) {
        debugPrint('✅ Cash split processed: driver gets \$${splitData?['driver_amount']}');
      } else {
        debugPrint('⚠️ Cash split warning: ${splitData?['error'] ?? 'unknown'}');
      }
    } catch (e) {
      // Split processing failure is non-critical for the ride completion
      debugPrint('Warning: Could not process cash split: $e');
    }

    return RideModel.fromJson(response);
  }

  /// Check if a ride requires cash payment confirmation
  bool requiresCashPaymentConfirmation(RideModel ride) {
    return ride.paymentMethod == PaymentMethod.cash && !ride.isPaid;
  }

  // ============================================================================
  // TEST: Create a test delivery for debugging
  // ============================================================================
  Future<Map<String, dynamic>?> createTestDelivery() async {
    try {
      // Only include columns that exist in the deliveries table
      final testData = {
        'user_id': null,
        'service_type': 'package',
        'pickup_lat': 25.6866,
        'pickup_lng': -100.3161,
        'pickup_address': '123 Calle Test, Monterrey, NL',
        'destination_lat': 25.6714,
        'destination_lng': -100.3089,
        'destination_address': '456 Av. Destino, Monterrey, NL',
        'status': 'pending',
        'driver_id': null,
        'created_at': DateTime.now().toIso8601String(),
      };

      final response = await _client
          .from(SupabaseConfig.packageDeliveriesTable)
          .insert(testData)
          .select()
          .single();

      return response;
    } catch (e) {
      return null;
    }
  }

  // Delete test deliveries
  Future<void> deleteTestDeliveries() async {
    try {
      await _client
          .from(SupabaseConfig.packageDeliveriesTable)
          .delete()
          .eq('notes', 'Test delivery - Paquete de prueba');
    } catch (e) {
      // Error deleting test deliveries
    }
  }
}
