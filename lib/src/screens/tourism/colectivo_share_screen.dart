import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../utils/app_colors.dart';
import '../../utils/money_format.dart';

/// "Comparte tu viaje": el organizador publica su BOLETO como imagen en
/// Facebook/Instagram/WhatsApp. La imagen lleva ruta, fecha, precio, lugares y
/// el QR con la liga toro-ride.com/event/EVT-XXXXXXXX: quien la escanea ve la
/// ficha del viaje en la web y, si no tiene el app, lo descarga y entra con ese
/// mismo código.
class ColectivoShareScreen extends StatefulWidget {
  final Map<String, dynamic> event;
  const ColectivoShareScreen({super.key, required this.event});

  @override
  State<ColectivoShareScreen> createState() => _ColectivoShareScreenState();
}

class _ColectivoShareScreenState extends State<ColectivoShareScreen> {
  final GlobalKey _posterKey = GlobalKey();
  bool _sharing = false;

  Map<String, dynamic> get e => widget.event;

  String get _code => (e['invitation_code'] ?? '').toString();
  String get _link => 'https://toro-ride.com/event/$_code';

  List<Map<String, dynamic>> get _stops {
    final it = e['itinerary'];
    if (it is List) {
      return it.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    }
    return const [];
  }

  String _name(int i) {
    final s = _stops;
    if (i < 0 || i >= s.length) return '';
    return (s[i]['name'] ?? '').toString().split(',').first.trim();
  }

  String get _origin => _name(0);
  String get _destination => _stops.isEmpty ? '' : _name(_stops.length - 1);

  String get _country => (e['country_code'] ?? 'MX').toString();

  String get _dateText {
    final d = DateTime.tryParse('${e['event_date'] ?? ''}');
    if (d == null) return '';
    return DateFormat('EEE d MMM', context.locale.toString()).format(d);
  }

  String get _timeText {
    final t = (e['start_time'] ?? '').toString();
    return t.length >= 5 ? t.substring(0, 5) : t;
  }

  double? get _price {
    final base = (e['total_base_price'] as num?)?.toDouble();
    if (base != null && base > 0) return base;
    final km = (e['total_distance_km'] as num?)?.toDouble();
    final ppk = (e['price_per_km'] as num?)?.toDouble();
    if (km != null && ppk != null) return km * ppk;
    return null;
  }

  int get _seats => (e['max_passengers'] as num?)?.toInt() ?? 0;

  int get _taken {
    final invs = e['tourism_invitations'];
    if (invs is List) {
      return invs.where((i) {
        final s = (i is Map ? i['status'] : null)?.toString();
        return s == 'accepted' || s == 'checked_in';
      }).length;
    }
    return (e['confirmed_passengers'] as num?)?.toInt() ?? 0;
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final boundary =
          _posterKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/toro_colectivo_$_code.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);

      final texto = [
        '$_origin → $_destination',
        '$_dateText · $_timeText',
        if (_price != null)
          '${'colectivo_share_price'.tr()}: ${formatMoney(_price, country: _country)} ${e['currency'] ?? ''}',
        'colectivo_share_cta'.tr(namedArgs: {'code': _code}),
        _link,
      ].join('\n');

      await Share.shareXFiles([XFile(file.path)], text: texto);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('colectivo_share_error'.tr())),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('colectivo_share_title'.tr()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('colectivo_share_help'.tr(),
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5)),
            const SizedBox(height: 14),
            Center(
              child: RepaintBoundary(
                key: _posterKey,
                child: _poster(),
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: _sharing ? null : _share,
              icon: _sharing
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.ios_share),
              label: Text('colectivo_share_button'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _link));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('colectivo_share_copied'.tr())),
                );
              },
              icon: const Icon(Icons.link, size: 18),
              label: Text(_link, overflow: TextOverflow.ellipsis),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// El "boleto" que se publica. Fondo sólido (no transparente) porque se
  /// exporta como PNG y las redes lo aplanan sobre blanco.
  Widget _poster() {
    final libres = (_seats - _taken).clamp(0, _seats);
    const gold = Color(0xFFD4AF37);
    return Container(
      width: 360,
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: gold.withValues(alpha: 0.5), width: 1.4),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.directions_bus_rounded, color: gold, size: 20),
              const SizedBox(width: 8),
              Text('colectivo_share_brand'.tr(),
                  style: const TextStyle(
                      color: gold, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              const Spacer(),
              Text('$_dateText · $_timeText',
                  style: const TextStyle(color: Color(0xFFB8B8B8), fontSize: 12.5)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(_origin,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
              ),
              const Icon(Icons.arrow_forward_rounded, color: gold, size: 20),
              Expanded(
                child: Text(_destination,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          if (_stops.length > 2) ...[
            const SizedBox(height: 6),
            Text(
              '${'colectivo_share_stops'.tr()}: ${_stops.sublist(1, _stops.length - 1).map((s) => (s['name'] ?? '').toString().split(',').first.trim()).join(' · ')}',
              style: const TextStyle(color: Color(0xFFB8B8B8), fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 14),
          Container(height: 1, color: const Color(0xFF2A2A2A)),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_price != null) ...[
                      Text('colectivo_share_price'.tr(),
                          style: const TextStyle(color: Color(0xFF7A7A7A), fontSize: 11.5)),
                      Text(
                        '${formatMoney(_price, country: _country)} ${e['currency'] ?? ''}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      libres > 0
                          ? 'colectivo_share_seats'.tr(namedArgs: {'n': '$libres'})
                          : 'colectivo_share_full'.tr(),
                      style: TextStyle(
                          color: libres > 3 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text((e['organizers']?['company_name'] ?? '').toString(),
                        style: const TextStyle(color: Color(0xFFB8B8B8), fontSize: 13)),
                  ],
                ),
              ),
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: QrImageView(
                      data: _link,
                      version: QrVersions.auto,
                      size: 104,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(_code,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('colectivo_share_footer'.tr(),
              style: const TextStyle(color: Color(0xFF7A7A7A), fontSize: 11.5)),
        ],
      ),
    );
  }
}
