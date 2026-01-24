import 'dart:async';
import 'dart:io' show ContentType, HttpRequest, HttpServer, InternetAddress, Platform;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../config/supabase_config.dart';
import '../models/driver_model.dart';

class AuthService {
  final SupabaseClient _client = SupabaseConfig.client;

  // Callback URL para Windows Desktop - Puerto 5001
  static const int _desktopPort = 5001;
  static const String _desktopCallbackUrl = 'http://localhost:$_desktopPort';

  // Current user
  User? get currentUser => _client.auth.currentUser;
  String? get currentUserId => currentUser?.id;
  bool get isAuthenticated => currentUser != null;

  // Auth state stream
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  // Sign up with email and password
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String phone,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      data: {
        'first_name': firstName,
        'last_name': lastName,
        'phone': phone,
      },
    );

    if (response.user != null) {
      // Create driver profile
      await _createDriverProfile(
        userId: response.user!.id,
        email: email,
        firstName: firstName,
        lastName: lastName,
        phone: phone,
      );
    }

    return response;
  }

  // Sign in with email and password
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  // Sign in with phone (OTP)
  Future<void> signInWithPhone(String phone) async {
    await _client.auth.signInWithOtp(
      phone: phone,
    );
  }

  // Verify OTP
  Future<AuthResponse> verifyOTP({
    required String phone,
    required String token,
  }) async {
    return await _client.auth.verifyOTP(
      phone: phone,
      token: token,
      type: OtpType.sms,
    );
  }

  // Sign in with Google OAuth
  Future<bool> signInWithGoogle() async {
    try {
      debugPrint('=== signInWithGoogle called ===');
      debugPrint('kIsWeb: $kIsWeb');

      // Check if desktop platform (only access Platform when NOT on web)
      bool isDesktop = false;
      bool isMobile = false;
      if (!kIsWeb) {
        isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
        isMobile = Platform.isAndroid || Platform.isIOS;
        debugPrint('isDesktop: $isDesktop, isMobile: $isMobile');
      }

      if (isDesktop) {
        debugPrint('Using DESKTOP method with port 5001');
        return await _signInWithGoogleDesktop();
      }

      if (isMobile) {
        debugPrint('Using MOBILE method with deep link');
        return await _signInWithGoogleMobile();
      }

      debugPrint('Using WEB method');
      // En producción usar URL de Cloudflare, en desarrollo usar localhost
      final isProduction = Uri.base.host.contains('pages.dev') ||
                           Uri.base.host.contains('toro-ride.com') ||
                           Uri.base.host.contains('toro-driver');
      final redirectUrl = isProduction
          ? Uri.base.origin
          : 'https://toro-driver.pages.dev';
      debugPrint('Web OAuth redirectTo: $redirectUrl');

      final response = await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectUrl,
      );
      return response;
    } catch (e) {
      debugPrint('Google sign in error: $e');
      return false;
    }
  }

  /// Sign in con Google para Android/iOS usando Google Sign In nativo
  /// FUERZA el selector de cuentas a aparecer siempre
  Future<bool> _signInWithGoogleMobile() async {
    try {
      debugPrint('=== GOOGLE SIGN IN NATIVE (Account Selector) ===');

      // Web Client ID from config
      final webClientId = SupabaseConfig.googleWebClientId;

      // Si no hay Web Client ID configurado, usar método OAuth estándar
      if (webClientId.isEmpty) {
        debugPrint('No Google Web Client ID configured, falling back to OAuth...');
        return await _signInWithGoogleMobileOAuth();
      }

      final googleSignIn = GoogleSignIn(
        serverClientId: webClientId,
        scopes: ['email', 'profile'],
      );

      // IMPORTANTE: Primero hacer signOut para forzar el selector de cuentas
      debugPrint('Signing out from Google to force account selector...');
      await googleSignIn.signOut();

      // Ahora hacer signIn - esto SIEMPRE mostrará el selector de cuentas
      debugPrint('Showing Google account selector...');
      final googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        debugPrint('User cancelled Google sign in');
        return false;
      }

      debugPrint('Google user selected: ${googleUser.email}');

      // Obtener tokens de autenticación
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      debugPrint('Got ID token: ${idToken != null ? "YES" : "NO"}');
      debugPrint('Got access token: ${accessToken != null ? "YES" : "NO"}');

      if (idToken == null) {
        debugPrint('ERROR: No ID token from Google, falling back to OAuth...');
        // Fallback: usar OAuth con login_hint del email seleccionado
        return await _signInWithGoogleMobileOAuth(loginHint: googleUser.email);
      }

      // Usar el ID token para autenticarse con Supabase
      debugPrint('Signing in to Supabase with Google ID token...');
      final response = await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      if (response.session != null) {
        debugPrint('SUCCESS: Supabase session established');
        debugPrint('User ID: ${response.user?.id}');
        debugPrint('Email: ${response.user?.email}');
        return true;
      } else {
        debugPrint('ERROR: No session returned from Supabase');
        return false;
      }
    } catch (e) {
      debugPrint('Native Google Sign In error: $e');
      // Fallback al método OAuth estándar
      debugPrint('Falling back to OAuth method...');
      return await _signInWithGoogleMobileOAuth();
    }
  }

  /// Fallback: OAuth estándar con deep links
  Future<bool> _signInWithGoogleMobileOAuth({String? loginHint}) async {
    try {
      debugPrint('=== GOOGLE OAUTH MOBILE (Fallback) ===');

      // Primero, limpiar cualquier sesión de Google Sign In anterior
      try {
        final googleSignIn = GoogleSignIn();
        await googleSignIn.signOut();
        debugPrint('Cleared Google Sign In cache');
      } catch (e) {
        debugPrint('Could not clear Google cache: $e');
      }

      const redirectUrl = 'io.supabase.torodriver://login-callback/';
      debugPrint('Redirect URL: $redirectUrl');

      // Set up deep link listener
      final appLinks = AppLinks();
      final completer = Completer<bool>();
      StreamSubscription<Uri>? subscription;

      // Función para procesar el URI del callback
      Future<void> processCallback(Uri uri) async {
        debugPrint('Deep link received: $uri');
        debugPrint('Scheme: ${uri.scheme}, Host: ${uri.host}');
        debugPrint('Query params: ${uri.queryParameters}');
        debugPrint('Fragment: ${uri.fragment}');

        if (uri.scheme == 'io.supabase.torodriver') {
          final code = uri.queryParameters['code'];
          final error = uri.queryParameters['error'];

          String? accessToken = uri.queryParameters['access_token'];
          String? refreshToken = uri.queryParameters['refresh_token'];

          if (accessToken == null && uri.fragment.isNotEmpty) {
            final fragmentParams = Uri.splitQueryString(uri.fragment);
            accessToken = fragmentParams['access_token'];
            refreshToken = fragmentParams['refresh_token'];
            debugPrint('Found tokens in fragment');
          }

          if (error != null) {
            debugPrint('OAuth error: $error');
            subscription?.cancel();
            if (!completer.isCompleted) completer.complete(false);
            return;
          }

          if (code != null) {
            debugPrint('Got auth code: ${code.substring(0, 10)}..., exchanging...');
            try {
              await _client.auth.exchangeCodeForSession(code);
              debugPrint('Session exchange successful!');
              subscription?.cancel();
              if (!completer.isCompleted) completer.complete(true);
            } catch (e) {
              debugPrint('Code exchange failed: $e');
              subscription?.cancel();
              if (!completer.isCompleted) completer.complete(false);
            }
            return;
          }

          if (accessToken != null) {
            debugPrint('Got access token directly');
            try {
              await _client.auth.setSession(refreshToken ?? accessToken);
              debugPrint('Session set successful!');
              subscription?.cancel();
              if (!completer.isCompleted) completer.complete(true);
            } catch (e) {
              debugPrint('Set session failed: $e');
              subscription?.cancel();
              if (!completer.isCompleted) completer.complete(false);
            }
            return;
          }

          debugPrint('No code or token found in callback');
          subscription?.cancel();
          if (!completer.isCompleted) completer.complete(false);
        }
      }

      // Escuchar deep links en stream
      subscription = appLinks.uriLinkStream.listen(processCallback);

      // Construir URL con prompt=select_account y login_hint si disponible
      var authUrlStr = 'https://gkqcrkqaijwhiksyjekv.supabase.co/auth/v1/authorize'
          '?provider=google'
          '&redirect_to=${Uri.encodeComponent(redirectUrl)}'
          '&prompt=select_account';

      if (loginHint != null) {
        authUrlStr += '&login_hint=${Uri.encodeComponent(loginHint)}';
      }

      final authUrl = Uri.parse(authUrlStr);
      debugPrint('Opening OAuth URL: $authUrl');

      final launched = await launchUrl(
        authUrl,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        debugPrint('Failed to launch browser');
        subscription?.cancel();
        return false;
      }

      // También verificar periódicamente si hay un link pendiente
      // (por si el stream no lo capturó)
      Timer.periodic(const Duration(seconds: 1), (timer) async {
        if (completer.isCompleted) {
          timer.cancel();
          return;
        }
        try {
          final latestLink = await appLinks.getLatestLink();
          if (latestLink != null && latestLink.scheme == 'io.supabase.torodriver') {
            debugPrint('Found pending deep link via getLatestLink');
            timer.cancel();
            await processCallback(latestLink);
          }
        } catch (e) {
          // Ignore errors
        }
      });

      return await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          debugPrint('OAuth timeout after 5 minutes');
          subscription?.cancel();
          return false;
        },
      );
    } catch (e) {
      debugPrint('OAuth fallback error: $e');
      return false;
    }
  }

  /// Sign in con Google para Windows/Desktop usando puerto 5001
  Future<bool> _signInWithGoogleDesktop() async {
    HttpServer? server;
    try {
      debugPrint('=== GOOGLE OAUTH DESKTOP ===');
      debugPrint('Starting OAuth server on port $_desktopPort...');

      // Iniciar servidor HTTP en localhost:5001
      server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        _desktopPort,
        shared: true,
      );
      debugPrint('Server running on $_desktopCallbackUrl');

      // Construir URL de OAuth directo a Supabase
      final authUrl = Uri.https(
        'gkqcrkqaijwhiksyjekv.supabase.co',
        '/auth/v1/authorize',
        {
          'provider': 'google',
          'redirect_to': _desktopCallbackUrl,
        },
      );

      debugPrint('Opening: $authUrl');

      // Abrir navegador
      await launchUrl(authUrl, mode: LaunchMode.externalApplication);

      // Esperar callback
      final completer = Completer<bool>();

      server.listen((request) async {
        debugPrint('Request received: ${request.uri}');

        try {
          // Buscar access_token en el fragment (viene como query después de #)
          final fullUrl = request.uri.toString();
          debugPrint('Full URL: $fullUrl');

          // Extraer parámetros
          final queryParams = request.uri.queryParameters;
          final code = queryParams['code'];
          final error = queryParams['error'];

          // También buscar en el fragment si viene como hash
          String? accessToken;
          if (fullUrl.contains('access_token=')) {
            final tokenMatch = RegExp(r'access_token=([^&]+)').firstMatch(fullUrl);
            accessToken = tokenMatch?.group(1);
          }

          if (code != null) {
            debugPrint('Got auth code, exchanging...');
            await _client.auth.exchangeCodeForSession(code);
            _sendSuccessResponse(request);
            completer.complete(true);
          } else if (accessToken != null) {
            debugPrint('Got access token directly');
            await _client.auth.setSession(accessToken);
            _sendSuccessResponse(request);
            completer.complete(true);
          } else if (error != null) {
            debugPrint('OAuth error: $error');
            _sendErrorResponse(request, error);
            completer.complete(false);
          } else {
            // Página que extrae el token del hash y lo envía
            _sendTokenExtractorPage(request);
          }
        } catch (e) {
          debugPrint('Callback error: $e');
          _sendErrorResponse(request, e.toString());
          if (!completer.isCompleted) completer.complete(false);
        }
      });

      // Timeout 5 minutos
      return await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => false,
      );
    } catch (e) {
      debugPrint('Desktop OAuth error: $e');
      return false;
    } finally {
      await server?.close(force: true);
      debugPrint('Server closed');
    }
  }

  void _sendSuccessResponse(HttpRequest request) {
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write(_getSuccessHtml())
      ..close();
  }

  void _sendErrorResponse(HttpRequest request, String error) {
    request.response
      ..statusCode = 400
      ..headers.contentType = ContentType.html
      ..write(_getErrorHtml(error))
      ..close();
  }

  void _sendTokenExtractorPage(HttpRequest request) {
    // Página que extrae el token del hash (#access_token=...) y lo envía como query
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write('''
<!DOCTYPE html>
<html>
<head><title>Procesando...</title></head>
<body style="background:#1a1a2e;color:white;display:flex;justify-content:center;align-items:center;height:100vh;font-family:sans-serif;">
<div style="text-align:center;">
  <p>Procesando autenticación...</p>
</div>
<script>
  const hash = window.location.hash.substring(1);
  if (hash && hash.includes('access_token')) {
    window.location.href = 'http://localhost:$_desktopPort/callback?' + hash;
  } else {
    document.body.innerHTML = '<p>Error: No se encontró token</p>';
  }
</script>
</body>
</html>
''')
      ..close();
  }

  String _getSuccessHtml() {
    return '''
<!DOCTYPE html>
<html>
<head>
  <title>Login Exitoso - Toro Driver</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      display: flex;
      justify-content: center;
      align-items: center;
      height: 100vh;
      margin: 0;
      background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
      color: white;
    }
    .container {
      text-align: center;
      padding: 40px;
      background: rgba(255,255,255,0.1);
      border-radius: 20px;
      backdrop-filter: blur(10px);
    }
    .success { color: #4ade80; font-size: 60px; }
    h1 { margin: 20px 0; }
    p { color: #94a3b8; }
  </style>
</head>
<body>
  <div class="container">
    <div class="success">✓</div>
    <h1>¡Login Exitoso!</h1>
    <p>Puedes cerrar esta ventana y volver a Toro Driver</p>
  </div>
  <script>setTimeout(() => window.close(), 3000);</script>
</body>
</html>
''';
  }

  String _getErrorHtml(String error) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <title>Error - Toro Driver</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      display: flex;
      justify-content: center;
      align-items: center;
      height: 100vh;
      margin: 0;
      background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
      color: white;
    }
    .container {
      text-align: center;
      padding: 40px;
      background: rgba(255,255,255,0.1);
      border-radius: 20px;
    }
    .error { color: #f87171; font-size: 60px; }
    h1 { margin: 20px 0; }
    p { color: #94a3b8; }
  </style>
</head>
<body>
  <div class="container">
    <div class="error">✗</div>
    <h1>Error de Autenticación</h1>
    <p>$error</p>
    <p>Cierra esta ventana e intenta de nuevo</p>
  </div>
</body>
</html>
''';
  }

  // Sign out - clear all sessions completely (Supabase + Google)
  Future<void> signOut() async {
    debugPrint('=== SIGNING OUT ===');
    debugPrint('Current session before signOut: ${_client.auth.currentSession != null}');

    // Sign out from Google Sign In first (clears cached account)
    try {
      final googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();
      debugPrint('Google Sign In: signed out');
    } catch (e) {
      debugPrint('Google Sign In signOut error (ignored): $e');
    }

    // Sign out from Supabase with global scope to clear ALL sessions
    await _client.auth.signOut(scope: SignOutScope.global);

    debugPrint('Session after signOut: ${_client.auth.currentSession}');
    debugPrint('User after signOut: ${_client.auth.currentUser}');
    debugPrint('=== SIGN OUT COMPLETE ===');
  }

  // Reset password
  Future<void> resetPassword(String email) async {
    await _client.auth.resetPasswordForEmail(email);
  }

  // Update password
  Future<UserResponse> updatePassword(String newPassword) async {
    return await _client.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }

  // Create driver profile in database
  Future<void> _createDriverProfile({
    required String userId,
    required String email,
    required String firstName,
    required String lastName,
    required String phone,
  }) async {
    final now = DateTime.now().toIso8601String();
    final fullName = '$firstName $lastName'.trim();

    await _client.from(SupabaseConfig.driversTable).insert({
      'id': userId,
      'user_id': userId,
      'email': email,
      'name': fullName,
      'phone': phone,
      'rating': 0.0,
      'total_rides': 0,
      'total_earnings': 0.0,
      'is_online': false,
      'is_verified': false,
      'is_active': true,
      'status': 'pending',
      'created_at': now,
      'updated_at': now,
    });
  }

  // Get current driver profile
  Future<DriverModel?> getCurrentDriverProfile() async {
    if (currentUserId == null) return null;

    // First try to find by user ID (primary method)
    var response = await _client
        .from(SupabaseConfig.driversTable)
        .select()
        .eq('id', currentUserId!)
        .maybeSingle();

    // If not found by ID, try to find by email (fallback for legacy registrations)
    if (response == null && currentUser?.email != null) {
      response = await _client
          .from(SupabaseConfig.driversTable)
          .select()
          .eq('email', currentUser!.email!)
          .maybeSingle();
    }

    // Return null if driver profile doesn't exist (new user needs to register)
    if (response == null) return null;

    return DriverModel.fromJson(response);
  }

  // Check if user exists
  Future<bool> checkUserExists(String email) async {
    final response = await _client
        .from(SupabaseConfig.driversTable)
        .select('id')
        .eq('email', email)
        .maybeSingle();

    return response != null;
  }

  // Delete account
  Future<void> deleteAccount() async {
    if (currentUserId == null) return;

    // Delete driver data
    await _client
        .from(SupabaseConfig.driversTable)
        .delete()
        .eq('id', currentUserId!);

    // Sign out
    await signOut();
  }
}
