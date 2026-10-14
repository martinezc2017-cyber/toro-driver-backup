import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_colors.dart';

/// Leyenda "con RFC / sin RFC" (Carlos, 13 oct 2026): el conductor debe ver por qué
/// conviene registrar su RFC. Las tasas NO van escritas a mano:
///  - con RFC  = `pricing_config.mx_isr_retention_percent` (lo que de verdad cobra el motor);
///  - sin RFC  = `countries.isr_rate_without_rfc` (Art. 113-A LISR).
/// Solo habla de ISR: la retención de IVA está apagada y no se promete.
class LeyendaRetencionIsr extends StatefulWidget {
  const LeyendaRetencionIsr({super.key});

  @override
  State<LeyendaRetencionIsr> createState() => _LeyendaRetencionIsrState();
}

class _LeyendaRetencionIsrState extends State<LeyendaRetencionIsr> {
  static ({double conRfc, double sinRfc})? _cache;
  late final Future<({double conRfc, double sinRfc})?> _tasas = _cargar();

  static Future<({double conRfc, double sinRfc})?> _cargar() async {
    if (_cache != null) return _cache;
    try {
      final db = Supabase.instance.client;
      final cfg = await db
          .from('pricing_config')
          .select('mx_isr_retention_percent')
          .eq('country_code', 'MX')
          .not('mx_isr_retention_percent', 'is', null)
          .limit(1)
          .maybeSingle();
      final pais = await db
          .from('countries')
          .select('isr_rate_without_rfc')
          .eq('code', 'MX')
          .maybeSingle();
      final con = double.tryParse('${cfg?['mx_isr_retention_percent']}');
      final sin = double.tryParse('${pais?['isr_rate_without_rfc']}');
      if (con == null || sin == null) return null;
      // countries guarda fracción (0.20); pricing_config guarda por ciento (2.10).
      return _cache = (conRfc: con, sinRfc: sin <= 1 ? sin * 100 : sin);
    } catch (_) {
      return null;
    }
  }

  static String _pct(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({double conRfc, double sinRfc})?>(
      future: _tasas,
      builder: (context, snap) {
        final t = snap.data;
        if (t == null) return const SizedBox.shrink(); // sin tasas no se inventa nada
        Widget fila(IconData icono, Color color, String texto) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icono, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(texto,
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.3)),
                ),
              ],
            );
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
          ),
          child: Column(children: [
            fila(Icons.check_circle, AppColors.success,
                'fiscal_leyenda_con'.tr(args: [_pct(t.conRfc)])),
            const SizedBox(height: 6),
            fila(Icons.warning_amber_rounded, AppColors.warning,
                'fiscal_leyenda_sin'.tr(args: [_pct(t.sinRfc)])),
          ]),
        );
      },
    );
  }
}
