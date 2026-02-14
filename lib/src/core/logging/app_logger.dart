import 'package:flutter/foundation.dart';

/// Simple logger for the Toro Driver app
class AppLogger {
  AppLogger._();

  static void log(String message) {
    if (kDebugMode) {
      final timestamp = DateTime.now().toIso8601String();
      // print('[$timestamp] $message');
    }
  }

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      debugPrint('[ERROR] $message');
      if (error != null) debugPrint('  Error: $error');
      if (stackTrace != null) debugPrint('  StackTrace: $stackTrace');
    }
  }
}
