import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/legal/consent_service.dart';
import '../core/legal/legal_constants.dart';
import '../core/logging/app_logger.dart';
import '../config/supabase_config.dart';
import '../providers/auth_provider.dart';
import '../providers/driver_provider.dart';
import '../providers/ride_provider.dart';
import '../providers/earnings_provider.dart';
import '../models/driver_model.dart';
import '../utils/app_colors.dart';
import 'home_screen.dart';
import 'organizer/organizer_home_screen.dart';
import 'tourism/tourism_driver_home_screen.dart';
import 'login_screen.dart';
import 'pending_approval_screen.dart';
import 'terms_acceptance_screen.dart';
import 'driver_onboarding_screen.dart';
import 'permissions_gate_screen.dart';
import '../services/version_check_service.dart';
import '../widgets/version_check_dialog.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  static const bool bypassAuth = false;
  static const String testDriverId = 'A20251231001';

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool? _localTermsAccepted;
  bool _checkingLocalTerms = true;
  String? _initializedDriverId;
  bool _initCallbackScheduled = false;

  @override
  void initState() {
    super.initState();
    _checkLocalTermsAcceptance();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeProviders();
      _checkAppVersion();
      // Try to sync any pending consent records
      ConsentService.instance.initialize().then((_) {
        ConsentService.instance.syncPendingConsents();
      });
    });
  }

  Future<void> _checkLocalTermsAcceptance() async {
    final prefs = await SharedPreferences.getInstance();
    final accepted = prefs.getBool(LegalConstants.termsAcceptedKey) ?? false;
    final acceptedVersion = prefs.getString(LegalConstants.termsVersionKey);
    final acceptedLanguage = prefs.getString(LegalConstants.termsLanguageKey);

    bool needsReAccept = false;

    if (accepted) {
      // Check version mismatch - force re-acceptance on new legal bundle
      if (acceptedVersion != null && acceptedVersion != LegalConstants.legalBundleVersion) {
        AppLogger.log('LEGAL_CHECK -> Version mismatch: accepted=$acceptedVersion current=${LegalConstants.legalBundleVersion}');
        needsReAccept = true;
      }

      // Check language change - if user changed language, must re-accept in new language
      if (acceptedLanguage != null && mounted) {
        try {
          final currentLang = context.locale.languageCode;
          final acceptedLang = acceptedLanguage.split('_').first.split('-').first;
          if (currentLang != acceptedLang) {
            AppLogger.log('LEGAL_CHECK -> Language changed: accepted=$acceptedLang current=$currentLang');
            needsReAccept = true;
          }
        } catch (_) {
          // EasyLocalization might not be ready yet
        }
      }
    }

    if (mounted) {
      setState(() {
        _localTermsAccepted = accepted && !needsReAccept;
        _checkingLocalTerms = false;
      });
    }
  }

  Future<void> _initializeProviders() async {
    if (AuthWrapper.bypassAuth) {
      final driverId = AuthWrapper.testDriverId;
      context.read<DriverProvider>().initialize(driverId);
      context.read<RideProvider>().initialize(driverId);
      context.read<EarningsProvider>().initialize(driverId);
      return;
    }

    final authProvider = context.read<AuthProvider>();
    if (authProvider.isAuthenticated && authProvider.driverId != null) {
      _initDriverProviders(authProvider.driverId!);
    }
  }

  Future<void> _checkAppVersion() async {
    try {
      final result = await VersionCheckService().checkVersion(appName: 'toro_driver');
      if (!result.isUpToDate && mounted) {
        await VersionCheckDialog.show(context, result);
      }
    } catch (_) {}
  }

  void _initDriverProviders(String driverId) {
    if (_initializedDriverId == driverId) return;
    _initializedDriverId = driverId;
    context.read<DriverProvider>().initialize(driverId);
    context.read<RideProvider>().initialize(driverId);
    context.read<EarningsProvider>().initialize(driverId);
  }

  @override
  Widget build(BuildContext context) {
    if (AuthWrapper.bypassAuth) {
      return const HomeScreen();
    }

    if (_checkingLocalTerms) {
      return _buildLoadingScreen();
    }

    if (_localTermsAccepted != true) {
      return const TermsAcceptanceScreen();
    }

    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        if (authProvider.status == AuthStatus.initial) {
          return _buildLoadingScreen();
        }

        if (!authProvider.isAuthenticated) {
          _initializedDriverId = null;
          return const LoginScreen();
        }

        final driver = authProvider.driver;

        // CRITICAL: If authenticated but no driver profile, go to onboarding
        // This prevents the loop where HomeScreen tries to use null driver
        if (driver == null) {
          final email = Supabase.instance.client.auth.currentUser?.email ?? 'NO EMAIL';
          final uid = Supabase.instance.client.auth.currentUser?.id ?? 'NO UID';
          debugPrint('[AUTH_WRAPPER] Authenticated as: $email (uid: $uid) but no driver profile - going to onboarding');
          return const DriverOnboardingScreen();
        }

        final driverStatus = driver.status;
        if (driverStatus == DriverStatus.suspended || driverStatus == DriverStatus.rejected) {
          return const PendingApprovalScreen();
        }

        // Initialize providers only once per driver ID - prevent scheduling multiple callbacks
        final driverId = driver.id;
        if (_initializedDriverId != driverId && !_initCallbackScheduled) {
          _initCallbackScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _initCallbackScheduled = false;
            if (mounted) {
              _initDriverProviders(driverId);
            }
          });
        }

        if (driver.vehicleMode == 'tourism' && driver.activeTourismEventId != null) {
          // Wrap in try-catch builder to prevent crash loop if event is invalid/limbo
          return PermissionsGateScreen(
            child: _SafeTourismWrapper(eventId: driver.activeTourismEventId!),
          );
        }

        // Organizers go directly to OrganizerHomeScreen — skip driver HomeScreen
        if (driver.role == 'organizer') {
          return PermissionsGateScreen(
            child: Scaffold(
              backgroundColor: AppColors.background,
              body: OrganizerHomeScreen(onSwitchToDriverMode: null),
            ),
          );
        }

        return const PermissionsGateScreen(child: HomeScreen());
      },
    );
  }

  Widget _buildLoadingScreen() {
    // Just dark background - no spinner. Splash already covers the loading time,
    // this only shows for a brief moment during auth state resolution.
    return const Scaffold(
      backgroundColor: Color(0xFF030B1A),
    );
  }
}

