import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../core/logging/app_logger.dart';

/// Service for organizer-specific operations in the bus tourism feature.
///
/// Organizers can browse available vehicles, submit transport requests,
/// track their earnings from seat reservations, and contact bus owners.
class OrganizerService {
  final SupabaseClient _client = SupabaseConfig.client;

  /// Send a DB notification to a user
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

  // ---------------------------------------------------------------------------
  // Profile
  // ---------------------------------------------------------------------------

  /// Fetches the organizer profile for the given [userId].
  ///
  /// Returns `null` when no organizer record exists.
  Future<Map<String, dynamic>?> getOrganizerProfile(String userId) async {
    try {
      final response = await _client
          .from('organizers')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      return response;
    } catch (e) {
      return null;
    }
  }

  /// Creates a new organizer profile and returns the inserted row.
  Future<Map<String, dynamic>> createOrganizerProfile(
      Map<String, dynamic> data) async {
    final response = await _client
        .from('organizers')
        .insert(data)
        .select()
        .single();

    return response;
  }

  /// Updates an existing organizer profile.
  /// Fields that can be updated:
  /// - company_name, phone, email, website, description
  /// - company_logo_url, social_media (JSON)
  Future<Map<String, dynamic>?> updateOrganizerProfile(
    String organizerId,
    Map<String, dynamic> updates,
  ) async {
    try {
      // Add updated_at timestamp
      updates['updated_at'] = DateTime.now().toUtc().toIso8601String();

      final response = await _client
          .from('organizers')
          .update(updates)
          .eq('id', organizerId)
          .select()
          .single();

      return response;
    } catch (e) {
      debugPrint('ORGANIZER_SVC -> updateOrganizerProfile ERROR: $e');
      debugPrint('ORGANIZER_SVC -> organizerId: $organizerId');
      debugPrint('ORGANIZER_SVC -> updates: $updates');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Agreement / Contract
  // ---------------------------------------------------------------------------

  /// Check if organizer has signed the platform agreement.
  ///
  /// Checks organizers.agreement_signed first (fast path).
  /// Falls back to legal_consents table if column doesn't exist yet.
  Future<bool> hasSignedAgreement(String organizerId) async {
    // 1. Try organizers table column (fast path)
    try {
      final response = await _client
          .from('organizers')
          .select('agreement_signed')
          .eq('id', organizerId)
          .maybeSingle();
      if (response?['agreement_signed'] == true) return true;
    } catch (e) {
      debugPrint('ORGANIZER_SVC -> hasSignedAgreement column check: $e');
    }

    // 2. Fallback: check legal_consents table
    try {
      // Get the user_id for this organizer
      final org = await _client
          .from('organizers')
          .select('user_id')
          .eq('id', organizerId)
          .maybeSingle();
      final userId = org?['user_id'] as String?;
      if (userId == null) return false;

      final consent = await _client
          .from('legal_consents')
          .select('id')
          .eq('user_id', userId)
          .eq('document_type', 'organizer_platform_agreement')
          .limit(1)
          .maybeSingle();
      return consent != null;
    } catch (e) {
      debugPrint('ORGANIZER_SVC -> hasSignedAgreement fallback: $e');
      return false;
    }
  }

  /// Save agreement signature and audit data to organizers table.
  ///
  /// Does NOT rethrow - the caller also saves to legal_consents as backup.
  Future<void> saveAgreementSignature(
    String organizerId,
    Map<String, dynamic> auditData,
  ) async {
    try {
      auditData['updated_at'] = DateTime.now().toUtc().toIso8601String();
      await _client
          .from('organizers')
          .update(auditData)
          .eq('id', organizerId);
    } catch (e) {
      debugPrint('ORGANIZER_SVC -> saveAgreementSignature ERROR: $e');
      // Don't rethrow - legal_consents is the real audit trail
    }
  }

  // ---------------------------------------------------------------------------
  // Storage
  // ---------------------------------------------------------------------------

  /// Uploads a company logo to Supabase storage and returns the public URL.
  Future<String?> uploadCompanyLogo(String organizerId, String filePath, {Uint8List? bytes}) async {
    try {
      AppLogger.log('LOGO_UPLOAD -> Starting upload for organizer: $organizerId');
      AppLogger.log('LOGO_UPLOAD -> File path: $filePath');

      // Prefer pre-read bytes (works on web), fallback to file read (mobile)
      final file = bytes ?? await _readFileBytes(filePath);
      if (file == null) {
        AppLogger.log('LOGO_UPLOAD -> ERROR: Could not read file bytes');
        throw Exception('No se pudo leer el archivo de imagen');
      }

      AppLogger.log('LOGO_UPLOAD -> File size: ${file.length} bytes');

      final extension = filePath.split('.').last.toLowerCase();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storagePath = 'organizers/$organizerId/logo_$timestamp.$extension';

      // Determine content type
      String contentType = 'image/jpeg';
      if (extension == 'png') {
        contentType = 'image/png';
      } else if (extension == 'webp') {
        contentType = 'image/webp';
      }

      AppLogger.log('LOGO_UPLOAD -> Uploading to: $storagePath ($contentType)');

      await _client.storage.from('organizer-logos').uploadBinary(
            storagePath,
            file,
            fileOptions: FileOptions(
              contentType: contentType,
              upsert: true,
            ),
          );

      AppLogger.log('LOGO_UPLOAD -> Upload successful');

      final publicUrl =
          _client.storage.from('organizer-logos').getPublicUrl(storagePath);

      AppLogger.log('LOGO_UPLOAD -> Public URL: $publicUrl');

      // Update the organizer record with the new logo URL
      await _client
          .from('organizers')
          .update({
            'company_logo_url': publicUrl,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', organizerId);

      AppLogger.log('LOGO_UPLOAD -> Organizer record updated');
      return publicUrl;
    } catch (e) {
      AppLogger.log('LOGO_UPLOAD -> ERROR: $e');
      rethrow;
    }
  }

  /// Upload a business card image for the organizer
  Future<String?> uploadBusinessCard(String organizerId, String filePath, {Uint8List? bytes}) async {
    try {
      final Uint8List fileBytes;
      if (bytes != null) {
        fileBytes = bytes;
      } else {
        final read = await _readFileBytes(filePath);
        if (read == null) throw Exception('No se pudo leer el archivo');
        fileBytes = read;
      }

      final extension = filePath.split('.').last.toLowerCase();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storagePath = 'organizers/$organizerId/business_card_$timestamp.$extension';

      String contentType = 'image/jpeg';
      if (extension == 'png') contentType = 'image/png';
      else if (extension == 'webp') contentType = 'image/webp';

      await _client.storage.from('organizer-logos').uploadBinary(
        storagePath,
        fileBytes,
        fileOptions: FileOptions(contentType: contentType, upsert: true),
      );

      final publicUrl = _client.storage.from('organizer-logos').getPublicUrl(storagePath);

      await _client.from('organizers').update({
        'business_card_url': publicUrl,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', organizerId);

      return publicUrl;
    } catch (e) {
      debugPrint('BUSINESS_CARD_UPLOAD -> ERROR: $e');
      rethrow;
    }
  }

  Future<Uint8List?> _readFileBytes(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        return await file.readAsBytes();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Earnings
  // ---------------------------------------------------------------------------

  /// Calculates organizer earnings from confirmed seat reservations.
  ///
  /// Optionally filters by a date range ([from] .. [to]).
  ///
  /// Returns a map with:
  /// - `total_commission` -- sum of all organizer commissions.
  /// - `total_reservations` -- number of confirmed reservations.
  /// - `reservations` -- full list of matching reservation rows.
  Future<Map<String, dynamic>> getEarnings(
    String organizerId, {
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      var query = _client
          .from('bus_seat_reservations')
          .select()
          .eq('organizer_id', organizerId)
          .eq('status', 'confirmed');

      if (from != null) {
        query = query.gte('created_at', from.toIso8601String());
      }
      if (to != null) {
        query = query.lte('created_at', to.toIso8601String());
      }

      final response =
          await query.order('created_at', ascending: false);

      final reservations = List<Map<String, dynamic>>.from(response);

      double totalCommission = 0;
      for (final r in reservations) {
        totalCommission +=
            (r['organizer_commission'] as num?)?.toDouble() ?? 0;
      }

      return {
        'total_commission': totalCommission,
        'total_reservations': reservations.length,
        'reservations': reservations,
      };
    } catch (e) {
      return {
        'total_commission': 0.0,
        'total_reservations': 0,
        'reservations': <Map<String, dynamic>>[],
      };
    }
  }

  // ---------------------------------------------------------------------------
  // Browse vehicles
  // ---------------------------------------------------------------------------

  /// Searches for active bus vehicles, optionally filtering by [state] and/or
  /// [countryCode].
  ///
  /// Each result includes the vehicle data joined with the owner driver's
  /// name, phone, and current location.
  Future<List<Map<String, dynamic>>> browseVehicles({
    String? state,
    String? countryCode,
  }) async {
    try {
      var query = _client
          .from('bus_vehicles')
          .select(
              '*, drivers!bus_vehicles_owner_id_fkey(id, user_id, name, phone, current_lat, current_lng)')
          .eq('is_active', true);

      if (state != null) {
        query = query.eq('state', state);
      }
      if (countryCode != null) {
        query = query.eq('country_code', countryCode);
      }

      final response = await query.order('created_at', ascending: false);

      // Flatten the joined driver data into each vehicle record.
      final results = <Map<String, dynamic>>[];
      for (final row in response as List) {
        final vehicle = Map<String, dynamic>.from(row as Map);
        final driver = vehicle.remove('drivers') as Map<String, dynamic>?;
        if (driver != null) {
          // Driver info (person who will operate the bus)
          vehicle['driver_name'] = driver['name'] ?? 'Sin nombre';
          vehicle['driver_phone'] = driver['phone'] ?? '';
          vehicle['driver_phone_hidden'] = false; // No privacy setting without profiles
          vehicle['driver_email'] = ''; // Not available without profile join

          // GPS coordinates from driver
          vehicle['current_lat'] = driver['current_lat'];
          vehicle['current_lng'] = driver['current_lng'];

          // Store driver_id and user_id for reference
          vehicle['driver_id'] = driver['id'];
          vehicle['driver_user_id'] = driver['user_id'];

          // Note: owner_name, owner_phone, codriver_name, codriver_phone come from bus_vehicles table directly
        }
        results.add(vehicle);
      }

      return results;
    } catch (e) {
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Transport requests
  // ---------------------------------------------------------------------------

  /// Returns all open transport requests, optionally filtered by [state].
  Future<List<Map<String, dynamic>>> getOpenRequests({String? state}) async {
    try {
      var query = _client
          .from('bus_transport_requests')
          .select()
          .eq('status', 'open');

      if (state != null) {
        query = query.eq('state', state);
      }

      final response =
          await query.order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  /// Submits a new transport request and returns the inserted row.
  Future<Map<String, dynamic>> submitTransportRequest(
      Map<String, dynamic> data) async {
    final response = await _client
        .from('bus_transport_requests')
        .insert(data)
        .select()
        .single();

    return response;
  }

  // ---------------------------------------------------------------------------
  // Contact bus owner
  // ---------------------------------------------------------------------------

  /// Creates a notification record so the bus owner receives an in-app message
  /// from the organizer.
  Future<void> contactBusOwner(
    String ownerId,
    String organizerId,
    String message,
  ) async {
    await _client.from(SupabaseConfig.notificationsTable).insert({
      'user_id': ownerId,
      'title': 'New message from organizer',
      'body': message,
      'type': 'organizer_contact',
      'data': {
        'organizer_id': organizerId,
      },
      'read': false,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // ---------------------------------------------------------------------------
  // Real-time bus locations
  // ---------------------------------------------------------------------------

  /// Fetches all active bus driver locations for display on a map.
  ///
  /// Returns a list of location records with driver info.
  Future<List<Map<String, dynamic>>> getActiveBusLocations() async {
    try {
      final response = await _client
          .from('bus_driver_location')
          .select('*, drivers!bus_driver_location_driver_id_fkey(id, name, phone)')
          .order('updated_at', ascending: false);

      final results = <Map<String, dynamic>>[];
      for (final row in response as List) {
        final location = Map<String, dynamic>.from(row as Map);
        final driver = location.remove('drivers') as Map<String, dynamic>?;
        if (driver != null) {
          location['driver_name'] = driver['name'];
          location['driver_phone'] = driver['phone'];
        }
        results.add(location);
      }

      return results;
    } catch (e) {
      return [];
    }
  }

  /// Fetches bus locations for a specific route.
  Future<List<Map<String, dynamic>>> getBusLocationsForRoute(String routeId) async {
    try {
      final response = await _client
          .from('bus_driver_location')
          .select('*, drivers!bus_driver_location_driver_id_fkey(id, name, phone)')
          .eq('route_id', routeId)
          .order('updated_at', ascending: false);

      final results = <Map<String, dynamic>>[];
      for (final row in response as List) {
        final location = Map<String, dynamic>.from(row as Map);
        final driver = location.remove('drivers') as Map<String, dynamic>?;
        if (driver != null) {
          location['driver_name'] = driver['name'];
          location['driver_phone'] = driver['phone'];
        }
        results.add(location);
      }

      return results;
    } catch (e) {
      return [];
    }
  }

  /// Subscribes to real-time bus location updates.
  ///
  /// Returns a RealtimeChannel that can be used to unsubscribe.
  RealtimeChannel subscribeToBusLocations({
    required void Function(Map<String, dynamic> location) onLocationUpdate,
    String? routeId,
  }) {
    final channel = _client.channel('bus_locations_realtime');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'bus_driver_location',
      filter: routeId != null
          ? PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'route_id',
              value: routeId,
            )
          : null,
      callback: (payload) {
        final newRecord = payload.newRecord;
        if (newRecord.isNotEmpty) {
          onLocationUpdate(newRecord);
        }
      },
    ).subscribe();

    return channel;
  }

  // ---------------------------------------------------------------------------
  // Bus events
  // ---------------------------------------------------------------------------

  /// Fetches recent bus events, optionally filtered by route.
  Future<List<Map<String, dynamic>>> getBusEvents({
    String? routeId,
    int limit = 50,
  }) async {
    try {
      var query = _client
          .from('bus_events')
          .select('*, drivers!bus_events_driver_id_fkey(id, name)');

      if (routeId != null) {
        query = query.eq('route_id', routeId);
      }

      final response = await query
          .order('created_at', ascending: false)
          .limit(limit);

      final results = <Map<String, dynamic>>[];
      for (final row in response as List) {
        final event = Map<String, dynamic>.from(row as Map);
        final driver = event.remove('drivers') as Map<String, dynamic>?;
        if (driver != null) {
          event['driver_name'] = driver['name'];
        }
        results.add(event);
      }

      return results;
    } catch (e) {
      return [];
    }
  }

  /// Subscribes to real-time bus events.
  RealtimeChannel subscribeToBusEvents({
    required void Function(Map<String, dynamic> event) onEvent,
    String? routeId,
  }) {
    final channel = _client.channel('bus_events_realtime');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'bus_events',
      filter: routeId != null
          ? PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'route_id',
              value: routeId,
            )
          : null,
      callback: (payload) {
        final newRecord = payload.newRecord;
        if (newRecord.isNotEmpty) {
          onEvent(newRecord);
        }
      },
    ).subscribe();

    return channel;
  }

  // ---------------------------------------------------------------------------
  // Bidding system
  // ---------------------------------------------------------------------------

  /// Sends bid requests to multiple drivers for a tourism event.
  ///
  /// Creates entries in `tourism_vehicle_bids` table with status 'pending'.
  /// Looks up the owner (driver) for each vehicle before creating bids.
  Future<void> sendBidRequests(
    String eventId,
    List<String> vehicleIds,
  ) async {
    // Look up owner_id (driver) for each vehicle
    final vehicleData = await _client
        .from('bus_vehicles')
        .select('id, owner_id')
        .inFilter('id', vehicleIds);

    final ownerMap = <String, String>{};
    for (final v in vehicleData as List) {
      final vid = v['id'] as String;
      final oid = v['owner_id'] as String?;
      if (oid != null) ownerMap[vid] = oid;
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final bids = vehicleIds
        .where((vid) => ownerMap.containsKey(vid))
        .map((vehicleId) {
      return {
        'event_id': eventId,
        'vehicle_id': vehicleId,
        'driver_id': ownerMap[vehicleId],
        'driver_status': 'pending',
        'organizer_status': 'pending',
        'is_winning_bid': false,
        'created_at': now,
      };
    }).toList();

    if (bids.isNotEmpty) {
      await _client.from('tourism_vehicle_bids').insert(bids);

      // Notify each driver about the bid request
      try {
        final event = await _client
            .from('tourism_events')
            .select('event_name, total_distance_km, organizer_id')
            .eq('id', eventId)
            .single();
        final eventName = event['event_name'] as String? ?? 'Evento';
        final distKm = (event['total_distance_km'] as num?)?.toDouble() ?? 0;

        // Get organizer name
        final orgId = event['organizer_id'] as String?;
        String orgName = 'Un organizador';
        if (orgId != null) {
          final org = await _client
              .from('organizers')
              .select('company_name')
              .eq('id', orgId)
              .maybeSingle();
          orgName = org?['company_name'] as String? ?? orgName;
        }

        for (final bid in bids) {
          final driverId = bid['driver_id'] as String?;
          if (driverId != null) {
            await _sendDbNotification(
              userId: driverId,
              title: 'Nueva Solicitud de Puja',
              body: '$orgName te invita a pujar en: $eventName (${distKm.toStringAsFixed(0)} km)',
              type: 'bid_request',
              data: {'event_id': eventId},
            );
          }
        }
      } catch (e) {
        debugPrint('Error sending bid request notifications: $e');
      }
    }
  }

  /// Fetches all bids for a specific event, including driver and vehicle info.
  Future<List<Map<String, dynamic>>> getBidsForEvent(String eventId) async {
    try {
      final response = await _client
          .from('tourism_vehicle_bids')
          .select('''
            *,
            vehicle:bus_vehicles!tourism_vehicle_bids_vehicle_id_fkey(
              id, vehicle_name, total_seats, image_urls,
              owner_name, owner_phone
            ),
            driver:drivers!tourism_vehicle_bids_driver_id_fkey(
              id, name, phone, current_lat, current_lng
            )
          ''')
          .eq('event_id', eventId)
          .order('created_at', ascending: false);

      final results = <Map<String, dynamic>>[];
      for (final row in response as List) {
        final bid = Map<String, dynamic>.from(row as Map);

        // Flatten vehicle data
        final vehicle = bid.remove('vehicle') as Map<String, dynamic>?;
        if (vehicle != null) {
          bid['vehicle_id'] = vehicle['id'];
          bid['vehicle_name'] = vehicle['vehicle_name'];
          bid['total_seats'] = vehicle['total_seats'];
          bid['vehicle_image_urls'] = vehicle['image_urls'];
          bid['owner_name'] = vehicle['owner_name'];
          bid['owner_phone'] = vehicle['owner_phone'];
        }

        // Flatten driver data
        final driver = bid.remove('driver') as Map<String, dynamic>?;
        if (driver != null) {
          bid['driver_id'] = driver['id'];
          bid['driver_name'] = driver['name'];
          bid['driver_phone'] = driver['phone'];
        }

        results.add(bid);
      }

      return results;
    } catch (e) {
      return [];
    }
  }

  /// Selects a winning bid for an event.
  ///
  /// Updates the selected bid's organizer_status to 'selected' and
  /// sets is_winning_bid to true. Rejects all other bids.
  Future<void> selectWinningBid(String bidId, String eventId) async {
    // First, reject all other bids for this event
    await _client
        .from('tourism_vehicle_bids')
        .update({
          'organizer_status': 'rejected',
          'responded_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('event_id', eventId)
        .neq('id', bidId);

    // Select the winning bid
    await _client.from('tourism_vehicle_bids').update({
      'organizer_status': 'selected',
      'is_winning_bid': true,
      'responded_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', bidId);

    // Get the winning bid details to update the event
    final winningBid = await _client
        .from('tourism_vehicle_bids')
        .select('vehicle_id, driver_id, proposed_price_per_km')
        .eq('id', bidId)
        .single();

    // Update the tourism event with the selected vehicle, driver, AND synced seats
    final updateData = <String, dynamic>{
      'driver_id': winningBid['driver_id'],
      'price_per_km': winningBid['proposed_price_per_km'],
      'status': 'vehicle_accepted',
      'vehicle_request_status': 'accepted',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    // Get the winning vehicle's seat count to sync max_passengers (if vehicle assigned)
    final bidVehicleId = winningBid['vehicle_id'] as String?;
    if (bidVehicleId != null) {
      updateData['vehicle_id'] = bidVehicleId;
      try {
        final vehicleData = await _client
            .from('bus_vehicles')
            .select('total_seats')
            .eq('id', bidVehicleId)
            .single();
        final vehicleSeats = (vehicleData['total_seats'] as num?)?.toInt();
        if (vehicleSeats != null && vehicleSeats > 0) {
          updateData['max_passengers'] = vehicleSeats;
        }
      } catch (_) {}
    }
    await _client.from('tourism_events').update(updateData).eq('id', eventId);

    // Notify the winning driver
    try {
      final winnerId = winningBid['driver_id'] as String?;
      final event = await _client
          .from('tourism_events')
          .select('event_name')
          .eq('id', eventId)
          .single();
      final eventName = event['event_name'] as String? ?? 'Evento';
      final price = (winningBid['proposed_price_per_km'] as num?)?.toDouble() ?? 0;

      if (winnerId != null) {
        await _sendDbNotification(
          userId: winnerId,
          title: 'Tu Puja Fue Seleccionada!',
          body: 'Ganaste: $eventName a \$${price.toStringAsFixed(2)}/km',
          type: 'bid_won',
          data: {'event_id': eventId, 'bid_id': bidId},
        );
      }

      // Notify rejected drivers
      final rejectedBids = await _client
          .from('tourism_vehicle_bids')
          .select('driver_id')
          .eq('event_id', eventId)
          .neq('id', bidId)
          .eq('organizer_status', 'rejected');
      for (final rb in rejectedBids as List) {
        final rejId = rb['driver_id'] as String?;
        if (rejId != null) {
          await _sendDbNotification(
            userId: rejId,
            title: 'Puja No Seleccionada',
            body: 'El organizador selecciono otra oferta para: $eventName',
            type: 'bid_lost',
            data: {'event_id': eventId},
          );
        }
      }
    } catch (e) {
      debugPrint('Error sending winning bid notifications: $e');
    }
  }

  /// Send a counter-offer to a driver for a bid.
  ///
  /// Sets organizer_status = 'counter_offered' and organizer_proposed_price.
  /// Increments the negotiation_round by reading the current value first.
  Future<void> sendCounterOffer({
    required String bidId,
    required double proposedPrice,
  }) async {
    // Read current negotiation round
    final current = await _client
        .from('tourism_vehicle_bids')
        .select('negotiation_round')
        .eq('id', bidId)
        .single();

    final currentRound = (current['negotiation_round'] as num?)?.toInt() ?? 0;

    await _client.from('tourism_vehicle_bids').update({
      'organizer_status': 'counter_offered',
      'organizer_proposed_price': proposedPrice,
      'negotiation_round': currentRound + 1,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', bidId);

    // Notify the driver about the counter-offer
    try {
      final bid = await _client
          .from('tourism_vehicle_bids')
          .select('driver_id, event_id')
          .eq('id', bidId)
          .single();
      final driverId = bid['driver_id'] as String?;
      final eventId = bid['event_id'] as String?;

      String eventName = 'Evento';
      if (eventId != null) {
        final event = await _client
            .from('tourism_events')
            .select('event_name')
            .eq('id', eventId)
            .maybeSingle();
        eventName = event?['event_name'] as String? ?? eventName;
      }

      if (driverId != null) {
        await _sendDbNotification(
          userId: driverId,
          title: 'Contra-oferta Recibida',
          body: 'El organizador propone \$${proposedPrice.toStringAsFixed(2)}/km para: $eventName',
          type: 'bid_counter_offer',
          data: {'bid_id': bidId, 'event_id': eventId},
        );
      }
    } catch (e) {
      debugPrint('Error sending counter-offer notification: $e');
    }
  }

  /// Accept a driver's counter-offer.
  ///
  /// When a driver sends a counter-offer (driver_status == 'counter_offered'),
  /// the organizer can accept it. This sets organizer_status = 'accepted'
  /// and uses the driver's proposed price as the agreed price.
  Future<void> acceptDriverCounterOffer({
    required String bidId,
    required String eventId,
    required double driverProposedPrice,
  }) async {
    // Update the bid: accept the driver's counter-offer price
    await _client.from('tourism_vehicle_bids').update({
      'organizer_status': 'accepted',
      'proposed_price_per_km': driverProposedPrice,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', bidId);

    // Now select this as the winning bid
    await selectWinningBid(bidId, eventId);
  }

  /// Subscribes to real-time bid updates for an event.
  RealtimeChannel subscribeToBids({
    required String eventId,
    required void Function(Map<String, dynamic> bid) onBidUpdate,
  }) {
    final channel = _client.channel('bids_$eventId');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'tourism_vehicle_bids',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'event_id',
        value: eventId,
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

  // ---------------------------------------------------------------------------
  // Weekly credit system
  // ---------------------------------------------------------------------------

  /// Fetches organizer credit account details.
  Future<Map<String, dynamic>?> getCreditAccount(String organizerId) async {
    try {
      final response = await _client
          .from('organizer_credit_accounts')
          .select()
          .eq('organizer_id', organizerId)
          .maybeSingle();

      return response;
    } catch (e) {
      return null;
    }
  }

  /// Fetches weekly statements for an organizer.
  Future<List<Map<String, dynamic>>> getWeeklyStatements(
    String organizerId, {
    String? status,
  }) async {
    try {
      var query = _client
          .from('organizer_weekly_statements')
          .select()
          .eq('organizer_id', organizerId);

      if (status != null) {
        query = query.eq('payment_status', status);
      }

      final response = await query.order('week_start_date', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Week reset requests
  // ---------------------------------------------------------------------------

  /// Submits a request to admin to clear the organizer's weekly debt.
  ///
  /// Creates a record in `week_reset_requests` so admin can verify
  /// and approve the reset.
  Future<Map<String, dynamic>> submitWeekResetRequest({
    required String requesterId,
    required String requesterType,
    String? organizerId,
    String? statementId,
    required double amountOwed,
    String? message,
  }) async {
    final response = await _client.from('week_reset_requests').insert({
      'requester_id': requesterId,
      'requester_type': requesterType,
      'organizer_id': organizerId,
      'statement_id': statementId,
      'amount_owed': amountOwed,
      'message': message,
      'status': 'pending',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }).select().single();

    return response;
  }

  /// Fetches pending reset requests for this organizer.
  Future<List<Map<String, dynamic>>> getMyResetRequests(
      String requesterId) async {
    try {
      final response = await _client
          .from('week_reset_requests')
          .select()
          .eq('requester_id', requesterId)
          .order('created_at', ascending: false)
          .limit(10);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  /// Fetches current week's events and calculates totals.
  Future<Map<String, dynamic>> getCurrentWeekSummary(
      String organizerId) async {
    try {
      // Get current week range (Sunday to Saturday)
      final now = DateTime.now();
      final weekStart = now.subtract(Duration(days: now.weekday % 7));
      final weekEnd = weekStart.add(const Duration(days: 6));

      // Query events for current week
      final events = await _client
          .from('tourism_events')
          .select()
          .eq('organizer_id', organizerId)
          .gte('created_at', weekStart.toIso8601String())
          .lte('created_at', weekEnd.toIso8601String())
          .order('created_at', ascending: false);

      // Calculate totals
      double totalKm = 0;
      double totalDriverCost = 0;
      double toroCommission = 0;
      int eventCount = 0;

      for (final event in events) {
        final km = (event['total_distance_km'] as num?)?.toDouble() ?? 0;
        final pricePerKm = (event['price_per_km'] as num?)?.toDouble() ?? 0;
        final cost = km * pricePerKm;
        final commission = cost * 0.18;

        totalKm += km;
        totalDriverCost += cost;
        toroCommission += commission;
        eventCount++;
      }

      return {
        'week_start': weekStart.toIso8601String(),
        'week_end': weekEnd.toIso8601String(),
        'event_count': eventCount,
        'total_km': totalKm,
        'total_driver_cost': totalDriverCost,
        'toro_commission': toroCommission,
        'events': events,
      };
    } catch (e) {
      return {
        'week_start': DateTime.now().toIso8601String(),
        'week_end': DateTime.now().toIso8601String(),
        'event_count': 0,
        'total_km': 0.0,
        'total_driver_cost': 0.0,
        'toro_commission': 0.0,
        'events': [],
      };
    }
  }
}
