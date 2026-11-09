import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/driver_provider.dart';
import '../services/pais_cuenta_service.dart';
import '../utils/app_colors.dart';

/// País de la CUENTA del conductor (Carlos, 9 nov 2026): se ve y se cambia en Mis documentos, se
/// pregunta al entrar si nunca se eligió, y al cambiarlo se actualiza toda la app (documentos,
/// contrato, pagos, moneda). Las reglas viven en el servidor: elegir_pais_conductor.

String nombrePais(String pais) =>
    (pais == 'MX' ? 'docs_center_mexico' : 'docs_center_us').tr();

/// Bandera dibujada (los emoji de bandera no salen en todos los Android).
class BanderaPais extends StatelessWidget {
  final String pais;
  final double ancho;
  const BanderaPais(this.pais, {super.key, this.ancho = 34});

  @override
  Widget build(BuildContext context) {
    final alto = ancho * 0.68;
    final Widget dibujo = pais == 'MX'
        ? Row(children: [
            Expanded(child: Container(color: const Color(0xFF006847))),
            Expanded(
              child: Container(
                color: Colors.white,
                alignment: Alignment.center,
                child: Container(
                  width: alto * 0.28,
                  height: alto * 0.28,
                  decoration: const BoxDecoration(color: Color(0xFF8A5A2B), shape: BoxShape.circle),
                ),
              ),
            ),
            Expanded(child: Container(color: const Color(0xFFCE1126))),
          ])
        : Stack(children: [
            Column(children: [
              for (var i = 0; i < 7; i++)
                Expanded(child: Container(color: i.isEven ? const Color(0xFFB22234) : Colors.white)),
            ]),
            Container(width: ancho * 0.44, height: alto * 0.54, color: const Color(0xFF3C3B6E)),
          ]);
    return Container(
      width: ancho,
      height: alto,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ancho * 0.12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: dibujo,
    );
  }
}

/// Renglón de Mis documentos: bandera, país y "Cambiar" (o por qué no se puede).
class PaisCuentaTarjeta extends StatelessWidget {
  final String pais;
  final String driverId;
  final bool aprobado;
  final VoidCallback onCambiado;

  const PaisCuentaTarjeta({
    super.key,
    required this.pais,
    required this.driverId,
    required this.aprobado,
    required this.onCambiado,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          BanderaPais(pais),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('pais_cuenta_titulo'.tr(),
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              Text(nombrePais(pais),
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
          ),
          if (!aprobado)
            FilledButton(
              key: const Key('pais_cuenta_cambiar'),
              onPressed: () async {
                final cambiado = await mostrarHojaPaisCuenta(context, driverId: driverId, paisActual: pais);
                if (cambiado) onCambiado();
              },
              child: Text('pais_cuenta_cambiar'.tr()),
            ),
        ]),
        if (aprobado) ...[
          const SizedBox(height: 8),
          Text('pais_cuenta_bloqueado_aprobado'.tr(namedArgs: {'pais': nombrePais(pais)}),
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
            onPressed: () => Navigator.pushNamed(context, '/support'),
            child: Text('pais_cuenta_soporte'.tr()),
          ),
        ],
      ]),
    );
  }
}

/// Hoja para elegir el país. Devuelve true si el país quedó guardado (cambiado o confirmado).
Future<bool> mostrarHojaPaisCuenta(BuildContext context,
    {required String driverId, required String paisActual}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: PaisCuentaSelector(
        driverId: driverId,
        paisInicial: paisActual,
        paisActual: paisActual,
        onGuardado: () => Navigator.of(context).pop(true),
      ),
    ),
  );
  return r == true;
}

/// Contenido común de la hoja y de la pantalla de primer ingreso.
class PaisCuentaSelector extends StatefulWidget {
  final String driverId;
  final String paisInicial;
  final String paisActual;
  final VoidCallback onGuardado;

  const PaisCuentaSelector({
    super.key,
    required this.driverId,
    required this.paisInicial,
    required this.paisActual,
    required this.onGuardado,
  });

  @override
  State<PaisCuentaSelector> createState() => _PaisCuentaSelectorState();
}

class _PaisCuentaSelectorState extends State<PaisCuentaSelector> {
  late String _elegido = PaisCuentaService.paises.contains(widget.paisInicial) ? widget.paisInicial : 'MX';
  final Map<String, List<String>> _requisitos = {};
  bool _cargandoRequisitos = true;
  bool _guardando = false;
  String? _mensaje;

  @override
  void initState() {
    super.initState();
    _cargarRequisitos();
  }

  Future<void> _cargarRequisitos() async {
    for (final p in PaisCuentaService.paises) {
      try {
        _requisitos[p] = await PaisCuentaService.instance.requisitos(widget.driverId, p);
      } catch (_) {
        // Sin la lista igual se puede elegir; se muestra solo contrato y pagos.
      }
    }
    if (mounted) setState(() => _cargandoRequisitos = false);
  }

