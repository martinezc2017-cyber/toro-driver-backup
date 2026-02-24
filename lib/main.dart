import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Config
import 'src/config/supabase_config.dart';
import 'src/services/payment_service.dart';
import 'src/services/mapbox_navigation_service.dart';
import 'src/services/update_service.dart';
import 'src/services/app_state_validator.dart';
import 'src/services/notification_service.dart';
import 'src/services/version_check_service.dart';
import 'src/services/background_location_service.dart';

// Theme
import 'src/utils/app_theme.dart';
import 'src/utils/app_colors.dart';
import 'src/utils/haptic_service.dart';

// In-app banner
import 'src/services/in_app_banner_service.dart';

// Providers
import 'src/providers/auth_provider.dart';
import 'src/providers/driver_provider.dart';
import 'src/providers/ride_provider.dart';
import 'src/providers/location_provider.dart';
import 'src/providers/earnings_provider.dart';
import 'src/providers/cash_account_provider.dart';

// Screens
import 'src/screens/home_screen.dart';
import 'src/screens/navigation_screen.dart';
import 'src/screens/profile_screen.dart';
import 'src/screens/history_screen.dart';
import 'src/screens/settings_screen.dart';
import 'src/screens/legal_screen.dart';
import 'src/screens/terms_acceptance_screen.dart';
import 'src/screens/account_screen.dart';
import 'src/screens/rides_screen.dart';
import 'src/screens/ranking_screen.dart';
import 'src/screens/earnings_screen.dart';
import 'src/screens/vehicle_screen.dart';
import 'src/screens/support_screen.dart';
import 'src/screens/documents_screen.dart';
import 'src/screens/refer_screen.dart';
import 'src/screens/language_screen.dart';
import 'src/screens/login_screen.dart';
import 'src/screens/auth_wrapper.dart';
import 'src/screens/notifications_screen.dart';
// map_screen.dart eliminado - usar home_screen.dart
import 'src/screens/messages_screen.dart';
import 'src/screens/bank_account_screen.dart';
import 'src/screens/add_vehicle_screen.dart';
import 'src/screens/driver_agreement_screen.dart';
import 'src/widgets/animated_splash.dart';
import 'features/splash/toro_splash_screen.dart';
// Driver credential
import 'src/screens/driver_credential_screen.dart';
// Mexico screens
import 'src/screens/mexico_documents_screen.dart';
import 'src/screens/mexico_tax_screen.dart';
import 'src/screens/mexico_invoices_screen.dart';
// Organizer screens
import 'src/screens/organizer/organizer_profile_screen.dart';
// Tourism screens
import 'src/screens/tourism/vehicle_request_screen.dart';
import 'src/screens/tourism/driver_bid_screen.dart';

/// FCM background handler - must be top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('FCM Background message: ${message.messageId}');
}

final _mainSw = Stopwatch();

void main() async {
  _mainSw.start();
  debugPrint('[MAIN] start at ${_mainSw.elapsedMilliseconds}ms');
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[MAIN] binding done at ${_mainSw.elapsedMilliseconds}ms');

  // Set Mapbox access token BEFORE any MapWidget is created (mobile only)
  if (!kIsWeb) {
    MapboxOptions.setAccessToken('pk.eyJ1IjoibWFydGluZXpjMjAxNyIsImEiOiJjbWtocWtoZHIwbW1iM2dvdXZ3bmp0ZjBiIn0.MjYgv6DuvLTkrBVbrhtFbg');
  }

  // Set system UI overlay style for futuristic dark theme (mobile only)
  if (!kIsWeb) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.surface,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  }

  // EasyLocalization needs to init before runApp (lightweight)
  await EasyLocalization.ensureInitialized();
  debugPrint('[MAIN] EasyLocalization done at ${_mainSw.elapsedMilliseconds}ms');

  debugPrint('[MAIN] runApp at ${_mainSw.elapsedMilliseconds}ms');
  // Run app IMMEDIATELY so splash shows while services init in background
  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('es'), Locale('es', 'MX')],
      path: 'assets/lang',
      startLocale: const Locale('es'),
      fallbackLocale: const Locale('es'),
      saveLocale: true,
      useOnlyLangCode: false, // Allow country codes for es-MX
      child: const ToroDriverApp(),
    ),
  );
}

