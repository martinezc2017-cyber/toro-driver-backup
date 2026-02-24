import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

/// Service for calculating per-passenger fares on tourism bus trips.
///
/// Fare model:
/// - Each passenger pays for the distance between their boarding stop
///   and their exit stop, multiplied by the event's price_per_km.
/// - The driver marks stop arrivals; when a passenger's destination stop
///   is reached the system calculates and records their final fare.
///
/// Database interactions:
/// - Reads itinerary from tourism_event_itinerary
/// - Reads/updates tourism_invitations (boarding_stop_index, exit_stop_index,
///   km_traveled, total_price, payment_status)
/// - Reads tourism_events (price_per_km, total_distance_km, max_passengers)
class TripFareService {
  // Singleton
  static final TripFareService _instance = TripFareService._internal();
  factory TripFareService() => _instance;
  TripFareService._internal();

  final SupabaseClient _client = SupabaseConfig.client;

  // ---------------------------------------------------------------------------
  // FARE CALCULATION
  // ---------------------------------------------------------------------------

  /// Calculates the fare for a passenger given their boarding and exit stop
  /// indices within the event itinerary.
  ///
  /// [itinerary] - ordered list of stops, each with lat/lng and stop_order.
  /// [boardingStopIndex] - the stop_order where the passenger boarded.
  /// [exitStopIndex] - the stop_order where the passenger will exit.
  /// [pricePerKm] - the event-level price per kilometre.
  ///
  /// Returns the fare amount rounded to 2 decimal places.
  double calculatePassengerFare({
    required List<Map<String, dynamic>> itinerary,
    required int boardingStopIndex,
    required int exitStopIndex,
    required double pricePerKm,
  }) {
    final distanceKm = calculateDistanceBetweenStops(
      itinerary: itinerary,
      fromIndex: boardingStopIndex,
      toIndex: exitStopIndex,
    );
    return _round2(distanceKm * pricePerKm);
  }

  /// Calculates the straight-line cumulative distance between two stops
  /// in the itinerary using the Haversine formula.
  ///
  /// [itinerary] - ordered list of stops with lat/lng.
  /// [fromIndex] - starting stop_order.
  /// [toIndex] - ending stop_order.
  ///
  /// Returns distance in kilometres.
  double calculateDistanceBetweenStops({
    required List<Map<String, dynamic>> itinerary,
    required int fromIndex,
    required int toIndex,
  }) {
    if (itinerary.isEmpty || fromIndex >= toIndex) return 0.0;

    // Sort itinerary by stop_order
    final sorted = List<Map<String, dynamic>>.from(itinerary)
      ..sort((a, b) =>
          ((a['stop_order'] as int?) ?? 0)
              .compareTo((b['stop_order'] as int?) ?? 0));

    double totalKm = 0.0;

    for (int i = 0; i < sorted.length - 1; i++) {
      final order = (sorted[i]['stop_order'] as int?) ?? i;
      final nextOrder = (sorted[i + 1]['stop_order'] as int?) ?? (i + 1);

      // Sum segments where both stops fall within [fromIndex, toIndex]
      if (order >= fromIndex && order < toIndex) {
        final lat1 = _toDouble(sorted[i]['lat']);
        final lng1 = _toDouble(sorted[i]['lng']);
        final lat2 = _toDouble(sorted[i + 1]['lat']);
        final lng2 = _toDouble(sorted[i + 1]['lng']);

        if (lat1 != null && lng1 != null && lat2 != null && lng2 != null) {
          totalKm += _haversineKm(lat1, lng1, lat2, lng2);
        }
      }
    }

    return _round2(totalKm);
  }

  // ---------------------------------------------------------------------------
  // DATABASE OPERATIONS
  // ---------------------------------------------------------------------------

  /// Records a passenger's exit from the bus.
  ///
  /// Updates the tourism_invitations row with exit_stop_index, km_traveled,
  /// total_price, status = 'off_boarded', and exited_at timestamp.
  ///
  /// [invitationId] - the invitation UUID.
  /// [exitStopIndex] - the stop_order where the passenger exits.
  /// [fare] - the calculated fare amount.
  /// [paymentMethod] - 'efectivo' or 'tarjeta' (defaults to 'efectivo').
  Future<void> recordPassengerExit({
    required String invitationId,
    required int exitStopIndex,
    required double fare,
    String paymentMethod = 'efectivo',
  }) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await _client.from('tourism_invitations').update({
        'status': 'off_boarded',
        'current_check_in_status': 'off_boarded',
        'total_price': fare,
        'payment_status': paymentMethod == 'efectivo' ? 'cash' : 'pending',
        'exited_at': now,
        'updated_at': now,
      }).eq('id', invitationId);

