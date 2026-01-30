import 'dart:async';
import 'dart:io' show ContentType, HttpRequest, HttpServer, InternetAddress, Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
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
      // Check if desktop platform (only access Platform when NOT on web)
      bool isDesktop = false;
      bool isMobile = false;
      if (!kIsWeb) {
        isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
        isMobile = Platform.isAndroid || Platform.isIOS;
      }

      if (isDesktop) {
        return await _signInWithGoogleDesktop();
      }

      if (isMobile) {
        return await _signInWithGoogleMobile();
      }

      // En producción usar URL de Cloudflare, en desarrollo usar localhost
      final isProduction = Uri.base.host.contains('pages.dev') ||
                           Uri.base.host.contains('toro-ride.com') ||
                           Uri.base.host.contains('toro-driver');
      final redirectUrl = isProduction
          ? Uri.base.origin
          : 'https://toro-driver.pages.dev';

      final response = await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectUrl,
      );
      return response;
    } catch (e) {
      return false;
    }
  }

  /// Sign in con Google para Android/iOS usando Google Sign In nativo
  /// FUERZA el selector de cuentas a aparecer siempre
  Future<bool> _signInWithGoogleMobile() async {
    try {
      // Web Client ID from config
      final webClientId = SupabaseConfig.googleWebClientId;

      // Si no hay Web Client ID configurado, usar método OAuth estándar
      if (webClientId.isEmpty) {
        return await _signInWithGoogleMobileOAuth();
      }

      final googleSignIn = GoogleSignIn(
        serverClientId: webClientId,
        scopes: ['email', 'profile'],
      );

      // IMPORTANTE: Primero hacer signOut para forzar el selector de cuentas
      await googleSignIn.signOut();

      // Ahora hacer signIn - esto SIEMPRE mostrará el selector de cuentas
      final googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        return false;
      }

      // Obtener tokens de autenticación
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null) {
        // Fallback: usar OAuth con login_hint del email seleccionado
        return await _signInWithGoogleMobileOAuth(loginHint: googleUser.email);
      }

      // Usar el ID token para autenticarse con Supabase
      final response = await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      if (response.session != null) {
        return true;
      } else {
        return false;
      }
    } catch (e) {
      // Fallback al método OAuth estándar
      return await _signInWithGoogleMobileOAuth();
    }
  }

  /// Fallback: OAuth estándar con deep links
  Future<bool> _signInWithGoogleMobileOAuth({String? loginHint}) async {
    try {
      // Primero, limpiar cualquier sesión de Google Sign In anterior
      try {
        final googleSignIn = GoogleSignIn();
        await googleSignIn.signOut();
      } catch (e) {
        // Ignore cache clear errors
      }

      const redirectUrl = 'io.supabase.torodriver://login-callback/';

      // Set up deep link listener
      final appLinks = AppLinks();
      final completer = Completer<bool>();
      StreamSubscription<Uri>? subscription;

      // Función para procesar el URI del callback
      Future<void> processCallback(Uri uri) async {
        if (uri.scheme == 'io.supabase.torodriver') {
          final code = uri.queryParameters['code'];
          final error = uri.queryParameters['error'];

          String? accessToken = uri.queryParameters['access_token'];
          String? refreshToken = uri.queryParameters['refresh_token'];

          if (accessToken == null && uri.fragment.isNotEmpty) {
            final fragmentParams = Uri.splitQueryString(uri.fragment);
            accessToken = fragmentParams['access_token'];
            refreshToken = fragmentParams['refresh_token'];
          }

          if (error != null) {
            subscription?.cancel();
            if (!completer.isCompleted) completer.complete(false);
            return;
          }

          if (code != null) {
            try {
              await _client.auth.exchangeCodeForSession(code);
              subscription?.cancel();
              if (!completer.isCompleted) completer.complete(true);
            } catch (e) {
              subscription?.cancel();
              if (!completer.isCompleted) completer.complete(false);
            }
            return;
          }

          if (accessToken != null) {
            try {
              await _client.auth.setSession(refreshToken ?? accessToken);
              subscription?.cancel();
              if (!completer.isCompleted) completer.complete(true);
            } catch (e) {
              subscription?.cancel();
              if (!completer.isCompleted) completer.complete(false);
            }
            return;
          }

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

      final launched = await launchUrl(
        authUrl,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        subscription.cancel();
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
          subscription?.cancel();
          return false;
        },
      );
    } catch (e) {
      return false;
    }
  }

  /// Sign in con Google para Windows/Desktop usando puerto 5001
  Future<bool> _signInWithGoogleDesktop() async {
    HttpServer? server;
    try {
      // Iniciar servidor HTTP en localhost:5001
      server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        _desktopPort,
        shared: true,
      );

      // Construir URL de OAuth directo a Supabase
      final authUrl = Uri.https(
        'gkqcrkqaijwhiksyjekv.supabase.co',
        '/auth/v1/authorize',
        {
          'provider': 'google',
          'redirect_to': _desktopCallbackUrl,
        },
      );

      // Abrir navegador
      await launchUrl(authUrl, mode: LaunchMode.externalApplication);

      // Esperar callback
      final completer = Completer<bool>();

      server.listen((request) async {
        try {
          // Buscar access_token en el fragment (viene como query después de #)
          final fullUrl = request.uri.toString();

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
            await _client.auth.exchangeCodeForSession(code);
            _sendSuccessResponse(request);
            completer.complete(true);
          } else if (accessToken != null) {
            await _client.auth.setSession(accessToken);
            _sendSuccessResponse(request);
            completer.complete(true);
          } else if (error != null) {
            _sendErrorResponse(request, error);
            completer.complete(false);
          } else {
            // Página que extrae el token del hash y lo envía
            _sendTokenExtractorPage(request);
          }
        } catch (e) {
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
      return false;
    } finally {
      await server?.close(force: true);
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
    // Sign out from Google Sign In first (clears cached account)
    try {
      final googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();
    } catch (e) {
      // Ignore Google Sign In signOut errors
    }

    // Sign out from Supabase with global scope to clear ALL sessions
    await _client.auth.signOut(scope: SignOutScope.global);
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
