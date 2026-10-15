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
///
/// Persona física o empresa (14 oct 2026, Carlos: "no miro si puedo poner físico o moral"). El SAT lo
/// define por el RFC: 13 caracteres = persona física, 12 = persona moral (empresa). No hay columna nueva:
/// el tipo SIEMPRE se saca del RFC guardado (aquí, en documentos y en el Command Center), así no puede
/// quedar un tipo que contradiga al RFC. A las empresas no les aplican las retenciones de plataforma
/// (art. 113-A LISR / 18-J LIVA son para personas físicas) ni el IMSS de plataformas.
class DatosFiscales {
  static final rfcValido = RegExp(r'^[A-ZÑ&]{3,4}[0-9]{6}[A-Z0-9]{3}$');
  static final rfcFisica = RegExp(r'^[A-ZÑ&]{4}[0-9]{6}[A-Z0-9]{3}$');
  static final rfcMoral = RegExp(r'^[A-ZÑ&]{3}[0-9]{6}[A-Z0-9]{3}$');
  static final cpValido = RegExp(r'^[0-9]{5}$');
  static final idcifValido = RegExp(r'^[0-9]{8,14}$');
  static const regimenesFisica = ['625', '626', '612', '605', '616'];
  // 601 General de Ley, 624 Coordinados (lo usan muchas empresas de autotransporte), 626 RESICO, 603 sin fines de lucro.
  static const regimenesMoral = ['601', '624', '626', '603'];
  static const regimenes = ['625', '626', '612', '605', '616', '601', '624', '603'];

  /// 'moral' si el RFC es de empresa (12 caracteres), 'fisica' en cualquier otro caso.
  static String tipoDeRfc(String? rfc) => rfcMoral.hasMatch((rfc ?? '').trim().toUpperCase()) ? 'moral' : 'fisica';
  static bool esEmpresa(String? rfc) => tipoDeRfc(rfc) == 'moral';
  static List<String> regimenesDe(String tipo) => tipo == 'moral' ? regimenesMoral : regimenesFisica;
}

/// Lo que se le dice a una empresa en vez de la leyenda de retención de ISR (que es para personas físicas).
class LeyendaEmpresa extends StatelessWidget {
  const LeyendaEmpresa({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.business, size: 16, color: AppColors.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text('fiscal_leyenda_empresa'.tr(),
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.3)),
        ),
      ]),
    );
  }
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
  String _tipo = 'fisica'; // 'fisica' | 'moral' — se elige arriba y se confirma con el RFC
  bool _intentoGuardar = false;
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
        _tipo = DatosFiscales.tipoDeRfc(_rfc.text);
        // Una empresa no escribe su nombre de persona: si no hay razón social guardada, va vacío.
        if (_tipo == 'moral' && (d['fiscal_nombre'] ?? '').toString().trim().isEmpty) _nombre.clear();
        final reg = d['fiscal_regimen']?.toString();
        _regimen = DatosFiscales.regimenesDe(_tipo).contains(reg) ? reg : null;
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
    if (!(_form.currentState?.validate() ?? false)) {
      // Desde el primer intento fallido, cada campo se revalida al corregirlo (si no, el aviso
      // rojo viejo se quedaba aunque el RFC ya estuviera bien).
      if (!_intentoGuardar) setState(() => _intentoGuardar = true);
      return;
    }
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

  void _cambiarTipo(String tipo) {
    if (tipo == _tipo) return;
    setState(() {
      _tipo = tipo;
      if (!DatosFiscales.regimenesDe(tipo).contains(_regimen)) _regimen = null;
    });
  }

  /// Si el RFC escrito ya es claramente de empresa (12) o de persona (13), el selector se acomoda solo.
  /// Ningún RFC de persona a medio escribir cumple el patrón de empresa (el 4.º carácter de una empresa
  /// es número y el de una persona es letra), así que no brinca mientras teclea.
  void _rfcCambio(String v) {
    final t = v.trim().toUpperCase();
    if (DatosFiscales.rfcMoral.hasMatch(t)) {
      _cambiarTipo('moral');
    } else if (DatosFiscales.rfcFisica.hasMatch(t)) {
      _cambiarTipo('fisica');
    }
  }

  String? _validarRfc(String? v) {
    final t = (v ?? '').trim().toUpperCase();
    if (_tipo == 'moral') {
      if (DatosFiscales.rfcMoral.hasMatch(t)) return null;
      return DatosFiscales.rfcFisica.hasMatch(t) ? 'fiscal_rfc_es_persona'.tr() : 'fiscal_rfc_error_moral'.tr();
    }
    if (DatosFiscales.rfcFisica.hasMatch(t)) return null;
    return DatosFiscales.rfcMoral.hasMatch(t) ? 'fiscal_rfc_es_empresa'.tr() : 'fiscal_rfc_error'.tr();
  }

  InputDecoration _deco(String label, {String? ayuda}) => InputDecoration(
        labelText: label,
        helperText: ayuda,
        helperMaxLines: 3,
        errorMaxLines: 3, // "Ese RFC es de empresa… Elige «Empresa» arriba" se cortaba en una línea

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
              autovalidateMode: _intentoGuardar ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
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
                  const SizedBox(height: 12),
                  Text('fiscal_tipo_pregunta'.tr(),
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: 'fisica', icon: const Icon(Icons.person, size: 18), label: Text('fiscal_tipo_fisica'.tr())),
                      ButtonSegment(value: 'moral', icon: const Icon(Icons.business, size: 18), label: Text('fiscal_tipo_moral'.tr())),
                    ],
                    selected: {_tipo},
                    onSelectionChanged: (s) => _cambiarTipo(s.first),
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith(
                          (st) => st.contains(WidgetState.selected) ? AppColors.primary : AppColors.card),
                      foregroundColor: WidgetStateProperty.resolveWith(
                          (st) => st.contains(WidgetState.selected) ? Colors.white : AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_tipo == 'moral') const LeyendaEmpresa() else const LeyendaRetencionIsr(),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _rfc,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-zÑñ&0-9]')),
                      LengthLimitingTextInputFormatter(13),
                    ],
                    onChanged: _rfcCambio,
                    decoration: _deco('fiscal_rfc'.tr(),
                        ayuda: (_tipo == 'moral' ? 'fiscal_rfc_ayuda_moral' : 'fiscal_rfc_ayuda_fisica').tr()),
                    validator: _validarRfc,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nombre,
                    textCapitalization: TextCapitalization.characters,
                    decoration: _tipo == 'moral'
                        ? _deco('fiscal_razon_social'.tr(), ayuda: 'fiscal_razon_social_ayuda'.tr())
                        : _deco('fiscal_nombre'.tr()),
                    validator: (v) => (v ?? '').trim().length >= 3
                        ? null
                        : (_tipo == 'moral' ? 'fiscal_razon_social_error' : 'fiscal_nombre_error').tr(),
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
                      for (final r in DatosFiscales.regimenesDe(_tipo))
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