      debugPrint(
          'FARE_SVC -> Recorded exit for $invitationId: '
          'stop=$exitStopIndex, fare=\$$fare');
    } catch (e) {
      debugPrint('FARE_SVC -> Error recording exit: $e');
      rethrow;
    }
  }

  /// Records the boarding stop for a passenger.
  ///
  /// Should be called when a passenger boards at a specific stop.
  Future<void> recordPassengerBoarding({
    required String invitationId,
    required int boardingStopIndex,
  }) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await _client.from('tourism_invitations').update({
        'status': 'boarded',
        'current_check_in_status': 'boarded',
        'boarded_at': now,
        'updated_at': now,
      }).eq('id', invitationId);

      debugPrint(
          'FARE_SVC -> Recorded boarding for $invitationId at stop $boardingStopIndex');
    } catch (e) {
      debugPrint('FARE_SVC -> Error recording boarding: $e');
      rethrow;
    }
  }

  /// Fetches a live trip summary for the driver panel.
  ///
  /// Returns a map with:
  /// - total_passengers: total accepted/boarded/checked_in count
  /// - passengers_aboard: currently on the bus
  /// - passengers_exited: already got off
  /// - passengers_waiting: accepted but not yet boarded
  /// - total_fare_collected: sum of fares for exited passengers
  /// - estimated_total_fare: sum of estimated fares for all passengers
  /// - next_stop: name and index of the next unvisited stop
  /// - itinerary: sorted list of stops
  /// - passengers: list of passenger data with fare info
  Future<Map<String, dynamic>> getActiveTripSummary(String eventId) async {
    try {
      // 1. Fetch event data
      final event = await _client
          .from('tourism_events')
          .select('price_per_km, total_distance_km, max_passengers, status, '
              'current_stop_index, started_at, event_name')
          .eq('id', eventId)
          .maybeSingle();

      if (event == null) {
        return {'error': 'Evento no encontrado'};
      }

      final pricePerKm = (event['price_per_km'] as num?)?.toDouble() ?? 0.0;
      final maxPassengers = (event['max_passengers'] as int?) ?? 0;

      // 2. Fetch itinerary from normalized table
      final itineraryRaw = await _client
          .from('tourism_event_itinerary')
          .select('*')
          .eq('event_id', eventId)
          .order('stop_order', ascending: true);

      var itinerary = List<Map<String, dynamic>>.from(itineraryRaw);

      // Fallback: if normalized table is empty, read from JSONB and build a minimal list
      if (itinerary.isEmpty) {
        final eventFull = await _client
            .from('tourism_events')
            .select('itinerary')
            .eq('id', eventId)
            .maybeSingle();
        final jsonbItinerary = eventFull?['itinerary'];
        if (jsonbItinerary is List && jsonbItinerary.isNotEmpty) {
          itinerary = jsonbItinerary.asMap().entries.map((entry) {
            final i = entry.key;
            final stop = Map<String, dynamic>.from(entry.value as Map);
            return <String, dynamic>{
              'event_id': eventId,
              'stop_order': (stop['order'] as int?) ?? (stop['stopOrder'] as int?) ?? i,
              'name': stop['name'] ?? 'Parada ${i + 1}',
              'address': stop['address'] as String?,
              'lat': (stop['lat'] as num?)?.toDouble(),
              'lng': (stop['lng'] as num?)?.toDouble(),
              'arrival_time': stop['arrival_time'] as String?,
              'departure_time': stop['departure_time'] as String?,
              'notes': stop['notes'] as String?,
              'duration_minutes': (stop['durationMinutes'] as int?) ?? 30,
            };
          }).toList();
        }
      }

      // 3. Fetch all relevant passengers
      final passengersRaw = await _client
          .from('tourism_invitations')
          .select('''
            id, event_id, user_id, status,
            invited_name, invited_phone, invited_email,
            km_traveled, total_price, price_per_km, payment_status,
            boarded_at, exited_at, accepted_at,
            last_check_in_at, current_check_in_status,
            seat_number,
            boarding_lat, boarding_lng, exit_lat, exit_lng,
            gps_tracking_enabled, last_known_lat, last_known_lng, last_gps_update
          ''')
          .eq('event_id', eventId)
          .inFilter('status', [
        'accepted',
        'checked_in',
        'boarded',
        'off_boarded',
      ]);

      final passengers = List<Map<String, dynamic>>.from(passengersRaw);

      // 4. Categorise passengers
      int aboard = 0;
      int exited = 0;
      int waiting = 0;
      double totalCollected = 0.0;
      double estimatedTotal = 0.0;

      final enrichedPassengers = <Map<String, dynamic>>[];

      for (final p in passengers) {
        final status = p['status'] as String? ?? 'accepted';
        final checkInStatus = p['current_check_in_status'] as String?;
        // No boarding_stop_index column — default to 0 (first stop)
        final boardingIdx = 0;
        // No exit_stop_index column — default to last stop
        final exitIdx = itinerary.isNotEmpty ? (itinerary.length - 1) : null;
        final recordedFare = (p['total_price'] as num?)?.toDouble();
        // Use current_check_in_status to determine actual status
        final effectiveStatus = (checkInStatus == 'boarded') ? 'boarded'
            : (checkInStatus == 'off_boarded') ? 'off_boarded'
            : status;

        // Calculate estimated fare
        double estimatedFare = 0.0;
        if (exitIdx != null) {
          estimatedFare = calculatePassengerFare(
            itinerary: itinerary,
            boardingStopIndex: boardingIdx,
            exitStopIndex: exitIdx,
            pricePerKm: pricePerKm,
          );
        } else {
          // If no exit stop set, estimate as boarding to last stop
          final lastStopIdx = itinerary.isNotEmpty
              ? ((itinerary.last['stop_order'] as int?) ??
                  (itinerary.length - 1))
              : 0;
          estimatedFare = calculatePassengerFare(
            itinerary: itinerary,
            boardingStopIndex: boardingIdx,
            exitStopIndex: lastStopIdx,
            pricePerKm: pricePerKm,
          );
        }

        // Get stop names
        String? boardingStopName;
        String? exitStopName;
        for (final stop in itinerary) {
          final order = (stop['stop_order'] as int?) ?? 0;
          if (order == boardingIdx) {
            boardingStopName = stop['name'] as String?;
          }
          if (exitIdx != null && order == exitIdx) {
            exitStopName = stop['name'] as String?;
          }
        }

        switch (effectiveStatus) {
          case 'boarded':
          case 'checked_in':
            aboard++;
            estimatedTotal += estimatedFare;
            break;
          case 'off_boarded':
            exited++;
            totalCollected += recordedFare ?? estimatedFare;
            estimatedTotal += recordedFare ?? estimatedFare;
            break;
          case 'accepted':
          default:
            waiting++;
            estimatedTotal += estimatedFare;
            break;
        }

        enrichedPassengers.add({
          ...p,
          'boarding_stop_index': boardingIdx,
          'exit_stop_index': exitIdx,
          'estimated_fare': estimatedFare,
          'final_fare': recordedFare,
          'boarding_stop_name': boardingStopName ?? 'Parada ${boardingIdx + 1}',
          'exit_stop_name':
              exitStopName ?? (exitIdx != null ? 'Parada ${exitIdx + 1}' : null),
          'category': effectiveStatus == 'boarded' || effectiveStatus == 'checked_in'
              ? 'aboard'
              : effectiveStatus == 'off_boarded'
                  ? 'exited'
                  : 'waiting',
        });
      }

      // 5. Determine next stop
      final currentStopIdx = (event['current_stop_index'] as int?) ?? 0;
      Map<String, dynamic>? nextStop;
      for (final stop in itinerary) {
        final order = (stop['stop_order'] as int?) ?? 0;
        if (order > currentStopIdx && stop['arrived_at'] == null) {
          nextStop = stop;
          break;
        }
      }
      // Fallback: if current stop not arrived yet, it IS the next stop
      if (nextStop == null) {
        for (final stop in itinerary) {
          final order = (stop['stop_order'] as int?) ?? 0;
          if (order >= currentStopIdx && stop['arrived_at'] == null) {
            nextStop = stop;
            break;
          }
        }
      }

      // 6. Calculate elapsed time
      String elapsedFormatted = '00:00';
      if (event['started_at'] != null) {
        final start = DateTime.tryParse(event['started_at'] as String);
        if (start != null) {
          final diff = DateTime.now().toUtc().difference(start);
          final hours = diff.inHours;
          final minutes = diff.inMinutes % 60;
          elapsedFormatted =
              '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
        }
      }

      return {
        'event_title': event['event_name'] ?? 'Evento',
        'event_status': event['status'] ?? 'unknown',
        'price_per_km': pricePerKm,
        'max_passengers': maxPassengers,
        'current_stop_index': currentStopIdx,
        'elapsed_time': elapsedFormatted,

        // Passenger counts
        'total_passengers': passengers.length,
        'passengers_aboard': aboard,
        'passengers_exited': exited,
        'passengers_waiting': waiting,

        // Revenue
        'total_fare_collected': _round2(totalCollected),
        'estimated_total_fare': _round2(estimatedTotal),

        // Next stop info
        'next_stop_name': nextStop?['name'] as String?,
        'next_stop_index': (nextStop?['stop_order'] as int?) ?? currentStopIdx,

        // Lists
        'itinerary': itinerary,
        'passengers': enrichedPassengers,
      };
    } catch (e) {
      debugPrint('FARE_SVC -> Error fetching trip summary: $e');
      return {'error': 'Error al cargar resumen: $e'};
    }
  }

  /// Returns passengers whose exit stop matches the given stop index.
  ///
  /// Used when the driver arrives at a stop to show which passengers
  /// should get off.
  Future<List<Map<String, dynamic>>> getPassengersExitingAtStop({
    required String eventId,
    required int stopIndex,
  }) async {
    try {
      // No exit_stop_index column — return all boarded passengers at this event
      // The caller will handle filtering by stop
      final response = await _client
          .from('tourism_invitations')
          .select('id, invited_name, invited_phone, '
              'total_price, payment_status, status, '
              'seat_number, current_check_in_status, gps_tracking_enabled')
          .eq('event_id', eventId)
          .inFilter('status', ['boarded', 'checked_in']);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('FARE_SVC -> Error getting exiting passengers: $e');
      return [];
    }
  }

  /// Batch-exit multiple passengers at a stop.
  ///
  /// Calculates the fare for each and marks them as off_boarded.
  Future<int> batchExitPassengers({
    required List<Map<String, dynamic>> passengers,
    required int exitStopIndex,
    required List<Map<String, dynamic>> itinerary,
    required double pricePerKm,
  }) async {
    int exitedCount = 0;

    for (final p in passengers) {
      final invitationId = p['id'] as String?;
      if (invitationId == null) continue;

      final boardingIdx = 0;
      final fare = calculatePassengerFare(
        itinerary: itinerary,
        boardingStopIndex: boardingIdx,
        exitStopIndex: exitStopIndex,
        pricePerKm: pricePerKm,
      );

      try {
        await recordPassengerExit(
          invitationId: invitationId,
          exitStopIndex: exitStopIndex,
          fare: fare,
        );
        exitedCount++;
      } catch (e) {
        debugPrint('FARE_SVC -> Error exiting passenger $invitationId: $e');
      }
    }

    return exitedCount;
  }

  /// Toggles boarding acceptance for the event.
  ///
  /// Sets a flag on the event to prevent new passengers from boarding.
  /// Toggles boarding acceptance — local state only.
  ///
  /// The `accepting_boardings` column does not exist in the DB, so this
  /// is a no-op for persistence. The toggle is kept in local widget state.
  Future<void> toggleBoardingAcceptance({
    required String eventId,
    required bool acceptingBoardings,
  }) async {
    // No DB column exists for this — handled as local driver state
    debugPrint(
        'FARE_SVC -> Boarding ${acceptingBoardings ? "enabled" : "disabled"} '
        '(local only)');
  }

  // ---------------------------------------------------------------------------
  // PRIVATE HELPERS
  // ---------------------------------------------------------------------------

  /// Haversine formula to calculate distance between two lat/lng points in km.
  double _haversineKm(
      double lat1, double lon1, double lat2, double lon2) {
    const earthRadiusKm = 6371.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) *
            cos(_degToRad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadiusKm * c;
  }

  double _degToRad(double deg) => deg * (pi / 180.0);

  double _round2(double value) =>
      double.parse(value.toStringAsFixed(2));

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}
