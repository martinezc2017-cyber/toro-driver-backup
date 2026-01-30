import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
// Firebase disabled for Windows build - uncomment for mobile release
// import 'package:firebase_core/firebase_core.dart';

// Config
import 'src/config/supabase_config.dart';
import 'src/services/payment_service.dart';
import 'src/services/mapbox_navigation_service.dart';
import 'src/services/update_service.dart';

// Theme
import 'src/utils/app_theme.dart';
import 'src/utils/app_colors.dart';
import 'src/utils/haptic_service.dart';

// Providers
import 'src/providers/auth_provider.dart';
import 'src/providers/driver_provider.dart';
import 'src/providers/ride_provider.dart';
import 'src/providers/location_provider.dart';
import 'src/providers/earnings_provider.dart';

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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set Mapbox access token BEFORE any MapWidget is created
  MapboxOptions.setAccessToken('pk.eyJ1IjoibWFydGluZXpjMjAxNyIsImEiOiJjbWtocWtoZHIwbW1iM2dvdXZ3bmp0ZjBiIn0.MjYgv6DuvLTkrBVbrhtFbg');

  // Set system UI overlay style for futuristic dark theme
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.surface,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Initialize services
  await _initializeServices();

  await EasyLocalization.ensureInitialized();

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('es')],
      path: 'assets/lang',
      fallbackLocale: const Locale('es'),
      saveLocale: true,
      useOnlyLangCode: true,
      child: const ToroDriverApp(),
    ),
  );
}

Future<void> _initializeServices() async {
  // Firebase disabled for Windows build - uncomment for mobile release
  // try {
  //   await Firebase.initializeApp();
  // } catch (e) {
  //   debugPrint('Firebase not configured, skipping: $e');
  // }

  // Initialize Supabase
  await SupabaseConfig.initialize();

  // Initialize Stripe (optional - skip if not configured)
  try {
    await PaymentService.initialize();
  } catch (e) {
    // Stripe not configured, skipping
  }

  // Initialize Haptic Service
  await HapticService.initialize();

  // Initialize Mapbox (set access token before any MapWidget is created)
  await MapboxNavigationService().initialize();
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
      ],
      child: MaterialApp(
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
          '/driver-agreement': (context) => const DriverAgreementScreen(),
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
  bool _checkingUpdate = false;

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return AnimatedSplash(
        title: 'TORO',
        subtitle: 'DRIVER',
        duration: const Duration(milliseconds: 3500),
        onComplete: () async {
          if (mounted) {
            setState(() {
              _showSplash = false;
              _checkingUpdate = true;
            });
            await _checkForUpdates();
          }
        },
      );
    }

    if (_checkingUpdate) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A0A),
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

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
      // Error checking for updates
    } finally {
      if (mounted) {
        setState(() => _checkingUpdate = false);
      }
    }
  }
}
