import 'package:flutter/foundation.dart' show kIsWeb;
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
  static const String googleWebClientId = '';

  // Puerto para OAuth callback en Windows Desktop
  static const int desktopAuthPort = 5001;

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        // Use implicit flow for web (better OAuth support), PKCE for mobile
        authFlowType: kIsWeb ? AuthFlowType.implicit : AuthFlowType.pkce,
        // Auto refresh token
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
  static const String profileImagesBucket = 'profile-images';
  static const String documentsBucket = 'documents';
  static const String vehicleImagesBucket = 'vehicle-images';
}
