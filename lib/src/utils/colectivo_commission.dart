import '../config/supabase_config.dart';

/// Comisión TORO por BOLETO de colectivo (la paga el chofer en modo depósito).
///
/// Fuente única, siempre de la base:
///   1. `tourism_events.toro_commission_rate` del viaje (fracción, ej. 0.05),
///   2. si el viaje no la trae, `organizers.commission_rate` (en %, ej. 5.00).
/// Antes cada pantalla tenía su propio 18% (y una 20%) escrito en el código.
class ColectivoCommission {
  ColectivoCommission._();

  static final Map<String, double> _byOrganizer = {};

  /// Tasa (fracción) para un viaje ya cargado. Usa la del organizador en caché
  /// si el viaje no trae la suya; 0 si todavía no se conoce ninguna.
  static double rateFor(Map<String, dynamic>? event) {
    final own = (event?['toro_commission_rate'] as num?)?.toDouble();
    if (own != null) return own;
    final orgId = event?['organizer_id'] as String?;
    return (orgId != null ? _byOrganizer[orgId] : null) ?? 0;
  }

  /// Carga la tasa del organizador del viaje (llamar al abrir la pantalla).
  static Future<void> warmUp(Map<String, dynamic>? event) async {
    final orgId = event?['organizer_id'] as String?;
    if (orgId == null || _byOrganizer.containsKey(orgId)) return;
    try {
      final row = await SupabaseConfig.client
          .from('organizers')
          .select('commission_rate')
          .eq('id', orgId)
          .maybeSingle();
      final pct = (row?['commission_rate'] as num?)?.toDouble();
      if (pct != null) _byOrganizer[orgId] = pct / 100;
    } catch (_) {}
  }
}
