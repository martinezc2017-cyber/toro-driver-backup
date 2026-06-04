// MarketplaceActiveDeliveryScreen — driver flow AFTER accepting.
// Two stages:
//   1. Driving to vendor → "He llegado, recoger" → MarketplaceConfirmScreen (pickup mode)
//   2. Driving to buyer  → "He llegado, entregar" → MarketplaceConfirmScreen (delivery mode)
//
// Reads canonical state from `marketplace_orders.status`:
//   - driver_assigned → stage 1 (pickup)
//   - picked_up / in_transit → stage 2 (delivery)
//   - delivered / completed → finished
//
// Tap on phone or address opens external maps/dialer.
// All actions logged via realtime subscription + app_logs (server-side RPCs).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../services/delivery_service.dart';
import 'marketplace_confirm_screen.dart';

class MarketplaceActiveDeliveryScreen extends StatefulWidget {
  final String deliveryId;
  const MarketplaceActiveDeliveryScreen({super.key, required this.deliveryId});

  @override
  State<MarketplaceActiveDeliveryScreen> createState() => _State();
}

class _State extends State<MarketplaceActiveDeliveryScreen> {
  static const _bg = Color(0xFF0A0A0A);
  static const _card = Color(0xFF161616);
  static const _yellow = Color(0xFFFFD700);
  static const _green = Color(0xFF22C55E);
  static const _orange = Color(0xFFF97316);
  static const _muted = Color(0xFF8B9099);

