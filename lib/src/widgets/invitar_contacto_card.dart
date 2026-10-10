import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_colors.dart';
import '../utils/haptic_service.dart';

/// "Invita por teléfono o correo" del chofer.
///
/// El chofer escribe el teléfono (MX/US) o correo del pasajero; el servidor
/// (`invitar_contacto` con `p_app: 'driver'`) manda el SMS o el correo con el
/// código del QR del chofer (`drivers.referral_code`) y la invitación queda
/// apartada a ese dato: cuando esa persona se registra con ese mismo teléfono
/// o correo, queda como pasajero traído por este chofer sin copiar nada.
class InvitarContactoCard extends StatefulWidget {
  const InvitarContactoCard({super.key});

  @override
  State<InvitarContactoCard> createState() => _InvitarContactoCardState();
}

class _InvitarContactoCardState extends State<InvitarContactoCard> {
  final _ctrl = TextEditingController();
  String _pais = 'MX';
  bool _enviando = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final destino = _ctrl.text.trim();
    if (destino.isEmpty || _enviando) return;
    HapticService.lightImpact();
    setState(() => _enviando = true);
    String resultado = 'error';
    String? canal;
    String? destinoServidor;
    try {
      final r = await Supabase.instance.client.rpc('invitar_contacto', params: {
        'p_destino': destino,
        'p_country': _pais,
        'p_app': 'driver',
      });
      final m = r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
      resultado = (m['resultado'] as String?) ?? 'error';
      canal = m['canal'] as String?;
      destinoServidor = m['destino'] as String?;
    } catch (_) {
      resultado = 'error';
    }
    if (!mounted) return;
    setState(() => _enviando = false);
    final mostrado = destinoServidor ?? destino;
    final texto = switch (resultado) {
      'enviado' => (canal == 'sms' ? 'invitar.enviado_sms' : 'invitar.enviado_correo')
          .tr(namedArgs: {'destino': mostrado}),
      'ya_tiene_cuenta' => 'invitar.ya_tiene_cuenta'.tr(),
      'propio' => 'invitar.propio'.tr(),
      'repetido' => 'invitar.repetido'.tr(),
      'tope' => 'invitar.tope'.tr(),
      'invalido' => 'invitar.invalido'.tr(),
      'sin_codigo' => 'invitar.sin_codigo'.tr(),
      _ => 'invitar.error'.tr(),
    };
    if (resultado == 'enviado') {
      HapticService.success();
      _ctrl.clear();
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: resultado == 'enviado' ? AppColors.success : null,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
    ));
  }

  @override
  Widget build(BuildContext context) {
    Widget pais(String codigo, String etiqueta) => ChoiceChip(
          label: Text(etiqueta, style: const TextStyle(fontSize: 12)),
          selected: _pais == codigo,
          selectedColor: AppColors.primary.withValues(alpha: 0.18),
          onSelected: (_) => setState(() => _pais = codigo),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.send_rounded, color: AppColors.primary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text('invitar.titulo'.tr(),
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 6),
          Text('invitar.texto'.tr(),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.35)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [pais('MX', 'invitar.pais_mx'.tr()), pais('US', 'invitar.pais_us'.tr())]),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _enviar(),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'invitar.hint'.tr(),
              prefixIcon: const Icon(Icons.person_add_alt_1_outlined, size: 20),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _enviando ? null : _enviar,
              icon: _enviando
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send, size: 18),
              label: Text('invitar.boton'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
