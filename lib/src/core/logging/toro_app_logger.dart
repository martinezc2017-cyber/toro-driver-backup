import 'dart:async';
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'uso_app_tracker.dart';

/// Eventos de uso de la app del CHOFER a `app_logs` (función `log-event`),
/// igual que el `ToroAppLogger` del rider pero con `app_role = 'driver'`.
///
/// Antes la app del chofer casi no mandaba nada (10 eventos en toda su
/// historia) y no se podía saber si los choferes entraban, si abrían
/// Documentos ni dónde se atoraban. Barato, en lotes y nunca truena la app.
class ToroAppLogger {
  ToroAppLogger._();

  static const _appRole = 'driver';
  static const _flushIntervalSec = 30;
  static const _maxBufferSize = 50;

  static final List<Map<String, dynamic>> _buffer = [];
  static Timer? _flushTimer;
  static String? _appVersion;
  static Map<String, dynamic>? _deviceInfo;
  static bool _initialized = false;

  /// Llamar una vez al arrancar, después de inicializar Supabase.
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final pkg = await PackageInfo.fromPlatform();
      _appVersion = '${pkg.version}+${pkg.buildNumber}';
    } catch (_) {}
    try {
      final dev = DeviceInfoPlugin();
      if (!kIsWeb && Platform.isAndroid) {
        final a = await dev.androidInfo;
        _deviceInfo = {
          'platform': 'android',
          'model': a.model,
          'manufacturer': a.manufacturer,
          'os_version': a.version.release,
          'sdk_int': a.version.sdkInt,
        };
      } else if (!kIsWeb && Platform.isIOS) {
        final i = await dev.iosInfo;
        _deviceInfo = {
          'platform': 'ios',
          'model': i.utsname.machine,
          'os_version': i.systemVersion,
        };
      }
    } catch (_) {}
    _flushTimer = Timer.periodic(
      const Duration(seconds: _flushIntervalSec),
      (_) => _flush(),
    );
    // Quien abre y cierra la app en menos de 30 s también cuenta: se envía
    // al mandarla al fondo.
    _ciclo = AppLifecycleListener(onHide: () => unawaited(_flush()));
  }

  // ignore: unused_field
  static AppLifecycleListener? _ciclo;

  static void info({
    required String source,
    required String event,
    String? message,
    Map<String, dynamic>? context,
  }) =>
      _enqueue('info', source, event, message, context, null);

  static void warn({
    required String source,
    required String event,
    String? message,
    Map<String, dynamic>? context,
  }) =>
      _enqueue('warn', source, event, message, context, null);

  static void error({
    required String source,
    required String event,
    String? message,
    Map<String, dynamic>? context,
    Object? error,
    StackTrace? stack,
  }) =>
      _enqueue('error', source, event, message ?? error?.toString(), context,
          stack?.toString());

  static void _enqueue(
    String level,
    String source,
    String event,
    String? message,
    Map<String, dynamic>? context,
    String? stack,
  ) {
    if (!_initialized) return;
    String? userId;
    try {
      userId = Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {}
    _buffer.add({
      'level': level,
      'source': source,
      'event': event,
      if (message != null) 'message': message,
      if (userId != null) 'user_id': userId,
      if (_deviceInfo != null) 'device_info': _deviceInfo,
      'context': {...UsoAppTracker.contexto(), ...?context},
      if (stack != null) 'stack_trace': stack,
      if (_appVersion != null) 'app_version': _appVersion,
      'app_role': _appRole,
    });
    if (_buffer.length >= _maxBufferSize) unawaited(_flush());
  }

  static Future<void> _flush() async {
    if (_buffer.isEmpty) return;
    final batch = List<Map<String, dynamic>>.from(_buffer);
    _buffer.clear();
    try {
      await Supabase.instance.client.functions.invoke('log-event', body: batch);
    } catch (e) {
      // Se descarta el lote: los eventos de uso son de mejor esfuerzo.
      if (kDebugMode) debugPrint('ToroAppLogger flush: $e');
    }
  }

  /// Enviar ya (p. ej. al mandar la app al fondo).
  static Future<void> flushNow() => _flush();
}
