import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../services/driver_service.dart';
import '../models/driver_model.dart';

class DriverProvider with ChangeNotifier {
  final DriverService _driverService = DriverService();

  DriverModel? _driver;
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _ranking = [];
  int _rankingPosition = -1;
  bool _isLoading = false;
  String? _error;
  StreamSubscription? _driverSubscription;

  // Test mode flag - Set to false to use real Supabase data
  static const bool isTestMode = false;

  DriverModel? get driver => _driver;
  Map<String, dynamic>? get stats => _stats;
  List<Map<String, dynamic>> get ranking => _ranking;
  int get rankingPosition => _rankingPosition;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isOnline => _driver?.isOnline ?? false;

  // Initialize with driver ID
  Future<void> initialize(String driverId) async {
    debugPrint('DriverProvider: Initializing with driver ID: $driverId');
    _isLoading = true;
    notifyListeners();

    // In test mode, always use mock driver
    if (isTestMode) {
      _driver = _createMockDriver(driverId);
      _stats = _createEmptyStats();
      _error = null;
      _isLoading = false;
      debugPrint('DriverProvider: Mock driver created - isOnline: ${_driver?.isOnline}');
      notifyListeners();
      return;
    }

    try {
      // Load driver profile
      _driver = await _driverService.getDriver(driverId);

      // If driver doesn't exist in database, create one for testing
      if (_driver == null) {
        debugPrint('DriverProvider: Driver not found in database, creating new driver');
        final newDriver = _createMockDriver(driverId);
        try {
          _driver = await _driverService.createDriver(newDriver);
          debugPrint('DriverProvider: Driver created in database successfully');
        } catch (e) {
          // If creation fails (e.g., table doesn't exist), use mock locally
          debugPrint('DriverProvider: Could not create driver in DB: $e - using local mock');
          _driver = newDriver;
        }
        _stats = _createEmptyStats();
        _error = null;
        _isLoading = false;
        notifyListeners();
        return;
      }

      // Load stats
      _stats = await _driverService.getDriverStats(driverId);

      // Subscribe to real-time updates
      _subscribeToDriverUpdates(driverId);

      _error = null;
    } catch (e) {
      // On any error, fallback to mock driver for testing
      debugPrint('DriverProvider: Error loading driver: $e - using mock driver');
      _driver = _createMockDriver(driverId);
      _stats = _createEmptyStats();
      _error = null;
    }

    _isLoading = false;
    notifyListeners();
  }

  // Create mock driver for testing
  DriverModel _createMockDriver(String driverId) {
    return DriverModel(
      id: driverId,
      name: 'Carlos Martinez',
      email: 'carlos@torodriver.com',
      phone: '+52 555 123 4567',
      rating: 4.92,
      totalRides: 1247,
      isOnline: false,
      isVerified: true,
      createdAt: DateTime.now().subtract(const Duration(days: 365)),
      updatedAt: DateTime.now(),
      preferences: {
        'notifications': true,
        'sounds': true,
        'vibration': true,
      },
    );
  }

  // Create empty stats (real zeros, not mock data)
  Map<String, dynamic> _createEmptyStats() {
    return {
      'active_time_today': '0h 0m',
      'distance_today_km': 0.0,
      'online_hours_today': 0.0,
      'rides_today': 0,
      'earnings_today': 0.0,
    };
  }

  // Flag to indicate forced disconnect (for UI notification)
  bool _wasForceDisconnected = false;
  String? _forceDisconnectReason;

  bool get wasForceDisconnected => _wasForceDisconnected;
  String? get forceDisconnectReason => _forceDisconnectReason;

  // Clear force disconnect flag (call after showing notification)
  void clearForceDisconnectFlag() {
    _wasForceDisconnected = false;
    _forceDisconnectReason = null;
  }

  // Flag to indicate account was just approved by admin (for UI notification)
  bool _wasJustApproved = false;
  String? _approvalMessage;

  bool get wasJustApproved => _wasJustApproved;
  String? get approvalMessage => _approvalMessage;

