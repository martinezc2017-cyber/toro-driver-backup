import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';

enum LocationStatus {
  initial,
  permissionDenied,
  serviceDisabled,
  tracking,
  stopped,
  error,
}

class LocationProvider with ChangeNotifier {
  final LocationService _locationService = LocationService();

  LocationStatus _status = LocationStatus.initial;
  Position? _currentPosition;
  String? _error;
  StreamSubscription<Position>? _positionSubscription;
  bool _isTracking = false;

  LocationStatus get status => _status;
  Position? get currentPosition => _currentPosition;
  String? get error => _error;
  bool get isTracking => _isTracking;
  double? get latitude => _currentPosition?.latitude;
  double? get longitude => _currentPosition?.longitude;
  double? get heading => _currentPosition?.heading;
  double? get speed => _currentPosition?.speed;

  // Initialize and check permissions
  Future<bool> initialize() async {
    try {
      final hasPermission = await _locationService.checkAndRequestPermission();

      if (!hasPermission) {
        _status = LocationStatus.permissionDenied;
        notifyListeners();
        return false;
      }

      // Get initial position
      _currentPosition = await _locationService.getCurrentPosition();
      _status = LocationStatus.stopped;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al inicializar ubicación: $e';
      _status = LocationStatus.error;
      notifyListeners();
      return false;
    }
  }

  // Start tracking location
  Future<bool> startTracking(String driverId) async {
    if (_isTracking) return true;

    try {
      final hasPermission = await _locationService.checkAndRequestPermission();

      if (!hasPermission) {
        _status = LocationStatus.permissionDenied;
        notifyListeners();
        return false;
      }

      await _locationService.startTracking(driverId);

      _positionSubscription = _locationService.positionStream.listen(
        (position) {
          _currentPosition = position;
          notifyListeners();
        },
        onError: (e) {
          _error = 'Error de ubicación: $e';
          notifyListeners();
        },
      );

      _isTracking = true;
      _status = LocationStatus.tracking;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al iniciar tracking: $e';
      _status = LocationStatus.error;
      notifyListeners();
      return false;
    }
  }

  // Stop tracking
  void stopTracking() {
    _locationService.stopTracking();
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _isTracking = false;
    _status = LocationStatus.stopped;
    notifyListeners();
  }

  // Get current position once
  Future<Position?> getCurrentPosition() async {
    try {
      _currentPosition = await _locationService.getCurrentPosition();
      notifyListeners();
      return _currentPosition;
    } catch (e) {
      _error = 'Error al obtener ubicación: $e';
      notifyListeners();
      return null;
    }
  }

  // Calculate distance to a point
  double? distanceTo(double lat, double lng) {
    if (_currentPosition == null) return null;
    return _locationService.calculateDistance(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      lat,
      lng,
    );
  }

  // Calculate bearing to a point
  double? bearingTo(double lat, double lng) {
    if (_currentPosition == null) return null;
    return _locationService.calculateBearing(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      lat,
      lng,
    );
  }

  // Open location settings
  Future<bool> openLocationSettings() async {
    return await _locationService.openLocationSettings();
  }

  // Open app settings
  Future<bool> openAppSettings() async {
    return await _locationService.openAppSettings();
  }

  // Request permissions again
  Future<bool> requestPermissions() async {
    final hasPermission = await _locationService.checkAndRequestPermission();
    if (hasPermission) {
      _status = LocationStatus.stopped;
    } else {
      _status = LocationStatus.permissionDenied;
    }
    notifyListeners();
    return hasPermission;
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    stopTracking();
    _locationService.dispose();
    super.dispose();
  }
}
