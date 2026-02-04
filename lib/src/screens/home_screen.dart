import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:geolocator/geolocator.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher/url_launcher_string.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/driver_provider.dart';
import '../providers/ride_provider.dart';
import '../providers/earnings_provider.dart';
import '../providers/location_provider.dart';
import '../providers/auth_provider.dart';
import '../models/ride_model.dart';
import '../models/driver_model.dart';
import '../utils/app_colors.dart';
import '../utils/app_theme.dart';
import '../utils/haptic_service.dart';
import '../widgets/futuristic_widgets.dart' hide NeonButton, NeonSwitch;
import '../widgets/neon_widgets.dart';
import '../config/supabase_config.dart';
import '../services/audit_service.dart';
import '../services/mapbox_navigation_service.dart';
import 'earnings_screen.dart';
import 'rides_screen.dart';
import 'profile_screen.dart';
import 'map_screen.dart';
import 'navigation_map_screen.dart';
import '../widgets/toro_3d_pin.dart';

/// TORO DRIVER - Luxury Uber Black Driver Home Screen
/// Clean, powerful, confident, luxurious
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int _selectedNavIndex = 0;

  // Collapsible section states
  bool _showDailyEarnings = true;
  bool _showWeeklyEarnings = true;
  bool _showRentalSection = false; // Collapsed by default

  // === APP LIFECYCLE OPTIMIZATION ===
  bool _isAppInBackground = false;

  // Navigation mode removed - using NavigationMapScreen on tab 1 instead

  // Maximum width for web to look like mobile
  static const double _maxWebWidth = 480;

  @override
  void initState() {
    super.initState();
    // Register lifecycle observer for background optimization
    WidgetsBinding.instance.addObserver(this);
    // Listen for forced disconnect events
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupForceDisconnectListener();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _isAppInBackground = true;
        break;
      case AppLifecycleState.resumed:
        _isAppInBackground = false;
        if (mounted) {
          setState(() {});
          // Force refresh available rides when app comes back to foreground
          _refreshRidesOnResume();
        }
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  // Force refresh rides when app resumes from background
  void _refreshRidesOnResume() {
    try {
      final rideProvider = Provider.of<RideProvider>(context, listen: false);
      final locationProvider = Provider.of<LocationProvider>(context, listen: false);
      final pos = locationProvider.currentPosition;
      rideProvider.refreshAvailableRides(
        latitude: pos?.latitude,
        longitude: pos?.longitude,
      );
    } catch (e) {
      // Ignore refresh errors on resume
    }
  }

  void _setupForceDisconnectListener() {
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    driverProvider.addListener(_checkForceDisconnect);
  }

  void _checkForceDisconnect() {
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);

    // Check for forced disconnect
    if (driverProvider.wasForceDisconnected) {
      // Stop GPS tracking
      final locationProvider = Provider.of<LocationProvider>(
        context,
        listen: false,
      );
      locationProvider.stopTracking();

      // Log to audit
      final driver = driverProvider.driver;
      if (driver != null) {
        AuditService.instance.logOffline(
          driverId: driver.id,
          reason:
              'force_disconnect_${driverProvider.forceDisconnectReason ?? "unknown"}',
        );
      }

      // Show dialog explaining why
      _showForceDisconnectDialog(driverProvider.forceDisconnectReason);

      // Clear the flag so dialog doesn't show again
      driverProvider.clearForceDisconnectFlag();
    }

    // Check for approval notification
    if (driverProvider.wasJustApproved) {
      _showApprovalDialog();
      driverProvider.clearApprovalFlag();
    }
  }

  void _showApprovalDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: AppColors.success,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                '¡Cuenta Aprobada!',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 18),
              ),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¡Felicidades! Tu cuenta ha sido aprobada por el equipo de Toro.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.5),
            ),
            SizedBox(height: 12),
            Text(
              'Ya puedes ponerte en línea y comenzar a recibir viajes.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.5),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('¡Empezar!'),
          ),
        ],
      ),
    );
  }

  void _showForceDisconnectDialog(String? reason) {
    String title;
    String message;
    IconData icon;
    Color color;

    switch (reason) {
      case 'documents_incomplete':
        title = 'Documentos Pendientes';
        message =
            'Has sido desconectado porque hay documentos pendientes por completar. '
            'Por favor completa todos los documentos requeridos para volver a estar online.';
        icon = Icons.description_outlined;
        color = const Color(0xFFFF9500);
        break;
      case 'pending_admin_approval':
        title = 'Aprobación Pendiente';
        message =
            'Has sido desconectado porque tu cuenta está pendiente de aprobación. '
            'Te notificaremos cuando seas aprobado.';
        icon = Icons.hourglass_top_rounded;
        color = const Color(0xFFFFD60A);
        break;
      case 'account_suspended':
        title = 'Cuenta Suspendida';
        message =
            'Tu cuenta ha sido suspendida. Has sido desconectado automáticamente. '
            'Contacta a soporte para más información.';
        icon = Icons.block_rounded;
        color = const Color(0xFFFF3B30);
        break;
      case 'account_rejected':
        title = 'Solicitud Rechazada';
        message =
            'Tu solicitud de conductor fue rechazada. Has sido desconectado. '
            'Contacta a soporte si crees que es un error.';
        icon = Icons.cancel_rounded;
        color = const Color(0xFFFF3B30);
        break;
      default:
        title = 'Desconectado';
        message =
            'Has sido desconectado automáticamente porque ya no cumples los requisitos '
            'para estar online. Verifica tu cuenta.';
        icon = Icons.info_outline_rounded;
        color = const Color(0xFFFF9500);
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [
          if (reason == 'documents_incomplete')
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/documents');
              },
              child: const Text('Ver Documentos'),
            ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: color),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    // Remove listener when disposing
    try {
      final driverProvider = Provider.of<DriverProvider>(
        context,
        listen: false,
      );
      driverProvider.removeListener(_checkForceDisconnect);
    } catch (e) {
      // Context might not be valid during dispose
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.surface,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: _buildBody(),
        bottomNavigationBar: _selectedNavIndex == 1 ? null : _buildBottomNav(),
      ),
    );

    // On web, constrain to mobile-like width
    if (!kIsWeb) return scaffold;

    return Container(
      color: AppColors.background,
      child: Center(
        child: SizedBox(width: _maxWebWidth, child: scaffold),
      ),
    );
  }

  Widget _buildBody() {
    switch (_selectedNavIndex) {
      case 1:
        return NavigationMapScreen(
          onBack: () {
            setState(() => _selectedNavIndex = 0);
          },
        );
      case 2:
        return const EarningsScreen();
      case 3:
        return const RidesScreen();
      case 4:
        return const ProfileScreen();
      default:
        return Consumer<RideProvider>(
          builder: (context, rideProvider, child) {
            // Normal home screen
            return SafeArea(
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildIncomingRides(),
                          _buildEarningsCard(),
                          const SizedBox(height: 12),
                          _buildTodayActivity(),
                          const SizedBox(height: 12),
                          _buildQuickActionButtons(),
                          const SizedBox(height: 60),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
    }
  }

  // Banner for active ride - tap to enter navigation
  Widget _buildActiveRideBanner(RideModel ride) {
    // Calculate estimated driver earnings (49% if not calculated yet)
    final estimatedEarnings = ride.driverEarnings > 0
        ? ride.driverEarnings
        : ride.fare * 0.49;

    return GestureDetector(
      onTap: () {
        // Go to NavigationMapScreen (tab Mapa)
        setState(() => _selectedNavIndex = 1);
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF10B981), Color(0xFF059669)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF10B981).withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Pulsing indicator
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.navigation_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'VIAJE ACTIVO',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ride.dropoffLocation.address ?? 'Destino',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tu ganancia: \$${estimatedEarnings.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            // Arrow
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER - Online/Offline Toggle
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Consumer<DriverProvider>(
      builder: (context, driverProvider, child) {
        final isOnline = driverProvider.isOnline;

        return Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                blurRadius: 12,
                spreadRadius: 0,
              ),
              BoxShadow(
                color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                blurRadius: 20,
                spreadRadius: -4,
              ),
            ],
          ),
          child: Row(
            children: [
              // Online/Offline Toggle
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  HapticService.lightImpact();

                  // Check if driver can go online
                  final driver = driverProvider.driver;
                  if (driver != null && !driver.canGoOnline) {
                    // Log to Supabase audit_log for compliance tracking
                    String blockReasonCode = 'unknown';
                    if (!driver.allDocumentsSigned) {
                      blockReasonCode = 'documents_incomplete';
                    } else if (!driver.adminApproved) {
                      blockReasonCode = 'pending_admin_approval';
                    } else if (driver.onboardingStage == 'suspended') {
                      blockReasonCode = 'account_suspended';
                    } else if (driver.onboardingStage == 'rejected') {
                      blockReasonCode = 'account_rejected';
                    }

                    AuditService.instance.logOnlineBlocked(
                      driverId: driver.id,
                      reason: blockReasonCode,
                      status: {
                        'admin_approved': driver.adminApproved,
                        'all_docs_signed': driver.allDocumentsSigned,
                        'can_receive_rides': driver.canReceiveRides,
                        'onboarding_stage': driver.onboardingStage,
                        'agreement_signed': driver.agreementSigned,
                        'ica_signed': driver.icaSigned,
                        'safety_policy_signed': driver.safetyPolicySigned,
                        'bgc_consent_signed': driver.bgcConsentSigned,
                      },
                    );

                    // Determine the reason for blocking
                    String blockReason;
                    String blockTitle;
                    IconData blockIcon;
                    Color blockColor;

                    if (!driver.allDocumentsSigned) {
                      blockTitle = 'Documentos Pendientes';
                      blockReason =
                          'Completa todos los documentos requeridos para poder activarte:\n\n'
                          '${driver.agreementSigned ? '✓' : '✗'} Driver Agreement\n'
                          '${driver.icaSigned ? '✓' : '✗'} Contractor Agreement (ICA)\n'
                          '${driver.safetyPolicySigned ? '✓' : '✗'} Safety Policy\n'
                          '${driver.bgcConsentSigned ? '✓' : '✗'} Background Check Consent';
                      blockIcon = Icons.description_outlined;
                      blockColor = const Color(0xFFFF9500);
                    } else if (!driver.adminApproved) {
                      blockTitle = 'Aprobación Pendiente';
                      blockReason =
                          'Tus documentos están completos.\n\n'
                          'Tu cuenta está siendo revisada por nuestro equipo. '
                          'Te notificaremos por email cuando seas aprobado.';
                      blockIcon = Icons.hourglass_top_rounded;
                      blockColor = const Color(0xFFFFD60A);
                    } else if (driver.onboardingStage == 'suspended') {
                      blockTitle = 'Cuenta Suspendida';
                      blockReason =
                          'Tu cuenta ha sido suspendida. Contacta a soporte para más información.';
                      blockIcon = Icons.block_rounded;
                      blockColor = const Color(0xFFFF3B30);
                    } else if (driver.onboardingStage == 'rejected') {
                      blockTitle = 'Solicitud Rechazada';
                      blockReason =
                          'Tu solicitud no fue aprobada. Contacta a soporte si crees que es un error.';
                      blockIcon = Icons.cancel_rounded;
                      blockColor = const Color(0xFFFF3B30);
                    } else {
                      blockTitle = 'No Disponible';
                      blockReason =
                          'No puedes ir online en este momento. Contacta a soporte.';
                      blockIcon = Icons.info_outline_rounded;
                      blockColor = const Color(0xFFFF9500);
                    }

                    // Show dialog with specific reason
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: AppColors.card,
                        title: Row(
                          children: [
                            Icon(blockIcon, color: blockColor),
                            const SizedBox(width: 12),
                            Text(
                              blockTitle,
                              style: TextStyle(color: AppColors.textPrimary),
                            ),
                          ],
                        ),
                        content: Text(
                          blockReason,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            height: 1.5,
                          ),
                        ),
                        actions: [
                          if (!driver.allDocumentsSigned)
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                Navigator.pushNamed(context, '/documents');
                              },
                              child: const Text('Ver Documentos'),
                            ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: blockColor,
                            ),
                            child: const Text('Entendido'),
                          ),
                        ],
                      ),
                    );
                    return; // Don't allow toggle
                  }

                  final locationProvider = Provider.of<LocationProvider>(
                    context,
                    listen: false,
                  );

                  if (!isOnline) {
                    // Going ONLINE - Initialize GPS and start tracking
                    final hasLocation = await locationProvider.initialize();

                    if (!hasLocation) {
                      // Show dialog to enable location
                      if (context.mounted) {
                        final shouldOpenSettings = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: AppColors.card,
                            title: Row(
                              children: [
                                Icon(
                                  Icons.location_off_rounded,
                                  color: const Color(0xFFFF9500),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'location_required'.tr(),
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            content: Text(
                              'location_required_msg'.tr(),
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text(
                                  'cancel'.tr(),
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF9500),
                                ),
                                child: Text('open_settings'.tr()),
                              ),
                            ],
                          ),
                        );

                        if (shouldOpenSettings == true) {
                          await locationProvider.openLocationSettings();
                        }
                      }
                      return; // Don't go online without location
                    }

                    // Start tracking location
                    if (driverProvider.driver != null) {
                      await locationProvider.startTracking(
                        driverProvider.driver!.id,
                      );

                      // Log successful online event to audit
                      AuditService.instance.logOnlineSuccess(
                        driverId: driverProvider.driver!.id,
                        latitude: locationProvider.currentPosition?.latitude,
                        longitude: locationProvider.currentPosition?.longitude,
                      );
                    }
                  } else {
                    // Going OFFLINE - Stop tracking
                    locationProvider.stopTracking();

                    // Log offline event to audit
                    if (driverProvider.driver != null) {
                      AuditService.instance.logOffline(
                        driverId: driverProvider.driver!.id,
                        reason: 'manual_toggle',
                      );
                    }
                  }

                  await driverProvider.toggleOnlineStatus();
                },
                child: _LuxuryToggle(isOnline: isOnline),
              ),
              const SizedBox(width: 12),
              // Status Bar - FireGlow style
              Expanded(child: _FireGlowStatusBar(isOnline: isOnline)),
              const SizedBox(width: 12),
              // Notifications
              _LuxuryIconButton(
                icon: Icons.notifications_none_rounded,
                onTap: () {
                  HapticService.lightImpact();
                  Navigator.pushNamed(context, '/notifications');
                },
                hasBadge: true,
              ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // OFFLINE NOTIFICATION - Shows when there are rides but driver is offline
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildOfflineRidesNotification(
    int rideCount,
    DriverProvider driverProvider,
  ) {
    return GestureDetector(
      onTap: () async {
        HapticService.mediumImpact();
        // Show dialog to go online
        final shouldGoOnline = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(
                  Icons.local_shipping_outlined,
                  color: const Color(0xFFFF9500),
                ),
                const SizedBox(width: 12),
                Text(
                  'trips_available'.tr(),
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 18),
                ),
              ],
            ),
            content: Text(
              '$rideCount ${rideCount == 1 ? 'trip_waiting_single'.tr() : 'trips_waiting_plural'.tr()}. ${'want_go_online'.tr()}',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  'not_now'.tr(),
                  style: TextStyle(color: AppColors.textTertiary),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF9500),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'go_online'.tr(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );

        if (shouldGoOnline == true) {
          // Get provider reference before async operations
          if (!mounted) return;
          final locationProvider = Provider.of<LocationProvider>(
            context,
            listen: false,
          );

          // Initialize GPS before going online
          final hasLocation = await locationProvider.initialize();

          if (hasLocation && driverProvider.driver != null) {
            await locationProvider.startTracking(driverProvider.driver!.id);
          }

          await driverProvider.toggleOnlineStatus();
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFFF9500).withValues(alpha: 0.2),
              const Color(0xFFFF6B00).withValues(alpha: 0.1),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFFF9500).withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            // Pulsing indicator
            _PulsingDot(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$rideCount ${rideCount == 1 ? 'trip_available_single'.tr() : 'trips_available_plural'.tr()}!',
                    style: const TextStyle(
                      color: Color(0xFFFF9500),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'tap_go_online'.tr(),
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: const Color(0xFFFF9500),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INCOMING RIDES - Shows available ride requests with FireGlow style
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildIncomingRides() {
    return Consumer3<RideProvider, DriverProvider, LocationProvider>(
      builder: (context, rideProvider, driverProvider, locationProvider, child) {
        final isOnline = driverProvider.isOnline;
        final rides = rideProvider.availableRides;
        final driverPosition = locationProvider.currentPosition;

        // Show offline notification if there are rides but driver is offline
        if (!isOnline && rides.isNotEmpty) {
          return _buildOfflineRidesNotification(rides.length, driverProvider);
        }

        // Don't show if offline with no rides, or online with no rides
        if (rides.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9500),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF9500).withValues(alpha: 0.5),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${rides.length} ${rides.length == 1 ? 'trip_available_single'.tr() : 'trips_available_plural'.tr()}',
                    style: TextStyle(
                      color: const Color(0xFFFF9500),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            // Ride cards
            ...rides.take(3).map((ride) {
              // Calculate pickup distance from driver's current location
              double? pickupDistanceMiles;
              if (driverPosition != null &&
                  ride.pickupLocation.latitude != 0 &&
                  ride.pickupLocation.longitude != 0) {
                final distanceCalc = const Distance();
                final distanceMeters = distanceCalc.as(
                  LengthUnit.Meter,
                  LatLng(driverPosition.latitude, driverPosition.longitude),
                  LatLng(
                    ride.pickupLocation.latitude,
                    ride.pickupLocation.longitude,
                  ),
                );
                pickupDistanceMiles =
                    distanceMeters / 1609.34; // meters to miles
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _FireGlowRideCard(
                  ride: ride,
                  pickupDistanceMiles: pickupDistanceMiles,
                  onTap: () {
                    HapticService.lightImpact();
                    _showRoutePreview(
                      context,
                      ride,
                      onAccept: () async {
                        HapticService.mediumImpact();
                        final driverId = driverProvider.driver?.id;
                        debugPrint('🔵 ACEPTAR (preview) tapped: rideId=${ride.id}, driverId=$driverId');
                        if (driverId == null) {
                          debugPrint('🔴 driverId is NULL - cannot accept ride');
                          return;
                        }
                        final success = await rideProvider.acceptRide(ride.id, driverId);
                        debugPrint('🔵 acceptRide (preview) result: $success');
                        if (context.mounted) {
                          if (success) {
                            Navigator.pop(context);
                            // Switch to NavigationMapScreen tab
                            setState(() => _selectedNavIndex = 1);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(rideProvider.error ?? 'Error accepting ride'), backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                    );
                  },
                  onAccept: () async {
                    HapticService.mediumImpact();
                    final driverId = driverProvider.driver?.id;
                    debugPrint('🔵 ACEPTAR VIAJE tapped: rideId=${ride.id}, driverId=$driverId');
                    if (driverId == null) {
                      debugPrint('🔴 driverId is NULL - cannot accept ride');
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: Driver profile not loaded'), backgroundColor: Colors.red),
                        );
                      }
                      return;
                    }
                    final success = await rideProvider.acceptRide(ride.id, driverId);
                    debugPrint('🔵 acceptRide result: $success, error: ${rideProvider.error}');
                    if (success && context.mounted) {
                      // Switch to NavigationMapScreen tab
                      setState(() => _selectedNavIndex = 1);
                    } else if (!success && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(rideProvider.error ?? 'Error accepting ride'), backgroundColor: Colors.red),
                      );
                    }
                  },
                  onReject: () async {
                    HapticService.lightImpact();
                    // Dismiss this ride and track rejection for acceptance rate
                    final driverId = driverProvider.driver?.id;
                    if (driverId != null) {
                      await rideProvider.dismissRide(ride.id, driverId);
                    }
                  },
                ),
              );
            }),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EARNINGS CARD - Today's & Weekly Earnings Display (hideable)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildEarningsCard() {
    return Consumer2<EarningsProvider, RideProvider>(
      builder: (context, earningsProvider, rideProvider, child) {
        final todayEarnings = earningsProvider.todayEarnings;
        final weeklyEarnings = earningsProvider.weeklyEarnings;
        final todayRides = rideProvider.todayRidesCount;
        final stats = context.read<DriverProvider>().stats;
        final onlineTime = stats?['active_time_today'] ?? '0h 0m';

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFFF9500).withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF9500).withValues(alpha: 0.15),
                blurRadius: 12,
                spreadRadius: 0,
              ),
              BoxShadow(
                color: const Color(0xFFFF6B00).withValues(alpha: 0.1),
                blurRadius: 20,
                spreadRadius: -4,
              ),
            ],
          ),
          child: Column(
            children: [
              // Top row with stats
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '$todayRides 🚗 · $onlineTime',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Earnings row - both cards side by side
              Row(
                children: [
                  // Daily Earnings - tappable to hide
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(
                        () => _showDailyEarnings = !_showDailyEarnings,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.cardHover,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _showDailyEarnings
                                ? const Color(0xFFFF9500).withValues(alpha: 0.3)
                                : Colors.transparent,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Hoy',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 10,
                                  ),
                                ),
                                Icon(
                                  _showDailyEarnings
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                  color: AppColors.textTertiary,
                                  size: 12,
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            _showDailyEarnings
                                ? Text(
                                    '\$${todayEarnings.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: const Color(0xFFFF9500),
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  )
                                : _TamagotchiPet(
                                    color: const Color(0xFFFF9500),
                                    seed: 1,
                                  ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Weekly Earnings - tappable to hide (deposited on Sunday)
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(
                        () => _showWeeklyEarnings = !_showWeeklyEarnings,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.cardHover,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _showWeeklyEarnings
                                ? AppColors.success.withValues(alpha: 0.3)
                                : Colors.transparent,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Semana',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 10,
                                  ),
                                ),
                                Icon(
                                  _showWeeklyEarnings
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                  color: AppColors.textTertiary,
                                  size: 12,
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            _showWeeklyEarnings
                                ? Text(
                                    '\$${weeklyEarnings.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: AppColors.success,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  )
                                : _TamagotchiPet(
                                    color: AppColors.success,
                                    seed: 2,
                                  ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TODAY'S ACTIVITY - Stats List
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTodayActivity() {
    return Consumer2<RideProvider, DriverProvider>(
      builder: (context, rideProvider, driverProvider, child) {
        final todayRides = rideProvider.todayRidesCount;
        final stats = driverProvider.stats;
        final onlineTime = stats?['active_time_today'] ?? '0h 0m';
        final distanceToday = stats?['distance_today_km'] ?? 0.0;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF00D4AA).withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00D4AA).withValues(alpha: 0.12),
                blurRadius: 12,
                spreadRadius: 0,
              ),
              BoxShadow(
                color: const Color(0xFF00D4AA).withValues(alpha: 0.08),
                blurRadius: 20,
                spreadRadius: -4,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                Icons.directions_car_outlined,
                '$todayRides',
                'rides_label'.tr(),
              ),
              Container(
                width: 1,
                height: 30,
                color: AppColors.border.withValues(alpha: 0.3),
              ),
              _buildStatItem(
                Icons.schedule_outlined,
                onlineTime,
                'duration_label'.tr(),
              ),
              Container(
                width: 1,
                height: 30,
                color: AppColors.border.withValues(alpha: 0.3),
              ),
              _buildStatItem(
                Icons.route_outlined,
                '${(distanceToday * 0.621371).toStringAsFixed(1)} mi',
                'distance_label'.tr(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: AppColors.textTertiary, size: 16),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          label,
          style: TextStyle(color: AppColors.textTertiary, fontSize: 9),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RENTA TU VEHICULO - Vehicle rental section
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildQuickActionButtons() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withValues(alpha: 0.08),
            blurRadius: 20,
            spreadRadius: -4,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header - tappable to expand/collapse
          GestureDetector(
            onTap: () {
              HapticService.lightImpact();
              setState(() => _showRentalSection = !_showRentalSection);
            },
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.car_rental_rounded,
                      color: Color(0xFF8B5CF6),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Renta tu Vehiculo',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Publica tu vehiculo y gana dinero',
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _showRentalSection ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textTertiary,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Collapsible content
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: [
                Divider(
                  color: AppColors.border.withValues(alpha: 0.5),
                  height: 1,
                ),
                _buildRentalActionItem(
                  icon: Icons.directions_car_rounded,
                  label: 'Publicar Vehiculo',
                  subtitle: 'Crea un anuncio de renta',
                  onTap: () {
                    HapticService.lightImpact();
                    _showPublishVehicleSheet();
                  },
                ),
                Divider(
                  color: AppColors.border.withValues(alpha: 0.3),
                  height: 1,
                  indent: 56,
                ),
                _buildRentalActionItem(
                  icon: Icons.receipt_long_rounded,
                  label: 'Mis Rentas',
                  subtitle: 'Acuerdos de renta activos',
                  onTap: () {
                    HapticService.lightImpact();
                    _showMyRentalsSheet();
                  },
                ),
                Divider(
                  color: AppColors.border.withValues(alpha: 0.3),
                  height: 1,
                  indent: 56,
                ),
                _buildRentalActionItem(
                  icon: Icons.gps_fixed_rounded,
                  label: 'GPS Tracking',
                  subtitle: 'Rastreo de vehiculos rentados',
                  onTap: () {
                    HapticService.lightImpact();
                    _showGpsTrackingSheet();
                  },
                ),
                const SizedBox(height: 4),
              ],
            ),
            crossFadeState: _showRentalSection
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
        ],
      ),
    );
  }

  Widget _buildRentalActionItem({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        splashColor: const Color(0xFF8B5CF6).withValues(alpha: 0.08),
        highlightColor: const Color(0xFF8B5CF6).withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.cardHover,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Icon(icon, color: const Color(0xFF8B5CF6), size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLISH VEHICLE BOTTOM SHEET
  // ═══════════════════════════════════════════════════════════════════════════

  void _showPublishVehicleSheet() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.driverId;

    if (userId == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PublishVehicleSheet(userId: userId),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MY RENTALS BOTTOM SHEET
  // ═══════════════════════════════════════════════════════════════════════════

  void _showMyRentalsSheet() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.driverId;

    if (userId == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MyRentalsSheet(userId: userId),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GPS TRACKING BOTTOM SHEET
  // ═══════════════════════════════════════════════════════════════════════════

  void _showGpsTrackingSheet() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.driverId;

    if (userId == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _GpsTrackingSheet(userId: userId),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ROUTE PREVIEW - Shows mini map when tapping a ride card
  // ═══════════════════════════════════════════════════════════════════════════

  void _showRoutePreview(
    BuildContext context,
    RideModel ride, {
    VoidCallback? onAccept,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _RoutePreviewSheet(ride: ride, onAccept: onAccept),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BOTTOM NAVIGATION - FireGlow Style - Exactly 4 Items
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBottomNav() {
    return Consumer<RideProvider>(
      builder: (context, rideProvider, child) {
        final hasActiveRide = rideProvider.hasActiveRide && rideProvider.activeRide != null;

        return FireGlowBottomNavBar(
          currentIndex: _selectedNavIndex,
          onTap: (index) {
            // Always go to NavigationMapScreen (the good Mapbox map) for index 1
            setState(() => _selectedNavIndex = index);
          },
          items: [
            FireGlowNavItem(
              icon: Icons.home_outlined,
              activeIcon: Icons.home_rounded,
              label: 'nav_home'.tr(),
            ),
            FireGlowNavItem(
              icon: Icons.map_outlined,
              activeIcon: Icons.navigation_rounded, // Navigation icon when active
              label: hasActiveRide ? 'Viaje' : 'Mapa',
              hasActiveGlow: hasActiveRide, // Green glow when there's an active ride
            ),
            FireGlowNavItem(
              icon: Icons.attach_money_outlined,
              activeIcon: Icons.attach_money_rounded,
              label: 'nav_earnings'.tr(),
            ),
            FireGlowNavItem(
              icon: Icons.directions_car_outlined,
              activeIcon: Icons.directions_car_rounded,
              label: 'nav_trips'.tr(),
            ),
            FireGlowNavItem(
              icon: Icons.person_outline_rounded,
              activeIcon: Icons.person_rounded,
              label: 'nav_profile'.tr(),
            ),
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LUXURY COMPONENTS
// ═══════════════════════════════════════════════════════════════════════════════

/// Luxury Online/Offline Toggle
class _LuxuryToggle extends StatelessWidget {
  final bool isOnline;

  const _LuxuryToggle({required this.isOnline});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppTheme.durationNormal,
      curve: AppTheme.curveDefault,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isOnline
            ? AppColors.success.withValues(alpha: 0.15)
            : AppColors.cardSecondary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isOnline
              ? AppColors.success.withValues(alpha: 0.3)
              : AppColors.border.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: AppTheme.durationFast,
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isOnline ? AppColors.success : AppColors.textTertiary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isOnline ? 'status_online'.tr() : 'status_offline'.tr(),
            style: TextStyle(
              color: isOnline ? AppColors.success : AppColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Luxury Icon Button
class _LuxuryIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool hasBadge;

  const _LuxuryIconButton({
    required this.icon,
    required this.onTap,
    this.hasBadge = false,
  });

  @override
  State<_LuxuryIconButton> createState() => _LuxuryIconButtonState();
}

class _LuxuryIconButtonState extends State<_LuxuryIconButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _isPressed ? AppColors.cardHover : AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.border.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
        child: Stack(
          children: [
            Icon(widget.icon, color: AppColors.textSecondary, size: 22),
            if (widget.hasBadge)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Luxury Action Button with micro light reaction
class _LuxuryActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _LuxuryActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_LuxuryActionButton> createState() => _LuxuryActionButtonState();
}

class _LuxuryActionButtonState extends State<_LuxuryActionButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: _isPressed ? AppColors.cardHover : AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _isPressed
                ? const Color(0xFF8B5CF6).withValues(alpha: 0.5)
                : const Color(0xFF8B5CF6).withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(
                0xFF8B5CF6,
              ).withValues(alpha: _isPressed ? 0.2 : 0.12),
              blurRadius: _isPressed ? 16 : 10,
              spreadRadius: _isPressed ? 1 : 0,
            ),
            BoxShadow(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
              blurRadius: 20,
              spreadRadius: -4,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, color: const Color(0xFF8B5CF6), size: 20),
            const SizedBox(width: 10),
            Text(
              widget.label,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// FireGlow Status Bar - Shows search status with animated glow when online
class _FireGlowStatusBar extends StatefulWidget {
  final bool isOnline;

  const _FireGlowStatusBar({required this.isOnline});

  @override
  State<_FireGlowStatusBar> createState() => _FireGlowStatusBarState();
}

class _FireGlowStatusBarState extends State<_FireGlowStatusBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;
  int _messageIndex = 0;

  // Positive messages that cycle when online - use method to get translated
  List<String> get _positiveMessages => [
    'searching_trips'.tr(),
    'ready_receive'.tr(),
    'connected_active'.tr(),
    'waiting_trips'.tr(),
    'available_status'.tr(),
  ];

  // FireGlow colors
  static const Color _fireColor = Color(0xFFFF9500);
  static const Color _emberColor = Color(0xFFFF6B00);
  static const Color _warmWhite = Color(0xFFFFF5E6);

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _glowAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    if (widget.isOnline) {
      _glowController.repeat(reverse: true);
      _startMessageCycle();
    }
  }

  void _startMessageCycle() {
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && widget.isOnline) {
        setState(() {
          _messageIndex = (_messageIndex + 1) % _positiveMessages.length;
        });
        _startMessageCycle();
      }
    });
  }

  @override
  void didUpdateWidget(_FireGlowStatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOnline && !oldWidget.isOnline) {
      _glowController.repeat(reverse: true);
      _startMessageCycle();
    } else if (!widget.isOnline && oldWidget.isOnline) {
      _glowController.stop();
      _glowController.value = 0;
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isOnline) {
      // Offline state - sleeping icon
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.cardSecondary,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.border.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bedtime_outlined,
              color: AppColors.textTertiary,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              'resting'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    // Online state - animated FireGlow
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        final glowIntensity = _glowAnimation.value;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _emberColor.withValues(alpha: 0.15 * glowIntensity),
                _fireColor.withValues(alpha: 0.2 * glowIntensity),
                _emberColor.withValues(alpha: 0.15 * glowIntensity),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _fireColor.withValues(alpha: 0.4 * glowIntensity),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _fireColor.withValues(alpha: 0.2 * glowIntensity),
                blurRadius: 12 * glowIntensity,
                spreadRadius: -2,
              ),
              BoxShadow(
                color: _emberColor.withValues(alpha: 0.15 * glowIntensity),
                blurRadius: 20 * glowIntensity,
                spreadRadius: -4,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pulsing dot
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: Color.lerp(_emberColor, _warmWhite, glowIntensity),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _fireColor.withValues(alpha: 0.6 * glowIntensity),
                      blurRadius: 6 * glowIntensity,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Animated text with crossfade
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                transitionBuilder: (child, animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child: Text(
                  _positiveMessages[_messageIndex],
                  key: ValueKey<int>(_messageIndex),
                  style: TextStyle(
                    color: Color.lerp(
                      _fireColor,
                      _warmWhite,
                      glowIntensity * 0.5,
                    ),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// FireGlow Ride Request Card - Shows incoming ride with accept/reject buttons
class _FireGlowRideCard extends StatefulWidget {
  final RideModel ride;
  final VoidCallback onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onTap;
  final double? pickupDistanceMiles; // Distance from driver to pickup

  const _FireGlowRideCard({
    required this.ride,
    required this.onAccept,
    this.onReject,
    this.onTap,
    this.pickupDistanceMiles,
  });

  @override
  State<_FireGlowRideCard> createState() => _FireGlowRideCardState();
}

class _FireGlowRideCardState extends State<_FireGlowRideCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // FireGlow colors
  static const Color _fireColor = Color(0xFFFF9500);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _getRideTypeIcon() {
    switch (widget.ride.type) {
      case RideType.passenger:
        return '🚗';
      case RideType.package:
        return '📦';
      case RideType.carpool:
        return '👥';
    }
  }

  String _getRideTypeLabel() {
    switch (widget.ride.type) {
      case RideType.passenger:
        return 'ride_type_ride'.tr();
      case RideType.package:
        return 'ride_type_package'.tr();
      case RideType.carpool:
        return 'ride_type_carpool'.tr();
    }
  }

  // Format recurring days (1-7) to day letters (L M X J V S D)
  String _formatRecurringDays(List<int> days) {
    const dayLetters = [
      '',
      'L',
      'M',
      'X',
      'J',
      'V',
      'S',
      'D',
    ]; // 1=Monday, 7=Sunday
    final sortedDays = List<int>.from(days)..sort();
    return sortedDays
        .map((d) => d >= 1 && d <= 7 ? dayLetters[d] : '?')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          final pulse = _pulseAnimation.value;

          return Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _fireColor.withValues(alpha: 0.3 * pulse),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: Type badge + Client + Fare
                Row(
                  children: [
                    // Type badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _fireColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _getRideTypeIcon(),
                            style: const TextStyle(fontSize: 18),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _getRideTypeLabel(),
                            style: TextStyle(
                              color: _fireColor,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.ride.isGoodTipper) ...[
                      const SizedBox(width: 4),
                      Text('💰', style: const TextStyle(fontSize: 14)),
                    ],
                    // Round Trip badge for carpool
                    if (widget.ride.isRoundTrip) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00C853), Color(0xFF00897B)],
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'round_trip'.tr(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    // Client avatar + name
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: _fireColor.withValues(alpha: 0.2),
                      backgroundImage: widget.ride.passengerImageUrl != null
                          ? NetworkImage(widget.ride.passengerImageUrl!)
                          : null,
                      child: widget.ride.passengerImageUrl == null
                          ? Text(
                              widget.ride.passengerName.isNotEmpty
                                  ? widget.ride.passengerName[0].toUpperCase()
                                  : 'C',
                              style: TextStyle(
                                color: _fireColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.ride.passengerName,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.ride.passengerRating > 0) ...[
                      Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                      const SizedBox(width: 2),
                      Text(
                        widget.ride.passengerRating.toStringAsFixed(1),
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),

                // Locations in compact format
                Row(
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Container(
                          width: 2,
                          height: 20,
                          color: AppColors.textTertiary.withValues(alpha: 0.3),
                        ),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _fireColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.ride.pickupLocation.address ??
                                'pickup_location'.tr(),
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.ride.dropoffLocation.address ??
                                'destination'.tr(),
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // EARNINGS DISPLAY - Simple: Total + Your Earnings (what driver cares about)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.success.withValues(alpha: 0.15),
                        AppColors.success.withValues(alpha: 0.08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Total fare (what customer pays)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total viaje',
                            style: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '\$${widget.ride.fare.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      // Arrow
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: AppColors.textTertiary,
                        size: 18,
                      ),
                      // Driver earnings (green - prominent)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Tu ganancia',
                            style: TextStyle(
                              color: AppColors.success,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '\$${widget.ride.driverEarnings.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: AppColors.success,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Distance + Time row (pickup distance + trip distance + trip time)
                Row(
                  children: [
                    // Pickup distance (miles away from driver)
                    if (widget.pickupDistanceMiles != null) ...[
                      Icon(Icons.near_me, color: Colors.cyan, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.pickupDistanceMiles!.toStringAsFixed(1)} mi',
                        style: TextStyle(
                          color: Colors.cyan,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 1,
                        height: 16,
                        color: AppColors.textTertiary.withValues(alpha: 0.3),
                      ),
                      const SizedBox(width: 10),
                    ],
                    // Trip distance
                    Icon(
                      Icons.route_outlined,
                      color: AppColors.textTertiary,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${(widget.ride.distanceKm * 0.621371).toStringAsFixed(1)} mi',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Trip time
                    Icon(
                      Icons.schedule_outlined,
                      color: AppColors.textTertiary,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '~${widget.ride.estimatedMinutes} min',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                // Carpool info: recurring days + seats (only for carpool type)
                if (widget.ride.type == RideType.carpool &&
                    widget.ride.recurringDays.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // Recurring days
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.calendar_today,
                              color: Colors.blue,
                              size: 10,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatRecurringDays(widget.ride.recurringDays),
                              style: const TextStyle(
                                color: Colors.blue,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Seats indicator
                      Row(
                        children: List.generate(3, (i) {
                          final isOccupied = i < widget.ride.filledSeats;
                          return Padding(
                            padding: const EdgeInsets.only(right: 2),
                            child: Icon(
                              Icons.person,
                              color: isOccupied
                                  ? AppColors.success
                                  : AppColors.textTertiary,
                              size: 14,
                            ),
                          );
                        }),
                      ),
                      Text(
                        '${widget.ride.filledSeats}/3',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                      // Return time if available
                      if (widget.ride.returnTime != null) ...[
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.replay,
                                color: Colors.purple,
                                size: 10,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                widget.ride.returnTime!,
                                style: const TextStyle(
                                  color: Colors.purple,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                // Buttons row - ACCEPT / REJECT prominently displayed
                Row(
                  children: [
                    // Reject button (X) - larger and more visible
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        widget.onReject?.call();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.error.withValues(alpha: 0.5),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.close_rounded,
                              color: AppColors.error,
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'RECHAZAR',
                              style: TextStyle(
                                color: AppColors.error,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Accept button - ACEPTAR VIAJE (clear CTA)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          widget.onAccept();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF22C55E),
                                const Color(0xFF16A34A),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.success.withValues(alpha: 0.5),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.check_circle_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'ACEPTAR VIAJE',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Pulsing dot indicator for offline notification
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _animation = Tween<double>(
      begin: 0.4,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: const Color(0xFFFF9500),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(
                  0xFFFF9500,
                ).withValues(alpha: _animation.value * 0.6),
                blurRadius: 8 * _animation.value,
                spreadRadius: 2 * _animation.value,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Route Preview Sheet - Shows mini map with route preview
class _RoutePreviewSheet extends StatefulWidget {
  final RideModel ride;
  final VoidCallback? onAccept;

  const _RoutePreviewSheet({required this.ride, this.onAccept});

  @override
  State<_RoutePreviewSheet> createState() => _RoutePreviewSheetState();
}

class _RoutePreviewSheetState extends State<_RoutePreviewSheet>
    with TickerProviderStateMixin {
  List<LatLng> _routePoints = [];
  bool _isLoading = true;
  String? _distance;
  String? _duration;

  // Collapsible states
  bool _showDailyEarnings = true;
  bool _showWeeklyEarnings = true;

  // Animated glow on route
  late AnimationController _glowController;
  late Animation<double> _glowProgress;

  @override
  void initState() {
    super.initState();
    _fetchRoute();

    // Initialize glow animation - travels along route
    _glowController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();

    _glowProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  Future<void> _fetchRoute() async {
    final pickup = LatLng(
      widget.ride.pickupLocation.latitude,
      widget.ride.pickupLocation.longitude,
    );
    final dropoff = LatLng(
      widget.ride.dropoffLocation.latitude,
      widget.ride.dropoffLocation.longitude,
    );

    try {
      final route = await MapboxNavigationService().getRoute(
        originLat: pickup.latitude,
        originLng: pickup.longitude,
        destinationLat: dropoff.latitude,
        destinationLng: dropoff.longitude,
      );

      if (route != null && route.geometry.isNotEmpty) {
        _routePoints = route.geometry
            .map((coord) => LatLng(coord[1], coord[0]))
            .toList();

        final distanceMeters = route.distance;
        final durationSeconds = route.duration;

        _distance = distanceMeters >= 1609
            ? '${(distanceMeters / 1609.34).toStringAsFixed(1)} mi'
            : '${(distanceMeters * 3.28084).toInt()} ft';

        final minutes = (durationSeconds / 60).round();
        _duration = minutes >= 60
            ? '${minutes ~/ 60}h ${minutes % 60}min'
            : '$minutes min';
      }
    } catch (e) {
      // Route fetch error
    }

    if (_routePoints.isEmpty) {
      _routePoints = [pickup, dropoff];
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, lat = 0, lng = 0;

    while (index < encoded.length) {
      int shift = 0, result = 0, byte;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1F) << shift;
        shift += 5;
      } while (byte >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      shift = 0;
      result = 0;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1F) << shift;
        shift += 5;
      } while (byte >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  // Get point along the route based on progress (0.0 to 1.0)
  LatLng _getPointAtProgress(double progress) {
    if (_routePoints.isEmpty) return const LatLng(0, 0);
    if (_routePoints.length == 1) return _routePoints.first;

    final totalPoints = _routePoints.length - 1;
    final exactIndex = progress * totalPoints;
    final index = exactIndex.floor();
    final fraction = exactIndex - index;

    if (index >= totalPoints) return _routePoints.last;

    final start = _routePoints[index];
    final end = _routePoints[index + 1];

    return LatLng(
      start.latitude + (end.latitude - start.latitude) * fraction,
      start.longitude + (end.longitude - start.longitude) * fraction,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pickup = LatLng(
      widget.ride.pickupLocation.latitude,
      widget.ride.pickupLocation.longitude,
    );
    final dropoff = LatLng(
      widget.ride.dropoffLocation.latitude,
      widget.ride.dropoffLocation.longitude,
    );

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9500).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.route_rounded,
                    color: Color(0xFFFF9500),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'route_preview'.tr(),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_distance != null && _duration != null)
                        Text(
                          '$_distance • $_duration',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  '\$${widget.ride.fare.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Color(0xFFFF9500),
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Collapsible Earnings Cards
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                // Daily Earnings - Collapsible
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(
                      () => _showDailyEarnings = !_showDailyEarnings,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: EdgeInsets.all(_showDailyEarnings ? 12 : 8),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _showDailyEarnings
                              ? const Color(0xFFFF9500).withValues(alpha: 0.3)
                              : AppColors.border.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'today'.tr(),
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Icon(
                                _showDailyEarnings
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                color: AppColors.textTertiary,
                                size: 14,
                              ),
                            ],
                          ),
                          if (_showDailyEarnings) ...[
                            const SizedBox(height: 4),
                            Consumer<EarningsProvider>(
                              builder: (context, ep, _) => Text(
                                '\$${ep.todayEarnings.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Color(0xFFFF9500),
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Weekly Earnings - Collapsible
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(
                      () => _showWeeklyEarnings = !_showWeeklyEarnings,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: EdgeInsets.all(_showWeeklyEarnings ? 12 : 8),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _showWeeklyEarnings
                              ? AppColors.primaryBright.withValues(alpha: 0.3)
                              : AppColors.border.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'this_week'.tr(),
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Icon(
                                _showWeeklyEarnings
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                color: AppColors.textTertiary,
                                size: 14,
                              ),
                            ],
                          ),
                          if (_showWeeklyEarnings) ...[
                            const SizedBox(height: 4),
                            Consumer<EarningsProvider>(
                              builder: (context, ep, _) => Text(
                                '\$${ep.weeklyEarnings.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: AppColors.primaryBright,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Map with animated glow route
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF9500)),
                  )
                : ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: AnimatedBuilder(
                      animation: _glowProgress,
                      builder: (context, child) {
                        final glowPoint = _getPointAtProgress(
                          _glowProgress.value,
                        );

                        return FlutterMap(
                          options: MapOptions(
                            initialCenter: LatLng(
                              (pickup.latitude + dropoff.latitude) / 2,
                              (pickup.longitude + dropoff.longitude) / 2,
                            ),
                            initialZoom: 13,
                            interactionOptions: const InteractionOptions(
                              flags:
                                  InteractiveFlag.all & ~InteractiveFlag.rotate,
                            ),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                              subdomains: const ['a', 'b', 'c', 'd'],
                            ),
                            // Route line with glow effect
                            if (_routePoints.isNotEmpty)
                              PolylineLayer(
                                polylines: [
                                  // Base route - darker
                                  Polyline(
                                    points: _routePoints,
                                    color: const Color(
                                      0xFFFF9500,
                                    ).withValues(alpha: 0.3),
                                    strokeWidth: 6,
                                  ),
                                  // Main route line
                                  Polyline(
                                    points: _routePoints,
                                    color: const Color(0xFFFF9500),
                                    strokeWidth: 4,
                                  ),
                                ],
                              ),
                            // Animated glow marker traveling along route
                            if (_routePoints.isNotEmpty)
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: glowPoint,
                                    width: 24,
                                    height: 24,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFD700),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(
                                              0xFFFF9500,
                                            ).withValues(alpha: 0.8),
                                            blurRadius: 15,
                                            spreadRadius: 5,
                                          ),
                                          BoxShadow(
                                            color: const Color(
                                              0xFFFFD700,
                                            ).withValues(alpha: 0.6),
                                            blurRadius: 8,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            // Start and End markers
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: pickup,
                                  width: 40,
                                  height: 40,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.success,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.success.withValues(
                                            alpha: 0.5,
                                          ),
                                          blurRadius: 10,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.trip_origin,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                                Marker(
                                  point: dropoff,
                                  width: 40,
                                  height: 40,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF9500),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(
                                            0xFFFF9500,
                                          ).withValues(alpha: 0.5),
                                          blurRadius: 10,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.flag_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
          ),
          // Address info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              border: Border(
                top: BorderSide(color: AppColors.border.withValues(alpha: 0.3)),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.success.withValues(alpha: 0.5),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.ride.pickupLocation.address ?? 'pickup'.tr(),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                // Dotted line connecting A to B
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Column(
                    children: List.generate(
                      3,
                      (i) => Container(
                        width: 2,
                        height: 4,
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.textTertiary.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9500),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFFFF9500,
                            ).withValues(alpha: 0.5),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.ride.dropoffLocation.address ??
                            'destination'.tr(),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Accept and Close buttons
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  // Close button
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          'close'.tr(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.onAccept != null) ...[
                    const SizedBox(width: 12),
                    // Accept button
                    Expanded(
                      flex: 2,
                      child: GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          widget.onAccept!();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.success,
                                AppColors.success.withValues(alpha: 0.8),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.success.withValues(alpha: 0.4),
                                blurRadius: 12,
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.check_circle_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'accept_trip'.tr().toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Cute animated Tamagotchi pet for hidden earnings
class _TamagotchiPet extends StatefulWidget {
  final Color color;
  final int seed;

  const _TamagotchiPet({required this.color, required this.seed});

  @override
  State<_TamagotchiPet> createState() => _TamagotchiPetState();
}

class _TamagotchiPetState extends State<_TamagotchiPet>
    with TickerProviderStateMixin {
  late AnimationController _blinkController;
  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;
  bool _isBlinking = false;
  int _expression = 0; // 0=happy, 1=excited, 2=sleepy, 3=love

  final List<String> _faces = ['◕‿◕', '◕ᴗ◕', '◡‿◡', '♥‿♥'];
  final List<String> _blinkFaces = ['◡‿◡', '◡ᴗ◡', '─‿─', '♥‿♥'];

  @override
  void initState() {
    super.initState();
    _expression = widget.seed % 4;

    _blinkController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..repeat(reverse: true);

    _bounceAnimation = Tween<double>(begin: 0, end: -3).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut),
    );

    // Random blink
    _startBlinking();
    // Change expression occasionally
    _startExpressionChanges();
  }

  void _startBlinking() {
    Future.delayed(
      Duration(milliseconds: 2000 + (widget.seed * 500) % 2000),
      () {
        if (!mounted) return;
        setState(() => _isBlinking = true);
        Future.delayed(const Duration(milliseconds: 150), () {
          if (!mounted) return;
          setState(() => _isBlinking = false);
          _startBlinking();
        });
      },
    );
  }

  void _startExpressionChanges() {
    Future.delayed(
      Duration(milliseconds: 4000 + (widget.seed * 1000) % 3000),
      () {
        if (!mounted) return;
        setState(() => _expression = (_expression + 1) % 4);
        _startExpressionChanges();
      },
    );
  }

  @override
  void dispose() {
    _blinkController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bounceAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _bounceAnimation.value),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pet body
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: widget.color.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  _isBlinking ? _blinkFaces[_expression] : _faces[_expression],
                  style: TextStyle(
                    fontSize: 16,
                    color: widget.color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Sparkle/heart decoration
              Text(
                _expression == 3 ? '💕' : '✨',
                style: const TextStyle(fontSize: 10),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// _ActiveRideNavigation class removed (was lines 3504-7413)

/// Navigation option button for external GPS apps
class _NavOptionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sublabel;
  final Color color;
  final VoidCallback onTap;
  final bool featured;

  const _NavOptionButton({
    required this.icon,
    required this.label,
    this.sublabel,
    required this.color,
    required this.onTap,
    this.featured = false,
  });

  @override
  Widget build(BuildContext context) {
    if (featured) {
      // Featured style - full width with gradient
      return GestureDetector(
        onTap: () {
          HapticService.mediumImpact();
          onTap();
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color, color.withValues(alpha: 0.8)],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (sublabel != null)
                    Text(
                      sublabel!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // Default style
    return GestureDetector(
      onTap: () {
        HapticService.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// CustomPainter para dibujar un triángulo de navegación con glow
class _NavigationTrianglePainter extends CustomPainter {
  final Color color;
  final double glowOpacity;

  _NavigationTrianglePainter({required this.color, required this.glowOpacity});

  @override
  void paint(Canvas canvas, Size size) {
    final path = ui.Path();

    // Triángulo apuntando hacia arriba (estilo navegación)
    path.moveTo(size.width / 2, 0); // Punta superior
    path.lineTo(
      size.width * 0.15,
      size.height * 0.85,
    ); // Esquina inferior izquierda
    path.lineTo(size.width / 2, size.height * 0.65); // Muesca central
    path.lineTo(
      size.width * 0.85,
      size.height * 0.85,
    ); // Esquina inferior derecha
    path.close();

    // Glow externo
    final glowPaint = Paint()
      ..color = color.withValues(alpha: glowOpacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
    canvas.drawPath(path, glowPaint);

    // Relleno principal
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // Borde blanco
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _NavigationTrianglePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.glowOpacity != glowOpacity;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PUBLISH VEHICLE SHEET - Create a rental listing (manual entry, no vehicles table)
// ═══════════════════════════════════════════════════════════════════════════════

class _PublishVehicleSheet extends StatefulWidget {
  final String userId;
  const _PublishVehicleSheet({required this.userId});

  @override
  State<_PublishVehicleSheet> createState() => _PublishVehicleSheetState();
}

class _PublishVehicleSheetState extends State<_PublishVehicleSheet> {
  static const _accent = Color(0xFF8B5CF6);

  // Step tracker
  int _currentStep = 0; // 0=Vehicle, 1=Insurance, 2=Pricing, 3=Location, 4=Contract

  // Vehicle info controllers
  final _makeCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _vinCtrl = TextEditingController();
  String _vehicleType = 'sedan';

  // Autobus: assigned driver
  final _driverEmailCtrl = TextEditingController();
  String? _assignedDriverId;
  String? _assignedDriverName;
  bool _driverVerified = false;
  bool _verifyingDriver = false;

  // Insurance controllers
  final _insCompanyCtrl = TextEditingController();
  final _insPolicyCtrl = TextEditingController();
  DateTime? _insExpiry;

  // Pricing controllers
  final _weeklyPriceCtrl = TextEditingController();
  final _perKmPriceCtrl = TextEditingController();
  final _depositCtrl = TextEditingController();

  // Location
  double? _pickupLat;
  double? _pickupLng;
  String? _pickupAddress;

  // Availability
  DateTime? _availableFrom;
  DateTime? _availableTo;

  // Contract signing
  bool _agreedToTerms = false;
  bool _isSubmitting = false;
  String? _error;

  final _vehicleTypes = ['sedan', 'SUV', 'van', 'truck', 'autobus'];

  @override
  void dispose() {
    _makeCtrl.dispose();
    _modelCtrl.dispose();
    _yearCtrl.dispose();
    _colorCtrl.dispose();
    _plateCtrl.dispose();
    _vinCtrl.dispose();
    _driverEmailCtrl.dispose();
    _insCompanyCtrl.dispose();
    _insPolicyCtrl.dispose();
    _weeklyPriceCtrl.dispose();
    _perKmPriceCtrl.dispose();
    _depositCtrl.dispose();
    super.dispose();
  }

  String? _validateStep(int step) {
    switch (step) {
      case 0:
        if (_makeCtrl.text.trim().isEmpty) return 'Ingresa la marca';
        if (_modelCtrl.text.trim().isEmpty) return 'Ingresa el modelo';
        if (_yearCtrl.text.trim().isEmpty) return 'Ingresa el año';
        final year = int.tryParse(_yearCtrl.text.trim());
        if (year == null || year < 1990 || year > 2030) return 'Año invalido';
        if (_plateCtrl.text.trim().isEmpty) return 'Ingresa la placa';
        if (_vehicleType == 'autobus' && !_driverVerified) {
          return 'Autobus requiere un chofer aprobado por Toro';
        }
        return null;
      case 1:
        // Insurance is optional but if company is entered, policy is required
        if (_insCompanyCtrl.text.trim().isNotEmpty && _insPolicyCtrl.text.trim().isEmpty) {
          return 'Ingresa el numero de poliza';
        }
        return null;
      case 2:
        if (_weeklyPriceCtrl.text.trim().isEmpty) return 'Ingresa el precio semanal';
        if (double.tryParse(_weeklyPriceCtrl.text.trim()) == null) return 'Precio semanal invalido';
        return null;
      case 3:
        if (_pickupLat == null || _pickupLng == null) return 'Selecciona la ubicacion de entrega';
        return null;
      case 4:
        if (!_agreedToTerms) return 'Debes aceptar los terminos del contrato';
        return null;
      default:
        return null;
    }
  }

  void _nextStep() {
    final validation = _validateStep(_currentStep);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() {
      _error = null;
      _currentStep++;
    });
    HapticService.lightImpact();
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() {
        _error = null;
        _currentStep--;
      });
      HapticService.lightImpact();
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      // Reverse geocode via Mapbox
      String address = '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      try {
        final url = 'https://api.mapbox.com/geocoding/v5/mapbox.places/${pos.longitude},${pos.latitude}.json'
            '?access_token=pk.eyJ1IjoibWFydGluZXpjMjAxNyIsImEiOiJjbWtocWtoZHIwbW1iM2dvdXZ3bmp0ZjBiIn0.MjYgv6DuvLTkrBVbrhtFbg&limit=1';
        final resp = await http.get(Uri.parse(url));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          final features = data['features'] as List?;
          if (features != null && features.isNotEmpty) {
            address = features[0]['place_name'] as String? ?? address;
          }
        }
      } catch (_) {}
      if (mounted) {
        setState(() {
          _pickupLat = pos.latitude;
          _pickupLng = pos.longitude;
          _pickupAddress = address;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Error obteniendo ubicacion: $e');
      }
    }
  }

  Future<void> _verifyDriver() async {
    final email = _driverEmailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Ingresa el email del chofer');
      return;
    }
    setState(() { _verifyingDriver = true; _error = null; });
    try {
      // Look up driver by email in drivers table - must be verified/approved
      final results = await SupabaseConfig.client
          .from('drivers')
          .select('id, name, email, status, is_verified')
          .eq('email', email)
          .limit(1);
      final list = List<Map<String, dynamic>>.from(results);
      if (list.isEmpty) {
        setState(() { _verifyingDriver = false; _error = 'Chofer no encontrado. Debe estar registrado en Toro.'; });
        return;
      }
      final driver = list.first;
      final status = driver['status']?.toString() ?? '';
      final isVerified = driver['is_verified'] == true;
      if (!isVerified && status != 'approved' && status != 'active') {
        setState(() { _verifyingDriver = false; _error = 'El chofer no esta aprobado por Toro. Status: $status'; });
        return;
      }
      setState(() {
        _assignedDriverId = driver['id'] as String;
        _assignedDriverName = driver['name'] as String? ?? email;
        _driverVerified = true;
        _verifyingDriver = false;
        _error = null;
      });
      HapticService.mediumImpact();
    } catch (e) {
      setState(() { _verifyingDriver = false; _error = 'Error verificando chofer: $e'; });
    }
  }

  Future<void> _submitListing() async {
    final validation = _validateStep(_currentStep);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      // Get current position for contract signing GPS
      Position? signPos;
      try {
        signPos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        );
      } catch (_) {}

      final data = <String, dynamic>{
        'owner_id': widget.userId,
        'vehicle_type': _vehicleType,
        'vehicle_make': _makeCtrl.text.trim(),
        'vehicle_model': _modelCtrl.text.trim(),
        'vehicle_year': int.parse(_yearCtrl.text.trim()),
        'vehicle_color': _colorCtrl.text.trim().isNotEmpty ? _colorCtrl.text.trim() : null,
        'vehicle_plate': _plateCtrl.text.trim(),
        'vehicle_vin': _vinCtrl.text.trim().isNotEmpty ? _vinCtrl.text.trim() : null,
        // Legacy columns
        'make': _makeCtrl.text.trim(),
        'model': _modelCtrl.text.trim(),
        'year': int.parse(_yearCtrl.text.trim()),
        'plate_number': _plateCtrl.text.trim(),
        // Insurance
        'insurance_company': _insCompanyCtrl.text.trim().isNotEmpty ? _insCompanyCtrl.text.trim() : null,
        'insurance_policy_number': _insPolicyCtrl.text.trim().isNotEmpty ? _insPolicyCtrl.text.trim() : null,
        'insurance_expiry': _insExpiry?.toIso8601String().substring(0, 10),
        // Pricing
        'weekly_price': double.parse(_weeklyPriceCtrl.text.trim()),
        'per_km_price': _perKmPriceCtrl.text.trim().isNotEmpty ? double.parse(_perKmPriceCtrl.text.trim()) : null,
        'deposit_amount': _depositCtrl.text.trim().isNotEmpty ? double.parse(_depositCtrl.text.trim()) : 0,
        // Location
        'pickup_lat': _pickupLat,
        'pickup_lng': _pickupLng,
        'pickup_address': _pickupAddress,
        // Availability
        'available_from': _availableFrom?.toIso8601String().substring(0, 10),
        'available_to': _availableTo?.toIso8601String().substring(0, 10),
        // Contract signing
        'owner_signed_at': DateTime.now().toIso8601String(),
        'owner_sign_lat': signPos?.latitude,
        'owner_sign_lng': signPos?.longitude,
        'status': 'active',
        'created_at': DateTime.now().toIso8601String(),
      };

      // Autobus: include assigned driver
      if (_vehicleType == 'autobus' && _assignedDriverId != null) {
        data['assigned_driver_id'] = _assignedDriverId;
      }

      await SupabaseConfig.client.from('rental_vehicle_listings').insert(data);

      if (mounted) {
        Navigator.of(context).pop(true); // true = refresh
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Vehiculo publicado exitosamente'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error al publicar: $e';
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? (_availableFrom ?? now) : (_availableTo ?? now.add(const Duration(days: 30))),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: _PublishVehicleSheetState._accent),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isFrom) {
          _availableFrom = picked;
        } else {
          _availableTo = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final stepTitles = ['Vehiculo', 'Seguro', 'Precios', 'Ubicacion', 'Contrato'];
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: _accent.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          // Title row
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
            child: Row(
              children: [
                const Icon(Icons.directions_car_rounded, color: _accent, size: 24),
                const SizedBox(width: 12),
                Text('Publicar Vehiculo', style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(onPressed: () => Navigator.of(context).pop(), icon: Icon(Icons.close_rounded, color: AppColors.textTertiary)),
              ],
            ),
          ),
          // Step indicator
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(
              children: List.generate(stepTitles.length, (i) {
                final isActive = i == _currentStep;
                final isDone = i < _currentStep;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i < stepTitles.length - 1 ? 4 : 0),
                    child: Column(
                      children: [
                        Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: isDone ? AppColors.success : isActive ? _accent : AppColors.border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          stepTitles[i],
                          style: TextStyle(
                            color: isActive ? _accent : isDone ? AppColors.success : AppColors.textDisabled,
                            fontSize: 10, fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
          Divider(color: AppColors.border.withValues(alpha: 0.5), height: 1),
          // Error
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: AppColors.error, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: TextStyle(color: AppColors.error, fontSize: 13))),
                  ],
                ),
              ),
            ),
          // Step content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _buildStepContent(),
            ),
          ),
          // Navigation buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Row(
              children: [
                if (_currentStep > 0)
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: OutlinedButton(
                        onPressed: _prevStep,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text('Atras', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                if (_currentStep > 0) const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : (_currentStep == 4 ? _submitListing : _nextStep),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _currentStep == 4 ? AppColors.success : _accent,
                        disabledBackgroundColor: _accent.withValues(alpha: 0.3),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                          : Text(
                              _currentStep == 4 ? 'Firmar y Publicar' : 'Siguiente',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0: return _buildVehicleStep();
      case 1: return _buildInsuranceStep();
      case 2: return _buildPricingStep();
      case 3: return _buildLocationStep();
      case 4: return _buildContractStep();
      default: return const SizedBox.shrink();
    }
  }

  // ── Step 0: Vehicle Info ──
  Widget _buildVehicleStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Tipo de Vehiculo'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: _vehicleTypes.map((t) {
            final sel = _vehicleType == t;
            return GestureDetector(
              onTap: () { HapticService.lightImpact(); setState(() { _vehicleType = t; _driverVerified = false; _assignedDriverId = null; _assignedDriverName = null; _driverEmailCtrl.clear(); }); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: sel ? _accent.withValues(alpha: 0.15) : AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: sel ? _accent.withValues(alpha: 0.6) : AppColors.border, width: sel ? 1.5 : 1),
                ),
                child: Text(t.toUpperCase(), style: TextStyle(color: sel ? _accent : AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        _sectionLabel('Informacion del Vehiculo'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _field(_makeCtrl, 'Marca', 'Toyota')),
            const SizedBox(width: 12),
            Expanded(child: _field(_modelCtrl, 'Modelo', 'Camry')),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _field(_yearCtrl, 'Año', '2024', isNumber: true)),
            const SizedBox(width: 12),
            Expanded(child: _field(_colorCtrl, 'Color', 'Blanco')),
          ],
        ),
        const SizedBox(height: 12),
        _field(_plateCtrl, 'Placa', 'ABC-1234'),
        const SizedBox(height: 12),
        _field(_vinCtrl, 'VIN (opcional)', '1HGBH41JXMN109186'),
        // ── Autobus: Chofer obligatorio ──
        if (_vehicleType == 'autobus') ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEAB308).withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: const Color(0xFFEAB308), size: 20),
                    const SizedBox(width: 8),
                    const Text('Chofer Requerido', style: TextStyle(color: Color(0xFFEAB308), fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'La renta de autobus requiere un chofer aprobado por Toro. Ingresa el email del chofer para verificarlo.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _field(_driverEmailCtrl, 'Email del Chofer', 'chofer@email.com')),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _verifyingDriver ? null : _verifyDriver,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: _driverVerified ? const Color(0xFF22C55E) : _accent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _verifyingDriver
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Icon(_driverVerified ? Icons.check : Icons.search, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
                if (_driverVerified && _assignedDriverName != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified, color: Color(0xFF22C55E), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Chofer verificado: $_assignedDriverName',
                            style: const TextStyle(color: Color(0xFF22C55E), fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── Step 1: Insurance ──
  Widget _buildInsuranceStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Seguro del Vehiculo (Opcional)'),
        const SizedBox(height: 4),
        Text(
          'Si tu vehiculo tiene seguro, ingresa los datos para proteccion adicional',
          style: TextStyle(color: AppColors.textDisabled, fontSize: 12),
        ),
        const SizedBox(height: 16),
        _field(_insCompanyCtrl, 'Compañia de Seguro', 'Qualitas, HDI, GNP...'),
        const SizedBox(height: 12),
        _field(_insPolicyCtrl, 'Numero de Poliza', 'POL-123456'),
        const SizedBox(height: 12),
        _sectionLabel('Vencimiento de Poliza'),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _insExpiry ?? DateTime.now().add(const Duration(days: 180)),
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 730)),
              builder: (ctx, child) => Theme(
                data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: _accent)),
                child: child!,
              ),
            );
            if (picked != null && mounted) setState(() => _insExpiry = picked);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today_rounded, color: _accent, size: 18),
                const SizedBox(width: 12),
                Text(
                  _insExpiry != null
                      ? '${_insExpiry!.day}/${_insExpiry!.month}/${_insExpiry!.year}'
                      : 'Seleccionar fecha',
                  style: TextStyle(color: _insExpiry != null ? AppColors.textPrimary : AppColors.textDisabled, fontSize: 15),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Step 2: Pricing ──
  Widget _buildPricingStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Precios de Renta'),
        const SizedBox(height: 4),
        Text(
          'Toro aplica un multiplicador sobre tu precio para cubrir costos de plataforma',
          style: TextStyle(color: AppColors.textDisabled, fontSize: 12),
        ),
        const SizedBox(height: 16),
        _priceField(_weeklyPriceCtrl, 'Precio Semanal *', 'Ej: 350.00'),
        const SizedBox(height: 12),
        _priceField(_perKmPriceCtrl, 'Precio por Km (opcional)', 'Ej: 2.50'),
        const SizedBox(height: 12),
        _priceField(_depositCtrl, 'Deposito (opcional)', 'Ej: 500.00'),
        const SizedBox(height: 20),
        _sectionLabel('Disponibilidad (Opcional)'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _dateTile('Desde', _availableFrom, () => _pickDate(isFrom: true)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _dateTile('Hasta', _availableTo, () => _pickDate(isFrom: false)),
            ),
          ],
        ),
      ],
    );
  }

  // ── Step 3: Location ──
  Widget _buildLocationStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Ubicacion de Entrega/Recogida'),
        const SizedBox(height: 4),
        Text(
          'Donde se entregara y recogerá el vehiculo',
          style: TextStyle(color: AppColors.textDisabled, fontSize: 12),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: _getCurrentLocation,
            icon: const Icon(Icons.my_location_rounded, size: 20),
            label: const Text('Usar Mi Ubicacion Actual'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _accent,
              side: BorderSide(color: _accent.withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        if (_pickupAddress != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.location_on_rounded, color: AppColors.success, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ubicacion seleccionada', style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(_pickupAddress!, style: TextStyle(color: AppColors.textPrimary, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── Step 4: Contract ──
  Widget _buildContractStep() {
    final make = _makeCtrl.text.trim();
    final model = _modelCtrl.text.trim();
    final year = _yearCtrl.text.trim();
    final plate = _plateCtrl.text.trim();
    final weekly = _weeklyPriceCtrl.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Resumen del Vehiculo'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _accent.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              _summaryRow('Tipo', _vehicleType.toUpperCase()),
              _summaryRow('Vehiculo', '$year $make $model'),
              _summaryRow('Placa', plate),
              if (_colorCtrl.text.trim().isNotEmpty) _summaryRow('Color', _colorCtrl.text.trim()),
              if (_vinCtrl.text.trim().isNotEmpty) _summaryRow('VIN', _vinCtrl.text.trim()),
              if (_insCompanyCtrl.text.trim().isNotEmpty) _summaryRow('Seguro', _insCompanyCtrl.text.trim()),
              _summaryRow('Precio Semanal', '\$$weekly'),
              if (_pickupAddress != null) _summaryRow('Ubicacion', _pickupAddress!),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _sectionLabel('Contrato de Publicacion'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            'Al firmar este contrato, acepto que:\n\n'
            '• El vehiculo descrito esta en condiciones operativas\n'
            '• La informacion proporcionada es veridica\n'
            '• Autorizo a Toro a listar mi vehiculo en la plataforma\n'
            '• Toro aplicara un multiplicador sobre el precio para cubrir costos de plataforma\n'
            '• Soy responsable del seguro y mantenimiento del vehiculo\n'
            '• Puedo retirar mi vehiculo en cualquier momento que no tenga un contrato activo',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
          ),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () { HapticService.lightImpact(); setState(() => _agreedToTerms = !_agreedToTerms); },
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24, height: 24,
                decoration: BoxDecoration(
                  color: _agreedToTerms ? _accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _agreedToTerms ? _accent : AppColors.border, width: 2),
                ),
                child: _agreedToTerms ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Acepto los terminos y firmo digitalmente este contrato',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Helpers ──
  Widget _sectionLabel(String text) => Text(
    text,
    style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
  );

  Widget _field(TextEditingController ctrl, String label, String hint, {bool isNumber = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textDisabled),
        filled: true, fillColor: AppColors.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _accent, width: 1.5)),
      ),
    );
  }

  Widget _priceField(TextEditingController ctrl, String label, String hint) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textDisabled),
        prefixText: '\$ ',
        prefixStyle: TextStyle(color: _accent, fontSize: 15, fontWeight: FontWeight.w600),
        filled: true, fillColor: AppColors.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _accent, width: 1.5)),
      ),
    );
  }

  Widget _dateTile(String label, DateTime? date, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: AppColors.textDisabled, fontSize: 11, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.calendar_today_rounded, color: _accent, size: 16),
                const SizedBox(width: 8),
                Text(
                  date != null ? '${date.day}/${date.month}/${date.year}' : 'Seleccionar',
                  style: TextStyle(color: date != null ? AppColors.textPrimary : AppColors.textDisabled, fontSize: 14),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MY RENTALS SHEET - Published listings + active rental activity
// ═══════════════════════════════════════════════════════════════════════════════

class _MyRentalsSheet extends StatefulWidget {
  final String userId;
  const _MyRentalsSheet({required this.userId});

  @override
  State<_MyRentalsSheet> createState() => _MyRentalsSheetState();
}

class _MyRentalsSheetState extends State<_MyRentalsSheet> {
  static const _accent = Color(0xFF8B5CF6);
  List<Map<String, dynamic>> _listings = [];
  // Active agreements for each listing (listing_id → agreement)
  Map<String, Map<String, dynamic>> _activeAgreements = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final client = SupabaseConfig.client;
      // Load all listings for this owner
      final listings = await client
          .from('rental_vehicle_listings')
          .select('*')
          .eq('owner_id', widget.userId)
          .order('created_at', ascending: false);

      final listingsList = List<Map<String, dynamic>>.from(listings);

      // Load active agreements for these listings
      final listingIds = listingsList.map((l) => l['id'] as String).toList();
      Map<String, Map<String, dynamic>> agreements = {};

      if (listingIds.isNotEmpty) {
        try {
          final agr = await client
              .from('rental_agreements')
              .select('*')
              .inFilter('listing_id', listingIds)
              .inFilter('status', ['active', 'pending']);

          for (final a in (agr as List)) {
            final lid = a['listing_id'] as String?;
            if (lid != null) agreements[lid] = Map<String, dynamic>.from(a);
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _listings = listingsList;
          _activeAgreements = agreements;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error al cargar: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleListingStatus(Map<String, dynamic> listing) async {
    final id = listing['id'] as String;
    final currentStatus = listing['status'] as String? ?? 'active';
    final newStatus = currentStatus == 'active' ? 'inactive' : 'active';

    try {
      await SupabaseConfig.client
          .from('rental_vehicle_listings')
          .update({'status': newStatus})
          .eq('id', id);
      HapticService.mediumImpact();
      _loadData(); // Refresh
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: _accent.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
            child: Row(
              children: [
                const Icon(Icons.receipt_long_rounded, color: _accent, size: 24),
                const SizedBox(width: 12),
                Text('Mis Rentas', style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(onPressed: () => Navigator.of(context).pop(), icon: Icon(Icons.close_rounded, color: AppColors.textTertiary)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Divider(color: AppColors.border.withValues(alpha: 0.5), height: 1),
          // Content
          Flexible(
            child: _isLoading
                ? const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: _accent)))
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.error_outline, color: AppColors.error, size: 40),
                              const SizedBox(height: 12),
                              Text(_error!, style: TextStyle(color: AppColors.textTertiary, fontSize: 14), textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      )
                    : _listings.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(40),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.car_rental_rounded, color: AppColors.textDisabled, size: 48),
                                  const SizedBox(height: 16),
                                  Text('No tienes vehiculos publicados', style: TextStyle(color: AppColors.textTertiary, fontSize: 15, fontWeight: FontWeight.w500)),
                                  const SizedBox(height: 6),
                                  Text('Publica un vehiculo para comenzar a rentar', style: TextStyle(color: AppColors.textDisabled, fontSize: 13), textAlign: TextAlign.center),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _listings.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, index) => _buildListingCard(_listings[index]),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildListingCard(Map<String, dynamic> listing) {
    final id = listing['id'] as String;
    final make = listing['vehicle_make'] ?? listing['make'] ?? '';
    final model = listing['vehicle_model'] ?? listing['model'] ?? '';
    final year = (listing['vehicle_year'] ?? listing['year'])?.toString() ?? '';
    final plate = listing['vehicle_plate'] ?? listing['plate_number'] ?? '';
    final type = listing['vehicle_type'] ?? '';
    final color = listing['vehicle_color'] ?? '';
    final status = listing['status'] as String? ?? 'active';
    final weeklyPrice = listing['weekly_price']?.toString() ?? '0';
    final pickupAddr = listing['pickup_address'] as String?;
    final isActive = status == 'active';

    final agreement = _activeAgreements[id];
    final hasRenter = agreement != null;

    return GestureDetector(
      onTap: hasRenter ? () => _showActivityDetail(listing, agreement) : null,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasRenter ? AppColors.warning.withValues(alpha: 0.5) : isActive ? _accent.withValues(alpha: 0.3) : AppColors.border,
            width: hasRenter ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: hasRenter ? AppColors.warning.withValues(alpha: 0.15) : isActive ? _accent.withValues(alpha: 0.15) : AppColors.cardHover,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    hasRenter ? Icons.person_rounded : Icons.directions_car_rounded,
                    color: hasRenter ? AppColors.warning : isActive ? _accent : AppColors.textDisabled,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$year $make $model', style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _statusBadge(hasRenter ? 'Rentado' : isActive ? 'Publicado' : 'Inactivo',
                            hasRenter ? AppColors.warning : isActive ? AppColors.success : AppColors.textDisabled),
                          const SizedBox(width: 8),
                          Text('\$$weeklyPrice/sem', style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
                if (hasRenter)
                  Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary, size: 22)
                else
                  // Toggle active/inactive
                  GestureDetector(
                    onTap: () => _toggleListingStatus(listing),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isActive ? AppColors.error.withValues(alpha: 0.1) : AppColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isActive ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: isActive ? AppColors.error : AppColors.success,
                        size: 20,
                      ),
                    ),
                  ),
              ],
            ),
            // Vehicle details row
            if (type.isNotEmpty || plate.isNotEmpty || color.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8, runSpacing: 6,
                children: [
                  if (type.isNotEmpty) _infoPill(Icons.category_rounded, type.toUpperCase()),
                  if (plate.isNotEmpty) _infoPill(Icons.confirmation_number_rounded, plate),
                  if (color.isNotEmpty) _infoPill(Icons.palette_rounded, color),
                ],
              ),
            ],
            // Location
            if (pickupAddr != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.location_on_rounded, color: AppColors.textDisabled, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(pickupAddr, style: TextStyle(color: AppColors.textDisabled, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ],
            // Renter info if active
            if (hasRenter) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.person_outline_rounded, color: AppColors.warning, size: 18),
                    const SizedBox(width: 8),
                    Text('Vehiculo en uso', style: TextStyle(color: AppColors.warning, fontSize: 13, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('Ver actividad →', style: TextStyle(color: AppColors.warning.withValues(alpha: 0.7), fontSize: 12)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _infoPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.cardHover,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.textDisabled, size: 12),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: AppColors.textTertiary, fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  void _showActivityDetail(Map<String, dynamic> listing, Map<String, dynamic> agreement) {
    final make = listing['vehicle_make'] ?? listing['make'] ?? '';
    final model = listing['vehicle_model'] ?? listing['model'] ?? '';
    final year = (listing['vehicle_year'] ?? listing['year'])?.toString() ?? '';
    final plate = listing['vehicle_plate'] ?? listing['plate_number'] ?? '';
    final agrStatus = agreement['status'] as String? ?? 'active';
    final startDate = agreement['start_date'] as String?;
    final endDate = agreement['end_date'] as String?;
    final totalCost = agreement['total_cost'];
    final renterId = agreement['renter_id'] as String?;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  const Icon(Icons.analytics_rounded, color: _accent, size: 24),
                  const SizedBox(width: 12),
                  Text('Actividad del Vehiculo', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: Icon(Icons.close_rounded, color: AppColors.textTertiary)),
                ],
              ),
            ),
            Divider(color: AppColors.border.withValues(alpha: 0.5), height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Vehicle
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                    child: Column(
                      children: [
                        _detailRow('Vehiculo', '$year $make $model'),
                        _detailRow('Placa', plate),
                        _detailRow('Estado', agrStatus == 'active' ? 'En uso' : agrStatus),
                        if (startDate != null) _detailRow('Inicio', startDate.substring(0, 10)),
                        if (endDate != null) _detailRow('Fin', endDate.substring(0, 10)),
                        if (totalCost != null) _detailRow('Costo Total', '\$$totalCost'),
                        if (renterId != null) _detailRow('Renter ID', renterId.substring(0, 8)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text(label, style: TextStyle(color: AppColors.textTertiary, fontSize: 13))),
          Expanded(child: Text(value, style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GPS TRACKING SHEET - Active vehicle tracking with checkin data
// ═══════════════════════════════════════════════════════════════════════════════

class _GpsTrackingSheet extends StatefulWidget {
  final String userId;
  const _GpsTrackingSheet({required this.userId});

  @override
  State<_GpsTrackingSheet> createState() => _GpsTrackingSheetState();
}

class _GpsTrackingSheetState extends State<_GpsTrackingSheet> {
  static const _accent = Color(0xFF8B5CF6);
  List<Map<String, dynamic>> _rentedVehicles = []; // listings with active agreements
  Map<String, List<Map<String, dynamic>>> _checkins = {}; // listing_id → checkins
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTracking();
  }

  Future<void> _loadTracking() async {
    try {
      final client = SupabaseConfig.client;

      // 1. Get owner's listings
      final listings = await client
          .from('rental_vehicle_listings')
          .select('*')
          .eq('owner_id', widget.userId)
          .order('created_at', ascending: false);

      final listingsList = List<Map<String, dynamic>>.from(listings);
      final listingIds = listingsList.map((l) => l['id'] as String).toList();

      if (listingIds.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // 2. Get active agreements
      final agreements = await client
          .from('rental_agreements')
          .select('*')
          .inFilter('listing_id', listingIds)
          .eq('status', 'active');

      final activeListingIds = <String>{};
      for (final a in (agreements as List)) {
        activeListingIds.add(a['listing_id'] as String);
      }

      // Filter listings to only those with active agreements
      final rentedListings = listingsList.where((l) => activeListingIds.contains(l['id'])).toList();

      // 3. Load recent checkins for rented vehicles
      Map<String, List<Map<String, dynamic>>> checkinMap = {};
      for (final lid in activeListingIds) {
        try {
          final checks = await client
              .from('rental_checkins')
              .select('*')
              .eq('listing_id', lid)
              .order('created_at', ascending: false)
              .limit(5);
          checkinMap[lid] = List<Map<String, dynamic>>.from(checks);
        } catch (_) {
          checkinMap[lid] = [];
        }
      }

      if (mounted) {
        setState(() {
          _rentedVehicles = rentedListings;
          _checkins = checkinMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error al cargar rastreo: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: _accent.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
            child: Row(
              children: [
                const Icon(Icons.gps_fixed_rounded, color: _accent, size: 24),
                const SizedBox(width: 12),
                Text('GPS Tracking', style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(onPressed: () => Navigator.of(context).pop(), icon: Icon(Icons.close_rounded, color: AppColors.textTertiary)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Divider(color: AppColors.border.withValues(alpha: 0.5), height: 1),
          // Content
          Flexible(
            child: _isLoading
                ? const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: _accent)))
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.error_outline, color: AppColors.error, size: 40),
                              const SizedBox(height: 12),
                              Text(_error!, style: TextStyle(color: AppColors.textTertiary, fontSize: 14), textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      )
                    : _rentedVehicles.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(40),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.gps_off_rounded, color: AppColors.textDisabled, size: 48),
                                  const SizedBox(height: 16),
                                  Text('Sin vehiculos rastreados', style: TextStyle(color: AppColors.textTertiary, fontSize: 15, fontWeight: FontWeight.w500)),
                                  const SizedBox(height: 6),
                                  Text('El rastreo GPS se activa cuando un vehiculo esta rentado', style: TextStyle(color: AppColors.textDisabled, fontSize: 13), textAlign: TextAlign.center),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _rentedVehicles.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 14),
                            itemBuilder: (context, index) {
                              final vehicle = _rentedVehicles[index];
                              return _buildTrackedVehicle(vehicle);
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackedVehicle(Map<String, dynamic> vehicle) {
    final id = vehicle['id'] as String;
    final make = vehicle['vehicle_make'] ?? vehicle['make'] ?? '';
    final model = vehicle['vehicle_model'] ?? vehicle['model'] ?? '';
    final year = (vehicle['vehicle_year'] ?? vehicle['year'])?.toString() ?? '';
    final plate = vehicle['vehicle_plate'] ?? vehicle['plate_number'] ?? '';
    final checkins = _checkins[id] ?? [];
    final lastCheckin = checkins.isNotEmpty ? checkins.first : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Vehicle header
          Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(Icons.gps_fixed_rounded, color: AppColors.success, size: 22),
                    Positioned(
                      right: 8, top: 8,
                      child: Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: AppColors.success.withValues(alpha: 0.5), blurRadius: 4)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$year $make $model', style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 6, height: 6, decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                              const SizedBox(width: 5),
                              Text('GPS Activo', style: TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        if (plate.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(plate, style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Last checkin info
          if (lastCheckin != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.cardHover,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ultimo Check-in', style: TextStyle(color: AppColors.textTertiary, fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  if (lastCheckin['lat'] != null && lastCheckin['lng'] != null)
                    Row(
                      children: [
                        Icon(Icons.location_on_rounded, color: _accent, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          '${(lastCheckin['lat'] as num).toStringAsFixed(5)}, ${(lastCheckin['lng'] as num).toStringAsFixed(5)}',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  if (lastCheckin['mileage'] != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.speed_rounded, color: _accent, size: 14),
                        const SizedBox(width: 6),
                        Text('${lastCheckin['mileage']} mi', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ],
                  if (lastCheckin['fuel_level'] != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.local_gas_station_rounded, color: _accent, size: 14),
                        const SizedBox(width: 6),
                        Text('${lastCheckin['fuel_level']}%', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ],
                  if (lastCheckin['created_at'] != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.access_time_rounded, color: AppColors.textDisabled, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          (lastCheckin['created_at'] as String).substring(0, 16).replaceAll('T', ' '),
                          style: TextStyle(color: AppColors.textDisabled, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
          // Checkin history
          if (checkins.length > 1) ...[
            const SizedBox(height: 8),
            Text('Historial (${checkins.length})', style: TextStyle(color: AppColors.textDisabled, fontSize: 11)),
          ],
        ],
      ),
    );
  }
}
