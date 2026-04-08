import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Remote debug logger — writes to Supabase debug_log table
/// Use for critical flows that need remote visibility (e.g. Apple Sign-In)
class DebugLogger {
  static Future<void> log(String step, {String? detail, String? userId}) async {
    debugPrint('[DEBUG_LOG] $step | $detail | $userId');
    try {
      await Supabase.instance.client.from('debug_log').insert({
        'step': step,
        'detail': detail,
        'user_id': userId ?? Supabase.instance.client.auth.currentUser?.id,
      });
    } catch (_) {
      // Never block the flow for logging
    }
  }
}
