import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, ChangeNotifier;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../models/driver_model.dart';

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

  AuthStatus get status => _status;
  DriverModel? get driver => _driver;
  String? get error => _error;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isLoading => _status == AuthStatus.loading;
  String? get driverId => _driver?.id;

  AuthProvider() {
    _init();
  }

  void _init() {
    _authSubscription = _authService.authStateChanges.listen((authState) {
      _handleAuthStateChange(authState);
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

    // Wait longer if OAuth callback detected, as Supabase needs time to process the token
    final delay = hasOAuthCallback ? 1500 : 500;

    Future.delayed(Duration(milliseconds: delay), () async {
      if (_status == AuthStatus.initial) {
        // Check if already authenticated
        if (_authService.isAuthenticated) {
          await _loadDriverProfile(caller: '_init_delayed_check');
        } else {
          // If OAuth callback detected but still not authenticated, try to recover session
          if (hasOAuthCallback) {
            await Future.delayed(const Duration(milliseconds: 1000));
            if (_authService.isAuthenticated) {
              await _loadDriverProfile(caller: '_init_oauth_retry');
              return;
            }
          }
          _status = AuthStatus.unauthenticated;
          notifyListeners();
        }
      }
    });
  }

  Future<void> _handleAuthStateChange(AuthState authState) async {
    final session = authState.session;
    final event = authState.event;

    if (session != null) {
      // Prevent infinite loop - only load if not already authenticated with same user
      if (_status != AuthStatus.authenticated || _driver?.id != session.user.id) {
        await _loadDriverProfile(caller: '_handleAuthStateChange');
      }
    } else {
      // Only set unauthenticated on explicit sign out event
      // For other events (like initial), let the delayed check handle it
      if (event == AuthChangeEvent.signedOut) {
        _status = AuthStatus.unauthenticated;
        _driver = null;
        notifyListeners();
      }
    }
  }

  Future<void> _loadDriverProfile({String caller = 'unknown'}) async {
    try {
      // Only change to loading if not already authenticated (avoid unmounting screens during refresh)
      if (_status != AuthStatus.authenticated) {
        _status = AuthStatus.loading;
        notifyListeners();
      }

      _driver = await _authService.getCurrentDriverProfile();

      // User is authenticated even if driver profile doesn't exist yet
      // (new users need to register as driver)
      _status = _authService.isAuthenticated ? AuthStatus.authenticated : AuthStatus.unauthenticated;
      _error = null;
    } catch (e) {
      _error = e.toString();
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  // Sign up
  Future<bool> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String phone,
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
    try {
      _status = AuthStatus.loading;
      _error = null;
      notifyListeners();

      await _authService.signIn(
        email: email,
        password: password,
      );

      await _loadDriverProfile(caller: 'signIn');
      return true;
    } on AuthException catch (e) {
      _error = _getAuthErrorMessage(e.message);
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    } catch (e) {
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
      _error = 'Google sign in error: $e';
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
    _authSubscription?.cancel();
    super.dispose();
  }
}
