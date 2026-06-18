import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// MoneyLogger — writes a snapshot of what a money screen RENDERS into the
/// shared `app_logs` table, so an external auditor (Claude) can verify that the
/// driver/rider/vendor apps show the SAME numbers as the admin web — WITHOUT
/// being able to open the rendered UI. Survives release builds (it's a real DB
/// insert, not a stripped debugPrint).
///
/// Read it: SELECT message, context FROM app_logs WHERE source='driver_app'
///          ORDER BY created_at DESC LIMIT 1;
class MoneyLogger {
  static const String _source = 'driver_app';
  static final Map<String, DateTime> _last = {};

  static Future<void> snapshot(
    String screen,
    Map<String, dynamic> kpis, {
    Map<String, dynamic>? context,
  }) async {
    final now = DateTime.now();
    final last = _last[screen];
    if (last != null && now.difference(last).inSeconds < 3) return;
    _last[screen] = now;
    try {
      final c = Supabase.instance.client;
      await c.from('app_logs').insert({
        'source': _source,
        'event': screen,
        'level': 'info',
        'app_role': 'driver',
        'user_id': c.auth.currentUser?.id,
        'message': kpis.entries.map((e) => '${e.key}=${e.value}').join(' | '),
        'context': {'kpis': kpis, if (context != null) ...context},
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[MoneyLogger] $screen failed: $e');
    }
  }
}
