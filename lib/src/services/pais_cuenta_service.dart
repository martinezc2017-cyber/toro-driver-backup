import 'package:flutter/foundation.dart' show debugPrint;

import '../config/supabase_config.dart';

/// Resultado de elegir el país de la cuenta (RPC `elegir_pais_conductor`).
class EleccionPais {
  final bool ok;
  final String? pais;
  final bool cambio;

  /// 'aprobado' | 'stripe' | 'pais_invalido' | 'sin_conductor' | 'error'
  final String? motivo;

  /// País que tiene la cuenta cuando no se pudo cambiar.
  final String? paisActual;

  const EleccionPais({
    required this.ok,
    this.pais,
    this.cambio = false,
    this.motivo,
    this.paisActual,
  });
}

/// País de la CUENTA del conductor: decide qué documentos se le piden, su contrato, su cuenta de
/// pagos (Stripe MX o US), la moneda y de qué país le llegan viajes. Lo elige el conductor (mientras
/// no esté aprobado ni tenga cuenta de Stripe) o soporte; el GPS nunca lo cambia.
class PaisCuentaService {
  PaisCuentaService._();
  static final PaisCuentaService instance = PaisCuentaService._();

  static const paises = ['MX', 'US'];

  Future<EleccionPais> elegir(String pais) async {
    try {
      final r = await SupabaseConfig.client
          .rpc('elegir_pais_conductor', params: {'p_pais': pais});
      final m = (r as Map).cast<String, dynamic>();
      return EleccionPais(
        ok: m['ok'] == true,
        pais: m['pais']?.toString(),
        cambio: m['cambio'] == true,
        motivo: m['motivo']?.toString(),
        paisActual: m['pais']?.toString(),
      );
    } catch (e) {
      debugPrint('PAIS_CUENTA -> elegir $pais falló: $e');
      return const EleccionPais(ok: false, motivo: 'error');
    }
  }

  /// Documentos que exige [pais], de la MISMA regla que usan la aprobación, el correo y el panel
  /// (`estado_documentos_conductor`). Devuelve los códigos (driver_license, ine, ...).
  Future<List<String>> requisitos(String driverId, String pais) async {
    final r = await SupabaseConfig.client.rpc('estado_documentos_conductor',
        params: {'p_driver_id': driverId, 'p_country': pais});
    final m = (r as Map).cast<String, dynamic>();
    return ((m['requeridos'] as List?) ?? const []).map((e) => e.toString()).toList();
  }
}
