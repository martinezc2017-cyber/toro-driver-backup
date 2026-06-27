// =============================================================================
// BACKGROUND LOCATION SERVICE - GPS tracking even when app is closed
// =============================================================================
// Uses Android Foreground Service with persistent notification
// For driver: "Compartiendo tu ubicación con el pasajero"
//
// Use cases:
// - Driver going to pickup (rider sees driver location)
// - Driver during active ride
// - Tourism: bus driver location tracking
// =============================================================================

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/logging/app_logger.dart';

// Notification channel for foreground service
const String notificationChannelId = 'toro_driver_location_channel';
const String notificationChannelName = 'Ubicación del conductor';
const int notificationId = 889;

/// Initialize the background service - call once at app startup
Future<void> initializeBackgroundLocationService() async {
  final service = FlutterBackgroundService();

  // Create notification channel for Android
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    notificationChannelId,
    notificationChannelName,
    description: 'Compartiendo tu ubicación con el pasajero',
    importance: Importance.low, // Low = no sound, just persistent
    showBadge: false,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false, // Don't auto-start, we control when to start
      isForegroundMode: true,
      notificationChannelId: notificationChannelId,
      initialNotificationTitle: 'TORO Driver - Viaje activo',
      initialNotificationContent: 'Compartiendo tu ubicación...',
      foregroundServiceNotificationId: notificationId,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );

  AppLogger.log('BACKGROUND_LOCATION -> Service initialized');
}

/// iOS background handler
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

