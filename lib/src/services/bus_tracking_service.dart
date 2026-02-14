import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Events that can be triggered by bus drivers
enum BusEventType {
  departed,
  stopped,
  arrivedStop,
  passengerBoarded,
  passengerDropped,
  breakStart,
  breakEnd,
  emergency,
  delay,
  completed,
}

/// Service for bus/vehicle GPS tracking and event logging
class BusTrackingService extends ChangeNotifier {
  static final BusTrackingService _instance = BusTrackingService._internal();
  factory BusTrackingService() => _instance;
  BusTrackingService._internal();

  static const Duration _locationInterval = Duration(seconds: 10);

  final _client = Supabase.instance.client;
  Timer? _locationTimer;
  StreamSubscription<geo.Position>? _positionStream;

  // Current state
  String? _activeRouteId;
  String? _activeVehicleId;
  String? _driverId;
  int _passengersOnBoard = 0;
  bool _isTracking = false;
  geo.Position? _lastPosition;
  double _lastSpeed = 0;
  double _lastHeading = 0;

  // Getters
  bool get isTracking => _isTracking;
  int get passengersOnBoard => _passengersOnBoard;
  String? get activeRouteId => _activeRouteId;
  geo.Position? get lastPosition => _lastPosition;

  /// Start tracking for a specific route
  Future<void> startTracking({
    required String driverId,
    required String routeId,
    String? vehicleId,
  }) async {
    if (_isTracking) {
      debugPrint('BUS_TRACKING: Already tracking, stopping first');
      await stopTracking();
    }

    _driverId = driverId;
    _activeRouteId = routeId;
    _activeVehicleId = vehicleId;
    _passengersOnBoard = 0;
    _isTracking = true;

    debugPrint('BUS_TRACKING: Starting for route $routeId');

    // Check location permissions
    final permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      final requested = await geo.Geolocator.requestPermission();
      if (requested == geo.LocationPermission.denied ||
          requested == geo.LocationPermission.deniedForever) {
        debugPrint('BUS_TRACKING: Location permission denied');
        _isTracking = false;
        return;
      }
    }

    // Start continuous position stream for better accuracy
    _positionStream = geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      ),
    ).listen((position) {
      _lastPosition = position;
      _lastSpeed = position.speed;
      _lastHeading = position.heading;
    });

    // Start periodic location updates to database
    _locationTimer = Timer.periodic(_locationInterval, (_) {
      _sendLocationUpdate();
    });

    // Send initial location immediately
    await _sendLocationUpdate();

    notifyListeners();
    debugPrint('BUS_TRACKING: Started successfully');
  }

  /// Stop tracking
  Future<void> stopTracking() async {
    debugPrint('BUS_TRACKING: Stopping');

    _locationTimer?.cancel();
    _locationTimer = null;

    await _positionStream?.cancel();
    _positionStream = null;

    _isTracking = false;
    _activeRouteId = null;
    _activeVehicleId = null;
    _passengersOnBoard = 0;

    notifyListeners();
  }

  /// Send current location to database
  Future<void> _sendLocationUpdate() async {
    if (!_isTracking || _driverId == null) return;

    try {
      // Get current position if we don't have one from stream
      geo.Position position;
      if (_lastPosition != null) {
        position = _lastPosition!;
      } else {
        position = await geo.Geolocator.getCurrentPosition(
          desiredAccuracy: geo.LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
        _lastPosition = position;
      }

      // Upsert location (update if exists, insert if not)
      await _client.from('bus_driver_location').upsert({
        'driver_id': _driverId,
        'route_id': _activeRouteId,
        'vehicle_id': _activeVehicleId,
        'lat': position.latitude,
        'lng': position.longitude,
        'speed': position.speed,
        'heading': position.heading,
        'accuracy': position.accuracy,
        'altitude': position.altitude,
        'is_moving': position.speed > 1.0, // > 1 m/s = moving
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'driver_id');

      debugPrint(
        'BUS_TRACKING: Location sent - ${position.latitude.toStringAsFixed(5)}, '
        '${position.longitude.toStringAsFixed(5)} @ ${position.speed.toStringAsFixed(1)} m/s',
      );
    } catch (e) {
      debugPrint('BUS_TRACKING: Error sending location: $e');
    }
  }

  /// Log a bus event
  Future<void> logEvent({
    required BusEventType eventType,
    String? stopName,
    String? notes,
    int? passengersChange,
    int? durationSeconds,
  }) async {
    if (_driverId == null || _activeRouteId == null) {
      debugPrint('BUS_TRACKING: Cannot log event - not tracking');
      return;
    }

    try {
      // Update passenger count
      if (passengersChange != null) {
        _passengersOnBoard += passengersChange;
        if (_passengersOnBoard < 0) _passengersOnBoard = 0;
      }

      // Get current position
      double? lat, lng;
      if (_lastPosition != null) {
        lat = _lastPosition!.latitude;
        lng = _lastPosition!.longitude;
      }

      // Insert event
      await _client.from('bus_events').insert({
        'route_id': _activeRouteId,
        'driver_id': _driverId,
        'event_type': eventType.name,
        'lat': lat,
        'lng': lng,
        'passengers_on_board': _passengersOnBoard,
        'passengers_change': passengersChange ?? 0,
        'stop_name': stopName,
        'notes': notes,
        'duration_seconds': durationSeconds,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      notifyListeners();
      debugPrint('BUS_TRACKING: Event logged - ${eventType.name}, passengers: $_passengersOnBoard');
    } catch (e) {
      debugPrint('BUS_TRACKING: Error logging event: $e');
    }
  }

  /// Quick actions for common events
  Future<void> departed() => logEvent(eventType: BusEventType.departed);

  Future<void> stopped({String? stopName}) =>
      logEvent(eventType: BusEventType.stopped, stopName: stopName);

  Future<void> arrivedAtStop(String stopName) =>
      logEvent(eventType: BusEventType.arrivedStop, stopName: stopName);

  Future<void> passengerBoarded({int count = 1}) =>
      logEvent(eventType: BusEventType.passengerBoarded, passengersChange: count);

  Future<void> passengerDropped({int count = 1}) =>
      logEvent(eventType: BusEventType.passengerDropped, passengersChange: -count);

  Future<void> startBreak() => logEvent(eventType: BusEventType.breakStart);

  Future<void> endBreak({int durationSeconds = 0}) =>
      logEvent(eventType: BusEventType.breakEnd, durationSeconds: durationSeconds);

  Future<void> emergency(String notes) =>
      logEvent(eventType: BusEventType.emergency, notes: notes);

  Future<void> reportDelay(String notes) =>
      logEvent(eventType: BusEventType.delay, notes: notes);

  Future<void> completed() async {
    await logEvent(eventType: BusEventType.completed);
    await stopTracking();
  }

  /// Set passengers count manually
  void setPassengers(int count) {
    _passengersOnBoard = count;
    notifyListeners();
  }

  @override
  void dispose() {
    stopTracking();
    super.dispose();
  }
}