/// Phase 1: Only Firebase + Supabase (blocks splash)
Future<void> _initCriticalServices() async {
  final sw = Stopwatch()..start();

  // Run Firebase and Supabase in PARALLEL — they are independent SDKs
  await Future.wait([
    // Firebase (skip on web — no firebase_options.dart for web)
    if (!kIsWeb) () async {
      try {
        await Firebase.initializeApp();
        FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
        debugPrint('[SERVICES] Firebase done at ${sw.elapsedMilliseconds}ms');
      } catch (e) {
        debugPrint('[SERVICES] Firebase skipped: $e');
      }
    }(),
    // Supabase
    () async {
      try {
        await SupabaseConfig.initialize();
        debugPrint('[SERVICES] Supabase done at ${sw.elapsedMilliseconds}ms');
      } catch (e) {
        debugPrint('[SERVICES] Supabase init error: $e');
        // Don't try to access client if init failed — it may not exist
      }
    }(),
  ]);
  debugPrint('[SERVICES] CRITICAL done at ${sw.elapsedMilliseconds}ms');
}

/// Phase 2: Everything else (runs AFTER splash, non-blocking)
void _initBackgroundServices() {
  final sw = Stopwatch()..start();
  // Fire all in parallel, none blocks the UI
  Future.wait([
    () async {
      await VersionCheckService().init();
      debugPrint('[BG_SERVICES] VersionCheck done at ${sw.elapsedMilliseconds}ms');
    }(),
    () async {
      await AppStateValidator.instance.initialize();
      debugPrint('[BG_SERVICES] AppStateValidator done at ${sw.elapsedMilliseconds}ms');
    }(),
    () async {
      try {
        await PaymentService.initialize();
        debugPrint('[BG_SERVICES] PaymentService done at ${sw.elapsedMilliseconds}ms');
      } catch (e) {
        debugPrint('[BG_SERVICES] PaymentService skipped: $e');
      }
    }(),
    if (!kIsWeb) () async {
      try {
        await NotificationService().initialize().timeout(
          const Duration(seconds: 5),
          onTimeout: () => debugPrint('[BG_SERVICES] NotificationService TIMEOUT (5s)'),
        );
        debugPrint('[BG_SERVICES] NotificationService done at ${sw.elapsedMilliseconds}ms');
      } catch (e) {
        debugPrint('[BG_SERVICES] NotificationService error: $e');
      }
    }(),
    () async {
      await HapticService.initialize();
      debugPrint('[BG_SERVICES] HapticService done at ${sw.elapsedMilliseconds}ms');
    }(),
    if (!kIsWeb) () async {
      try {
        await MapboxNavigationService().initialize();
        debugPrint('[BG_SERVICES] Mapbox done at ${sw.elapsedMilliseconds}ms');
      } catch (e) {
        debugPrint('[BG_SERVICES] Mapbox error: $e');
      }
    }(),
    if (!kIsWeb) () async {
      try {
        await initializeBackgroundLocationService();
        debugPrint('[BG_SERVICES] BackgroundLocation done at ${sw.elapsedMilliseconds}ms');
      } catch (e) {
        debugPrint('[BG_SERVICES] BackgroundLocation error: $e');
      }
    }(),
  ]).then((_) => debugPrint('[BG_SERVICES] ALL DONE at ${sw.elapsedMilliseconds}ms'));
}

