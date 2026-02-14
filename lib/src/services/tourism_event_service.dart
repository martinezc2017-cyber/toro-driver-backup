import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../core/logging/app_logger.dart';

/// Service for tourism event operations.
///
/// Handles creation, management, and querying of tourism events
/// including vehicle requests, driver assignments, and itinerary management.
class TourismEventService {
  // Singleton
  static final TourismEventService _instance = TourismEventService._internal();
  factory TourismEventService() => _instance;
  TourismEventService._internal();

  final SupabaseClient _client = SupabaseConfig.client;

  /// Send a DB notification to a user (shows in notifications screen)
  Future<void> _sendDbNotification({
    required String userId,
    required String title,
    required String body,
    String type = 'bid_update',
    Map<String, dynamic>? data,
  }) async {
    try {
      await _client.from('notifications').insert({
        'user_id': userId,
        'title': title,
        'body': body,
        'type': type,
        'data': data ?? {},
        'read': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error sending bid notification: $e');
    }
  }

  // ===========================================================================
  // EVENTOS
  // ===========================================================================

  /// Creates a new tourism event.
  ///
  /// [data] should include fields like:
  /// - `organizer_id`: the user creating the event
  /// - `title`: event title
  /// - `description`: event description
  /// - `start_date`, `end_date`: event dates
  /// - `pickup_location`, `dropoff_location`: location details
  /// - `expected_passengers`: number of passengers
  /// - `state_code`, `country_code`: location identifiers
  ///
  /// Returns the created event row or empty map on error.
  Future<Map<String, dynamic>> createEvent(Map<String, dynamic> data) async {
    try {
      // Auto-determine status: if driver+vehicle assigned → active
      String status = data['status'] ?? 'draft';
      if (data['driver_id'] != null && data['vehicle_id'] != null) {
        status = 'active';
      }

      final response = await _client
          .from('tourism_events')
          .insert({
            ...data,
            'status': status,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          })
          .select()
          .single();

      return response;
    } catch (e) {
      debugPrint('CREATE_EVENT -> ERROR: $e');
      rethrow;
    }
  }

  /// Gets a single event by ID with related data.
  ///
  /// Returns `null` when no matching event exists.
  /// Fetches organizer profile name via user_id for consistent display.
  Future<Map<String, dynamic>?> getEvent(String eventId) async {
    try {
      debugPrint('EVENT_SVC -> getEvent called for: $eventId');

      // First get the event without joins to avoid RLS issues
      final eventResponse = await _client
          .from('tourism_events')
          .select('*')
          .eq('id', eventId)
          .maybeSingle();

      debugPrint('EVENT_SVC -> eventResponse: $eventResponse');

      if (eventResponse == null) {
        debugPrint('EVENT_SVC -> Event not found');
        return null;
      }

      // Create mutable copy
      final response = Map<String, dynamic>.from(eventResponse);

      // Get driver separately if assigned
      final driverId = response['driver_id'] as String?;
      if (driverId != null) {
        try {
          final driverResponse = await _client
              .from('drivers')
              .select('id, name, full_name, phone, profile_image_url, business_card_url, contact_email, contact_phone, contact_facebook, current_lat, current_lng')
              .eq('id', driverId)
              .maybeSingle();
          debugPrint('EVENT_SVC -> driverResponse: $driverResponse');
          response['drivers'] = driverResponse;
        } catch (e) {
          debugPrint('EVENT_SVC -> Error fetching driver: $e');
        }
      }

      // Get organizer separately
      final organizerId = response['organizer_id'] as String?;
      if (organizerId != null) {
        try {
          final organizerResponse = await _client
              .from('organizers')
              .select('id, user_id, company_name, phone, contact_email, contact_phone, website, description, company_logo_url, business_card_url, contact_facebook, state, country_code, is_verified, commission_rate')
              .eq('id', organizerId)
              .maybeSingle();
          debugPrint('EVENT_SVC -> organizerResponse: $organizerResponse');
          response['organizers'] = organizerResponse;
        } catch (e) {
          debugPrint('EVENT_SVC -> Error fetching organizer: $e');
        }
      }

      // Get vehicle separately
      final vehicleId = response['vehicle_id'] as String?;
      if (vehicleId != null) {
        try {
          final vehicleResponse = await _client
              .from('bus_vehicles')
              .select('id, vehicle_name, vehicle_type, total_seats, image_urls, plate, make, model, year, color, amenities')
              .eq('id', vehicleId)
              .maybeSingle();
          debugPrint('EVENT_SVC -> vehicleResponse: $vehicleResponse');
          response['bus_vehicles'] = vehicleResponse;
        } catch (e) {
          debugPrint('EVENT_SVC -> Error fetching vehicle: $e');
        }
      }

      // Get itinerary from normalized table (source of truth)
      try {
        final itineraryResponse = await _client
            .from('tourism_event_itinerary')
            .select('*')
            .eq('event_id', eventId)
            .order('stop_order', ascending: true);
        var itineraryList = List<Map<String, dynamic>>.from(itineraryResponse);

        // Auto-sync: if normalized table is empty but JSONB has data, populate it
        if (itineraryList.isEmpty) {
          final jsonbItinerary = response['itinerary'];
          if (jsonbItinerary != null && jsonbItinerary is List && jsonbItinerary.isNotEmpty) {
            debugPrint('EVENT_SVC -> Syncing JSONB itinerary to normalized table (${jsonbItinerary.length} stops)');
            itineraryList = await _syncItineraryFromJsonb(eventId, jsonbItinerary);
          }
        }

        response['tourism_event_itinerary'] = itineraryList;
        // Always use normalized table as source of truth for 'itinerary' key
        if (itineraryList.isNotEmpty) {
          response['itinerary'] = itineraryList;
        }
      } catch (e) {
        debugPrint('EVENT_SVC -> Error fetching itinerary: $e');
      }

      // Enrich organizer with profile name
      final organizer = response['organizers'] as Map<String, dynamic>?;
      if (organizer != null && organizer['user_id'] != null) {
        try {
          final profile = await _client
              .from('profiles')
              .select('full_name, email, avatar_url')
              .eq('id', organizer['user_id'])
              .maybeSingle();

          if (profile != null) {
            final enrichedOrganizer = Map<String, dynamic>.from(organizer);
            enrichedOrganizer['name'] = profile['full_name'] ?? organizer['company_name'] ?? 'Organizador';
            enrichedOrganizer['email'] = profile['email'];
            enrichedOrganizer['avatar_url'] = profile['avatar_url'];
            response['organizers'] = enrichedOrganizer;
          }
        } catch (_) {
          // If profile fetch fails, use company_name as fallback
        }
      }

      return response;
    } catch (e, stackTrace) {
      debugPrint('EVENT_SVC -> ERROR in getEvent: $e');
      debugPrint('EVENT_SVC -> Stack: $stackTrace');
      return null;
    }
  }

  /// Updates an existing tourism event.
  ///
  /// Returns the updated event or empty map on error.
  Future<Map<String, dynamic>> updateEvent(
    String eventId,
    Map<String, dynamic> updates,
  ) async {
    try {
      final response = await _client
          .from('tourism_events')
          .update({
            ...updates,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', eventId)
          .select()
          .single();

      return response;
    } catch (e) {
      return {};
    }
  }

  /// Gets all events for an organizer.
  ///
  /// Ordered by creation date descending (newest first).
  /// RLS policies allow organizers to see vehicles and drivers assigned to their events.
  Future<List<Map<String, dynamic>>> getMyEvents(String organizerId) async {
    try {
      final response = await _client
          .from('tourism_events')
          .select('''
            *,
            bus_vehicles(id, vehicle_name, vehicle_type, make, model, year, plate, color, total_seats, image_urls, owner_name, owner_phone),
            tourism_vehicle_bids(id, driver_id, vehicle_id, proposed_price_per_km, driver_status, organizer_status, is_winning_bid, created_at,
              bid_driver:drivers!tourism_vehicle_bids_driver_id_fkey(id, name, full_name, phone, profile_image_url),
              bid_vehicle:bus_vehicles!tourism_vehicle_bids_vehicle_id_fkey(id, vehicle_name, vehicle_type, make, model, year, total_seats, plate)),
            tourism_invitations(id, status)
          ''')
          .eq('organizer_id', organizerId)
          .neq('status', 'cancelled')
          .order('created_at', ascending: false);

      // Calculate confirmed_passengers from invitations
      final events = List<Map<String, dynamic>>.from(response);
      for (final event in events) {
        final invitations = event['tourism_invitations'] as List<dynamic>? ?? [];
        final confirmed = invitations.where((i) {
          final s = (i as Map<String, dynamic>)['status'] as String?;
          return s == 'accepted' || s == 'boarded' || s == 'checked_in';
        }).length;
        event['confirmed_passengers'] = confirmed;
        event['total_invitations'] = invitations.length;
      }

      return events;
    } catch (e) {
      // Log error for debugging
      AppLogger.log('TourismEventService.getMyEvents error: $e');
      return [];
    }
  }

  /// Gets all events where the driver is assigned and accepted.
  ///
  /// Returns events with the driver's assignment status.
  /// Includes vehicle bids with driver info so winning driver profile is available.
  Future<List<Map<String, dynamic>>> getEventsByDriver(String driverId) async {
    try {
      final response = await _client
          .from('tourism_events')
          .select('''
            *,
            organizers(id, company_name, phone, state, is_verified),
            bus_vehicles(id, vehicle_name, vehicle_type, make, model, year, plate, total_seats, image_urls, owner_name, owner_phone),
            tourism_vehicle_bids(id, driver_id, vehicle_id, proposed_price_per_km, driver_status, organizer_status, is_winning_bid, created_at,
              bid_driver:drivers!tourism_vehicle_bids_driver_id_fkey(id, name, full_name, phone, profile_image_url),
              bid_vehicle:bus_vehicles!tourism_vehicle_bids_vehicle_id_fkey(id, vehicle_name, vehicle_type, make, model, year, total_seats, plate)),
            tourism_invitations(id, status)
          ''')
          .eq('driver_id', driverId)
          .eq('vehicle_request_status', 'accepted')
          .order('event_date', ascending: false);

      // Calculate confirmed_passengers from invitations
      final events = List<Map<String, dynamic>>.from(response);
      for (final event in events) {
        final invitations = event['tourism_invitations'] as List<dynamic>? ?? [];
        final confirmed = invitations.where((i) {
          final s = (i as Map<String, dynamic>)['status'] as String?;
          return s == 'accepted' || s == 'boarded' || s == 'checked_in';
        }).length;
        event['confirmed_passengers'] = confirmed;
        event['total_invitations'] = invitations.length;
      }

      return events;
    } catch (e) {
      debugPrint('getEventsByDriver error: $e');
      return [];
    }
  }

  // ===========================================================================
  // VEHICLE REQUESTS
  // ===========================================================================

  /// Sends a vehicle request to a driver for an event.
  ///
  /// [eventId] - the event requiring a vehicle
  /// [vehicleId] - the vehicle being requested
  /// [driverId] - the driver/owner of the vehicle
  ///
  /// Updates the event with vehicle request and notifies the driver.
  Future<Map<String, dynamic>> requestVehicle(
    String eventId,
    String vehicleId,
    String driverId,
  ) async {
    try {
      final response = await _client
          .from('tourism_events')
          .update({
            'vehicle_id': vehicleId,
            'driver_id': driverId,
            'status': 'pending_vehicle',
            'vehicle_request_status': 'pending',
            'vehicle_requested_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', eventId)
          .select()
          .single();

      // Send notification to driver
      await _sendNotification(
        driverId,
        'Nueva solicitud de evento',
        'Un organizador te ha solicitado para un evento de turismo.',
        'tourism_event_request',
        {'event_id': eventId},
      );

      return response;
    } catch (e) {
      return {};
    }
  }

  /// Driver responds to a vehicle request.
  ///
  /// [eventId] - identifies the event with the pending request
  /// [accept] - true to accept, false to reject
  /// [reason] - optional rejection reason
  /// [bidId] - optional bid ID for the new bid system
  ///
  /// Returns the updated event or empty map on error.
  Future<Map<String, dynamic>> respondToVehicleRequest(
    String eventId,
    bool accept, {
    String? reason,
    String? bidId,
    double? pricePerKm,
  }) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();

      // Update the bid record (driver_status + proposed price)
      if (bidId != null) {
        final driverStatus = accept ? 'accepted' : 'rejected';
        final bidUpdate = <String, dynamic>{
          'driver_status': driverStatus,
          'driver_responded_at': now,
          'driver_notes': accept ? null : reason,
          'updated_at': now,
        };
        if (accept && pricePerKm != null) {
          bidUpdate['proposed_price_per_km'] = pricePerKm;
        }
        await _client
            .from('tourism_vehicle_bids')
            .update(bidUpdate)
            .eq('id', bidId);
      }

      // Read the event with organizer user_id for notification
      final response = await _client
          .from('tourism_events')
          .select('*, organizers(user_id)')
          .eq('id', eventId)
          .single();

      // Notify organizer (use organizers.user_id, NOT organizer_id)
      final orgData = response['organizers'] as Map<String, dynamic>?;
      final orgUserId = orgData?['user_id'] as String?;
      if (orgUserId != null) {
        await _sendNotification(
          orgUserId,
          accept ? 'Nueva Puja Recibida' : 'Puja Rechazada',
          accept
              ? 'Un conductor ha enviado su puja${pricePerKm != null ? " de \$${pricePerKm.toStringAsFixed(0)}/km" : ""}.'
              : 'Un conductor ha rechazado la invitacion${reason != null ? ": $reason" : "."}',
          'tourism_request_response',
          {'event_id': eventId, 'accepted': accept, 'bid_id': bidId},
        );
      }

      return response;
    } catch (e) {
      debugPrint('respondToVehicleRequest error: $e');
      return {};
    }
  }

  /// Cancels a pending vehicle request.
  ///
  /// Clears the vehicle and driver assignment and resets the status to draft.
  Future<Map<String, dynamic>> cancelVehicleRequest(String eventId) async {
    try {
      final response = await _client
          .from('tourism_events')
          .update({
            'vehicle_id': null,
            'driver_id': null,
            'status': 'draft',
            'vehicle_request_status': null,
            'vehicle_requested_at': null,
            'vehicle_responded_at': null,
            'vehicle_rejection_reason': null,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', eventId)
          .select()
          .single();

      return response;
    } catch (e) {
      return {};
    }
  }

  /// Gets all open events available for any driver to bid on.
  ///
  /// Returns events with status='draft' (pending bids) that don't have a driver assigned yet.
  /// Any driver can see these and submit a bid.
  Future<List<Map<String, dynamic>>> getOpenEventsForBidding(String driverId) async {
    try {
      // Get events open for PUBLIC bidding (no driver assigned)
      // Uses 'draft' status because DB check constraint doesn't allow 'pending_bids'
      // Only shows events with bid_visibility='public' (or null for backwards compat)
      debugPrint('[OPEN_EVENTS] Fetching open events for driver: $driverId');

      final response = await _client
          .from('tourism_events')
          .select('''
            *,
            organizers(id, company_name, phone, company_logo_url, is_verified,
              contact_email, contact_phone, contact_facebook)
          ''')
          .eq('status', 'draft')
          .isFilter('driver_id', null)
          .order('created_at', ascending: false);

      debugPrint('[OPEN_EVENTS] Raw response count: ${(response as List).length}');

      final results = <Map<String, dynamic>>[];

      // Check which events this driver has already bid on
      List<String> alreadyBidEventIds = [];
      try {
        final existingBids = await _client
            .from('tourism_vehicle_bids')
            .select('event_id')
            .eq('driver_id', driverId);
        alreadyBidEventIds = (existingBids as List)
            .map((b) => b['event_id'] as String)
            .toList();
      } catch (_) {}

      for (final event in response) {
        final mapped = Map<String, dynamic>.from(event as Map);
        final eventId = mapped['id'] as String?;
        // Filter: only public bids (or null = legacy events = treat as public)
        final bidVisibility = mapped['bid_visibility'] as String?;
        if (bidVisibility == 'private') {
          debugPrint('[OPEN_EVENTS] Skipping private event: $eventId');
          continue;
        }
        mapped['_source'] = 'open';
        mapped['already_bid'] = alreadyBidEventIds.contains(eventId);
        results.add(mapped);
      }

      debugPrint('[OPEN_EVENTS] Returning ${results.length} public events');
      return results;
    } catch (e) {
      debugPrint('[OPEN_EVENTS] getOpenEventsForBidding error: $e');
      return [];
    }
  }

  /// Submit a new bid on an open event (driver initiates the bid).
  ///
  /// Creates a tourism_vehicle_bids record for this driver+event.
  Future<Map<String, dynamic>> submitBidOnOpenEvent({
    required String eventId,
    required String driverId,
    required double pricePerKm,
    String? vehicleId,
  }) async {
    // Get driver's first active vehicle if not provided
    vehicleId ??= await _getDriverVehicleId(driverId);

    final bidData = <String, dynamic>{
      'event_id': eventId,
      'driver_id': driverId,
      'driver_status': 'accepted',
      'organizer_status': 'pending',
      'proposed_price_per_km': pricePerKm,
      'is_winning_bid': false,
      'driver_responded_at': DateTime.now().toIso8601String(),
    };
    if (vehicleId != null) {
      bidData['vehicle_id'] = vehicleId;
    }

    final result = await _client.from('tourism_vehicle_bids')
        .insert(bidData).select().single();

    // Notify the organizer about the new bid
    try {
      final event = await _client
          .from('tourism_events')
          .select('organizer_id, event_name, organizers(user_id)')
          .eq('id', eventId)
          .single();
      final orgData = event['organizers'] as Map<String, dynamic>?;
      final orgUserId = orgData?['user_id'] as String?;
      final eventName = event['event_name'] as String? ?? 'Evento';

      // Get driver name
      final driver = await _client
          .from('drivers')
          .select('name')
          .eq('id', driverId)
          .maybeSingle();
      final driverName = driver?['name'] as String? ?? 'Un chofer';

      if (orgUserId != null) {
        await _sendDbNotification(
          userId: orgUserId,
          title: 'Nueva Puja Recibida',
          body: '$driverName ofrece \$${pricePerKm.toStringAsFixed(0)}/km para: $eventName',
          type: 'bid_response',
          data: {'event_id': eventId, 'bid_id': result['id']},
        );
      }
    } catch (e) {
      debugPrint('Error sending bid notification to organizer: $e');
    }

    return result;
  }

  /// Helper: get driver's first active vehicle ID
  Future<String?> _getDriverVehicleId(String driverId) async {
    try {
      final vehicles = await _client
          .from('bus_vehicles')
          .select('id')
          .eq('owner_id', driverId)
          .eq('is_active', true)
          .limit(1);
      if ((vehicles as List).isNotEmpty) {
        return vehicles.first['id'] as String?;
      }
    } catch (_) {}
    return null;
  }

  /// Gets all pending vehicle requests for a driver.
  ///
  /// Checks both the legacy system (tourism_events.vehicle_request_status)
  /// and the new bid system (tourism_vehicle_bids.driver_status).
  Future<List<Map<String, dynamic>>> getPendingVehicleRequests(
    String driverId,
  ) async {
    try {
      final results = <Map<String, dynamic>>[];

      // 1) New bid system: tourism_vehicle_bids with driver_status = pending
      //    OR organizer_status = counter_offered (organizer sent a counter-offer)
      try {
        final bidsResponse = await _client
            .from('tourism_vehicle_bids')
            .select('''
              *,
              tourism_events(*),
              bus_vehicles(id, vehicle_name, vehicle_type, total_seats, image_urls)
            ''')
            .eq('driver_id', driverId)
            .or('driver_status.eq.pending,organizer_status.eq.counter_offered')
            .order('created_at', ascending: false);

        for (final bid in bidsResponse) {
          final event = bid['tourism_events'] as Map<String, dynamic>?;
          if (event == null) continue;

          // Flatten: merge event fields with bid metadata
          final merged = Map<String, dynamic>.from(event);
          merged['bid_id'] = bid['id'];
          merged['bid_driver_status'] = bid['driver_status'];
          merged['bid_organizer_status'] = bid['organizer_status'];
          merged['proposed_price_per_km'] = bid['proposed_price_per_km'];
          merged['organizer_proposed_price'] = bid['organizer_proposed_price'];
          merged['negotiation_round'] = bid['negotiation_round'];
          merged['organizer_notes'] = bid['organizer_notes'];
          merged['bus_vehicles'] = bid['bus_vehicles'];
          merged['_source'] = 'bid'; // track source for respond logic

          // Fetch organizer info
          final organizerId = event['organizer_id'] as String?;
          if (organizerId != null) {
            try {
              final org = await _client
                  .from('organizers')
                  .select('id, company_name, phone, state, is_verified')
                  .eq('id', organizerId)
                  .maybeSingle();
              merged['organizers'] = org;
            } catch (_) {}
          }

          results.add(merged);
        }
      } catch (e) {
        debugPrint('getPendingVehicleRequests bids error: $e');
      }

      // 2) Legacy system: tourism_events.vehicle_request_status = pending
      try {
        final legacyResponse = await _client
            .from('tourism_events')
            .select('''
              *,
              organizers(id, company_name, phone, state, is_verified),
              bus_vehicles(id, vehicle_name, vehicle_type, total_seats, image_urls)
            ''')
            .eq('driver_id', driverId)
            .eq('vehicle_request_status', 'pending')
            .order('vehicle_requested_at', ascending: false);

        for (final event in legacyResponse) {
          // Skip if already covered by a bid
          final eventId = event['id'] as String?;
          final alreadyInBids = results.any((r) => r['id'] == eventId);
          if (!alreadyInBids) {
            final merged = Map<String, dynamic>.from(event);
            merged['_source'] = 'legacy';
            results.add(merged);
          }
        }
      } catch (e) {
        debugPrint('getPendingVehicleRequests legacy error: $e');
      }

      return results;
    } catch (e) {
      return [];
    }
  }

  // ===========================================================================
  // COUNTER-OFFER NEGOTIATION
  // ===========================================================================

  /// Accept the organizer's counter-offer price.
  ///
  /// Notification flow: DB trigger sends FCM push to organizer with
  /// type 'bid_counter_offer'. The driver app handles incoming
  /// counter-offers via FCM → NotificationService._navigateFromNotification.
  Future<void> acceptCounterOffer(String bidId) async {
    await _client.from('tourism_vehicle_bids').update({
      'driver_status': 'accepted',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', bidId);

    // Notify the organizer that the driver accepted the counter-offer
    try {
      final bid = await _client
          .from('tourism_vehicle_bids')
          .select('event_id, driver_id, proposed_price_per_km')
          .eq('id', bidId)
          .single();
      final eventId = bid['event_id'] as String?;
      final driverId = bid['driver_id'] as String?;
      final price = (bid['proposed_price_per_km'] as num?)?.toDouble() ?? 0;

      if (eventId != null) {
        final event = await _client
            .from('tourism_events')
            .select('organizer_id, event_name, organizers(user_id)')
            .eq('id', eventId)
            .single();
        final orgData = event['organizers'] as Map<String, dynamic>?;
        final orgUserId = orgData?['user_id'] as String?;
        final eventName = event['event_name'] as String? ?? 'Evento';

        String driverName = 'El chofer';
        if (driverId != null) {
          final d = await _client.from('drivers').select('name').eq('id', driverId).maybeSingle();
          driverName = d?['name'] as String? ?? driverName;
        }

        if (orgUserId != null) {
          await _sendDbNotification(
            userId: orgUserId,
            title: 'Puja Aceptada',
            body: '$driverName acepto tu oferta de \$${price.toStringAsFixed(2)}/km para: $eventName',
            type: 'bid_accepted',
            data: {'event_id': eventId, 'bid_id': bidId},
          );
        }
      }
    } catch (e) {
      debugPrint('Error sending accept counter notification: $e');
    }
  }

  /// Driver sends a counter-offer back to the organizer.
  ///
  /// Notification flow: DB trigger sends FCM push to organizer with
  /// type 'bid_counter_offer'. No Flutter-side notification call needed;
  /// the DB trigger handles it.
  Future<void> sendDriverCounterOffer({
    required String bidId,
    required double proposedPrice,
  }) async {
    // Read current negotiation_round, increment it
    final bid = await _client
        .from('tourism_vehicle_bids')
        .select('negotiation_round')
        .eq('id', bidId)
        .single();
    final currentRound = (bid['negotiation_round'] as int?) ?? 0;

    await _client.from('tourism_vehicle_bids').update({
      'driver_status': 'counter_offered',
      'proposed_price_per_km': proposedPrice,
      'negotiation_round': currentRound + 1,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', bidId);

    // Notify the organizer about driver's counter-offer
    try {
      final bidFull = await _client
          .from('tourism_vehicle_bids')
          .select('event_id, driver_id')
          .eq('id', bidId)
          .single();
      final eventId = bidFull['event_id'] as String?;
      final driverId = bidFull['driver_id'] as String?;

      if (eventId != null) {
        final event = await _client
            .from('tourism_events')
            .select('organizer_id, event_name, organizers(user_id)')
            .eq('id', eventId)
            .single();
        final orgData = event['organizers'] as Map<String, dynamic>?;
        final orgUserId = orgData?['user_id'] as String?;
        final eventName = event['event_name'] as String? ?? 'Evento';

        String driverName = 'El chofer';
        if (driverId != null) {
          final d = await _client.from('drivers').select('name').eq('id', driverId).maybeSingle();
          driverName = d?['name'] as String? ?? driverName;
        }

        if (orgUserId != null) {
          await _sendDbNotification(
            userId: orgUserId,
            title: 'Contra-oferta del Chofer',
            body: '$driverName propone \$${proposedPrice.toStringAsFixed(2)}/km para: $eventName',
            type: 'bid_counter_offer',
            data: {'event_id': eventId, 'bid_id': bidId},
          );
        }
      }
    } catch (e) {
      debugPrint('Error sending driver counter-offer notification: $e');
    }
  }

  // ===========================================================================
  // STATUS
  // ===========================================================================

  /// Starts the event (changes status to 'in_progress').
  ///
  /// Should be called when the event begins.
  Future<Map<String, dynamic>> startEvent(String eventId) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await _client
          .from('tourism_events')
          .update({
            'status': 'in_progress',
            'updated_at': now,
          })
          .eq('id', eventId);

      // Fetch using the safe getEvent method
      final response = await getEvent(eventId);

      // Notify all accepted passengers that the event has started
      final eventName = response?['event_name'] ?? 'Evento';
      notifyEventPassengers(
        eventId: eventId,
        title: 'Viaje Iniciado',
        body: '"$eventName" ha comenzado. El chofer está en camino.',
        type: 'tourism_event_started',
      );

      return response ?? {'status': 'in_progress', 'id': eventId};
    } catch (e) {
      debugPrint('❌ startEvent error: $e');
      rethrow;
    }
  }

  /// Completes the event (changes status to 'completed').
  ///
  /// Also generates trip records for all participants (passengers, driver, organizer).
  Future<Map<String, dynamic>> completeEvent(String eventId) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();

      // Update the status
      await _client
          .from('tourism_events')
          .update({
            'status': 'completed',
            'updated_at': now,
          })
          .eq('id', eventId);

      // Fetch the updated event using the same safe method as getEvent
      final response = await getEvent(eventId);

      if (response != null) {
        // Generate trip records in background
        _generateTripRecords(eventId, response);
      }

      return response ?? {'status': 'completed', 'id': eventId};
    } catch (e) {
      debugPrint('❌ completeEvent error: $e');
      rethrow;
    }
  }

  /// Generates tourism_trip_records for all participants of a completed event.
  Future<void> _generateTripRecords(String eventId, Map<String, dynamic> event) async {
    try {
      final eventName = event['event_name'] as String? ?? '';
      final eventDate = event['event_date'] as String?;
      final driverId = event['driver_id'] as String?;
      final organizerId = event['organizer_id'] as String?;
      final pricePerKm = (event['price_per_km'] as num?)?.toDouble();
      final totalDistKm = (event['total_distance_km'] as num?)?.toDouble();

      // Denormalized names
      final driverData = event['drivers'] as Map<String, dynamic>?;
      final driverName = driverData?['full_name'] as String? ?? driverData?['name'] as String? ?? '';
      final organizerData = event['organizers'] as Map<String, dynamic>?;
      final organizerName = organizerData?['company_name'] as String? ?? '';
      final vehicleData = event['bus_vehicles'] as Map<String, dynamic>?;
      final vehicleName = vehicleData?['vehicle_name'] as String? ?? '';

      // Build route summary from itinerary
      final itinerary = event['itinerary'];
      String routeSummary = '';
      if (itinerary is List && itinerary.isNotEmpty) {
        final first = itinerary.first['name'] ?? '';
        final last = itinerary.last['name'] ?? '';
        routeSummary = '$first → $last';
      }

      // Calculate event duration from event_date + updated_at
      final startTime = event['event_date'] as String?;
      final endTime = event['updated_at'] as String?;
      int? durationMin;
      if (startTime != null && endTime != null) {
        final start = DateTime.tryParse(startTime);
        final end = DateTime.tryParse(endTime);
        if (start != null && end != null) {
          durationMin = end.difference(start).inMinutes;
        }
      }

      // Get all accepted/checked-in/boarded passengers
      final invitations = await _client
          .from('tourism_invitations')
          .select('user_id, invited_name, pickup_address, pickup_lat, pickup_lng, last_check_in_at, accepted_at, seat_number, boarding_stop, dropoff_stop, gps_tracking_enabled')
          .eq('event_id', eventId)
          .inFilter('status', ['accepted', 'checked_in', 'boarded', 'off_boarded']);

      final records = <Map<String, dynamic>>[];

      // Passenger records
      for (final inv in invitations) {
        final userId = inv['user_id'] as String?;
        if (userId == null) continue;

        records.add({
          'event_id': eventId,
          'user_id': userId,
          'user_role': 'passenger',
          'pickup_address': inv['pickup_address'],
          'pickup_lat': inv['pickup_lat'],
          'pickup_lng': inv['pickup_lng'],
          'km_traveled': totalDistKm,
          'price_paid': (totalDistKm ?? 0) * (pricePerKm ?? 0),
          'price_per_km': pricePerKm,
          'boarded_at': inv['last_check_in_at'] ?? inv['accepted_at'],
          'exited_at': endTime,
          'duration_minutes': durationMin,
          'event_name': eventName,
          'event_date': eventDate,
          'route_summary': routeSummary,
          'driver_name': driverName,
          'organizer_name': organizerName,
          'vehicle_name': vehicleName,
          'payment_status': 'pending',
        });
      }

      // Driver record
      if (driverId != null) {
        records.add({
          'event_id': eventId,
          'user_id': driverId,
          'user_role': 'driver',
          'km_traveled': totalDistKm,
          'boarded_at': startTime,
          'exited_at': endTime,
          'duration_minutes': durationMin,
          'event_name': eventName,
          'event_date': eventDate,
          'route_summary': routeSummary,
          'driver_name': driverName,
          'organizer_name': organizerName,
          'vehicle_name': vehicleName,
          'payment_status': 'pending',
        });
      }

      if (records.isNotEmpty) {
        await _client.from('tourism_trip_records').insert(records);
        debugPrint('[TOURISM] Generated ${records.length} trip records for event $eventId');
      }
    } catch (e) {
      debugPrint('[TOURISM] Error generating trip records: $e');
    }
  }

  /// Publishes the event (changes status to 'active').
  ///
  /// Should be called after itinerary and vehicle are configured.
  Future<Map<String, dynamic>> publishEvent(String eventId) async {
    try {
      final response = await _client
          .from('tourism_events')
          .update({
            'status': 'active',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', eventId)
          .select()
          .single();

      return response;
    } catch (e) {
      return {};
    }
  }

  /// Deletes the event by marking status as 'deleted'.
  ///
  /// Uses UPDATE instead of DELETE because RLS only allows UPDATE for organizers.
  /// Notifies the assigned driver about the deletion.
  Future<void> cancelEvent(String eventId) async {
    try {
      final event = await getEvent(eventId);
      final driverId = event?['driver_id'] as String?;

      // Mark event as cancelled (CHECK constraint only allows known statuses)
      await _client.from('tourism_events').update({
        'status': 'cancelled',
      }).eq('id', eventId);

      // Cancel related invitations
      await _client.from('tourism_invitations').update({
        'status': 'cancelled',
      }).eq('event_id', eventId);

      debugPrint('✅ Event marked as cancelled: $eventId');

      if (driverId != null) {
        await _sendNotification(
          driverId,
          'Evento eliminado',
          'Un evento de turismo al que estabas asignado ha sido eliminado.',
          'tourism_event_cancelled',
          {'event_id': eventId},
        );
      }
    } catch (e) {
      debugPrint('❌ Error deleting event: $e');
      rethrow;
    }
  }

  // ===========================================================================
  // DRIVER MODE
  // ===========================================================================

  /// Sets the driver's operating mode.
  ///
  /// [mode] can be:
  /// - 'personal': driver is doing regular rides
  /// - 'tourism': driver is doing tourism events
  ///
  /// [eventId] should be provided when switching to tourism mode.
  Future<Map<String, dynamic>> setDriverMode(
    String driverId,
    String mode, {
    String? eventId,
  }) async {
    try {
      final response = await _client
          .from(SupabaseConfig.driversTable)
          .update({
            'operating_mode': mode,
            'active_event_id': mode == 'tourism' ? eventId : null,
            'mode_changed_at': DateTime.now().toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', driverId)
          .select()
          .single();

      return response;
    } catch (e) {
      return {};
    }
  }

  /// Gets the currently active tourism event for the driver.
  ///
  /// Returns `null` if the driver has no active event.
  Future<Map<String, dynamic>?> getActiveEvent(String driverId) async {
    try {
      // First check driver's active event
      final driver = await _client
          .from(SupabaseConfig.driversTable)
          .select('active_event_id, operating_mode')
          .eq('id', driverId)
          .maybeSingle();

      if (driver == null ||
          driver['operating_mode'] != 'tourism' ||
          driver['active_event_id'] == null) {
        return null;
      }

      // Get the event details
      return await getEvent(driver['active_event_id']);
    } catch (e) {
      return null;
    }
  }

  // ===========================================================================
  // ITINERARY
  // ===========================================================================

  /// Updates the itinerary for an event.
  ///
  /// [stops] is a list of stop data, each containing:
  /// - `name`: stop name
  /// - `address`: address
  /// - `lat`, `lng`: coordinates
  /// - `stop_order`: order in the itinerary
  /// - `scheduled_time`: expected arrival time
  /// - `duration_minutes`: planned stop duration
  ///
  /// Replaces all existing stops.
  Future<List<Map<String, dynamic>>> updateItinerary(
    String eventId,
    List<Map<String, dynamic>> stops,
  ) async {
    try {
      // Delete existing itinerary
      await _client
          .from('tourism_event_itinerary')
          .delete()
          .eq('event_id', eventId);

      if (stops.isEmpty) return [];

      // Insert new stops with proper ordering
      final rows = stops.asMap().entries.map((entry) {
        return {
          ...entry.value,
          'event_id': eventId,
          'stop_order': entry.value['stop_order'] ?? entry.key,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        };
      }).toList();

      final response = await _client
          .from('tourism_event_itinerary')
          .insert(rows)
          .select();

      // Sync JSONB column on tourism_events so getEvent() returns fresh data
      try {
        await _client
            .from('tourism_events')
            .update({'itinerary': stops})
            .eq('id', eventId);
      } catch (_) {
        // Non-fatal: normalized table is source of truth
      }

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  /// Syncs JSONB itinerary data from tourism_events to the normalized table.
  ///
  /// Handles two JSONB formats:
  /// - Format A (organizer): {order, name, address, arrival_time, departure_time, notes, lat, lng}
  /// - Format B (driver):    {stopOrder, name, notes, estimatedArrival, durationMinutes, lat, lng}
  Future<List<Map<String, dynamic>>> _syncItineraryFromJsonb(
    String eventId,
    List<dynamic> jsonbStops,
  ) async {
    try {
      final rows = <Map<String, dynamic>>[];

      for (int i = 0; i < jsonbStops.length; i++) {
        final stop = Map<String, dynamic>.from(jsonbStops[i] as Map);

        // Determine stop_order: try 'order' (Format A), then 'stopOrder' (Format B), then index
        final stopOrder = (stop['order'] as int?) ??
            (stop['stopOrder'] as int?) ??
            i;

        // Determine scheduled_time: try 'arrival_time' (Format A), then parse 'estimatedArrival' (Format B)
        String? scheduledTime = stop['arrival_time'] as String?;
        if (scheduledTime == null && stop['estimatedArrival'] != null) {
          final dt = DateTime.tryParse(stop['estimatedArrival']);
          if (dt != null) {
            final local = dt.toLocal();
            scheduledTime = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
          }
        }

        rows.add({
          'event_id': eventId,
          'stop_order': stopOrder,
          'name': stop['name'] ?? 'Parada ${stopOrder + 1}',
          'description': stop['type'] as String?,
          'address': stop['address'] as String?,
          'lat': (stop['lat'] as num?)?.toDouble(),
          'lng': (stop['lng'] as num?)?.toDouble(),
          'arrival_time': stop['arrival_time'] as String?,
          'departure_time': stop['departure_time'] as String?,
          'scheduled_time': scheduledTime,
          'duration_minutes': (stop['durationMinutes'] as int?) ?? 30,
          'notes': stop['notes'] as String?,
          'status': 'pending',
        });
      }

      if (rows.isEmpty) return [];

      final response = await _client
          .from('tourism_event_itinerary')
          .upsert(rows, onConflict: 'event_id,stop_order')
          .select();

      debugPrint('EVENT_SVC -> Synced ${response.length} stops to normalized table');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('EVENT_SVC -> Error syncing itinerary: $e');
      return [];
    }
  }

  /// Marks a specific stop as arrived.
  ///
  /// [stopIndex] is the 0-based index (stop_order) of the stop.
  Future<Map<String, dynamic>> markStopArrived(
    String eventId,
    int stopIndex,
  ) async {
    try {
      final response = await _client
          .from('tourism_event_itinerary')
          .update({
            'arrived_at': DateTime.now().toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('event_id', eventId)
          .eq('stop_order', stopIndex)
          .select()
          .single();

      return response;
    } catch (e) {
      return {};
    }
  }

  // ===========================================================================
  // REALTIME
  // ===========================================================================

  /// Subscribes to real-time updates for a specific event.
  ///
  /// [onUpdate] is called whenever the event data changes.
  ///
  /// Returns a RealtimeChannel that can be used to unsubscribe.
  RealtimeChannel subscribeToEvent(
    String eventId,
    void Function(Map<String, dynamic> event) onUpdate,
  ) {
    final channel = _client.channel('tourism_event_$eventId');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'tourism_events',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: eventId,
      ),
      callback: (payload) {
        final newRecord = payload.newRecord;
        if (newRecord.isNotEmpty) {
          onUpdate(newRecord);
        }
      },
    ).subscribe();

    return channel;
  }

  /// Subscribes to real-time vehicle requests for a driver.
  ///
  /// Listens to both tourism_vehicle_bids (new system) and
  /// tourism_events (legacy system).
  ///
  /// [onRequest] is called whenever a request is created or updated.
  ///
  /// Returns a RealtimeChannel that can be used to unsubscribe.
  RealtimeChannel subscribeToVehicleRequests(
    String driverId,
    void Function(Map<String, dynamic> request) onRequest,
  ) {
    final channel = _client.channel('tourism_requests_$driverId');

    // New bid system
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'tourism_vehicle_bids',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'driver_id',
        value: driverId,
      ),
      callback: (payload) {
        final newRecord = payload.newRecord;
        if (newRecord.isNotEmpty &&
            (newRecord['driver_status'] == 'pending' ||
             newRecord['organizer_status'] == 'counter_offered')) {
          onRequest(newRecord);
        }
      },
    );

    // Legacy system
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'tourism_events',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'driver_id',
        value: driverId,
      ),
      callback: (payload) {
        final newRecord = payload.newRecord;
        if (newRecord.isNotEmpty &&
            newRecord['vehicle_request_status'] == 'pending') {
          onRequest(newRecord);
        }
      },
    );

    channel.subscribe();

    return channel;
  }

  /// Unsubscribes from a realtime channel.
  Future<void> unsubscribe(RealtimeChannel channel) async {
    try {
      await _client.removeChannel(channel);
    } catch (e) {
      // Ignore unsubscribe errors
    }
  }

  // ===========================================================================
  // VEHICLE BROWSING
  // ===========================================================================

  /// Fetches available bus vehicles for tourism events.
  ///
  /// Only returns vehicles where is_exclusive = false and available_for_tourism = true.
  Future<List<Map<String, dynamic>>> getAvailableVehicles({
    String? stateCode,
    String? countryCode,
  }) async {
    try {
      var query = _client
          .from('bus_vehicles')
          .select('''
            *,
            drivers!bus_vehicles_owner_id_fkey(id, name, phone, profile_image_url, current_lat, current_lng)
          ''')
          .eq('is_active', true)
          .eq('is_exclusive', false)
          .eq('available_for_tourism', true);

      if (stateCode != null && stateCode.isNotEmpty) {
        query = query.eq('state_code', stateCode);
      }
      if (countryCode != null && countryCode.isNotEmpty) {
        query = query.eq('country_code', countryCode);
      }

      final response = await query.order('created_at', ascending: false);

      final results = <Map<String, dynamic>>[];
      for (final row in response as List) {
        final vehicle = Map<String, dynamic>.from(row as Map);
        final driver = vehicle.remove('drivers') as Map<String, dynamic>?;
        if (driver != null) {
          vehicle['owner_name'] = driver['name'];
          vehicle['owner_phone'] = driver['phone'];
          vehicle['owner_avatar_url'] = driver['profile_image_url'];
          vehicle['owner_lat'] = driver['current_lat'];
          vehicle['owner_lng'] = driver['current_lng'];
        }
        results.add(vehicle);
      }

      return results;
    } catch (e) {
      return [];
    }
  }

  // ===========================================================================
  // PRICING CALCULATION
  // ===========================================================================

  /// Calculate pricing for an event based on distance.
  ///
  /// When [isDriverOwned] is true (driver created the event), organizer
  /// commission is 0%. When false (organizer hired a driver), organizer
  /// gets 3%.
  Map<String, double> calculatePricing({
    required double distanceKm,
    required double pricePerKm,
    bool isDriverOwned = false,
    double toroFeePercent = 0.18,
    double organizerCommissionPercent = 0.03,
  }) {
    final totalBase = distanceKm * pricePerKm;
    final toroFee = totalBase * toroFeePercent;
    final organizerCommission = isDriverOwned ? 0.0 : totalBase * organizerCommissionPercent;
    final driverAmount = totalBase - toroFee - organizerCommission;

    return {
      'total_base_price': totalBase,
      'toro_fee': toroFee,
      'organizer_commission': organizerCommission,
      'driver_amount': driverAmount,
      'distance_km': distanceKm,
      'price_per_km': pricePerKm,
    };
  }

  // ===========================================================================
  // JOIN REQUESTS (Passenger -> Event)
  // ===========================================================================

  /// Fetches all join requests for a specific event, including passenger profile data.
  ///
  /// [eventId] - The tourism event ID.
  ///
  /// Returns a list of join request records enriched with profile info
  /// (full_name, phone, avatar_url) from the profiles table.
  /// Ordered by creation date descending (newest first).
  Future<List<Map<String, dynamic>>> getJoinRequestsForEvent(
    String eventId,
  ) async {
    try {
      final response = await _client
          .from('tourism_join_requests')
          .select('''
            *,
            profile:profiles!tourism_join_requests_user_id_fkey(
              id,
              full_name,
              phone,
              email,
              avatar_url
            )
          ''')
          .eq('event_id', eventId)
          .order('created_at', ascending: false);

      final results = <Map<String, dynamic>>[];
      for (final row in response as List) {
        final request = Map<String, dynamic>.from(row as Map);
        final profile = request.remove('profile') as Map<String, dynamic>?;

        // Enrich with profile data
        request['passenger_name'] = profile?['full_name'] ??
            request['passenger_name'] ??
            'Sin nombre';
        request['passenger_phone'] = profile?['phone'] ??
            request['passenger_phone'];
        request['passenger_email'] = profile?['email'];
        request['passenger_avatar_url'] = profile?['avatar_url'];
        request['has_profile'] = profile != null;

        results.add(request);
      }

      return results;
    } catch (e) {
      debugPrint('getJoinRequestsForEvent error: $e');
      // Fallback without profile join
      try {
        final fallback = await _client
            .from('tourism_join_requests')
            .select()
            .eq('event_id', eventId)
            .order('created_at', ascending: false);

        return List<Map<String, dynamic>>.from(
          (fallback as List).map((r) {
            final m = Map<String, dynamic>.from(r as Map);
            m['passenger_name'] = m['passenger_name'] ?? 'Sin nombre';
            m['has_profile'] = false;
            return m;
          }),
        );
      } catch (_) {
        return [];
      }
    }
  }

  /// Accepts a join request from a passenger.
  ///
  /// Workflow:
  /// 1. Updates the join request status to 'accepted' with responded_at timestamp.
  /// 2. Creates a tourism_invitation for the accepted passenger so they appear
  ///    in the passenger list and can receive check-in / GPS tracking.
  /// 3. Links the invitation back to the join request via invitation_id.
  ///
  /// The DB trigger `on_join_request_accepted` handles sending a push
  /// notification to the rider app.
  ///
  /// [requestId] - The UUID of the join request.
  /// [eventId] - The tourism event ID (needed to create the invitation).
  ///
  /// Returns `true` on success, `false` on failure.
  Future<bool> acceptJoinRequest(String requestId, String eventId) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();

      // 1. Fetch the join request to get passenger info
      final joinRequest = await _client
          .from('tourism_join_requests')
          .select()
          .eq('id', requestId)
          .single();

      final userId = joinRequest['user_id'] as String?;
      final passengerName = joinRequest['passenger_name'] as String? ?? 'Pasajero';
      final passengerPhone = joinRequest['passenger_phone'] as String?;
      final pickupAddress = joinRequest['pickup_address'] as String?;
      final pickupLat = joinRequest['pickup_lat'];
      final pickupLng = joinRequest['pickup_lng'];
      final dropoffAddress = joinRequest['dropoff_address'] as String?;
      final dropoffLat = joinRequest['dropoff_lat'];
      final dropoffLng = joinRequest['dropoff_lng'];

      // 2. Create a tourism_invitation for this passenger
      final invitationData = <String, dynamic>{
        'event_id': eventId,
        'user_id': userId,
        'invited_name': passengerName,
        'invited_phone': passengerPhone,
        'invitation_method': 'join_request',
        'status': 'accepted',
        'accepted_at': now,
        'created_at': now,
        'updated_at': now,
      };

      // Include pickup/dropoff if provided
      if (pickupAddress != null) invitationData['pickup_address'] = pickupAddress;
      if (pickupLat != null) invitationData['pickup_lat'] = pickupLat;
      if (pickupLng != null) invitationData['pickup_lng'] = pickupLng;
      if (dropoffAddress != null) invitationData['dropoff_address'] = dropoffAddress;
      if (dropoffLat != null) invitationData['dropoff_lat'] = dropoffLat;
      if (dropoffLng != null) invitationData['dropoff_lng'] = dropoffLng;

      // Generate a simple invitation code
      final code = 'JR-${requestId.substring(0, 8).toUpperCase()}';
      invitationData['invitation_code'] = code;

      final invitation = await _client
          .from('tourism_invitations')
          .insert(invitationData)
          .select()
          .single();

      final invitationId = invitation['id'] as String;

      // 3. Update join request: accepted + link to invitation
      await _client.from('tourism_join_requests').update({
        'status': 'accepted',
        'responded_at': now,
        'invitation_id': invitationId,
        'updated_at': now,
      }).eq('id', requestId);

      // 4. Notify the passenger (non-critical)
      if (userId != null) {
        await _sendNotification(
          userId,
          'Solicitud aceptada',
          'Tu solicitud para unirte al evento ha sido aceptada.',
          'tourism_join_accepted',
          {'event_id': eventId, 'invitation_id': invitationId},
        );
      }

      debugPrint('JOIN_REQ -> Accepted request $requestId, invitation $invitationId');
      return true;
    } catch (e) {
      debugPrint('acceptJoinRequest error: $e');
      return false;
    }
  }

  /// Rejects a join request from a passenger.
  ///
  /// Updates the join request status to 'rejected' with an optional reason.
  ///
  /// [requestId] - The UUID of the join request.
  /// [reason] - Optional rejection reason shown to the passenger.
  ///
  /// Returns `true` on success, `false` on failure.
  Future<bool> rejectJoinRequest(String requestId, {String? reason}) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();

      // Fetch user_id before updating so we can notify
      final joinRequest = await _client
          .from('tourism_join_requests')
          .select('user_id, event_id')
          .eq('id', requestId)
          .maybeSingle();

      await _client.from('tourism_join_requests').update({
        'status': 'rejected',
        'responded_at': now,
        'response_notes': reason,
        'updated_at': now,
      }).eq('id', requestId);

      // Notify the passenger (non-critical)
      final userId = joinRequest?['user_id'] as String?;
      final eventId = joinRequest?['event_id'] as String?;
      if (userId != null) {
        await _sendNotification(
          userId,
          'Solicitud rechazada',
          reason != null && reason.isNotEmpty
              ? 'Tu solicitud fue rechazada: $reason'
              : 'Tu solicitud para unirte al evento no fue aceptada.',
          'tourism_join_rejected',
          {'event_id': eventId, 'request_id': requestId},
        );
      }

      debugPrint('JOIN_REQ -> Rejected request $requestId');
      return true;
    } catch (e) {
      debugPrint('rejectJoinRequest error: $e');
      return false;
    }
  }

  /// Subscribes to real-time join request changes for a specific event.
  ///
  /// [eventId] - The tourism event ID.
  /// [onRequest] - Called when a join request is created or updated.
  ///
  /// Returns a RealtimeChannel that should be unsubscribed when no longer needed.
  RealtimeChannel subscribeToJoinRequests(
    String eventId,
    void Function(Map<String, dynamic> payload) onRequest,
  ) {
    final channel = _client.channel('join_requests_$eventId');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'tourism_join_requests',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'event_id',
        value: eventId,
      ),
      callback: (payload) {
        final newRecord = payload.newRecord;
        if (newRecord.isNotEmpty) {
          onRequest(newRecord);
        }
      },
    ).subscribe();

    return channel;
  }

  /// Counts pending join requests for an event.
  ///
  /// Useful for showing a badge count on the event detail screen.
  Future<int> countPendingJoinRequests(String eventId) async {
    try {
      final response = await _client
          .from('tourism_join_requests')
          .select('id')
          .eq('event_id', eventId)
          .eq('status', 'pending');

      return (response as List).length;
    } catch (e) {
      return 0;
    }
  }

  // ===========================================================================
  // EVENT REVIEWS (Driver/Organizer side - read-only, anonymous)
  // ===========================================================================

  /// Gets all reviews for a specific event.
  ///
  /// Returns anonymous review data (no user_id exposed).
  /// Ordered by creation date descending (newest first).
  Future<List<Map<String, dynamic>>> getEventReviews(String eventId) async {
    try {
      final response = await _client
          .from('tourism_event_reviews')
          .select('id, event_id, overall_rating, driver_rating, organizer_rating, vehicle_rating, comment, improvement_tags, would_recommend, created_at')
          .eq('event_id', eventId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('getEventReviews error: $e');
      return [];
    }
  }

  /// Gets average ratings across all events for the current driver.
  ///
  /// Aggregates reviews from all events where the driver is assigned.
  /// Returns a map with avg ratings, total reviews, and top improvement tags.
  Future<Map<String, dynamic>> getMyAverageRatings(String driverId) async {
    try {
      // Get all events assigned to this driver
      final events = await _client
          .from('tourism_events')
          .select('id, avg_overall_rating, avg_driver_rating, avg_organizer_rating, total_reviews')
          .eq('driver_id', driverId);

      final eventList = List<Map<String, dynamic>>.from(events);
      if (eventList.isEmpty) {
        return {
          'avg_overall': 0.0,
          'avg_driver': 0.0,
          'total_reviews': 0,
          'total_events': 0,
          'improvement_tags': <Map<String, dynamic>>[],
        };
      }

      double sumOverall = 0;
      double sumDriver = 0;
      int totalReviews = 0;
      int eventsWithReviews = 0;

      for (final e in eventList) {
        final reviews = (e['total_reviews'] as num?)?.toInt() ?? 0;
        if (reviews > 0) {
          eventsWithReviews++;
          totalReviews += reviews;
          sumOverall += (e['avg_overall_rating'] as num?)?.toDouble() ?? 0;
          sumDriver += (e['avg_driver_rating'] as num?)?.toDouble() ?? 0;
        }
      }

      final avgOverall = eventsWithReviews > 0 ? sumOverall / eventsWithReviews : 0.0;
      final avgDriver = eventsWithReviews > 0 ? sumDriver / eventsWithReviews : 0.0;

      // Get aggregated improvement tags across all events
      final eventIds = eventList.map((e) => e['id'] as String).toList();
      final Map<String, int> tagCounts = {};

      try {
        final reviews = await _client
            .from('tourism_event_reviews')
            .select('improvement_tags')
            .inFilter('event_id', eventIds);

        for (final r in List<Map<String, dynamic>>.from(reviews)) {
          final tags = r['improvement_tags'];
          if (tags is List) {
            for (final t in tags) {
              final tag = t.toString();
              tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
            }
          }
        }
      } catch (_) {
        // Non-critical: tags aggregation failed
      }

      final sortedTags = tagCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      return {
        'avg_overall': avgOverall,
        'avg_driver': avgDriver,
        'total_reviews': totalReviews,
        'total_events': eventList.length,
        'events_with_reviews': eventsWithReviews,
        'improvement_tags': sortedTags
            .take(10)
            .map((e) => {'tag': e.key, 'count': e.value})
            .toList(),
      };
    } catch (e) {
      debugPrint('getMyAverageRatings error: $e');
      return {
        'avg_overall': 0.0,
        'avg_driver': 0.0,
        'total_reviews': 0,
        'total_events': 0,
        'improvement_tags': <Map<String, dynamic>>[],
      };
    }
  }

  // ===========================================================================
  // HELPER METHODS
  // ===========================================================================

  /// Sends a notification to a user.
  Future<void> _sendNotification(
    String userId,
    String title,
    String body,
    String type,
    Map<String, dynamic> data,
  ) async {
    try {
      await _client.from(SupabaseConfig.notificationsTable).insert({
        'user_id': userId,
        'title': title,
        'body': body,
        'type': type,
        'data': data,
        'read': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      // Notification failed - non-critical
    }
  }

  /// Logs an itinerary change for audit/billing purposes.
  /// Records are visible in admin panel for weekly billing.
  Future<void> logItineraryChange({
    required String eventId,
    required String changeType,
    required String summary,
    Map<String, dynamic>? oldValue,
    Map<String, dynamic>? newValue,
  }) async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;

      // Get organizer name
      String? organizerName;
      try {
        final event = await _client
            .from('tourism_events')
            .select('organizer_id, organizers(company_name)')
            .eq('id', eventId)
            .maybeSingle();
        final org = event?['organizers'] as Map<String, dynamic>?;
        organizerName = org?['company_name'];
      } catch (_) {}

      await _client.from('tourism_event_changes').insert({
        'event_id': eventId,
        'changed_by': userId,
        'change_type': changeType,
        'change_summary': summary,
        'old_value': oldValue,
        'new_value': newValue,
        'organizer_name': organizerName,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('LOG_CHANGE -> Error: $e');
    }
  }

  /// Notifies all accepted/checked-in passengers of an event change.
  ///
  /// Used when organizer updates price, seats, or route so riders stay informed.
  Future<void> notifyEventPassengers({
    required String eventId,
    required String title,
    required String body,
    required String type,
    Map<String, dynamic> extraData = const {},
  }) async {
    try {
      final invitations = await _client
          .from('tourism_invitations')
          .select('user_id')
          .eq('event_id', eventId)
          .inFilter('status', ['accepted', 'checked_in', 'boarded']);

      for (final inv in invitations) {
        final userId = inv['user_id'] as String?;
        if (userId != null) {
          await _sendNotification(userId, title, body, type, {
            'event_id': eventId,
            ...extraData,
          });
        }
      }
    } catch (e) {
      debugPrint('NOTIFY_PASSENGERS -> Error: $e');
    }
  }

  /// Broadcasts an emergency notification to ALL event passengers regardless
  /// of invitation status (pending, accepted, checked_in, boarded, etc.).
  ///
  /// This is a Level 4 emergency broadcast — use only for critical situations
  /// like route changes, weather alerts, or safety warnings.
  ///
  /// Returns the number of passengers notified.
  Future<int> broadcastToAllPassengers({
    required String eventId,
    required String title,
    required String body,
    Map<String, dynamic> extraData = const {},
  }) async {
    int count = 0;
    try {
      // Fetch ALL invitations for this event — no status filter
      final invitations = await _client
          .from('tourism_invitations')
          .select('user_id')
          .eq('event_id', eventId);

      for (final inv in invitations) {
        final userId = inv['user_id'] as String?;
        if (userId != null) {
          await _sendNotification(
            userId,
            title,
            body,
            'tourism_emergency_broadcast',
            {
              'event_id': eventId,
              'is_emergency': true,
              ...extraData,
            },
          );
          count++;
        }
      }
      debugPrint('EMERGENCY_BROADCAST -> Sent to $count passengers');
    } catch (e) {
      debugPrint('EMERGENCY_BROADCAST -> Error: $e');
    }
    return count;
  }

  /// Sends a custom organizer announcement to passengers filtered by status.
  ///
  /// [statusFilter] controls the audience:
  /// - `null` or empty list: all accepted + checked_in (default behavior)
  /// - `['accepted']`: only accepted passengers
  /// - `['checked_in', 'boarded']`: only boarded passengers
  /// - `['pending', 'invited']`: only pending invitations
  /// - `['accepted', 'checked_in', 'boarded', 'pending', 'invited']`: everyone
  ///
  /// Returns the number of passengers notified.
  Future<int> sendOrganizerAnnouncement({
    required String eventId,
    required String title,
    required String body,
    List<String>? statusFilter,
    Map<String, dynamic> extraData = const {},
  }) async {
    int count = 0;
    try {
      final filter = (statusFilter != null && statusFilter.isNotEmpty)
          ? statusFilter
          : ['accepted', 'checked_in'];

      final invitations = await _client
          .from('tourism_invitations')
          .select('user_id')
          .eq('event_id', eventId)
          .inFilter('status', filter);

      for (final inv in invitations) {
        final userId = inv['user_id'] as String?;
        if (userId != null) {
          await _sendNotification(
            userId,
            title,
            body,
            'tourism_organizer_announcement',
            {
              'event_id': eventId,
              ...extraData,
            },
          );
          count++;
        }
      }
      debugPrint('ORGANIZER_ANNOUNCEMENT -> Sent to $count passengers (filter: $filter)');
    } catch (e) {
      debugPrint('ORGANIZER_ANNOUNCEMENT -> Error: $e');
    }
    return count;
  }

  // ===========================================================================
  // EVENT COMPLETION REPORT
  // ===========================================================================

  /// Generate a completion report for a finished event.
  /// Returns a Map with all event statistics - NO personal passenger data.
  /// This data can be displayed in-app or exported.
  Future<Map<String, dynamic>> getEventCompletionReport(String eventId) async {
    try {
      // Get event details
      final event = await _client
          .from('tourism_events')
          .select('*, bus_vehicles(vehicle_name, vehicle_type, total_seats)')
          .eq('id', eventId)
          .single();

      // Get passenger stats (anonymous - no names)
      final passengers = await _client
          .from('tourism_invitations')
          .select('km_traveled, total_price, payment_status, boarded_at, exited_at, status')
          .eq('event_id', eventId)
          .inFilter('status', ['accepted', 'boarded', 'checked_in', 'off_boarded']);

      final passengerList = List<Map<String, dynamic>>.from(passengers);
      final totalPassengers = passengerList.length;
      final totalKmAllPassengers = passengerList.fold<double>(
        0, (sum, p) => sum + ((p['km_traveled'] as num?)?.toDouble() ?? 0));
      final totalRevenue = passengerList.fold<double>(
        0, (sum, p) => sum + ((p['total_price'] as num?)?.toDouble() ?? 0));
      final paidCount = passengerList.where((p) => p['payment_status'] == 'paid').length;

      // Get reviews (anonymous - no user info)
      final reviews = await _client
          .from('tourism_event_reviews')
          .select('overall_rating, driver_rating, organizer_rating, vehicle_rating, improvement_tags, would_recommend, comment')
          .eq('event_id', eventId);

      final reviewList = List<Map<String, dynamic>>.from(reviews);
      final totalReviews = reviewList.length;

      // Calculate average ratings
      double avgOverall = 0, avgDriver = 0, avgOrganizer = 0, avgVehicle = 0;
      int recommendCount = 0;
      final Map<String, int> tagCounts = {};

      for (final r in reviewList) {
        avgOverall += (r['overall_rating'] as num?)?.toDouble() ?? 0;
        avgDriver += (r['driver_rating'] as num?)?.toDouble() ?? 0;
        avgOrganizer += (r['organizer_rating'] as num?)?.toDouble() ?? 0;
        avgVehicle += (r['vehicle_rating'] as num?)?.toDouble() ?? 0;
        if (r['would_recommend'] == true) recommendCount++;
        final tags = r['improvement_tags'] as List? ?? [];
        for (final tag in tags) {
          tagCounts[tag.toString()] = (tagCounts[tag.toString()] ?? 0) + 1;
        }
      }

      if (totalReviews > 0) {
        avgOverall /= totalReviews;
        avgDriver /= totalReviews;
        avgOrganizer /= totalReviews;
        avgVehicle /= totalReviews;
      }

      // Sort improvement tags by frequency
      final sortedTags = tagCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      // Get anonymous comments (no user attribution)
      final comments = reviewList
          .where((r) => r['comment'] != null && r['comment'].toString().trim().isNotEmpty)
          .map((r) => r['comment'].toString())
          .toList();

      final isDriverOwned = event['is_driver_owned'] == true;
      final pricePerKm = (event['price_per_km'] as num?)?.toDouble() ?? 0;
      final toroFee = totalRevenue * 0.18;
      final organizerCommission = isDriverOwned ? 0.0 : totalRevenue * 0.03;
      final driverEarnings = totalRevenue - toroFee - organizerCommission;

      return {
        // Event info
        'event_name': event['event_name'],
        'event_date': event['event_date'],
        'event_type': event['event_type'],
        'status': event['status'],
        'total_distance_km': event['total_distance_km'],
        'price_per_km': pricePerKm,
        'vehicle_name': event['bus_vehicles']?['vehicle_name'],
        'is_driver_owned': isDriverOwned,

        // Passenger stats (anonymous)
        'total_passengers': totalPassengers,
        'total_km_all_passengers': totalKmAllPassengers,
        'paid_passengers': paidCount,

        // Revenue
        'total_revenue': totalRevenue,
        'toro_fee': toroFee,
        'organizer_commission': organizerCommission,
        'driver_earnings': driverEarnings,

        // Reviews (anonymous)
        'total_reviews': totalReviews,
        'avg_overall_rating': avgOverall,
        'avg_driver_rating': avgDriver,
        'avg_organizer_rating': avgOrganizer,
        'avg_vehicle_rating': avgVehicle,
        'recommend_percentage': totalReviews > 0 ? (recommendCount / totalReviews * 100) : 0,
        'improvement_suggestions': sortedTags.map((e) => {'tag': e.key, 'count': e.value}).toList(),
        'anonymous_comments': comments,
      };
    } catch (e) {
      return {'error': 'Error al generar reporte: $e'};
    }
  }

  // ===========================================================================
  // ABUSE REPORTS
  // ===========================================================================

  /// Submits an abuse report from the driver/organizer side.
  ///
  /// [eventId] - The tourism event where the incident occurred.
  /// [reportedUserId] - Optional: the user being reported.
  /// [reportType] - One of: passenger_abuse, safety_issue, pricing_fraud, other.
  /// [severity] - One of: low, medium, high, critical.
  /// [description] - Free-text description of the incident.
  ///
  /// Throws if the user is not authenticated.
  Future<void> submitAbuseReport({
    required String eventId,
    String? reportedUserId,
    required String reportType,
    required String severity,
    required String description,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('No autenticado');

    await _client.from('tourism_abuse_reports').insert({
      'event_id': eventId,
      'reporter_id': userId,
      'reported_user_id': reportedUserId,
      'report_type': reportType,
      'severity': severity,
      'description': description,
      'status': 'pending',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Gets ratings for the last N events for a driver (for trend display).
  ///
  /// Returns a list of maps with event_name, avg_overall_rating, avg_driver_rating,
  /// and start_date, ordered newest first.
  Future<List<Map<String, dynamic>>> getRecentEventRatings(
    String driverId, {
    int limit = 5,
  }) async {
    try {
      final response = await _client
          .from('tourism_events')
          .select('id, title, start_date, avg_overall_rating, avg_driver_rating, total_reviews')
          .eq('driver_id', driverId)
          .gt('total_reviews', 0)
          .order('start_date', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('getRecentEventRatings error: $e');
      return [];
    }
  }
  // ===========================================================================
  // SCHEMA DIAGNOSTICS
  // ===========================================================================

  /// Validates all tourism schema connections and logs results.
  ///
  /// Checks every table used by the tourism system and logs accessibility.
  /// Returns a map with table name -> {ok: bool, count: int, error: String?}
  Future<Map<String, dynamic>> validateSchemaConnections() async {
    debugPrint('═══════════════════════════════════════════════════');
    debugPrint('  TOURISM SCHEMA DIAGNOSTICS');
    debugPrint('═══════════════════════════════════════════════════');

    final results = <String, dynamic>{};
    int passed = 0;
    int failed = 0;

    Future<void> check(String table, {String select = 'id'}) async {
      try {
        final response = await _client.from(table).select(select).limit(1);
        final count = (response as List).length;
        results[table] = {'ok': true, 'sample': count};
        debugPrint('  [OK] $table');
        passed++;
      } catch (e) {
        results[table] = {'ok': false, 'error': '$e'};
        debugPrint('  [FAIL] $table — $e');
        failed++;
      }
    }

    // Core tourism
    await check('tourism_events');
    await check('tourism_invitations');
    await check('tourism_check_ins');
    await check('tourism_messages');
    await check('tourism_join_requests');
    await check('tourism_event_reviews');
    await check('tourism_trip_records');
    await check('tourism_vehicle_bids');
    await check('tourism_passenger_locations');
    await check('tourism_event_itinerary');
    await check('tourism_abuse_reports');

    // Bus/vehicle
    await check('bus_vehicles');
    await check('bus_routes');
    await check('bus_route_stops');
    await check('bus_seat_reservations');
    await check('bus_driver_location');
    await check('bus_events');
    await check('bus_messages');
    await check('bus_calls');

    // Organizer
    await check('organizers');
    await check('organizer_credit_accounts');
    await check('organizer_weekly_statements');

    // Supporting
    await check('drivers', select: 'id, name, business_card_url');
    await check('profiles', select: 'id, full_name');

    debugPrint('───────────────────────────────────────────────────');
    debugPrint('  RESULT: $passed passed, $failed failed');
    debugPrint('═══════════════════════════════════════════════════');

    results['_summary'] = {'total': passed + failed, 'passed': passed, 'failed': failed, 'all_ok': failed == 0};
    return results;
  }

  /// Validates event data completeness for a specific event.
  ///
  /// Checks organizer, driver, vehicle, itinerary, invitations, messages, bids, trip records.
  Future<Map<String, dynamic>> validateEventCompleteness(String eventId) async {
    debugPrint('── EVENT COMPLETENESS: $eventId ──');
    final checks = <String, dynamic>{};

    try {
      final event = await _client.from('tourism_events').select('*').eq('id', eventId).maybeSingle();
      if (event == null) {
        debugPrint('  [FAIL] Event not found');
        return {'event': {'ok': false, 'error': 'Not found'}};
      }
      checks['event'] = {'ok': true, 'status': event['status'], 'country_code': event['country_code']};
      debugPrint('  [OK] Event: ${event['event_name']} (${event['status']}) country=${event['country_code']}');

      // Organizer
      final orgId = event['organizer_id'] as String?;
      if (orgId != null) {
        final org = await _client.from('organizers').select('id, company_name, phone, country_code').eq('id', orgId).maybeSingle();
        checks['organizer'] = org != null ? {'ok': true, 'name': org['company_name']} : {'ok': false, 'error': 'Not found'};
        debugPrint('  ${org != null ? "[OK]" : "[FAIL]"} Organizer: ${org?['company_name'] ?? "NOT FOUND"}');
      }

      // Driver
      final dId = event['driver_id'] as String?;
      if (dId != null) {
        final d = await _client.from('drivers').select('id, name, full_name, business_card_url').eq('id', dId).maybeSingle();
        checks['driver'] = d != null ? {'ok': true, 'name': d['full_name'] ?? d['name'], 'has_card': d['business_card_url'] != null} : {'ok': false};
        debugPrint('  ${d != null ? "[OK]" : "[FAIL]"} Driver: ${d?['full_name'] ?? d?['name'] ?? "NOT FOUND"}');
      }

      // Vehicle
      final vId = event['vehicle_id'] as String?;
      if (vId != null) {
        final v = await _client.from('bus_vehicles').select('id, vehicle_name, total_seats, vehicle_type').eq('id', vId).maybeSingle();
        checks['vehicle'] = v != null ? {'ok': true, 'name': v['vehicle_name'], 'seats': v['total_seats']} : {'ok': false};
        debugPrint('  ${v != null ? "[OK]" : "[FAIL]"} Vehicle: ${v?['vehicle_name'] ?? "NOT FOUND"} (${v?['total_seats']} seats)');
      }

      // Itinerary
      final itin = await _client.from('tourism_event_itinerary').select('id').eq('event_id', eventId);
      checks['itinerary'] = {'ok': true, 'stops': (itin as List).length};
      debugPrint('  [OK] Itinerary: ${itin.length} stops');

      // Invitations
      final inv = await _client.from('tourism_invitations').select('id, status').eq('event_id', eventId);
      final invList = List<Map<String, dynamic>>.from(inv);
      final accepted = invList.where((i) => i['status'] == 'accepted').length;
      checks['invitations'] = {'ok': true, 'total': invList.length, 'accepted': accepted};
      debugPrint('  [OK] Invitations: ${invList.length} total, $accepted accepted');

      // Messages
      final msgs = await _client.from('tourism_messages').select('id').eq('event_id', eventId);
      checks['messages'] = {'ok': true, 'count': (msgs as List).length};
      debugPrint('  [OK] Messages: ${msgs.length}');

      // Vehicle bids
      final bids = await _client.from('tourism_vehicle_bids').select('id').eq('event_id', eventId);
      checks['bids'] = {'ok': true, 'count': (bids as List).length};
      debugPrint('  [OK] Bids: ${bids.length}');

      // Trip records
      final trips = await _client.from('tourism_trip_records').select('id').eq('event_id', eventId);
      checks['trip_records'] = {'ok': true, 'count': (trips as List).length};
      debugPrint('  [OK] Trip records: ${trips.length}');

      debugPrint('── EVENT CHECK COMPLETE ──');
    } catch (e) {
      debugPrint('  [ERROR] $e');
      checks['_error'] = '$e';
    }

    return checks;
  }

  // ===========================================================================
  // DRIVER CREDENTIALS
  // ===========================================================================
  /// Gets all credentials/badges earned by the current driver.
  ///
  /// Returns a list of credential records ordered by earned date descending.
  /// Each record includes credential type, title, description, and earned_at.
  Future<List<Map<String, dynamic>>> getMyCredentials() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];
    try {
      final response = await _client
          .from('tourism_user_credentials')
          .select('*')
          .eq('user_id', userId)
          .order('earned_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('getMyCredentials error: $e');
      return [];
    }
  }

  // ===========================================================================
  // DRIVER BID MANAGEMENT
  // ===========================================================================

  /// Fetches all bids for a specific driver, including event and vehicle info.
  ///
  /// Returns bids across all statuses so the driver can see their full
  /// bidding history: pending, accepted, counter_offered, rejected, selected.
  Future<List<Map<String, dynamic>>> getDriverBids(String driverId) async {
    try {
      final response = await _client
          .from('tourism_vehicle_bids')
          .select('''
            *,
            tourism_events(
              id, event_name, event_type, event_description, event_date, start_time,
              total_distance_km, max_passengers, price_per_km,
              itinerary, status, organizer_id,
              organizers(id, company_name, phone, company_logo_url, is_verified,
                contact_email, contact_phone, contact_facebook)
            ),
            bus_vehicles(id, vehicle_name, vehicle_type, total_seats, image_urls)
          ''')
          .eq('driver_id', driverId)
          .order('created_at', ascending: false);

      final results = <Map<String, dynamic>>[];
      for (final row in response as List) {
        final bid = Map<String, dynamic>.from(row as Map);

        // Flatten event data
        final event = bid.remove('tourism_events') as Map<String, dynamic>?;
        if (event != null) {
          bid['event_id'] = event['id'];
          bid['event_name'] = event['event_name'];
          bid['event_type'] = event['event_type'];
          bid['event_description'] = event['event_description'];
          bid['event_date'] = event['event_date'];
          bid['start_time'] = event['start_time'];
          bid['total_distance_km'] = event['total_distance_km'];
          bid['max_passengers'] = event['max_passengers'];
          bid['event_price_per_km'] = event['price_per_km'];
          bid['itinerary'] = event['itinerary'];
          bid['event_status'] = event['status'];

          // Flatten organizer
          final org = event['organizers'] as Map<String, dynamic>?;
          if (org != null) {
            bid['organizer_name'] = org['company_name'];
            bid['organizer_phone'] = org['phone'];
            bid['organizer_logo'] = org['company_logo_url'];
            bid['organizer_verified'] = org['is_verified'];
            bid['organizer_email'] = org['contact_email'];
            bid['organizer_contact_phone'] = org['contact_phone'];
            bid['organizer_facebook'] = org['contact_facebook'];
          }
        }

        // Flatten vehicle data
        final vehicle = bid.remove('bus_vehicles') as Map<String, dynamic>?;
        if (vehicle != null) {
          bid['vehicle_name'] = vehicle['vehicle_name'];
          bid['vehicle_type'] = vehicle['vehicle_type'];
          bid['total_seats'] = vehicle['total_seats'];
          bid['vehicle_image_urls'] = vehicle['image_urls'];
        }

        results.add(bid);
      }

      return results;
    } catch (e) {
      debugPrint('getDriverBids error: $e');
      return [];
    }
  }

  /// Gets the count of active (actionable) bids for a driver.
  ///
  /// Active means: driver_status == 'pending' OR organizer_status == 'counter_offered'
  /// Used for badge counts in navigation.
  Future<int> getActiveDriverBidCount(String driverId) async {
    try {
      final response = await _client
          .from('tourism_vehicle_bids')
          .select('id')
          .eq('driver_id', driverId)
          .or('driver_status.eq.pending,organizer_status.eq.counter_offered');

      return (response as List).length;
    } catch (e) {
      return 0;
    }
  }

  /// Count pending bids received on the organizer's events.
  /// Used for badge/banner in organizer home.
  Future<int> getOrganizerPendingBidCount(String organizerId) async {
    try {
      // Get all event IDs for this organizer
      final events = await _client
          .from('tourism_events')
          .select('id')
          .eq('organizer_id', organizerId)
          .inFilter('status', ['draft', 'pending_vehicle']);

      final eventIds = (events as List).map((e) => e['id'] as String).toList();
      if (eventIds.isEmpty) return 0;

      // Count bids where driver accepted but organizer hasn't decided
      final bids = await _client
          .from('tourism_vehicle_bids')
          .select('id')
          .inFilter('event_id', eventIds)
          .eq('driver_status', 'accepted')
          .eq('organizer_status', 'pending');

      return (bids as List).length;
    } catch (e) {
      debugPrint('getOrganizerPendingBidCount error: $e');
      return 0;
    }
  }

  /// Subscribes to real-time bid updates for a driver.
  ///
  /// Fires on any change to bids where the driver is involved.
  RealtimeChannel subscribeToDriverBids({
    required String driverId,
    required void Function(Map<String, dynamic> bid) onBidUpdate,
  }) {
    final channel = _client.channel('driver_bids_$driverId');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'tourism_vehicle_bids',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'driver_id',
        value: driverId,
      ),
      callback: (payload) {
        final newRecord = payload.newRecord;
        if (newRecord.isNotEmpty) {
          onBidUpdate(newRecord);
        }
      },
    ).subscribe();

    return channel;
  }
}