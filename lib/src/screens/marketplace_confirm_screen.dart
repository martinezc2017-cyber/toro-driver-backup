import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import '../services/delivery_service.dart';

/// Driver-side screen used at vendor pickup AND at buyer delivery.
/// Requires: 4-digit OTP from vendor (or buyer) + photo proof + auto-captured GPS.
/// Without all 3, the RPC rejects the action — anti-fraude.
class MarketplaceConfirmScreen extends StatefulWidget {
  final String orderId;
  final String mode; // 'pickup' or 'delivery'
  final String? vendorBusinessName;
  final String? buyerName;

  const MarketplaceConfirmScreen({
    super.key,
    required this.orderId,
    required this.mode,
    this.vendorBusinessName,
    this.buyerName,
  });

  @override
  State<MarketplaceConfirmScreen> createState() => _MarketplaceConfirmScreenState();
}

class _MarketplaceConfirmScreenState extends State<MarketplaceConfirmScreen> {
  final _otpCtrl = TextEditingController();
  final _picker = ImagePicker();
  final _service = DeliveryService();

  File? _photo;
  Position? _position;
  bool _capturingGps = false;
  bool _submitting = false;

  bool get _isPickup => widget.mode == 'pickup';
  String get _title => _isPickup ? 'Confirmar recogida' : 'Confirmar entrega';
  String get _subtitle => _isPickup
      ? 'En la tienda del vendedor'
      : 'En la direccion del comprador';
  String get _otpLabel => _isPickup
      ? 'Codigo de recogida (te lo da el vendedor)'
      : 'Codigo de entrega (te lo da el comprador)';
  String get _photoLabel => _isPickup
      ? 'Foto del producto que recoges'
      : 'Foto del producto entregado';
  Color get _accent => _isPickup ? Colors.orange : Colors.green;

  @override
  void initState() {
    super.initState();
    _captureGps();
  }

  @override
  void dispose() {
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _captureGps() async {
    setState(() => _capturingGps = true);
    try {
      final pos = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() {
        _position = pos;
        _capturingGps = false;
      });
    } catch (_) {
      if (mounted) setState(() => _capturingGps = false);
    }
  }

  Future<void> _takePhoto() async {
    final img = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1280,
      imageQuality: 75,
    );
    if (img != null && mounted) {
      setState(() => _photo = File(img.path));
    }
  }

  Future<void> _submit() async {
    final otp = _otpCtrl.text.trim();
    if (otp.length != 4) {
      _err('El codigo debe tener 4 digitos');
      return;
    }
    if (_photo == null) {
      _err('Toma la foto antes de confirmar');
      return;
    }
    if (_position == null) {
      _err('Esperando GPS — toca el icono para reintentar');
      return;
    }

    setState(() => _submitting = true);
    try {
      final bytes = await _photo!.readAsBytes();
      final url = await _service.uploadProofPhoto(
        orderId: widget.orderId,
        stage: widget.mode,
        bytes: bytes,
        lat: _position!.latitude,
        lng: _position!.longitude,
      );
      if (url == null) throw 'No se pudo subir la foto';

      final ok = _isPickup
          ? await _service.confirmMarketplacePickup(
              orderId: widget.orderId,
              otp: otp,
              photoUrl: url,
              lat: _position!.latitude,
              lng: _position!.longitude,
            )
          : await _service.confirmMarketplaceDelivery(
              orderId: widget.orderId,
              otp: otp,
              photoUrl: url,
              lat: _position!.latitude,
              lng: _position!.longitude,
            );
      if (!mounted) return;
      if (ok) {
        // CAPTURA del cobro con tarjeta al confirmar la ENTREGA (auth -> capture).
        // El PI se creo con capture_method:manual en el checkout; aqui entra el
        // dinero de verdad. Idempotente server-side (mp_capture_<order>); no-op
        // para cash/wallet. Sin esto, la auth caduca en 7 dias y NUNCA se cobra.
        if (!_isPickup) {
          await _service.captureMarketplacePayment(widget.orderId);
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isPickup ? 'Recogida confirmada' : 'Entrega confirmada'),
          backgroundColor: Colors.green,
        ));
        Navigator.pop(context, true);
      } else {
        // ok=false means geofence failed but action was logged
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Confirmado pero fuera de zona — flagged para revision'),
          backgroundColor: Colors.orange,
        ));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) _err(e.toString().replaceAll('PostgrestException', '').split(',').first);
    }
    if (mounted) setState(() => _submitting = false);
  }

  void _err(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        title: Text(_title, style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _accent.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    Icon(_isPickup ? Icons.shopping_bag : Icons.home,
                        color: _accent, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_subtitle,
                              style: TextStyle(color: _accent, fontSize: 13, fontWeight: FontWeight.w600)),
                          if (widget.vendorBusinessName != null && _isPickup)
                            Text(widget.vendorBusinessName!,
                                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          if (widget.buyerName != null && !_isPickup)
                            Text(widget.buyerName!,
                                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // OTP input
              Text(_otpLabel, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _otpCtrl,
                keyboardType: TextInputType.number,
                maxLength: 4,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 8),
                decoration: InputDecoration(
                  hintText: '0000',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.2), letterSpacing: 8),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Photo
              Text(_photoLabel, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _takePhoto,
                child: Container(
                  height: 220,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _photo == null ? Colors.white24 : Colors.green,
                      width: _photo == null ? 1 : 2,
                    ),
                    image: _photo != null
                        ? DecorationImage(image: FileImage(_photo!), fit: BoxFit.cover)
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: _photo == null
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_a_photo, color: _accent, size: 48),
                            const SizedBox(height: 8),
                            const Text('Toca para tomar foto',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            Text('Foto clara del producto',
                                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                          ],
                        )
                      : Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                              child: const Icon(Icons.refresh, color: Colors.white, size: 18),
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),

              // GPS
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      _position != null ? Icons.gps_fixed : Icons.gps_off,
                      color: _position != null ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _position != null
                            ? 'Ubicacion capturada (${_position!.latitude.toStringAsFixed(4)}, ${_position!.longitude.toStringAsFixed(4)})'
                            : (_capturingGps ? 'Capturando GPS...' : 'Sin GPS'),
                        style: TextStyle(
                          color: _position != null ? Colors.green : Colors.orange,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: _capturingGps
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.refresh, color: Colors.white60),
                      onPressed: _capturingGps ? null : _captureGps,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Submit
              ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _submitting
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                    : Text(_isPickup ? 'Confirmar recogida' : 'Confirmar entrega',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 12),
              Text(
                'Sin codigo, foto o GPS no se completa la accion. Es para tu proteccion y la del comprador.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
