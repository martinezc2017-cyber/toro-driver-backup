import 'dart:io';
import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/delivery_service.dart';
import '../services/location_service.dart';

/// Driver-side screen used at vendor pickup AND at buyer delivery.
/// Requires: 4-digit OTP from vendor (or buyer) + photo proof + auto-captured GPS.
/// Without all 3, the RPC rejects the action — anti-fraude.
class MarketplaceConfirmScreen extends StatefulWidget {
  final String orderId;
  final String mode; // 'pickup' or 'delivery'
  final String? vendorBusinessName;
  final String? buyerName;
  final String? address; // direccion real (recogida o entrega)

  const MarketplaceConfirmScreen({
    super.key,
    required this.orderId,
    required this.mode,
    this.vendorBusinessName,
    this.buyerName,
    this.address,
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

  // Contacto de la contraparte (vendor en recogida, comprador en entrega).
  String? _contactName;
  String? _contactPhone;
  bool _noShowBusy = false;

  // TORO te lo compra: en la recogida no hay PIN de vendedor; el chofer compra, sube el ticket y se le reembolsa al
  // entregar. Se detecta del propio pedido (source = 'tienda') para no cambiar a quien abre esta pantalla.
  final _montoCtrl = TextEditingController();
  bool _teLoCompra = false;
  double? _pagarEnTienda;
  double? _subtotal;
  String? _deliveryId;
  bool _sinExistenciaBusy = false;

  bool get _isPickup => widget.mode == 'pickup';
  bool get _compra => _isPickup && _teLoCompra;
  String get _title => _compra
      ? 'te_lo_compra.titulo_recoger'.tr()
      : (_isPickup ? 'marketplace.confirm_pickup'.tr() : 'marketplace.confirm_delivery'.tr());
  String get _subtitle => _compra
      ? 'te_lo_compra.compra_en'.tr()
      : (_isPickup ? 'marketplace.at_vendor_store'.tr() : 'marketplace.at_buyer_address'.tr());
  String get _otpLabel => _isPickup
      ? 'marketplace.pickup_code'.tr()
      : 'marketplace.delivery_code'.tr();
  String get _photoLabel => _compra
      ? 'te_lo_compra.foto_ticket'.tr()
      : (_isPickup ? 'marketplace.photo_pickup'.tr() : 'marketplace.photo_delivery'.tr());
  Color get _accent => _isPickup ? Colors.orange : Colors.green;

  @override
  void initState() {
    super.initState();
    _captureGps();
    _loadContacts();
    if (_isPickup) _loadTeLoCompra();
  }

  Future<void> _loadTeLoCompra() async {
    final info = await _service.teLoCompraInfo(widget.orderId);
    if (!mounted || info == null || info['source'] != 'tienda') return;
    setState(() {
      _teLoCompra = true;
      _pagarEnTienda = (info['vendor_payout'] as num?)?.toDouble();
      _subtotal = (info['subtotal'] as num?)?.toDouble();
      _deliveryId = info['delivery_id']?.toString();
    });
  }

  /// No había en la tienda: se cancela el pedido y se suelta la tarjeta del comprador (no paga nada). Hay que estar en
  /// la tienda; lo que no había queda fuera de venta unos días y TORO le paga la vuelta al chofer.
  Future<void> _noHay() async {
    final notaCtrl = TextEditingController();
    final articulos = await _service.articulosDelPedido(widget.orderId);
    if (!mounted) return;
    // Varias cosas: cuáles no había (las que sí, siguen a la venta).
    final faltan = {for (final a in articulos) '${a['product_id']}'};
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          backgroundColor: const Color(0xFF161616),
          title: Text('te_lo_compra.no_hay_titulo'.tr(), style: const TextStyle(color: AppColors.textPrimary)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('te_lo_compra.no_hay_explica'.tr(), style: const TextStyle(color: AppColors.textSecondary)),
                if (articulos.length > 1) ...[
                  const SizedBox(height: 12),
                  Text('te_lo_compra.no_hay_cuales'.tr(),
                      style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                  for (final a in articulos)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: faltan.contains('${a['product_id']}'),
                      activeColor: Colors.orange,
                      title: Text('${a['quantity'] ?? 1} × ${a['product_name_snapshot'] ?? ''}',
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                      onChanged: (v) => setD(() => v == true
                          ? faltan.add('${a['product_id']}')
                          : faltan.remove('${a['product_id']}')),
                    ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: notaCtrl,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'te_lo_compra.no_hay_nota'.tr(),
                    hintStyle: const TextStyle(color: AppColors.textDisabled),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text('go_back'.tr())),
            ElevatedButton(
              onPressed: articulos.length > 1 && faltan.isEmpty ? null : () => Navigator.pop(c, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: Text('te_lo_compra.no_hay_confirmar'.tr()),
            ),
          ],
        ),
      ),
    );
    if (ok != true || _deliveryId == null) return;
    setState(() => _sinExistenciaBusy = true);
    try {
      final r = await _service.tiendaSinExistencia(
        deliveryId: _deliveryId!,
        nota: notaCtrl.text.trim(),
        productos: articulos.length > 1 ? faltan.toList() : null,
      );
      if (!mounted) return;
      final pago = (r['pago_chofer'] as num?)?.toDouble() ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(pago > 0
            ? 'te_lo_compra.no_hay_listo_pago'.tr(namedArgs: {'monto': pago.toStringAsFixed(2)})
            : 'te_lo_compra.no_hay_listo'.tr()),
        backgroundColor: Colors.orange,
      ));
      Navigator.pop(context, false);
    } catch (e) {
      if (!mounted) return;
      final s = e.toString();
      final lejos = RegExp(r'TE_LO_COMPRA_NO_ESTAS_EN_LA_TIENDA (\d+)').firstMatch(s);
      _err(lejos != null
          ? 'te_lo_compra.no_hay_lejos'.tr(namedArgs: {'metros': lejos.group(1)!})
          : s.contains('TE_LO_COMPRA_SIN_UBICACION')
              ? 'te_lo_compra.no_hay_sin_ubicacion'.tr()
              : s.replaceAll('PostgrestException', '').split(',').first);
    }
    if (mounted) setState(() => _sinExistenciaBusy = false);
  }

