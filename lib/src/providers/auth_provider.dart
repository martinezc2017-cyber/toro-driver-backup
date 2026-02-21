import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, ChangeNotifier;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../models/driver_model.dart';
import '../core/logging/app_logger.dart';

enum AuthStatus {
  initial,
  authenticated,
  unauthenticated,
  loading,
}

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();

  AuthStatus _status = AuthStatus.initial;
  DriverModel? _driver;
  String? _error;
  StreamSubscription<AuthState>? _authSubscription;
  Timer? _safetyTimer;

  /// Hard timeout: if auth is not resolved after this, force unauthenticated.
  static const _safetyTimeoutSeconds = 20;

  AuthStatus get status => _status;
  DriverModel? get driver => _driver;
  String? get error => _error;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isLoading => _status == AuthStatus.loading;
  String? get driverId => _driver?.id;

  AuthProvider() {
    _init();
  }

  // Track if we've already resolved the initial auth state
  bool _initialResolved = false;
  bool _isLoadingProfile = false;

  void _init() {
    _authSubscription = _authService.authStateChanges.listen(
      (authState) {
        _handleAuthStateChange(authState);
      },
      onError: (error) {
        // Handle async auth errors (e.g., stale refresh token from session recovery)
        AppLogger.log('[AUTH] Stream error: $error');
        final errorStr = error.toString();
        if (errorStr.contains('refresh_token_not_found') ||
            errorStr.contains('Invalid Refresh Token')) {
          AppLogger.log('[AUTH] Stale session detected, forcing unauthenticated');
          _forceUnauthenticated(reason: 'stale_refresh_token');
        }
      },
    );

    // SAFETY NET: If after 10 seconds auth is still not resolved, force logout.
    // This prevents the dark screen loop permanently.
    _safetyTimer = Timer(const Duration(seconds: _safetyTimeoutSeconds), () {
      if (!_initialResolved || _status == AuthStatus.initial || _status == AuthStatus.loading) {
        AppLogger.log('[AUTH] SAFETY TIMEOUT after ${_safetyTimeoutSeconds}s — status=$_status, initialResolved=$_initialResolved');
        _forceUnauthenticated(reason: 'safety_timeout');
      }
    });

    // Check if this is an OAuth callback (token in URL fragment on web)
    bool hasOAuthCallback = false;
    if (kIsWeb) {
      try {
        final uri = Uri.base;
        final fragment = uri.fragment;
        hasOAuthCallback = fragment.contains('access_token=');
      } catch (e) {
        // Ignore URL check errors
      }
    }

    final delay = hasOAuthCallback ? 1500 : 500;

    Future.delayed(Duration(milliseconds: delay), () async {
      if (_status == AuthStatus.initial) {
        if (_authService.isAuthenticated) {
          await _loadDriverProfile(caller: '_init_delayed_check');
        } else {
          if (hasOAuthCallback) {
            await Future.delayed(const Duration(milliseconds: 1000));
            if (_authService.isAuthenticated) {
              await _loadDriverProfile(caller: '_init_oauth_retry');
              return;
            }
          }
          _status = AuthStatus.unauthenticated;
          _initialResolved = true;
          notifyListeners();
        }
      }
    });
  }

  /// Force to unauthenticated state.
  /// Used by safety timeout and stale token recovery.
  void _forceUnauthenticated({required String reason}) {
    AppLogger.log('[AUTH] _forceUnauthenticated reason=$reason');
    _safetyTimer?.cancel();
    _status = AuthStatus.unauthenticated;
    _initialResolved = true;
    _driver = null;
    _isLoadingProfile = false;
    notifyListeners();
    // Only sign out for stale tokens, NOT for timeouts
    // Signing out on timeout destroys a valid session and causes login loops
    if (reason == 'stale_refresh_token') {
      try {
        _authService.signOut();
      } catch (_) {}
    }
  }

  Future<void> _handleAuthStateChange(AuthState authState) async {
    final session = authState.session;
    final event = authState.event;

    AppLogger.log('[AUTH] onAuthStateChange: event=$event, session=${session != null}, status=$_status, initialResolved=$_initialResolved');

    if (session != null) {
      // Only respond to explicit sign-in events, NOT stale session recovery
      // This prevents the loop: stale token → loading → fail → unauthenticated → stale token...
      if (event == AuthChangeEvent.signedIn) {
        if (_status != AuthStatus.authenticated || _driver?.id != session.user.id) {
          await _loadDriverProfile(caller: '_handleAuthStateChange($event)');
          // Backfill GPS for existing users + mark driver_app_installed
          _authService.backfillLocationIfMissing();
        }
      } else if (event == AuthChangeEvent.tokenRefreshed) {
        // Only reload on token refresh if NOT yet authenticated
        // Avoids loop when driver profile is null (new Google users without driver row)
        if (_status != AuthStatus.authenticated) {
          await _loadDriverProfile(caller: '_handleAuthStateChange(tokenRefreshed)');
        }
      } else if (event == AuthChangeEvent.initialSession) {
        // Initial session: only load if we haven't already resolved
        if (!_initialResolved && _status == AuthStatus.initial) {
          await _loadDriverProfile(caller: '_handleAuthStateChange(initialSession)');
        }
      }
      // Ignore other events with session (like mfaChallenge, etc)
    } else {
      // No session
      if (event == AuthChangeEvent.signedOut) {
        _status = AuthStatus.unauthenticated;
        _initialResolved = true;
        _driver = null;
        notifyListeners();
      }
    }
  }

  Future<void> _loadDriverProfile({String caller = 'unknown'}) async {
    // Prevent concurrent calls that cause rebuild loops
    if (_isLoadingProfile) {
      AppLogger.log('[AUTH] _loadDriverProfile SKIPPED (already loading) from: $caller');
      return;
    }
    _isLoadingProfile = true;
    // Cancel safety timer once we start loading - prevents timeout during slow networks
    _safetyTimer?.cancel();
    AppLogger.log('[AUTH] _loadDriverProfile from: $caller | status=$_status | supaAuth=${_authService.isAuthenticated}');
    try {
      // Only change to loading if not already authenticated (avoid unmounting screens during refresh)
      if (_status != AuthStatus.authenticated) {
        _status = AuthStatus.loading;
        notifyListeners();
      }

      // Timeout: if profile fetch takes >8s, abort
      _driver = await _authService.getCurrentDriverProfile()
          .timeout(const Duration(seconds: 8), onTimeout: () {
        AppLogger.log('[AUTH] getCurrentDriverProfile TIMEOUT after 8s');
        return null;
      });
      // Retry once if null but authenticated (handles transient timeouts after hot restart)
      if (_driver == null && _authService.isAuthenticated) {
        AppLogger.log('[AUTH] driver null but authenticated, retrying once...');
        await Future.delayed(const Duration(milliseconds: 500));
        _driver = await _authService.getCurrentDriverProfile()
            .timeout(const Duration(seconds: 8), onTimeout: () => null);
      }
      AppLogger.log('[AUTH] driver loaded: ${_driver?.id}, role: ${_driver?.role}');

      _status = _authService.isAuthenticated ? AuthStatus.authenticated : AuthStatus.unauthenticated;
      AppLogger.log('[AUTH] final status: $_status');
      _error = null;
    } catch (e) {
      AppLogger.log('[AUTH] ERROR in _loadDriverProfile: $e');
      _error = e.toString();
      _status = AuthStatus.unauthenticated;
    }
    _isLoadingProfile = false;
    _initialResolved = true;
    notifyListeners();
  }

  // Sign up
  Future<bool> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String phone,
    String role = 'driver',
  }) async {
    try {
      _status = AuthStatus.loading;
      _error = null;
      notifyListeners();

      await _authService.signUp(
        email: email,
        password: password,
        firstName: firstName,
        lastName: lastName,
        phone: phone,
        role: role,
      );

      await _loadDriverProfile(caller: 'signUp');
      return true;
    } on AuthException catch (e) {
      _error = _getAuthErrorMessage(e.message);
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Sign up error: $e';
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  // Sign in
  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    AppLogger.log('AUTH_PROVIDER -> signIn called with email: $email');
    try {
      _status = AuthStatus.loading;
      _error = null;
      notifyListeners();

      final response = await _authService.signIn(
        email: email,
        password: password,
      );
      AppLogger.log('AUTH_PROVIDER -> signIn response user: ${response.user?.id}');
      AppLogger.log('AUTH_PROVIDER -> signIn response session: ${response.session != null}');

      await _loadDriverProfile(caller: 'signIn');
      AppLogger.log('AUTH_PROVIDER -> after _loadDriverProfile, status: $_status, driver: ${_driver?.id}');
      return true;
    } on AuthException catch (e) {
      AppLogger.log('AUTH_PROVIDER -> AuthException: ${e.message}');
      _error = _getAuthErrorMessage(e.message);
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    } catch (e) {
      AppLogger.log('AUTH_PROVIDER -> Exception: $e');
      _error = 'Sign in error: $e';
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  // Sign in with phone
  Future<bool> signInWithPhone(String phone) async {
    try {
      _status = AuthStatus.loading;
      _error = null;
      notifyListeners();

      await _authService.signInWithPhone(phone);

      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error sending code: $e';
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  // Verify OTP
  Future<bool> verifyOTP({
    required String phone,
    required String token,
  }) async {
    try {
      _status = AuthStatus.loading;
      _error = null;
      notifyListeners();

      await _authService.verifyOTP(phone: phone, token: token);
      await _loadDriverProfile(caller: 'verifyOTP');
      return true;
    } catch (e) {
      _error = 'Invalid code';
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  // Sign in with Google
  Future<bool> signInWithGoogle() async {
    try {
      _status = AuthStatus.loading;
      _error = null;
      notifyListeners();

      final success = await _authService.signInWithGoogle();

      if (!success) {
        _error = 'Google sign in error';
        _status = AuthStatus.unauthenticated;
        notifyListeners();
      }
      // Auth state listener will handle the rest
      return success;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('cancelled') || msg.contains('canceled')) {
        _status = AuthStatus.unauthenticated;
        notifyListeners();
        return false;
      }
      if (msg.contains('ApiException: 10') || msg.contains('sign_in_failed') || msg.contains('DEVELOPER_ERROR')) {
        _error = 'Esta version necesita actualizarse. Descarga la ultima version en toro-ride.com o escribenos a support@toro-ride.com';
      } else if (msg.contains('network') || msg.contains('timeout') || msg.contains('SocketException')) {
        _error = 'Sin conexion a internet. Verifica tu conexion e intenta de nuevo.';
      } else {
        _error = 'No se pudo iniciar sesion con Google. Intenta de nuevo o usa correo y contrasena. Si el problema continua, escribenos a support@toro-ride.com';
      }
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await _authService.signOut();
      _driver = null;
      _status = AuthStatus.unauthenticated;
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = 'Sign out error: $e';
      notifyListeners();
    }
  }

  // Reset password
  Future<bool> resetPassword(String email) async {
    try {
      _error = null;
      await _authService.resetPassword(email);
      return true;
    } catch (e) {
      _error = 'Error sending recovery email';
      notifyListeners();
      return false;
    }
  }

  // Update password
  Future<bool> updatePassword(String newPassword) async {
    try {
      _error = null;
      await _authService.updatePassword(newPassword);
      return true;
    } catch (e) {
      _error = 'Error updating password';
      notifyListeners();
      return false;
    }
  }

  // Refresh driver profile
  Future<void> refreshProfile() async {
    await _loadDriverProfile(caller: 'refreshProfile');
  }

  // Logout (alias for signOut)
  Future<void> logout() async {
    await signOut();
  }

  // Delete account
  Future<void> deleteAccount() async {
    try {
      await _authService.deleteAccount();
      _driver = null;
      _status = AuthStatus.unauthenticated;
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = 'Error deleting account: $e';
      notifyListeners();
    }
  }

  // Update driver locally
  void updateDriver(DriverModel driver) {
    _driver = driver;
    notifyListeners();
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  String _getAuthErrorMessage(String message) {
    if (message.contains('Invalid login credentials')) {
      return 'Invalid email or password';
    } else if (message.contains('Email not confirmed')) {
      return 'Please confirm your email first';
    } else if (message.contains('User already registered')) {
      return 'This email is already registered';
    } else if (message.contains('Password')) {
      return 'Password must be at least 6 characters';
    } else if (message.contains('rate limit')) {
      return 'Too many attempts. Please try again later';
    }
    return message;
  }

  @override
  void dispose() {
    _safetyTimer?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }
}
