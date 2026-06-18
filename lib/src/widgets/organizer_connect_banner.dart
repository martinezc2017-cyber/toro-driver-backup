import 'package:flutter/material.dart';

import '../services/organizer_stripe_service.dart';

/// Banner que aparece automáticamente en cualquier pantalla de organizador
/// cuando aún no completa el onboarding de Stripe Connect.
///
/// Tres estados:
/// - `notCreated`/`incomplete` → CTA "Activar pagos" en rojo, bloquea cobros
/// - `pending` (KYC en revisión) → banner amarillo informativo
/// - `active` → no se muestra
///
/// Uso: insertar como hijo dentro de un Column en cada pantalla organizer
/// (home, dashboard, events, earnings, etc.). El banner se autogestiona.
///
/// ```dart
/// OrganizerConnectBanner(organizerId: orgId)
/// ```
class OrganizerConnectBanner extends StatefulWidget {
  final String organizerId;
  final EdgeInsetsGeometry margin;

  const OrganizerConnectBanner({
    super.key,
    required this.organizerId,
    this.margin = const EdgeInsets.all(12),
  });

  @override
  State<OrganizerConnectBanner> createState() => _OrganizerConnectBannerState();
}

class _OrganizerConnectBannerState extends State<OrganizerConnectBanner> {
  OrganizerStripeStatus? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant OrganizerConnectBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.organizerId != widget.organizerId) _load();
  }

  Future<void> _load() async {
    final s = await OrganizerStripeService.instance.getStatus(widget.organizerId);
    if (!mounted) return;
    setState(() => _status = s);
  }

  Future<void> _activate() async {
    setState(() => _busy = true);
    try {
      String? url;
      if (_status == null || !_status!.hasAccount) {
        url = await OrganizerStripeService.instance.createConnectAccount(
          organizerId: widget.organizerId,
        );
      } else {
        url = await OrganizerStripeService.instance.getOnboardingLink(widget.organizerId);
      }
      if (url == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo abrir el onboarding de Stripe')),
          );
        }
        return;
      }
      await OrganizerStripeService.instance.openOnboardingLink(url);
    } finally {
      if (mounted) setState(() => _busy = false);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    if (s == null) return const SizedBox.shrink();
    if (s.isActive) return const SizedBox.shrink();

    final isPending = s.detailsSubmitted && !s.canReceivePayments;
    final bg = isPending ? const Color(0xFFFFF7E6) : const Color(0xFFFFEBEE);
    final fg = isPending ? const Color(0xFF7A4F00) : const Color(0xFFB71C1C);
    final icon = isPending ? Icons.hourglass_top : Icons.warning_amber_rounded;
    final title = isPending
        ? 'Stripe está revisando tu identidad'
        : 'No puedes recibir dinero todavía';
    final subtitle = isPending
        ? 'En cuanto Stripe verifique tus documentos podrás cobrar reservas y recibir payouts.'
        : 'Conecta tu cuenta de Stripe para recibir pagos de pasajeros. Sin esto, el dinero queda detenido.';

    return Container(
      margin: widget.margin,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: fg.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: fg, fontSize: 12)),
                if (!isPending) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 32,
                    child: ElevatedButton.icon(
                      onPressed: _busy ? null : _activate,
                      icon: const Icon(Icons.link, size: 16),
                      label: Text(_busy ? 'Abriendo…' : 'Activar pagos'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: fg,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Guard para acciones que requieren `charges_enabled` (cobrar reservas).
/// Devuelve `true` si puede proceder; si no, muestra dialog explicando por qué.
class OrganizerConnectGuard {
  static Future<bool> require({
    required BuildContext context,
    required String organizerId,
    String actionLabel = 'cobrar',
  }) async {
    final s = await OrganizerStripeService.instance.getStatus(organizerId);
    if (s.canReceivePayments) return true;
    if (!context.mounted) return false;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('No puedes $actionLabel todavía'),
        content: const Text(
          'Para que TORO pueda enviarte el dinero de los pasajeros, '
          'primero tienes que completar tu cuenta de Stripe.\n\n'
          'Tu cuenta queda lista en 3 minutos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Más tarde'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Activar pagos'),
          ),
        ],
      ),
    );
    if (proceed != true) return false;
    String? url;
    if (s.hasAccount) {
      url = await OrganizerStripeService.instance.getOnboardingLink(organizerId);
    } else {
      url = await OrganizerStripeService.instance.createConnectAccount(organizerId: organizerId);
    }
    if (url != null) {
      await OrganizerStripeService.instance.openOnboardingLink(url);
    }
    return false; // caller debe esperar a que termine el onboarding
  }
}
