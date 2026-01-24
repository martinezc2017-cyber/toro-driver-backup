import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../providers/driver_provider.dart';
import '../providers/ride_provider.dart';
import '../providers/earnings_provider.dart';
import '../models/driver_model.dart';
import '../utils/app_colors.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'pending_approval_screen.dart';
import 'terms_acceptance_screen.dart';
// AccountChoiceScreen removed - users go directly to Home
// Go Online button is blocked until documents complete

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  // BYPASS: Cambia a true para saltar login en pruebas
  static const bool bypassAuth = false;
  // ID Format: A=Admin, U=User + YYYYMMDD + sequential number
  static const String testDriverId = 'A20251231001';

  // Key for local terms acceptance
  static const String termsAcceptedKey = 'toro_driver_terms_accepted_v1';

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool? _localTermsAccepted;
  bool _checkingLocalTerms = true;

  @override
  void initState() {
    super.initState();
    // Check local terms acceptance
    _checkLocalTermsAcceptance();
    // Defer initialization to avoid calling during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeProviders();
    });
  }

  Future<void> _checkLocalTermsAcceptance() async {
    final prefs = await SharedPreferences.getInstance();
    final accepted = prefs.getBool(AuthWrapper.termsAcceptedKey) ?? false;
    if (mounted) {
      setState(() {
        _localTermsAccepted = accepted;
        _checkingLocalTerms = false;
      });
    }
  }

  Future<void> _initializeProviders() async {
    // If bypass is enabled, use test driver ID
    if (AuthWrapper.bypassAuth) {
      final driverId = AuthWrapper.testDriverId;
      context.read<DriverProvider>().initialize(driverId);
      context.read<RideProvider>().initialize(driverId);
      context.read<EarningsProvider>().initialize(driverId);
      return;
    }

    final authProvider = context.read<AuthProvider>();

    // Wait for auth to be ready
    if (authProvider.isAuthenticated && authProvider.driverId != null) {
      final driverId = authProvider.driverId!;

      // Initialize other providers with driver ID
      context.read<DriverProvider>().initialize(driverId);
      context.read<RideProvider>().initialize(driverId);
      context.read<EarningsProvider>().initialize(driverId);
    }
  }

  @override
  Widget build(BuildContext context) {
    // BYPASS: Skip auth and go directly to home
    if (AuthWrapper.bypassAuth) {
      return const HomeScreen();
    }

    // Show loading while checking local terms
    if (_checkingLocalTerms) {
      return _buildLoadingScreen();
    }

    // FIRST: Check if terms accepted locally (before login)
    if (_localTermsAccepted != true) {
      return const TermsAcceptanceScreen();
    }

    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        // Show loading while checking auth status
        if (authProvider.status == AuthStatus.initial ||
            authProvider.status == AuthStatus.loading) {
          return _buildLoadingScreen();
        }

        // Show login if not authenticated
        if (!authProvider.isAuthenticated) {
          return const LoginScreen();
        }

        // Check if user is registered as a driver
        final driver = authProvider.driver;

        // Initialize providers if driver exists
        if (driver != null && authProvider.driverId != null) {
          // Check driver status - only block if suspended or rejected
          final driverStatus = driver.status;
          if (driverStatus == DriverStatus.suspended || driverStatus == DriverStatus.rejected) {
            return const PendingApprovalScreen();
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            final driverId = authProvider.driverId!;
            context.read<DriverProvider>().initialize(driverId);
            context.read<RideProvider>().initialize(driverId);
            context.read<EarningsProvider>().initialize(driverId);
          });
        }

        // Go to Home - driver can complete registration from Profile → Documents
        // Go Online button is already blocked until all documents are complete
        return const HomeScreen();
      },
    );
  }

  Widget _buildLoadingScreen() {
    // Simple loading indicator - no logo/text to avoid looking like another splash
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 3,
          ),
        ),
      ),
    );
  }
}
