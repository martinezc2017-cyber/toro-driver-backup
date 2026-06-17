// MarketplaceDeliveryAcceptScreen — driver-side accept screen for marketplace
// deliveries. Triggered by FCM push (type=new_ride, service_type=marketplace).
// Reads canonical fields from `deliveries` + `marketplace_orders` + `vendors`.
// Driver earnings come from deliveries.driver_earnings — NOT recomputed.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../config/supabase_config.dart';
import '../services/delivery_service.dart';

class MarketplaceDeliveryAcceptScreen extends StatefulWidget {
  final String deliveryId;
  /// True when this offer arrived as a stacked/on-the-way offer to a driver
  /// already holding another delivery. Renders a green "extra ingreso" banner
  /// and a shorter countdown.
  final bool isStackedOffer;
  const MarketplaceDeliveryAcceptScreen({
    super.key,
    required this.deliveryId,
    this.isStackedOffer = false,
  });

  @override
  State<MarketplaceDeliveryAcceptScreen> createState() => _State();
}

class _State extends State<MarketplaceDeliveryAcceptScreen> {
  static const _bg = Color(0xFF0A0A0A);
  static const _card = Color(0xFF161616);
  static const _yellow = Color(0xFFFFD700);
  static const _green = Color(0xFF22C55E);
  static const _muted = Color(0xFF8B9099);

