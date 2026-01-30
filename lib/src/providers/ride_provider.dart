import 'dart:async';
import 'package:flutter/foundation.dart' show ChangeNotifier;
import '../services/ride_service.dart';
import '../services/driver_service.dart';
import '../models/ride_model.dart';
import '../models/driver_model.dart';

enum RideProviderStatus {
  idle,
  loading,
  hasActiveRide,
  error,
}

class RideProvider with ChangeNotifier {
  final RideService _rideService = RideService();
  final DriverService _driverService = DriverService();

  // Test mode flag - Set to false to use real Supabase data
  static const bool isTestMode = false;

  RideProviderStatus _status = RideProviderStatus.idle;
  RideModel? _activeRide;
  List<RideModel> _availableRides = [];
  List<RideModel> _rideHistory = [];
  int _todayRidesCount = 0;
  String? _error;

  StreamSubscription? _availableRidesSubscription;
  StreamSubscription? _activeRideSubscription;
  Timer? _refreshTimer;  // Periodic refresh as backup
  String? _currentDriverId;  // Store for refresh

  RideProviderStatus get status => _status;
  RideModel? get activeRide => _activeRide;
  List<RideModel> get availableRides => _availableRides;
  List<RideModel> get rideHistory => _rideHistory;
  int get todayRidesCount => _todayRidesCount;
  String? get error => _error;
  bool get hasActiveRide => _activeRide != null;
  bool get isLoading => _status == RideProviderStatus.loading;

  // Initialize provider for a driver
  Future<void> initialize(String driverId) async {
    _status = RideProviderStatus.loading;
    _currentDriverId = driverId;  // Store for periodic refresh
    notifyListeners();

    try {
      // Check driver status - only active drivers can see rides
      final driver = await _driverService.getDriver(driverId);

      if (driver == null) {
        _status = RideProviderStatus.idle;
        notifyListeners();
        return;
      }

      final isActiveDriver = driver.status == DriverStatus.active;

      // Check for active ride
      _activeRide = await _rideService.getActiveRide(driverId);

      if (_activeRide != null) {
        _status = RideProviderStatus.hasActiveRide;
        _subscribeToActiveRide(_activeRide!.id);
      } else {
        _status = RideProviderStatus.idle;
        // Only subscribe to available rides if driver is active
        if (isActiveDriver) {
          _subscribeToAvailableRides();
        }
      }

      // Load today's count
      _todayRidesCount = await _rideService.getTodayRidesCount(driverId);

      _error = null;
    } catch (e) {
      // Don't subscribe to rides on error - driver may not be active
      _status = RideProviderStatus.idle;
      _todayRidesCount = 0;
      _error = null; // Clear error
    }

    notifyListeners();
  }

  // Simulate a new ride request (for testing)
  // ⚠️ MOCK PARA DESARROLLO/TESTING SOLAMENTE
  // Los valores reales vienen de la BD via StatePricingService
  // Estos valores son SOLO para simular rides en modo desarrollo
  void simulateNewRideRequest() {
    final mockRide = RideModel(
      id: 'ride-${DateTime.now().millisecondsSinceEpoch}',
      passengerId: 'passenger-123',
      passengerName: 'Juan García',
      passengerPhone: '+52 555 987 6543',
      passengerRating: 4.8,
      type: RideType.passenger,
      status: RideStatus.pending,
      pickupLocation: LocationPoint(
        latitude: 19.4326,
        longitude: -99.1332,
        address: 'Av. Reforma 222, CDMX',
      ),
      dropoffLocation: LocationPoint(
        latitude: 19.4285,
        longitude: -99.1277,
        address: 'Zócalo, Centro Histórico',
      ),
      distanceKm: 3.5,
      estimatedMinutes: 12,
      // MOCK VALUES - En producción vienen de pricing_config via StatePricingService
      fare: 85.0,        // Mock fare
      driverEarnings: 68.0,  // Mock earnings (80% of fare)
      platformFee: 17.0,     // Mock platform fee (20% of fare)
      paymentMethod: PaymentMethod.card,
      createdAt: DateTime.now(),
    );

    _availableRides = [mockRide, ..._availableRides];
    notifyListeners();
  }

