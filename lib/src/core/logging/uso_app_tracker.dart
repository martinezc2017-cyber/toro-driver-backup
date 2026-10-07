import 'dart:math';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';

import 'toro_app_logger.dart';

/// Qué pantallas abre el chofer (mismo formato que el rider: `source='nav'`,
/// `event='pantalla'`, `context.pantalla` / `sesion`), para la pestaña
/// "Uso de la app" del Command Center.
///
/// La app del chofer navega de dos formas: rutas con nombre (`/documents`) y
/// `MaterialPageRoute` sin nombre. Para las sin nombre se toma el tipo de la
/// pantalla (`DocumentsScreen`) buscándolo en el árbol ya dibujado. La
/// pantalla raíz la elige AuthWrapper sin navegar: la marca con [marcar].
/// Nunca viajan ids ni datos personales, solo el nombre de la pantalla.
class UsoAppTracker {
  UsoAppTracker._();

  static String pantallaActual = '/';
  static final String sesion = _nuevaSesion();
  static String? _ultima;

  /// Lo que muestra AuthWrapper en la raíz (login, alta, inicio…): al
  /// regresar a la raíz se vuelve a contar esa pantalla.
  static String? _raiz;

  static final NavigatorObserver observer = _Observador();

  static String _nuevaSesion() {
    final r = Random.secure();
    return List.generate(12, (_) => r.nextInt(36).toRadixString(36)).join();
  }

  /// Pantalla raíz que eligió AuthWrapper (no hay navegación de por medio).
  /// [visible] = la raíz está al frente (si hay otra pantalla encima, solo
  /// se recuerda para cuando regrese).
  static void marcarRaiz(String pantalla, {bool visible = true}) {
    _raiz = pantalla;
    if (visible) marcar(pantalla);
  }

  /// Registra que el chofer está viendo [pantalla] (no repite la misma).
  static void marcar(String pantalla) {
    if (pantalla.isEmpty || pantalla == _ultima) return;
    final desde = _ultima;
    _ultima = pantalla;
    pantallaActual = pantalla;
    ToroAppLogger.info(
      source: 'nav',
      event: 'pantalla',
      context: contexto(extra: {if (desde != null) 'desde': desde}),
    );
  }

  /// Datos comunes de cada evento: pantalla, sesión, hora local y país del
  /// teléfono.
  static Map<String, dynamic> contexto({Map<String, dynamic>? extra}) => {
        'pantalla': pantallaActual,
        'sesion': sesion,
        'tz_min': DateTime.now().timeZoneOffset.inMinutes,
        'ts': DateTime.now().toUtc().toIso8601String(),
        'pais': PlatformDispatcher.instance.locale.countryCode ?? '',
        ...?extra,
      };

  /// Nombre de la pantalla de una ruta: su nombre si lo tiene; si no, el
  /// primer widget `...Screen` / `...Page` dentro de ella.
  static void _registrarRuta(Route<dynamic>? route) {
    if (route == null || route is PopupRoute) return; // diálogos y menús no
    if (route.isFirst) {
      final raiz = _raiz;
      if (raiz != null) marcar(raiz);
      return;
    }
    final nombre = route.settings.name;
    if (nombre != null && nombre.isNotEmpty && nombre != '/') {
      marcar(nombre);
      return;
    }
    // Sin nombre: esperar a que se dibuje y buscar el tipo de la pantalla.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = route is ModalRoute ? route.subtreeContext : null;
      final tipo = ctx == null ? null : _buscarPantalla(ctx);
      if (tipo != null) marcar(tipo);
    });
  }

  static String? _buscarPantalla(BuildContext ctx) {
    String? hallado;
    var visitados = 0;
    void visitar(Element e) {
      if (hallado != null || visitados > 400) return;
      visitados++;
      final t = e.widget.runtimeType.toString();
      if (t.endsWith('Screen') || t.endsWith('Page')) {
        hallado = t;
        return;
      }
      e.visitChildElements(visitar);
    }

    try {
      (ctx as Element).visitChildElements(visitar);
    } catch (_) {}
    return hallado;
  }
}

class _Observador extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      UsoAppTracker._registrarRuta(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      UsoAppTracker._registrarRuta(newRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      UsoAppTracker._registrarRuta(previousRoute);
}
