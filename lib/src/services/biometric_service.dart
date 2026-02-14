import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/logging/app_logger.dart';

/// Service for biometric authentication (Face ID / Fingerprint)
/// Allows drivers to quickly log in using their biometrics
class BiometricService {
  static final BiometricService _instance = BiometricService._internal();
  static BiometricService get instance => _instance;

  BiometricService._internal();

  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // Storage keys
  static const String _biometricEnabledKey = 'driver_biometric_enabled';
  static const String _storedEmailKey = 'driver_biometric_email';
  static const String _storedPasswordKey = 'driver_biometric_password';

  /// Check if device supports biometrics
  Future<bool> isBiometricAvailable() async {
    try {
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      return canCheckBiometrics && isDeviceSupported;
    } catch (e) {
      AppLogger.log('BIOMETRIC -> Error checking availability: $e');
      return false;
    }
  }

  /// Get available biometric types
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      AppLogger.log('BIOMETRIC -> Error getting types: $e');
      return [];
    }
  }

  /// Check if biometric login is enabled for this driver
  Future<bool> isBiometricEnabled() async {
    try {
      final enabled = await _secureStorage.read(key: _biometricEnabledKey);
      return enabled == 'true';
    } catch (e) {
      AppLogger.log('BIOMETRIC -> SecureStorage read error (corrupted keystore?): $e');
      // Keystore corrupted (e.g. after reinstall) - disable biometric
      try { await _secureStorage.deleteAll(); } catch (_) {}
      return false;
    }
  }

  /// Enable biometric login and store credentials securely
  Future<bool> enableBiometric({
    required String email,
    required String password,
  }) async {
    try {
      // First authenticate to confirm it's the driver
      final authenticated = await authenticate(
        reason: 'Confirma tu identidad para activar el acceso biométrico',
      );

      if (!authenticated) {
        return false;
      }

      // Store credentials securely
      await _secureStorage.write(key: _biometricEnabledKey, value: 'true');
      await _secureStorage.write(key: _storedEmailKey, value: email);
      await _secureStorage.write(key: _storedPasswordKey, value: password);

      AppLogger.log('BIOMETRIC -> Enabled for driver: $email');
      return true;
    } catch (e) {
      AppLogger.log('BIOMETRIC -> Error enabling: $e');
      return false;
    }
  }

  /// Disable biometric login and clear stored credentials
  Future<void> disableBiometric() async {
    await _secureStorage.delete(key: _biometricEnabledKey);
    await _secureStorage.delete(key: _storedEmailKey);
    await _secureStorage.delete(key: _storedPasswordKey);
    AppLogger.log('BIOMETRIC -> Disabled');
  }

  /// Authenticate with biometrics
  Future<bool> authenticate({String? reason}) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason ?? 'Usa Face ID o huella para iniciar sesión',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } on PlatformException catch (e) {
      AppLogger.log('BIOMETRIC -> Auth error: $e');
      return false;
    }
  }

  /// Get stored credentials after biometric authentication
  Future<Map<String, String>?> getStoredCredentials() async {
    try {
      final authenticated = await authenticate();
      if (!authenticated) {
        return null;
      }

      final email = await _secureStorage.read(key: _storedEmailKey);
      final password = await _secureStorage.read(key: _storedPasswordKey);

      if (email != null && password != null) {
        return {'email': email, 'password': password};
      }
      return null;
    } catch (e) {
      AppLogger.log('BIOMETRIC -> Error getting credentials: $e');
      return null;
    }
  }

  /// Check if has stored credentials
  Future<bool> hasStoredCredentials() async {
    try {
      final email = await _secureStorage.read(key: _storedEmailKey);
      final password = await _secureStorage.read(key: _storedPasswordKey);
      return email != null && password != null;
    } catch (e) {
      AppLogger.log('BIOMETRIC -> SecureStorage read error: $e');
      return false;
    }
  }

  /// Get biometric type name for display
  Future<String> getBiometricTypeName() async {
    final types = await getAvailableBiometrics();
    if (types.contains(BiometricType.face)) {
      return 'Face ID';
    } else if (types.contains(BiometricType.fingerprint)) {
      return 'Huella';
    } else if (types.contains(BiometricType.iris)) {
      return 'Iris';
    }
    return 'Biométrico';
  }

  /// Get icon for biometric type
  Future<String> getBiometricIcon() async {
    final types = await getAvailableBiometrics();
    if (types.contains(BiometricType.face)) {
      return 'face';
    } else if (types.contains(BiometricType.fingerprint)) {
      return 'fingerprint';
    }
    return 'security';
  }
}