  // Clear approval flag (call after showing notification)
  void clearApprovalFlag() {
    _wasJustApproved = false;
    _approvalMessage = null;
  }

  // Subscribe to real-time driver updates
  void _subscribeToDriverUpdates(String driverId) {
    _driverSubscription?.cancel();
    _driverSubscription = _driverService.streamDriver(driverId).listen(
      (driver) {
        if (driver != null) {
          final previousDriver = _driver;
          final wasOnline = previousDriver?.isOnline ?? false;
          final couldGoOnline = previousDriver?.canGoOnline ?? false;

          _driver = driver;

          // CRITICAL: Auto-disconnect if driver is online but can no longer go online
          // This happens when admin disapproves, documents expire, account suspended, etc.
          if (wasOnline && driver.isOnline && !driver.canGoOnline) {
            debugPrint('DriverProvider: [AUTO-DISCONNECT] Driver online but canGoOnline=false');
            debugPrint('  - adminApproved: ${driver.adminApproved}');
            debugPrint('  - allDocumentsSigned: ${driver.allDocumentsSigned}');
            debugPrint('  - canReceiveRides: ${driver.canReceiveRides}');
            debugPrint('  - onboardingStage: ${driver.onboardingStage}');

            // Determine reason for disconnect
            if (!driver.allDocumentsSigned) {
              _forceDisconnectReason = 'documents_incomplete';
            } else if (!driver.adminApproved) {
              _forceDisconnectReason = 'pending_admin_approval';
            } else if (driver.onboardingStage == 'suspended') {
              _forceDisconnectReason = 'account_suspended';
            } else if (driver.onboardingStage == 'rejected') {
              _forceDisconnectReason = 'account_rejected';
            } else {
              _forceDisconnectReason = 'not_eligible';
            }

            _wasForceDisconnected = true;

            // Force disconnect - update DB and local state
            _forceOffline(driverId);
          }

          // Also check if DB says offline but local says online (sync issue)
          if (wasOnline && !driver.isOnline) {
            debugPrint('DriverProvider: DB shows offline, syncing local state');
            // Local state already updated via _driver = driver
          }

          // APPROVAL NOTIFICATION: Check if driver was just approved
          // This happens when canGoOnline changes from false to true
          if (!couldGoOnline && driver.canGoOnline) {
            debugPrint('DriverProvider: [APPROVED] Driver can now go online!');
            debugPrint('  - adminApproved: ${driver.adminApproved}');
            debugPrint('  - allDocumentsSigned: ${driver.allDocumentsSigned}');
            debugPrint('  - onboardingStage: ${driver.onboardingStage}');

            _wasJustApproved = true;
            _approvalMessage = '¡Tu cuenta ha sido aprobada! Ya puedes comenzar a recibir viajes.';
          }

          notifyListeners();
        }
      },
      onError: (e) {
        _error = 'Error en actualizaciones: $e';
        debugPrint('DriverProvider: Stream error: $e');
        notifyListeners();
      },
    );
  }

  // Force driver offline (internal method)
  Future<void> _forceOffline(String driverId) async {
    debugPrint('DriverProvider: Forcing driver offline');
    try {
      await _driverService.updateOnlineStatus(driverId, false);
      _driver = _driver?.copyWith(isOnline: false);
      debugPrint('DriverProvider: Driver forced offline successfully');
    } catch (e) {
      debugPrint('DriverProvider: Error forcing offline: $e');
      // Still update local state even if DB fails
      _driver = _driver?.copyWith(isOnline: false);
    }
    notifyListeners();
  }

  // Update online status
  Future<void> setOnlineStatus(bool online) async {
    debugPrint('DriverProvider: setOnlineStatus called with: $online');
    debugPrint('DriverProvider: Current driver is null? ${_driver == null}');

    if (_driver == null) {
      debugPrint('DriverProvider: Driver is null, cannot change status');
      return;
    }

    // Always try to update database first (even for mock drivers)
    // This ensures admin can see the driver's status
    try {
      await _driverService.updateOnlineStatus(_driver!.id, online);
      debugPrint('DriverProvider: Database updated successfully');
    } catch (e) {
      debugPrint('DriverProvider: Error updating DB (will continue with local): $e');
    }

    // Always update local state so UI works
    _driver = _driver!.copyWith(isOnline: online);
    debugPrint('DriverProvider: Status changed to ${online ? "ONLINE" : "OFFLINE"}');
    notifyListeners();
  }

