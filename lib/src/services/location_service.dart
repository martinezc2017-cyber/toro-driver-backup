import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../config/app_config.dart';

class LocationService {
  final SupabaseClient _client = SupabaseConfig.client;

  StreamSubscription<Position>? _positionSubscription;
  Position? _currentPosition;
  final _positionController = StreamController<Position>.broadcast();

  Position? get currentPosition => _currentPosition;
  Stream<Position> get positionStream => _positionController.stream;

  // Check and request location permissions
  Future<bool> checkAndRequestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  // Get current position - ALWAYS fresh GPS, never cached
  Future<Position?> getCurrentPosition() async {
    final hasPermission = await checkAndRequestPermission();
    if (!hasPermission) return null;

    try {
      // Forzar GPS fresco - NO usar posiciones cacheadas
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 10),
      );
      debugPrint('LocationService: Fresh GPS - lat: ${_currentPosition?.latitude}, lng: ${_currentPosition?.longitude}');
    } catch (e) {
      debugPrint('LocationService: GPS error: $e - trying alternative...');
      try {
        // Segundo intento con precisión alta
        _currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 8),
        );
        debugPrint('LocationService: Alternative GPS - lat: ${_currentPosition?.latitude}, lng: ${_currentPosition?.longitude}');
      } catch (e2) {
        debugPrint('LocationService: All GPS attempts failed: $e2');
        // NO usar getLastKnownPosition - puede devolver ubicación del emulador
        _currentPosition = null;
      }
    }

    return _currentPosition;
  }

  // Start tracking location
  Future<void> startTracking(String driverId) async {
    final hasPermission = await checkAndRequestPermission();
    if (!hasPermission) return;

    final locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: AppConfig.locationDistanceFilter.toInt(),
    );

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      _currentPosition = position;
      _positionController.add(position);

      // Update location in database
      _updateLocationInDatabase(driverId, position);
    });
  }

  // Stop tracking location
  void stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  // Update location in database
  Future<void> _updateLocationInDatabase(String driverId, Position position) async {
    try {
      // Update driver's location directly in drivers table (for admin visibility)
      // Only update columns that exist in the drivers table
      await _client.from(SupabaseConfig.driversTable).update({
        'current_lat': position.latitude,
        'current_lng': position.longitude,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', driverId);

      debugPrint('LocationService: Updated driver location - lat: ${position.latitude}, lng: ${position.longitude}');
    } catch (e) {
      debugPrint('LocationService: Error updating driver location: $e');
    }

    // Also try to update separate locations table (may not exist)
    try {
      await _client.from(SupabaseConfig.locationsTable).update({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'heading': position.heading,
        'speed': position.speed,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('driver_id', driverId);
    } catch (_) {
      // Locations table may not exist or no row for this driver - that's okay
    }
  }

  // Get driver's last known location
  Future<Map<String, dynamic>?> getDriverLocation(String driverId) async {
    final response = await _client
        .from(SupabaseConfig.locationsTable)
        .select()
        .eq('driver_id', driverId)
        .maybeSingle();

    return response;
  }

  // Stream driver location (real-time)
  Stream<Map<String, dynamic>> streamDriverLocation(String driverId) {
    return _client
        .from(SupabaseConfig.locationsTable)
        .stream(primaryKey: ['driver_id'])
        .eq('driver_id', driverId)
        .map((data) => data.isNotEmpty ? data.first : {});
  }

  // Calculate distance between two points
  double calculateDistance(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    return Geolocator.distanceBetween(
      startLat,
      startLng,
      endLat,
      endLng,
    ) / 1000; // Convert to km
  }

  // Calculate bearing between two points
  double calculateBearing(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    return Geolocator.bearingBetween(
      startLat,
      startLng,
      endLat,
      endLng,
    );
  }

  // Get nearby drivers
  Future<List<Map<String, dynamic>>> getNearbyDrivers({
    required double latitude,
    required double longitude,
    double radiusKm = 5.0,
  }) async {
    // Using PostGIS function for nearby search
    // This requires the PostGIS extension and a custom function in Supabase
    final response = await _client.rpc('get_nearby_drivers', params: {
      'lat': latitude,
      'lng': longitude,
      'radius_km': radiusKm,
    });

    return List<Map<String, dynamic>>.from(response ?? []);
  }

  // Open location settings
  Future<bool> openLocationSettings() async {
    return await Geolocator.openLocationSettings();
  }

  // Open app settings
  Future<bool> openAppSettings() async {
    return await Geolocator.openAppSettings();
  }

  // ============================================================================
  // ACTIVE RIDE TRACKING - Updates rider can see
  // ============================================================================

  StreamSubscription<Position>? _rideTrackingSubscription;
  String? _activeRideId;

  /// Start tracking for an active ride
  /// Updates both driver_locations AND the delivery record so rider can see
  Future<void> startRideTracking({
    required String driverId,
    required String rideId,
  }) async {
    final hasPermission = await checkAndRequestPermission();
    if (!hasPermission) return;

    _activeRideId = rideId;

    // Use high accuracy and frequent updates during active ride
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 10, // Update every 10 meters
    );

    _rideTrackingSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      _currentPosition = position;
      _positionController.add(position);

      // Update driver's general location
      _updateLocationInDatabase(driverId, position);

      // Update ride-specific location (for rider to see)
      _updateRideLocation(rideId, position);
    });

    debugPrint('LocationService: Started ride tracking for ride $rideId');
  }

  /// Stop ride tracking
  void stopRideTracking() {
    _rideTrackingSubscription?.cancel();
    _rideTrackingSubscription = null;
    _activeRideId = null;
    debugPrint('LocationService: Stopped ride tracking');
  }

  /// Update ride location in deliveries table
  Future<void> _updateRideLocation(String rideId, Position position) async {
    try {
      await _client.from(SupabaseConfig.packageDeliveriesTable).update({
        'driver_lat': position.latitude,
        'driver_lng': position.longitude,
        'driver_heading': position.heading,
        'driver_speed': position.speed,
        'driver_location_updated_at': DateTime.now().toIso8601String(),
      }).eq('id', rideId);
    } catch (e) {
      // Columns might not exist - that's okay
      debugPrint('LocationService: Error updating ride location: $e');
    }
  }

  /// Get current tracking status
  bool get isTrackingRide => _rideTrackingSubscription != null;
  String? get activeRideId => _activeRideId;

  // ============================================================================
  // STATE CODE FROM GPS - Get US state code from coordinates
  // ============================================================================

  /// Cache for state code to avoid repeated API calls
  String? _cachedStateCode;
  Position? _cachedStatePosition;

  /// Get US state code from current GPS position
  /// Returns 2-letter state code (AZ, CA, TX, etc.) or 'AZ' as fallback
  Future<String> getStateCodeFromGPS() async {
    try {
      final position = await getCurrentPosition();
      if (position == null) {
        debugPrint('LocationService: No GPS position, using fallback AZ');
        return 'AZ';
      }

      return await getStateCodeFromCoordinates(position.latitude, position.longitude);
    } catch (e) {
      debugPrint('LocationService: Error getting state from GPS: $e');
      return 'AZ';
    }
  }

  /// Get US state code from specific coordinates
  /// Uses reverse geocoding to determine the state
  Future<String> getStateCodeFromCoordinates(double lat, double lng) async {
    // Check cache - if position is within 0.1 degree (~11km), use cached value
    if (_cachedStateCode != null && _cachedStatePosition != null) {
      final latDiff = (lat - _cachedStatePosition!.latitude).abs();
      final lngDiff = (lng - _cachedStatePosition!.longitude).abs();
      if (latDiff < 0.1 && lngDiff < 0.1) {
        debugPrint('LocationService: Using cached state code: $_cachedStateCode');
        return _cachedStateCode!;
      }
    }

    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);

      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        final stateCode = _extractStateCode(placemark);

        if (stateCode != null) {
          // Cache the result
          _cachedStateCode = stateCode;
          _cachedStatePosition = Position(
            latitude: lat,
            longitude: lng,
            timestamp: DateTime.now(),
            accuracy: 0,
            altitude: 0,
            altitudeAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            speed: 0,
            speedAccuracy: 0,
          );

          debugPrint('LocationService: State code from coordinates: $stateCode');
          return stateCode;
        }
      }

      debugPrint('LocationService: Could not determine state, using fallback AZ');
      return 'AZ';
    } catch (e) {
      debugPrint('LocationService: Reverse geocoding error: $e');
      return 'AZ';
    }
  }

  /// Extract state code from placemark
  /// Handles both full state names and abbreviations
  String? _extractStateCode(Placemark placemark) {
    // Try administrativeArea first (usually contains state name or code)
    final adminArea = placemark.administrativeArea;

    if (adminArea != null && adminArea.isNotEmpty) {
      // If it's already a 2-letter code
      if (adminArea.length == 2) {
        return adminArea.toUpperCase();
      }

      // Convert full state name to code
      return _stateNameToCode(adminArea);
    }

    return null;
  }

  /// Convert US state name to 2-letter code
  static final Map<String, String> _stateNameMap = {
    'alabama': 'AL', 'alaska': 'AK', 'arizona': 'AZ', 'arkansas': 'AR',
    'california': 'CA', 'colorado': 'CO', 'connecticut': 'CT', 'delaware': 'DE',
    'florida': 'FL', 'georgia': 'GA', 'hawaii': 'HI', 'idaho': 'ID',
    'illinois': 'IL', 'indiana': 'IN', 'iowa': 'IA', 'kansas': 'KS',
    'kentucky': 'KY', 'louisiana': 'LA', 'maine': 'ME', 'maryland': 'MD',
    'massachusetts': 'MA', 'michigan': 'MI', 'minnesota': 'MN', 'mississippi': 'MS',
    'missouri': 'MO', 'montana': 'MT', 'nebraska': 'NE', 'nevada': 'NV',
    'new hampshire': 'NH', 'new jersey': 'NJ', 'new mexico': 'NM', 'new york': 'NY',
    'north carolina': 'NC', 'north dakota': 'ND', 'ohio': 'OH', 'oklahoma': 'OK',
    'oregon': 'OR', 'pennsylvania': 'PA', 'rhode island': 'RI', 'south carolina': 'SC',
    'south dakota': 'SD', 'tennessee': 'TN', 'texas': 'TX', 'utah': 'UT',
    'vermont': 'VT', 'virginia': 'VA', 'washington': 'WA', 'west virginia': 'WV',
    'wisconsin': 'WI', 'wyoming': 'WY', 'district of columbia': 'DC',
  };

  String? _stateNameToCode(String stateName) {
    final normalized = stateName.toLowerCase().trim();
    return _stateNameMap[normalized];
  }

  /// Clear state code cache (call when driver moves significantly)
  void clearStateCache() {
    _cachedStateCode = null;
    _cachedStatePosition = null;
  }

  // Dispose
  void dispose() {
    stopTracking();
    stopRideTracking();
    _positionController.close();
  }
}
