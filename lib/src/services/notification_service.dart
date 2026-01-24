import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

// Firebase disabled for Windows build - uncomment for mobile release
// import 'package:firebase_core/firebase_core.dart';
// import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
  final SupabaseClient _client = SupabaseConfig.client;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  // Notification channels
  static const String rideChannel = 'ride_notifications';
  static const String chatChannel = 'chat_notifications';
  static const String earningsChannel = 'earnings_notifications';
  static const String generalChannel = 'general_notifications';

  // Initialize notification service
  Future<void> initialize() async {
    // Initialize local notifications
    await _initializeLocalNotifications();

    // Firebase disabled for Windows - uncomment for mobile release
    // await _requestPermissions();
    // await _setupFirebaseMessaging();
    // await _updateFCMToken();
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

  // Dispose
  void dispose() {
    // Firebase subscriptions disabled
  }
}
