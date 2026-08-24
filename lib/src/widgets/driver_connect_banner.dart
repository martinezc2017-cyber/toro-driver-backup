import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import '../config/supabase_config.dart';
import '../services/stripe_connect_service.dart';

/// Recordatorio en el home del chofer: si todavía NO conectó su Stripe Connect
/// (no puede recibir payouts), muestra un banner → 1 toque → onboarding.
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
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final s = await StripeConnectService.instance
          .getAccountStatus(widget.driverId, provider: widget.provider);
      if (mounted) setState(() => _status = s);
    } catch (_) {}
  }

  Future<void> _activate() async {
    setState(() => _busy = true);
    try {
      final authEmail = SupabaseConfig.client.auth.currentUser?.email ?? '';
      final email = widget.email.trim().isNotEmpty ? widget.email.trim() : authEmail;

      final result = await StripeConnectService.instance.createConnectAccount(
        driverId: widget.driverId,
        email: email,
        provider: widget.provider,
      );
      String? url = result.url;
      url ??= await StripeConnectService.instance
          .getOnboardingLink(widget.driverId, provider: widget.provider);

      if (url == null) {
        if (mounted) {
          final errorDetail = result.error ?? '';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(email.isEmpty
                ? 'banner.no_email_stripe'.tr()
                : 'banner.stripe_error'.tr(namedArgs: {'error': errorDetail})),
            backgroundColor: Colors.red[700],
            duration: const Duration(seconds: 6),
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
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('banner.connect_bank_title'.tr(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, height: 1.15)),
            const SizedBox(height: 3),
            Text('banner.connect_bank_subtitle'.tr(),
                style: const TextStyle(color: Colors.white, fontSize: 11.5, height: 1.2)),
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
              : Text('banner.connect_btn'.tr(), style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }
}