/// Safe wrapper that validates the tourism event exists before showing
/// TourismDriverHomeScreen. Falls back to HomeScreen if event is invalid/limbo.
class _SafeTourismWrapper extends StatefulWidget {
  final String eventId;
  const _SafeTourismWrapper({required this.eventId});

  @override
  State<_SafeTourismWrapper> createState() => _SafeTourismWrapperState();
}

class _SafeTourismWrapperState extends State<_SafeTourismWrapper> {
  bool _checked = false;
  bool _eventValid = false;

  @override
  void initState() {
    super.initState();
    _validateEvent();
  }

  Future<void> _validateEvent() async {
    try {
      final event = await SupabaseConfig.client
          .from('tourism_events')
          .select('id, status')
          .eq('id', widget.eventId)
          .maybeSingle()
          .timeout(const Duration(seconds: 5), onTimeout: () {
        debugPrint('[TOURISM] ⚠️ Event validation TIMEOUT after 5s');
        return null;
      });

      if (mounted) {
        setState(() {
          _checked = true;
          _eventValid = event != null;
        });

        // If event doesn't exist or timed out, clear the limbo reference
        if (event == null) {
          _clearLimboEvent();
        }
      }
    } catch (e) {
      debugPrint('[TOURISM] Event validation error: $e');
      if (mounted) {
        setState(() {
          _checked = true;
          _eventValid = false;
        });
        _clearLimboEvent();
      }
    }
  }

  void _clearLimboEvent() {
    final authProvider = context.read<AuthProvider>();
    final driver = authProvider.driver;
    if (driver != null) {
      authProvider.updateDriver(driver.copyWith(
        activeTourismEventId: null,
        vehicleMode: 'personal',
      ));
      // Also clear in database
      SupabaseConfig.client
          .from('drivers')
          .update({
            'active_tourism_event_id': null,
            'vehicle_mode': 'personal',
          })
          .eq('id', driver.id)
          .then((_) {})
          .catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
        ),
      );
    }

    if (_eventValid) {
      return TourismDriverHomeScreen(eventId: widget.eventId);
    }

    return const HomeScreen();
  }
}
