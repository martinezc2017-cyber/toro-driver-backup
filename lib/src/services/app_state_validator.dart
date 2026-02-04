import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/supabase_config.dart';

/// Service that validates and cleans app state on startup
/// - Clears stale state when app version changes
/// - Validates local state against server state
/// - Prevents ghost rides and stuck UI states
class AppStateValidator {
  static const String _lastVersionKey = 'app_last_version';
  static const String _lastBuildKey = 'app_last_build';
  static const String _activeRideIdKey = 'active_ride_id';

  static final AppStateValidator instance = AppStateValidator._();
  AppStateValidator._();

  /// Initialize and validate app state
  /// Call this in main() before running the app
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final packageInfo = await PackageInfo.fromPlatform();

      final currentVersion = packageInfo.version;
      final currentBuild = packageInfo.buildNumber;
      final lastVersion = prefs.getString(_lastVersionKey);
      final lastBuild = prefs.getString(_lastBuildKey);

      debugPrint('STATE_VALIDATOR -> Current: v$currentVersion+$currentBuild, Last: v$lastVersion+$lastBuild');

      // Check if version changed
      if (lastVersion != currentVersion || lastBuild != currentBuild) {
        debugPrint('STATE_VALIDATOR -> Version changed! Clearing stale state...');
        await _clearStaleState(prefs);

        // Save new version
        await prefs.setString(_lastVersionKey, currentVersion);
        await prefs.setString(_lastBuildKey, currentBuild);
      }

      // Always validate server state on startup if logged in
      await _validateServerState(prefs);

    } catch (e) {
      debugPrint('STATE_VALIDATOR -> Error: $e');
      // Don't throw - app should still start
    }
  }

  /// Clear all cached ride/booking state
  Future<void> _clearStaleState(SharedPreferences prefs) async {
    // Clear ride-related keys
    final keysToRemove = <String>[
      _activeRideIdKey,
      'current_ride_id',
      'current_ride_status',
      'pending_ride_id',
      'ride_in_progress',
      'driver_location',
      'last_ride_data',
    ];

    for (final key in keysToRemove) {
      await prefs.remove(key);
    }

    debugPrint('STATE_VALIDATOR -> Cleared ${keysToRemove.length} stale keys');
  }

  /// Validate local state against server
  /// If local says "active ride" but server says "no ride", clear local
  Future<void> _validateServerState(SharedPreferences prefs) async {
    final client = SupabaseConfig.client;
    final user = client.auth.currentUser;

    if (user == null) {
      debugPrint('STATE_VALIDATOR -> Not logged in, skipping server validation');
      return;
    }

    try {
      final driverId = user.id;

      // Check if there's actually an active ride assigned to this driver
      final activeDelivery = await client
          .from('deliveries')
          .select('id, status, pickup_address, destination_address')
          .eq('driver_id', driverId)
          .inFilter('status', ['accepted', 'in_progress', 'arrived', 'picked_up', 'in_transit'])
          .maybeSingle();

      final activeCarpool = await client
          .from('share_ride_bookings')
          .select('id, status, pickup_address, dropoff_address')
          .eq('driver_id', driverId)
          .inFilter('status', ['confirmed', 'in_progress', 'driver_arrived'])
          .maybeSingle();

      final hasActiveRide = activeDelivery != null || activeCarpool != null;

      debugPrint('STATE_VALIDATOR -> Server has active ride for driver: $hasActiveRide');

      if (hasActiveRide) {
        // Show details of active ride
        if (activeDelivery != null) {
          debugPrint('STATE_VALIDATOR -> ACTIVE DELIVERY:');
          debugPrint('  ID: ${activeDelivery['id']}');
          debugPrint('  Status: ${activeDelivery['status']}');
          debugPrint('  Pickup: ${activeDelivery['pickup_address']}');
          debugPrint('  Dropoff: ${activeDelivery['destination_address']}');
        }
        if (activeCarpool != null) {
          debugPrint('STATE_VALIDATOR -> ACTIVE CARPOOL:');
          debugPrint('  ID: ${activeCarpool['id']}');
          debugPrint('  Status: ${activeCarpool['status']}');
          debugPrint('  Pickup: ${activeCarpool['pickup_address']}');
          debugPrint('  Dropoff: ${activeCarpool['dropoff_address']}');
        }

        // Store the active ride ID
        final rideId = activeDelivery?['id'] ?? activeCarpool?['id'];
        if (rideId != null) {
          await prefs.setString(_activeRideIdKey, rideId.toString());
        }
      } else {
        // No active ride in server - clear any local state
        final localActiveRide = prefs.getString(_activeRideIdKey);
        if (localActiveRide != null) {
          debugPrint('STATE_VALIDATOR -> Local has stale ride state ($localActiveRide), clearing...');
          await prefs.remove(_activeRideIdKey);
        }
      }

    } catch (e) {
      debugPrint('STATE_VALIDATOR -> Server validation error: $e');
    }
  }

  /// Force clear all state (for debugging or manual reset)
  Future<void> forceResetState() async {
    final prefs = await SharedPreferences.getInstance();
    await _clearStaleState(prefs);
    await prefs.remove(_lastVersionKey);
    await prefs.remove(_lastBuildKey);
    debugPrint('STATE_VALIDATOR -> Force reset complete');
  }

  /// Get valid active ride ID from server
  Future<Map<String, dynamic>?> getValidActiveRide() async {
    final client = SupabaseConfig.client;
    final user = client.auth.currentUser;
    if (user == null) return null;

    try {
      final driverId = user.id;

      // Check deliveries first
      final activeDelivery = await client
          .from('deliveries')
          .select('id, status, service_type')
          .eq('driver_id', driverId)
          .inFilter('status', ['accepted', 'in_progress', 'arrived', 'picked_up', 'in_transit'])
          .maybeSingle();

      if (activeDelivery != null) {
        return {
          'id': activeDelivery['id'],
          'status': activeDelivery['status'],
          'type': activeDelivery['service_type'] ?? 'ride',
          'table': 'deliveries',
        };
      }

      // Check carpools
      final activeCarpool = await client
          .from('share_ride_bookings')
          .select('id, status')
          .eq('driver_id', driverId)
          .inFilter('status', ['confirmed', 'in_progress', 'driver_arrived'])
          .maybeSingle();

      if (activeCarpool != null) {
        return {
          'id': activeCarpool['id'],
          'status': activeCarpool['status'],
          'type': 'carpool',
          'table': 'share_ride_bookings',
        };
      }

      return null;
    } catch (e) {
      debugPrint('STATE_VALIDATOR -> Error getting active ride: $e');
      return null;
    }
  }
}
