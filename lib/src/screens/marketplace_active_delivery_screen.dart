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
import '../services/background_location_service.dart';
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
  /// Full multi-order context from delivery_full_context RPC:
  /// `{delivery, orders: [order1, order2, ...]}`
  Map<String, dynamic>? _full;
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
      // Load both: legacy single-order context AND full multi-order context.
      // Multi-order context is the new canonical source; single-order kept for
      // back-compat with existing widgets until UI is fully migrated.
      final ctx = await _service.getMarketplaceDeliveryContext(widget.deliveryId);
      final full = await _service.getDeliveryFullContext(widget.deliveryId);
      if (!mounted) return;
      if (ctx == null || ctx['is_marketplace'] != true) {
        setState(() { _error = 'Delivery no encontrada'; _loading = false; });
        return;
      }
      setState(() {
        _ctx = ctx;
        _full = full;
        _loading = false;
      });
      _subscribeOrder();
      _syncBackgroundLocation();
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  /// True when this delivery has 2+ marketplace_orders bundled under it.
  bool get _isBundled {
    final orders = (_full?['orders'] as List?) ?? const [];
    return orders.length >= 2;
  }

  /// List of bundled orders sorted by created_at (already sorted from RPC).
  List<Map<String, dynamic>> get _orders {
    final orders = (_full?['orders'] as List?) ?? const [];
    return orders.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Build the sequenced stop list: vendor pickup(s) → buyer drop(s).
  /// For same-vendor bundles, we collapse to ONE pickup stop with all OTPs
  /// shown together, then ONE drop stop per order.
  List<_Stop> _buildStops() {
    final orders = _orders;
    final stops = <_Stop>[];
    if (orders.isEmpty) return stops;

    // Group by vendor_id for pickups
    final pickupGroups = <String, List<Map<String, dynamic>>>{};
    for (final o in orders) {
      final vid = (o['vendor']?['id'] ?? '') as String;
      pickupGroups.putIfAbsent(vid, () => []).add(o);
    }

    int seq = 1;
    pickupGroups.forEach((vid, group) {
      stops.add(_Stop(
        kind: 'pickup',
        sequence: seq++,
        label: group.first['vendor']?['business_name']?.toString() ?? 'Tienda',
        address: group.first['vendor_pickup_address']?.toString() ?? '',
        lat: (group.first['vendor_pickup_lat'] as num?)?.toDouble(),
        lng: (group.first['vendor_pickup_lng'] as num?)?.toDouble(),
        orders: group,
      ));
    });
    for (final o in orders) {
      stops.add(_Stop(
        kind: 'drop',
        sequence: seq++,
        label: o['buyer_name']?.toString() ?? 'Cliente',
        address: o['delivery_address']?.toString() ?? '',
        lat: (o['delivery_lat'] as num?)?.toDouble(),
        lng: (o['delivery_lng'] as num?)?.toDouble(),
        orders: [o],
      ));
    }
    return stops;
  }

  /// Ensures the BackgroundLocationService is broadcasting our GPS to
  /// deliveries.driver_lat/lng while this delivery is active (pre-completion).
  /// Stops broadcasting once the order is delivered/completed so the buyer's
  /// tracking map can resolve to the final delivered state.
  Future<void> _syncBackgroundLocation() async {
    final order = _ctx?['order'] as Map<String, dynamic>?;
    final vendor = _ctx?['vendor'] as Map<String, dynamic>?;
    final status = order?['status']?.toString() ?? '';
    final terminal = status == 'delivered' || status == 'completed'
        || status.startsWith('cancel') || status == 'failed';
    final ctl = BackgroundLocationController();
    if (terminal) {
      if (ctl.isRunning) await ctl.stopTracking();
      return;
    }
    final url = SupabaseConfig.supabaseUrl;
    final anon = SupabaseConfig.supabaseAnonKey;
    if (url.isEmpty || anon.isEmpty) return;
    await ctl.startTracking(
      deliveryId: widget.deliveryId,
      supabaseUrl: url,
      supabaseKey: anon,
      riderName: order?['buyer_name']?.toString()
          ?? vendor?['business_name']?.toString(),
      tableName: 'deliveries',
    );
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

  bool _canCancel() {
    final delivery = _ctx?['delivery'] as Map<String, dynamic>?;
    final ds = delivery?['status']?.toString() ?? '';
    return ds == 'pending' || ds == 'accepted';
  }

  Future<void> _cancelDelivery() async {
    // Reasons follow the canonical structured-cancellation pattern used by
    // Rappi/DiDi: short list, one-tap selection, optional free-text note.
    const reasons = <Map<String, String>>[
      {'code': 'vendor_closed', 'label': 'Tienda cerrada'},
      {'code': 'order_not_ready', 'label': 'Pedido no listo / esperé mucho'},
      {'code': 'wrong_address', 'label': 'Dirección errónea'},
      {'code': 'vehicle_problem', 'label': 'Problema con vehículo'},
      {'code': 'other', 'label': 'Otro motivo'},
    ];
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('¿Por qué cancelas?',
                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              for (final r in reasons)
                ListTile(
                  leading: const Icon(Icons.report_problem, color: Colors.orange),
                  title: Text(r['label']!, style: const TextStyle(color: Colors.white)),
                  onTap: () => Navigator.pop(context, r['code']),
                ),
              const Divider(color: _muted, height: 1),
              ListTile(
                leading: const Icon(Icons.close, color: _muted),
                title: const Text('No cancelar', style: TextStyle(color: _muted)),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    try {
      final res = await _service.cancelMarketplaceDelivery(
        widget.deliveryId, reason: picked,
      );
      if (!mounted) return;
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Cancelado: $picked. Buscando otro chofer.'),
          backgroundColor: Colors.orange,
        ));
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: ${e.toString().split(',').first}'),
        backgroundColor: Colors.red,
      ));
    }
  }

  /// Returns the orders that still need confirmation for the given stage.
  /// pickup → orders with status `driver_assigned` (or `ready_for_pickup`)
  /// delivery → orders with status `picked_up` or `in_transit`
  List<Map<String, dynamic>> _ordersPendingForStage(String mode) {
    final pendingStatuses = mode == 'pickup'
      ? const {'driver_assigned', 'ready_for_pickup', 'accepted_by_vendor'}
      : const {'picked_up', 'in_transit'};
    final source = _isBundled ? _orders : <Map<String, dynamic>>[
      if (_ctx?['order'] != null) Map<String, dynamic>.from(_ctx!['order'] as Map),
    ];
    return source.where((o) {
      final s = o['status']?.toString() ?? '';
      return pendingStatuses.contains(s);
    }).toList();
  }

  /// Opens MarketplaceConfirmScreen sequentially for each pending order at
  /// this stage. Each order has its own OTP/photo/geofence verification.
  /// If the driver bails on one, we stop (next confirm will trigger on next tap).
  Future<void> _openConfirm(String mode) async {
    final pending = _ordersPendingForStage(mode);
    if (pending.isEmpty) return;
    final vendor = _ctx?['vendor'] as Map<String, dynamic>?;
    for (var i = 0; i < pending.length; i++) {
      final o = pending[i];
      final orderId = o['id'] as String;
      final vendorName = (o['vendor']?['business_name'] as String?)
          ?? vendor?['business_name']?.toString();
      final buyerName = o['buyer_name']?.toString();
      // El chofer LLEGÓ a recoger -> avisar al vendedor (con el PIN en el push)
      // para que entregue el paquete y dé el código. Solo en la etapa de recogida.
      if (mode == 'pickup') {
        await _service.notifyVendorDriverArrived(orderId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Avisamos a la tienda que llegaste — pídeles el código de recogida'),
            backgroundColor: Color(0xFFF97316),
            duration: Duration(seconds: 3),
          ));
        }
      }
      if (_isBundled && mounted) {
        // Quick info banner so driver knows which package they're confirming
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Paquete ${i + 1} de ${pending.length} · ${mode == 'pickup' ? "recoger" : "entregar"} a ${buyerName ?? "cliente"}'),
          backgroundColor: const Color(0xFFFFD700),
          duration: const Duration(seconds: 2),
        ));
      }
      final result = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => MarketplaceConfirmScreen(
          orderId: orderId,
          mode: mode,
          vendorBusinessName: vendorName,
          buyerName: buyerName,
        ),
      ));
      if (result != true) break;
      await _load();
      if (!mounted) return;
    }
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
          // Cancel is allowed only BEFORE pickup (deliveries.status in pending|accepted).
          // After in_progress the driver has the goods → support case, not self-cancel.
          if (_canCancel())
            IconButton(
              icon: const Icon(Icons.cancel_outlined, color: Colors.orange),
              tooltip: 'Cancelar entrega',
              onPressed: _cancelDelivery,
            ),
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

        // Bundle banner — visible only when 2+ orders share this delivery
        if (_isBundled) ...[
          _bundleBanner(),
          const SizedBox(height: 12),
          _bundleStopList(),
          const SizedBox(height: 16),
        ],

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

  /// Yellow banner shown when 2+ orders are bundled under this delivery.
  /// Reminds the driver to collect/verify all OTPs in sequence.
  Widget _bundleBanner() {
    final n = _orders.length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _yellow.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _yellow, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2, color: _yellow, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PEDIDOS COMBINADOS · $n paquetes',
                  style: const TextStyle(color: _yellow, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1)),
                const SizedBox(height: 2),
                const Text('Lleva cada uno por separado — tienen PIN distinto',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Per-order quick reference: 1 row per bundled order with its PIN status.
  /// Shown directly under the bundle banner so driver always sees the OTPs
  /// pending. Done orders are dimmed.
  Widget _bundleStopList() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _orders.length; i++) ...[
            if (i > 0) const Divider(color: Color(0xFF2A2A2A), height: 16),
            _orderRow(i + 1, _orders[i]),
          ],
        ],
      ),
    );
  }

  Widget _orderRow(int n, Map<String, dynamic> o) {
    final status = o['status']?.toString() ?? '';
    final isDone = status == 'delivered' || status == 'completed';
    final isPicked = status == 'picked_up' || status == 'in_transit';
    final items = (o['items'] as List?) ?? const [];
    final summary = items.map((e) {
      final m = e as Map;
      return '${m['quantity']}× ${m['product_name_snapshot']}';
    }).join(', ');
    final buyer = o['buyer_name']?.toString() ?? 'Cliente';
    final dim = isDone ? 0.4 : 1.0;
    return Opacity(
      opacity: dim,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: isDone ? _green : (isPicked ? _yellow : _orange),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: isDone
                ? const Icon(Icons.check, color: Colors.black, size: 16)
                : Text('$n', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Paquete $n · para $buyer',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                Text(summary,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!isDone) Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(isPicked ? 'PIN entrega' : 'PIN recoger',
                style: const TextStyle(color: _muted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              Text(isPicked
                ? (o['delivery_otp']?.toString() ?? '----')
                : (o['pickup_otp']?.toString() ?? '----'),
                style: const TextStyle(color: _yellow, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
            ],
          ),
        ],
      ),
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

/// One stop on the driver's sequenced route. Either a vendor pickup or a buyer drop.
/// `orders` holds the marketplace_orders rows that resolve at this stop (1 for drops;
/// 1..N for pickups when multiple orders are bundled at the same vendor).
class _Stop {
  final String kind; // 'pickup' | 'drop'
  final int sequence;
  final String label;
  final String address;
  final double? lat;
  final double? lng;
  final List<Map<String, dynamic>> orders;
  _Stop({
    required this.kind,
    required this.sequence,
    required this.label,
    required this.address,
    required this.lat,
    required this.lng,
    required this.orders,
  });
}