  /// No cabe en mi vehículo (antes de comprar): se le ofrece a un chofer con un vehículo más grande y el producto queda
  /// marcado de ese tamaño para la próxima.
  Future<void> _noCabe() async {
    final notaCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF161616),
        title: Text('te_lo_compra.no_cabe_titulo'.tr(), style: const TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('te_lo_compra.no_cabe_explica'.tr(), style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: notaCtrl,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'te_lo_compra.no_hay_nota'.tr(),
                hintStyle: const TextStyle(color: AppColors.textDisabled),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('go_back'.tr())),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text('te_lo_compra.no_cabe'.tr()),
          ),
        ],
      ),
    );
    if (ok != true || _deliveryId == null) return;
    setState(() => _sinExistenciaBusy = true);
    try {
      final r = await _service.noCabe(deliveryId: _deliveryId!, nota: notaCtrl.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('te_lo_compra.no_cabe_listo'.tr(namedArgs: {'vehiculo': '${r['nombre'] ?? ''}'.toLowerCase()})),
        backgroundColor: Colors.orange,
      ));
      Navigator.pop(context, false);
    } catch (e) {
      if (mounted) _err(e.toString().replaceAll('PostgrestException', '').split(',').first);
    }
    if (mounted) setState(() => _sinExistenciaBusy = false);
  }

  Future<void> _loadContacts() async {
    final rows = await _service.marketplaceContacts(widget.orderId);
    final want = _isPickup ? 'vendor' : 'buyer';
    for (final r in rows) {
      if (r['party'] == want) {
        if (mounted) {
          setState(() {
            _contactName = r['name'] as String?;
            _contactPhone = r['phone'] as String?;
          });
        }
        return;
      }
    }
  }

  String _digits(String p) => p.replaceAll(RegExp(r'[^0-9]'), '');

  Future<void> _launch(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        _err('marketplace.could_not_open'.tr());
      }
    } catch (_) {
      if (mounted) _err('marketplace.could_not_open'.tr());
    }
  }

  Future<void> _reportNoShow() async {
    final who = _isPickup ? 'marketplace.the_vendor'.tr() : 'marketplace.the_buyer'.tr();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF161616),
        title: Text('marketplace.report_no_show'.tr(),
            style: const TextStyle(color: AppColors.textPrimary)),
        content: Text(
            'marketplace.confirm_no_show'.tr(namedArgs: {'who': who}),
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('go_back'.tr())),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text('marketplace.yes_no_show'.tr()),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _noShowBusy = true);
    try {
      await _service.reportNoShow(
        orderId: widget.orderId,
        by: 'driver',
        lat: _position?.latitude,
        lng: _position?.longitude,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('marketplace.reported_no_show'.tr(namedArgs: {'who': who})),
        backgroundColor: Colors.orange,
      ));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _err(e.toString().replaceAll('PostgrestException', '').split(',').first);
    }
    if (mounted) setState(() => _noShowBusy = false);
  }

  @override
  void dispose() {
    _otpCtrl.dispose();
    _montoCtrl.dispose();
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

  /// TORO te lo compra: foto del ticket + total pagado en la tienda (sin PIN de vendedor).
  Future<void> _submitCompra() async {
    final monto = double.tryParse(_montoCtrl.text.trim().replaceAll(',', '').replaceAll(r'$', ''));
    if (monto == null || monto <= 0) {
      _err('te_lo_compra.monto_invalido'.tr());
      return;
    }
    if (_subtotal != null && monto > _subtotal!) {
      _err('te_lo_compra.monto_mayor'.tr(namedArgs: {'max': _subtotal!.toStringAsFixed(2)}));
      return;
    }
    if (_photo == null) {
      _err('te_lo_compra.foto_ticket_falta'.tr());
      return;
    }
    if (_position == null) {
      _err('marketplace.waiting_gps'.tr());
      return;
    }
    if (_deliveryId == null) {
      _err('nav.marketplace_not_found'.tr());
      return;
    }
    setState(() => _submitting = true);
    try {
      final bytes = await _photo!.readAsBytes();
      final url = await _service.uploadProofPhoto(
        orderId: widget.orderId,
        stage: 'pickup',
        bytes: bytes,
        lat: _position!.latitude,
        lng: _position!.longitude,
      );
      if (url == null) throw 'marketplace.upload_failed'.tr();
      await _service.comproEnTienda(deliveryId: _deliveryId!, monto: monto, photoUrl: url);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('te_lo_compra.compra_registrada'.tr(namedArgs: {'amount': monto.toStringAsFixed(2)})),
        backgroundColor: Colors.green,
      ));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _err(e.toString().replaceAll('PostgrestException', '').split(',').first);
    }
    if (mounted) setState(() => _submitting = false);
  }

  Future<void> _submit() async {
    if (_compra) return _submitCompra();
    final otp = _otpCtrl.text.trim();
    if (otp.length != 4) {
      _err('marketplace.code_4_digits'.tr());
      return;
    }
    if (_photo == null) {
      _err('marketplace.take_photo_first'.tr());
      return;
    }
    if (_position == null) {
      _err('marketplace.waiting_gps'.tr());
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
      if (url == null) throw 'marketplace.upload_failed'.tr();

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
          // Entrega confirmada: detener el GPS en vivo (ya no hay que rastrear).
          // El servicio de fondo es singleton, asi que esto lo apaga aunque se
          // haya arrancado desde otra pantalla.
          try { LocationService().stopRideTracking(); } catch (_) {}
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isPickup ? 'marketplace.pickup_confirmed'.tr() : 'marketplace.delivery_confirmed'.tr()),
          backgroundColor: Colors.green,
        ));
        Navigator.pop(context, true);
      } else {
        // ok=false means geofence failed but action was logged
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('marketplace.confirmed_out_of_zone'.tr()),
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(_title, style: const TextStyle(color: AppColors.textPrimary)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
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
                                style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                          if (widget.buyerName != null && !_isPickup)
                            Text(widget.buyerName!,
                                style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                          if (widget.address != null && widget.address!.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(widget.address!,
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Contacto de la contraparte: Llamar + WhatsApp (para que se encuentren)
              if (_contactPhone != null && _contactPhone!.trim().isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person, color: AppColors.textDisabled),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_contactName ?? (_isPickup ? 'marketplace.vendor'.tr() : 'marketplace.buyer'.tr()),
                                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                            Text(_contactPhone!,
                                style: const TextStyle(color: AppColors.textDisabled, fontSize: 12)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.call, color: Colors.green),
                        tooltip: 'marketplace.call'.tr(),
                        onPressed: () => _launch('tel:${_contactPhone!}'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
                        tooltip: 'WhatsApp',
                        onPressed: () => _launch('https://wa.me/${_digits(_contactPhone!)}'),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),

              if (_compra) ...[
                // TORO te lo compra: cuánto pagar y que se le reembolsa al entregar; luego el total del ticket.
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'te_lo_compra.paga_en_tienda'.tr(namedArgs: {
                          'amount': (_pagarEnTienda ?? 0).toStringAsFixed(2),
                        }),
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text('te_lo_compra.reembolso_al_entregar'.tr(),
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text('te_lo_compra.total_ticket'.tr(),
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: _montoCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 28, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    prefixText: r'$ ',
                    prefixStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 24),
                    hintText: '0.00',
                    hintStyle: TextStyle(color: AppColors.border),
                    filled: true,
                    fillColor: AppColors.border,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ] else ...[
              // OTP input
              Text(_otpLabel, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _otpCtrl,
                keyboardType: TextInputType.number,
                maxLength: 4,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 8),
                decoration: InputDecoration(
                  hintText: '0000',
                  hintStyle: TextStyle(color: AppColors.border, letterSpacing: 8),
                  filled: true,
                  fillColor: AppColors.border,
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ],

              // Photo
              Text(_photoLabel, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _takePhoto,
                child: Container(
                  height: 220,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _photo == null ? AppColors.border : Colors.green,
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
                            Text('marketplace.tap_to_take_photo'.tr(),
                                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                            Text('marketplace.clear_product_photo'.tr(),
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
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
                  color: AppColors.border,
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
                            ? 'marketplace.location_captured'.tr(namedArgs: {'lat': _position!.latitude.toStringAsFixed(4), 'lng': _position!.longitude.toStringAsFixed(4)})
                            : (_capturingGps ? 'marketplace.capturing_gps'.tr() : 'marketplace.no_gps'.tr()),
                        style: TextStyle(
                          color: _position != null ? Colors.green : Colors.orange,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: _capturingGps
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                          : const Icon(Icons.refresh, color: AppColors.textSecondary),
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
                    : Text(_compra
                            ? 'te_lo_compra.ya_lo_compre'.tr()
                            : (_isPickup ? 'marketplace.confirm_pickup'.tr() : 'marketplace.confirm_delivery'.tr()),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 12),
              // TORO te lo compra: si no hay, se cancela sin cobrarle al comprador.
              if (_compra) ...[
                OutlinedButton.icon(
                  onPressed: _sinExistenciaBusy ? null : _noHay,
                  icon: _sinExistenciaBusy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange))
                      : const Icon(Icons.remove_shopping_cart, color: Colors.orange),
                  label: Text('te_lo_compra.no_hay'.tr(), style: const TextStyle(color: Colors.orange)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    side: const BorderSide(color: Colors.orange),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 12),
                // Llegó y no cabe en su vehículo: se le ofrece a uno más grande (no se le cobra nada al comprador).
                OutlinedButton.icon(
                  onPressed: _sinExistenciaBusy ? null : _noCabe,
                  icon: const Icon(Icons.local_shipping_outlined, color: Colors.orange),
                  label: Text('te_lo_compra.no_cabe'.tr(), style: const TextStyle(color: Colors.orange)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    side: const BorderSide(color: Colors.orange),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                _compra ? 'te_lo_compra.requisitos'.tr() : 'marketplace.missing_requirements'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
              // No-show: el comprador no se presento a la entrega -> cancelar.
              if (!_isPickup) ...[
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _noShowBusy ? null : _reportNoShow,
                  icon: _noShowBusy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange))
                      : const Icon(Icons.person_off, color: Colors.orange),
                  label: Text('marketplace.buyer_no_show'.tr(),
                      style: const TextStyle(color: Colors.orange)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    side: const BorderSide(color: Colors.orange),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
