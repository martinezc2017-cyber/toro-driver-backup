import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
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
import '../services/audit_service.dart';
import '../services/mapbox_navigation_service.dart';
import 'earnings_screen.dart';
import 'rides_screen.dart';
import 'profile_screen.dart';
import 'navigation_map_screen.dart';
import '../widgets/toro_3d_pin.dart';

/// TORO DRIVER - Luxury Uber Black Driver Home Screen
/// Clean, powerful, confident, luxurious
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int _selectedNavIndex = 0;

  // Collapsible earnings states
  bool _showDailyEarnings = true;
  bool _showWeeklyEarnings = true;

  // === APP LIFECYCLE OPTIMIZATION ===
  bool _isAppInBackground = false;

  // Navigation mode - user must explicitly enter
  bool _isInNavigationMode = false;

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
        // App going to background - reduce GPS frequency
        _isAppInBackground = true;
        debugPrint('📱 App -> Background: Reducing GPS updates');
        break;
      case AppLifecycleState.resumed:
        // App coming to foreground - restore normal operations
        _isAppInBackground = false;
        debugPrint('📱 App -> Foreground: Restoring GPS updates');
        // Force a UI refresh when coming back
        if (mounted) setState(() {});
        break;
      case AppLifecycleState.detached:
        break;
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
      final locationProvider = Provider.of<LocationProvider>(context, listen: false);
      locationProvider.stopTracking();
      debugPrint('HomeScreen: GPS tracking stopped due to force disconnect');

      // Log to audit
      final driver = driverProvider.driver;
      if (driver != null) {
        AuditService.instance.logOffline(
          driverId: driver.id,
          reason: 'force_disconnect_${driverProvider.forceDisconnectReason ?? "unknown"}',
        );
      }

      // Show dialog explaining why
      _showForceDisconnectDialog(driverProvider.forceDisconnectReason);

      // Clear the flag so dialog doesn't show again
      driverProvider.clearForceDisconnectFlag();
    }

    // Check for approval notification
    if (driverProvider.wasJustApproved) {
      debugPrint('HomeScreen: Driver was just approved, showing notification');
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
              child: const Icon(Icons.check_circle, color: AppColors.success, size: 28),
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
        message = 'Has sido desconectado porque hay documentos pendientes por completar. '
                  'Por favor completa todos los documentos requeridos para volver a estar online.';
        icon = Icons.description_outlined;
        color = const Color(0xFFFF9500);
        break;
      case 'pending_admin_approval':
        title = 'Aprobación Pendiente';
        message = 'Has sido desconectado porque tu cuenta está pendiente de aprobación. '
                  'Te notificaremos cuando seas aprobado.';
        icon = Icons.hourglass_top_rounded;
        color = const Color(0xFFFFD60A);
        break;
      case 'account_suspended':
        title = 'Cuenta Suspendida';
        message = 'Tu cuenta ha sido suspendida. Has sido desconectado automáticamente. '
                  'Contacta a soporte para más información.';
        icon = Icons.block_rounded;
        color = const Color(0xFFFF3B30);
        break;
      case 'account_rejected':
        title = 'Solicitud Rechazada';
        message = 'Tu solicitud de conductor fue rechazada. Has sido desconectado. '
                  'Contacta a soporte si crees que es un error.';
        icon = Icons.cancel_rounded;
        color = const Color(0xFFFF3B30);
        break;
      default:
        title = 'Desconectado';
        message = 'Has sido desconectado automáticamente porque ya no cumples los requisitos '
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
      final driverProvider = Provider.of<DriverProvider>(context, listen: false);
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
        // Hide bottom nav ONLY when in full-screen navigation mode
        bottomNavigationBar: _isInNavigationMode ? null : _buildBottomNav(),
      ),
    );

    // On web, constrain to mobile-like width
    if (!kIsWeb) return scaffold;

    return Container(
      color: AppColors.background,
      child: Center(
        child: SizedBox(
          width: _maxWebWidth,
          child: scaffold,
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_selectedNavIndex) {
      case 1:
        return const EarningsScreen();
      case 2:
        return const RidesScreen();
      case 3:
        return const ProfileScreen();
      default:
        return Consumer<RideProvider>(
          builder: (context, rideProvider, child) {
            // Show navigation/map when user explicitly entered navigation mode
            if (_isInNavigationMode) {
              // Key forces complete rebuild when ride changes (avoids ghost map state)
              return _ActiveRideNavigation(
                key: ValueKey('nav_${rideProvider.activeRide?.id ?? 'idle'}'),
                ride: rideProvider.activeRide, // Can be null - will just show map
                onExitNavigation: () {
                  setState(() => _isInNavigationMode = false);
                },
              );
            }

            // Normal home screen
            return SafeArea(
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildIncomingRides(),
                          _buildEarningsCard(),
                          const SizedBox(height: 12),
                          _buildTodayActivity(),
                          const SizedBox(height: 12),
                          _buildQuickActionButtons(),
                          const SizedBox(height: 12),
                          _buildMapButton(),
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
        setState(() => _isInNavigationMode = true);
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
              child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 28),
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
              child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
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
                  debugPrint('HomeScreen: Toggle tapped!');
                  HapticService.lightImpact();

                  // Check if driver can go online (Uber-style: all docs + admin approved)
                  final driver = driverProvider.driver;
                  if (driver != null && !driver.canGoOnline) {
                    // Log the blocked attempt for audit (DB + console)
                    debugPrint('HomeScreen: [AUDIT] Driver ${driver.id} blocked from going online');
                    debugPrint('  - adminApproved: ${driver.adminApproved}');
                    debugPrint('  - allDocsSigned: ${driver.allDocumentsSigned}');
                    debugPrint('  - canReceiveRides: ${driver.canReceiveRides}');
                    debugPrint('  - onboardingStage: ${driver.onboardingStage}');

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
                      blockReason = 'Completa todos los documentos requeridos para poder activarte:\n\n'
                          '${driver.agreementSigned ? '✓' : '✗'} Driver Agreement\n'
                          '${driver.icaSigned ? '✓' : '✗'} Contractor Agreement (ICA)\n'
                          '${driver.safetyPolicySigned ? '✓' : '✗'} Safety Policy\n'
                          '${driver.bgcConsentSigned ? '✓' : '✗'} Background Check Consent';
                      blockIcon = Icons.description_outlined;
                      blockColor = const Color(0xFFFF9500);
                    } else if (!driver.adminApproved) {
                      blockTitle = 'Aprobación Pendiente';
                      blockReason = 'Tus documentos están completos.\n\n'
                          'Tu cuenta está siendo revisada por nuestro equipo. '
                          'Te notificaremos por email cuando seas aprobado.';
                      blockIcon = Icons.hourglass_top_rounded;
                      blockColor = const Color(0xFFFFD60A);
                    } else if (driver.onboardingStage == 'suspended') {
                      blockTitle = 'Cuenta Suspendida';
                      blockReason = 'Tu cuenta ha sido suspendida. Contacta a soporte para más información.';
                      blockIcon = Icons.block_rounded;
                      blockColor = const Color(0xFFFF3B30);
                    } else if (driver.onboardingStage == 'rejected') {
                      blockTitle = 'Solicitud Rechazada';
                      blockReason = 'Tu solicitud no fue aprobada. Contacta a soporte si crees que es un error.';
                      blockIcon = Icons.cancel_rounded;
                      blockColor = const Color(0xFFFF3B30);
                    } else {
                      blockTitle = 'No Disponible';
                      blockReason = 'No puedes ir online en este momento. Contacta a soporte.';
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
                            Text(blockTitle, style: TextStyle(color: AppColors.textPrimary)),
                          ],
                        ),
                        content: Text(
                          blockReason,
                          style: TextStyle(color: AppColors.textSecondary, height: 1.5),
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
                            style: ElevatedButton.styleFrom(backgroundColor: blockColor),
                            child: const Text('Entendido'),
                          ),
                        ],
                      ),
                    );
                    return; // Don't allow toggle
                  }

                  final locationProvider = Provider.of<LocationProvider>(context, listen: false);

                  if (!isOnline) {
                    // Going ONLINE - Initialize GPS and start tracking
                    debugPrint('HomeScreen: Going online, initializing GPS...');
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
                                Icon(Icons.location_off_rounded, color: const Color(0xFFFF9500)),
                                const SizedBox(width: 12),
                                Text('location_required'.tr(), style: TextStyle(color: AppColors.textPrimary)),
                              ],
                            ),
                            content: Text(
                              'location_required_msg'.tr(),
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text('cancel'.tr(), style: TextStyle(color: AppColors.textSecondary)),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF9500)),
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
                      await locationProvider.startTracking(driverProvider.driver!.id);
                      debugPrint('HomeScreen: GPS tracking started');

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
                    debugPrint('HomeScreen: GPS tracking stopped');

                    // Log offline event to audit
                    if (driverProvider.driver != null) {
                      AuditService.instance.logOffline(
                        driverId: driverProvider.driver!.id,
                        reason: 'manual_toggle',
                      );
                    }
                  }

                  await driverProvider.toggleOnlineStatus();
                  debugPrint('HomeScreen: Toggle completed, new isOnline: ${driverProvider.isOnline}');
                },
                child: _LuxuryToggle(isOnline: isOnline),
              ),
              const SizedBox(width: 12),
              // Status Bar - FireGlow style
              Expanded(
                child: _FireGlowStatusBar(isOnline: isOnline),
              ),
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

  Widget _buildOfflineRidesNotification(int rideCount, DriverProvider driverProvider) {
    return GestureDetector(
      onTap: () async {
        HapticService.mediumImpact();
        // Show dialog to go online
        final shouldGoOnline = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.local_shipping_outlined, color: const Color(0xFFFF9500)),
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
                child: Text('not_now'.tr(), style: TextStyle(color: AppColors.textTertiary)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF9500),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text('go_online'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );

        if (shouldGoOnline == true) {
          // Get provider reference before async operations
          if (!mounted) return;
          final locationProvider = Provider.of<LocationProvider>(context, listen: false);

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
                  LatLng(ride.pickupLocation.latitude, ride.pickupLocation.longitude),
                );
                pickupDistanceMiles = distanceMeters / 1609.34; // meters to miles
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
                      if (driverId != null) {
                        // Accept ride - UI will auto-switch to navigation mode via rideProvider.hasActiveRide
                        await rideProvider.acceptRide(ride.id, driverId);
                        // Close the preview sheet
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      }
                    },
                  );
                },
                onAccept: () async {
                  HapticService.mediumImpact();
                  final driverId = driverProvider.driver?.id;
                  if (driverId != null) {
                    // Accept ride - UI will auto-switch to navigation mode via rideProvider.hasActiveRide
                    await rideProvider.acceptRide(ride.id, driverId);
                    // No navigation - same screen transforms to show navigation UI
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
                  Text('$todayRides 🚗 · $onlineTime', style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 8),
              // Earnings row - both cards side by side
              Row(
                children: [
                  // Daily Earnings - tappable to hide
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _showDailyEarnings = !_showDailyEarnings),
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
                                Text('Hoy', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                                Icon(
                                  _showDailyEarnings ? Icons.visibility : Icons.visibility_off,
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
                                : _TamagotchiPet(color: const Color(0xFFFF9500), seed: 1),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Weekly Earnings - tappable to hide (deposited on Sunday)
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _showWeeklyEarnings = !_showWeeklyEarnings),
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
                                Text('Semana', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                                Icon(
                                  _showWeeklyEarnings ? Icons.visibility : Icons.visibility_off,
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
                                : _TamagotchiPet(color: AppColors.success, seed: 2),
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
              _buildStatItem(Icons.directions_car_outlined, '$todayRides', 'rides_label'.tr()),
              Container(width: 1, height: 30, color: AppColors.border.withValues(alpha: 0.3)),
              _buildStatItem(Icons.schedule_outlined, onlineTime, 'duration_label'.tr()),
              Container(width: 1, height: 30, color: AppColors.border.withValues(alpha: 0.3)),
              _buildStatItem(Icons.route_outlined, '${(distanceToday * 0.621371).toStringAsFixed(1)} mi', 'distance_label'.tr()),
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
        Text(value, style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
        Text(label, style: TextStyle(color: AppColors.textTertiary, fontSize: 9)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // QUICK ACTION BUTTONS - Messages & Ride History
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildQuickActionButtons() {
    return Row(
      children: [
        Expanded(
          child: _LuxuryActionButton(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'messages'.tr(),
            onTap: () {
              HapticService.lightImpact();
              Navigator.pushNamed(context, '/messages');
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _LuxuryActionButton(
            icon: Icons.history_rounded,
            label: 'ride_history'.tr(),
            onTap: () {
              HapticService.lightImpact();
              Navigator.pushNamed(context, '/rides');
            },
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MAP BUTTON - Go to Map
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMapButton() {
    return Consumer<RideProvider>(
      builder: (context, rideProvider, child) {
        final hasActiveRide = rideProvider.hasActiveRide && rideProvider.activeRide != null;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Main button with dynamic glow
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: hasActiveRide
                    ? [
                        BoxShadow(
                          color: const Color(0xFF10B981).withOpacity(0.5),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                        BoxShadow(
                          color: const Color(0xFF10B981).withOpacity(0.3),
                          blurRadius: 40,
                          spreadRadius: 5,
                        ),
                      ]
                    : null,
              ),
              child: NeonButton(
                text: 'go_to_map'.tr(),
                icon: hasActiveRide ? Icons.navigation_rounded : Icons.map_outlined,
                onPressed: () {
                  HapticService.lightImpact();
                  setState(() => _isInNavigationMode = true);
                },
                style: hasActiveRide ? NeonButtonStyle.success : NeonButtonStyle.primary,
              ),
            ),
            // Notification badge when active ride
            if (hasActiveRide)
              Positioned(
                top: -8,
                right: -8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF059669)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withOpacity(0.5),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'VIAJE ACTIVO',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ROUTE PREVIEW - Shows mini map when tapping a ride card
  // ═══════════════════════════════════════════════════════════════════════════

  void _showRoutePreview(BuildContext context, RideModel ride, {VoidCallback? onAccept}) {
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
    return FireGlowBottomNavBar(
      currentIndex: _selectedNavIndex,
      onTap: (index) {
        setState(() => _selectedNavIndex = index);
      },
      items: [
        FireGlowNavItem(
          icon: Icons.home_outlined,
          activeIcon: Icons.home_rounded,
          label: 'nav_home'.tr(),
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
          color: _isPressed
              ? AppColors.cardHover
              : AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.border.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
        child: Stack(
          children: [
            Icon(
              widget.icon,
              color: AppColors.textSecondary,
              size: 22,
            ),
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
              color: const Color(0xFF8B5CF6).withValues(alpha: _isPressed ? 0.2 : 0.12),
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
            Icon(
              widget.icon,
              color: const Color(0xFF8B5CF6),
              size: 20,
            ),
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
    const dayLetters = ['', 'L', 'M', 'X', 'J', 'V', 'S', 'D']; // 1=Monday, 7=Sunday
    final sortedDays = List<int>.from(days)..sort();
    return sortedDays.map((d) => d >= 1 && d <= 7 ? dayLetters[d] : '?').join(' ');
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
              border: Border.all(color: _fireColor.withValues(alpha: 0.3 * pulse)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: Type badge + Client + Fare
                Row(
                children: [
                  // Type badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _fireColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_getRideTypeIcon(), style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 3),
                        Text(_getRideTypeLabel(), style: TextStyle(color: _fireColor, fontSize: 10, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  if (widget.ride.isGoodTipper) ...[
                    const SizedBox(width: 4),
                    Text('💰', style: const TextStyle(fontSize: 10)),
                  ],
                  // Round Trip badge for carpool
                  if (widget.ride.isRoundTrip) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF00C853), Color(0xFF00897B)]),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('round_trip'.tr(), style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                    ),
                  ],
                  const SizedBox(width: 8),
                  // Client avatar + name
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: _fireColor.withValues(alpha: 0.2),
                    backgroundImage: widget.ride.passengerImageUrl != null ? NetworkImage(widget.ride.passengerImageUrl!) : null,
                    child: widget.ride.passengerImageUrl == null
                        ? Text(widget.ride.passengerName.isNotEmpty ? widget.ride.passengerName[0].toUpperCase() : 'C',
                            style: TextStyle(color: _fireColor, fontWeight: FontWeight.w600, fontSize: 10))
                        : null,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(widget.ride.passengerName, style: TextStyle(color: AppColors.textPrimary, fontSize: 12), overflow: TextOverflow.ellipsis),
                  ),
                  if (widget.ride.passengerRating > 0) ...[
                    Icon(Icons.star_rounded, color: Colors.amber, size: 12),
                    Text(widget.ride.passengerRating.toStringAsFixed(1), style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  ],
                ],
              ),
              const SizedBox(height: 8),

              // Locations in compact format
              Row(
                children: [
                  Column(
                    children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                      Container(width: 1, height: 16, color: AppColors.textTertiary.withValues(alpha: 0.3)),
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: _fireColor, shape: BoxShape.circle)),
                    ],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.ride.pickupLocation.address ?? 'pickup_location'.tr(),
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        Text(widget.ride.dropoffLocation.address ?? 'destination'.tr(),
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // EARNINGS DISPLAY - Simple: Total + Your Earnings (what driver cares about)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.success.withValues(alpha: 0.15),
                      AppColors.success.withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Total fare (what customer pays)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total viaje', style: TextStyle(color: AppColors.textTertiary, fontSize: 9)),
                        Text('\$${widget.ride.fare.toStringAsFixed(2)}', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                    // Arrow
                    Icon(Icons.arrow_forward_rounded, color: AppColors.textTertiary, size: 14),
                    // Driver earnings (green - prominent)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Tu ganancia', style: TextStyle(color: AppColors.success, fontSize: 9, fontWeight: FontWeight.w600)),
                        Text('\$${widget.ride.driverEarnings.toStringAsFixed(2)}', style: TextStyle(color: AppColors.success, fontSize: 16, fontWeight: FontWeight.bold)),
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
                    Icon(Icons.near_me, color: Colors.cyan, size: 12),
                    const SizedBox(width: 2),
                    Text('${widget.pickupDistanceMiles!.toStringAsFixed(1)} mi', style: TextStyle(color: Colors.cyan, fontSize: 10, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Container(width: 1, height: 12, color: AppColors.textTertiary.withValues(alpha: 0.3)),
                    const SizedBox(width: 8),
                  ],
                  // Trip distance
                  Icon(Icons.route_outlined, color: AppColors.textTertiary, size: 12),
                  const SizedBox(width: 2),
                  Text('${(widget.ride.distanceKm * 0.621371).toStringAsFixed(1)} mi', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                  const SizedBox(width: 12),
                  // Trip time
                  Icon(Icons.schedule_outlined, color: AppColors.textTertiary, size: 12),
                  const SizedBox(width: 2),
                  Text('~${widget.ride.estimatedMinutes} min', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                ],
              ),
              // Carpool info: recurring days + seats (only for carpool type)
              if (widget.ride.type == RideType.carpool && widget.ride.recurringDays.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Recurring days
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_today, color: Colors.blue, size: 10),
                          const SizedBox(width: 4),
                          Text(
                            _formatRecurringDays(widget.ride.recurringDays),
                            style: const TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.w600),
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
                            color: isOccupied ? AppColors.success : AppColors.textTertiary,
                            size: 14,
                          ),
                        );
                      }),
                    ),
                    Text(
                      '${widget.ride.filledSeats}/3',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
                    ),
                    // Return time if available
                    if (widget.ride.returnTime != null) ...[
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.purple.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.replay, color: Colors.purple, size: 10),
                            const SizedBox(width: 3),
                            Text(
                              widget.ride.returnTime!,
                              style: const TextStyle(color: Colors.purple, fontSize: 10, fontWeight: FontWeight.w600),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.error.withValues(alpha: 0.5), width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.close_rounded, color: AppColors.error, size: 18),
                          const SizedBox(width: 4),
                          Text('RECHAZAR', style: TextStyle(color: AppColors.error, fontSize: 11, fontWeight: FontWeight.bold)),
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
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF22C55E),
                              const Color(0xFF16A34A),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [BoxShadow(
                            color: AppColors.success.withValues(alpha: 0.5),
                            blurRadius: 10,
                            spreadRadius: 1,
                          )],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              'ACEPTAR VIAJE',
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
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

    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
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
                color: const Color(0xFFFF9500).withValues(alpha: _animation.value * 0.6),
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

class _RoutePreviewSheetState extends State<_RoutePreviewSheet> with TickerProviderStateMixin {
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
      debugPrint('Route fetch error: $e');
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
                  child: const Icon(Icons.route_rounded, color: Color(0xFFFF9500), size: 22),
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
                    onTap: () => setState(() => _showDailyEarnings = !_showDailyEarnings),
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
                                _showDailyEarnings ? Icons.visibility : Icons.visibility_off,
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
                    onTap: () => setState(() => _showWeeklyEarnings = !_showWeeklyEarnings),
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
                                _showWeeklyEarnings ? Icons.visibility : Icons.visibility_off,
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
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF9500)))
                : ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    child: AnimatedBuilder(
                      animation: _glowProgress,
                      builder: (context, child) {
                        final glowPoint = _getPointAtProgress(_glowProgress.value);

                        return FlutterMap(
                          options: MapOptions(
                            initialCenter: LatLng(
                              (pickup.latitude + dropoff.latitude) / 2,
                              (pickup.longitude + dropoff.longitude) / 2,
                            ),
                            initialZoom: 13,
                            interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                            ),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                              subdomains: const ['a', 'b', 'c', 'd'],
                            ),
                            // Route line with glow effect
                            if (_routePoints.isNotEmpty)
                              PolylineLayer(
                                polylines: [
                                  // Base route - darker
                                  Polyline(
                                    points: _routePoints,
                                    color: const Color(0xFFFF9500).withValues(alpha: 0.3),
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
                                            color: const Color(0xFFFF9500).withValues(alpha: 0.8),
                                            blurRadius: 15,
                                            spreadRadius: 5,
                                          ),
                                          BoxShadow(
                                            color: const Color(0xFFFFD700).withValues(alpha: 0.6),
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
                                      border: Border.all(color: Colors.white, width: 2),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.success.withValues(alpha: 0.5),
                                          blurRadius: 10,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(Icons.trip_origin, color: Colors.white, size: 20),
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
                                      border: Border.all(color: Colors.white, width: 2),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFFFF9500).withValues(alpha: 0.5),
                                          blurRadius: 10,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(Icons.flag_rounded, color: Colors.white, size: 20),
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
              border: Border(top: BorderSide(color: AppColors.border.withValues(alpha: 0.3))),
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
                        boxShadow: [BoxShadow(color: AppColors.success.withValues(alpha: 0.5), blurRadius: 4)],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.ride.pickupLocation.address ?? 'pickup'.tr(),
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
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
                    children: List.generate(3, (i) => Container(
                      width: 2,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.textTertiary.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    )),
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
                        boxShadow: [BoxShadow(color: const Color(0xFFFF9500).withValues(alpha: 0.5), blurRadius: 4)],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.ride.dropoffLocation.address ?? 'destination'.tr(),
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
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
                              colors: [AppColors.success, AppColors.success.withValues(alpha: 0.8)],
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
                              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
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

class _TamagotchiPetState extends State<_TamagotchiPet> with TickerProviderStateMixin {
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
    Future.delayed(Duration(milliseconds: 2000 + (widget.seed * 500) % 2000), () {
      if (!mounted) return;
      setState(() => _isBlinking = true);
      Future.delayed(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        setState(() => _isBlinking = false);
        _startBlinking();
      });
    });
  }

  void _startExpressionChanges() {
    Future.delayed(Duration(milliseconds: 4000 + (widget.seed * 1000) % 3000), () {
      if (!mounted) return;
      setState(() => _expression = (_expression + 1) % 4);
      _startExpressionChanges();
    });
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

/// ═══════════════════════════════════════════════════════════════════════════════
/// ACTIVE RIDE NAVIGATION - Inline navigation UI (replaces NavigationMapScreen)
/// Shows map with route, status, and action buttons on the same screen
/// If ride is null, just shows the map with driver location
/// ═══════════════════════════════════════════════════════════════════════════════
class _ActiveRideNavigation extends StatefulWidget {
  final RideModel? ride; // Nullable - if null, just show map
  final VoidCallback? onExitNavigation;

  const _ActiveRideNavigation({super.key, this.ride, this.onExitNavigation});

  @override
  State<_ActiveRideNavigation> createState() => _ActiveRideNavigationState();
}

class _ActiveRideNavigationState extends State<_ActiveRideNavigation>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final MapController _mapController = MapController();
  List<LatLng> _routePoints = [];
  LatLng? _driverLocation;
  bool _isLoading = true;
  String? _routeDistance;
  String? _routeDuration;

  // === APP LIFECYCLE OPTIMIZATION ===
  bool _isAppInBackground = false;

  // Real-time GPS tracking
  StreamSubscription<Position>? _locationSubscription;
  double _heading = 0; // Direction driver is facing (degrees from GPS)
  double _bearingToTarget = 0; // Direction TO the destination
  bool _isTrackingMode = true; // Follow driver with map rotation
  DateTime? _lastRouteUpdate;

  // Navigation optimization (smooth bearing along route)
  int _lastRouteIndex = 0; // Last visited route point index
  double _lastCalculatedBearing = 0; // For smooth bearing transitions

  // === CAMERA INTERPOLATION (smooth between GPS updates) ===
  Timer? _interpolationTimer;
  LatLng? _lastGpsPosition;
  LatLng? _currentGpsPosition;
  double _lastGpsBearing = 0;
  double _currentGpsBearing = 0;
  DateTime? _lastGpsTimestamp;
  double _gpsSpeedMps = 0; // Speed in meters per second
  static const int _interpolationIntervalMs = 16; // 16ms = 60fps (máxima fluidez)

  // === DEBUG VISUAL OVERLAY ===
  int _debugBuildCount = 0;
  DateTime? _debugLastBuildTime;
  int _debugLastBuildIntervalMs = 0;
  Timer? _debugTimer;

  // === DISTANCIA EN METROS AL TARGET (para lógica de ≤100m) ===
  double _distanceToTargetMeters = double.infinity;

  // === UBER-STYLE WAIT TIMER (2 min gratis) ===
  DateTime? _arrivedAtPickupTime; // Cuando llegó al pickup
  Timer? _waitTimer; // Timer que actualiza cada segundo
  int _waitSeconds = 0; // Segundos esperando
  static const int _freeWaitMinutes = 2; // 2 minutos gratis

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Mapbox 3D navigation (when ride is active)
  mapbox.MapboxMap? _mapboxMap;
  mapbox.PolylineAnnotationManager? _polylineManager;
  mapbox.PointAnnotationManager? _pointManager;
  List<List<double>> _mapboxRouteGeometry = [];
  bool _mapboxUserInteracting = false; // Usuario tocando el mapa
  Timer? _returnToNavTimer; // Timer para volver a navegación automática

  // === TURN-BY-TURN NAVIGATION ===
  List<NavigationStep> _navigationSteps = [];
  int _currentStepIndex = 0;
  NavigationStep? get _currentStep =>
      _currentStepIndex < _navigationSteps.length ? _navigationSteps[_currentStepIndex] : null;
  NavigationStep? get _nextStep =>
      _currentStepIndex + 1 < _navigationSteps.length ? _navigationSteps[_currentStepIndex + 1] : null;

  // === POSICIONES DE PANTALLA PARA PINS 3D OVERLAY ===
  Offset? _pickupScreenPos;
  Offset? _destinationScreenPos;
  Offset? _riderGpsScreenPos;
  List<Offset?> _waypointScreenPositions = [];

  // Check if there's an active ride
  bool get _hasRide => widget.ride != null;

  // Determine target based on ride status
  // Pickup: pending, accepted, arrivedAtPickup
  // Destination: inProgress
  bool get _isGoingToPickup => _hasRide &&
      (widget.ride!.status == RideStatus.accepted ||
       widget.ride!.status == RideStatus.pending ||
       widget.ride!.status == RideStatus.arrivedAtPickup);

  LatLng? get _targetLocation => _hasRide
      ? (_isGoingToPickup
          ? LatLng(widget.ride!.pickupLocation.latitude,
              widget.ride!.pickupLocation.longitude)
          : LatLng(widget.ride!.dropoffLocation.latitude,
              widget.ride!.dropoffLocation.longitude))
      : null;

  String get _targetAddress => _hasRide
      ? (_isGoingToPickup
          ? widget.ride!.pickupLocation.address ?? 'Punto de recogida'
          : widget.ride!.dropoffLocation.address ?? 'Destino')
      : 'Tu ubicación';

  // === CERCA DEL TARGET (≤100m) - para mostrar botón "Llegué" ===
  bool get _isNearTarget => _distanceToTargetMeters <= 100;

  @override
  void initState() {
    super.initState();
    // Register lifecycle observer for background optimization
    WidgetsBinding.instance.addObserver(this);

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.4).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // === DEBUG: Timer DESHABILITADO - interfiere con rendering de Mapbox ===
    // El setState() cada 100ms compite con el render loop de Mapbox
    // _debugTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
    //   if (mounted && !_isAppInBackground) {
    //     setState(() {
    //       // Forzar rebuild para medir FPS
    //     });
    //   }
    // });

    _initializeMap();

    // Si el ride ya está en arrivedAtPickup, iniciar timer de espera
    if (widget.ride?.status == RideStatus.arrivedAtPickup) {
      // Usar arrived_at del ride si está disponible, sino usar ahora
      final arrivedAt = widget.ride?.arrivedAt;
      if (arrivedAt != null) {
        _arrivedAtPickupTime = arrivedAt;
        _waitSeconds = DateTime.now().difference(arrivedAt).inSeconds;
      }
      _startWaitTimer();
    }
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
        if (mounted) setState(() {});
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _initializeMap() async {
    final locationProvider =
        Provider.of<LocationProvider>(context, listen: false);

    // Reset navigation state for new ride
    _lastRouteIndex = 0;
    _lastCalculatedBearing = 0;
    _routePoints = [];
    _navigationSteps = [];
    _currentStepIndex = 0;

    if (locationProvider.currentPosition != null) {
      _driverLocation = LatLng(
        locationProvider.currentPosition!.latitude,
        locationProvider.currentPosition!.longitude,
      );
    } else {
      final position = await locationProvider.getCurrentPosition();
      if (position != null) {
        _driverLocation = LatLng(position.latitude, position.longitude);
      }
    }

    // Calculate initial bearing to target BEFORE fetching route
    if (_driverLocation != null && _targetLocation != null) {
      _bearingToTarget = _calculateBearing(_driverLocation!, _targetLocation!);
      _lastCalculatedBearing = _bearingToTarget;
    }

    // Only fetch route if there's an active ride
    if (_hasRide) {
      await _fetchRouteFromMapbox();
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }

    // Start real-time GPS tracking
    _startLocationTracking();
  }

  @override
  void didUpdateWidget(covariant _ActiveRideNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Si el ride cambió (de tener ride a no tener, o viceversa)
    final hadRide = oldWidget.ride != null;
    final hasRide = widget.ride != null;
    final rideIdChanged = oldWidget.ride?.id != widget.ride?.id;

    if (hadRide != hasRide || rideIdChanged) {
      debugPrint('🔄 Ride changed: hadRide=$hadRide, hasRide=$hasRide, idChanged=$rideIdChanged');

      // Limpiar estado del mapa anterior
      _cleanupMapboxResources();

      // Reset navigation state
      _lastRouteIndex = 0;
      _lastCalculatedBearing = 0;
      _currentStepIndex = 0;
      _pickupScreenPos = null;
      _destinationScreenPos = null;
      _riderGpsScreenPos = null;
      _waypointScreenPositions = [];
      _mapboxUserInteracting = false;

      // Si hay nuevo ride, obtener nueva ruta
      if (hasRide) {
        setState(() => _isLoading = true);
        _fetchRouteFromMapbox();
      }
    }
  }

  /// Calculate bearing from point A to point B (in degrees)
  /// Returns 0-360 where 0=North, 90=East, 180=South, 270=West
  double _calculateBearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLon = (to.longitude - from.longitude) * math.pi / 180;

    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    var bearing = math.atan2(y, x) * 180 / math.pi;
    return (bearing + 360) % 360; // Normalize to 0-360
  }

  /// Calcular distancia mínima del driver a la ruta (en metros)
  /// Usa la fórmula haversine para calcular distancia a cada punto
  double _calculateDistanceToRoute(LatLng driverPos) {
    if (_routePoints.isEmpty) return 0;

    double minDistance = double.infinity;
    const earthRadius = 6371000.0; // metros

    for (final point in _routePoints) {
      final lat1 = driverPos.latitude * math.pi / 180;
      final lat2 = point.latitude * math.pi / 180;
      final dLat = (point.latitude - driverPos.latitude) * math.pi / 180;
      final dLon = (point.longitude - driverPos.longitude) * math.pi / 180;

      final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
          math.cos(lat1) * math.cos(lat2) *
          math.sin(dLon / 2) * math.sin(dLon / 2);
      final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
      final distance = earthRadius * c;

      if (distance < minDistance) {
        minDistance = distance;
      }

      // Optimización: si encontramos un punto muy cercano, no seguir buscando
      if (minDistance < 10) break;
    }

    return minDistance;
  }

  /// Calculate bearing ALONG the route (not straight to destination)
  /// Optimized for smooth Uber/Google Maps style navigation
  int _bearingCalcCount = 0;
  double _calculateBearingAlongRoute(LatLng driverPos) {
    _bearingCalcCount++;

    if (_routePoints.length < 2) {
      if (_targetLocation != null) {
        return _calculateBearing(driverPos, _targetLocation!);
      }
      return _bearingToTarget;
    }

    // 1. Encontrar el punto más cercano SOLO HACIA ADELANTE (no retroceder)
    int closestIndex = _lastRouteIndex;
    double minDistance = double.infinity;

    // Buscar solo desde el último índice hasta +20 puntos adelante
    final searchEnd = math.min(_lastRouteIndex + 20, _routePoints.length);

    for (int i = _lastRouteIndex; i < searchEnd; i++) {
      final distance = _haversineDistance(driverPos, _routePoints[i]);
      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }

    // Si estamos muy lejos de la ruta (>100m), buscar en toda la ruta
    if (minDistance > 100) {
      for (int i = 0; i < _routePoints.length; i++) {
        final distance = _haversineDistance(driverPos, _routePoints[i]);
        if (distance < minDistance) {
          minDistance = distance;
          closestIndex = i;
        }
      }
    }

    // Actualizar el último índice (nunca retroceder)
    if (closestIndex > _lastRouteIndex) {
      _lastRouteIndex = closestIndex;
    }

    // 2. Look-ahead: encontrar punto ~80 metros adelante en la ruta
    const lookAheadDistance = 80.0; // metros
    double accumulatedDistance = 0;
    int lookAheadIndex = closestIndex;

    for (int i = closestIndex; i < _routePoints.length - 1; i++) {
      accumulatedDistance += _haversineDistance(_routePoints[i], _routePoints[i + 1]);
      lookAheadIndex = i + 1;
      if (accumulatedDistance >= lookAheadDistance) break;
    }

    // 3. Calcular bearing desde posición actual hacia el punto look-ahead
    final lookAheadPoint = _routePoints[lookAheadIndex];
    double newBearing = _calculateBearing(driverPos, lookAheadPoint);

    // === LOG DETALLADO cada 5 cálculos ===
    if (_bearingCalcCount % 5 == 0) {
      debugPrint('📐 BEARING[#$_bearingCalcCount]: idx=$closestIndex→$lookAheadIndex dist=${minDistance.toStringAsFixed(1)}m bearing=${newBearing.toStringAsFixed(1)}° total=${_routePoints.length}pts');
    }

    _lastCalculatedBearing = newBearing;
    return newBearing;
  }

  /// Haversine distance in meters between two points
  double _haversineDistance(LatLng p1, LatLng p2) {
    const earthRadius = 6371000.0;
    final lat1 = p1.latitude * math.pi / 180;
    final lat2 = p2.latitude * math.pi / 180;
    final dLat = (p2.latitude - p1.latitude) * math.pi / 180;
    final dLon = (p2.longitude - p1.longitude) * math.pi / 180;

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  /// Smooth bearing transition to avoid jumps (max 15° per update)
  double _smoothBearing(double current, double target) {
    // Normalizar ambos a 0-360
    current = (current + 360) % 360;
    target = (target + 360) % 360;

    // Calcular la diferencia más corta
    double diff = target - current;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;

    // Limitar cambio máximo a 15° por actualización (suaviza las curvas)
    const maxChange = 15.0;
    if (diff.abs() > maxChange) {
      diff = diff.sign * maxChange;
    }

    return (current + diff + 360) % 360;
  }

  // === GPS TRACKING OPTIMIZATION ===
  int _gpsUpdateCount = 0;
  DateTime? _lastGpsLogTime;
  DateTime? _lastGpsUpdate;

  // === UI REFRESH THROTTLING ===
  DateTime? _lastUiRefresh;
  LatLng? _lastUiLocation;
  double _lastUiBearing = 0;
  int _lastUiStepIndex = 0;
  static const int _minUiRefreshMs = 300; // Minimum 300ms between UI refreshes (más responsivo)
  static const double _minLocationChangeM = 10; // Minimum 10m movement for UI refresh
  static const double _minBearingChangeDeg = 5; // Minimum 5° bearing change for UI refresh

  /// === CAMERA INTERPOLATION TIMER ===
  /// Timer de cámara a 60fps - SIEMPRE actualiza, sin gaps
  int _frameCount = 0;
  void _startInterpolationTimer() {
    _interpolationTimer?.cancel();
    _interpolationTimer = Timer.periodic(
      Duration(milliseconds: _interpolationIntervalMs),
      (timer) {
        if (!mounted || _isAppInBackground) return;
        if (_mapboxMap == null || _mapboxUserInteracting) return;
        if (!_hasRide || !_isTrackingMode) return;
        if (_driverLocation == null) return;

        _frameCount++;
        final now = DateTime.now();
        final msSinceGps = _lastGpsTimestamp != null
            ? now.difference(_lastGpsTimestamp!).inMilliseconds
            : 0;

        // === SIEMPRE ACTUALIZAR CÁMARA - Sin gaps ===
        // La interpolación de posición solo si hay velocidad
        // Timeout aumentado a 8 segundos para GPS lento (emulador ~5s, real ~1s)
        if (_currentGpsPosition != null && _gpsSpeedMps > 0.5 && msSinceGps > 50 && msSinceGps < 8000) {
          // Predecir posición basada en velocidad
          final distanceM = _gpsSpeedMps * (msSinceGps / 1000.0);
          final bearingRad = _bearingToTarget * (3.14159265359 / 180.0);
          final latOffset = (distanceM / 111111.0) * math.cos(bearingRad);
          final lngOffset = (distanceM / (111111.0 * math.cos(_currentGpsPosition!.latitude * 3.14159265359 / 180.0))) * math.sin(bearingRad);
          _driverLocation = LatLng(
            _currentGpsPosition!.latitude + latOffset,
            _currentGpsPosition!.longitude + lngOffset,
          );
        }

        // === LOG ADVERTENCIA SI GPS VIEJO ===
        if (msSinceGps > 4000) {
          debugPrint('⚠️ GPS STALE: ${msSinceGps}ms - posible pérdida de cámara próximamente!');
        }

        // === LOG DETALLADO cada 60 frames (1 segundo) ===
        if (_frameCount % 60 == 0) {
          debugPrint('🎮 FRAME[$_frameCount] pos=(${_driverLocation!.latitude.toStringAsFixed(5)},${_driverLocation!.longitude.toStringAsFixed(5)}) bearing=${_bearingToTarget.toStringAsFixed(1)}° smooth=${_smoothedBearing.toStringAsFixed(1)}° gpsAge=${msSinceGps}ms spd=${(_gpsSpeedMps * 2.237).toStringAsFixed(1)}mph');
        }

        // === ACTUALIZAR CÁMARA SIEMPRE ===
        _updateMapboxCamera(instant: true);
      },
    );
    debugPrint('🎮 Camera timer started at 60fps (${_interpolationIntervalMs}ms) - NO GAPS');
  }

  /// Start real-time GPS tracking with heading for Uber-style navigation
  void _startLocationTracking() {
    _locationSubscription?.cancel();
    _startInterpolationTimer(); // Start smooth camera updates

    _locationSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3, // 3 metros para máxima frecuencia
      ),
    ).listen(
      (Position position) {
        if (!mounted) return;

        final now = DateTime.now();
        final newLocation = LatLng(position.latitude, position.longitude);

        // === CALCULATE SPEED FOR INTERPOLATION ===
        if (_currentGpsPosition != null && _lastGpsTimestamp != null) {
          final timeDeltaMs = now.difference(_lastGpsTimestamp!).inMilliseconds;
          if (timeDeltaMs > 0) {
            final distanceM = _haversineDistance(newLocation, _currentGpsPosition!);
            _gpsSpeedMps = (distanceM / timeDeltaMs) * 1000; // m/s
          }
          _lastGpsPosition = _currentGpsPosition;
          _lastGpsBearing = _currentGpsBearing;
        }
        _currentGpsPosition = newLocation;
        _lastGpsTimestamp = now;

        // === GPS TIMING LOG ===
        final gpsInterval = _lastGpsUpdate != null
            ? now.difference(_lastGpsUpdate!).inMilliseconds
            : 0;
        _lastGpsUpdate = now;

        // === BACKGROUND MODE: Minimal processing ===
        if (_isAppInBackground) {
          _driverLocation = newLocation;
          if (position.heading > 0) _heading = position.heading;
          return;
        }

        _gpsUpdateCount++;
        final newHeading = position.heading;

        // Log GPS update con velocidad
        debugPrint('🛰️ GPS[#$_gpsUpdateCount]: (${newLocation.latitude.toStringAsFixed(5)}, ${newLocation.longitude.toStringAsFixed(5)}) Δ${gpsInterval}ms spd=${(_gpsSpeedMps * 3.6).toStringAsFixed(1)}km/h');

        // Calculate bearing ALONG THE ROUTE (not straight to destination)
        double newBearingToTarget = _bearingToTarget;
        final oldBearing = _bearingToTarget;
        if (_routePoints.isNotEmpty && _hasRide) {
          newBearingToTarget = _calculateBearingAlongRoute(newLocation);
        } else if (_targetLocation != null) {
          newBearingToTarget = _calculateBearing(newLocation, _targetLocation!);
        }
        _currentGpsBearing = newBearingToTarget;

        // LOG cuando el bearing cambia significativamente (VUELTA)
        double bearingChange = newBearingToTarget - oldBearing;
        while (bearingChange > 180) bearingChange -= 360;
        while (bearingChange < -180) bearingChange += 360;
        if (bearingChange.abs() > 15) {
          debugPrint('🔄 GPS VUELTA: bearing cambió ${bearingChange.toStringAsFixed(1)}° (${oldBearing.toStringAsFixed(1)}°→${newBearingToTarget.toStringAsFixed(1)}°) gps#$_gpsUpdateCount');
        }

        // === UPDATE INTERNAL STATE WITHOUT setState ===
        _driverLocation = newLocation;
        _bearingToTarget = newBearingToTarget;
        if (newHeading > 0) {
          _heading = newHeading;
        }

        // === DETECCIÓN DE DESVÍO DE RUTA ===
        if (_routePoints.isNotEmpty && _hasRide && !_isRouteFetching) {
          final distanceToRoute = _calculateDistanceToRoute(newLocation);
          if (distanceToRoute > 300) {
            debugPrint('🔄 NAV: Driver desvió ${distanceToRoute.toStringAsFixed(0)}m - forzando recálculo');
            _lastRouteUpdate = null;
            _lastFetchLocation = null;
          }
        }

        // === CHECK NAVIGATION STEP (without setState) ===
        final previousStepIndex = _currentStepIndex;
        _updateCurrentNavigationStep();
        final stepChanged = _currentStepIndex != previousStepIndex;

        // === SMART UI REFRESH: Only call setState when necessary ===
        bool shouldRefreshUi = false;

        // Always refresh if navigation step changed (critical for turn-by-turn)
        if (stepChanged) {
          shouldRefreshUi = true;
          debugPrint('🧭 Step changed to $_currentStepIndex - forcing UI refresh');
        }

        // Otherwise, check time and distance thresholds
        if (!shouldRefreshUi) {
          final timeSinceLastRefresh = _lastUiRefresh != null
              ? now.difference(_lastUiRefresh!).inMilliseconds
              : _minUiRefreshMs + 1;

          if (timeSinceLastRefresh >= _minUiRefreshMs) {
            final locationChange = _lastUiLocation != null
                ? _haversineDistance(newLocation, _lastUiLocation!)
                : _minLocationChangeM + 1;

            final bearingChange = (newBearingToTarget - _lastUiBearing).abs();
            final normalizedBearingChange = bearingChange > 180 ? 360 - bearingChange : bearingChange;

            if (locationChange >= _minLocationChangeM || normalizedBearingChange >= _minBearingChangeDeg) {
              shouldRefreshUi = true;
            }
          }
        }

        // Only call setState when we have meaningful UI changes
        if (shouldRefreshUi) {
          _lastUiRefresh = now;
          _lastUiLocation = newLocation;
          _lastUiBearing = newBearingToTarget;
          _lastUiStepIndex = _currentStepIndex;

          setState(() {
            // State is already updated above, this just triggers rebuild
            // === DEBUG: Track build count and interval ===
            _debugBuildCount++;
            if (_debugLastBuildTime != null) {
              _debugLastBuildIntervalMs = now.difference(_debugLastBuildTime!).inMilliseconds;
            }
            _debugLastBuildTime = now;
          });
        }

        // === MAP CAMERA UPDATES (independent of setState) ===
        // IMPORTANTE: Usar instant:true porque el timer de interpolación maneja el movimiento suave
        // Si usamos easeTo aquí, compite con setCamera del interpolation timer causando saltos
        if (_isTrackingMode && _driverLocation != null) {
          if (_hasRide && _mapboxMap != null && !_mapboxUserInteracting) {
            _updateMapboxCamera(instant: true); // GPS real también usa instant para no interferir con interpolación
          } else if (!_hasRide) {
            try {
              _mapController.moveAndRotate(
                _driverLocation!,
                _mapController.camera.zoom,
                -_bearingToTarget,
              );
            } catch (e) {
              // Map controller not ready - silent fail
            }
          }
        }

        // Route fetch with internal optimization
        if (_hasRide && _targetLocation != null) {
          _fetchRouteFromMapbox();
        }
      },
      onError: (error) {
        debugPrint('Location stream error: $error');
      },
    );

    debugPrint('🛰️ GPS Tracking started - Destination always UP');
  }

  // === NAVIGATION OPTIMIZATION: Tracking variables ===
  bool _isRouteFetching = false; // Prevent concurrent route fetches
  LatLng? _lastFetchLocation; // Last location where route was fetched
  DateTime? _lastFetchTime; // Last time route was fetched
  int _routeFetchCount = 0; // Counter for debugging

  Future<void> _fetchRouteFromMapbox() async {
    if (_driverLocation == null || _targetLocation == null) return;

    // === OPTIMIZATION 1: Prevent concurrent fetches ===
    if (_isRouteFetching) {
      debugPrint('⏸️ NAV: Skipping fetch - already fetching');
      return;
    }

    // === OPTIMIZATION 2: Skip if driver hasn't moved significantly (75m) ===
    if (_lastFetchLocation != null) {
      final distanceMoved = _haversineDistance(_driverLocation!, _lastFetchLocation!);
      if (distanceMoved < 75 && _routePoints.isNotEmpty) {
        return; // Silent skip - driver hasn't moved enough
      }
    }

    // === OPTIMIZATION 3: Rate limiting (min 15 seconds between fetches) ===
    if (_lastFetchTime != null) {
      final elapsed = DateTime.now().difference(_lastFetchTime!).inSeconds;
      if (elapsed < 15 && _routePoints.isNotEmpty) {
        return; // Silent skip - too soon
      }
    }

    _isRouteFetching = true;
    _routeFetchCount++;
    final fetchStart = DateTime.now();
    debugPrint('🚀 NAV[$_routeFetchCount]: Starting route fetch...');

    try {
      final route = await MapboxNavigationService().getRoute(
        originLat: _driverLocation!.latitude,
        originLng: _driverLocation!.longitude,
        destinationLat: _targetLocation!.latitude,
        destinationLng: _targetLocation!.longitude,
      );

      final fetchDuration = DateTime.now().difference(fetchStart).inMilliseconds;
      debugPrint('✅ NAV[$_routeFetchCount]: ${route?.distance.toStringAsFixed(0) ?? '?'}m in ${fetchDuration}ms');

      // Update tracking variables
      _lastFetchLocation = _driverLocation;
      _lastFetchTime = DateTime.now();

      if (route != null && route.geometry.isNotEmpty) {
        // Convert [lng, lat] to LatLng
        final newRoutePoints = route.geometry
            .map((coord) => LatLng(coord[1], coord[0]))
            .toList();

        // Solo resetear índice si la ruta cambió significativamente
        if (_routePoints.isEmpty ||
            _haversineDistance(newRoutePoints.first, _routePoints.isEmpty ? newRoutePoints.first : _routePoints[_lastRouteIndex.clamp(0, _routePoints.length - 1)]) > 50) {
          _lastRouteIndex = 0;
          _lastCalculatedBearing = _bearingToTarget;
        }

        _routePoints = newRoutePoints;

        // Store for Mapbox drawing
        _mapboxRouteGeometry = route.geometry;

        if (mounted) {
          setState(() {
            _distanceToTargetMeters = route.distance; // metros para lógica ≤100m
            _routeDistance = _formatDistance(route.distance);
            _routeDuration = _formatDuration(route.duration);

            // === TURN-BY-TURN: Guardar steps de navegación ===
            if (route.steps.isNotEmpty) {
              _navigationSteps = route.steps;
              // Actualizar el step actual basado en la ubicación
              _updateCurrentNavigationStep();
            }
          });

          // Update Mapbox route if map exists
          _drawMapboxRoute();
        }

        _isRouteFetching = false;
        return;
      }

      // Fallback: calcular distancia haversine si Mapbox falla
      debugPrint('⚠️ NAV[$_routeFetchCount]: Empty route, using fallback');
      _setFallbackDistance();
    } catch (e) {
      final fetchDuration = DateTime.now().difference(fetchStart).inMilliseconds;
      debugPrint('❌ NAV[$_routeFetchCount]: Error after ${fetchDuration}ms - $e');
      _setFallbackDistance();
    }

    _isRouteFetching = false;
  }

  /// Calcula distancia haversine como fallback cuando la API de rutas falla
  void _setFallbackDistance() {
    if (_driverLocation == null || _targetLocation == null) return;

    final haversine = _haversineDistance(_driverLocation!, _targetLocation!);
    _routePoints = [_driverLocation!, _targetLocation!];

    if (mounted) {
      setState(() {
        _distanceToTargetMeters = haversine;
        _routeDistance = _formatDistance(haversine);
        _routeDuration = null; // No tenemos duración sin ruta
      });
    }
    debugPrint('📍 Fallback haversine distance: ${haversine.toStringAsFixed(0)}m');
  }

  /// Actualiza el step de navegación actual basado en la ubicación del conductor
  void _updateCurrentNavigationStep() {
    if (_driverLocation == null || _navigationSteps.isEmpty) return;
    if (_currentStepIndex >= _navigationSteps.length - 1) return;

    final nextStep = _navigationSteps[_currentStepIndex + 1];
    if (nextStep.maneuverLocation != null) {
      final distanceToNextManeuver = _haversineDistance(
        _driverLocation!,
        LatLng(nextStep.maneuverLocation!.latitude, nextStep.maneuverLocation!.longitude),
      );

      // Si estamos a menos de 30m de la próxima maniobra, avanzar al siguiente step
      if (distanceToNextManeuver < 30) {
        _currentStepIndex++;
        debugPrint('🧭 Navigation: Advanced to step $_currentStepIndex - ${nextStep.instruction}');
      }
    }
  }

  /// Construye el banner de navegación turn-by-turn
  Widget _buildNavigationBanner() {
    if (_currentStep == null) return const SizedBox.shrink();

    final step = _currentStep!;
    final distanceToManeuver = step.distance > 0 ? _formatDistance(step.distance) : '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icono de maniobra
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF00C853),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              step.maneuverIcon,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          // Instrucción
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (distanceToManeuver.isNotEmpty)
                  Text(
                    distanceToManeuver,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                Text(
                  step.bannerInstruction ?? step.instruction,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      int shift = 0;
      int result = 0;
      int byte;

      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1F) << shift;
        shift += 5;
      } while (byte >= 0x20);

      int dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1F) << shift;
        shift += 5;
      } while (byte >= 0x20);

      int dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return points;
  }

  String _formatDistance(double meters) {
    if (meters >= 1609) {
      return '${(meters / 1609.34).toStringAsFixed(1)} mi';
    }
    return '${(meters * 3.28084).toInt()} ft';
  }

  String _formatDuration(double seconds) {
    final minutes = (seconds / 60).round();
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      return '${hours}h ${mins}min';
    }
    return '$minutes min';
  }

  void _fitBounds() {
    if (_driverLocation == null) return;

    // If no target (no ride), just center on driver
    if (_targetLocation == null) {
      _mapController.move(_driverLocation!, 16);
      return;
    }

    final minLat = math.min(_driverLocation!.latitude, _targetLocation!.latitude);
    final maxLat = math.max(_driverLocation!.latitude, _targetLocation!.latitude);
    final minLng = math.min(_driverLocation!.longitude, _targetLocation!.longitude);
    final maxLng = math.max(_driverLocation!.longitude, _targetLocation!.longitude);

    final bounds = LatLngBounds(
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
    );

    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(80)),
    );
  }

  void _centerOnDriver() {
    if (_driverLocation != null) {
      if (_isTrackingMode) {
        // Destination UP: center and rotate so destination is at top
        _mapController.moveAndRotate(_driverLocation!, 16, -_bearingToTarget);
      } else {
        // North-up: just center without rotation
        _mapController.move(_driverLocation!, 16);
      }
      // Re-enable tracking mode when centering
      setState(() => _isTrackingMode = true);
    }
  }

  /// Initialize Mapbox map when created
  Future<void> _onMapboxMapCreated(mapbox.MapboxMap map) async {
    _mapboxMap = map;
    debugPrint('🗺️ Mapbox map created');

    try {
      // Create annotation managers (solo para ruta y walking pad)
      _polylineManager = await map.annotations.createPolylineAnnotationManager();
      _pointManager = await map.annotations.createPointAnnotationManager();
      debugPrint('📍 Annotation managers created');

      // Draw route if available
      await _drawMapboxRoute();

      // Calcular posiciones de pantalla para los PINs 3D overlay
      await _updatePinScreenPositions();

      // === FORZAR CÁMARA A GPS REAL ===
      // Si tenemos GPS, centrar inmediatamente
      if (_driverLocation != null) {
        debugPrint('📷 Forcing camera to GPS: ${_driverLocation!.latitude}, ${_driverLocation!.longitude}');
        _updateMapboxCamera(instant: true);
      } else {
        // Si no hay GPS aún, obtenerlo y centrar
        final locationProvider = Provider.of<LocationProvider>(context, listen: false);
        final position = await locationProvider.getCurrentPosition();
        if (position != null) {
          _driverLocation = LatLng(position.latitude, position.longitude);
          debugPrint('📷 Got fresh GPS, centering: ${position.latitude}, ${position.longitude}');
          _updateMapboxCamera(instant: true);
        }
      }
      debugPrint('✅ Mapbox setup complete');
    } catch (e) {
      debugPrint('❌ Mapbox setup error: $e');
    }
  }

  /// Llamado cuando el usuario interactúa con el mapa Mapbox
  void _onMapboxScroll(mapbox.MapContentGestureContext context) {
    if (!_mapboxUserInteracting) {
      setState(() => _mapboxUserInteracting = true);
      _returnToNavTimer?.cancel();
    }
  }

  /// Llamado cuando la cámara del mapa cambia (en tiempo real)
  /// THROTTLED: No actualizar pins en cada frame - causa lag
  DateTime? _lastPinUpdateTime;
  void _onMapboxCameraChange(mapbox.CameraChangedEventData data) {
    // Throttle pin updates to max 5fps (200ms) to avoid main thread overload
    final now = DateTime.now();
    if (_lastPinUpdateTime != null &&
        now.difference(_lastPinUpdateTime!).inMilliseconds < 200) {
      return; // Skip this update
    }
    _lastPinUpdateTime = now;
    _updatePinScreenPositions();
  }

  /// Llamado cuando el mapa deja de moverse (usuario soltó)
  void _onMapboxIdle(mapbox.MapIdleEventData data) {
    // Actualizar posiciones finales de los PINs
    _updatePinScreenPositions();

    if (_mapboxUserInteracting) {
      _returnToNavTimer?.cancel();
      _returnToNavTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _hasRide) {
          setState(() => _mapboxUserInteracting = false);
          // Regresar al seguimiento automático - usar instant para no interferir con interpolación
          _updateMapboxCamera(instant: true);
        }
      });
    }
  }

  /// Draw route on Mapbox map (ruta de conducción)
  Future<void> _drawMapboxRoute() async {
    if (_polylineManager == null || _mapboxRouteGeometry.isEmpty) return;

    // IMPORTANTE: Limpiar todas las anotaciones anteriores antes de dibujar
    try {
      await _polylineManager!.deleteAll();
    } catch (e) {
      debugPrint('Error clearing polylines: $e');
    }

    final points = _mapboxRouteGeometry.map((coord) {
      return mapbox.Point(coordinates: mapbox.Position(coord[0], coord[1]));
    }).toList();

    if (points.isEmpty) return;

    // Ruta de conducción - línea azul gruesa
    await _polylineManager!.create(
      mapbox.PolylineAnnotationOptions(
        geometry: mapbox.LineString(coordinates: points.map((p) => p.coordinates).toList()),
        lineColor: const Color(0xFF4285F4).toARGB32(), // Azul tipo Google Maps
        lineWidth: 8.0, // Más gruesa para mejor visibilidad
        lineOpacity: 1.0,
      ),
    );

    // Si hay walking pad del rider, dibujarlo
    await _drawRiderWalkingPad();
  }

  /// Dibujar walking pad del rider (caminando del GPS al PIN)
  Future<void> _drawRiderWalkingPad() async {
    if (_polylineManager == null || widget.ride == null) return;
    final ride = widget.ride!;

    // Solo durante pickup y si no es para otra persona
    if (!_isGoingToPickup || ride.isBookingForSomeoneElse) return;

    // Necesita tener walking pad
    if (!ride.hasWalkingPad) return;

    // Decodificar walking pad polyline
    final walkingPoints = _decodePolyline(ride.riderWalkingPad!);
    if (walkingPoints.isEmpty) return;

    // Convertir a formato Mapbox
    final mapboxPoints = walkingPoints.map((p) {
      return mapbox.Position(p.longitude, p.latitude);
    }).toList();

    // Walking pad - línea punteada naranja
    await _polylineManager!.create(
      mapbox.PolylineAnnotationOptions(
        geometry: mapbox.LineString(coordinates: mapboxPoints),
        lineColor: const Color(0xFFFF9500).toARGB32(), // Naranja
        lineWidth: 3.0,
        lineOpacity: 0.8,
      ),
    );
  }

  /// Actualiza las posiciones de pantalla de los PINs 3D
  /// OPTIMIZADO: Ejecuta llamadas en paralelo y evita setState innecesarios
  bool _pinUpdateInProgress = false;
  Future<void> _updatePinScreenPositions() async {
    if (_mapboxMap == null || widget.ride == null) return;
    if (_pinUpdateInProgress) return; // Evitar llamadas concurrentes

    _pinUpdateInProgress = true;
    final ride = widget.ride!;

    try {
      // Preparar todas las coordenadas a convertir
      final futures = <Future<mapbox.ScreenCoordinate>>[];
      final labels = <String>[];

      // === 1. PICKUP ===
      if (_isGoingToPickup) {
        futures.add(_mapboxMap!.pixelForCoordinate(mapbox.Point(
          coordinates: mapbox.Position(ride.pickupLocation.longitude, ride.pickupLocation.latitude),
        )));
        labels.add('pickup');

        // === 2. RIDER GPS ===
        if (ride.hasRiderGps) {
          futures.add(_mapboxMap!.pixelForCoordinate(mapbox.Point(
            coordinates: mapbox.Position(ride.riderGpsLng!, ride.riderGpsLat!),
          )));
          labels.add('riderGps');
        }
      }

      // === 3. DESTINO ===
      if (!_isGoingToPickup || ride.status == RideStatus.inProgress) {
        futures.add(_mapboxMap!.pixelForCoordinate(mapbox.Point(
          coordinates: mapbox.Position(ride.dropoffLocation.longitude, ride.dropoffLocation.latitude),
        )));
        labels.add('destination');
      }

      // Ejecutar todas las conversiones EN PARALELO
      if (futures.isEmpty) {
        _pickupScreenPos = null;
        _riderGpsScreenPos = null;
        _destinationScreenPos = null;
        _pinUpdateInProgress = false;
        return;
      }

      final results = await Future.wait(futures);

      // Asignar resultados
      for (int i = 0; i < labels.length; i++) {
        final pixel = results[i];
        final offset = Offset(pixel.x, pixel.y);
        switch (labels[i]) {
          case 'pickup':
            _pickupScreenPos = offset;
            break;
          case 'riderGps':
            _riderGpsScreenPos = offset;
            break;
          case 'destination':
            _destinationScreenPos = offset;
            break;
        }
      }

      // Limpiar posiciones no usadas
      if (!_isGoingToPickup) {
        _pickupScreenPos = null;
        _riderGpsScreenPos = null;
      }
      if (_isGoingToPickup && ride.status != RideStatus.inProgress) {
        _destinationScreenPos = null;
      }
      if (!ride.hasRiderGps) {
        _riderGpsScreenPos = null;
      }

      // === 4. WAYPOINTS - Solo si los hay (raro) ===
      if (ride.waypoints != null && ride.waypoints!.isNotEmpty) {
        final wpFutures = <Future<mapbox.ScreenCoordinate>>[];
        for (final wp in ride.waypoints!) {
          final lat = (wp['lat'] as num?)?.toDouble();
          final lng = (wp['lng'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            wpFutures.add(_mapboxMap!.pixelForCoordinate(
              mapbox.Point(coordinates: mapbox.Position(lng, lat)),
            ));
          }
        }
        if (wpFutures.isNotEmpty) {
          final wpResults = await Future.wait(wpFutures);
          _waypointScreenPositions = wpResults.map((p) => Offset(p.x, p.y)).toList();
        }
      } else {
        _waypointScreenPositions = [];
      }

      // NO llamar setState aquí - los pins se actualizan con el siguiente rebuild natural
      // Esto evita rebuilds excesivos
    } catch (e) {
      // Silenciar errores durante navegación
    } finally {
      _pinUpdateInProgress = false;
    }
  }

  /// Construye los widgets de PIN 3D como overlays sobre el mapa
  List<Widget> _buildPinOverlays() {
    final pins = <Widget>[];
    const pinSize = 48.0;
    const pinHeight = pinSize * 1.25;

    // === PICKUP PIN ===
    if (_pickupScreenPos != null) {
      pins.add(
        Positioned(
          left: _pickupScreenPos!.dx - pinSize / 2,
          top: _pickupScreenPos!.dy - pinHeight, // Ancla en la punta del pin
          child: const Toro3DPin(
            kind: ToroPinKind.pickup,
            size: pinSize,
            label: 'PICKUP',
          ),
        ),
      );
    }

    // === RIDER GPS PIN ===
    if (_riderGpsScreenPos != null) {
      pins.add(
        Positioned(
          left: _riderGpsScreenPos!.dx - 20,
          top: _riderGpsScreenPos!.dy - 50,
          child: const Toro3DPin(
            kind: ToroPinKind.riderGps,
            size: 40,
            label: 'RIDER',
          ),
        ),
      );
    }

    // === DESTINO PIN ===
    if (_destinationScreenPos != null) {
      pins.add(
        Positioned(
          left: _destinationScreenPos!.dx - pinSize / 2,
          top: _destinationScreenPos!.dy - pinHeight,
          child: const Toro3DPin(
            kind: ToroPinKind.destination,
            size: pinSize,
            label: 'DESTINO',
          ),
        ),
      );
    }

    // === WAYPOINT PINS ===
    for (var i = 0; i < _waypointScreenPositions.length; i++) {
      final pos = _waypointScreenPositions[i];
      if (pos != null) {
        final wpName = widget.ride?.waypoints?[i]['name'] as String? ?? 'Parada ${i + 1}';
        pins.add(
          Positioned(
            left: pos.dx - 22,
            top: pos.dy - 55,
            child: Toro3DPin(
              kind: ToroPinKind.waypoint,
              size: 44,
              label: wpName,
            ),
          ),
        );
      }
    }

    return pins;
  }

  /// Update Mapbox camera to follow driver
  /// UBER-STYLE: Driver stays at fixed screen position (lower 1/3)
  /// Map moves and rotates around the driver's position
  DateTime? _lastMapboxCameraUpdate;

  // === CAMERA DIAGNOSTICS ===
  int _cameraUpdateCount = 0;
  DateTime? _lastCameraLogTime;

  // === SMOOTH CAMERA CON PREDICCIÓN ===
  // Predice posiciones futuras para que Mapbox anime sin esperar
  double _smoothedBearing = 0;
  double _smoothedLat = 0;
  double _smoothedLng = 0;
  bool _smoothedPositionInitialized = false;

  // === PREDICCIÓN DE POSICIÓN ===
  // Predecir 100ms hacia adelante basado en velocidad
  static const int _predictionMs = 100;
  static const int _mapboxAnimationMs = 80; // Animación que cubre el gap

  // === SMOOTHING PARAMS ===
  static const double _bearingSmoothing = 0.90; // 90% - muy rápido
  static const double _positionSmoothing = 0.80; // 80% - responsivo
  static const double _maxBearingChangePerFrame = 5.0; // 5°/frame = 300°/seg

  void _updateMapboxCamera({bool instant = false}) {
    if (_mapboxMap == null || _driverLocation == null) return;
    if (_mapboxUserInteracting) return;

    _cameraUpdateCount++;

    // === INICIALIZAR ===
    if (!_smoothedPositionInitialized) {
      _smoothedLat = _driverLocation!.latitude;
      _smoothedLng = _driverLocation!.longitude;
      _smoothedBearing = _bearingToTarget;
      _smoothedPositionInitialized = true;
    }

    // === PREDECIR POSICIÓN FUTURA ===
    // Calcular dónde estaremos en _predictionMs basado en velocidad actual
    double predictedLat = _driverLocation!.latitude;
    double predictedLng = _driverLocation!.longitude;

    if (_gpsSpeedMps > 0.5) {
      final distanceM = _gpsSpeedMps * (_predictionMs / 1000.0);
      final bearingRad = _bearingToTarget * (3.14159265359 / 180.0);
      predictedLat += (distanceM / 111111.0) * math.cos(bearingRad);
      predictedLng += (distanceM / (111111.0 * math.cos(_driverLocation!.latitude * 3.14159265359 / 180.0))) * math.sin(bearingRad);
    }

    // === SUAVIZADO DE BEARING ===
    double bearingDiff = _bearingToTarget - _smoothedBearing;
    while (bearingDiff > 180) bearingDiff -= 360;
    while (bearingDiff < -180) bearingDiff += 360;

    // LOG cuando detectamos una vuelta (diff > 20°)
    if (bearingDiff.abs() > 20) {
      debugPrint('🔄 VUELTA DETECTADA: diff=${bearingDiff.toStringAsFixed(1)}° smoothed=${_smoothedBearing.toStringAsFixed(1)}° target=${_bearingToTarget.toStringAsFixed(1)}° frame#$_cameraUpdateCount');
    }

    if (bearingDiff.abs() > _maxBearingChangePerFrame) {
      bearingDiff = bearingDiff.sign * _maxBearingChangePerFrame;
    }
    _smoothedBearing += bearingDiff * _bearingSmoothing;
    while (_smoothedBearing < 0) _smoothedBearing += 360;
    while (_smoothedBearing >= 360) _smoothedBearing -= 360;

    // === SUAVIZADO DE POSICIÓN PREDICHA ===
    _smoothedLat += (predictedLat - _smoothedLat) * _positionSmoothing;
    _smoothedLng += (predictedLng - _smoothedLng) * _positionSmoothing;

    // Log cada 60 updates (~1 segundo) - MÁS DETALLADO
    if (_cameraUpdateCount % 60 == 0) {
      final msSinceGps = _lastGpsUpdate != null
          ? DateTime.now().difference(_lastGpsUpdate!).inMilliseconds
          : 0;
      debugPrint('📷 CAM[#$_cameraUpdateCount]: '
          'bearing=${_smoothedBearing.toStringAsFixed(1)}° '
          'target=${_bearingToTarget.toStringAsFixed(1)}° '
          'diff=${(_bearingToTarget - _smoothedBearing).toStringAsFixed(1)}° | '
          'spd=${_gpsSpeedMps.toStringAsFixed(1)}m/s (${(_gpsSpeedMps * 2.237).toStringAsFixed(1)}mph) | '
          'gpsAge=${msSinceGps}ms | '
          'pos=(${_smoothedLat.toStringAsFixed(5)},${_smoothedLng.toStringAsFixed(5)})');
    }
    _lastMapboxCameraUpdate = DateTime.now();

    final screenSize = MediaQuery.of(context).size;
    final topPadding = screenSize.height * 0.35;

    // === ZOOM DINÁMICO ===
    double dynamicZoom;
    if (_gpsSpeedMps > 16.6) {
      dynamicZoom = 15.5;
    } else if (_gpsSpeedMps > 8.3) {
      dynamicZoom = 16.5;
    } else {
      dynamicZoom = 17.5;
    }

    final cameraOptions = mapbox.CameraOptions(
      center: mapbox.Point(
        coordinates: mapbox.Position(_smoothedLng, _smoothedLat),
      ),
      zoom: dynamicZoom,
      bearing: _smoothedBearing,
      pitch: 60,
      padding: mapbox.MbxEdgeInsets(
        top: topPadding,
        left: 0,
        bottom: 0,
        right: 0,
      ),
    );

    // === ANIMACIÓN PREDICTIVA ===
    // easeTo con 80ms cubre el gap de predicción (100ms) para fluidez total
    _mapboxMap!.easeTo(
      cameraOptions,
      mapbox.MapAnimationOptions(duration: _mapboxAnimationMs),
    );
  }

  /// Card informativo del rider durante el pickup - COMPACTO
  /// Muestra: nombre, GPS status, dirección abreviada
  Widget _buildRiderInfoCard() {
    final ride = widget.ride!;
    final hasGps = ride.hasRiderGps;
    final isForSomeoneElse = ride.isBookingForSomeoneElse;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF9500).withOpacity(0.4)),
      ),
      child: Row(
        children: [
          // Icono persona
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFFF9500).withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.person, color: Color(0xFFFF9500), size: 18),
          ),
          const SizedBox(width: 10),
          // Info del rider
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ride.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  isForSomeoneElse ? 'Para otra persona' : (ride.pickupLocation.address ?? 'Pickup'),
                  style: TextStyle(
                    color: isForSomeoneElse ? Colors.orange : Colors.white60,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // GPS Badge (solo si no es para otra persona)
          if (!isForSomeoneElse)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: hasGps
                    ? const Color(0xFF34C759).withOpacity(0.2)
                    : Colors.grey.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    hasGps ? Icons.gps_fixed : Icons.gps_off,
                    color: hasGps ? const Color(0xFF34C759) : Colors.grey,
                    size: 12,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    hasGps ? 'GPS' : 'OFF',
                    style: TextStyle(
                      color: hasGps ? const Color(0xFF34C759) : Colors.grey,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Card vertical compacto del rider - LADO IZQUIERDO del mapa
  /// No se encima con el banner de distancia de arriba
  Widget _buildRiderInfoCardVertical() {
    final ride = widget.ride!;
    final hasGps = ride.hasRiderGps;
    final isForSomeoneElse = ride.isBookingForSomeoneElse;

    return Container(
      width: 55,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF9500).withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icono persona naranja
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFFF9500).withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.person, color: Color(0xFFFF9500), size: 24),
          ),
          const SizedBox(height: 6),
          // Nombre corto
          Text(
            ride.displayName.split(' ').first, // Solo primer nombre
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          // GPS Badge
          if (!isForSomeoneElse)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: hasGps
                    ? const Color(0xFF34C759).withValues(alpha: 0.3)
                    : Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                hasGps ? Icons.gps_fixed : Icons.gps_off,
                color: hasGps ? const Color(0xFF34C759) : Colors.grey,
                size: 16,
              ),
            ),
          // Badge "otra persona"
          if (isForSomeoneElse)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.person_outline, color: Colors.orange, size: 16),
            ),
        ],
      ),
    );
  }

  /// WEB COMPLETE: FlutterMap with all navigation UI (no duplicates)
  Widget _buildWebNavigationMapComplete() {
    final ride = widget.ride;
    final driverLat = _driverLocation?.latitude ?? 33.4484;
    final driverLng = _driverLocation?.longitude ?? -112.0740;

    // Build markers
    final markers = <Marker>[];

    // Target marker (pickup or destination)
    if (ride != null) {
      final targetLat = _isGoingToPickup
          ? ride.pickupLocation.latitude
          : ride.dropoffLocation.latitude;
      final targetLng = _isGoingToPickup
          ? ride.pickupLocation.longitude
          : ride.dropoffLocation.longitude;
      final targetColor = _isGoingToPickup
          ? const Color(0xFF26A69A) // Teal for pickup
          : const Color(0xFFFF0066); // Magenta for destination
      final targetIcon = _isGoingToPickup ? Icons.person : Icons.flag;

      markers.add(
        Marker(
          point: LatLng(targetLat, targetLng),
          width: 48,
          height: 60,
          alignment: Alignment.bottomCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: targetColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: targetColor.withOpacity(0.6),
                      blurRadius: 12,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Icon(targetIcon, color: Colors.white, size: 22),
              ),
              Container(
                width: 4,
                height: 14,
                decoration: BoxDecoration(
                  color: targetColor,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(2),
                    bottomRight: Radius.circular(2),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Driver marker - navigation arrow that rotates with heading
    markers.add(
      Marker(
        point: LatLng(driverLat, driverLng),
        width: 60,
        height: 60,
        rotate: false, // We handle rotation manually
        child: Transform.rotate(
          angle: (_heading - _bearingToTarget) * math.pi / 180,
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFF4285F4),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4285F4).withOpacity(0.5),
                  blurRadius: 12,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: const Icon(
              Icons.navigation,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      ),
    );

    // Route polyline with glow effect
    final polylines = <Polyline>[];
    if (_routePoints.isNotEmpty) {
      // Outer glow
      polylines.add(
        Polyline(
          points: _routePoints,
          strokeWidth: 12,
          color: const Color(0xFF00BFFF).withOpacity(0.2),
        ),
      );
      // Inner line
      polylines.add(
        Polyline(
          points: _routePoints,
          strokeWidth: 5,
          color: const Color(0xFF00BFFF),
        ),
      );
    }

    return Stack(
      children: [
        // === MAP ===
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: LatLng(driverLat, driverLng),
            initialZoom: 16.0,
            initialRotation: _bearingToTarget,
            onPositionChanged: (position, hasGesture) {
              if (hasGesture && _isTrackingMode) {
                setState(() => _isTrackingMode = false);
              }
            },
          ),
          children: [
            // Mapbox dark tiles
            TileLayer(
              urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/navigation-night-v1/tiles/256/{z}/{x}/{y}@2x?access_token=pk.eyJ1IjoibWFydGluZXpjMjAxNyIsImEiOiJjbWtocWtoZHIwbW1iM2dvdXZ3bmp0ZjBiIn0.MjYgv6DuvLTkrBVbrhtFbg',
              userAgentPackageName: 'com.toro.driver',
              maxZoom: 19,
            ),
            if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
            MarkerLayer(markers: markers),
          ],
        ),

        // === NAVIGATION BANNER (top) ===
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: _buildWebNavigationBanner(),
          ),
        ),

        // === RIDER INFO (left side, if going to pickup) ===
        if (_isGoingToPickup && ride != null)
          Positioned(
            top: 100,
            left: 12,
            child: _buildRiderInfoCardVertical(),
          ),

        // === RE-CENTER BUTTON (if not tracking) ===
        if (!_isTrackingMode)
          Positioned(
            right: 16,
            bottom: 240,
            child: GestureDetector(
              onTap: () {
                HapticService.lightImpact();
                setState(() => _isTrackingMode = true);
                if (_driverLocation != null) {
                  _mapController.moveAndRotate(
                    _driverLocation!,
                    16,
                    _bearingToTarget,
                  );
                }
              },
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF3A3A3A)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.gps_fixed,
                  color: Color(0xFF4285F4),
                  size: 24,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Web navigation banner - clean, professional
  Widget _buildWebNavigationBanner() {
    final ride = widget.ride;
    if (ride == null) return const SizedBox.shrink();

    // Get current navigation step
    final currentStep = _navigationSteps.isNotEmpty && _currentStepIndex < _navigationSteps.length
        ? _navigationSteps[_currentStepIndex]
        : null;

    // Use pre-formatted strings from route calculation
    final distanceText = _routeDistance ?? '';
    final etaText = _routeDuration ?? '';

    // Get maneuver icon and instruction from NavigationStep class
    IconData maneuverIcon = Icons.straight;
    String instruction = _isGoingToPickup ? 'Hacia el pickup' : 'Hacia el destino';

    if (currentStep != null) {
      instruction = currentStep.bannerInstruction ?? currentStep.instruction;
      maneuverIcon = currentStep.maneuverIcon;
    }

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2A4A)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Maneuver icon
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF4285F4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(maneuverIcon, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          // Instructions
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (distanceText.isNotEmpty || etaText.isNotEmpty)
                  Row(
                    children: [
                      if (distanceText.isNotEmpty)
                        Text(
                          distanceText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      if (distanceText.isNotEmpty && etaText.isNotEmpty)
                        const Text(
                          ' • ',
                          style: TextStyle(color: Colors.white54, fontSize: 20),
                        ),
                      if (etaText.isNotEmpty)
                        Text(
                          etaText,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 4),
                Text(
                  instruction,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // External navigation button
          GestureDetector(
            onTap: _openExternalNavigation,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A4A),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.open_in_new, color: Colors.white70, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  /// Open external GPS apps (Google Maps / Waze)
  void _openExternalGPS() {
    if (_targetLocation == null) return;
    HapticService.lightImpact();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Abrir en app externa',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      Navigator.pop(ctx);
                      final url = 'https://www.google.com/maps/dir/?api=1&destination=${_targetLocation!.latitude},${_targetLocation!.longitude}&travelmode=driving';
                      try {
                        await launchUrlString(url);
                      } catch (e) {
                        debugPrint('Error opening Google Maps: $e');
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4285F4).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF4285F4).withValues(alpha: 0.5)),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.map, color: const Color(0xFF4285F4), size: 28),
                          const SizedBox(height: 8),
                          Text('Google Maps', style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      Navigator.pop(ctx);
                      final url = 'https://waze.com/ul?ll=${_targetLocation!.latitude},${_targetLocation!.longitude}&navigate=yes';
                      try {
                        await launchUrlString(url);
                      } catch (e) {
                        debugPrint('Error opening Waze: $e');
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF33CCFF).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF33CCFF).withValues(alpha: 0.5)),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.directions, color: const Color(0xFF33CCFF), size: 28),
                          const SizedBox(height: 8),
                          Text('Waze', style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _openExternalNavigation() async {
    HapticService.mediumImpact();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Abrir navegación',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _targetAddress,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // Mapbox turn-by-turn navigation (featured - full width)
            _NavOptionButton(
              icon: Icons.navigation_rounded,
              label: 'Navegación 3D',
              sublabel: 'Turn-by-turn profesional',
              color: const Color(0xFF4264FB), // Mapbox blue
              featured: true,
              onTap: () {
                Navigator.pop(ctx);
                final rideProvider = Provider.of<RideProvider>(context, listen: false);
                final activeRide = rideProvider.activeRide;
                if (activeRide != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => NavigationMapScreen(ride: activeRide),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 16),
            // Google Maps and Waze row
            Row(
              children: [
                Expanded(
                  child: _NavOptionButton(
                    icon: Icons.map,
                    label: 'Google Maps',
                    color: const Color(0xFF4285F4),
                    onTap: () async {
                      Navigator.pop(ctx);
                      if (_targetLocation == null) return;
                      final fallbackUrl = Uri.parse(
                        'https://www.google.com/maps/dir/?api=1&destination=${_targetLocation!.latitude},${_targetLocation!.longitude}&travelmode=driving',
                      );
                      try {
                        await launchUrlString(fallbackUrl.toString());
                      } catch (e) {
                        debugPrint('Error opening Maps: $e');
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _NavOptionButton(
                    icon: Icons.navigation,
                    label: 'Waze',
                    color: const Color(0xFF33CCFF),
                    onTap: () async {
                      Navigator.pop(ctx);
                      if (_targetLocation == null) return;
                      final url = Uri.parse(
                        'https://waze.com/ul?ll=${_targetLocation!.latitude},${_targetLocation!.longitude}&navigate=yes',
                      );
                      try {
                        await launchUrlString(url.toString());
                      } catch (e) {
                        debugPrint('Error opening Waze: $e');
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(RideStatus status) {
    switch (status) {
      case RideStatus.pending:
      case RideStatus.accepted:
        return const Color(0xFFFF9500);
      case RideStatus.arrivedAtPickup:
        return const Color(0xFF4285F4);
      case RideStatus.inProgress:
        return Colors.green;
      case RideStatus.completed:
        return Colors.green;
      case RideStatus.cancelled:
        return Colors.red;
    }
  }

  String _getStatusLabel(RideStatus status) {
    switch (status) {
      case RideStatus.pending:
      case RideStatus.accepted:
        return '📦 IR A RECOGER';
      case RideStatus.arrivedAtPickup:
        return '⏳ ESPERANDO PASAJERO';
      case RideStatus.inProgress:
        return '🚗 EN CAMINO AL DESTINO';
      case RideStatus.completed:
        return '✅ COMPLETADO';
      case RideStatus.cancelled:
        return '❌ CANCELADO';
    }
  }

  @override
  Widget build(BuildContext context) {
    // === DEBUG: Track build intervals ===
    final now = DateTime.now();
    _debugBuildCount++;
    if (_debugLastBuildTime != null) {
      _debugLastBuildIntervalMs = now.difference(_debugLastBuildTime!).inMilliseconds;
    }
    _debugLastBuildTime = now;

    return SafeArea(
      child: Stack(
        children: [
          // Map - Mapbox 3D when ride active, FlutterMap otherwise
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF9500)),
            )
          else if (_hasRide)
            // MAPBOX 3D NAVIGATION + FLECHA CENTRAL
            Builder(
              builder: (ctx) {
                // UBER-STYLE: Padding para que el driver quede en el tercio inferior
                final screenSize = MediaQuery.of(ctx).size;
                final topPadding = screenSize.height * 0.35;

                return Stack(
                  children: [
                    // === MAPA 3D (Mapbox SDK - funciona en mobile, fallback en web) ===
                    Positioned.fill(
                      child: kIsWeb
                        ? _buildWebNavigationMapComplete() // Web: FlutterMap con UI completa
                        : mapbox.MapWidget(
                            key: ValueKey('mapbox_${widget.ride?.id ?? 'none'}'),
                            cameraOptions: mapbox.CameraOptions(
                              center: mapbox.Point(
                                coordinates: mapbox.Position(
                                  _driverLocation?.longitude ?? -112.0740,
                                  _driverLocation?.latitude ?? 33.4484,
                                ),
                              ),
                              zoom: 17.0,
                              bearing: _bearingToTarget,
                              pitch: 60, // 3D perspective
                              padding: mapbox.MbxEdgeInsets(
                                top: topPadding,
                                left: 0,
                                bottom: 0,
                                right: 0,
                              ),
                            ),
                            styleUri: mapbox.MapboxStyles.STANDARD,
                            onMapCreated: _onMapboxMapCreated,
                            onScrollListener: _onMapboxScroll,
                            onMapIdleListener: _onMapboxIdle,
                            onCameraChangeListener: _onMapboxCameraChange,
                          ),
                    ),
                    // === MOBILE ONLY: PINs overlay ===
                    if (!kIsWeb) ...[
                      ..._buildPinOverlays(),
                    ],
                  ],
                );
              },
            )
          else
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _driverLocation ?? _targetLocation ?? const LatLng(33.4484, -112.0740),
                initialZoom: 16,
                // Start with destination UP if tracking mode
                initialRotation: _isTrackingMode ? -_bearingToTarget : 0,
                onMapReady: () {
                  Future.delayed(const Duration(milliseconds: 500), () {
                    if (_isTrackingMode && _driverLocation != null) {
                      // Apply rotation so destination is UP
                      _mapController.moveAndRotate(
                        _driverLocation!,
                        16,
                        -_bearingToTarget,
                      );
                    } else {
                      _fitBounds();
                    }
                  });
                },
                // Disable tracking when user manually interacts with map
                onPositionChanged: (position, hasGesture) {
                  if (hasGesture && _isTrackingMode) {
                    setState(() => _isTrackingMode = false);
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.toro.driver',
                ),
                if (_routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePoints,
                        color: const Color(0xFFFF9500),
                        strokeWidth: 5,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    if (_driverLocation != null)
                      Marker(
                        point: _driverLocation!,
                        width: 60,
                        height: 60,
                        // Don't let flutter_map rotate the marker
                        rotate: false,
                        child: AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (context, child) {
                            // Calculate rotation for driver icon
                            // In tracking mode: show heading relative to destination
                            // (if heading == bearing, icon points UP toward destination)
                            // In north-up mode: show absolute heading
                            final iconRotation = _isTrackingMode
                                ? (_heading - _bearingToTarget) * math.pi / 180
                                : _heading * math.pi / 180;

                            return Transform.rotate(
                              angle: iconRotation,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Pulse ring
                                  Container(
                                    width: 50 * _pulseAnimation.value,
                                    height: 50 * _pulseAnimation.value,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(0xFF4285F4)
                                          .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  // Driver icon (navigation arrow)
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(0xFF4285F4),
                                      border: Border.all(color: Colors.white, width: 3),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF4285F4)
                                              .withValues(alpha: 0.6),
                                          blurRadius: 12,
                                          spreadRadius: 3,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.navigation_rounded,
                                      color: Colors.white,
                                      size: 26,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    // Target marker (only if there's a ride)
                    if (_targetLocation != null)
                      Marker(
                        point: _targetLocation!,
                        width: 50,
                        height: 50,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isGoingToPickup
                                ? const Color(0xFFFF9500)
                                : Colors.green,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: (_isGoingToPickup
                                        ? const Color(0xFFFF9500)
                                        : Colors.green)
                                    .withValues(alpha: 0.5),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Icon(
                            _isGoingToPickup
                                ? Icons.location_on
                                : Icons.flag_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                    // Dropoff marker when going to pickup (only if there's a ride)
                    if (_isGoingToPickup && widget.ride != null)
                      Marker(
                        point: LatLng(
                          widget.ride!.dropoffLocation.latitude,
                          widget.ride!.dropoffLocation.longitude,
                        ),
                        width: 40,
                        height: 40,
                        child: Opacity(
                          opacity: 0.6,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.green,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(
                              Icons.flag_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),

          // === NAVIGATION BANNER (EXPANDED) ===
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Column(
              children: [
                // === ROW 1: Back button + Navigation Banner ===
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 15,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Turn icon + Distance + ETA row
                      Row(
                        children: [
                          // Back button
                          if (widget.onExitNavigation != null)
                            GestureDetector(
                              onTap: () {
                                HapticService.lightImpact();
                                widget.onExitNavigation!();
                              },
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.arrow_back_rounded,
                                    color: Colors.white, size: 20),
                              ),
                            ),
                          if (widget.onExitNavigation != null) const SizedBox(width: 12),
                          // Turn icon (large)
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: _currentStep != null
                                  ? const Color(0xFF00C853)
                                  : const Color(0xFFFF9500),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              _currentStep?.maneuverIcon ?? Icons.directions_car,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Distance + ETA
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Distance (large)
                                Text(
                                  _routeDistance ?? '...',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                // ETA
                                if (_routeDuration != null)
                                  Text(
                                    _routeDuration!,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.7),
                                      fontSize: 16,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      // Turn instruction (if available)
                      if (_currentStep != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _currentStep!.bannerInstruction ?? _currentStep!.instruction,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // === ROW 2: Action Buttons (below banner) ===
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Tracking mode toggle
                    GestureDetector(
                      onTap: () {
                        HapticService.lightImpact();
                        setState(() {
                          _isTrackingMode = !_isTrackingMode;
                          if (_isTrackingMode && _driverLocation != null) {
                            _mapController.moveAndRotate(
                              _driverLocation!,
                              _mapController.camera.zoom,
                              -_bearingToTarget,
                            );
                          } else {
                            _mapController.rotate(0);
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: _isTrackingMode
                              ? const Color(0xFF4285F4)
                              : AppColors.card,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isTrackingMode
                                  ? Icons.navigation_rounded
                                  : Icons.explore_rounded,
                              color: _isTrackingMode
                                  ? Colors.white
                                  : const Color(0xFFFF9500),
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _isTrackingMode ? 'AUTO' : 'NORTH',
                              style: TextStyle(
                                color: _isTrackingMode ? Colors.white : Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Center on driver
                    GestureDetector(
                      onTap: () {
                        HapticService.lightImpact();
                        _centerOnDriver();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.my_location_rounded,
                            color: Color(0xFFFF9500), size: 18),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // External GPS
                    GestureDetector(
                      onTap: _openExternalGPS,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.map_outlined, color: Colors.white70, size: 18),
                            SizedBox(width: 6),
                            Text(
                              'GPS',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Bottom card with ride controls (only if there's a ride)
          if (_hasRide)
            Positioned(
              left: 16,
              right: 16,
              bottom: 32,
              child: Consumer2<RideProvider, DriverProvider>(
                builder: (context, rideProvider, driverProvider, child) {
                  final currentRide = rideProvider.activeRide ?? widget.ride!;
                  final rideStatus = currentRide.status;

                  return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFFFF9500).withValues(alpha: 0.3),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF9500).withValues(alpha: 0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // === ROW 1: Rider Info + Quick Actions ===
                      Row(
                        children: [
                          // Rider Avatar
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFFF9500).withValues(alpha: 0.2),
                              border: Border.all(color: const Color(0xFFFF9500), width: 2),
                            ),
                            child: currentRide.displayImageUrl != null
                                ? ClipOval(
                                    child: Image.network(
                                      currentRide.displayImageUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Center(
                                        child: Text(
                                          currentRide.displayName.isNotEmpty
                                              ? currentRide.displayName[0].toUpperCase()
                                              : 'C',
                                          style: const TextStyle(
                                            color: Color(0xFFFF9500),
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                                : Center(
                                    child: Text(
                                      currentRide.displayName.isNotEmpty
                                          ? currentRide.displayName[0].toUpperCase()
                                          : 'C',
                                      style: const TextStyle(
                                        color: Color(0xFFFF9500),
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          // Rider Name + Status
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentRide.displayName,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _getStatusColor(rideStatus).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        _getStatusLabel(rideStatus),
                                        style: TextStyle(
                                          color: _getStatusColor(rideStatus),
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '\$${(currentRide.driverEarnings > 0 ? currentRide.driverEarnings : currentRide.fare * 0.49).toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        color: AppColors.success,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Quick Action Button: Message (no phone calls)
                          _buildQuickActionButton(
                            icon: Icons.chat_bubble_outline,
                            color: const Color(0xFF4285F4),
                            onTap: () => _openInAppChat(currentRide),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // === ROW 2: Destination Address ===
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _isGoingToPickup ? Icons.location_on : Icons.flag,
                              color: _isGoingToPickup ? const Color(0xFFFF9500) : Colors.green,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _targetAddress,
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
                      ),
                      const SizedBox(height: 12),
                      // === ROW 3: Action Buttons ===
                      Row(
                        children: [
                          // Cancel Button (solo si no ha iniciado el viaje)
                          if (rideStatus != RideStatus.inProgress &&
                              rideStatus != RideStatus.completed &&
                              rideStatus != RideStatus.cancelled)
                            Expanded(
                              child: GestureDetector(
                                onTap: () => _showCancelDialog(context, rideProvider),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.close, color: Colors.red, size: 18),
                                      SizedBox(width: 6),
                                      Text(
                                        'CANCELAR',
                                        style: TextStyle(
                                          color: Colors.red,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          if (rideStatus != RideStatus.inProgress &&
                              rideStatus != RideStatus.completed &&
                              rideStatus != RideStatus.cancelled)
                            const SizedBox(width: 10),
                          // Main Action Button (Uber-style: siempre visible)
                          Expanded(
                            flex: 2,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Timer de espera (solo visible en arrivedAtPickup)
                                _buildWaitTimerWidget(),
                                // Botón de acción
                                _buildActionButton(context, rideProvider, driverProvider, rideStatus),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // === DEBUG OVERLAY REMOVIDO - reduce overhead de rendering ===
          // Para reactivar, descomentar el bloque de abajo
          /*
          Positioned(
            top: 200,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red, width: 2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('BUILD #$_debugBuildCount', style: const TextStyle(color: Colors.white, fontSize: 11)),
                  Text('GPS #$_gpsUpdateCount', style: const TextStyle(color: Colors.cyan, fontSize: 11)),
                  Text('CAM #$_cameraUpdateCount', style: const TextStyle(color: Colors.yellow, fontSize: 11)),
                ],
              ),
            ),
          ),
          */
        ],
      ),
    );
  }

  /// Botón circular pequeño para acciones rápidas (chat, llamar)
  Widget _buildQuickActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticService.lightImpact();
        onTap();
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.15),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  /// Abrir chat interno con el rider
  void _openInAppChat(RideModel ride) {
    // TODO: Implementar chat interno
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Chat interno próximamente...'),
        backgroundColor: Color(0xFF4285F4),
      ),
    );
  }

  /// Mostrar dialogo de cancelación
  void _showCancelDialog(BuildContext context, RideProvider rideProvider) {
    HapticService.mediumImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 12),
            Text('¿Cancelar viaje?', style: TextStyle(color: AppColors.textPrimary)),
          ],
        ),
        content: const Text(
          'Esta acción puede afectar tu calificación. ¿Estás seguro de que deseas cancelar?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('NO', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await rideProvider.cancelRide('driver_cancelled');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('SÍ, CANCELAR', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    RideProvider rideProvider,
    DriverProvider driverProvider,
    RideStatus status,
  ) {
    String buttonText;
    IconData buttonIcon;
    Color buttonColor;
    VoidCallback? onTap;
    bool isLoading = rideProvider.isLoading;
    bool isDisabled = false;

    switch (status) {
      case RideStatus.pending:
      case RideStatus.accepted:
        // === UBER-STYLE: Botón siempre visible, confirmación si está lejos ===
        final distanceText = _routeDistance ?? '...';
        buttonText = _isNearTarget ? 'LLEGUÉ AL PUNTO' : 'LLEGUÉ ($distanceText)';
        buttonIcon = Icons.location_on;
        buttonColor = const Color(0xFFFF9500);
        onTap = () async {
          debugPrint('🔵 BOTÓN LLEGUÉ presionado');
          debugPrint('🔵 activeRide: ${rideProvider.activeRide?.id}');
          debugPrint('🔵 isLoading: ${rideProvider.isLoading}');
          debugPrint('🔵 isNearTarget: $_isNearTarget');

          HapticService.mediumImpact();

          // Si está lejos (>100m), pedir confirmación
          if (!_isNearTarget) {
            debugPrint('🔵 Mostrando diálogo de confirmación...');
            final confirmed = await _showConfirmArrivalDialog();
            debugPrint('🔵 Confirmado: $confirmed');
            if (!confirmed) return;
          }

          debugPrint('🔵 Llamando arriveAtPickup...');
          final success = await rideProvider.arriveAtPickup();
          debugPrint('🔵 arriveAtPickup resultado: $success');
          debugPrint('🔵 Error: ${rideProvider.error}');

          if (success && context.mounted) {
            // Iniciar timer de espera
            _startWaitTimer();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Llegaste al punto. Esperando al pasajero...'),
                backgroundColor: Color(0xFFFF9500),
              ),
            );
          } else if (!success && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error: ${rideProvider.error ?? "No se pudo marcar llegada"}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        };
        break;

      case RideStatus.arrivedAtPickup:
        // === UBER-STYLE: Mostrar timer + botón INICIAR ===
        buttonText = 'INICIAR VIAJE';
        buttonIcon = Icons.play_arrow_rounded;
        buttonColor = const Color(0xFF4285F4);
        onTap = () async {
          HapticService.mediumImpact();
          _stopWaitTimer(); // Detener timer de espera
          final success = await rideProvider.startRide();
          if (success && context.mounted) {
            // === CAMBIO AUTOMÁTICO: Ahora navegar al DESTINO ===
            _lastRouteIndex = 0; // Reset navigation index
            _lastCalculatedBearing = 0;
            _navigationSteps = []; // Reset turn-by-turn
            _currentStepIndex = 0;
            await _fetchRouteFromMapbox(); // Nueva ruta al destino
            setState(() {});
          }
        };
        break;

      case RideStatus.inProgress:
        // === UBER-STYLE: Botón siempre visible, confirmación si está lejos ===
        final distanceTextDest = _routeDistance ?? '...';
        buttonText = _isNearTarget ? 'COMPLETAR VIAJE' : 'COMPLETAR ($distanceTextDest)';
        buttonIcon = Icons.check_circle;
        buttonColor = Colors.green;
        onTap = () async {
          HapticService.heavyImpact();

          // Si está lejos (>100m), pedir confirmación
          if (!_isNearTarget) {
            final confirmed = await _showConfirmCompletionDialog();
            if (!confirmed) return;
          }

          final driverId = driverProvider.driver?.id;
          if (driverId != null) {
            final success = await rideProvider.completeRide(driverId: driverId);
            if (success && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('¡Viaje completado! Ganancias agregadas.'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          }
        };
        break;

      case RideStatus.completed:
      case RideStatus.cancelled:
        buttonText = 'VOLVER AL INICIO';
        buttonIcon = Icons.home_rounded;
        buttonColor = AppColors.textSecondary;
        onTap = () {
          // The UI will automatically switch back when ride is completed
        };
        break;
    }

    return GestureDetector(
      onTap: isLoading || isDisabled ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isLoading || isDisabled
                ? [Colors.grey.shade700, Colors.grey.shade800]
                : [buttonColor, buttonColor.withValues(alpha: 0.8)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: isDisabled
              ? null
              : [
                  BoxShadow(
                    color: buttonColor.withValues(alpha: 0.4),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            else
              Icon(buttonIcon, color: isDisabled ? Colors.white54 : Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              buttonText,
              style: TextStyle(
                color: isDisabled ? Colors.white54 : Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    _locationSubscription?.cancel();
    _interpolationTimer?.cancel(); // Interpolation timer for smooth camera
    _debugTimer?.cancel(); // Debug FPS timer
    _returnToNavTimer?.cancel();
    _waitTimer?.cancel(); // Timer de espera Uber-style
    _pulseController.dispose();

    // CLEANUP: Limpiar recursos de Mapbox para evitar mapa fantasma
    _cleanupMapboxResources();

    debugPrint('🛰️ GPS Tracking stopped');
    super.dispose();
  }

  /// Limpiar recursos de Mapbox cuando el widget se destruye o el ride cambia
  void _cleanupMapboxResources() {
    try {
      _polylineManager?.deleteAll();
      _pointManager?.deleteAll();
    } catch (e) {
      debugPrint('Error cleaning Mapbox resources: $e');
    }
    _mapboxMap = null;
    _polylineManager = null;
    _pointManager = null;
    _mapboxRouteGeometry = [];
    _routePoints = [];
    _navigationSteps = [];
    debugPrint('🗺️ Mapbox resources cleaned');
  }

  // === UBER-STYLE WAIT TIMER FUNCTIONS ===

  void _startWaitTimer() {
    _arrivedAtPickupTime = DateTime.now();
    _waitSeconds = 0;
    _waitTimer?.cancel();
    _waitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _waitSeconds = DateTime.now().difference(_arrivedAtPickupTime!).inSeconds;
        });
      }
    });
  }

  void _stopWaitTimer() {
    _waitTimer?.cancel();
    _waitTimer = null;
    _arrivedAtPickupTime = null;
    _waitSeconds = 0;
  }

  String _formatWaitTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  bool get _isWaitTimeExceeded => _waitSeconds > (_freeWaitMinutes * 60);

  // Mostrar diálogo de confirmación cuando está lejos
  Future<bool> _showConfirmArrivalDialog() async {
    final distanceText = _routeDistance ?? '${_distanceToTargetMeters.toStringAsFixed(0)}m';

    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade400, size: 28),
            const SizedBox(width: 12),
            const Text('¿Confirmar llegada?', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Estás a $distanceText del punto de recogida.',
              style: TextStyle(color: Colors.grey.shade300, fontSize: 15),
            ),
            const SizedBox(height: 12),
            Text(
              '¿Estás seguro que ya llegaste?',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar', style: TextStyle(color: Colors.grey.shade400)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF9500),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Sí, llegué', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ) ?? false;
  }

  // Diálogo de confirmación para completar viaje lejos del destino
  Future<bool> _showConfirmCompletionDialog() async {
    final distanceText = _routeDistance ?? '${_distanceToTargetMeters.toStringAsFixed(0)}m';

    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade400, size: 28),
            const SizedBox(width: 12),
            const Text('¿Completar viaje?', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Estás a $distanceText del destino.',
              style: TextStyle(color: Colors.grey.shade300, fontSize: 15),
            ),
            const SizedBox(height: 12),
            Text(
              '¿El pasajero quiere bajarse aquí?',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar', style: TextStyle(color: Colors.grey.shade400)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Sí, completar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ) ?? false;
  }

  // Widget del timer de espera (mostrar encima del botón cuando arrivedAtPickup)
  Widget _buildWaitTimerWidget() {
    if (widget.ride?.status != RideStatus.arrivedAtPickup) {
      return const SizedBox.shrink();
    }

    final isOvertime = _isWaitTimeExceeded;
    final freeTimeLeft = (_freeWaitMinutes * 60) - _waitSeconds;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isOvertime ? Colors.red.shade900.withOpacity(0.3) : Colors.blue.shade900.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOvertime ? Colors.red.shade400 : Colors.blue.shade400,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isOvertime ? Icons.timer_off : Icons.timer,
            color: isOvertime ? Colors.red.shade300 : Colors.blue.shade300,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'Esperando: ${_formatWaitTime(_waitSeconds)}',
            style: TextStyle(
              color: isOvertime ? Colors.red.shade200 : Colors.blue.shade200,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (!isOvertime) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.shade800,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${_formatWaitTime(freeTimeLeft > 0 ? freeTimeLeft : 0)} gratis',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
          if (isOvertime) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.shade700,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'COBRO EXTRA',
                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

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

  _NavigationTrianglePainter({
    required this.color,
    required this.glowOpacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = ui.Path();

    // Triángulo apuntando hacia arriba (estilo navegación)
    path.moveTo(size.width / 2, 0); // Punta superior
    path.lineTo(size.width * 0.15, size.height * 0.85); // Esquina inferior izquierda
    path.lineTo(size.width / 2, size.height * 0.65); // Muesca central
    path.lineTo(size.width * 0.85, size.height * 0.85); // Esquina inferior derecha
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
