import 'package:supabase_flutter/supabase_flutter.dart';

/// FUENTE ÚNICA de los porcentajes que ve el chofer.
///
/// Lee `pricing_config` — la MISMA tabla que edita el admin en Dinero > Pricing.
/// Si el admin sube o baja un slider, la app lo refleja sin recompilar.
///
/// Por qué existe: cada pantalla traía su propia copia (y sus propios
/// hardcodes de USA: 57% chofer / 20.4% plataforma), así que a un chofer de
/// México se le mostraban números que no eran los suyos. Aquí se carga una vez
/// y todas las pantallas leen lo mismo.
///
/// Si no hay fila para el estado del chofer, cae a la fila DEFAULT de su país.
/// Si no hay nada, devuelve null: NO se inventan porcentajes.
class LivePricing {
  final double driver; // % que se queda el chofer
  final double platform; // % que cobra TORO
  final double insurance; // % de seguro
  final double iva; // % de IVA
  final double isrRetention; // retención ISR sobre la parte del chofer (MX)
  final double ivaRetention; // retención IVA sobre la parte del chofer (MX)

  // Turismo / camión (eventos de organizador). Van aparte del split de viajes.
  final double busSurcharge; // % que se le suma al pasajero sobre el precio base
  final double busToroKeep; // % que se queda TORO de ese cargo
  final double busOrganizer; // % del organizador

  const LivePricing({
    required this.driver,
    required this.platform,
    required this.insurance,
    required this.iva,
    required this.isrRetention,
    required this.ivaRetention,
    required this.busSurcharge,
    required this.busToroKeep,
    required this.busOrganizer,
  });

  /// Retención total del SAT sobre la parte del chofer.
  double get totalRetention => isrRetention + ivaRetention;

  static LivePricing? _cache;
  static String? _cacheKey;

  /// Trae los % del país+estado del chofer. Cachea por país+estado.
  static Future<LivePricing?> load({
    required String countryCode,
    String? stateCode,
  }) async {
    final country = countryCode.toUpperCase();
    final state = (stateCode ?? '').trim();
    final key = '$country|$state';
    if (_cache != null && _cacheKey == key) return _cache;

    try {
      final rows = await Supabase.instance.client
          .from('pricing_config')
          .select('state_code, driver_commission, platform_commission, '
              'insurance_percent, tax_percent, mx_isr_retention_percent, '
              'mx_iva_retention_percent, bus_passenger_surcharge_pct, '
              'bus_platform_keep_pct, bus_organizer_commission_pct')
          .eq('country_code', country)
          .eq('is_active', true);

      final list = (rows as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) return null;

      // 1) fila del estado del chofer  2) DEFAULT del país  3) la primera activa
      Map<String, dynamic>? row;
      for (final r in list) {
        if ((r['state_code']?.toString() ?? '') == state && state.isNotEmpty) {
          row = r;
          break;
        }
      }
      row ??= list.firstWhere(
        (r) => (r['state_code']?.toString() ?? '') == 'DEFAULT',
        orElse: () => list.first,
      );

      double v(String k) => (row![k] as num?)?.toDouble() ?? 0;
      final cfg = LivePricing(
        driver: v('driver_commission'),
        platform: v('platform_commission'),
        insurance: v('insurance_percent'),
        iva: v('tax_percent'),
        isrRetention: v('mx_isr_retention_percent'),
        ivaRetention: v('mx_iva_retention_percent'),
        busSurcharge: v('bus_passenger_surcharge_pct'),
        busToroKeep: v('bus_platform_keep_pct'),
        busOrganizer: v('bus_organizer_commission_pct'),
      );
      _cache = cfg;
      _cacheKey = key;
      return cfg;
    } catch (_) {
      // Si falla la red no se inventa nada: la pantalla decide qué mostrar.
      return null;
    }
  }

  /// Para cuando el admin cambia el pricing y se quiere refrescar ya.
  static void invalidate() {
    _cache = null;
    _cacheKey = null;
  }
}
