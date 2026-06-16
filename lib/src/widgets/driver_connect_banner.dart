import 'package:flutter/material.dart';

import '../config/supabase_config.dart';
import '../services/stripe_connect_service.dart';

/// Recordatorio en el home del chofer: si todavía NO conectó su Stripe Connect
/// (no puede recibir payouts), muestra un banner → 1 toque → onboarding.
///
/// Mismo principio que el banner del vendedor/organizador: multiusuario, el chofer
/// recibe el recordatorio automático. Sin esto, el dinero de sus entregas queda
/// atrapado en el balance de TORO (le pasó a Carlos).
///
/// IMPORTANTE: `provider` DEBE casar con la cuenta donde corren los cobros
/// (MX = la cuenta del marketplace). Para choferes MX pasar 'mx'.
class DriverConnectBanner extends StatefulWidget {
  final String driverId;
  final String email;
  final String provider; // 'mx' | 'us'
  final EdgeInsetsGeometry margin;

  const DriverConnectBanner({
    super.key,
    required this.driverId,
    required this.email,
    this.provider = 'mx',
    this.margin = const EdgeInsets.fromLTRB(12, 0, 12, 12),
  });

  @override
  State<DriverConnectBanner> createState() => _DriverConnectBannerState();
}

class _DriverConnectBannerState extends State<DriverConnectBanner> with WidgetsBindingObserver {
  StripeAccountStatus? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // El usuario sale al navegador a hacer el KYC de Stripe y vuelve -> la app
    // se REANUDA. Re-consultamos el estado para que el banner se actualice SOLO,
    // sin que el usuario tenga que cerrar/reabrir la app.
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final s = await StripeConnectService.instance
          .getAccountStatus(widget.driverId, provider: widget.provider);
      if (mounted) setState(() => _status = s);
    } catch (_) {/* offline / sin cuenta → no mostrar hasta saber */}
  }

  Future<void> _activate() async {
    setState(() => _busy = true);
    try {
      // Email robusto: usa el de la cuenta (auth) si el del perfil viene vacio.
      // Stripe rechaza email vacio con "Invalid email address" -> el edge da 500
      // -> createConnectAccount retorna null -> el banner fallaba justo aqui.
      final authEmail = SupabaseConfig.client.auth.currentUser?.email ?? '';
      final email = widget.email.trim().isNotEmpty ? widget.email.trim() : authEmail;

      String? url = await StripeConnectService.instance.createConnectAccount(
        driverId: widget.driverId,
        email: email,
        provider: widget.provider,
      );
      // Fallback: si la cuenta ya existia y create no regreso link, pide solo el link.
      url ??= await StripeConnectService.instance
          .getOnboardingLink(widget.driverId, provider: widget.provider);

      if (url == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(email.isEmpty
                ? 'Tu perfil no tiene correo — agrega uno para conectar Stripe.'
                : 'No se pudo abrir el registro de Stripe. Intenta de nuevo.'),
          ));
        }
        return;
      }
      await StripeConnectService.instance.openOnboardingLink(url);
    } finally {
      if (mounted) setState(() => _busy = false);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    // Mostrar SOLO si el chofer aun NO conectó (cuenta no creada o incompleta).
    // Si ya envió sus datos (pending), ya está activa, o aún cargando/error -> NO
    // molestar. Asi el banner desaparece SOLO en cuanto conecta — incluido al
    // volver del navegador, por el refresh en didChangeAppLifecycleState.
    final needsConnect = s == StripeAccountStatus.notCreated ||
        s == StripeAccountStatus.incomplete ||
        s == StripeAccountStatus.notFound;
    if (!needsConnect) return const SizedBox.shrink();

    return Container(
      margin: widget.margin,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFB45309), Color(0xFFF59E0B)]),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        const Icon(Icons.account_balance, color: Colors.white, size: 28),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Conecta tu banco para recibir tus pagos',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, height: 1.15)),
            SizedBox(height: 3),
            Text('Sin esto, el dinero de tus entregas queda detenido y no te llega.',
                style: TextStyle(color: Colors.white, fontSize: 11.5, height: 1.2)),
          ]),
        ),
        const SizedBox(width: 10),
        ElevatedButton(
          onPressed: _busy ? null : _activate,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFFB45309),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          child: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Conectar', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }
}