  // Subscribe to available rides
  void _subscribeToAvailableRides() {
    _availableRidesSubscription?.cancel();
    _availableRidesSubscription = _rideService.streamAvailableRides().listen(
      (rides) {
        _availableRides = rides;
        notifyListeners();
      },
      onError: (e) {
        _error = 'Error al cargar viajes: $e';
        notifyListeners();
      },
    );

    // Start periodic refresh as backup (every 10 seconds)
    _startPeriodicRefresh();
  }

  // Periodic refresh to ensure cancelled rides are removed
  void _startPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (_status == RideProviderStatus.hasActiveRide) {
        // Don't refresh if driver has active ride
        return;
      }
      try {
        final freshRides = await _rideService.getAvailableRides();
        if (_availableRides.length != freshRides.length) {
          _availableRides = freshRides;
          notifyListeners();
        }
      } catch (e) {
        // Ignore periodic refresh errors
      }
    });
  }

  // Stop periodic refresh
  void _stopPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  // Subscribe to active ride updates
  void _subscribeToActiveRide(String rideId) {
    _activeRideSubscription?.cancel();
    _activeRideSubscription = _rideService.streamRide(rideId).listen(
      (ride) {
        _activeRide = ride;
        if (ride == null || ride.status == RideStatus.completed || ride.status == RideStatus.cancelled) {
          _status = RideProviderStatus.idle;
          _activeRide = null;
          _subscribeToAvailableRides();
        }
        notifyListeners();
      },
      onError: (e) {
        _error = 'Error en viaje activo: $e';
        notifyListeners();
      },
    );
  }

  // Accept a ride
  Future<bool> acceptRide(String rideId, String driverId) async {
    try {
      _status = RideProviderStatus.loading;
      notifyListeners();

      // Get service type from the ride being accepted
      final ride = _availableRides.firstWhere(
        (r) => r.id == rideId,
        orElse: () => _availableRides.first,
      );
      final serviceType = ride.type == RideType.package ? 'delivery'
          : ride.type == RideType.carpool ? 'carpool'
          : 'ride';

      _activeRide = await _rideService.acceptRide(rideId, driverId, serviceType: serviceType);
      _status = RideProviderStatus.hasActiveRide;

      // Stop listening to available rides and periodic refresh
      _availableRidesSubscription?.cancel();
      _stopPeriodicRefresh();
      _availableRides = [];

      // Start listening to active ride
      _subscribeToActiveRide(rideId);

      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al aceptar viaje: $e';
      _status = RideProviderStatus.error;
      notifyListeners();
      return false;
    }
  }

  // Dismiss/reject a ride - tracks rejection for acceptance rate
  Future<void> dismissRide(String rideId, String driverId) async {
    // Get service type before removing
    final ride = _availableRides.firstWhere(
      (r) => r.id == rideId,
      orElse: () => _availableRides.first,
    );
    final serviceType = ride.type == RideType.package ? 'delivery'
        : ride.type == RideType.carpool ? 'carpool'
        : 'ride';

    // Track rejection for acceptance rate
    await _rideService.rejectRide(rideId, driverId, serviceType: serviceType);

    // Remove from local list
    _availableRides = _availableRides.where((r) => r.id != rideId).toList();
    notifyListeners();
  }

  // Track timeout when ride expires without response
  Future<void> trackRideTimeout(String rideId, String driverId, {String serviceType = 'ride'}) async {
    await _rideService.trackRideTimeout(rideId, driverId, serviceType: serviceType);
  }

  // Arrive at pickup
  Future<bool> arriveAtPickup() async {
    if (_activeRide == null) return false;

    try {
      _activeRide = await _rideService.arriveAtPickup(_activeRide!.id);
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al marcar llegada: $e';
      notifyListeners();
      return false;
    }
  }

  // Start ride
  Future<bool> startRide() async {
    if (_activeRide == null) return false;

    try {
      _activeRide = await _rideService.startRide(_activeRide!.id);
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al iniciar viaje: $e';
      notifyListeners();
      return false;
    }
  }

  // Complete ride
  Future<bool> completeRide({double? tip, required String driverId}) async {
    if (_activeRide == null) return false;

    try {
      final completedRide = await _rideService.completeRide(_activeRide!.id, tip: tip);

      // Update driver stats
      await _driverService.incrementRideCount(driverId, completedRide.driverEarnings);

      _activeRide = null;
      _status = RideProviderStatus.idle;
      _todayRidesCount++;

      // Resume listening to available rides
      _subscribeToAvailableRides();

      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al completar viaje: $e';
      notifyListeners();
      return false;
    }
  }

  // Cancel ride
  Future<bool> cancelRide(String reason) async {
    if (_activeRide == null) return false;

    try {
      await _rideService.cancelRide(_activeRide!.id, reason);

      _activeRide = null;
      _status = RideProviderStatus.idle;

      // Resume listening to available rides
      _subscribeToAvailableRides();

      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al cancelar viaje: $e';
      notifyListeners();
      return false;
    }
  }

  // Load ride history
  Future<void> loadRideHistory(String driverId, {int limit = 50, int offset = 0}) async {
    try {
      _status = RideProviderStatus.loading;
      notifyListeners();

      final history = await _rideService.getRideHistory(
        driverId,
        limit: limit,
        offset: offset,
      );

      if (offset == 0) {
        _rideHistory = history;
      } else {
        _rideHistory.addAll(history);
      }

      _status = _activeRide != null ? RideProviderStatus.hasActiveRide : RideProviderStatus.idle;
      notifyListeners();
    } catch (e) {
      _error = 'Error al cargar historial: $e';
      _status = RideProviderStatus.error;
      notifyListeners();
    }
  }

  // Rate passenger
  Future<bool> ratePassenger(String rideId, double rating, String? comment) async {
    try {
      await _rideService.ratePassenger(rideId, rating, comment);
      return true;
    } catch (e) {
      _error = 'Error al calificar: $e';
      notifyListeners();
      return false;
    }
  }

  // Refresh available rides
  Future<void> refreshAvailableRides({double? latitude, double? longitude}) async {
    try {
      _availableRides = await _rideService.getAvailableRides(
        latitude: latitude,
        longitude: longitude,
      );
      notifyListeners();
    } catch (e) {
      _error = 'Error al actualizar viajes: $e';
      notifyListeners();
    }
  }

  // Calculate fare (sync version with default pricing)
  double calculateFare(double distanceKm, int estimatedMinutes) {
    // Default Arizona pricing - for real pricing use calculateFareAsync
    const baseFare = 2.50;
    const perMileRate = 0.85;
    const perMinuteRate = 0.16;
    const bookingFee = 2.00;
    const serviceFee = 1.50;
    const minimumFare = 6.00;

    final distanceMiles = distanceKm * 0.621371;
    double fare = baseFare + (distanceMiles * perMileRate) + (estimatedMinutes * perMinuteRate) + bookingFee + serviceFee;
    return fare < minimumFare ? minimumFare : fare;
  }

  // Calculate fare async (uses real pricing from DB)
  Future<double> calculateFareAsync(double distanceKm, int estimatedMinutes) async {
    return await _rideService.calculateFareAsync(
      distanceKm: distanceKm,
      estimatedMinutes: estimatedMinutes,
    );
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _availableRidesSubscription?.cancel();
    _activeRideSubscription?.cancel();
    _stopPeriodicRefresh();
    super.dispose();
  }
}
