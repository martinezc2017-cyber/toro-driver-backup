import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../utils/app_colors.dart';
import '../services/notification_service.dart';
import '../core/logging/app_logger.dart';

/// Mandatory permissions gate screen for TORO Driver.
/// Blocks app usage until GPS and Notification permissions are granted.
/// Wraps the main content screens (HomeScreen, etc).
class PermissionsGateScreen extends StatefulWidget {
  final Widget child;

  const PermissionsGateScreen({super.key, required this.child});

  @override
  State<PermissionsGateScreen> createState() => _PermissionsGateScreenState();
}

class _PermissionsGateScreenState extends State<PermissionsGateScreen>
    with WidgetsBindingObserver {
  bool _locationGranted = false;
  bool _locationDeniedForever = false;
  bool _gpsEnabled = false;
  bool _notificationGranted = false;
  bool _checking = true;
  bool _allGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Re-check when user comes back from Settings
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_allGranted) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    if (kIsWeb) {
      setState(() {
        _allGranted = true;
        _checking = false;
      });
      return;
    }

    setState(() => _checking = true);

    // Check GPS service
    final gpsEnabled = await Geolocator.isLocationServiceEnabled();

    // Check location permission
    final locPerm = await Geolocator.checkPermission();
    final locGranted = locPerm == LocationPermission.always ||
        locPerm == LocationPermission.whileInUse;
    final locDeniedForever = locPerm == LocationPermission.deniedForever;

    // Check notification permission
    final msgSettings = await FirebaseMessaging.instance.getNotificationSettings();
    final notifGranted =
        msgSettings.authorizationStatus == AuthorizationStatus.authorized ||
            msgSettings.authorizationStatus == AuthorizationStatus.provisional;

    if (mounted) {
      setState(() {
        _gpsEnabled = gpsEnabled;
        _locationGranted = locGranted;
        _locationDeniedForever = locDeniedForever;
        _notificationGranted = notifGranted;
        _allGranted = locGranted && notifGranted && gpsEnabled;
        _checking = false;
      });
    }
  }

  Future<void> _requestLocation() async {
    if (_locationDeniedForever) {
      await Geolocator.openAppSettings();
      return;
    }

    if (!_gpsEnabled) {
      await Geolocator.openLocationSettings();
      return;
    }

    final result = await Geolocator.requestPermission();
    AppLogger.log('PERMISSIONS_GATE -> Location result: $result');

    if (result == LocationPermission.deniedForever) {
      setState(() => _locationDeniedForever = true);
    }

    await _checkPermissions();
  }

  Future<void> _requestNotifications() async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    AppLogger.log(
        'PERMISSIONS_GATE -> Notification result: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      if (Platform.isAndroid) {
        await Geolocator.openAppSettings();
      }
    }

    // If granted, initialize notification service to register FCM token
    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      try {
        await NotificationService().requestPermissions();
      } catch (e) {
        AppLogger.log('PERMISSIONS_GATE -> FCM init error: $e');
      }
    }

    await _checkPermissions();
  }

  @override
  Widget build(BuildContext context) {
    // If all permissions granted or still checking, show child directly
    if (_allGranted) {
      return widget.child;
    }

    if (_checking) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFFFFD700)),
        ),
      );
    }

    final allOk = _locationGranted && _notificationGranted && _gpsEnabled;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 40),

              // Logo area
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.local_taxi, color: Colors.black, size: 40),
              ),

              const SizedBox(height: 20),

              const Text(
                'TORO Driver necesita permisos',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'Para recibir viajes y navegar, necesitamos acceso a tu ubicacion y notificaciones.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 32),

              // GPS Permission Card
              _PermissionCard(
                icon: Icons.location_on,
                title: 'Ubicacion (GPS)',
                description: !_gpsEnabled
                    ? 'Tu GPS esta apagado. Activalo para recibir viajes cercanos y navegar.'
                    : _locationGranted
                        ? 'Permiso de ubicacion activado.'
                        : _locationDeniedForever
                            ? 'Permiso bloqueado. Abre Ajustes y activa la ubicacion para TORO Driver.'
                            : 'TORO necesita tu ubicacion para mostrarte viajes cercanos y permitir navegacion.',
                granted: _locationGranted && _gpsEnabled,
                blocked: _locationDeniedForever || !_gpsEnabled,
                onTap: _requestLocation,
              ),

              const SizedBox(height: 12),

              // Notification Permission Card
              _PermissionCard(
                icon: Icons.notifications_active,
                title: 'Notificaciones',
                description: _notificationGranted
                    ? 'Notificaciones activadas. Recibiras alertas de nuevos viajes.'
                    : 'Recibe alertas instantaneas de nuevos viajes, mensajes de pasajeros y actualizaciones importantes.',
                granted: _notificationGranted,
                blocked: false,
                onTap: _requestNotifications,
              ),

              const Spacer(),

              // Continue button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: allOk
                      ? () => setState(() => _allGranted = true)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        allOk ? const Color(0xFFFFD700) : const Color(0xFF2A2A2A),
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: const Color(0xFF2A2A2A),
                    disabledForegroundColor: Colors.white38,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: allOk ? 4 : 0,
                  ),
                  child: Text(
                    allOk ? 'Continuar' : 'Activa todos los permisos',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Text(
                'Tus datos se usan solo para el servicio de transporte. No compartimos tu ubicacion con terceros.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 11,
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool granted;
  final bool blocked;
  final VoidCallback onTap;

  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.granted,
    required this.blocked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color accentColor = granted
        ? const Color(0xFF22C55E)
        : blocked
            ? const Color(0xFFEF4444)
            : const Color(0xFFFFD700);

    return GestureDetector(
      onTap: granted ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: granted
                ? const Color(0xFF22C55E).withValues(alpha: 0.3)
                : const Color(0xFF2A2A2A),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accentColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (granted)
                        const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 16),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (!granted)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  blocked ? 'Ajustes' : 'Activar',
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
