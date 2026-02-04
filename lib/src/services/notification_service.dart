import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../config/supabase_config.dart';

/// Top-level background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('🔔 FCM Background message: ${message.messageId}');
}

class NotificationService {
  final SupabaseClient _client = SupabaseConfig.client;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;

  // Notification channels
  static const String rideChannel = 'ride_notifications';
  static const String chatChannel = 'chat_notifications';
  static const String earningsChannel = 'earnings_notifications';
  static const String generalChannel = 'general_notifications';

  // Initialize notification service
  Future<void> initialize() async {
    // Initialize local notifications
    await _initializeLocalNotifications();

    // Firebase Cloud Messaging
    await _requestPermissions();
    await _setupFirebaseMessaging();
  }

  // Initialize local notifications
  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
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

  // Show local notification
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
    String channelId = generalChannel,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelId == rideChannel
          ? 'Solicitudes de viaje'
          : channelId == chatChannel
              ? 'Mensajes'
              : channelId == earningsChannel
                  ? 'Ganancias'
                  : 'General',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@drawable/ic_notification',
      color: const Color(0xFFFFD700),
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

  // Get notification history from database
  Future<List<Map<String, dynamic>>> getNotificationHistory(String driverId) async {
    final response = await _client
        .from(SupabaseConfig.notificationsTable)
        .select()
        .eq('driver_id', driverId)
        .order('created_at', ascending: false)
        .limit(50);

    return List<Map<String, dynamic>>.from(response);
  }

  // Mark notification as read
  Future<void> markNotificationAsRead(String notificationId) async {
    await _client
        .from(SupabaseConfig.notificationsTable)
        .update({
          'is_read': true,
          'read_at': DateTime.now().toIso8601String(),
        })
        .eq('id', notificationId);
  }

  // Mark all notifications as read
  Future<void> markAllNotificationsAsRead(String driverId) async {
    await _client
        .from(SupabaseConfig.notificationsTable)
        .update({
          'is_read': true,
          'read_at': DateTime.now().toIso8601String(),
        })
        .eq('driver_id', driverId)
        .eq('is_read', false);
  }

  // Get unread notification count
  Future<int> getUnreadCount(String driverId) async {
    final response = await _client
        .from(SupabaseConfig.notificationsTable)
        .select('id')
        .eq('driver_id', driverId)
        .eq('is_read', false);

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
  // FIREBASE CLOUD MESSAGING
  // =========================================================================

  /// Request notification permissions (iOS + Android 13+)
  Future<void> _requestPermissions() async {
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

      // Foreground messages → show local notification
      _foregroundSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('🔔 FCM Foreground: ${message.notification?.title}');
        final notification = message.notification;
        if (notification != null) {
          final channelId = _channelFromData(message.data);
          _showLocalNotification(
            title: notification.title ?? 'Toro Driver',
            body: notification.body ?? '',
            payload: jsonEncode(message.data),
            channelId: channelId,
          );
        }
      });

      // When user taps notification that opened the app from background
      _openedAppSub = FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('🔔 FCM Opened app: ${message.data}');
        _handleNotificationTap(Map<String, dynamic>.from(message.data));
      });

      // Check if app was opened from a terminated state via notification
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('🔔 FCM Initial message: ${initialMessage.data}');
        _handleNotificationTap(Map<String, dynamic>.from(initialMessage.data));
      }
    } catch (e) {
      debugPrint('🔔 FCM setup error: $e');
    }
  }

  /// Get FCM token and save to Supabase drivers table
  Future<void> updateFCMToken(String driverId) async {
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
    if (type.contains('ride') || type.contains('trip')) return rideChannel;
    if (type.contains('message') || type.contains('chat')) return chatChannel;
    if (type.contains('earning') || type.contains('payment') || type.contains('payout')) return earningsChannel;
    return generalChannel;
  }

  // Dispose
  void dispose() {
    _foregroundSub?.cancel();
    _openedAppSub?.cancel();
  }
}
