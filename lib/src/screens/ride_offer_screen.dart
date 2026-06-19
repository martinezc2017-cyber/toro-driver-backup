// RideOfferScreen — oferta PERSISTENTE a pantalla completa para el chofer en
// rides / paquetes / carpool (marketplace tiene su propia pantalla). Se abre por
// el push FCM (type=new_ride). Antes el ride normal solo mostraba un banner
// transitorio que se perdia; ahora aparece esta oferta con Aceptar/Rechazar +
// cuenta regresiva, independiente de la lista de disponibles.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ride_model.dart';
import '../services/ride_service.dart';
import '../providers/ride_provider.dart';
import '../providers/driver_provider.dart';
import '../utils/money_format.dart';

class RideOfferScreen extends StatefulWidget {
  final String rideId;
  const RideOfferScreen({super.key, required this.rideId});

  @override
  State<RideOfferScreen> createState() => _RideOfferScreenState();
}

class _RideOfferScreenState extends State<RideOfferScreen> {
  static const _bg = Color(0xFF0A0A0A);
  static const _card = Color(0xFF161616);
  static const _cyan = Color(0xFF22D3EE);
  static const _green = Color(0xFF22C55E);
  static const _red = Color(0xFFEF4444);
  static const _muted = Color(0xFF8B9099);
  static const _offerTimeoutSec = 30;

  final _service = RideService();
  RideModel? _ride;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Timer? _timer;
  int _secsLeft = _offerTimeoutSec;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final ride = await _service.getRide(widget.rideId);
      if (!mounted) return;
      if (ride == null) {
        setState(() {
          _error = 'El viaje ya no está disponible';
          _loading = false;
        });
        return;
      }
      setState(() {
        _ride = ride;
        _loading = false;
      });
      _startCountdown();
    } catch (e) {
      if (mounted) setState(() { _error = 'Error: $e'; _loading = false; });
    }
  }

  void _startCountdown() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _secsLeft--);
      if (_secsLeft <= 0) {
        t.cancel();
        if (mounted) Navigator.of(context).maybePop(); // expira -> se re-ofrece a otro
      }
    });
  }

  Future<void> _accept() async {
    if (_busy || _ride == null) return;
    setState(() => _busy = true);
    final driverId = context.read<DriverProvider>().driver?.id;
    if (driverId == null) {
      setState(() => _busy = false);
      return;
    }
    final ok = await context.read<RideProvider>().acceptRide(_ride!.id, driverId);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true); // el home/mapa toma el viaje activo
    } else {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: _red,
        content: Text(context.read<RideProvider>().error ?? 'No se pudo aceptar (otro chofer lo tomó)'),
      ));
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _reject() async {
    if (_busy) return;
    final driverId = context.read<DriverProvider>().driver?.id;
    if (driverId != null && _ride != null) {
      try { await context.read<RideProvider>().dismissRide(_ride!.id, driverId); } catch (_) {}
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  ({String label, IconData icon, Color color}) _typeMeta(RideType t) {
    switch (t) {
      case RideType.package:
        return (label: 'Paquete', icon: Icons.inventory_2, color: const Color(0xFF78909C));
      case RideType.carpool:
        return (label: 'Carpool', icon: Icons.groups, color: const Color(0xFF42A5F5));
      case RideType.marketplace:
        return (label: 'Pedido', icon: Icons.shopping_bag, color: const Color(0xFFFFD700));
      case RideType.passenger:
        return (label: 'Viaje', icon: Icons.person, color: _cyan);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cc = context.read<DriverProvider>().driver?.countryCode ?? 'MX';
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _cyan))
            : _error != null
                ? _buildError()
                : _buildOffer(cc),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.directions_car_outlined, color: _muted, size: 48),
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Cerrar', style: TextStyle(color: _cyan)),
          ),
        ],
      ),
    );
  }

  Widget _buildOffer(String cc) {
    final ride = _ride!;
    final meta = _typeMeta(ride.type);
    final isCash = ride.paymentMethod == PaymentMethod.cash;
    final pct = _secsLeft / _offerTimeoutSec;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: tipo + cuenta regresiva
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: meta.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(meta.icon, color: meta.color, size: 16),
                  const SizedBox(width: 6),
                  Text(meta.label.toUpperCase(),
                      style: TextStyle(color: meta.color, fontSize: 12, fontWeight: FontWeight.w800)),
                ]),
              ),
              const Spacer(),
              SizedBox(
                width: 40, height: 40,
                child: Stack(alignment: Alignment.center, children: [
                  CircularProgressIndicator(
                    value: pct, strokeWidth: 3,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation(_secsLeft <= 8 ? _red : _cyan),
                  ),
                  Text('$_secsLeft', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Ganancia (lo importante)
          Center(
            child: Column(children: [
              Text(
                isCash
                    ? 'Cobrar ${formatMoney(ride.fare, country: cc)}'
                    : formatMoney(ride.driverEarnings, country: cc),
                style: TextStyle(
                    color: isCash ? _green : _cyan, fontSize: 38, fontWeight: FontWeight.w900),
              ),
              Text(isCash ? 'en efectivo' : 'tu ganancia',
                  style: const TextStyle(color: _muted, fontSize: 13)),
            ]),
          ),
          const SizedBox(height: 18),

          // Pickup -> Dropoff
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              _addrRow(_green, ride.pickupLocation.address ?? 'Punto de recogida'),
              const Padding(
                padding: EdgeInsets.only(left: 5),
                child: SizedBox(height: 18, child: VerticalDivider(color: Colors.white24, width: 1, thickness: 1)),
              ),
              _addrRow(_red, ride.dropoffLocation.address ?? 'Destino'),
            ]),
          ),
          const SizedBox(height: 14),

          // Distancia + tiempo + pago
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _chip(Icons.route, formatDistance(ride.distanceKm, country: cc)),
            const SizedBox(width: 10),
            _chip(Icons.schedule, '~${ride.estimatedMinutes} min'),
            const SizedBox(width: 10),
            _chip(isCash ? Icons.payments_outlined : Icons.credit_card, isCash ? 'Efectivo' : 'Tarjeta'),
          ]),

          const Spacer(),

          // Botones
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _reject,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Rechazar', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _busy ? null : _accept,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('ACEPTAR', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _addrRow(Color dot, String text) {
    return Row(children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
      const SizedBox(width: 12),
      Expanded(
        child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 14)),
      ),
    ]);
  }

  Widget _chip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: _muted, size: 14),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ]),
    );
  }
}
