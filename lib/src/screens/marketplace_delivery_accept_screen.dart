// MarketplaceDeliveryAcceptScreen — driver-side accept screen for marketplace
// deliveries. Triggered by FCM push (type=new_ride, service_type=marketplace).
// Reads canonical fields from `deliveries` + `marketplace_orders` + `vendors`.
// Driver earnings come from deliveries.driver_earnings — NOT recomputed.

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/delivery_service.dart';
import 'marketplace_active_delivery_screen.dart';

class MarketplaceDeliveryAcceptScreen extends StatefulWidget {
  final String deliveryId;
  const MarketplaceDeliveryAcceptScreen({super.key, required this.deliveryId});

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
    if (created == null) return;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed = DateTime.now().difference(created));
    });
    _elapsed = DateTime.now().difference(created);
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      final res = await _service.acceptMarketplaceDelivery(widget.deliveryId);
      if (!mounted) return;
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Entrega aceptada'),
          backgroundColor: _green,
        ));
        // Navigate to active delivery flow
        if (mounted) {
          Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => MarketplaceActiveDeliveryScreen(
              deliveryId: widget.deliveryId,
            ),
          ));
        }
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
        const SizedBox(height: 16),
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