class ToroDriverApp extends StatelessWidget {
  const ToroDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => DriverProvider()),
        ChangeNotifierProvider(create: (_) => RideProvider()),
        ChangeNotifierProvider(create: (_) => LocationProvider()),
        ChangeNotifierProvider(create: (_) => EarningsProvider()),
        ChangeNotifierProvider(create: (_) => CashAccountProvider()),
      ],
      child: MaterialApp(
        navigatorKey: InAppBannerService.navigatorKey,
        title: 'Toro Driver',
        debugShowCheckedModeBanner: false,
        // Futuristic Dark Theme - Uber Style
        theme: AppTheme.darkTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        home: const _SplashWrapper(),
        routes: {
          '/auth': (context) => const AuthWrapper(), // Direct to auth after terms
          '/home': (context) => const HomeScreen(),
          '/login': (context) => const LoginScreen(),
          '/terms': (context) => const TermsAcceptanceScreen(),
          '/navigation': (context) => const NavigationScreen(),
          '/profile': (context) => const ProfileScreen(),
          '/history': (context) => const HistoryScreen(),
          '/settings': (context) => const SettingsScreen(),
          '/legal': (context) => const LegalScreen(),
          '/account': (context) => const AccountScreen(),
          '/rides': (context) => const RidesScreen(),
          '/ranking': (context) => const RankingScreen(),
          '/earnings': (context) => const EarningsScreen(),
          '/vehicle': (context) => const VehicleScreen(),
          '/support': (context) => const SupportScreen(),
          '/documents': (context) => const DocumentsScreen(),
          '/refer': (context) => const ReferScreen(),
          '/language': (context) => const LanguageScreen(),
          '/notifications': (context) => const NotificationsScreen(),
          '/messages': (context) => const MessagesScreen(),
          '/bank-account': (context) => const BankAccountScreen(),
          '/add-vehicle': (context) => const AddVehicleScreen(),
          '/add-vehicle-tourism': (context) => const AddVehicleScreen(forTourism: true),
          '/driver-agreement': (context) => const DriverAgreementScreen(),
          // Driver credential
          '/driver-credential': (context) => const DriverCredentialScreen(),
          // Mexico routes
          '/mexico-documents': (context) => const MexicoDocumentsScreen(),
          '/mexico-tax': (context) => const MexicoTaxScreen(),
          '/mexico-invoices': (context) => const MexicoInvoicesScreen(),
          // Organizer routes
          '/organizer-profile': (context) => const OrganizerProfileScreen(),
          // Tourism routes
          '/vehicle-requests': (context) => const VehicleRequestScreen(),
          '/driver-bids': (context) => const DriverBidScreen(),
          '/logout': (context) => _buildLogoutScreen(context),
        },
      ),
    );
  }

  Widget _buildLogoutScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.3),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.error.withValues(alpha: 0.2),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.error,
                          AppColors.error.withValues(alpha: 0.7),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.error.withValues(alpha: 0.4),
                          blurRadius: 20,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.logout_rounded,
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '¿Cerrar Sesión?',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '¿Estás seguro que deseas salir de tu cuenta?',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            HapticService.lightImpact();
                            Navigator.pop(context);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppColors.border,
                                width: 1.5,
                              ),
                            ),
                            child: const Center(
                              child: Text(
                                'Cancelar',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            HapticService.mediumImpact();
                            final authProvider = Provider.of<AuthProvider>(
                              context,
                              listen: false,
                            );
                            await authProvider.signOut();
                            if (context.mounted) {
                              Navigator.pushNamedAndRemoveUntil(
                                context,
                                '/login',
                                (route) => false,
                              );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.error,
                                  AppColors.error.withValues(alpha: 0.8),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.error.withValues(alpha: 0.4),
                                  blurRadius: 15,
                                  spreadRadius: 0,
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Text(
                                'Salir',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Splash screen wrapper - shows animated splash then navigates to AuthWrapper
class _SplashWrapper extends StatefulWidget {
  const _SplashWrapper();

  @override
  State<_SplashWrapper> createState() => _SplashWrapperState();
}

class _SplashWrapperState extends State<_SplashWrapper> {
  bool _showSplash = true;
  /// Tells AnimatedSplash when to start its exit fade
  final _exitSplash = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    debugPrint('[WRAPPER] initState at ${_mainSw.elapsedMilliseconds}ms');
    // Initialize services + update check IN PARALLEL with splash animation
    _initAllInBackground();
  }

  Future<void> _initAllInBackground() async {
    debugPrint('[WRAPPER] services START at ${_mainSw.elapsedMilliseconds}ms');

    try {
      // Wait for BOTH: critical services AND minimum splash display time.
      // Safety timeout of 12s prevents splash from getting stuck forever.
      await Future.wait([
        _initCriticalServices(),
        Future.delayed(const Duration(milliseconds: 5500)), // min 5.5s splash
      ]).timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          debugPrint('[WRAPPER] TIMEOUT after 12s — forcing splash exit');
          return [null, null];
        },
      );
    } catch (e) {
      debugPrint('[WRAPPER] init error: $e — forcing splash exit');
    }

    debugPrint('[WRAPPER] ready at ${_mainSw.elapsedMilliseconds}ms');

    // Tell splash it can now exit (always, even on error/timeout)
    if (mounted) {
      _exitSplash.value = true;
    }

    // Fire background services + update check (non-blocking)
    _initBackgroundServices();
    _checkForUpdates();
  }

  @override
  void dispose() {
    _exitSplash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return ToroSplashScreen(
        onComplete: () {
          debugPrint('[WRAPPER] onComplete → AuthWrapper at ${_mainSw.elapsedMilliseconds}ms');
          setState(() => _showSplash = false);
        },
      );
    }

    // Go directly to AuthWrapper - no intermediate spinners
    return const AuthWrapper();
  }

  Future<void> _checkForUpdates() async {
    try {
      final updateService = UpdateService();
      await updateService.initialize();
      final updateInfo = await updateService.checkForUpdate();

      if (updateInfo != null && mounted) {
        await UpdateService.showUpdateDialog(context, updateInfo);
      }
    } catch (e) {
      // Error checking for updates - non-blocking
    }
  }
}
