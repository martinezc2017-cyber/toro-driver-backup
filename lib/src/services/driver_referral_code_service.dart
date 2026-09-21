import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

/// El código que va dentro del QR del conductor.
///
/// POR QUÉ EXISTE ESTE SERVICIO
/// El panel del home pintaba el QR con `drivers.qr_code`, y cuando venía nulo
/// se inventaba uno: `TORO-DRV-<5 letras del uuid>`. Esa columna está vacía
/// para TODOS los conductores, así que el QR siempre llevaba un código
/// inventado que no existe en ninguna tabla.
///
/// Quien resuelve el código es la función `award_qr_point(..., p_referrer_code,
/// ...)` de Supabase, y busca así:
///     SELECT id FROM drivers WHERE referral_code = p_referrer_code
///
/// Es decir, la única llave que el sistema entiende es **`referral_code`**, la
/// misma que ya usaba la pantalla de Referidos. Por eso ambas pantallas ahora
/// piden el código aquí: un solo código por conductor, el que sí cuenta puntos.
class DriverReferralCodeService {
  DriverReferralCodeService._();
  static final DriverReferralCodeService instance =
      DriverReferralCodeService._();

  final Map<String, String> _cache = {};

  /// Devuelve el `referral_code` del conductor. Si todavía no tiene, genera uno
  /// y lo guarda; si no se puede guardar, devuelve null en vez de inventar un
  /// código que el sistema no podría resolver.
  Future<String?> loadOrCreate({
    required String driverId,
    String? fullName,
  }) async {
    final enCache = _cache[driverId];
    if (enCache != null) return enCache;

    final db = Supabase.instance.client;
    try {
      final fila = await db
          .from('drivers')
          .select('referral_code')
          .eq('id', driverId)
          .maybeSingle();
      final actual = (fila?['referral_code'] ?? '').toString().trim();
      if (actual.isNotEmpty) {
        _cache[driverId] = actual;
        return actual;
      }
    } catch (_) {
      // Sin red o sin permiso: se intenta generar abajo.
    }

    final nuevo = _generar(fullName);
    try {
      await db
          .from('drivers')
          .update({'referral_code': nuevo}).eq('id', driverId);
      _cache[driverId] = nuevo;
      return nuevo;
    } catch (_) {
      // No se pudo guardar: sin código guardado el QR no serviría de nada, así
      // que la pantalla debe ocultarlo en vez de mostrar uno falso.
      return null;
    }
  }

  /// Mismo formato que ya usaba la pantalla de Referidos: nombre + 4 dígitos.
  String _generar(String? fullName) {
    final nombre = (fullName ?? 'TORO').trim();
    final primero =
        (nombre.isEmpty ? 'TORO' : nombre.split(' ').first).toUpperCase();
    final corto = primero.length > 6 ? primero.substring(0, 6) : primero;
    final rnd = Random();
    final digitos = List.generate(4, (_) => rnd.nextInt(10)).join();
    return '$corto$digitos';
  }

  /// La liga que se codifica en el QR y la que se comparte. Una sola forma para
  /// toda la app, para que no vuelvan a existir dos rutas distintas.
  static String link(String code) => 'https://toro-ride.com/d/$code';
}