/// Main background service entry point
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // Get parameters passed when starting the service
  String? deliveryId;
  String? tableName;
  String? riderName;
  String? supabaseUrl;
  String? supabaseKey;
  String? driverId; // modo "online idle": heartbeat de presencia sin viaje
  int tick = 0;     // para throttlear el heartbeat idle a ~30s

  // Listen for data from main app
  service.on('setData').listen((event) {
    if (event != null) {
      deliveryId = event['deliveryId'] as String?;
      tableName = event['tableName'] as String?;
      riderName = event['riderName'] as String?;
      supabaseUrl = event['supabaseUrl'] as String?;
      supabaseKey = event['supabaseKey'] as String?;
      driverId = event['driverId'] as String?;

      AppLogger.log('BACKGROUND_LOCATION -> Data received: deliveryId=$deliveryId, rider=$riderName');
    }
  });

  // Listen for stop command
  service.on('stop').listen((event) {
    service.stopSelf();
    AppLogger.log('BACKGROUND_LOCATION -> Service stopped by command');
  });

  // Update notification when rider info changes
  service.on('updateNotification').listen((event) {
    if (event != null && service is AndroidServiceInstance) {
      final title = event['title'] as String? ?? 'TORO Driver - Viaje activo';
      final content = event['content'] as String? ?? 'Compartiendo tu ubicación...';
      service.setForegroundNotificationInfo(title: title, content: content);
    }
  });

  // Initialize Supabase client for background updates
  SupabaseClient? supabase;

  // GPS tracking timer - send every 5 seconds (driver needs faster updates)
  Timer.periodic(const Duration(seconds: 5), (timer) async {
    tick++;
    final idle = deliveryId == null && driverId != null;
    if (deliveryId == null && driverId == null) return;
    // En modo idle (solo presencia, sin viaje) heartbeat cada ~30s para no
    // drenar bateria; en viaje activo sigue cada 5s.
    if (idle && tick % 6 != 1) return;

    // Initialize Supabase if needed
    if (supabase == null && supabaseUrl != null && supabaseKey != null) {
      try {
        supabase = SupabaseClient(supabaseUrl!, supabaseKey!);
        AppLogger.log('BACKGROUND_LOCATION -> Supabase client initialized');
      } catch (e) {
        AppLogger.log('BACKGROUND_LOCATION -> Supabase init error: $e');
        return;
      }
    }

    if (supabase == null) return;

    try {
      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      // Update database
      if (deliveryId != null) {
        // VIAJE ACTIVO: comparte ubicacion con el pasajero (columnas de la fila)
        final table = tableName ?? 'deliveries';
        await supabase!.from(table).update({
          'driver_lat': position.latitude,
          'driver_lng': position.longitude,
          // Columna real en deliveries = driver_location_updated_at (driver_gps_updated_at
          // no existe -> el update rebotaba). + UTC (antes local = 7h mal).
          'driver_location_updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', deliveryId!);
      } else {
        // ONLINE IDLE: heartbeat de presencia -> drivers (lo que ve el admin/
        // dispatch). Sobrevive el segundo plano gracias al foreground service.
        await supabase!.from('drivers').update({
          'current_lat': position.latitude,
          'current_lng': position.longitude,
          'location_updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', driverId!);
      }

      AppLogger.log('BACKGROUND_LOCATION -> GPS sent: ${position.latitude}, ${position.longitude}');

      // Update foreground notification (simple style like Uber)
      if (service is AndroidServiceInstance) {
        final notificationContent = riderName != null
            ? 'En camino a recoger a $riderName'
            : 'Compartiendo tu ubicación...';

        const androidDetails = AndroidNotificationDetails(
          notificationChannelId,
          notificationChannelName,
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          icon: '@drawable/ic_notification',
          color: Color(0xFF2196F3),
          showWhen: false,
        );
        final flnp = FlutterLocalNotificationsPlugin();
        await flnp.show(
          notificationId,
          idle ? 'TORO Driver — En Línea' : 'TORO Driver - Viaje activo',
          idle ? 'Disponible para viajes' : notificationContent,
          const NotificationDetails(android: androidDetails),
        );
      }

      // Send update to main app
      service.invoke('locationUpdate', {
        'lat': position.latitude,
        'lng': position.longitude,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      AppLogger.log('BACKGROUND_LOCATION -> Error: $e');
      // RESPALDO DE PRESENCIA: si el GPS falla en segundo plano (background
      // lento, fix tardío), igual estampamos location_updated_at para que el
      // chofer NO desaparezca del mapa del admin NI del "hay choferes cerca"
      // del rider mientras siga online. Mismo criterio que el heartbeat de
      // foreground (_sendHeartbeat). Conserva las últimas coords conocidas.
      if (idle && driverId != null) {
        try {
          supabase ??= (supabaseUrl != null && supabaseKey != null)
              ? SupabaseClient(supabaseUrl!, supabaseKey!)
              : null;
          await supabase?.from('drivers').update({
            'location_updated_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', driverId!);
        } catch (_) {}
      }
    }
  });

  AppLogger.log('BACKGROUND_LOCATION -> Service started');
}

/// Controller class for easy use from the app
class BackgroundLocationController {
  static final BackgroundLocationController _instance =
      BackgroundLocationController._internal();
  factory BackgroundLocationController() => _instance;
  BackgroundLocationController._internal();

  final FlutterBackgroundService _service = FlutterBackgroundService();
  bool _isRunning = false;

  bool get isRunning => _isRunning;

  /// Start background location tracking
  /// Call when driver accepts a ride
  Future<void> startTracking({
    required String deliveryId,
    required String supabaseUrl,
    required String supabaseKey,
    String? riderName,
    String tableName = 'deliveries',
  }) async {
    if (_isRunning) {
      AppLogger.log('BACKGROUND_LOCATION -> Already running, updating data');
      // Just update the data
      _service.invoke('setData', {
        'deliveryId': deliveryId,
        'tableName': tableName,
        'riderName': riderName,
        'supabaseUrl': supabaseUrl,
        'supabaseKey': supabaseKey,
      });
      return;
    }

    // Check location permission
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      AppLogger.log('BACKGROUND_LOCATION -> No location permission');
      return;
    }

    // Start the service
    final started = await _service.startService();
    if (started) {
      _isRunning = true;

      // Send configuration data
      await Future.delayed(const Duration(milliseconds: 500));
      _service.invoke('setData', {
        'deliveryId': deliveryId,
        'tableName': tableName,
        'riderName': riderName,
        'supabaseUrl': supabaseUrl,
        'supabaseKey': supabaseKey,
      });

      AppLogger.log('BACKGROUND_LOCATION -> Tracking started for $deliveryId');
    } else {
      AppLogger.log('BACKGROUND_LOCATION -> Failed to start service');
    }
  }

  /// Inicia el HEARTBEAT DE PRESENCIA en segundo plano (sin viaje). Mantiene al
  /// chofer "online" aunque el app este minimizado o la pantalla apagada: el
  /// foreground service NO lo mata Android (a diferencia del Timer en el app,
  /// que se pausa en background y por eso el chofer "desaparecia" del admin).
  /// Llamar al ponerse EN LINEA.
  Future<void> startOnlineHeartbeat({
    required String driverId,
    required String supabaseUrl,
    required String supabaseKey,
  }) async {
    final data = {
      'driverId': driverId,
      'supabaseUrl': supabaseUrl,
      'supabaseKey': supabaseKey,
    };
    if (_isRunning) {
      _service.invoke('setData', data); // ya corre (p.ej. tras un viaje) -> idle
      return;
    }
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      AppLogger.log('BACKGROUND_LOCATION -> sin permiso (heartbeat)');
      return;
    }
    final started = await _service.startService();
    if (started) {
      _isRunning = true;
      await Future.delayed(const Duration(milliseconds: 500));
      _service.invoke('setData', data);
      AppLogger.log('BACKGROUND_LOCATION -> heartbeat online iniciado: $driverId');
    }
  }

  /// Update the notification text (e.g., status changes)
  void updateNotification({String? title, String? content}) {
    _service.invoke('updateNotification', {
      'title': title,
      'content': content,
    });
  }

  /// Stop background location tracking
  /// Call when ride is completed or cancelled
  Future<void> stopTracking() async {
    if (!_isRunning) return;

    _service.invoke('stop');
    _isRunning = false;
    AppLogger.log('BACKGROUND_LOCATION -> Tracking stopped');
  }

  /// Listen to location updates from background service
  Stream<Map<String, dynamic>?> get onLocationUpdate {
    return _service.on('locationUpdate');
  }
}