  final _service = DeliveryService();
  Map<String, dynamic>? _ctx;
  bool _loading = true;
  String? _error;
  RealtimeChannel? _orderChannel;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _orderChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final ctx = await _service.getMarketplaceDeliveryContext(widget.deliveryId);
      if (!mounted) return;
      if (ctx == null || ctx['is_marketplace'] != true) {
        setState(() { _error = 'Delivery no encontrada'; _loading = false; });
        return;
      }
      setState(() { _ctx = ctx; _loading = false; });
      _subscribeOrder();
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _subscribeOrder() {
    final order = _ctx?['order'] as Map<String, dynamic>?;
    if (order == null) return;
    final orderId = order['id'] as String;
    _orderChannel = SupabaseConfig.client
        .channel('mp_active_$orderId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'marketplace_orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: orderId,
          ),
          callback: (_) => _load(),
        )
        ..subscribe();
  }

  Future<void> _openMaps(double? lat, double? lng, String address) async {
    if (lat == null || lng == null) return;
    final uri = Uri.parse('geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(address)})');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      final fallback = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
      await launchUrl(fallback, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _callPhone(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openConfirm(String mode) async {
    final order = _ctx!['order'] as Map<String, dynamic>;
    final vendor = _ctx?['vendor'] as Map<String, dynamic>?;
    final result = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => MarketplaceConfirmScreen(
        orderId: order['id'] as String,
        mode: mode,
        vendorBusinessName: vendor?['business_name']?.toString(),
        buyerName: order['buyer_name']?.toString(),
      ),
    ));
    if (result == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: const Text('Entrega activa', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _yellow))
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white)))
              : _renderBody(),
    );
  }

  Widget _renderBody() {
    final delivery = _ctx!['delivery'] as Map<String, dynamic>;
    final order = _ctx!['order'] as Map<String, dynamic>?;
    final vendor = _ctx!['vendor'] as Map<String, dynamic>?;
    final items = (_ctx!['items'] as List?) ?? const [];
    final status = order?['status']?.toString() ?? delivery['status']?.toString() ?? '';

    final isPickupStage = status == 'driver_assigned' || status == 'accepted_by_vendor';
    final isDeliveryStage = status == 'picked_up' || status == 'in_transit';
    final isDone = status == 'delivered' || status == 'completed';

    final driverEarn = (delivery['driver_earnings'] as num?)?.toDouble() ?? 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Stage banner
        _stageBanner(isPickupStage, isDeliveryStage, isDone),
        const SizedBox(height: 16),

        // Earnings (compact)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _yellow.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _yellow.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.account_balance_wallet, color: _yellow, size: 22),
              const SizedBox(width: 10),
              const Text('Tu pago:', style: TextStyle(color: Colors.white70)),
              const Spacer(),
              Text('\$${driverEarn.toStringAsFixed(0)}',
                style: const TextStyle(color: _yellow, fontSize: 20, fontWeight: FontWeight.w900)),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // PICKUP card (always visible; emphasized when isPickupStage)
        _addressCard(
          stageNum: 1,
          stageActive: isPickupStage,
          stageDone: !isPickupStage && (isDeliveryStage || isDone),
          icon: Icons.store,
          color: _orange,
          title: 'RECOGER EN',
          name: vendor?['business_name']?.toString() ?? 'Tienda',
          address: delivery['pickup_address']?.toString() ?? '',
          lat: (delivery['pickup_lat'] as num?)?.toDouble(),
          lng: (delivery['pickup_lng'] as num?)?.toDouble(),
        ),
        const SizedBox(height: 12),

        if (isPickupStage)
          SizedBox(
            height: 60,
            child: ElevatedButton.icon(
              onPressed: () => _openConfirm('pickup'),
              icon: const Icon(Icons.qr_code_2, color: Colors.black, size: 26),
              label: const Text('LLEGUÉ — RECOGER',
                style: TextStyle(color: Colors.black, fontSize: 17, fontWeight: FontWeight.w900)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),

        if (!isPickupStage) const SizedBox(height: 16),
        if (!isPickupStage)
          _addressCard(
            stageNum: 2,
            stageActive: isDeliveryStage,
            stageDone: isDone,
            icon: Icons.location_on,
            color: _green,
            title: 'ENTREGAR EN',
            name: order?['buyer_name']?.toString() ?? 'Cliente',
            address: delivery['destination_address']?.toString() ?? '',
            subtitle: order?['delivery_notes']?.toString(),
            phone: order?['buyer_phone']?.toString(),
            lat: (delivery['destination_lat'] as num?)?.toDouble(),
            lng: (delivery['destination_lng'] as num?)?.toDouble(),
          ),
        const SizedBox(height: 12),
        if (isDeliveryStage)
          SizedBox(
            height: 60,
            child: ElevatedButton.icon(
              onPressed: () => _openConfirm('delivery'),
              icon: const Icon(Icons.check_circle, color: Colors.white, size: 26),
              label: const Text('LLEGUÉ — ENTREGAR',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        if (isDone)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _green, width: 2),
            ),
            child: Column(
              children: [
                const Icon(Icons.celebration, color: _green, size: 56),
                const SizedBox(height: 8),
                const Text('ENTREGA COMPLETADA',
                  style: TextStyle(color: _green, fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text('Tu pago: \$${driverEarn.toStringAsFixed(0)} se liquidará pronto',
                  style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    style: ElevatedButton.styleFrom(backgroundColor: _yellow, foregroundColor: Colors.black),
                    child: const Text('FINALIZAR', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 20),

        // Package list (always visible)
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
                        Text('${m['quantity']}× ',
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
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _stageBanner(bool pickup, bool delivery, bool done) {
    final (color, text) = done
        ? (_green, 'PASO 3 · ENTREGADO')
        : pickup
            ? (_orange, 'PASO 1 · RECOGER EN TIENDA')
            : delivery
                ? (_green, 'PASO 2 · ENTREGAR AL CLIENTE')
                : (_muted, 'EN PROCESO');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 2),
      ),
      child: Center(
        child: Text(text,
          style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
      ),
    );
  }

  Widget _addressCard({
    required int stageNum,
    required bool stageActive,
    required bool stageDone,
    required IconData icon,
    required Color color,
    required String title,
    required String name,
    required String address,
    String? subtitle,
    String? phone,
    double? lat,
    double? lng,
  }) {
    final accent = stageDone ? _green : (stageActive ? color : _muted);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: stageActive ? 0.8 : 0.2), width: stageActive ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: stageDone
                    ? const Icon(Icons.check, color: _green, size: 22)
                    : Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                      style: TextStyle(
                        color: accent, fontSize: 11,
                        fontWeight: FontWeight.w800, letterSpacing: 1.5,
                      )),
                    const SizedBox(height: 4),
                    Text(name,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(address, style: const TextStyle(color: _muted, fontSize: 13)),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('"$subtitle"',
                        style: const TextStyle(color: Colors.white70, fontSize: 12, fontStyle: FontStyle.italic)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (lat != null || phone != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (lat != null && lng != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openMaps(lat, lng, address),
                      icon: const Icon(Icons.map, color: Colors.white),
                      label: const Text('Maps', style: TextStyle(color: Colors.white)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF2A2A2A)),
                      ),
                    ),
                  ),
                if (lat != null && phone != null) const SizedBox(width: 8),
                if (phone != null && phone.isNotEmpty)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _callPhone(phone),
                      icon: const Icon(Icons.phone, color: Colors.white),
                      label: const Text('Llamar', style: TextStyle(color: Colors.white)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF2A2A2A)),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
