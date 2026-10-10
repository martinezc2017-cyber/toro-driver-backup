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
    // La fila del chofer: por su id y, si no aparece (a veces lo que llega es
    // el id del USUARIO, que en 55 de 56 choferes no coincide con drivers.id),
    // por la cuenta con sesión.
    String idReal = driverId;
    String? nombre = fullName;
    try {
      var fila = await db
          .from('drivers')
          .select('id, referral_code, full_name, name')
          .eq('id', driverId)
          .maybeSingle();
      final uid = db.auth.currentUser?.id;
      if (fila == null && uid != null) {
        fila = await db
            .from('drivers')
            .select('id, referral_code, full_name, name')
            .eq('user_id', uid)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
      }
      if (fila != null) {
        idReal = (fila['id'] ?? driverId).toString();
        nombre ??= (fila['full_name'] ?? fila['name'])?.toString();
        final actual = (fila['referral_code'] ?? '').toString().trim();
        if (actual.isNotEmpty) {
          _cache[driverId] = actual;
          _cache[idReal] = actual;
          return actual;
        }
      }
    } catch (_) {
      // Sin red o sin permiso: se intenta generar abajo.
    }

    final nuevo = _generar(nombre);
    try {
      final guardado = await db
          .from('drivers')
          .update({'referral_code': nuevo})
          .eq('id', idReal)
          .select('id');
      // Sin fila actualizada no hay código guardado, y un QR con un código que
      // no existe en la base no le sirve a nadie.
      if ((guardado as List).isEmpty) return null;
      _cache[driverId] = nuevo;
      _cache[idReal] = nuevo;
      return nuevo;
    } catch (_) {
      // No se pudo guardar: sin código guardado el QR no serviría de nada, así
      // que la pantalla debe ocultarlo en vez de mostrar uno falso.
      return null;
    }
  }

  /// El código del chofer con sesión, aunque el perfil (DriverProvider) todavía
  /// no haya cargado: antes Referidos pintaba un QR a `toro-ride.com/d/` (sin
  /// código, a nadie) cuando el perfil venía nulo.
  Future<String?> loadForCurrentUser() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return null;
    return loadOrCreate(driverId: uid);
  }

  /// Mismo formato que ya usaba la pantalla de Referidos: nombre + 4 dígitos.
  String _generar(String? fullName) {
    final nombre = (fullName ?? 'TORO').trim();
    // Sin acentos ni símbolos: el código viaja en una liga (toro-ride.com/d/…)
    // y el router del app solo acepta A-Z y dígitos. "JOSUÉ6793" no abría nada.
    final primero = _sinAcentos(
            (nombre.isEmpty ? 'TORO' : nombre.split(' ').first).toUpperCase())
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final base = primero.isEmpty ? 'TORO' : primero;
    final corto = base.length > 6 ? base.substring(0, 6) : base;
    final rnd = Random();
    final digitos = List.generate(4, (_) => rnd.nextInt(10)).join();
    return '$corto$digitos';
  }

  static String _sinAcentos(String t) => t
      .replaceAll(RegExp('[ÁÀÄÂ]'), 'A')
      .replaceAll(RegExp('[ÉÈËÊ]'), 'E')
      .replaceAll(RegExp('[ÍÌÏÎ]'), 'I')
      .replaceAll(RegExp('[ÓÒÖÔ]'), 'O')
      .replaceAll(RegExp('[ÚÙÜÛ]'), 'U')
      .replaceAll('Ñ', 'N');

  /// La liga que se codifica en el QR y la que se comparte. Una sola forma para
  /// toda la app, para que no vuelvan a existir dos rutas distintas.
  static String link(String code) => 'https://toro-ride.com/d/$code';
}
