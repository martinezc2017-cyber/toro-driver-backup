import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

/// Service for managing bus tourism routes, stops, passengers, and vehicles.
///
/// All queries run against the Supabase backend using the authenticated client
/// from [SupabaseConfig].
class BusRouteService {
  final SupabaseClient _client = SupabaseConfig.client;

  // ---------------------------------------------------------------------------
  // Routes
  // ---------------------------------------------------------------------------

  /// Returns all bus routes owned by [ownerId], ordered by departure date.
  Future<List<Map<String, dynamic>>> getMyRoutes(String ownerId) async {
    try {
      final response = await _client
          .from('bus_routes')
          .select()
          .eq('owner_id', ownerId)
          .order('departure_date');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  /// Fetches a single route by [routeId] including its related stops.
  ///
  /// Returns `null` when no matching route exists.
  Future<Map<String, dynamic>?> getRouteDetail(String routeId) async {
    try {
      final response = await _client
          .from('bus_routes')
          .select('*, bus_route_stops(*)')
          .eq('id', routeId)
          .maybeSingle();

      return response;
    } catch (e) {
      return null;
    }
  }

  /// Creates a new bus route and returns the inserted row.
  Future<Map<String, dynamic>> createRoute(
      Map<String, dynamic> routeData) async {
    final response = await _client
        .from('bus_routes')
        .insert(routeData)
        .select()
        .single();

    return response;
  }

  /// Applies partial [updates] to the route identified by [routeId].
  Future<void> updateRoute(
      String routeId, Map<String, dynamic> updates) async {
    await _client
        .from('bus_routes')
        .update(updates)
        .eq('id', routeId);
  }

  /// Marks a route as cancelled.
  Future<void> cancelRoute(String routeId) async {
    await _client
        .from('bus_routes')
        .update({'status': 'cancelled'})
        .eq('id', routeId);
  }

  // ---------------------------------------------------------------------------
  // Passengers
  // ---------------------------------------------------------------------------

  /// Returns all non-cancelled seat reservations for a given [routeId].
  Future<List<Map<String, dynamic>>> getRoutePassengers(
      String routeId) async {
    try {
      final response = await _client
          .from('bus_seat_reservations')
          .select()
          .eq('route_id', routeId)
          .neq('status', 'cancelled')
          .order('created_at');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Stops
  // ---------------------------------------------------------------------------

  /// Bulk-inserts a list of stops for the given [routeId].
  ///
  /// Each entry in [stops] should already contain the necessary fields
  /// (e.g. `name`, `lat`, `lng`, `stop_order`). The [routeId] is automatically
  /// injected into every record before insertion.
  Future<void> addStops(
      String routeId, List<Map<String, dynamic>> stops) async {
    final rows = stops.map((stop) {
      return {
        ...stop,
        'route_id': routeId,
      };
    }).toList();

    await _client.from('bus_route_stops').insert(rows);
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  /// Searches for published bus routes with optional filters.
  ///
  /// - [stateCode]: filters by state (e.g. `'AZ'`).
  /// - [countryCode]: filters by country (e.g. `'US'`, `'MX'`).
  /// - [fromDate]: only returns routes departing on or after this date.
  Future<List<Map<String, dynamic>>> searchPublishedRoutes({
    String? stateCode,
    String? countryCode,
    DateTime? fromDate,
  }) async {
    try {
      var query = _client
          .from('bus_routes')
          .select()
          .eq('status', 'published');

      if (stateCode != null) {
        query = query.eq('state_code', stateCode);
      }
      if (countryCode != null) {
        query = query.eq('country_code', countryCode);
      }
      if (fromDate != null) {
        query = query.gte('departure_date', fromDate.toIso8601String());
      }

      final response = await query.order('departure_date');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Vehicles
  // ---------------------------------------------------------------------------

  /// Returns all bus vehicles registered under [ownerId].
  Future<List<Map<String, dynamic>>> getMyVehicles(String ownerId) async {
    try {
      final response = await _client
          .from('bus_vehicles')
          .select()
          .eq('owner_id', ownerId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  /// Registers a new bus vehicle and returns the inserted row.
  Future<Map<String, dynamic>> registerVehicle(
      Map<String, dynamic> vehicleData) async {
    final response = await _client
        .from('bus_vehicles')
        .insert(vehicleData)
        .select()
        .single();

    return response;
  }
}