  String _nombreDoc(String codigo, String pais) {
    final llave = codigo == 'vehicle_registration'
        ? 'pais_doc_vehicle_registration_${pais.toLowerCase()}'
        : 'pais_doc_$codigo';
    final t = llave.tr();
    return t == llave ? codigo.replaceAll('_', ' ') : t;
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _mensaje = null;
    });
    final r = await PaisCuentaService.instance.elegir(_elegido);
    if (!mounted) return;
    if (r.ok) {
      // Las dos copias del conductor en memoria (AuthProvider y DriverProvider) se recargan para que
      // documentos, contrato, pagos, moneda y la pestaña Fiscal cambien en toda la app.
      final auth = context.read<AuthProvider>();
      final driverProvider = context.read<DriverProvider>();
      await auth.refreshProfile();
      await driverProvider.initialize(widget.driverId);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text('pais_cuenta_listo'.tr(namedArgs: {'pais': nombrePais(_elegido)}))));
      widget.onGuardado();
      return;
    }
    setState(() {
      _guardando = false;
      final actual = nombrePais(r.paisActual ?? widget.paisActual);
      _mensaje = switch (r.motivo) {
        'aprobado' => 'pais_cuenta_bloqueado_aprobado'.tr(namedArgs: {'pais': actual}),
        'stripe' => 'pais_cuenta_bloqueado_stripe'.tr(namedArgs: {'pais': actual}),
        _ => 'pais_cuenta_error'.tr(),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final cambia = _elegido != widget.paisActual;
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Center(
          child: Container(
            width: 44,
            height: 5,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: AppColors.borderStrong, borderRadius: BorderRadius.circular(3)),
          ),
        ),
        Text('pais_cuenta_hoja_titulo'.tr(),
            style: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('pais_cuenta_hoja_sub'.tr(), style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.35)),
        const SizedBox(height: 16),
        for (final p in PaisCuentaService.paises) _opcion(p),
        if (cambia && widget.paisActual.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text('pais_cuenta_aviso_contrato'.tr(), style: TextStyle(color: AppColors.warning, fontSize: 13)),
        ],
        if (_mensaje != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.errorSoft, borderRadius: BorderRadius.circular(12)),
            child: Text(_mensaje!, style: TextStyle(color: AppColors.errorDark, fontSize: 13)),
          ),
          if (_mensaje != 'pais_cuenta_error'.tr())
            TextButton(onPressed: () => Navigator.pushNamed(context, '/support'), child: Text('pais_cuenta_soporte'.tr())),
        ],
        const SizedBox(height: 14),
        FilledButton(
          key: const Key('pais_cuenta_guardar'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
              : Text('pais_cuenta_guardar'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 10),
        Text('pais_cuenta_nota'.tr(),
            textAlign: TextAlign.center, style: TextStyle(color: AppColors.textTertiary, fontSize: 12, height: 1.35)),
      ]),
    );
  }

  Widget _opcion(String p) {
    final sel = _elegido == p;
    final docs = _requisitos[p];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        key: Key('pais_cuenta_opcion_$p'),
        borderRadius: BorderRadius.circular(18),
        onTap: _guardando ? null : () => setState(() => _elegido = p),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: sel ? AppColors.primaryPale : AppColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: sel ? AppColors.primary : AppColors.border, width: sel ? 2 : 1),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 3), child: BanderaPais(p, ancho: 38)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(nombrePais(p),
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                  Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: sel ? AppColors.primary : AppColors.textDisabled),
                ]),
                const SizedBox(height: 6),
                if (_cargandoRequisitos)
                  const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                else if (docs != null && docs.isNotEmpty)
                  _dato('pais_cuenta_documentos'.tr(), docs.map((c) => _nombreDoc(c, p)).join(', ')),
                _dato('pais_cuenta_contrato'.tr(), 'pais_cuenta_contrato_${p.toLowerCase()}'.tr()),
                _dato('pais_cuenta_pagos'.tr(), 'pais_cuenta_pagos_${p.toLowerCase()}'.tr()),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _dato(String etiqueta, String valor) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: '$etiqueta: ', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
            TextSpan(text: valor),
          ]),
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
        ),
      );
}

/// Primer ingreso de un conductor que nunca eligió país (p. ej. quedó US por default al registrarse).
/// Nunca deja encerrado: siempre hay salida (soporte y cerrar sesión).
class PaisCuentaScreen extends StatelessWidget {
  final String driverId;
  final String paisDetectado;
  const PaisCuentaScreen({super.key, required this.driverId, required this.paisDetectado});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Column(children: [
            Expanded(
              child: PaisCuentaSelector(
                driverId: driverId,
                paisInicial: paisDetectado,
                // Sin país elegido no hay "cambio": no se avisa de volver a firmar.
                paisActual: '',
                onGuardado: () {},
              ),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              TextButton(onPressed: () => Navigator.pushNamed(context, '/support'), child: Text('pais_cuenta_soporte'.tr())),
              TextButton(
                onPressed: () => context.read<AuthProvider>().signOut(),
                child: Text('logout'.tr()),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
