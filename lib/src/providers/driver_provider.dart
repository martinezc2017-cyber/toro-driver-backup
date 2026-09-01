import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/driver_service.dart';
import '../services/notification_service.dart';
import '../services/background_location_service.dart';
import '../config/supabase_config.dart';
import '../config/stripe_config.dart';
import '../models/driver_model.dart';
import '../utils/money_format.dart' show setUserCountry;

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
    _isLoading = true;
    notifyListeners();

    // In test mode, always use mock driver
    if (isTestMode) {
      _driver = _createMockDriver(driverId);
      _stats = _createEmptyStats();
      _error = null;
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      // Load driver profile
      _driver = await _driverService.getDriver(driverId);
      if (_driver == null) {
        _stats = _createEmptyStats();
        _error = 'driver_profile_not_found';
        _isLoading = false;
        notifyListeners();
        return;
      }

      setUserCountry(_driver!.countryCode);
      await StripeConfig.switchProvider(
        _driver!.countryCode.toUpperCase() == 'MX'
            ? StripeProvider.mx
            : StripeProvider.us,
      );

      // Load stats
      _stats = await _driverService.getDriverStats(driverId);

      // Subscribe to real-time updates
      _subscribeToDriverUpdates(driverId);

      // Register FCM token for push notifications
      try {
        final notifService = NotificationService();
        await notifService.initialize();
        await notifService.updateFCMToken(driverId);
      } catch (e) {
        debugPrint('FCM token registration error: $e');
      }

      _error = null;
    } catch (e) {
      _driver = null;
      _stats = _createEmptyStats();
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  // Create driver from real user auth data (not mock)
  DriverModel _createMockDriver(String driverId) {
    // Get real user data from Supabase Auth
    final user = Supabase.instance.client.auth.currentUser;
    final userMetadata = user?.userMetadata;

    // Extract real name from metadata or use email as fallback
    String realName = 'Driver';
    if (userMetadata != null) {
      final firstName = userMetadata['first_name'] ?? '';
      final lastName = userMetadata['last_name'] ?? '';
      if (firstName.isNotEmpty || lastName.isNotEmpty) {
        realName = '$firstName $lastName'.trim();
      }
    }
    // Fallback to email prefix if no name
    if (realName == 'Driver' && user?.email != null) {
      realName = user!.email!.split('@').first;
    }

    return DriverModel(
      id: driverId,
      name: realName,
      email: user?.email ?? 'driver@toro.com',
      phone: userMetadata?['phone'] ?? '',
      rating: 5.0,
      totalRides: 0,
      isOnline: false,
      isVerified: true,
      createdAt: DateTime.now().subtract(const Duration(days: 30)),
      updatedAt: DateTime.now(),
      preferences: {'notifications': true, 'sounds': true, 'vibration': true},
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
    _driverSubscription = _driverService
        .streamDriver(driverId)
        .listen(
          (driver) {
            if (driver != null) {
              final previousDriver = _driver;
              final wasOnline = previousDriver?.isOnline ?? false;
              final couldGoOnline = previousDriver?.canGoOnline ?? false;

              _driver = driver;
              setUserCountry(driver.countryCode);
              unawaited(
                StripeConfig.switchProvider(
                  driver.countryCode.toUpperCase() == 'MX'
                      ? StripeProvider.mx
                      : StripeProvider.us,
                ),
              );

              // PRESENCIA EN VIVO: mantén el latido GPS corriendo SIEMPRE que esté
              // online — incluido cuando el app abre ya-online (sin tocar el
              // switch). Antes solo arrancaba en el toggle → al reabrir el app
              // quedaba online sin latido y el admin lo veía stale.
              if (driver.isOnline) {
                if (_heartbeatTimer == null) _startHeartbeat();
              } else {
                _stopHeartbeat();
              }

              // CRITICAL: Auto-disconnect if driver is online but can no longer go online
              // This happens when admin disapproves, documents expire, account suspended, etc.
              if (wasOnline && driver.isOnline && !driver.canGoOnline) {
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
              // if wasOnline && !driver.isOnline: Local state already updated via _driver = driver

              // APPROVAL NOTIFICATION: Check if driver was just approved
              // This happens when canGoOnline changes from false to true
              if (!couldGoOnline && driver.canGoOnline) {
                _wasJustApproved = true;
                _approvalMessage = 'driver.account_approved'.tr();
              }

              notifyListeners();
            }
          },
          onError: (e) {
            _error = 'error.realtime_updates'.tr(namedArgs: {'error': '$e'});
            notifyListeners();
          },
        );
  }

  // Force driver offline (internal method)
  Future<void> _forceOffline(String driverId) async {
    try {
      await _driverService.updateOnlineStatus(driverId, false);
      _driver = _driver?.copyWith(isOnline: false);
    } catch (e) {
      // Still update local state even if DB fails
      _driver = _driver?.copyWith(isOnline: false);
    }
    notifyListeners();
  }

  // Update online status
  // VALIDA documentos y auto-aprueba si están completos
  Future<void> setOnlineStatus(bool online) async {
    if (_driver == null) return;

    // Si va a OFFLINE, permitir siempre
    if (!online) {
      _intendedOnline = false;
      _stopHeartbeat();
      try {
        await _driverService.updateOnlineStatus(_driver!.id, false);
      } catch (e) {
        debugPrint('Error setting offline: $e');
      }
      _driver = _driver!.copyWith(isOnline: false);
      notifyListeners();
      return;
    }

    // Si va a ONLINE, validar que pueda
    final driver = _driver!;

    // 1. Verificar status no suspendido/rechazado
    if (driver.status == DriverStatus.suspended) {
      _error = 'driver.account_suspended'.tr();
      notifyListeners();
      throw Exception(_error);
    }
    if (driver.status == DriverStatus.rejected) {
      _error = 'driver.account_rejected'.tr();
      notifyListeners();
      throw Exception(_error);
    }

    // LA APROBACIÓN DEL ADMIN MANDA: si el chofer YA puede operar
    // (canGoOnline = docs legales firmados + admin_approved + can_receive_rides
    // + onboarding 'approved', o modo trial), NO re-validar licencia/seguro/
    // placa campo por campo. Eso bloqueaba a choferes YA APROBADOS por detalles
    // como "licencia sin número" aunque la imagen esté subida. canGoOnline es
    // la MISMA verdad que usa el admin y el resto del app.
    if (driver.canGoOnline) {
      try {
        await _driverService.updateOnlineStatus(_driver!.id, true);
        _driver = _driver!.copyWith(isOnline: true);
        _intendedOnline = true;
        _error = null;
        _startHeartbeat(); // presencia EN VIVO mientras esté online
        notifyListeners();
        return;
      } catch (e) {
        _error = 'error.going_online'.tr(namedArgs: {'error': '$e'});
        notifyListeners();
        throw Exception(_error);
      }
    }

    // 2. Verificar documentos firmados
    if (!driver.allDocumentsSigned) {
      final missing = <String>[];
      if (!driver.agreementSigned) missing.add('driver.doc_agreement'.tr());
      if (!driver.icaSigned) missing.add('driver.doc_ica'.tr());
      if (!driver.safetyPolicySigned) missing.add('driver.safety_policy'.tr());
      if (!driver.bgcConsentSigned) missing.add('driver.doc_bgc'.tr());
      _error = 'driver.missing_docs'.tr(namedArgs: {'docs': missing.join(", ")});
      notifyListeners();
      throw Exception(_error);
    }

    // 3. Verificar documentos vigentes (licencia + seguro)
    if (driver.licenseNumber == null || driver.licenseNumber!.isEmpty) {
      _error = 'driver.missing_license'.tr();
      notifyListeners();
      throw Exception(_error);
    }
    if (driver.licenseExpiry != null &&
        driver.licenseExpiry!.isBefore(DateTime.now())) {
      _error = 'driver.license_expired'.tr();
      notifyListeners();
      throw Exception(_error);
    }
    if (driver.insurancePolicy == null || driver.insurancePolicy!.isEmpty) {
      _error = 'driver.missing_insurance'.tr();
      notifyListeners();
      throw Exception(_error);
    }
    if (driver.insuranceExpiry != null &&
        driver.insuranceExpiry!.isBefore(DateTime.now())) {
      _error = 'driver.insurance_expired'.tr();
      notifyListeners();
      throw Exception(_error);
    }

    // 4. Verificar vehículo registrado
    if (driver.vehiclePlate == null || driver.vehiclePlate!.isEmpty) {
      _error = 'driver.register_vehicle'.tr();
      notifyListeners();
      throw Exception(_error);
    }

    // 5. La aprobación la hace un ADMIN (RPC admin_approve_driver), NUNCA el cliente.
    //    El chofer sube sus documentos y queda en revisión. El candado server-side
    //    (trg_protect_driver_approval_cols) revierte cualquier intento de auto-aprobarse.
    //    El modo prueba (trial) sigue permitido para el bootstrap.
    if (!driver.adminApproved && !driver.trialModeAccepted) {
      _error = 'driver.pending_review'.tr();
      notifyListeners();
      throw Exception(_error);
    }

    // 6. Ya validado, poner online
    try {
      await _driverService.updateOnlineStatus(_driver!.id, true);
      _driver = _driver!.copyWith(isOnline: true);
      _intendedOnline = true;
      _error = null;
      _startHeartbeat(); // presencia EN VIVO mientras esté online
      notifyListeners();
    } catch (e) {
      _error = 'error.going_online'.tr(namedArgs: {'error': '$e'});
      notifyListeners();
      throw Exception(_error);
    }
  }

  // ===========================================================================
  // HEARTBEAT — mantiene la presencia FRESCA mientras el chofer está online.
  // Cada 30s estampa location_updated_at → admin/dispatch/marketplace lo ven
  // online en tiempo real. Sin esto el conteo "online" siempre quedaba en 0
  // (el admin exige GPS < 5 min). Para TODOS los sectores (presencia unificada).
  // ===========================================================================
  Timer? _heartbeatTimer;
  bool _sessionActive = false; // guarda 1 sola sesion por periodo online
  /// INTENDED online state — tracks what the driver WANTS, not what the DB says.
  /// Prevents the death spiral: DB marks offline (stale timestamp) → heartbeat
  /// reads isOnline=false → kills itself → driver stays offline forever.
  bool _intendedOnline = false;

  // Graba la sesion: started_at al ponerse online, ended_at al offline.
  // Asi el admin puede saber QUIEN se conecto al ultimo, hace cuanto, y cuanto
  // lleva online/offline (antes driver_sessions estaba vacia = sin historial).
  Future<void> _recordSessionStart() async {
    if (_sessionActive) return;
    final d = _driver;
    if (d == null) return;
    _sessionActive = true;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    try {
      final sb = Supabase.instance.client;
      // cierra sesiones colgadas previas del chofer
      await sb
          .from('driver_sessions')
          .update({
            'is_active': false,
            'ended_at': nowIso,
            'logout_reason': 'stale',
          })
          .eq('driver_id', d.id)
          .eq('is_active', true);
      await sb.from('driver_sessions').insert({
        'driver_id': d.id,
        'user_id': sb.auth.currentUser?.id,
        // session_token es NOT NULL en la tabla -> generamos uno unico por sesion
        'session_token': '${d.id}_${DateTime.now().microsecondsSinceEpoch}',
        'is_active': true,
        'started_at': nowIso,
        'last_activity_at': nowIso,
        'device_platform': 'android',
        if (d.currentLat != null) 'login_latitude': d.currentLat,
        if (d.currentLng != null) 'login_longitude': d.currentLng,
        if (d.stateCode != null) 'login_state': d.stateCode,
      });
    } catch (e) {
      debugPrint('session start error: $e');
      _sessionActive = false;
    }
  }

  Future<void> _recordSessionEnd() async {
    if (!_sessionActive) return;
    _sessionActive = false;
    final d = _driver;
    if (d == null) return;
    try {
      final endIso = DateTime.now().toUtc().toIso8601String();
      await Supabase.instance.client
          .from('driver_sessions')
          .update({
            'is_active': false,
            'ended_at': endIso,
            'logged_out_at': endIso,
            'logout_reason': 'offline',
          })
          .eq('driver_id', d.id)
          .eq('is_active', true);
    } catch (e) {
      debugPrint('session end error: $e');
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _sendHeartbeat(); // inmediato
    _recordSessionStart(); // historial de presencia
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _sendHeartbeat(),
    );
    // FOREGROUND SERVICE: mantiene el heartbeat vivo en SEGUNDO PLANO. El Timer
    // de arriba se PAUSA cuando Android manda el app a background -> el chofer
    // "desaparecia" del admin al cerrar/minimizar la pantalla. El service sigue
    // estampando location_updated_at aunque el app este en segundo plano.
    final d = _driver;
    if (d != null) {
      BackgroundLocationController().startOnlineHeartbeat(
        driverId: d.id,
        supabaseUrl: SupabaseConfig.supabaseUrl,
        supabaseKey: SupabaseConfig.supabaseAnonKey,
      );
    }
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _recordSessionEnd(); // cierra la sesion (ended_at)
    // Para el foreground service (quita la notificacion "En Linea").
    BackgroundLocationController().stopTracking();
  }

  /// Called from HomeScreen.didChangeAppLifecycleState(resumed).
  /// On iOS the Dart Timer PAUSES in background → location_updated_at goes
  /// stale → DB marks the driver offline → rider sees "no drivers available".
  /// This method fires an IMMEDIATE heartbeat and restarts the timer if it died.
  Future<void> resumeHeartbeat() async {
    if (!_intendedOnline || _driver == null) return;
    // Immediate heartbeat to refresh location_updated_at NOW
    await _sendHeartbeat();
    // Restart timer if it was killed/paused
    if (_heartbeatTimer == null || !_heartbeatTimer!.isActive) {
      _startHeartbeat();
    }
  }

  Future<void> _sendHeartbeat() async {
    final d = _driver;
    if (d == null) return;
    // USE _intendedOnline — NOT d.isOnline. The DB may show isOnline=false
    // because location_updated_at expired (> 5 min stale). If we read that
    // and stop the heartbeat, the driver NEVER recovers → death spiral.
    // _intendedOnline tracks what the DRIVER WANTS, not what the DB says.
    if (!_intendedOnline) {
      _stopHeartbeat();
      return;
    }
    final nowIso = DateTime.now().toUtc().toIso8601String();
    try {
      // GPS REAL → conecta con el mapa en vivo, el conteo online y el dispatch.
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 12));
      await Supabase.instance.client
          .from('drivers')
          .update({
            'is_online': true,
            'current_lat': pos.latitude,
            'current_lng': pos.longitude,
            'location_updated_at': nowIso,
          })
          .eq('id', d.id);
    } catch (e) {
      debugPrint('Heartbeat GPS error: $e');
      // Respaldo: al menos mantener la presencia (prueba de vida)
      try {
        await Supabase.instance.client
            .from('drivers')
            .update({
              'is_online': true,
              'location_updated_at': nowIso,
            })
            .eq('id', d.id);
      } catch (_) {}
    }
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
      _error = 'error.update_profile'.tr(namedArgs: {'error': '$e'});
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Upload profile image
  Future<String?> uploadProfileImage(Uint8List imageBytes) async {
    if (_driver == null) return null;

    try {
      _isLoading = true;
      notifyListeners();

      final imageUrl = await _driverService.uploadProfileImage(
        _driver!.id,
        imageBytes,
      );
      _driver = _driver!.copyWith(profileImageUrl: imageUrl);

      _isLoading = false;
      notifyListeners();
      return imageUrl;
    } catch (e) {
      _error = 'error.upload_image'.tr(namedArgs: {'error': '$e'});
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
      _error = 'error.update_vehicle'.tr(namedArgs: {'error': '$e'});
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
      _error = 'error.load_stats'.tr(namedArgs: {'error': '$e'});
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
        _rankingPosition = await _driverService.getDriverRankingPosition(
          _driver!.id,
        );
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'error.loading_ranking'.tr(namedArgs: {'error': e.toString()});
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
        _error = 'error.invalid_referral'.tr();
        notifyListeners();
      }
      return success;
    } catch (e) {
      _error = 'error.apply_code'.tr(namedArgs: {'error': '$e'});
      notifyListeners();
      return false;
    }
  }

  // Update a single preference
  Future<void> updatePreference(String key, dynamic value) async {
    if (_driver == null) return;

    try {
      final updatedPreferences = Map<String, dynamic>.from(
        _driver!.preferences,
      );
      updatedPreferences[key] = value;

      await _driverService.updateDriverPreferences(
        _driver!.id,
        updatedPreferences,
      );
      _driver = _driver!.copyWith(preferences: updatedPreferences);
      notifyListeners();
    } catch (e) {
      _error = 'error.update_preference'.tr(namedArgs: {'error': '$e'});
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
      _error = 'error.update_profile'.tr(namedArgs: {'error': '$e'});
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
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    super.dispose();
  }
}
