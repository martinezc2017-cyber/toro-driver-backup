import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/ride_model.dart';
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

      return (response as List).map((json) => RideModel.fromJson(json)).toList();
    }

    // === 1. Query deliveries table (rides and packages) with rider profile ===
    final deliveriesResponse = await _client
        .from(SupabaseConfig.packageDeliveriesTable)
        .select('''
          *,
          profiles!user_id(
            full_name,
            avatar_url,
            rating
          )
        ''')
        .eq('status', statusToDatabase(RideStatus.pending))
        .isFilter('driver_id', null)
        .order('created_at', ascending: false)
        .limit(20);

    // === 2. Query share_ride_bookings table (carpools) with rider profile ===
    List<dynamic> carpoolsResponse = [];
    try {
      carpoolsResponse = await _client
          .from('share_ride_bookings')
          .select('''
            *,
            profiles!rider_id(
              full_name,
              avatar_url,
              rating
            )
          ''')
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

    return rides;
  }

  // Helper to parse ride and calculate split if needed
  Future<RideModel> _parseAndCalculateSplit(Map<String, dynamic> json) async {
    // === FIX: Extract rider profile data from nested profiles object ===
    final profiles = json['profiles'] as Map<String, dynamic>?;
    if (profiles != null) {
      // Map profile fields to expected field names
      json['passenger_name'] = profiles['full_name'];
      json['passenger_image_url'] = profiles['avatar_url'];
      json['passenger_rating'] = profiles['rating'];
    }

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
    // Try deliveries first (rides and packages) with rider profile
    var response = await _client
        .from(SupabaseConfig.packageDeliveriesTable)
        .select('''
          *,
          profiles!user_id(
            full_name,
            avatar_url,
            rating
          )
        ''')
        .eq('id', rideId)
        .maybeSingle();

    if (response != null) {
      final json = Map<String, dynamic>.from(response);
      // Extract rider profile data
      final profiles = json['profiles'] as Map<String, dynamic>?;
      if (profiles != null) {
        json['passenger_name'] = profiles['full_name'];
        json['passenger_image_url'] = profiles['avatar_url'];
        json['passenger_rating'] = profiles['rating'];
      }
      return RideModel.fromJson(json);
    }

    // Try share_ride_bookings (carpools) with rider profile
    response = await _client
        .from('share_ride_bookings')
        .select('''
          *,
          profiles!rider_id(
            full_name,
            avatar_url,
            rating
          )
        ''')
        .eq('id', rideId)
        .maybeSingle();

    if (response != null) {
      final carpoolJson = Map<String, dynamic>.from(response);
      carpoolJson['service_type'] = 'carpool';
      // Extract rider profile data
      final profiles = carpoolJson['profiles'] as Map<String, dynamic>?;
      if (profiles != null) {
        carpoolJson['passenger_name'] = profiles['full_name'];
        carpoolJson['passenger_image_url'] = profiles['avatar_url'];
        carpoolJson['passenger_rating'] = profiles['rating'];
      }
      return RideModel.fromJson(carpoolJson);
    }

    return null;
  }

  // Accept ride - uses SQL function for atomicity, supports both tables
  Future<RideModel> acceptRide(String rideId, String driverId, {String serviceType = 'ride'}) async {
    try {
      // Track acceptance in ride_requests for acceptance rate calculation
      await _trackRideResponse(driverId, rideId, serviceType, 'accepted');

      await _client.rpc(
        'accept_ride',
        params: {
          'p_ride_id': rideId,
          'p_driver_id': driverId,
        },
      );

      // Fetch the ride with profile data after accepting
      final ride = await getRide(rideId);
      if (ride != null) return ride;
      throw Exception('Ride not found after accept');
    } catch (e) {
      // Fallback to direct update if function doesn't exist
      // Determine which table to update based on service type
      if (serviceType == 'carpool') {
        // Update share_ride_bookings for carpools
        await _client
            .from('share_ride_bookings')
            .update({
              'driver_id': driverId,
              'status': 'confirmed', // Carpools use 'confirmed' when driver accepts
              'confirmed_at': DateTime.now().toIso8601String(),
            })
            .eq('id', rideId)
            .inFilter('status', ['pending', 'matched']);
      } else {
        // Update deliveries for rides and packages
        await _client
            .from(SupabaseConfig.packageDeliveriesTable)
            .update({
              'driver_id': driverId,
              'status': statusToDatabase(RideStatus.accepted),
              'accepted_at': DateTime.now().toIso8601String(),
            })
            .eq('id', rideId)
            .eq('status', statusToDatabase(RideStatus.pending));
      }

      // Fetch the ride with profile data after updating
      final ride = await getRide(rideId);
      if (ride != null) return ride;
      throw Exception('Ride not found after fallback accept');
    }
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
      } else {
        // Insert new request with response
        await _client.from('ride_requests').insert({
          'driver_id': driverId,
          'service_type': serviceType,
          'reference_id': referenceId,
          'status': status,
          'responded_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      // Don't throw - this is non-critical for the ride flow
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

  // Complete ride - uses SQL function for atomicity
  Future<RideModel> completeRide(String rideId, {double? tip}) async {
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
      // Fallback to direct update if function doesn't exist
      final ride = await getRide(rideId);
      if (ride == null) throw Exception('Ride not found');

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

      final updateData = <String, dynamic>{
        'status': statusToDatabase(RideStatus.completed),
        'completed_at': now.toIso8601String(),
        'delivered_at': now.toIso8601String(), // CRITICAL: needed for earnings queries
        'is_paid': true,
        'final_price': fare,
        'driver_earnings': totalDriverEarnings,
        'duration_minutes': durationMinutes,
        'distance_miles': distanceMiles,
        // Complete breakdown from admin pricing config
        'state_code': stateCode,
        'driver_commission_percent': driverCommissionPercent,
        'platform_fee_percent': platformFeePercent,
        'platform_fee_amount': platformAmount,
        'tax_percent': taxPercent,
        'tax_amount': taxAmount,
        'insurance_percent': insurancePercent,
        'insurance_amount': insuranceAmount,
      };

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

      return completedRide;
    }
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

  // Get driver's active ride
  Future<RideModel?> getActiveRide(String driverId) async {
    try {
      final response = await _client
          .from(SupabaseConfig.packageDeliveriesTable)
          .select()
          .eq('driver_id', driverId)
          .inFilter('status', [
            statusToDatabase(RideStatus.accepted),       // 'accepted'
            statusToDatabase(RideStatus.arrivedAtPickup), // 'in_progress'
            statusToDatabase(RideStatus.inProgress),      // 'in_progress'
          ])
          .maybeSingle();

      if (response == null) return null;
      return RideModel.fromJson(response);
    } catch (e) {
      return null;
    }
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

    final distanceMiles = distanceKm * 0.621371;
    double fare = pricing.baseFare;
    fare += distanceMiles * pricing.perMileRate;
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
  // FIX: Listen to ALL status changes to detect cancellations, then filter locally
  // FIX: Calculate preview split for each ride using pricing_config
  Stream<List<RideModel>> streamAvailableRides() {
    // Also fetch initial data to see if there are pending rides
    _fetchInitialPendingRides();

    // FIXED: Listen to ALL deliveries without status filter
    // This way we detect when a ride changes from 'pending' to 'cancelled'
    // Then filter locally for pending + no driver
    return _client
        .from(SupabaseConfig.packageDeliveriesTable)
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .asyncMap((dynamic data) async {
          // Handle null or non-list data
          if (data == null) {
            return <RideModel>[];
          }

          final List<dynamic> dataList = data is List ? data : [];

          try {
            // FIXED: Filter locally for pending rides without driver
            // This ensures cancelled rides are removed from the list
            final filtered = dataList.where((json) {
              final status = json['status'] as String?;
              final driverId = json['driver_id'];
              return status == 'pending' && driverId == null;
            }).toList();

            // Parse rides and calculate preview split for each
            final rides = <RideModel>[];
            for (final json in filtered) {
              final ride = RideModel.fromJson(json as Map<String, dynamic>);

              // Calculate preview split if driverEarnings is 0
              if (ride.driverEarnings == 0 && ride.fare > 0) {
                final rideWithSplit = await _calculatePreviewSplit(ride);
                rides.add(rideWithSplit);
              } else {
                rides.add(ride);
              }
            }
            return rides;
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

  // Stream current ride (real-time)
  Stream<RideModel?> streamRide(String rideId) {
    return _client
        .from(SupabaseConfig.packageDeliveriesTable)
        .stream(primaryKey: ['id'])
        .eq('id', rideId)
        .map((dynamic data) {
          if (data == null) return null;
          final List<dynamic> dataList = data is List ? data : [];
          return dataList.isNotEmpty ? RideModel.fromJson(dataList.first as Map<String, dynamic>) : null;
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
