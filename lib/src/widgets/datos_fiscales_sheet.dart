import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_colors.dart';
import 'leyenda_retencion_isr.dart';

/// Datos fiscales ESCRITOS por el conductor (12 oct 2026). Antes solo se aceptaba subir el PDF de
/// la Constancia de Situación Fiscal. Aquí escribe lo que pide su CFDI de retenciones: RFC, nombre
/// exacto como en el SAT, código postal fiscal y régimen (+ idCIF opcional para verificarlo con el
/// SAT). La regla oficial (estado_documentos_conductor) los cuenta como la constancia.
class DatosFiscales {
  static final rfcValido = RegExp(r'^[A-ZÑ&]{3,4}[0-9]{6}[A-Z0-9]{3}$');
  static final cpValido = RegExp(r'^[0-9]{5}$');
  static final idcifValido = RegExp(r'^[0-9]{8,14}$');
  static const regimenes = ['625', '626', '612', '605', '616'];
}

/// Abre el formulario. Devuelve true si se guardó.
Future<bool> mostrarDatosFiscales(BuildContext context, String driverId) async {
  // The account's persisted country decides which tax flow applies, regardless
  // of language or which screen opened this form.
  try {
    final driver = await Supabase.instance.client
        .from('drivers')
        .select('country_code')
        .eq('id', driverId)
        .maybeSingle();
    if (!context.mounted) return false;
    if (driver?['country_code']?.toString().trim().toUpperCase() != 'MX') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('fiscal_country_only_mx'.tr())),
      );
      return false;
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('fiscal_load_error'.tr())),
      );
    }
    return false;
  }
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _DatosFiscalesSheet(driverId: driverId),
  );
  return r == true;
}

class _DatosFiscalesSheet extends StatefulWidget {
  final String driverId;
  const _DatosFiscalesSheet({required this.driverId});

  @override
  State<_DatosFiscalesSheet> createState() => _DatosFiscalesSheetState();
}

class _DatosFiscalesSheetState extends State<_DatosFiscalesSheet> {
  final _form = GlobalKey<FormState>();
  final _rfc = TextEditingController();
  final _nombre = TextEditingController();
  final _cp = TextEditingController();
  final _idcif = TextEditingController();
  String? _regimen;
  bool _cargando = true;
  bool _guardando = false;
  bool _errorCarga = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final c in [_rfc, _nombre, _cp, _idcif]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _errorCarga = false;
    });
    try {
      final d = await Supabase.instance.client
          .from('drivers')
          .select('rfc, fiscal_nombre, fiscal_cp, fiscal_regimen, fiscal_idcif, name')
          .eq('id', widget.driverId)
          .eq('country_code', 'MX')
          .maybeSingle();
      if (!mounted) return;
      if (d != null) {
        _rfc.text = (d['rfc'] ?? '').toString();
        _nombre.text = (d['fiscal_nombre'] ?? d['name'] ?? '').toString().toUpperCase();
        _cp.text = (d['fiscal_cp'] ?? '').toString();
        _idcif.text = (d['fiscal_idcif'] ?? '').toString();
        final reg = d['fiscal_regimen']?.toString();
        _regimen = DatosFiscales.regimenes.contains(reg) ? reg : null;
      } else {
        _errorCarga = true;
      }
    } catch (_) {
      if (!mounted) return;
      _errorCarga = true;
    }
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _guardar() async {
    if (_guardando || _cargando || _errorCarga) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _guardando = true);
    try {
      final saved = await Supabase.instance.client.from('drivers').update({
        'rfc': _rfc.text.trim().toUpperCase(),
        'fiscal_nombre': _nombre.text.trim().toUpperCase(),
        'fiscal_cp': _cp.text.trim(),
        'fiscal_regimen': _regimen,
        'fiscal_idcif': _idcif.text.trim().isEmpty ? null : _idcif.text.trim(),
        'fiscal_capturado_at': DateTime.now().toUtc().toIso8601String(),
      })
          .eq('id', widget.driverId)
          .eq('country_code', 'MX')
          .select('id')
          .maybeSingle();
      if (!mounted) return;
      if (saved == null) {
        setState(() => _guardando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('fiscal_save_error'.tr()), backgroundColor: AppColors.error),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('fiscal_guardado'.tr())));
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('fiscal_save_error'.tr()),
        backgroundColor: AppColors.error,
      ));
    }
  }

  InputDecoration _deco(String label, {String? ayuda}) => InputDecoration(
        labelText: label,
        helperText: ayuda,
        helperMaxLines: 3,
        filled: true,
        fillColor: AppColors.card,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      );

  @override
  Widget build(BuildContext context) {
    final abajo = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + abajo),
      child: _cargando
          ? const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))
          : _errorCarga
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('fiscal_load_error'.tr(), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                TextButton(onPressed: _cargar, child: Text('retry'.tr())),
              ],
            )
          : Form(
              key: _form,
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  Center(
                    child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
                  ),
                  const SizedBox(height: 14),
                  Text('fiscal_titulo'.tr(),
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 19, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('fiscal_sub'.tr(), style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 10),
                  const LeyendaRetencionIsr(),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _rfc,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-zÑñ&0-9]')),
                      LengthLimitingTextInputFormatter(13),
                    ],
                    decoration: _deco('fiscal_rfc'.tr()),
                    validator: (v) => DatosFiscales.rfcValido.hasMatch((v ?? '').trim().toUpperCase()) ? null : 'fiscal_rfc_error'.tr(),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nombre,
                    textCapitalization: TextCapitalization.characters,
                    decoration: _deco('fiscal_nombre'.tr()),
                    validator: (v) => (v ?? '').trim().length >= 3 ? null : 'fiscal_nombre_error'.tr(),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _cp,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
                    decoration: _deco('fiscal_cp'.tr()),
                    validator: (v) => DatosFiscales.cpValido.hasMatch((v ?? '').trim()) ? null : 'fiscal_cp_error'.tr(),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _regimen,
                    isExpanded: true,
                    decoration: _deco('fiscal_regimen'.tr()),
                    items: [
                      for (final r in DatosFiscales.regimenes)
                        DropdownMenuItem(value: r, child: Text('fiscal_reg_$r'.tr(), overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => _regimen = v),
                    validator: (v) => v == null ? 'fiscal_regimen_error'.tr() : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _idcif,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(14)],
                    decoration: _deco('fiscal_idcif'.tr(), ayuda: 'fiscal_idcif_ayuda'.tr()),
                    validator: (v) {
                      final t = (v ?? '').trim();
                      return t.isEmpty || DatosFiscales.idcifValido.hasMatch(t) ? null : 'fiscal_idcif_error'.tr();
                    },
                  ),
                  const SizedBox(height: 12),
                  Text('fiscal_sin_constancia'.tr(), style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _guardando ? null : _guardar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _guardando
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text('fiscal_guardar'.tr(), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ]),
              ),
            ),
    );
  }
}
