import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../config/supabase_config.dart';
import 'in_app_banner_service.dart';

/// Top-level background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('🔔 FCM Background message: ${message.messageId}');
}

class NotificationService {
  final SupabaseClient _client = SupabaseConfig.client;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  // Lazy-init: FirebaseMessaging.instance crashes on web if Firebase not configured
  FirebaseMessaging? _messagingInstance;
  FirebaseMessaging get _messaging {
    _messagingInstance ??= FirebaseMessaging.instance;
    return _messagingInstance!;
  }

  // Platform channel for native custom notifications (colored TORO logo)
  static const _nativeChannel = MethodChannel('com.tororide.driver/notifications');
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;

  // Notification channels
  static const String rideChannel = 'ride_notifications';
  static const String chatChannel = 'chat_notifications';
  static const String earningsChannel = 'earnings_notifications';
  static const String generalChannel = 'general_notifications';

  // Initialize notification service (no permission dialog)
  Future<void> initialize() async {
    if (kIsWeb) {
      debugPrint('🔔 NotificationService: skipped on web');
      return;
    }
    // Initialize local notifications
    await _initializeLocalNotifications();

    // Firebase Cloud Messaging (setup handlers, no permission prompt)
    await _setupFirebaseMessaging();
  }

  // Initialize local notifications
  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@drawable/ic_notification');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    // Note: Windows notifications not supported in this version
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create notification channels for Android
    if (Platform.isAndroid) {
      await _createNotificationChannels();
    }
  }

  // Create Android notification channels
  Future<void> _createNotificationChannels() async {
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          rideChannel,
          'Solicitudes de viaje',
          description: 'Notificaciones de nuevas solicitudes de viaje',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );

      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          chatChannel,
          'Mensajes',
          description: 'Notificaciones de mensajes de pasajeros',
          importance: Importance.high,
          playSound: true,
        ),
      );

      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          earningsChannel,
          'Ganancias',
          description: 'Notificaciones de pagos y ganancias',
          importance: Importance.defaultImportance,
        ),
      );

      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          generalChannel,
          'General',
          description: 'Notificaciones generales de la aplicación',
          importance: Importance.defaultImportance,
        ),
      );
    }
  }

  // Show local notification with full-color TORO logo on the LEFT
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
    String channelId = generalChannel,
  }) async {
    if (kIsWeb) return; // Local notifications not supported on web
    // Load TORO logo for Person avatar (shows full color on LEFT)
    final ByteData byteData = await rootBundle.load('assets/images/toro_notification_logo.png');
    final Uint8List iconBytes = byteData.buffer.asUint8List();

    final toroPerson = Person(
      name: 'TORO Driver',
      key: 'toro_driver',
      icon: ByteArrayAndroidIcon(iconBytes),
    );

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelId == rideChannel
          ? 'Solicitudes de viaje'
          : channelId == chatChannel
              ? 'Mensajes'
              : channelId == earningsChannel
                  ? 'Ganancias'
                  : 'General',
      importance: Importance.max,
      priority: Priority.max,
      showWhen: true,
      icon: '@drawable/ic_notification',
      color: const Color(0xFF2196F3),
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      ledColor: const Color(0xFFFFD700),
      ledOnMs: 1000,
      ledOffMs: 500,
      category: AndroidNotificationCategory.message,
      shortcutId: 'toro_notifications',
      styleInformation: MessagingStyleInformation(
        toroPerson,
        conversationTitle: title,
        messages: [
          Message(body, DateTime.now(), toroPerson),
        ],
      ),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      details,
      payload: payload,
    );
  }

  // Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    if (response.payload != null) {
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;
      _handleNotificationTap(data);
    }
  }

  // Handle notification navigation
  void _handleNotificationTap(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    final id = data['id'] as String?;

    // Navigation will be handled by the app's navigation service
    // This is a placeholder for the callback
    _onNotificationTapCallback?.call(type, id);
  }

  // Callback for notification taps
  Function(String?, String?)? _onNotificationTapCallback;

  void setNotificationTapCallback(Function(String?, String?) callback) {
    _onNotificationTapCallback = callback;
  }

  // Show ride request notification
  Future<void> showRideRequestNotification({
    required String rideId,
    required String pickupAddress,
    required double fare,
  }) async {
    await _showLocalNotification(
      title: '¡Nueva solicitud de viaje!',
      body: 'Recoger en: $pickupAddress\nTarifa: \$${fare.toStringAsFixed(2)}',
      payload: jsonEncode({'type': 'ride_request', 'id': rideId}),
      channelId: rideChannel,
    );
  }

  // Show message notification
  Future<void> showMessageNotification({
    required String conversationId,
    required String senderName,
    required String message,
  }) async {
    await _showLocalNotification(
      title: senderName,
      body: message,
      payload: jsonEncode({'type': 'message', 'id': conversationId}),
      channelId: chatChannel,
    );
  }

  // Show earning notification
  Future<void> showEarningNotification({
    required double amount,
    required String description,
  }) async {
    await _showLocalNotification(
      title: '¡Ganancia recibida!',
      body: '+\$${amount.toStringAsFixed(2)} - $description',
      payload: jsonEncode({'type': 'earning'}),
      channelId: earningsChannel,
    );
  }

  // Show ride completion earning notification with breakdown
  Future<void> showRideEarningNotification({
    required double totalEarnings,
    required double baseFare,
    double tip = 0,
    double qrBonus = 0,
  }) async {
    final parts = <String>['\$${baseFare.toStringAsFixed(2)} base'];
    if (tip > 0) parts.add('+\$${tip.toStringAsFixed(2)} propina');
    if (qrBonus > 0) parts.add('+\$${qrBonus.toStringAsFixed(2)} QR bonus');

    await _showLocalNotification(
      title: '+\$${totalEarnings.toStringAsFixed(2)} - Viaje completado',
      body: parts.join(' | '),
      payload: jsonEncode({'type': 'earning'}),
      channelId: earningsChannel,
    );
  }

  // Show support ticket update notification
  Future<void> showTicketUpdateNotification({
    required String ticketId,
    required String subject,
    required String status,
  }) async {
    String statusText;
    switch (status) {
      case 'pending':
        statusText = 'En revisión';
        break;
      case 'in_progress':
        statusText = 'En progreso';
        break;
      case 'resolved':
        statusText = 'Resuelto';
        break;
      case 'closed':
        statusText = 'Cerrado';
        break;
      default:
        statusText = status;
    }

    await _showLocalNotification(
      title: 'Actualización de Ticket',
      body: '$subject - Estado: $statusText',
      payload: jsonEncode({'type': 'ticket_update', 'id': ticketId}),
      channelId: generalChannel,
    );
  }

  // Show general notification (for tourism, events, etc.)
  Future<void> showGeneralNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    await _showLocalNotification(
      title: title,
      body: body,
      payload: data != null ? jsonEncode(data) : null,
      channelId: generalChannel,
    );
  }

  // Get notification history from database
  Future<List<Map<String, dynamic>>> getNotificationHistory(String driverId) async {
    final response = await _client
        .from(SupabaseConfig.notificationsTable)
        .select()
        .eq('user_id', driverId)
        .order('created_at', ascending: false)
        .limit(50);

    return List<Map<String, dynamic>>.from(response);
  }

  // Mark notification as read
  Future<void> markNotificationAsRead(String notificationId) async {
    await _client
        .from(SupabaseConfig.notificationsTable)
        .update({'read': true})
        .eq('id', notificationId);
  }

  // Mark all notifications as read
  Future<void> markAllNotificationsAsRead(String driverId) async {
    await _client
        .from(SupabaseConfig.notificationsTable)
        .update({'read': true})
        .eq('user_id', driverId)
        .eq('read', false);
  }

  // Get unread notification count
  Future<int> getUnreadCount(String driverId) async {
    final response = await _client
        .from(SupabaseConfig.notificationsTable)
        .select('id')
        .eq('user_id', driverId)
        .eq('read', false);

    return (response as List).length;
  }

  // Clear all notifications
  Future<void> clearAllNotifications() async {
    await _localNotifications.cancelAll();
  }

  // Cancel specific notification
  Future<void> cancelNotification(int id) async {
    await _localNotifications.cancel(id);
  }

  // =========================================================================
  // TOURISM BIDDING NOTIFICATIONS
  // =========================================================================

  /// Show notification when organizer sends bid request to driver
  Future<void> showBidRequestNotification({
    required String bidId,
    required String eventName,
    required String organizerName,
    required double totalKm,
  }) async {
    await _showLocalNotification(
      title: '¡Nueva Solicitud de Puja!',
      body: '$organizerName te invita a participar en: $eventName\n${totalKm.toStringAsFixed(0)} km',
      payload: jsonEncode({'type': 'bid_request', 'id': bidId}),
      channelId: rideChannel,
    );
  }

  /// Show notification when driver responds to bid request
  Future<void> showBidResponseNotification({
    required String bidId,
    required String driverName,
    required double pricePerKm,
    bool accepted = true,
  }) async {
    if (accepted) {
      await _showLocalNotification(
        title: 'Nueva Oferta Recibida',
        body: '$driverName ofrece \$${pricePerKm.toStringAsFixed(2)}/km',
        payload: jsonEncode({'type': 'bid_response', 'id': bidId}),
        channelId: earningsChannel,
      );
    } else {
      await _showLocalNotification(
        title: 'Puja Rechazada',
        body: '$driverName rechazó la solicitud',
        payload: jsonEncode({'type': 'bid_rejected', 'id': bidId}),
        channelId: generalChannel,
      );
    }
  }

  /// Show notification when organizer selects winning bid
  Future<void> showBidAcceptedNotification({
    required String bidId,
    required String eventName,
    required double pricePerKm,
    bool isWinner = true,
  }) async {
    if (isWinner) {
      await _showLocalNotification(
        title: '¡Tu Puja Fue Seleccionada!',
        body: 'Ganaste: $eventName a \$${pricePerKm.toStringAsFixed(2)}/km',
        payload: jsonEncode({'type': 'bid_won', 'id': bidId}),
        channelId: earningsChannel,
      );
    } else {
      await _showLocalNotification(
        title: 'Puja No Seleccionada',
        body: 'El organizador seleccionó otra oferta para: $eventName',
        payload: jsonEncode({'type': 'bid_lost', 'id': bidId}),
        channelId: generalChannel,
      );
    }
  }

  /// Show notification when organizer sends a counter-offer on a bid
  Future<void> showCounterOfferNotification({
    required String bidId,
    required String eventName,
    required double counterOfferPrice,
  }) async {
    await _showLocalNotification(
      title: 'Contra-oferta Recibida',
      body: 'El organizador propone \$${counterOfferPrice.toStringAsFixed(2)}/km para: $eventName',
      payload: jsonEncode({
        'type': 'bid_counter_offer',
        'bid_id': bidId,
      }),
      channelId: rideChannel,
    );
  }

  /// Show notification when a new passenger join request arrives
  Future<void> showJoinRequestNotification({
    required String eventId,
    required String passengerName,
    required String eventName,
  }) async {
    await _showLocalNotification(
      title: 'Nueva Solicitud de Pasajero',
      body: '$passengerName quiere unirse a: $eventName',
      payload: jsonEncode({
        'type': 'join_request_new',
        'event_id': eventId,
      }),
      channelId: generalChannel,
    );
  }

  /// Show notification when a review is submitted for an event
  Future<void> showReviewSubmittedNotification({
    required String eventId,
    required String eventName,
    required double rating,
  }) async {
    await _showLocalNotification(
      title: 'Nueva Resena',
      body: 'Calificacion: ${rating.toStringAsFixed(1)} estrellas para: $eventName',
      payload: jsonEncode({
        'type': 'review_submitted',
        'event_id': eventId,
      }),
      channelId: generalChannel,
    );
  }

  /// Show notification when an abuse report is updated
  Future<void> showAbuseReportUpdateNotification({
    required String reportId,
    required String status,
    String? message,
  }) async {
    await _showLocalNotification(
      title: 'Actualizacion de Reporte',
      body: message ?? 'Tu reporte ha sido actualizado. Estado: $status',
      payload: jsonEncode({
        'type': 'abuse_report_update',
        'id': reportId,
      }),
      channelId: generalChannel,
    );
  }

  /// Show notification for weekly statement generated
  Future<void> showWeeklyStatementNotification({
    required String statementId,
    required double amountDue,
    required String dueDate,
  }) async {
    await _showLocalNotification(
      title: 'Estado de Cuenta Semanal',
      body: 'Debes \$${amountDue.toStringAsFixed(2)}\nFecha límite: $dueDate',
      payload: jsonEncode({'type': 'weekly_statement', 'id': statementId}),
      channelId: earningsChannel,
    );
  }

  /// Show notification for payment due/overdue
  Future<void> showPaymentDueNotification({
    required String statementId,
    required double amountDue,
    required bool isOverdue,
  }) async {
    await _showLocalNotification(
      title: isOverdue ? '⚠️ Pago Vencido' : 'Recordatorio de Pago',
      body: isOverdue
          ? 'Pago vencido de \$${amountDue.toStringAsFixed(2)}\nTu cuenta puede ser suspendida'
          : 'Tienes un pago pendiente de \$${amountDue.toStringAsFixed(2)}',
      payload: jsonEncode({'type': 'payment_due', 'id': statementId}),
      channelId: isOverdue ? rideChannel : earningsChannel,
    );
  }

  /// Show notification when payment is approved
  Future<void> showPaymentApprovedNotification({
    required String paymentId,
    required double amount,
  }) async {
    await _showLocalNotification(
      title: '✅ Pago Aprobado',
      body: 'Tu pago de \$${amount.toStringAsFixed(2)} ha sido aprobado',
      payload: jsonEncode({'type': 'payment_approved', 'id': paymentId}),
      channelId: earningsChannel,
    );
  }

  /// Show notification when account is blocked/unblocked
  Future<void> showAccountStatusNotification({
    required bool isBlocked,
    String? reason,
  }) async {
    if (isBlocked) {
      await _showLocalNotification(
        title: '🚫 Cuenta Suspendida',
        body: reason ?? 'Tu cuenta ha sido suspendida por pagos vencidos',
        payload: jsonEncode({'type': 'account_blocked'}),
        channelId: rideChannel,
      );
    } else {
      await _showLocalNotification(
        title: '✅ Cuenta Reactivada',
        body: 'Tu cuenta ha sido desbloqueada. Ya puedes crear eventos',
        payload: jsonEncode({'type': 'account_unblocked'}),
        channelId: generalChannel,
      );
    }
  }

  // =========================================================================
  // FIREBASE CLOUD MESSAGING
  // =========================================================================

  /// Request notification permissions (iOS + Android 13+)
  /// Call this from home screen instead of startup to avoid blocking terms screen
  Future<void> requestPermissions() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      debugPrint('🔔 FCM permission: ${settings.authorizationStatus}');
    } catch (e) {
      debugPrint('🔔 FCM permission error: $e');
    }
  }

  /// Setup Firebase Messaging handlers
  Future<void> _setupFirebaseMessaging() async {
    try {
      // Background handler (top-level)
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Foreground messages → show in-app banner + local notification
      _foregroundSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('🔔 FCM Foreground: ${message.notification?.title}');
        final notification = message.notification;
        if (notification != null) {
          final title = notification.title ?? 'Toro Driver';
          final body = notification.body ?? '';
          final type = message.data['type'] as String? ??
              message.data['notification_type'] as String? ?? '';
          final data = Map<String, dynamic>.from(message.data);

          // Show in-app banner overlay
          InAppBannerService.instance.show(
            title: title,
            body: body,
            type: type,
            data: data,
            onTap: () => _navigateFromNotification(data),
          );

          // Also show system notification (for notification shade)
          final channelId = _channelFromData(message.data);
          _showLocalNotification(
            title: title,
            body: body,
            payload: jsonEncode(message.data),
            channelId: channelId,
          );
        }
      });

      // When user taps notification that opened the app from background
      _openedAppSub = FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('🔔 FCM Opened app: ${message.data}');
        _navigateFromNotification(Map<String, dynamic>.from(message.data));
      });

      // Check if app was opened from a terminated state via notification
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('🔔 FCM Initial message: ${initialMessage.data}');
        // Delay to let navigator initialize
        Future.delayed(const Duration(milliseconds: 500), () {
          _navigateFromNotification(Map<String, dynamic>.from(initialMessage.data));
        });
      }
    } catch (e) {
      debugPrint('🔔 FCM setup error: $e');
    }
  }

  /// Get FCM token and save to Supabase drivers table
  Future<void> updateFCMToken(String driverId) async {
    if (kIsWeb) return;
    try {
      final token = await _messaging.getToken();
      if (token == null) return;

      debugPrint('🔔 FCM Token: ${token.substring(0, 20)}...');

      // Save to drivers table
      await _client.from(SupabaseConfig.driversTable).update({
        'fcm_token': token,
        'fcm_token_updated_at': DateTime.now().toIso8601String(),
      }).eq('id', driverId);

      debugPrint('🔔 FCM Token saved for driver $driverId');

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) async {
        debugPrint('🔔 FCM Token refreshed');
        await _client.from(SupabaseConfig.driversTable).update({
          'fcm_token': newToken,
          'fcm_token_updated_at': DateTime.now().toIso8601String(),
        }).eq('id', driverId);
      });
    } catch (e) {
      debugPrint('🔔 FCM Token error: $e');
    }
  }

  /// Clear FCM token on logout
  Future<void> clearFCMToken(String driverId) async {
    if (kIsWeb) return;
    try {
      await _client.from(SupabaseConfig.driversTable).update({
        'fcm_token': null,
      }).eq('id', driverId);
      await _messaging.deleteToken();
      debugPrint('🔔 FCM Token cleared for driver $driverId');
    } catch (e) {
      debugPrint('🔔 FCM Token clear error: $e');
    }
  }

  /// Map FCM data to notification channel
  String _channelFromData(Map<String, dynamic> data) {
    final type = data['type'] as String? ?? '';

    // Ride/trip notifications
    if (type.contains('ride') || type.contains('trip')) return rideChannel;

    // Message/chat notifications
    if (type.contains('message') || type.contains('chat')) return chatChannel;

    // Earning/payment notifications (including bidding wins and payments)
    if (type.contains('earning') ||
        type.contains('payment') ||
        type.contains('payout') ||
        type.contains('bid_won') ||
        type.contains('bid_response') ||
        type.contains('weekly_statement')) return earningsChannel;

    // High-priority bid requests and counter-offers
    if (type.contains('bid_request') || type.contains('bid_counter_offer')) {
      return rideChannel;
    }

    // Join requests (passenger wants to join event)
    if (type.contains('join_request')) return generalChannel;

    // Reviews
    if (type.contains('review_submitted')) return generalChannel;

    // Abuse reports
    if (type.contains('abuse_report')) return generalChannel;

    // Account status changes
    if (type.contains('account_blocked')) return rideChannel;

    return generalChannel;
  }

  // =========================================================================
  // NAVIGATION FROM NOTIFICATIONS
  // =========================================================================

  /// Navigate to the correct screen based on notification data
  void _navigateFromNotification(Map<String, dynamic> data) {
    final navigator = InAppBannerService.navigatorKey.currentState;
    if (navigator == null) return;

    final type = data['type'] as String? ??
        data['notification_type'] as String? ?? '';
    final eventId = data['event_id'] as String?;
    final bidId = data['bid_id'] as String?;

    switch (type) {
      // Tourism bid request → vehicle requests screen
      case 'tourism':
      case 'bid_request':
        if (eventId != null) {
          navigator.pushNamed('/vehicle-requests', arguments: {'event_id': eventId, 'bid_id': bidId});
        } else {
          navigator.pushNamed('/notifications');
        }
        break;

      // Counter-offer from organizer → vehicle request screen to see it
      case 'bid_counter_offer':
        if (eventId != null) {
          navigator.pushNamed('/vehicle-requests', arguments: {
            'event_id': eventId,
            'bid_id': bidId,
          });
        } else {
          navigator.pushNamed('/notifications');
        }
        break;

      // New join request from a passenger → join requests screen
      case 'join_request_new':
        if (eventId != null) {
          navigator.pushNamed('/join-requests', arguments: {
            'event_id': eventId,
          });
        } else {
          navigator.pushNamed('/notifications');
        }
        break;

      // Join request accepted/rejected (rider-side, future use)
      case 'join_request_accepted':
      case 'join_request_rejected':
        navigator.pushNamed('/notifications');
        break;

      // New review submitted for an event → event reviews screen
      case 'review_submitted':
        if (eventId != null) {
          navigator.pushNamed('/event-reviews', arguments: {
            'event_id': eventId,
          });
        } else {
          navigator.pushNamed('/notifications');
        }
        break;

      // Abuse report status update → notifications list
      case 'abuse_report_update':
        navigator.pushNamed('/notifications');
        break;

      // Ride-related
      case 'ride_request':
      case 'ride_update':
      case 'trip':
        navigator.pushNamed('/rides');
        break;

      // Messages/chat
      case 'message':
      case 'chat':
        navigator.pushNamed('/messages');
        break;

      // Bid won → navigate to driver bids screen to see the won bid
      case 'bid_won':
        navigator.pushNamed('/driver-bids');
        break;

      // Earnings/payments
      case 'earning':
      case 'payment':
      case 'bid_response':
      case 'weekly_statement':
        navigator.pushNamed('/earnings');
        break;

      // Account status
      case 'account_blocked':
      case 'account_unblocked':
        navigator.pushNamed('/account');
        break;

      // Default → notifications list
      default:
        navigator.pushNamed('/notifications');
        break;
    }
  }

  // Dispose
  void dispose() {
    _foregroundSub?.cancel();
    _openedAppSub?.cancel();
  }
}