  // Toggle online status
  Future<void> toggleOnlineStatus() async {
    await setOnlineStatus(!isOnline);
  }

  // Update driver profile
  Future<bool> updateProfile(DriverModel updatedDriver) async {
    try {
      _isLoading = true;
      notifyListeners();

      _driver = await _driverService.updateDriver(updatedDriver);
      _error = null;

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al actualizar perfil: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Upload profile image
  Future<String?> uploadProfileImage(File imageFile) async {
    if (_driver == null) return null;

    try {
      _isLoading = true;
      notifyListeners();

      final imageUrl = await _driverService.uploadProfileImage(_driver!.id, imageFile);
      _driver = _driver!.copyWith(profileImageUrl: imageUrl);

      _isLoading = false;
      notifyListeners();
      return imageUrl;
    } catch (e) {
      _error = 'Error al subir imagen: $e';
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  // Update current vehicle
  Future<void> updateCurrentVehicle(String? vehicleId) async {
    if (_driver == null) return;

    try {
      await _driverService.updateCurrentVehicle(_driver!.id, vehicleId);
      _driver = _driver!.copyWith(currentVehicleId: vehicleId);
      notifyListeners();
    } catch (e) {
      _error = 'Error al actualizar vehículo: $e';
      notifyListeners();
    }
  }

  // Load driver stats
  Future<void> loadStats() async {
    if (_driver == null) return;

    try {
      _stats = await _driverService.getDriverStats(_driver!.id);
      notifyListeners();
    } catch (e) {
      _error = 'Error al cargar estadísticas: $e';
      notifyListeners();
    }
  }

  // Load ranking
  Future<void> loadRanking() async {
    try {
      _isLoading = true;
      notifyListeners();

      _ranking = await _driverService.getDriverRanking();

      if (_driver != null) {
        _rankingPosition = await _driverService.getDriverRankingPosition(_driver!.id);
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Error al cargar ranking: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  // Apply referral code
  Future<bool> applyReferralCode(String code) async {
    if (_driver == null) return false;

    try {
      final success = await _driverService.applyReferralCode(_driver!.id, code);
      if (!success) {
        _error = 'Código de referido inválido';
        notifyListeners();
      }
      return success;
    } catch (e) {
      _error = 'Error al aplicar código: $e';
      notifyListeners();
      return false;
    }
  }

  // Update a single preference
  Future<void> updatePreference(String key, dynamic value) async {
    if (_driver == null) return;

    try {
      final updatedPreferences = Map<String, dynamic>.from(_driver!.preferences);
      updatedPreferences[key] = value;

      await _driverService.updateDriverPreferences(_driver!.id, updatedPreferences);
      _driver = _driver!.copyWith(preferences: updatedPreferences);
      notifyListeners();
    } catch (e) {
      _error = 'Error al actualizar preferencia: $e';
      notifyListeners();
    }
  }

  // Update profile with individual fields
  Future<bool> updateProfileFields({
    String? firstName,
    String? lastName,
    String? phone,
    String? email,
    String? username,
    String? licenseNumber,
  }) async {
    if (_driver == null) return false;

    try {
      _isLoading = true;
      notifyListeners();

      final updatedDriver = _driver!.copyWith(
        firstName: firstName,
        lastName: lastName,
        phone: phone,
        email: email,
        username: username,
        licenseNumber: licenseNumber,
        updatedAt: DateTime.now(),
      );

      _driver = await _driverService.updateDriver(updatedDriver);
      _error = null;

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al actualizar perfil: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Update driver from external source (e.g., auth provider)
  void setDriver(DriverModel? driver) {
    _driver = driver;
    if (driver != null) {
      _subscribeToDriverUpdates(driver.id);
    }
    notifyListeners();
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _driverSubscription?.cancel();
    super.dispose();
  }
}