  final _service = DeliveryService();
  Map<String, dynamic>? _ctx;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Timer? _countdownTimer;
  Duration _elapsed = Duration.zero;
  // Driver must answer within this many seconds. After that the offer
  // expires and the screen auto-closes so the dispatch can re-fire to
  // the next eligible driver.
  static const _offerTimeoutSec = 30;
  int _secsLeft = _offerTimeoutSec;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final ctx = await _service.getMarketplaceDeliveryContext(widget.deliveryId);
      if (!mounted) return;
      if (ctx == null) {
        setState(() { _error = 'Delivery no encontrada'; _loading = false; });
        return;
      }
      if (ctx['is_marketplace'] != true) {
        setState(() { _error = 'No es un pedido marketplace'; _loading = false; });
        return;
      }
      setState(() { _ctx = ctx; _loading = false; });
      _startCountdown();
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _startCountdown() {
    final created = DateTime.tryParse(_ctx?['delivery']?['created_at'] ?? '');
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        if (created != null) _elapsed = DateTime.now().difference(created);
        if (_secsLeft > 0) _secsLeft--;
      });
      if (_secsLeft == 0) {
        t.cancel();
        _autoExpire();
      }
    });
    if (created != null) _elapsed = DateTime.now().difference(created);
  }

  void _autoExpire() {
    debugPrint('🔔 marketplace offer ${widget.deliveryId} expired after ${_offerTimeoutSec}s');
    // Best-effort server-side log (the cron will also catch unanswered offers)
    SupabaseConfig.client.from('app_logs').insert({
      'level': 'info',
      'source': 'driver_marketplace',
      'event': 'offer_expired',
      'context': {'delivery_id': widget.deliveryId, 'seconds': _offerTimeoutSec},
      'app_role': 'driver',
    }).then((_) {}).catchError((_) {});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Oferta expirada — pasa al siguiente chofer'),
      backgroundColor: Colors.orange,
    ));
    Navigator.of(context).maybePop();
  }

  Future<void> _accept() async {
    _countdownTimer?.cancel();
    setState(() => _busy = true);
    try {
      final res = await _service.acceptMarketplaceDelivery(widget.deliveryId);
      if (!mounted) return;
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Entrega aceptada'),
          backgroundColor: _green,
        ));
        // Volver al home: el viaje activo se navega en el MISMO mapa (tab 1),
        // igual que cualquier otro viaje (NavigationMapScreen).
        if (mounted) Navigator.of(context).maybePop();
      } else {
        _err('No se pudo aceptar');
      }
    } catch (e) {
      _err(e.toString().split(',').first);
    }
    if (mounted) setState(() => _busy = false);
  }

  void _reject() {
    Navigator.of(context).maybePop();
  }

  void _err(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: const Text('Nueva entrega', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _yellow))
          : _error != null
              ? _renderError()
              : _renderContent(),
    );
  }

  Widget _renderError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 64),
          const SizedBox(height: 16),
          Text(_error ?? '', style: const TextStyle(color: Colors.white, fontSize: 16),
            textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    ),
  );

  Widget _renderContent() {
    final delivery = _ctx!['delivery'] as Map<String, dynamic>;
    final order = _ctx!['order'] as Map<String, dynamic>?;
    final vendor = _ctx!['vendor'] as Map<String, dynamic>?;
    final items = (_ctx!['items'] as List?) ?? const [];

    final driverEarn = (delivery['driver_earnings'] as num?)?.toDouble() ?? 0;
    final deliveryFee = (delivery['estimated_price'] as num?)?.toDouble() ?? 0;
    final mins = _elapsed.inMinutes;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.isStackedOffer) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _green, width: 1.5),
            ),
            child: const Row(
              children: [
                Icon(Icons.add_road, color: _green, size: 24),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('OFERTA EXTRA EN TU RUTA',
                        style: TextStyle(color: _green, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1)),
                      Text('Recoge este pedido también — sin desviarte mucho',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        // Earnings hero
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_yellow, Color(0xFFFFB300)],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tu pago por esta entrega',
                style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('\$${driverEarn.toStringAsFixed(0)}',
                style: const TextStyle(
                  color: Colors.black, fontSize: 56, fontWeight: FontWeight.w900,
                  height: 1.0,
                )),
              Text('de \$${deliveryFee.toStringAsFixed(0)} delivery total',
                style: const TextStyle(color: Colors.black54, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Offer-expiration countdown (auto-decline if vendor doesn't act)
        _offerCountdownChip(),
        const SizedBox(height: 12),
        // Vendor / Pickup
        _sectionCard(
          icon: Icons.store,
          iconColor: Colors.orange,
          title: 'RECOGER EN',
          name: vendor?['business_name']?.toString() ?? 'Tienda',
          address: delivery['pickup_address']?.toString() ?? '',
        ),
        const SizedBox(height: 12),
        // Buyer / Drop
        _sectionCard(
          icon: Icons.location_on,
          iconColor: _green,
          title: 'ENTREGAR EN',
          name: order?['buyer_name']?.toString() ?? 'Cliente',
          address: delivery['destination_address']?.toString() ?? '',
          subtitle: (order?['delivery_notes']?.toString().isNotEmpty ?? false)
              ? '"${order!['delivery_notes']}"' : null,
        ),
        const SizedBox(height: 12),
        // Items
        if (items.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2A2A2A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('PAQUETE',
                  style: TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                const SizedBox(height: 8),
                ...items.map((i) {
                  final m = i as Map<String, dynamic>;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Text('${m['quantity']}×  ',
                          style: const TextStyle(color: _yellow, fontWeight: FontWeight.w800)),
                        Expanded(child: Text(m['product_name_snapshot']?.toString() ?? '',
                          style: const TextStyle(color: Colors.white))),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        const SizedBox(height: 12),
        // Meta info
        Row(
          children: [
            Expanded(child: _metaChip(Icons.timer, '$mins min en cola')),
            const SizedBox(width: 8),
            Expanded(child: _metaChip(
              order?['payment_method'] == 'cash' ? Icons.payments : Icons.credit_card,
              order?['payment_method']?.toString().toUpperCase() ?? '',
            )),
          ],
        ),
        const SizedBox(height: 24),
        // Big ACEPTAR
        SizedBox(
          height: 72,
          child: ElevatedButton.icon(
            onPressed: _busy ? null : _accept,
            icon: _busy
                ? const SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3),
                  )
                : const Icon(Icons.check_circle, color: Colors.black, size: 28),
            label: Text(_busy ? 'Aceptando...' : 'ACEPTAR ENTREGA',
              style: const TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.w900)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _yellow,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _busy ? null : _reject,
          child: const Text('Rechazar', style: TextStyle(color: _muted, fontSize: 16)),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _offerCountdownChip() {
    final isUrgent = _secsLeft <= 10;
    final color = isUrgent ? Colors.red : _yellow;
    final pct = _secsLeft / _offerTimeoutSec;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: isUrgent ? 2 : 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timer, color: color, size: 22),
              const SizedBox(width: 8),
              Text(
                isUrgent ? 'EXPIRA EN ${_secsLeft}s' : 'Responde en $_secsLeft s',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: isUrgent ? 18 : 15,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Text(
                '${(_offerTimeoutSec - _secsLeft)}/${_offerTimeoutSec}s',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String name,
    required String address,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                  style: TextStyle(
                    color: iconColor, fontSize: 11,
                    fontWeight: FontWeight.w800, letterSpacing: 1.5,
                  )),
                const SizedBox(height: 4),
                Text(name,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                Text(address, style: const TextStyle(color: _muted, fontSize: 13)),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12, fontStyle: FontStyle.italic)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: _muted, size: 16),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }
}
