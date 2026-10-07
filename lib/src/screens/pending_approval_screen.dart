import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/driver_model.dart';
import '../providers/auth_provider.dart';
import '../utils/app_colors.dart';
import '../utils/haptic_service.dart';

/// Correo de soporte REAL. Es el mismo que publica la pagina, el aviso de
/// privacidad y los terminos, y el Worker de Cloudflare reenvia todo el dominio,
/// asi que este buzon si llega a alguien.
///
/// NO agregar telefonos: el unico que habia en el codigo del app
/// (+1 602 555-0123, en account_status_screen.dart) es del rango ficticio
/// reservado 555-01xx. Un numero que no contesta es peor que no poner numero.
const String _correoSoporte = 'support@toro-ride.com';

/// Pantalla para el chofer que todavia no puede entrar.
///
/// REGLA DE ESTA PANTALLA: nunca puede ser un callejon sin salida. Siempre
/// ofrece, en este orden: (1) el motivo de la decision escrito, (2) pedir
/// revision, que mete una fila en `reactivation_requests`, (3) escribir a
/// soporte con su folio ya llenado, (4) copiar el correo por si no hay app de
/// correo, y (5) cerrar sesion.
///
/// Lo que estaba mal antes: el titulo decia "PENDING APPROVAL" aunque la cuenta
/// estuviera suspendida; decia "contact support" SIN dar ningun contacto;
/// prometia "24-48 hours" y "we'll notify you by email" sin que nada lo cumpla;
/// y mostraba "v1.0.0" con la app en 1.3.0.
class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Timer? _checkTimer;

  bool _isChecking = false;
  bool _enviando = false;

  /// Motivo escrito por el admin, tomado de la primera columna que traiga algo.
  String? _motivo;

  /// Ultima solicitud de revision del chofer, si ya mando una.
  Map<String, dynamic>? _solicitud;

  /// Vive en el State a proposito. Si se crea dentro de _pedirRevision y se
  /// desecha en cuanto showModalBottomSheet devuelve, se esta desechando
  /// mientras la hoja todavia se esta cerrando: el TextField sigue montado unos
  /// 250 ms y Flutter truena con
  /// "'_dependents.isEmpty': is not true" (framework.dart, pantalla roja).
  final TextEditingController _motivoCtrl = TextEditingController();

  String _version = '';

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _checkTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _revisarEstado();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revisarEstado();
      _cargarVersion();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _checkTimer?.cancel();
    _motivoCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(
        () => _version = 'TORO DRIVER ${info.version}+${info.buildNumber}',
      );
    } catch (_) {
      // Sin version es mejor que con una version inventada.
    }
  }

  Future<void> _revisarEstado() async {
    if (_isChecking) return;
    setState(() => _isChecking = true);

    try {
      final authProvider = context.read<AuthProvider>();
      await authProvider.refreshProfile();
      if (!mounted) return;

      if (authProvider.driver?.status == DriverStatus.active) {
        HapticService.heavyImpact();
        // El AuthWrapper detecta el cambio y navega solo.
      }

      await _cargarDetalle();
    } catch (_) {
      // Si falla la red la pantalla sigue usable: escribir a soporte y copiar
      // el correo no dependen de esto.
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  /// Trae el motivo de la decision y la ultima solicitud de revision.
  ///
  /// El motivo no vive en una sola columna: segun quien bloquee queda en
  /// suspension_reason, rejection_reason, compliance_reason o approval_notes.
  /// Se toma la primera que traiga texto.
  Future<void> _cargarDetalle() async {
    final cliente = Supabase.instance.client;
    final uid = cliente.auth.currentUser?.id;
    if (uid == null) return;

    try {
      final fila = await cliente
          .from('drivers')
          .select(
            'suspension_reason, rejection_reason, compliance_reason, approval_notes',
          )
          .eq('id', uid)
          .maybeSingle();

      String? motivo;
      if (fila != null) {
        for (final columna in const [
          'suspension_reason',
          'rejection_reason',
          'compliance_reason',
          'approval_notes',
        ]) {
          final valor = (fila[columna] as String?)?.trim();
          if (valor != null && valor.isNotEmpty) {
            motivo = valor;
            break;
          }
        }
      }

      final solicitudes = await cliente
          .from('reactivation_requests')
          .select('status, reason, submitted_at, review_notes')
          .eq('driver_id', uid)
          .order('submitted_at', ascending: false)
          .limit(1);

      if (!mounted) return;
      setState(() {
        _motivo = motivo;
        _solicitud = solicitudes.isEmpty
            ? null
            : Map<String, dynamic>.from(solicitudes.first);
      });
    } catch (_) {
      // Sin detalle la pantalla sigue funcionando.
    }
  }

  // ---------------------------------------------------------------------------
  // Salidas
  // ---------------------------------------------------------------------------

  String get _folio {
    final id = context.read<AuthProvider>().driver?.id ?? '';
    return id.length >= 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase();
  }

  Future<void> _copiar(String texto) async {
    await Clipboard.setData(ClipboardData(text: texto));
    if (!mounted) return;
    _aviso('gate_copied'.tr(namedArgs: {'dato': texto}));
  }

  void _aviso(String mensaje, {bool malo = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: malo ? AppColors.error : AppColors.cardSecondary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Abre el correo con el folio y el estado ya escritos, para que soporte no
  /// tenga que preguntar quien es. Si no hay app de correo, copia la direccion:
  /// asi el boton nunca se queda sin hacer nada.
  Future<void> _escribirSoporte() async {
    final driver = context.read<AuthProvider>().driver;
    final estado = driver?.status.value ?? '-';

    final asunto = 'gate_mail_subject'.tr(namedArgs: {'folio': _folio});
    final cuerpo = 'gate_mail_body'.tr(
      namedArgs: {
        'folio': _folio,
        'correo': driver?.email ?? '-',
        'estado': estado,
      },
    );

    final uri = Uri(
      scheme: 'mailto',
      path: _correoSoporte,
      query: 'subject=${Uri.encodeComponent(asunto)}'
          '&body=${Uri.encodeComponent(cuerpo)}',
    );

    var abrio = false;
    try {
      abrio = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      abrio = false;
    }

    if (!abrio) {
      await Clipboard.setData(const ClipboardData(text: _correoSoporte));
      if (!mounted) return;
      _aviso('gate_mail_failed'.tr());
    }
  }

  /// Mete la solicitud en `reactivation_requests`. La tabla y su RLS ya existian
  /// (el chofer puede insertar la suya y leerla) y ningun codigo del app la
  /// usaba: era la puerta de salida construida y nunca conectada.
  Future<void> _pedirRevision() async {
    _motivoCtrl.clear();

    final texto = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (contextoHoja) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: 20 + MediaQuery.viewInsetsOf(contextoHoja).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'gate_ask_review'.tr(),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'gate_ask_review_hint'.tr(),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _motivoCtrl,
                maxLines: 5,
                minLines: 3,
                maxLength: 1000,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.cardSecondary,
                  counterStyle: const TextStyle(color: AppColors.textTertiary),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final valor = _motivoCtrl.text.trim();
                    if (valor.isEmpty) {
                      ScaffoldMessenger.of(contextoHoja).showSnackBar(
                        SnackBar(content: Text('gate_ask_review_empty'.tr())),
                      );
                      return;
                    }
                    Navigator.pop(contextoHoja, valor);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text('gate_ask_review_send'.tr()),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (texto == null || !mounted) return;

    setState(() => _enviando = true);
    try {
      final driver = context.read<AuthProvider>().driver;
      await Supabase.instance.client.from('reactivation_requests').insert({
        'driver_id': driver?.id,
        'reason': texto,
        'country_code': driver?.countryCode ?? 'MX',
      });
      HapticService.heavyImpact();
      if (!mounted) return;
      _aviso('gate_ask_review_sent'.tr());
      await _cargarDetalle();
    } catch (_) {
      _aviso('gate_error_send'.tr(), malo: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _cerrarSesion() async {
    await context.read<AuthProvider>().signOut();
  }

  // ---------------------------------------------------------------------------
  // Pintado
  // ---------------------------------------------------------------------------

  _Aspecto _aspectoDe(DriverStatus? estado) {
    switch (estado) {
      case DriverStatus.suspended:
        return const _Aspecto(
          titulo: 'gate_title_suspended',
          mensaje: 'gate_msg_suspended',
          icono: Icons.pause_circle_outline_rounded,
          color: AppColors.error,
          puedeCompletarDocumentos: false,
        );
      case DriverStatus.rejected:
        return const _Aspecto(
          titulo: 'gate_title_rejected',
          mensaje: 'gate_msg_rejected',
          icono: Icons.cancel_outlined,
          color: AppColors.error,
          puedeCompletarDocumentos: false,
        );
      default:
        return const _Aspecto(
          titulo: 'gate_title_review',
          mensaje: 'gate_msg_review',
          icono: Icons.hourglass_top_rounded,
          color: AppColors.warning,
          puedeCompletarDocumentos: true,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = context.watch<AuthProvider>().driver?.status;
    final a = _aspectoDe(estado);

    // Esta pantalla ya NO es una traba: se abre desde Mis Documentos y se
    // cierra. El boton solo aparece si hay a donde regresar, por si algun dia
    // se vuelve a mostrar como raiz.
    final sePuedeCerrar = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              if (sePuedeCerrar)
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                    color: AppColors.textSecondary,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'back'.tr(),
                  ),
                ),
              const SizedBox(height: 24),
              _icono(a),
              const SizedBox(height: 32),
              Text(
                a.titulo.tr(),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  letterSpacing: 3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              Text(
                a.mensaje.tr(),
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              _tarjetaMotivo(a),
              if (_solicitud != null) ...[
                const SizedBox(height: 12),
                _tarjetaSolicitud(),
              ],
              const SizedBox(height: 12),
              _tarjetaSalidas(a),
              const SizedBox(height: 28),
              TextButton(
                onPressed: _cerrarSesion,
                child: Text(
                  'logout'.tr(),
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 14,
                  ),
                ),
              ),
              if (_version.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _version,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textDisabled,
                    letterSpacing: 1,
                  ),
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _icono(_Aspecto a) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  a.color.withValues(alpha: 0.3),
                  a.color.withValues(alpha: 0.1),
                ],
              ),
              border: Border.all(
                color: a.color.withValues(alpha: 0.5),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: a.color.withValues(alpha: 0.2),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Center(child: Icon(a.icono, size: 54, color: a.color)),
          ),
        );
      },
    );
  }

  /// El motivo escrito por el admin, y el folio para que soporte lo identifique.
  Widget _tarjetaMotivo(_Aspecto a) {
    final hayMotivo = _motivo != null && _motivo!.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: a.color),
              const SizedBox(width: 8),
              Text(
                'gate_reason'.tr(),
                style: TextStyle(
                  color: a.color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            hayMotivo ? _motivo! : 'gate_reason_missing'.tr(),
            style: TextStyle(
              color: hayMotivo ? AppColors.textPrimary : AppColors.textSecondary,
              fontSize: 14,
              height: 1.45,
              fontStyle: hayMotivo ? FontStyle.normal : FontStyle.italic,
            ),
          ),
          const Divider(color: AppColors.divider, height: 26),
          Row(
            children: [
              const Icon(
                Icons.confirmation_number_outlined,
                size: 18,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: 8),
              Text(
                'gate_folio'.tr(),
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Text(
                _folio,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
              IconButton(
                onPressed: () => _copiar(_folio),
                icon: const Icon(Icons.copy_rounded, size: 16),
                color: AppColors.textTertiary,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.only(left: 8),
                tooltip: 'gate_folio'.tr(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tarjetaSolicitud() {
    final estado = (_solicitud?['status'] as String?) ?? 'pending';
    final notas = (_solicitud?['review_notes'] as String?)?.trim();
    final enviada = _solicitud?['submitted_at'] as String?;

    final String texto;
    final Color color;
    final IconData icono;
    switch (estado) {
      case 'approved':
      case 'accepted':
        texto = 'gate_request_approved'.tr();
        color = AppColors.success;
        icono = Icons.check_circle_outline_rounded;
      case 'rejected':
      case 'denied':
        texto = 'gate_request_rejected'.tr();
        color = AppColors.error;
        icono = Icons.cancel_outlined;
      default:
        texto = 'gate_request_pending'.tr();
        color = AppColors.warning;
        icono = Icons.schedule_rounded;
    }

    String? fecha;
    if (enviada != null) {
      final cuando = DateTime.tryParse(enviada);
      if (cuando != null) {
        fecha = 'gate_request_sent_on'.tr(
          namedArgs: {'fecha': DateFormat.yMMMd().format(cuando.toLocal())},
        );
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  texto,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (fecha != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    fecha,
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (notas != null && notas.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    notas,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Las salidas. Siempre hay al menos tres que funcionan sin depender de nadie:
  /// escribir a soporte, copiar el correo y cerrar sesion.
  Widget _tarjetaSalidas(_Aspecto a) {
    final yaPidio = _solicitud != null &&
        ((_solicitud?['status'] as String?) ?? 'pending') == 'pending';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'gate_exit_title'.tr(),
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 14),

          if (a.puedeCompletarDocumentos)
            _boton(
              icono: Icons.folder_open_rounded,
              etiqueta: 'gate_complete_docs'.tr(),
              principal: true,
              onTap: () => Navigator.pushNamed(context, '/documents'),
            )
          else
            _boton(
              icono: Icons.gavel_rounded,
              etiqueta: 'gate_ask_review'.tr(),
              principal: true,
              cargando: _enviando,
              onTap: (_enviando || yaPidio) ? null : _pedirRevision,
            ),

          const SizedBox(height: 10),
          _boton(
            icono: Icons.mail_outline_rounded,
            etiqueta: 'gate_write_support'.tr(),
            onTap: _escribirSoporte,
          ),
          const SizedBox(height: 10),
          _boton(
            icono: Icons.copy_rounded,
            etiqueta: _correoSoporte,
            onTap: () => _copiar(_correoSoporte),
          ),
          const SizedBox(height: 10),
          _boton(
            icono: Icons.refresh_rounded,
            etiqueta: _isChecking ? 'gate_checking'.tr() : 'gate_check'.tr(),
            cargando: _isChecking,
            onTap: _isChecking ? null : _revisarEstado,
          ),
        ],
      ),
    );
  }

  Widget _boton({
    required IconData icono,
    required String etiqueta,
    required VoidCallback? onTap,
    bool principal = false,
    bool cargando = false,
  }) {
    final apagado = onTap == null;
    final colorTexto = principal
        ? AppColors.textPrimary
        : (apagado ? AppColors.textDisabled : AppColors.primary);

    return SizedBox(
      width: double.infinity,
      child: Material(
        color: principal
            ? (apagado ? AppColors.cardSecondary : AppColors.primary)
            : AppColors.cardSecondary,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: principal
                  ? null
                  : Border.all(
                      color: apagado
                          ? AppColors.border
                          : AppColors.primary.withValues(alpha: 0.4),
                    ),
            ),
            child: Row(
              children: [
                if (cargando)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorTexto,
                    ),
                  )
                else
                  Icon(icono, size: 18, color: colorTexto),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    etiqueta,
                    style: TextStyle(
                      color: colorTexto,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Como se ve la pantalla segun el estado del chofer. Existe para que el titulo,
/// el icono, el color y el mensaje NUNCA se contradigan entre si (el bug de
/// antes: titulo "PENDING APPROVAL" con el texto "has been suspended").
class _Aspecto {
  const _Aspecto({
    required this.titulo,
    required this.mensaje,
    required this.icono,
    required this.color,
    required this.puedeCompletarDocumentos,
  });

  final String titulo;
  final String mensaje;
  final IconData icono;
  final Color color;

  /// Solo tiene sentido mandarlo a subir papeles cuando esta en revision. A un
  /// suspendido o rechazado, subir otra foto no le sirve de nada.
  final bool puedeCompletarDocumentos;
}
