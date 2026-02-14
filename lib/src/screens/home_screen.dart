import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
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
import 'package:supabase_flutter/supabase_flutter.dart';
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
import '../config/supabase_config.dart';
import '../services/audit_service.dart';
import '../services/mapbox_navigation_service.dart';
import '../services/tourism_event_service.dart';
import '../services/notification_service.dart';
import '../services/cash_account_service.dart';
import '../services/driver_qr_points_service.dart';
import '../services/ride_service.dart';
import 'earnings_screen.dart';
import 'rides_screen.dart';
import 'profile_screen.dart';
import 'navigation_map_screen.dart';
import 'tourism/vehicle_request_screen.dart';
import 'organizer/organizer_home_screen.dart';
import 'cash_balance_screen.dart';
import 'account_suspended_screen.dart';
import 'rental/browse_rentals_screen.dart';
import '../widgets/toro_3d_pin.dart';
import '../core/logging/app_logger.dart';

/// Tracks which event chat screens are currently open on the driver side.
/// Used to suppress chat notifications when the user is viewing the chat.
class ActiveDriverChatTracker {
  static final Set<String> _activeChats = {};

  static void open(String eventId) => _activeChats.add(eventId);
  static void close(String eventId) => _activeChats.remove(eventId);
  static bool isOpen(String eventId) => _activeChats.contains(eventId);
}

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

  // Mode toggle: Driver (normal rides) vs Tourism (events/rentals)
  bool _isTourismMode = false;

  // Collapsible section states
  bool _showDailyEarnings = true;
  bool _showWeeklyEarnings = true;
  bool _showRentalSection = false; // Collapsed by default
  bool _showQRTierExpanded = false; // QR tier panel expand/collapse

  // === APP LIFECYCLE OPTIMIZATION ===
  bool _isAppInBackground = false;

  // === VEHICLE REQUESTS ===
  int _pendingRequestsCount = 0;
  final TourismEventService _tourismService = TourismEventService();
  RealtimeChannel? _vehicleRequestsChannel;
  RealtimeChannel? _notificationsChannel;
  final NotificationService _notificationService = NotificationService();

  // === NOTIFICATIONS ===
  int _unreadNotificationsCount = 0;

  // === TOURISM CHAT NOTIFICATIONS ===
  RealtimeChannel? _chatMessagesChannel;

  // === QR POINTS ===
  final DriverQRPointsService _qrPointsService = DriverQRPointsService();
  bool _qrServiceInitialized = false;

  // === CASH CONTROL ===
  final CashAccountService _cashService = CashAccountService();
  double _cashOwed = 0;
  String _cashAccountStatus = 'active';

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
      _loadPendingRequestsCount();
      _loadUnreadNotificationsCount();
      _subscribeToVehicleRequests();
      _subscribeToNotifications();
      _subscribeToChatMessages();
      _loadCashAccountStatus();
      _initQRService();
      // Request permissions sequentially so dialogs don't overlap
      _requestPermissionsSequentially();
      // Run tourism schema diagnostics on startup
      TourismEventService().validateSchemaConnections();
    });
  }

  Future<void> _requestPermissionsSequentially() async {
    // Location first, then notifications - so dialogs don't overlap
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }
    // Small delay then request notifications
    await Future.delayed(const Duration(milliseconds: 500));
    NotificationService().requestPermissions();
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
      // Also refresh pending requests count
      _loadPendingRequestsCount();
    } catch (e) {
      // Ignore refresh errors on resume
    }
  }

  // === VEHICLE REQUESTS MANAGEMENT ===

  Future<void> _loadPendingRequestsCount() async {
    try {
      final driverProvider = Provider.of<DriverProvider>(context, listen: false);
      final driver = driverProvider.driver;

      if (driver == null) return;

      final requests = await _tourismService.getPendingVehicleRequests(driver.id);

      if (mounted) {
        setState(() {
          _pendingRequestsCount = requests.length;
        });
      }
    } catch (e) {
      // Silently fail - not critical
      debugPrint('Error loading pending requests count: $e');
    }
  }

  Future<void> _loadUnreadNotificationsCount() async {
    try {
      final driverProvider = Provider.of<DriverProvider>(context, listen: false);
      final driver = driverProvider.driver;

      if (driver == null) return;

      final count = await _notificationService.getUnreadCount(driver.id);

      if (mounted) {
        setState(() {
          _unreadNotificationsCount = count;
        });
      }
    } catch (e) {
      // Silently fail - not critical
      debugPrint('Error loading unread notifications count: $e');
    }
  }

  Future<void> _loadCashAccountStatus() async {
    try {
      final driverProvider = Provider.of<DriverProvider>(context, listen: false);
      final driver = driverProvider.driver;
      if (driver == null) return;

      final account = await _cashService.getCashAccount(driver.id);
      if (mounted && account != null) {
        final balance = (account['current_balance'] as num?)?.toDouble() ?? 0;
        final status = account['status'] as String? ?? 'active';

        setState(() {
          _cashOwed = balance;
          _cashAccountStatus = status;
        });

        // Auto-navigate to suspended screen if account is suspended/blocked
        if ((status == 'suspended' || status == 'blocked') && balance > 0) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AccountSuspendedScreen(
                amountOwed: balance,
                blockedReason: account['blocked_reason'] as String?,
              ),
            ),
          ).then((_) {
            // Refresh status when returning from suspended screen
            _loadCashAccountStatus();
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading cash account: $e');
    }
  }

  void _initQRService() {
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    final driver = driverProvider.driver;
    if (driver == null || _qrServiceInitialized) return;

    _qrPointsService.initialize(driver.id);
    _qrPointsService.addListener(_onQRServiceUpdate);
    _qrServiceInitialized = true;
  }

  void _onQRServiceUpdate() {
    if (mounted) setState(() {});
  }

  void _subscribeToVehicleRequests() {
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    final driver = driverProvider.driver;

    if (driver == null) return;

    _vehicleRequestsChannel = _tourismService.subscribeToVehicleRequests(
      driver.id,
      (request) {
        // Reload count when new requests arrive
        _loadPendingRequestsCount();
      },
    );
  }

  Future<void> _unsubscribeFromVehicleRequests() async {
    if (_vehicleRequestsChannel != null) {
      await _tourismService.unsubscribe(_vehicleRequestsChannel!);
      _vehicleRequestsChannel = null;
    }
  }

  void _subscribeToNotifications() {
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    final driver = driverProvider.driver;

    if (driver == null) {
      debugPrint('⚠️ Cannot subscribe to notifications: driver is null');
      // Retry after 1 second
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          _subscribeToNotifications();
        }
      });
      return;
    }

    // Don't subscribe twice
    if (_notificationsChannel != null) {
      debugPrint('⚠️ Already subscribed to notifications');
      return;
    }

    // Subscribe to notifications table for real-time push notifications
    _notificationsChannel = Supabase.instance.client
        .channel('notifications_${driver.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: driver.id,
          ),
          callback: (payload) {
            if (mounted && payload.newRecord.isNotEmpty) {
              debugPrint('🔔 Received notification from Realtime: ${payload.newRecord}');
              _handleNewNotification(payload.newRecord);
            }
          },
        )
        .subscribe();

    debugPrint('🔔 Subscribed to notifications for driver ${driver.id}');
  }

  Future<void> _unsubscribeFromNotifications() async {
    if (_notificationsChannel != null) {
      await Supabase.instance.client.removeChannel(_notificationsChannel!);
      _notificationsChannel = null;
    }
  }

  // === TOURISM CHAT MESSAGE NOTIFICATIONS ===

  void _subscribeToChatMessages() {
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    final driver = driverProvider.driver;
    if (driver == null) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _subscribeToChatMessages();
      });
      return;
    }

    if (_chatMessagesChannel != null) return; // Already subscribed

    _chatMessagesChannel = Supabase.instance.client
        .channel('tourism_chat_driver_${driver.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'tourism_messages',
          callback: (payload) {
            if (mounted && payload.newRecord.isNotEmpty) {
              _handleChatMessage(payload.newRecord, driver.id);
            }
          },
        )
        .subscribe();

    debugPrint('🔔 Subscribed to tourism chat messages for driver ${driver.id}');
  }

  void _handleChatMessage(Map<String, dynamic> record, String currentUserId) {
    final senderId = record['sender_id'] as String? ?? '';
    final eventId = record['event_id'] as String? ?? '';
    final senderName = record['sender_name'] as String? ?? '';
    final message = record['message'] as String? ?? '';
    final messageType = record['message_type'] as String? ?? 'text';

    // Skip own messages
    if (senderId == currentUserId) return;

    // Skip if chat screen for this event is currently open
    if (ActiveDriverChatTracker.isOpen(eventId)) return;

    // Skip system messages
    if (messageType == 'system') return;

    // Determine notification content
    String title;
    String body;

    switch (messageType) {
      case 'emergency':
        title = 'ALERTA DE EMERGENCIA';
        body = message.isNotEmpty ? message : 'Alerta de emergencia en el evento';
        // Use high-priority channel for emergencies
        _notificationService.showRideRequestNotification(
          rideId: eventId,
          pickupAddress: body,
          fare: 0,
        );
        // Also show in-app emergency dialog
        if (mounted) {
          _showEmergencyDialog(title, body, eventId);
        }
        return;
      case 'call_to_bus':
        title = 'Regresen al autobus';
        body = senderName.isNotEmpty ? 'De: $senderName' : '';
        break;
      case 'announcement':
        title = 'Aviso del evento';
        body = message;
        break;
      case 'image':
      case 'gif':
        title = senderName.isNotEmpty ? senderName : 'Nuevo mensaje';
        body = 'Imagen';
        break;
      case 'location':
        title = senderName.isNotEmpty ? senderName : 'Nuevo mensaje';
        body = 'Ubicacion compartida';
        break;
      default:
        title = senderName.isNotEmpty ? senderName : 'Nuevo mensaje';
        body = message;
    }

    _notificationService.showMessageNotification(
      conversationId: eventId,
      senderName: title,
      message: body,
    );
  }

  Future<void> _unsubscribeFromChatMessages() async {
    if (_chatMessagesChannel != null) {
      await Supabase.instance.client.removeChannel(_chatMessagesChannel!);
      _chatMessagesChannel = null;
    }
  }

  /// Show emergency dialog for tourism emergencies (driver side)
  void _showEmergencyDialog(String title, String body, String eventId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.red.withOpacity(0.3),
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.red, width: 2),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'ALERTA DE EMERGENCIA',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Text(
          body.isNotEmpty ? body : 'Se ha emitido una alerta de emergencia.',
          style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendido', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _handleNewNotification(Map<String, dynamic> notification) {
    final String title = notification['title'] ?? 'Toro Driver';
    final String body = notification['body'] ?? '';
    final String type = notification['type'] ?? 'system';

    // Parse data — may come as Map or JSON string from realtime
    Map<String, dynamic> data = {};
    final rawData = notification['data'];
    if (rawData is Map<String, dynamic>) {
      data = rawData;
    } else if (rawData is Map) {
      data = Map<String, dynamic>.from(rawData);
    } else if (rawData is String && rawData.isNotEmpty) {
      try {
        data = Map<String, dynamic>.from(jsonDecode(rawData));
      } catch (_) {}
    }

    debugPrint('🔔 New notification: type=$type, title=$title');

    // Show local notification based on type
    switch (type) {
      case 'vehicle_request':
        // Use general notification for vehicle requests (shows title/body from DB)
        _notificationService.showGeneralNotification(
          title: title,
          body: body,
          data: data,
        );
        // Reload badge count
        _loadPendingRequestsCount();
        break;

      case 'bid_request':
        _notificationService.showGeneralNotification(
          title: title,
          body: body,
          data: data,
        );
        break;

      case 'bid_won':
        // Winning bid - high priority notification + in-app banner
        _notificationService.showGeneralNotification(
          title: title,
          body: body,
          data: data,
        );
        // Show prominent in-app banner
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.emoji_events, color: Colors.amber, size: 28),
                  const SizedBox(width: 12),
                  Expanded(child: Text(body, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                ],
              ),
              backgroundColor: Colors.green.shade700,
              duration: const Duration(seconds: 6),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        break;

      case 'bid_lost':
        _notificationService.showGeneralNotification(
          title: title,
          body: body,
          data: data,
        );
        break;

      case 'bid_response':
      case 'counter_offer':
        _notificationService.showGeneralNotification(
          title: title,
          body: body,
          data: data,
        );
        break;

      case 'event_update':
      case 'tourism_warning':
      case 'tourism_event_updated':
        _notificationService.showGeneralNotification(
          title: title,
          body: body,
          data: data,
        );
        break;

      // === LVL 4: EMERGENCY BROADCAST ===
      case 'tourism_emergency_broadcast':
      case 'tourism_emergency':
        // High-priority system notification
        _notificationService.showGeneralNotification(
          title: title,
          body: body,
          data: {'type': type, ...data},
        );
        // Show blocking emergency dialog
        if (mounted) {
          _showEmergencyDialog(title, body, data['event_id'] as String? ?? '');
        }
        break;

      // === TOURISM ANNOUNCEMENTS ===
      case 'tourism_organizer_announcement':
        _notificationService.showGeneralNotification(
          title: title,
          body: body,
          data: data,
        );
        // Show in-app banner
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.campaign_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(body, style: const TextStyle(color: Colors.white), maxLines: 2, overflow: TextOverflow.ellipsis)),
                ],
              ),
              backgroundColor: const Color(0xFF1565C0),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        break;

      // === TOURISM INVITATION ===
      case 'tourism_invitation':
      case 'tourism_invitation_accepted':
      case 'tourism_join_accepted':
      case 'tourism_join_rejected':
        _notificationService.showGeneralNotification(
          title: title,
          body: body,
          data: data,
        );
        break;

      case 'payment':
        // Extract amount and description from notification data
        final double amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
        final String description = data['description']?.toString() ?? body;
        _notificationService.showEarningNotification(
          amount: amount,
          description: description,
        );
        break;

      default:
        _notificationService.showGeneralNotification(
          title: title,
          body: body,
          data: data,
        );
    }

    // Update unread notifications badge count
    _loadUnreadNotificationsCount();
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
    // Cleanup vehicle requests subscription
    _unsubscribeFromVehicleRequests();
    // Cleanup notifications subscription
    _unsubscribeFromNotifications();
    // Cleanup chat messages subscription
    _unsubscribeFromChatMessages();
    // Cleanup QR points service
    _qrPointsService.removeListener(_onQRServiceUpdate);
    _qrPointsService.dispose();
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
    final scaffold = Consumer<DriverProvider>(
      builder: (context, driverProvider, child) {
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            systemNavigationBarColor: AppColors.surface,
            systemNavigationBarIconBrightness: Brightness.light,
          ),
          child: Scaffold(
            backgroundColor: AppColors.background,
            body: _buildBody(),
            bottomNavigationBar: (_selectedNavIndex == 1 || _isTourismMode || _isOrganizer) ? null : _buildBottomNav(),
          ),
        );
      },
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

  /// Check if current user is an organizer (no driver features needed)
  bool get _isOrganizer {
    try {
      final driverProvider = Provider.of<DriverProvider>(context, listen: false);
      return driverProvider.driver?.role == 'organizer';
    } catch (_) {
      return false;
    }
  }

  Widget _buildBody() {
    // Organizer users go straight to Tourism/Organizer mode - no driver features
    if (_isOrganizer) {
      return OrganizerHomeScreen(
        onSwitchToDriverMode: null, // No switch back for organizers
      );
    }

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
        // If in Tourism Mode, show Organizer content
        if (_isTourismMode) {
          return OrganizerHomeScreen(
            onSwitchToDriverMode: () {
              setState(() {
                _isTourismMode = false;
              });
            },
          );
        }

        // Normal Driver Mode
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
                          if (_cashOwed > 0 || _cashAccountStatus != 'active')
                            _buildCashOwedBanner(),
                          _buildIncomingRides(),
                          _buildEarningsCard(),
                          const SizedBox(height: 12),
                          _buildQRTierPanel(),
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
              // Mode Toggle: Driver vs Tourism
              GestureDetector(
                onTap: () {
                  HapticService.lightImpact();
                  setState(() {
                    _isTourismMode = !_isTourismMode;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isTourismMode
                          ? const Color(0xFFFF9500)
                          : const Color(0xFF3B82F6),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Driver Mode
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          gradient: !_isTourismMode
                              ? const LinearGradient(
                                  colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                                )
                              : null,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.local_taxi_rounded,
                              color: !_isTourismMode
                                  ? Colors.white
                                  : AppColors.textTertiary,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Driver',
                              style: TextStyle(
                                color: !_isTourismMode
                                    ? Colors.white
                                    : AppColors.textTertiary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Tourism Mode
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          gradient: _isTourismMode
                              ? const LinearGradient(
                                  colors: [Color(0xFFFF9500), Color(0xFFFF6B00)],
                                )
                              : null,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.directions_bus_rounded,
                              color: _isTourismMode
                                  ? Colors.white
                                  : AppColors.textTertiary,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Turismo',
                              style: TextStyle(
                                color: _isTourismMode
                                    ? Colors.white
                                    : AppColors.textTertiary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Vehicle Requests
              _LuxuryIconButton(
                icon: Icons.event_note,
                onTap: () async {
                  HapticService.lightImpact();
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const VehicleRequestScreen(),
                    ),
                  );
                  // Refresh count when returning from screen
                  _loadPendingRequestsCount();
                },
                badgeCount: _pendingRequestsCount,
              ),
              const SizedBox(width: 8),
              // Notifications
              _LuxuryIconButton(
                icon: Icons.notifications_none_rounded,
                onTap: () async {
                  HapticService.lightImpact();
                  await Navigator.pushNamed(context, '/notifications');
                  // Refresh count when returning from notifications screen
                  _loadUnreadNotificationsCount();
                },
                badgeCount: _unreadNotificationsCount,
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
  // ═══════════════════════════════════════════════════════════════════════════
  // CASH OWED BANNER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCashOwedBanner() {
    final isSuspended = _cashAccountStatus == 'suspended' || _cashAccountStatus == 'blocked';

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CashBalanceScreen()),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isSuspended
                ? [const Color(0xFFDC2626), const Color(0xFFB91C1C)]
                : [const Color(0xFFF59E0B), const Color(0xFFD97706)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: (isSuspended ? const Color(0xFFDC2626) : const Color(0xFFF59E0B))
                  .withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              isSuspended ? Icons.block_rounded : Icons.account_balance_wallet_rounded,
              color: Colors.white,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isSuspended ? 'CUENTA SUSPENDIDA' : 'DEBES A TORO',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '\$${_cashOwed.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    isSuspended
                        ? 'Deposita para reactivar tu cuenta'
                        : 'De viajes en efectivo',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isSuspended ? 'Depositar' : 'Ver',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
                  driverQrTier: _qrPointsService.currentTier,
                  onNegotiate: _qrPointsService.currentTier >= 1
                      ? (proposedPrice) async {
                          HapticService.mediumImpact();
                          final driverId = driverProvider.driver?.id;
                          if (driverId == null) return;
                          final success = await rideProvider.proposePrice(
                            rideId: ride.id,
                            driverId: driverId,
                            proposedPrice: proposedPrice,
                            driverQrTier: _qrPointsService.currentTier,
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(success
                                    ? 'Oferta enviada: \$${proposedPrice.toStringAsFixed(2)}'
                                    : rideProvider.error ?? 'Error al enviar oferta'),
                                backgroundColor: success ? const Color(0xFF1E88E5) : Colors.red,
                              ),
                            );
                          }
                        }
                      : null,
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
  // QR TIER PANEL - Blue transparent panel with tier info + QR code
  // New model: QR scans per week → reduced Toro commission (not bonus %)
  // Tier 0: 20% | Tier 1: 19% | Tier 2: 18% | Tier 3: 17% | Tier 4: 16% | Tier 5: 15%
  // ═══════════════════════════════════════════════════════════════════════════

  // Commission tiers: index 0 = no QR, 1-5 = tier 1-5
  static const List<int> _tierMaxQRs = [0, 6, 12, 18, 24, 30];
  static const List<double> _tierCommission = [20, 19, 18, 17, 16, 15];

  int _getDriverTier(int qrLevel) {
    if (qrLevel <= 0) return 0;
    if (qrLevel <= 6) return 1;
    if (qrLevel <= 12) return 2;
    if (qrLevel <= 18) return 3;
    if (qrLevel <= 24) return 4;
    return 5;
  }

  double _getCommissionForTier(int tier) {
    if (tier < 0 || tier > 5) return 20;
    return _tierCommission[tier];
  }

  Widget _buildQRTierPanel() {
    final driver = context.read<DriverProvider>().driver;
    if (driver == null) return const SizedBox.shrink();

    final qrCode = driver.qrCode ?? 'TORO-DRV-${driver.id.substring(0, 5).toUpperCase()}';
    final qrLink = 'https://tororider.app/d/$qrCode';

    // Live data from DriverQRPointsService
    final qrLevel = _qrPointsService.currentLevel.level;
    final currentTier = _qrPointsService.currentTier;
    final currentCommission = _qrPointsService.effectivePlatformPercent;
    final myRank = _qrPointsService.myStateRank;
    final nextTierQRs = currentTier < 5
        ? _tierMaxQRs[currentTier + 1] - qrLevel
        : 0;
    final nextCommission = currentTier < 5
        ? _tierCommission[currentTier + 1]
        : _tierCommission[5];
    final progress = currentTier < 5 && _tierMaxQRs[currentTier + 1] > 0
        ? qrLevel / _tierMaxQRs[currentTier + 1]
        : 1.0;

    const panelBlue = Color(0xFF1E88E5);
    const panelSecondary = Color(0xFF00BCD4);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            panelBlue.withValues(alpha: 0.40),
            panelSecondary.withValues(alpha: 0.30),
            AppColors.card.withValues(alpha: 0.85),
          ],
        ),
        border: Border.all(
          color: panelBlue.withValues(alpha: 0.5),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // === HEADER - always visible, tap to expand ===
          InkWell(
            onTap: () => setState(() => _showQRTierExpanded = !_showQRTierExpanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  // QR icon
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [panelBlue, panelSecondary],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Mi Nivel QR',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00FF66).withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFF00FF66).withValues(alpha: 0.7),
                                ),
                              ),
                              child: Text(
                                currentTier > 0 ? 'Tier $currentTier' : '$qrLevel QRs',
                                style: const TextStyle(
                                  color: Color(0xFF00FF66),
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Comisión Toro: ${currentCommission.toStringAsFixed(0)}%'
                          '${myRank > 0 ? ' · #$myRank en ranking' : ''}'
                          '${currentTier < 5 ? ' · $nextTierQRs QRs para ${nextCommission.toStringAsFixed(0)}%' : ' · Máximo'}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _showQRTierExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white70,
                    size: 28,
                  ),
                ],
              ),
            ),
          ),

          // === PROGRESS BAR - always visible ===
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(3),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progress.clamp(0, 1).toDouble(),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00FF66), Color(0xFF00CC99)],
                    ),
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00FF66).withValues(alpha: 0.4),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // === EXPANDED CONTENT ===
          if (_showQRTierExpanded) ...[
            const SizedBox(height: 12),

            // Tier table
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: List.generate(5, (i) {
                    final tierNum = i + 1;
                    final prevMax = i == 0 ? 0 : _tierMaxQRs[i];
                    final maxQR = _tierMaxQRs[tierNum];
                    final commission = _tierCommission[tierNum];
                    final isCurrent = currentTier == tierNum;
                    final isReached = qrLevel >= (prevMax + 1);

                    return Container(
                      margin: EdgeInsets.only(bottom: i < 4 ? 4 : 0),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? const Color(0xFF00FF66).withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: isCurrent
                            ? Border.all(color: const Color(0xFF00FF66).withValues(alpha: 0.3))
                            : null,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 50,
                            child: Text(
                              'Tier $tierNum',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                color: isCurrent
                                    ? const Color(0xFF00FF66)
                                    : isReached
                                        ? Colors.white
                                        : Colors.white54,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${prevMax + 1}-$maxQR QRs',
                              style: TextStyle(
                                fontSize: 12,
                                color: isCurrent ? Colors.white : Colors.white60,
                              ),
                            ),
                          ),
                          Text(
                            '${commission.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isCurrent
                                  ? const Color(0xFF00FF66)
                                  : isReached
                                      ? Colors.greenAccent
                                      : Colors.white54,
                            ),
                          ),
                          if (isCurrent) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.arrow_back_rounded, size: 12, color: Color(0xFF00FF66)),
                          ],
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // QR Code + Share buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  // Mini QR
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: QrImageView(
                      data: qrLink,
                      version: QrVersions.auto,
                      size: 80,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Color(0xFF1E88E5),
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Color(0xFF1E88E5),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Share buttons
                  Expanded(
                    child: Column(
                      children: [
                        // Code display
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            qrCode,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              letterSpacing: 1.5,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Action row
                        Row(
                          children: [
                            Expanded(
                              child: _buildQRActionButton(
                                icon: Icons.fullscreen,
                                label: 'Ver QR',
                                onTap: () => _showFullQRCode(qrLink, qrCode),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildQRActionButton(
                                icon: Icons.share,
                                label: 'Compartir',
                                onTap: () => _shareDriverQR(qrCode, qrLink),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // How it works hint
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lightbulb_outline, color: Colors.amber, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Riders escanean tu QR → ambos ganan puntos → tu comisión baja',
                        style: TextStyle(color: Colors.white60, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildQRActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFF1E88E5).withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFullQRCode(String qrLink, String code) {
    const panelBlue = Color(0xFF1E88E5);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: panelBlue.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade600,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Comparte tu código QR',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'Riders escanean → ambos ganan puntos → tu comisión baja',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // Large QR
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: panelBlue.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: QrImageView(
                data: qrLink,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: panelBlue),
                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: panelBlue),
              ),
            ),
            const SizedBox(height: 16),
            // Code display
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: panelBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                code,
                style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold,
                  color: panelBlue, letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: qrLink));
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Link copiado')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copiar Link'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: panelBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _shareDriverQR(code, qrLink),
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('Compartir'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: panelBlue,
                      side: const BorderSide(color: panelBlue),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(qrLink, style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _shareDriverQR(String code, String link) async {
    final message = 'Únete a TORO y escanea mi QR. '
        'Ambos ganamos puntos para bajar comisiones.\n'
        'Código: $code\n$link';
    await Clipboard.setData(ClipboardData(text: link));
    await Share.share(message, subject: 'TORO Driver - Mi código QR');
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
                  icon: Icons.garage_rounded,
                  label: 'Mis Vehiculos',
                  subtitle: 'Ver, editar o eliminar vehiculos',
                  onTap: () {
                    HapticService.lightImpact();
                    _showMyVehiclesSheet();
                  },
                ),
                Divider(
                  color: AppColors.border.withValues(alpha: 0.3),
                  height: 1,
                  indent: 56,
                ),
                _buildRentalActionItem(
                  icon: Icons.search_rounded,
                  label: 'Buscar Vehiculo de Renta',
                  subtitle: 'Encuentra vehiculos disponibles',
                  onTap: () {
                    HapticService.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const BrowseRentalsScreen()),
                    );
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

    // Use full-screen route instead of bottom sheet to prevent accidental dismissal
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => _PublishVehicleSheet(userId: userId),
        fullscreenDialog: true,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MY VEHICLES LIST (VIEW/EDIT/DELETE)
  // ═══════════════════════════════════════════════════════════════════════════

  void _showMyVehiclesSheet() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.driverId;

    if (userId == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => _MyVehiclesSheet(userId: userId),
        fullscreenDialog: true,
      ),
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
  final int? badgeCount;

  const _LuxuryIconButton({
    required this.icon,
    required this.onTap,
    this.badgeCount,
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
          clipBehavior: Clip.none,
          children: [
            Icon(widget.icon, color: AppColors.textSecondary, size: 22),
            if (widget.badgeCount != null && widget.badgeCount! > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.surface,
                      width: 1.5,
                    ),
                  ),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  child: Text(
                    widget.badgeCount! > 99 ? '99+' : widget.badgeCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      height: 1.0,
                    ),
                    textAlign: TextAlign.center,
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
              Flexible(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  child: Text(
                    _positiveMessages[_messageIndex],
                    key: ValueKey<int>(_messageIndex),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
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
  final int driverQrTier; // Driver's QR tier (0-5) for negotiate eligibility
  final void Function(double proposedPrice)? onNegotiate;

  const _FireGlowRideCard({
    required this.ride,
    required this.onAccept,
    this.onReject,
    this.onTap,
    this.pickupDistanceMiles,
    this.driverQrTier = 0,
    this.onNegotiate,
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

  static String _getVehicleTypeLabel(String vehicleType) {
    switch (vehicleType) {
      case 'moto': return 'Toro Moto';
      case 'xl': return 'Toro XL';
      case 'premium': return 'Premium';
      case 'black': return 'Black';
      case 'pickup': return 'Pickup';
      case 'bicycle': return 'Eco';
      case 'autobus': return 'Bus';
      default: return vehicleType;
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

  // Negotiate dialog - slider to propose a higher price
  void _showNegotiateDialog() {
    final baseFare = widget.ride.fare;
    final maxPercent = RideService.getMaxNegotiatePercent(widget.driverQrTier);
    final maxPrice = baseFare * (1 + maxPercent / 100);
    double proposedPrice = baseFare;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final increase = proposedPrice - baseFare;
            final increasePercent = baseFare > 0 ? (increase / baseFare) * 100 : 0.0;

            return Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFF1E88E5).withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1E88E5), Color(0xFF00BCD4)],
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.handshake_rounded, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Negociar Precio',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              'Tier ${widget.driverQrTier} - Hasta +${maxPercent.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF1E88E5),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Price display
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Precio original',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                          Text(
                            '\$${baseFare.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 16,
                              color: AppColors.textSecondary,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'Tu oferta',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF1E88E5),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '\$${proposedPrice.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E88E5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // Increase indicator
                  if (increase > 0)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00FF66).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '+\$${increase.toStringAsFixed(2)} (+${increasePercent.toStringAsFixed(0)}%)',
                        style: const TextStyle(
                          color: Color(0xFF00FF66),
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Slider
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: const Color(0xFF1E88E5),
                      inactiveTrackColor: const Color(0xFF1E88E5).withValues(alpha: 0.2),
                      thumbColor: const Color(0xFF1E88E5),
                      overlayColor: const Color(0xFF1E88E5).withValues(alpha: 0.15),
                      trackHeight: 6,
                    ),
                    child: Slider(
                      value: proposedPrice,
                      min: baseFare,
                      max: maxPrice,
                      divisions: ((maxPrice - baseFare) / 0.5).round().clamp(1, 100),
                      onChanged: (value) {
                        setModalState(() {
                          proposedPrice = double.parse(value.toStringAsFixed(2));
                        });
                      },
                    ),
                  ),

                  // Quick select buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [5, 10, 15, 20, 25, 30]
                        .where((p) => p <= maxPercent)
                        .map((percent) {
                      final price = baseFare * (1 + percent / 100);
                      final isSelected = (proposedPrice - price).abs() < 0.01;
                      return GestureDetector(
                        onTap: () {
                          setModalState(() {
                            proposedPrice = double.parse(price.toStringAsFixed(2));
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF1E88E5)
                                : const Color(0xFF1E88E5).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFF1E88E5).withValues(alpha: isSelected ? 1 : 0.3),
                            ),
                          ),
                          child: Text(
                            '+$percent%',
                            style: TextStyle(
                              color: isSelected ? Colors.white : const Color(0xFF1E88E5),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 8),
                  Text(
                    'El rider tiene 30 seg para aceptar o rechazar',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Send offer button
                  SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        widget.onNegotiate?.call(proposedPrice);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1E88E5), Color(0xFF00BCD4)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF1E88E5).withValues(alpha: 0.4),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'ENVIAR OFERTA \$${proposedPrice.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
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
            );
          },
        );
      },
    );
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
                    // Vehicle type badge (if not standard)
                    if (widget.ride.vehicleType != 'standard') ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFA855F7).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFFA855F7).withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          _getVehicleTypeLabel(widget.ride.vehicleType),
                          style: const TextStyle(
                            color: Color(0xFFA855F7),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
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
                // Buttons row - REJECT / NEGOTIATE / ACCEPT
                Row(
                  children: [
                    // Reject button (X)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        widget.onReject?.call();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
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
                        child: Icon(
                          Icons.close_rounded,
                          color: AppColors.error,
                          size: 18,
                        ),
                      ),
                    ),
                    // Negotiate button - only for QR Tier 1+
                    if (widget.driverQrTier >= 1 && widget.onNegotiate != null) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _showNegotiateDialog(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1E88E5), Color(0xFF00BCD4)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.handshake_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'NEGOCIAR',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
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
                                'ACEPTAR',
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
  final Color color;
  final VoidCallback onTap;

  const _NavOptionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
  final Map<String, dynamic>? existingVehicle; // For editing

  const _PublishVehicleSheet({
    required this.userId,
    this.existingVehicle,
  });

  @override
  State<_PublishVehicleSheet> createState() => _PublishVehicleSheetState();
}

class _PublishVehicleSheetState extends State<_PublishVehicleSheet> {
  static const _accent = Color(0xFF8B5CF6);

  // Contract text constant (used for display and storage)
  // Generate contract text with vehicle and insurance information
  String get _contractText {
    final insuranceInfo = _insCompanyCtrl.text.trim().isNotEmpty
        ? '\nINFORMACIÓN DE SEGURO:\n- Compañía: ${_insCompanyCtrl.text.trim()}\n- Póliza: ${_insPolicyCtrl.text.trim()}\n- Vencimiento: ${_insExpiry != null ? "${_insExpiry!.day}/${_insExpiry!.month}/${_insExpiry!.year}" : "No especificado"}\n'
        : '\nINFORMACIÓN DE SEGURO: No proporcionada\n';

    return '''CONTRATO DE PUBLICACIÓN DE VEHÍCULO

NATURALEZA DE TORO:
TORO es únicamente una plataforma tecnológica que FACILITA la conexión entre propietarios de vehículos y usuarios. TORO NO es propietaria, operadora, ni arrendadora de vehículos. TORO NO es responsable de ningún daño, pérdida, accidente o incidente que ocurra con el vehículo.

INFORMACIÓN DEL VEHÍCULO:
- Marca/Modelo: ${_makeCtrl.text.trim()} ${_modelCtrl.text.trim()}
- Año: ${_yearCtrl.text.trim()}
- Placas: ${_plateCtrl.text.trim()}
- Color: ${_colorCtrl.text.trim().isNotEmpty ? _colorCtrl.text.trim() : "No especificado"}
$insuranceInfo
DECLARACIONES DEL PROPIETARIO:
1. CONDICIONES DEL VEHÍCULO: Declaro bajo protesta de decir verdad que el vehículo descrito está en perfectas condiciones operativas, mecánicas, eléctricas y de seguridad. Cuenta con todos los sistemas requeridos por ley (frenos, luces, neumáticos, etc.) en óptimas condiciones.

2. VERACIDAD DE LA INFORMACIÓN: Toda la información proporcionada (marca, modelo, año, placa, seguro, fotos, etc.) es VERIDICA y COMPLETA. Cualquier falsedad me hace responsable legal y económicamente.

3. AUTORIZACIÓN DE PUBLICACIÓN: Autorizo a TORO a publicar mi vehículo en la plataforma digital y usar las fotografías/información para fines de marketing y promoción.

RESPONSABILIDADES DEL PROPIETARIO:
4. SEGURO VIGENTE: Me comprometo a mantener un seguro de auto VIGENTE y ADECUADO que cubra daños a terceros, responsabilidad civil, robo total, y daños materiales. Es MI RESPONSABILIDAD exclusiva mantener este seguro activo.

5. MANTENIMIENTO: Soy el ÚNICO responsable del mantenimiento preventivo y correctivo del vehículo (aceite, frenos, neumáticos, afinaciones, etc.).

6. ACCIDENTES Y DAÑOS: En caso de accidente, colisión, volcadura, o cualquier daño durante el uso del vehículo por usuarios de TORO, yo (propietario) soy el ÚNICO responsable legal y económico. TORO queda exenta de toda responsabilidad.

7. USO INDEBIDO/ILEGAL: Si el vehículo es usado para actividades ilegales, tráfico de drogas, contrabando, o cualquier delito, yo (propietario) soy responsable y deslindo totalmente a TORO de cualquier consecuencia legal.

8. VANDALISMO Y ROBO: Cualquier acto de vandalismo, grafiti, robo, robo de partes, o destrucción intencional del vehículo es MI responsabilidad. TORO no se hace responsable de la seguridad del vehículo.

9. DESASTRES NATURALES: Daños causados por fenómenos naturales (tormentas, inundaciones, granizo, terremotos, huracanes, incendios forestales, rayos, etc.) son responsabilidad exclusiva del propietario y su aseguradora.

10. DEFECTOS OCULTOS: Cualquier defecto mecánico, eléctrico o estructural del vehículo (fallas de motor, transmisión, frenos, etc.) que cause daños o accidentes es responsabilidad exclusiva del propietario.

11. CHOFER ASIGNADO: El chofer asignado debe tener licencia vigente y experiencia comprobable. Soy responsable de verificar sus credenciales. Cualquier negligencia del chofer es mi responsabilidad.

COMISIONES Y PAGOS:
12. COMISIÓN DE PLATAFORMA: Acepto que TORO aplique una comisión/multiplicador sobre el precio base para cubrir costos operativos de la plataforma (tecnología, soporte, marketing, etc.).

SISTEMA DE TURISMO Y EVENTOS:
13. MANEJO DE PAGOS: Reconozco que TORO no maneja ni procesa pagos de pasajeros en el sistema de turismo. Soy responsable de coordinarme directamente con el organizador del evento para acordar tarifas, formas de pago y cualquier asunto financiero relacionado con el viaje.

14. COBRO POR KILOMETRAJE: Entiendo que TORO cobra una comisión basada en los kilómetros recorridos registrados en la aplicación durante eventos de turismo. Al aceptar este contrato, acepto la propuesta comercial de TORO y me comprometo a pagar dicha comisión según los términos establecidos en la plataforma.

15. COMUNICACIÓN CON ORGANIZADORES: Es mi responsabilidad mantener comunicación directa con los coordinadores u organizadores que publiquen eventos en mi vehículo. TORO solo facilita la conexión y el registro de kilometraje, pero no participa en negociaciones de precio ni cobros a pasajeros.

INDEMNIZACIÓN A TORO:
16. INDEMNIZACIÓN TOTAL: Me comprometo a indemnizar, defender y mantener libre de daño a TORO, sus accionistas, empleados, y socios de cualquier demanda, reclamo, pérdida, daño, lesión, muerte, o gasto (incluyendo honorarios legales) que surja del uso de mi vehículo en la plataforma.

DERECHO DE RETIRO:
17. RETIRO DEL VEHÍCULO: Puedo retirar mi vehículo de la plataforma en cualquier momento, siempre que NO tenga contratos o reservas activas pendientes.

JURISDICCIÓN Y LEY APLICABLE:
18. Este contrato se rige por las leyes de México. Cualquier disputa será resuelta en los tribunales competentes.

FIRMA DIGITAL:
Al marcar la casilla y presionar "Firmar y Publicar", acepto TODOS los términos anteriores. Esta firma digital tiene la misma validez legal que una firma manuscrita. Se registrará: mi email, ubicación GPS, fecha/hora exacta, y datos del chofer asignado.

⚠️ HE LEÍDO Y COMPRENDIDO TODOS LOS TÉRMINOS. ACEPTO TODA LA RESPONSABILIDAD.''';
  }

  // Step tracker
  // Autobus: 0=Vehicle+Driver, 1=Insurance, 2=Photos, 3=Contract
  // Others:  0=Vehicle, 1=Pricing+Photos, 2=Insurance+INE, 3=Contract
  int _currentStep = 0;

  // Vehicle info controllers
  final _makeCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _vinCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  String _vehicleType = 'sedan';

  // Pricing controllers (owner sets prices)
  final _weeklyPriceCtrl = TextEditingController();
  final _dailyPriceCtrl = TextEditingController();
  final _depositCtrl = TextEditingController();
  final _pickupAddressCtrl = TextEditingController();

  // Vehicle photos (all types)
  final List<XFile> _vehiclePhotos = [];
  final _imagePicker = ImagePicker();
  bool _isPickingPhotos = false;

  // Owner document (INE or License - required)
  XFile? _ownerDocument;
  String _ownerDocumentType = 'ine'; // 'ine' or 'licencia'
  bool _isPickingDocument = false;

  // Features checklist
  final List<String> _selectedFeatures = [];
  static const _availableFeatures = [
    'Aire Acondicionado', 'Bluetooth', 'GPS', 'Camara Reversa',
    'Asientos de Piel', 'Techo Solar', 'USB/AUX', 'Transmision Automatica',
    'CarPlay/Android Auto', 'Sensores de Estacionamiento',
  ];

  // Autobus: assigned driver
  final _driverEmailCtrl = TextEditingController();
  String? _assignedDriverId;
  String? _assignedDriverName;
  bool _driverVerified = false;
  bool _verifyingDriver = false;

  // Autobus: vehicle details (public info)
  final _totalSeatsCtrl = TextEditingController();
  final _unitNumberCtrl = TextEditingController(); // Fleet unit number
  final _ownerNameCtrl = TextEditingController();
  final _ownerPhoneCtrl = TextEditingController();

  // Autobus: Photos only (Step 2 for autobus only) - kept for backwards compat
  List<XFile> get _busPhotos => _vehiclePhotos;

  // Insurance controllers
  final _insCompanyCtrl = TextEditingController();
  final _insPolicyCtrl = TextEditingController();
  DateTime? _insExpiry;

  // Contract signing
  bool _agreedToTerms = false;
  bool _isSubmitting = false;
  String? _error;

  final _vehicleTypes = ['sedan', 'SUV', 'van', 'truck', 'autobus'];

  @override
  void initState() {
    super.initState();
    // Auto-fill owner info from logged-in driver's profile for NEW listings
    if (widget.existingVehicle == null) {
      _loadOwnerProfile();
    }
    // Pre-fill form if editing existing vehicle
    if (widget.existingVehicle != null) {
      final vehicle = widget.existingVehicle!;
      final source = vehicle['_source'] ?? 'bus';
      final isRental = source == 'rental';

      _vehicleType = vehicle['vehicle_type'] ?? 'autobus';

      if (isRental) {
        // Rental vehicle field names
        _makeCtrl.text = vehicle['vehicle_make'] ?? '';
        _modelCtrl.text = vehicle['vehicle_model'] ?? '';
        _yearCtrl.text = vehicle['vehicle_year']?.toString() ?? '';
        _colorCtrl.text = vehicle['vehicle_color'] ?? '';
        _plateCtrl.text = vehicle['vehicle_plate'] ?? '';
        _vinCtrl.text = vehicle['vehicle_vin'] ?? '';
        _descriptionCtrl.text = vehicle['description'] ?? '';
        _weeklyPriceCtrl.text = (vehicle['weekly_price_base'] ?? '').toString();
        _dailyPriceCtrl.text = (vehicle['daily_price'] ?? '').toString();
        _depositCtrl.text = (vehicle['deposit_amount'] ?? '').toString();
        _pickupAddressCtrl.text = vehicle['pickup_address'] ?? '';
        _ownerNameCtrl.text = vehicle['owner_name'] ?? '';
        _ownerPhoneCtrl.text = vehicle['owner_phone'] ?? '';
        _ownerDocumentType = vehicle['owner_document_type'] ?? 'ine';
        if (vehicle['features'] != null) {
          _selectedFeatures.addAll(List<String>.from(vehicle['features']));
        }
      } else {
        // Bus vehicle field names
        _makeCtrl.text = vehicle['make'] ?? '';
        _modelCtrl.text = vehicle['model'] ?? '';
        _yearCtrl.text = vehicle['year']?.toString() ?? '';
        _colorCtrl.text = vehicle['color'] ?? '';
        _plateCtrl.text = vehicle['plate'] ?? '';
      }

      // Insurance fields (shared)
      _insCompanyCtrl.text = vehicle['insurance_company'] ?? '';
      _insPolicyCtrl.text = vehicle['insurance_policy_number'] ?? '';
      if (vehicle['insurance_expiry'] != null) {
        try {
          _insExpiry = DateTime.parse(vehicle['insurance_expiry']);
        } catch (_) {}
      }

      // Autobus specific fields
      if (_vehicleType == 'autobus') {
        _totalSeatsCtrl.text = vehicle['total_seats']?.toString() ?? '';
        _unitNumberCtrl.text = vehicle['unit_number'] ?? '';
        _ownerNameCtrl.text = vehicle['owner_name'] ?? '';
        _ownerPhoneCtrl.text = vehicle['owner_phone'] ?? '';
        _loadDriverInfo(vehicle['owner_id']);
      }
    }
  }

  /// Auto-fill owner name/phone/email from the logged-in driver's profile
  Future<void> _loadOwnerProfile() async {
    try {
      final result = await SupabaseConfig.client
          .from('drivers')
          .select('name, phone, email')
          .eq('id', widget.userId)
          .single();

      if (mounted) {
        setState(() {
          if (_ownerNameCtrl.text.isEmpty) {
            _ownerNameCtrl.text = result['name'] ?? '';
          }
          if (_ownerPhoneCtrl.text.isEmpty) {
            _ownerPhoneCtrl.text = result['phone'] ?? '';
          }
        });
      }
    } catch (e) {
      // Non-critical - user can type manually
    }
  }

  // Load driver info when editing (pre-fill chofer fields)
  Future<void> _loadDriverInfo(String? driverId) async {
    if (driverId == null) return;

    try {
      final result = await SupabaseConfig.client
          .from('drivers')
          .select('id, name, email, is_verified')
          .eq('id', driverId)
          .single();

      if (mounted) {
        setState(() {
          _assignedDriverId = result['id'];
          _assignedDriverName = result['name'];
          _driverEmailCtrl.text = result['email'] ?? '';
          _driverVerified = result['is_verified'] == true;
        });
      }
    } catch (e) {
      AppLogger.log('Error loading driver info: $e');
      // Non-critical error, just continue
    }
  }

  @override
  void dispose() {
    _makeCtrl.dispose();
    _modelCtrl.dispose();
    _yearCtrl.dispose();
    _colorCtrl.dispose();
    _plateCtrl.dispose();
    _vinCtrl.dispose();
    _driverEmailCtrl.dispose();
    _totalSeatsCtrl.dispose();
    _unitNumberCtrl.dispose();
    _ownerNameCtrl.dispose();
    _ownerPhoneCtrl.dispose();
    _insCompanyCtrl.dispose();
    _insPolicyCtrl.dispose();
    super.dispose();
  }

  String? _validateStep(int step) {
    if (_vehicleType == 'autobus') {
      // Autobus: 0=Vehicle+Driver, 1=Insurance, 2=Photos, 3=Contract
      switch (step) {
        case 0:
          if (_makeCtrl.text.trim().isEmpty) return 'Ingresa la marca';
          if (_modelCtrl.text.trim().isEmpty) return 'Ingresa el modelo';
          if (_yearCtrl.text.trim().isEmpty) return 'Ingresa el año';
          final year = int.tryParse(_yearCtrl.text.trim());
          if (year == null || year < 1990 || year > 2030) return 'Año invalido';
          if (_plateCtrl.text.trim().isEmpty) return 'Ingresa la placa';
          if (!_driverVerified) return 'Autobus requiere un chofer aprobado por Toro';
          // Validate total seats (required)
          if (_totalSeatsCtrl.text.trim().isEmpty) return 'Ingresa el total de asientos';
          final totalSeats = int.tryParse(_totalSeatsCtrl.text.trim());
          if (totalSeats == null || totalSeats < 1 || totalSeats > 100) return 'Total de asientos invalido (1-100)';
          return null;
        case 1:
          // Insurance is optional but if company is entered, policy is required
          if (_insCompanyCtrl.text.trim().isNotEmpty && _insPolicyCtrl.text.trim().isEmpty) {
            return 'Ingresa el numero de poliza';
          }
          return null;
        case 2:
          // Photos (minimum 1)
          if (_busPhotos.isEmpty) return 'Debes tomar al menos 1 foto del autobus';
          return null;
        case 3:
          // Contract
          if (!_agreedToTerms) return 'Debes aceptar los terminos del contrato';
          return null;
        default:
          return null;
      }
    } else {
      // Others: 0=Vehicle, 1=Photos+Pricing, 2=Insurance+INE, 3=Contract
      switch (step) {
        case 0:
          if (_makeCtrl.text.trim().isEmpty) return 'Ingresa la marca';
          if (_modelCtrl.text.trim().isEmpty) return 'Ingresa el modelo';
          if (_yearCtrl.text.trim().isEmpty) return 'Ingresa el año';
          final year = int.tryParse(_yearCtrl.text.trim());
          if (year == null || year < 1990 || year > 2030) return 'Año invalido';
          if (_plateCtrl.text.trim().isEmpty) return 'Ingresa la placa';
          return null;
        case 1:
          // Photos & Pricing - at least weekly price required
          if (_weeklyPriceCtrl.text.trim().isEmpty) return 'Ingresa el precio por semana';
          final weekly = double.tryParse(_weeklyPriceCtrl.text.trim());
          if (weekly == null || weekly <= 0) return 'Precio semanal invalido';
          return null;
        case 2:
          // Insurance + INE - INE/license is required
          if (_ownerDocument == null) return 'Debes subir tu INE o licencia';
          if (_insCompanyCtrl.text.trim().isNotEmpty && _insPolicyCtrl.text.trim().isEmpty) {
            return 'Ingresa el numero de poliza';
          }
          return null;
        case 3:
          // Contract
          if (!_agreedToTerms) return 'Debes aceptar los terminos del contrato';
          return null;
        default:
          return null;
      }
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

  Future<void> _pickBusPhotos({required bool useCamera}) async {
    if (_isPickingPhotos) return; // Prevent multiple calls

    setState(() => _isPickingPhotos = true);

    try {
      if (useCamera) {
        // Take photo with camera
        final XFile? photo = await _imagePicker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1920,
          maxHeight: 1080,
          imageQuality: 85,
          preferredCameraDevice: CameraDevice.rear,
        );

        if (photo != null && mounted) {
          setState(() {
            _busPhotos.add(photo);
            if (_busPhotos.length > 10) {
              _busPhotos.removeAt(0); // Remove oldest if over 10
            }
          });
          HapticService.lightImpact();
        }
      } else {
        // Pick from gallery
        final List<XFile> pickedFiles = await _imagePicker.pickMultiImage(
          maxWidth: 1920,
          maxHeight: 1080,
          imageQuality: 85,
        );

        if (pickedFiles.isNotEmpty && mounted) {
          setState(() {
            _busPhotos.addAll(pickedFiles);
            if (_busPhotos.length > 10) {
              _busPhotos.removeRange(10, _busPhotos.length); // Max 10 photos
            }
          });
          HapticService.lightImpact();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = useCamera ? 'Error tomando foto: $e' : 'Error seleccionando fotos: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isPickingPhotos = false);
      }
    }
  }

  void _removeBusPhoto(int index) {
    setState(() {
      _busPhotos.removeAt(index);
    });
    HapticService.lightImpact();
  }

  void _moveBusPhotoUp(int index) {
    if (index == 0) return; // Already first
    setState(() {
      final photo = _busPhotos.removeAt(index);
      _busPhotos.insert(index - 1, photo);
    });
    HapticService.lightImpact();
  }

  void _moveBusPhotoDown(int index) {
    if (index == _busPhotos.length - 1) return; // Already last
    setState(() {
      final photo = _busPhotos.removeAt(index);
      _busPhotos.insert(index + 1, photo);
    });
    HapticService.lightImpact();
  }

  Future<List<String>> _uploadBusPhotos() async {
    final List<String> photoUrls = [];
    try {
      for (final photo in _busPhotos) {
        final bytes = await photo.readAsBytes();
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_${photo.name}';
        final path = '${widget.userId}/bus_photos/$fileName';

        await SupabaseConfig.client.storage
            .from('vehicle-documents')
            .uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true));

        final url = SupabaseConfig.client.storage.from('vehicle-documents').getPublicUrl(path);
        photoUrls.add(url);
      }
    } catch (e) {
      // Log upload error
      AppLogger.log('ERROR subiendo fotos del autobus: $e');
      rethrow; // Re-throw to show error to user
    }
    return photoUrls;
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

      // If autobus: ONLY insert into bus_vehicles (tourism system)
      if (_vehicleType == 'autobus') {
        // Upload bus photos first
        final photoUrls = await _uploadBusPhotos();

        final busData = <String, dynamic>{
          'vehicle_name': '${_makeCtrl.text.trim()} ${_modelCtrl.text.trim()} ${_yearCtrl.text.trim()}',
          'make': _makeCtrl.text.trim(),
          'model': _modelCtrl.text.trim(),
          'year': int.parse(_yearCtrl.text.trim()),
          'plate': _plateCtrl.text.trim(),
          'color': _colorCtrl.text.trim().isNotEmpty ? _colorCtrl.text.trim() : null,
          // Public information (optional for privacy)
          'total_seats': int.parse(_totalSeatsCtrl.text.trim()),
          'unit_number': _unitNumberCtrl.text.trim().isNotEmpty ? _unitNumberCtrl.text.trim() : null,
          'owner_name': _ownerNameCtrl.text.trim().isNotEmpty ? _ownerNameCtrl.text.trim() : null,
          'owner_phone': _ownerPhoneCtrl.text.trim().isNotEmpty ? _ownerPhoneCtrl.text.trim() : null,
          // Insurance information
          'insurance_company': _insCompanyCtrl.text.trim().isNotEmpty ? _insCompanyCtrl.text.trim() : null,
          'insurance_policy_number': _insPolicyCtrl.text.trim().isNotEmpty ? _insPolicyCtrl.text.trim() : null,
          'insurance_expiry': _insExpiry?.toIso8601String().substring(0, 10),
          'updated_at': DateTime.now().toIso8601String(),
        };

        // Only update image_urls if new photos were uploaded
        if (photoUrls.isNotEmpty) {
          busData['image_urls'] = photoUrls;
        }

        // If editing, update; otherwise, insert
        if (widget.existingVehicle != null) {
          // UPDATE existing vehicle
          await SupabaseConfig.client
              .from('bus_vehicles')
              .update(busData)
              .eq('id', widget.existingVehicle!['id']);
        } else {
          // INSERT new vehicle (only for new vehicles)
          busData['owner_id'] = _assignedDriverId ?? widget.userId;
          busData['vehicle_type'] = 'autobus';
          busData['amenities'] = <String>[];
          busData['image_urls'] = photoUrls;
          busData['is_active'] = true;
          busData['country_code'] = 'MX';
          busData['available_for_tourism'] = true;
          // Contract signing info
          busData['owner_signed_at'] = DateTime.now().toIso8601String();
          busData['owner_sign_lat'] = signPos?.latitude;
          busData['owner_sign_lng'] = signPos?.longitude;
          busData['owner_sign_email'] = widget.userId;
          busData['assigned_driver_email'] = _driverEmailCtrl.text.trim();
          busData['contract_text'] = _contractText;
          busData['created_at'] = DateTime.now().toIso8601String();

          await SupabaseConfig.client.from('bus_vehicles').insert(busData);
        }
      } else {
        // Other vehicles: insert into rental_vehicle_listings with photos + INE + pricing
        // Upload vehicle photos
        final photoUrls = <String>[];
        for (final photo in _vehiclePhotos) {
          try {
            final ext = photo.path.split('.').last.toLowerCase();
            final fileName = '${DateTime.now().millisecondsSinceEpoch}_${photo.name}';
            final path = '${widget.userId}/vehicles/$fileName';
            if (kIsWeb) {
              final bytes = await photo.readAsBytes();
              await SupabaseConfig.client.storage.from('rental-media').uploadBinary(path, bytes, fileOptions: FileOptions(contentType: 'image/$ext', upsert: true));
            } else {
              await SupabaseConfig.client.storage.from('rental-media').upload(path, File(photo.path), fileOptions: FileOptions(contentType: 'image/$ext', upsert: true));
            }
            final url = SupabaseConfig.client.storage.from('rental-media').getPublicUrl(path);
            photoUrls.add(url);
          } catch (e) {
            debugPrint('Error uploading photo: $e');
          }
        }

        // Upload owner document (INE/License)
        String? documentUrl;
        if (_ownerDocument != null) {
          try {
            final ext = _ownerDocument!.path.split('.').last.toLowerCase();
            final fileName = '${DateTime.now().millisecondsSinceEpoch}_document.$ext';
            final path = '${widget.userId}/documents/$fileName';
            if (kIsWeb) {
              final bytes = await _ownerDocument!.readAsBytes();
              await SupabaseConfig.client.storage.from('rental-media').uploadBinary(path, bytes, fileOptions: FileOptions(contentType: 'image/$ext', upsert: true));
            } else {
              await SupabaseConfig.client.storage.from('rental-media').upload(path, File(_ownerDocument!.path), fileOptions: FileOptions(contentType: 'image/$ext', upsert: true));
            }
            documentUrl = SupabaseConfig.client.storage.from('rental-media').getPublicUrl(path);
          } catch (e) {
            debugPrint('Error uploading document: $e');
          }
        }

        final make = _makeCtrl.text.trim();
        final model = _modelCtrl.text.trim();
        final year = _yearCtrl.text.trim();

        final data = <String, dynamic>{
          'owner_id': widget.userId,
          'vehicle_type': _vehicleType,
          'vehicle_make': make,
          'vehicle_model': model,
          'vehicle_year': int.parse(year),
          'vehicle_color': _colorCtrl.text.trim().isNotEmpty ? _colorCtrl.text.trim() : null,
          'vehicle_plate': _plateCtrl.text.trim(),
          'vehicle_vin': _vinCtrl.text.trim().isNotEmpty ? _vinCtrl.text.trim() : null,
          'title': '$make $model $year',
          'description': _descriptionCtrl.text.trim().isNotEmpty ? _descriptionCtrl.text.trim() : null,
          // Photos
          'image_urls': photoUrls,
          // Owner document
          'owner_document_url': documentUrl,
          'owner_document_type': _ownerDocumentType,
          // Pricing (owner sets prices)
          'weekly_price_base': double.tryParse(_weeklyPriceCtrl.text.trim()) ?? 0,
          'daily_price': double.tryParse(_dailyPriceCtrl.text.trim()) ?? 0,
          'deposit_amount': double.tryParse(_depositCtrl.text.trim()) ?? 0,
          // Features
          'features': _selectedFeatures,
          // Pickup location
          'pickup_address': _pickupAddressCtrl.text.trim().isNotEmpty ? _pickupAddressCtrl.text.trim() : null,
          // Owner contact
          'owner_name': _ownerNameCtrl.text.trim().isNotEmpty ? _ownerNameCtrl.text.trim() : null,
          'owner_phone': _ownerPhoneCtrl.text.trim().isNotEmpty ? _ownerPhoneCtrl.text.trim() : null,
          // Insurance
          'insurance_company': _insCompanyCtrl.text.trim().isNotEmpty ? _insCompanyCtrl.text.trim() : null,
          'insurance_policy_number': _insPolicyCtrl.text.trim().isNotEmpty ? _insPolicyCtrl.text.trim() : null,
          'insurance_expiry': _insExpiry?.toIso8601String().substring(0, 10),
          // Contract signing
          'owner_signed_at': DateTime.now().toIso8601String(),
          'owner_sign_lat': signPos?.latitude,
          'owner_sign_lng': signPos?.longitude,
          'status': 'active',
          'currency': 'MXN',
        };

        final isEditing = widget.existingVehicle != null && (widget.existingVehicle!['_source'] == 'rental');
        if (isEditing) {
          // Keep existing photos if no new ones uploaded
          if (photoUrls.isEmpty) {
            data.remove('image_urls');
          }
          if (documentUrl == null) {
            data.remove('owner_document_url');
          }
          data.remove('owner_id'); // Cannot change owner
          data['updated_at'] = DateTime.now().toIso8601String();
          await SupabaseConfig.client
              .from('rental_vehicle_listings')
              .update(data)
              .eq('id', widget.existingVehicle!['id']);
        } else {
          await SupabaseConfig.client.from('rental_vehicle_listings').insert(data);
        }
      }

      if (mounted) {
        Navigator.of(context).pop(true); // true = refresh
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_vehicleType == 'autobus'
              ? 'Autobus publicado exitosamente para turismo'
              : 'Vehiculo publicado exitosamente'),
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

  bool _isLastStep() {
    return _vehicleType == 'autobus' ? _currentStep == 3 : _currentStep == 3;
  }

  @override
  Widget build(BuildContext context) {
    final stepTitles = _vehicleType == 'autobus'
        ? ['Vehiculo', 'Seguro', 'Fotos', 'Contrato']
        : ['Vehiculo', 'Fotos y Precio', 'Seguro e ID', 'Contrato'];
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: AppColors.textTertiary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            const Icon(Icons.directions_car_rounded, color: _accent, size: 24),
            const SizedBox(width: 12),
            Text('Publicar Vehiculo', style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(color: AppColors.border.withValues(alpha: 0.5), height: 1),
        ),
      ),
      body: Column(
        children: [
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
                      onPressed: _isSubmitting ? null : (_isLastStep() ? _submitListing : _nextStep),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isLastStep() ? AppColors.success : _accent,
                        disabledBackgroundColor: _accent.withValues(alpha: 0.3),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                          : Text(
                              _isLastStep() ? 'Firmar y Publicar' : 'Siguiente',
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
    // Autobus: 0=Vehicle+Driver, 1=Insurance, 2=Photos, 3=Contract
    // Others:  0=Vehicle, 1=Photos+Pricing, 2=Insurance+INE, 3=Contract

    if (_vehicleType == 'autobus') {
      switch (_currentStep) {
        case 0: return _buildVehicleStep();
        case 1: return _buildInsuranceStep();
        case 2: return _buildPhotosStep();
        case 3: return _buildContractStep();
        default: return const SizedBox.shrink();
      }
    } else {
      switch (_currentStep) {
        case 0: return _buildVehicleStep();
        case 1: return _buildPhotosPricingStep();
        case 2: return _buildInsuranceDocumentStep();
        case 3: return _buildContractStep();
        default: return const SizedBox.shrink();
      }
    }
  }

  // ── Step 1 (non-autobus): Photos + Pricing ──
  Widget _buildPhotosPricingStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // PHOTOS SECTION
        _sectionLabel('Fotos del Vehiculo'),
        const SizedBox(height: 4),
        Text('Agrega fotos claras de tu vehiculo (minimo 3)', style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
        const SizedBox(height: 12),
        // Photo grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemCount: _vehiclePhotos.length + 1,
          itemBuilder: (ctx, i) {
            if (i == _vehiclePhotos.length) {
              // Add photo button
              return GestureDetector(
                onTap: _isPickingPhotos ? null : _pickVehiclePhotos,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.cardSecondary,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _accent.withValues(alpha: 0.3), style: BorderStyle.solid),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_isPickingPhotos ? Icons.hourglass_top_rounded : Icons.add_a_photo_rounded, color: _accent, size: 28),
                      const SizedBox(height: 6),
                      Text(_isPickingPhotos ? 'Cargando...' : 'Agregar', style: TextStyle(color: _accent, fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              );
            }
            // Photo thumbnail
            return Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: kIsWeb
                      ? Image.network(_vehiclePhotos[i].path, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
                      : Image.file(File(_vehiclePhotos[i].path), fit: BoxFit.cover, width: double.infinity, height: double.infinity),
                ),
                Positioned(
                  top: 4, right: 4,
                  child: GestureDetector(
                    onTap: () => setState(() => _vehiclePhotos.removeAt(i)),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
                    ),
                  ),
                ),
                if (i == 0)
                  Positioned(
                    bottom: 4, left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(4)),
                      child: const Text('Principal', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                    ),
                  ),
              ],
            );
          },
        ),

        // DESCRIPTION
        const SizedBox(height: 24),
        _sectionLabel('Descripcion (opcional)'),
        const SizedBox(height: 8),
        _field(_descriptionCtrl, 'Describe tu vehiculo...', 'Vehiculo en excelente estado, bien cuidado...', maxLines: 3),

        // FEATURES
        const SizedBox(height: 24),
        _sectionLabel('Caracteristicas'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: _availableFeatures.map((f) {
            final sel = _selectedFeatures.contains(f);
            return GestureDetector(
              onTap: () {
                HapticService.lightImpact();
                setState(() {
                  if (sel) { _selectedFeatures.remove(f); } else { _selectedFeatures.add(f); }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? _accent.withValues(alpha: 0.15) : AppColors.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: sel ? _accent.withValues(alpha: 0.5) : AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(sel ? Icons.check_circle_rounded : Icons.circle_outlined, color: sel ? _accent : AppColors.textDisabled, size: 16),
                    const SizedBox(width: 6),
                    Text(f, style: TextStyle(color: sel ? _accent : AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),

        // PRICING
        const SizedBox(height: 24),
        _sectionLabel('Precios (tu defines los precios)'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _field(_dailyPriceCtrl, 'Precio/Dia', '500', isNumber: true, prefix: '\$')),
            const SizedBox(width: 12),
            Expanded(child: _field(_weeklyPriceCtrl, 'Precio/Semana', '2500', isNumber: true, prefix: '\$')),
          ],
        ),
        const SizedBox(height: 12),
        _field(_depositCtrl, 'Deposito (opcional)', '5000', isNumber: true, prefix: '\$'),
        const SizedBox(height: 12),
        _field(_pickupAddressCtrl, 'Direccion de Entrega', 'Av. Reforma 123, CDMX'),
      ],
    );
  }

  Future<void> _pickVehiclePhotos() async {
    setState(() => _isPickingPhotos = true);
    try {
      final picked = await _imagePicker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (picked.isNotEmpty && mounted) {
        setState(() => _vehiclePhotos.addAll(picked));
      }
    } catch (e) {
      debugPrint('Error picking photos: $e');
    }
    if (mounted) setState(() => _isPickingPhotos = false);
  }

  // ── Step 2 (non-autobus): Insurance + INE/License ──
  Widget _buildInsuranceDocumentStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Insurance section (same as existing)
        _sectionLabel('Seguro del Vehiculo'),
        const SizedBox(height: 12),
        _field(_insCompanyCtrl, 'Compania de Seguro', 'GNP, Qualitas, AXA...'),
        const SizedBox(height: 12),
        _field(_insPolicyCtrl, 'Numero de Poliza', 'POL-123456'),
        const SizedBox(height: 12),
        // Expiry date picker
        GestureDetector(
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _insExpiry ?? DateTime.now().add(const Duration(days: 180)),
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
              builder: (ctx, child) => Theme(
                data: Theme.of(ctx).copyWith(colorScheme: ColorScheme.dark(primary: _accent, surface: AppColors.card)),
                child: child!,
              ),
            );
            if (d != null) setState(() => _insExpiry = d);
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
                Icon(Icons.calendar_today_rounded, color: AppColors.textTertiary, size: 18),
                const SizedBox(width: 12),
                Text(
                  _insExpiry != null
                      ? '${_insExpiry!.day}/${_insExpiry!.month}/${_insExpiry!.year}'
                      : 'Fecha de Vencimiento del Seguro',
                  style: TextStyle(
                    color: _insExpiry != null ? AppColors.textPrimary : AppColors.textDisabled,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),

        // OWNER DOCUMENT SECTION (INE or License - Required)
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.badge_rounded, color: const Color(0xFFEF4444), size: 20),
                  const SizedBox(width: 8),
                  Text('Identificacion Oficial (Obligatorio)', style: TextStyle(color: const Color(0xFFEF4444), fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Sube una foto de tu INE o Licencia de Conducir. Es requerido para verificar tu identidad como propietario.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 12),
              // Document type selector
              Row(
                children: [
                  _docTypeChip('INE', 'ine'),
                  const SizedBox(width: 8),
                  _docTypeChip('Licencia', 'licencia'),
                ],
              ),
              const SizedBox(height: 12),
              // Upload button / preview
              GestureDetector(
                onTap: _isPickingDocument ? null : _pickOwnerDocument,
                child: Container(
                  height: 120,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _ownerDocument != null ? AppColors.success.withValues(alpha: 0.5) : AppColors.border,
                      width: _ownerDocument != null ? 2 : 1,
                    ),
                  ),
                  child: _ownerDocument != null
                      ? Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(11),
                              child: kIsWeb
                                  ? Image.network(_ownerDocument!.path, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
                                  : Image.file(File(_ownerDocument!.path), fit: BoxFit.cover, width: double.infinity, height: double.infinity),
                            ),
                            Positioned(
                              top: 8, right: 8,
                              child: GestureDetector(
                                onTap: () => setState(() => _ownerDocument = null),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
                                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 8, left: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: AppColors.success, borderRadius: BorderRadius.circular(6)),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.check_circle_rounded, color: Colors.white, size: 14),
                                    const SizedBox(width: 4),
                                    Text(_ownerDocumentType == 'ine' ? 'INE' : 'Licencia', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_isPickingDocument ? Icons.hourglass_top_rounded : Icons.add_photo_alternate_rounded,
                                color: _accent, size: 36),
                            const SizedBox(height: 8),
                            Text(
                              _isPickingDocument ? 'Cargando...' : 'Tomar foto o seleccionar',
                              style: TextStyle(color: _accent, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),

        // Owner contact info
        const SizedBox(height: 24),
        _sectionLabel('Informacion de Contacto'),
        const SizedBox(height: 12),
        _field(_ownerNameCtrl, 'Nombre Completo', 'Juan Perez'),
        const SizedBox(height: 12),
        _field(_ownerPhoneCtrl, 'Telefono', '+52 55 1234 5678'),
      ],
    );
  }

  Widget _docTypeChip(String label, String type) {
    final sel = _ownerDocumentType == type;
    return GestureDetector(
      onTap: () { HapticService.lightImpact(); setState(() => _ownerDocumentType = type); },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? _accent.withValues(alpha: 0.15) : AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: sel ? _accent.withValues(alpha: 0.5) : AppColors.border),
        ),
        child: Text(label, style: TextStyle(color: sel ? _accent : AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Future<void> _pickOwnerDocument() async {
    setState(() => _isPickingDocument = true);
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 90,
      );
      if (picked != null && mounted) {
        setState(() => _ownerDocument = picked);
      }
    } catch (e) {
      debugPrint('Error picking document: $e');
    }
    if (mounted) setState(() => _isPickingDocument = false);
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
                child: Text(
                  t == 'autobus' ? 'TRANSPORTE\nTURISMO' : t.toUpperCase(),
                  style: TextStyle(color: sel ? _accent : AppColors.textSecondary, fontSize: t == 'autobus' ? 12 : 13, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
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
          // ── Autobus: Public information (optional for privacy) ──
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    const Text('Información Pública', style: TextStyle(color: AppColors.primary, fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Esta información se mostrará públicamente a otros organizadores. Déjala vacía si prefieres privacidad.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 16),
                // Total seats (required)
                _field(_totalSeatsCtrl, 'Total de Asientos *', '30', isNumber: true),
                const SizedBox(height: 12),
                // Unit number (optional - for fleet management)
                _field(_unitNumberCtrl, 'Número de Unidad (opcional)', 'Unidad 1'),
                const SizedBox(height: 12),
                // Owner name (optional)
                _field(_ownerNameCtrl, 'Nombre del Dueño (opcional)', 'Juan Pérez'),
                const SizedBox(height: 12),
                // Owner phone (optional)
                _field(_ownerPhoneCtrl, 'Teléfono del Dueño (opcional)', '686-123-4567'),
                const SizedBox(height: 8),
                Text(
                  '💡 Los campos opcionales se pueden dejar vacíos para mantener tu privacidad.',
                  style: TextStyle(color: AppColors.textTertiary, fontSize: 11, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── Step 2: Photos (only for autobus) ──
  Widget _buildPhotosStep() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Fotos del Autobus *'),
          const SizedBox(height: 4),
          Text(
            'Minimo 1 foto (obligatorio), maximo 10. La primera foto sera la principal publicada.',
            style: TextStyle(color: AppColors.textDisabled, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            '⚠️ Las fotos seran publicas y visibles para los turistas. Puedes reordenarlas.',
            style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),

          // Photo grid
          if (_busPhotos.isEmpty)
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _pickBusPhotos(useCamera: true),
                    child: Container(
                      height: 100,
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border, style: BorderStyle.solid),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.camera_alt, color: _accent, size: 32),
                          const SizedBox(height: 6),
                          Text('Tomar Foto', style: TextStyle(color: _accent, fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _pickBusPhotos(useCamera: false),
                    child: Container(
                      height: 100,
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border, style: BorderStyle.solid),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.photo_library, color: _accent, size: 32),
                          const SizedBox(height: 6),
                          Text('Galería', style: TextStyle(color: _accent, fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            )
          else
            Column(
              children: [
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1,
                  ),
                  itemCount: _busPhotos.length + (_busPhotos.length < 10 ? 1 : 0),
                  itemBuilder: (ctx, index) {
                    if (index == _busPhotos.length) {
                      // Add photo button - shows menu to choose camera or gallery
                      return GestureDetector(
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            builder: (ctx) => Container(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading: Icon(Icons.camera_alt, color: _accent),
                                    title: const Text('Tomar Foto'),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _pickBusPhotos(useCamera: true);
                                    },
                                  ),
                                  ListTile(
                                    leading: Icon(Icons.photo_library, color: _accent),
                                    title: const Text('Seleccionar de Galería'),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _pickBusPhotos(useCamera: false);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add, color: _accent, size: 24),
                              const SizedBox(height: 4),
                              Text('Agregar', style: TextStyle(color: _accent, fontSize: 11)),
                            ],
                          ),
                        ),
                      );
                    }

                    // Photo thumbnail
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(_busPhotos[index].path),
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                          ),
                        ),
                        // Position number badge (1 = main photo)
                        Positioned(
                          top: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: index == 0 ? Colors.green : Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        // Delete button
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => _removeBusPhoto(index),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.8),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, color: Colors.white, size: 14),
                            ),
                          ),
                        ),
                        // Reorder buttons (bottom)
                        Positioned(
                          bottom: 4,
                          left: 4,
                          right: 4,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (index > 0)
                                GestureDetector(
                                  onTap: () => _moveBusPhotoUp(index),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.7),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Icon(Icons.arrow_back, color: Colors.white, size: 14),
                                  ),
                                ),
                              if (index > 0 && index < _busPhotos.length - 1) const SizedBox(width: 4),
                              if (index < _busPhotos.length - 1)
                                GestureDetector(
                                  onTap: () => _moveBusPhotoDown(index),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.7),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Icon(Icons.arrow_forward, color: Colors.white, size: 14),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  '${_busPhotos.length}/10 fotos (minimo 1)',
                  style: TextStyle(
                    color: _busPhotos.isNotEmpty ? const Color(0xFF22C55E) : const Color(0xFFEAB308),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ── Step 1 (autobus) / Step 1 (others): Insurance ──
  Widget _buildInsuranceStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Seguro del Vehiculo'),
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

  // ── Step 3 (autobus) / Step 2 (others): Contract ──
  Widget _buildContractStep() {
    final make = _makeCtrl.text.trim();
    final model = _modelCtrl.text.trim();
    final year = _yearCtrl.text.trim();
    final plate = _plateCtrl.text.trim();

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
              _summaryRow('Tipo', _vehicleType == 'autobus' ? 'TRANSPORTE TURISMO' : _vehicleType.toUpperCase()),
              _summaryRow('Vehiculo', '$year $make $model'),
              _summaryRow('Placa', plate),
              if (_colorCtrl.text.trim().isNotEmpty) _summaryRow('Color', _colorCtrl.text.trim()),
              if (_vinCtrl.text.trim().isNotEmpty) _summaryRow('VIN', _vinCtrl.text.trim()),
              if (_insCompanyCtrl.text.trim().isNotEmpty) _summaryRow('Seguro', _insCompanyCtrl.text.trim()),
              if (_vehicleType == 'autobus') _summaryRow('Fotos', '${_busPhotos.length} fotos'),
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
            _contractText,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
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

  Widget _field(TextEditingController ctrl, String label, String hint, {bool isNumber = false, String? prefix, int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
      maxLines: maxLines,
      style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textDisabled),
        prefixText: prefix,
        prefixStyle: TextStyle(color: AppColors.textSecondary, fontSize: 15, fontWeight: FontWeight.w600),
        filled: true, fillColor: AppColors.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _accent, width: 1.5)),
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
                            separatorBuilder: (_, _) => const SizedBox(height: 12),
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
                            separatorBuilder: (_, _) => const SizedBox(height: 14),
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
// Add this to the end of home_screen.dart (before the last closing brace)

// ═══════════════════════════════════════════════════════════════════════════
// MY VEHICLES SHEET - View/Edit/Delete published vehicles
// ═══════════════════════════════════════════════════════════════════════════

class _MyVehiclesSheet extends StatefulWidget {
  final String userId;

  const _MyVehiclesSheet({required this.userId});

  @override
  State<_MyVehiclesSheet> createState() => _MyVehiclesSheetState();
}

class _MyVehiclesSheetState extends State<_MyVehiclesSheet> {
  List<Map<String, dynamic>> _vehicles = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
  }

  Future<void> _loadVehicles() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load bus_vehicles
      final busVehicles = await SupabaseConfig.client
          .from('bus_vehicles')
          .select()
          .eq('owner_id', widget.userId)
          .order('created_at', ascending: false);

      // Load rental_vehicle_listings
      final rentalVehicles = await SupabaseConfig.client
          .from('rental_vehicle_listings')
          .select()
          .eq('owner_id', widget.userId)
          .neq('status', 'deleted')
          .order('created_at', ascending: false);

      // Merge both lists, tag source
      final all = <Map<String, dynamic>>[];
      for (final v in busVehicles) {
        all.add({...Map<String, dynamic>.from(v), '_source': 'bus'});
      }
      for (final v in rentalVehicles) {
        all.add({...Map<String, dynamic>.from(v), '_source': 'rental'});
      }

      setState(() {
        _vehicles = all;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error al cargar vehiculos: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteVehicle(String vehicleId, String vehicleName, {String source = 'bus'}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Vehiculo'),
        content: Text('¿Estas seguro de eliminar "$vehicleName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      if (source == 'rental') {
        // Soft-delete rental listings
        await SupabaseConfig.client
            .from('rental_vehicle_listings')
            .update({'status': 'deleted'})
            .eq('id', vehicleId);
      } else {
        await SupabaseConfig.client
            .from('bus_vehicles')
            .delete()
            .eq('id', vehicleId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vehiculo eliminado'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadVehicles();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al eliminar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            const Icon(Icons.garage_rounded, color: AppColors.primary, size: 24),
            const SizedBox(width: 12),
            Text(
              'Mis Vehiculos',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            color: AppColors.border.withValues(alpha: 0.5),
            height: 1,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _vehicles.isEmpty
                  ? _buildEmpty()
                  : _buildVehiclesList(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Error desconocido',
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadVehicles,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.directions_bus_rounded,
                size: 80, color: AppColors.textTertiary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text(
              'No tienes vehiculos publicados',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Publica tu primer vehiculo para empezar',
              style: TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehiclesList() {
    return RefreshIndicator(
      onRefresh: _loadVehicles,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _vehicles.length,
        itemBuilder: (context, index) {
          final vehicle = _vehicles[index];
          return _buildVehicleCard(vehicle);
        },
      ),
    );
  }

  Widget _buildVehicleCard(Map<String, dynamic> vehicle) {
    final source = vehicle['_source'] ?? 'bus';
    final isRental = source == 'rental';

    // Common fields
    final make = vehicle[isRental ? 'vehicle_make' : 'make'] ?? '';
    final model = vehicle[isRental ? 'vehicle_model' : 'model'] ?? '';
    final year = vehicle[isRental ? 'vehicle_year' : 'year'];
    final imageUrls = vehicle['image_urls'] as List<dynamic>?;
    final firstPhoto = (imageUrls != null && imageUrls.isNotEmpty)
        ? imageUrls[0].toString()
        : null;

    // Bus-specific
    final vehicleName = isRental
        ? (vehicle['title'] ?? '$make $model')
        : (vehicle['vehicle_name'] ?? 'Sin nombre');
    final totalSeats = vehicle['total_seats'] ?? 0;
    final unitNumber = vehicle['unit_number'] as String?;

    // Rental-specific
    final weeklyPrice = vehicle['weekly_price_base'];
    final dailyPrice = vehicle['daily_price'];
    final status = vehicle['status'] as String?;
    final isActive = isRental ? status == 'active' : (vehicle['is_active'] ?? false);
    final vehicleType = vehicle['vehicle_type'] as String?;

    final accentColor = isRental ? const Color(0xFF8B5CF6) : AppColors.primary;
    final typeIcon = isRental ? Icons.directions_car_rounded : Icons.directions_bus_rounded;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Vehicle photo
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: firstPhoto != null
                  ? Image.network(
                      firstPhoto,
                      width: 85,
                      height: 85,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 85, height: 85,
                        color: accentColor.withValues(alpha: 0.1),
                        child: Icon(typeIcon, color: accentColor, size: 32),
                      ),
                    )
                  : Container(
                      width: 85, height: 85,
                      color: accentColor.withValues(alpha: 0.1),
                      child: Icon(typeIcon, color: accentColor, size: 32),
                    ),
            ),
            const SizedBox(width: 12),
            // Vehicle info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name + type badge
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          vehicleName,
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isRental ? (vehicleType ?? 'Renta').toUpperCase() : (unitNumber ?? 'BUS'),
                          style: TextStyle(color: accentColor, fontSize: 9, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$make $model ${year != null ? "($year)" : ""}',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (isRental && weeklyPrice != null) ...[
                        Icon(Icons.attach_money_rounded, size: 14, color: AppColors.success),
                        const SizedBox(width: 2),
                        Text(
                          '\$${(weeklyPrice as num).toStringAsFixed(0)}/sem',
                          style: const TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        if (dailyPrice != null && dailyPrice is num && dailyPrice > 0) ...[
                          Text(' · ', style: TextStyle(color: AppColors.textDisabled, fontSize: 12)),
                          Text(
                            '\$${dailyPrice.toStringAsFixed(0)}/dia',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                          ),
                        ],
                      ] else if (!isRental) ...[
                        Icon(Icons.event_seat, size: 14, color: AppColors.success),
                        const SizedBox(width: 4),
                        Text(
                          '$totalSeats asientos',
                          style: const TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.success.withValues(alpha: 0.15)
                              : AppColors.error.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isActive ? 'Activo' : 'Inactivo',
                          style: TextStyle(
                            color: isActive ? AppColors.success : AppColors.error,
                            fontSize: 10, fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Action buttons
            Column(
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_rounded, size: 20),
                  color: accentColor,
                  onPressed: () {
                    Navigator.of(context).pop();
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (ctx) => _PublishVehicleSheet(
                        userId: widget.userId,
                        existingVehicle: vehicle,
                      ),
                    ).then((_) => _loadVehicles());
                  },
                  tooltip: 'Editar',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  color: AppColors.error,
                  onPressed: () => _deleteVehicle(
                    vehicle['id'].toString(),
                    vehicleName,
                    source: source,
                  ),
                  tooltip: 'Eliminar',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
