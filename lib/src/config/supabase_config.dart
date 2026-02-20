import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  // Supabase project credentials
  static const String supabaseUrl = 'https://gkqcrkqaijwhiksyjekv.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdrcWNya3FhaWp3aGlrc3lqZWt2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjcyMjA0NTYsImV4cCI6MjA4Mjc5NjQ1Nn0.QmYXkhPndrUgInC8pdr7wdROVeh69BtbeICZbFV7Rno';

  // Google OAuth Web Client ID
  // ==========================================================================
  // NOTA: Este campo solo es necesario para LOGIN CON GOOGLE EN WEB.
  // Para Android/iOS nativo, el OAuth funciona sin este ID (usa native flow).
  //
  // Si necesitas habilitarlo para web:
  // 1. Ve a Google Cloud Console > APIs & Services > Credentials
  // 2. Crea un OAuth 2.0 Client ID tipo "Web application"
  // 3. Agrega los Authorized redirect URIs:
  //    - https://gkqcrkqaijwhiksyjekv.supabase.co/auth/v1/callback
  // 4. Copia el Client ID aquí
  // 5. Configura el mismo Client ID en Supabase Dashboard > Auth > Providers > Google
  // ==========================================================================
  static const String googleWebClientId = '732187337384-3tg9j5qq6al4jjkcnt89t3p6b9d49qe6.apps.googleusercontent.com';

  // Puerto para OAuth callback en Windows Desktop
  static const int desktopAuthPort = 5001;

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() async {
    // Pre-flight: test if Android Keystore is healthy BEFORE Supabase tries to use it.
    // If corrupted (debug/release switch, system update), clear storage proactively
    // so Supabase starts fresh instead of crashing on a stale/unreadable token.
    if (!kIsWeb) {
      await _checkKeystoreHealth();
    }

    try {
      await _doInitialize();
    } catch (e) {
      final errorStr = e.toString();

      // Android Keystore corruption (e.g. switching between release/debug APKs)
      // flutter_secure_storage fails with "unwrap key failed" or "BadPaddingException"
      if (errorStr.contains('unwrap key') ||
          errorStr.contains('BadPaddingException') ||
          errorStr.contains('StorageCipher') ||
          errorStr.contains('InvalidKeyException') ||
          errorStr.contains('KeyStoreException')) {
        debugPrint('[SUPABASE] Keystore corrupted — clearing secure storage and retrying');
        try {
          const storage = FlutterSecureStorage();
          await storage.deleteAll();
        } catch (_) {}
        // Retry after clearing corrupted keys
        try {
          await _doInitialize();
        } catch (retryError) {
          debugPrint('[SUPABASE] Retry also failed: $retryError');
          // Still continue — app will show login screen
        }
        return;
      }

      // Session recovery can fail with invalid/stale refresh tokens
      // (e.g., after global signOut from another device, or token expiry)
      if (errorStr.contains('refresh_token_not_found') ||
          errorStr.contains('Invalid Refresh Token')) {
        debugPrint('[SUPABASE] Stale refresh token — signing out');
        try {
          await Supabase.instance.client.auth.signOut();
        } catch (_) {}
        return;
      }

      // Unknown error — log but don't crash
      debugPrint('[SUPABASE] Init error: $e');
    }
  }

  /// Test if flutter_secure_storage can read/write.
  /// If the Android Keystore is corrupted, this will fail and we clear everything
  /// BEFORE Supabase tries to restore a session with an unreadable token.
  static Future<void> _checkKeystoreHealth() async {
    try {
      const storage = FlutterSecureStorage();
      const testKey = '_keystore_health_check';
      await storage.write(key: testKey, value: 'ok');
      final value = await storage.read(key: testKey);
      await storage.delete(key: testKey);
      if (value != 'ok') throw Exception('read mismatch');
      debugPrint('[KEYSTORE] Health check passed');
    } catch (e) {
      debugPrint('[KEYSTORE] Health check FAILED: $e — clearing all secure storage');
      try {
        const storage = FlutterSecureStorage();
        await storage.deleteAll();
        debugPrint('[KEYSTORE] Cleared. User will need to re-login.');
      } catch (clearError) {
        debugPrint('[KEYSTORE] Could not clear: $clearError');
      }
    }
  }

  static Future<void> _doInitialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        authFlowType: kIsWeb ? AuthFlowType.implicit : AuthFlowType.pkce,
        autoRefreshToken: true,
      ),
      realtimeClientOptions: const RealtimeClientOptions(
        logLevel: RealtimeLogLevel.info,
      ),
    );
  }

  // Database table names
  static const String driversTable = 'drivers';
  static const String ridesTable = 'rides';
  static const String vehiclesTable = 'vehicles';
  static const String documentsTable = 'documents';
  static const String earningsTable = 'earnings';
  static const String messagesTable = 'messages';
  static const String ratingsTable = 'ratings';
  static const String referralsTable = 'referrals';
  static const String notificationsTable = 'notifications';
  static const String locationsTable = 'driver_locations';
  static const String conversationsTable = 'conversations';

  // Package delivery tables - 'deliveries' is the unified table for rides, packages, and carpools
  static const String packageDeliveriesTable = 'deliveries';
  static const String driverTicketsTable = 'driver_tickets';
  static const String deliveryMessagesTable = 'delivery_messages';
  static const String earningsReportTable = 'driver_earnings_report';
  static const String bankAccountsTable = 'bank_accounts';
  static const String stripeAccountsTable = 'driver_stripe_accounts';
  static const String payoutsTable = 'payouts';

  // Storage buckets
  static const String profileImagesBucket = 'driver-documents';
  static const String documentsBucket = 'documents';
  static const String vehicleImagesBucket = 'vehicle-images';
}
