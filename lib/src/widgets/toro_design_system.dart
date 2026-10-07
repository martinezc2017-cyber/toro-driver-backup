import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

/// Sistema de diseño TORO. Solo presentación: ningún widget de aquí navega,
/// consulta datos ni decide reglas de negocio.
///
/// Lenguaje "TORO eléctrico": arriba una franja azul profundo con la luz y las
/// estelas del logo ([ToroBand]); debajo el contenido claro donde se lee todo;
/// entre los dos, tarjetas de cristal ([ToroGlass]). Botones con volumen
/// ([ToroRaised]): luz arriba, canto del mismo color abajo, sombra profunda y
/// se hunden al tocar. Azul eléctrico = acción y selección. Dorado real del
/// branding = agendar y recompensas. Verde/ámbar/rojo = solo significado.
abstract final class ToroColors {
  // Azul de la marca (sale del logo)
  static const ink = Color(0xFF061233); // franja, fondo del logo
  static const ink2 = Color(0xFF0B2A6B);
  static const ink3 = Color(0xFF0A2F8A);
  static const blue = AppColors.primary; // #1769FF eléctrico
  static const blueDeep = AppColors.primaryDark;
  static const blueLight = Color(0xFF4F93FF);
  static const blueEdge = Color(0xFF0B46B5); // canto 3D
  static const cyan = Color(0xFF35C6FF);
  static const glow = Color(0xFF7FD8FF);
  static const blueSoft = AppColors.accentSoft; // #EAF2FF
  // Texto y superficies claras
  static const navy = AppColors.textPrimary; // #102A56
  static const textMid = AppColors.textSecondary;
  static const textLow = AppColors.textDisabled;
  static const bg = AppColors.background;
  static const bgWarm = AppColors.backgroundWarm;
  static const surface = AppColors.surface;
  static const surface2 = AppColors.cardSecondary;
  static const border = AppColors.border;
  static const edge = Color(0xFFD5DEEC); // canto 3D de lo blanco
  // Dorado real del branding
  static const gold = AppColors.gold; // #D4AF37
  static const goldDeep = AppColors.goldDeep; // #B8860B
  static const goldLight = Color(0xFFF6D97A);
  static const goldEdge = Color(0xFF9C7420);
  static const goldSoft = AppColors.goldSoft;
  // Semánticos
  static const green = Color(0xFF17B897);
  static const greenEdge = Color(0xFF0B7A63);
  static const greenText = AppColors.success;
  static const greenSoft = AppColors.successSoft;
  static const red = Color(0xFFE5484D);
  static const redSoft = AppColors.errorSoft;
  static const amber = Color(0xFFB7791F);
  static const amberSoft = Color(0xFFFFF6E5);
  static const purple = Color(0xFF6B3FD9);
  static const purpleSoft = Color(0xFFF1EAFF);
}

abstract final class ToroSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double page = 20;
  static const double maxContentWidth = 1240;
  /// Alto reservado para el dock flotante + aire (sin el safe area inferior).
  static const double dockClearance = 100;
}

abstract final class ToroRadius {
  static const double control = 12;
  static const double button = 16;
  static const double card = 24;
  static const double panel = 28;
  static const double pill = 999;
}

abstract final class ToroShadows {
  static const card = [
    BoxShadow(color: Color(0x0F0F2454), blurRadius: 30, offset: Offset(0, 10)),
  ];
  static const floating = [
    BoxShadow(color: Color(0x2E061233), blurRadius: 50, offset: Offset(0, 20)),
    BoxShadow(color: Color(0x0A061233), blurRadius: 6, offset: Offset(0, 2)),
  ];
  static const dock = [
    BoxShadow(color: Color(0x38061233), blurRadius: 44, offset: Offset(0, 18)),
    BoxShadow(color: Color(0x0F061233), blurRadius: 6, offset: Offset(0, 2)),
  ];
}

/// Breakpoints compartidos: 1 columna en teléfono, 2 en tableta vertical, 3 en
/// tableta horizontal / escritorio.
abstract final class ToroBreakpoints {
  static const double tablet = 640;
  static const double wide = 1024;
  static int columns(double width, {int max = 3}) =>
      (width >= wide ? 3 : width >= tablet ? 2 : 1).clamp(1, max);
  static bool isWide(BuildContext c) => MediaQuery.sizeOf(c).width >= tablet;
}

/// Tipografía: los títulos en la fuente de display del tema, el resto Inter.
abstract final class ToroType {
  static TextStyle display(BuildContext c, {double size = 30, Color color = Colors.white}) =>
      (Theme.of(c).textTheme.headlineMedium ?? const TextStyle()).copyWith(
          fontSize: size, fontWeight: FontWeight.w800, letterSpacing: -size * .03, height: 1.1, color: color);
  static TextStyle title(BuildContext c, {double size = 17, Color color = ToroColors.navy}) =>
      (Theme.of(c).textTheme.titleMedium ?? const TextStyle()).copyWith(
          fontSize: size, fontWeight: FontWeight.w800, letterSpacing: -.2, height: 1.2, color: color);
  static TextStyle body(BuildContext c, {double size = 13.5, Color color = ToroColors.textMid, FontWeight weight = FontWeight.w500}) =>
      (Theme.of(c).textTheme.bodyMedium ?? const TextStyle()).copyWith(
          fontSize: size, fontWeight: weight, height: 1.4, color: color);
}

// =============================================================================
// FONDOS: franja eléctrica y bruma clara
// =============================================================================

/// Pinta la luz del logo: dos resplandores cian y tres estelas inclinadas.
/// Son degradados; sin filtros de desenfoque.
class _ElectricLightPainter extends CustomPainter {
  const _ElectricLightPainter({this.intensity = 1});
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    void glow(Offset c, double r, Color color) {
      final p = Paint()
        ..shader = RadialGradient(colors: [color.withValues(alpha: color.a * intensity), color.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: c, radius: r));
      canvas.drawCircle(c, r, p);
    }
    glow(Offset(w * 1.02, -h * .15), math.max(w * .55, 220), const Color(0x8C35C6FF));
    glow(Offset(-w * .15, h * 1.05), math.max(w * .5, 200), const Color(0x4D7FD8FF));
    void streak(Offset from, Offset to, double width, double alpha) {
      final p = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = width
        ..shader = LinearGradient(colors: [
          const Color(0x007FD8FF),
          Color.fromRGBO(127, 216, 255, alpha * intensity),
          Color.fromRGBO(255, 255, 255, alpha * intensity),
          Color.fromRGBO(127, 216, 255, alpha * .6 * intensity),
          const Color(0x007FD8FF),
        ]).createShader(Rect.fromPoints(from, to));
      canvas.drawLine(from, to, p);
    }
    streak(Offset(w * .55, h * .62), Offset(w * 1.1, h * .18), 3, .85);
    streak(Offset(w * .62, h * .78), Offset(w * 1.05, h * .42), 2, .45);
    streak(Offset(-w * .1, h * 1.0), Offset(w * .55, h * .72), 2, .5);
  }

  @override
  bool shouldRepaint(_ElectricLightPainter old) => old.intensity != intensity;
}

/// Franja superior azul profundo con la luz del logo. Lo que va encima va en
/// blanco. [overlap] deja espacio abajo para que el contenido se le monte.
class ToroBand extends StatelessWidget {
  const ToroBand({super.key, required this.child, this.overlap = 56,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 0), this.radius = 0,
    this.intensity = 1});
  final Widget child;
  final double overlap;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double intensity;

  static const gradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFF040C24), Color(0xFF07173F), Color(0xFF0A2F8A)],
    stops: [0, .45, 1],
  );

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: gradient),
        child: CustomPaint(
          painter: _ElectricLightPainter(intensity: intensity),
          child: Padding(
            padding: padding.add(EdgeInsets.only(bottom: overlap)),
            child: DefaultTextStyle.merge(style: const TextStyle(color: Colors.white), child: child),
          ),
        ),
      ),
    );
  }
}

/// Franja + contenido que se le monta [overlap] px. Para pantallas con scroll:
/// úsalo como primer sliver/elemento y pasa el resto en [children].
class ToroBandPage extends StatelessWidget {
  const ToroBandPage({super.key, required this.band, required this.children,
    this.overlap = 52, this.bandOverlap = 72, this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.gap = 12, this.maxWidth = ToroSpacing.maxContentWidth});
  final Widget band;
  final List<Widget> children;
  final double overlap;
  final double bandOverlap;
  final EdgeInsetsGeometry padding;
  final double gap;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ToroBand(overlap: bandOverlap, padding: EdgeInsets.fromLTRB(20, top + 6, 20, 0),
        child: Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: band))),
      Transform.translate(
        offset: Offset(0, -overlap),
        child: Padding(
          padding: padding,
          child: Center(child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: gap), children[i]],
            ]),
          )),
        ),
      ),
    ]);
  }
}

/// Fondo claro de toda la app: blanco cálido con bruma azul y dorada (dos
/// degradados radiales, sin blur).
class ToroBackdrop extends StatelessWidget {
  const ToroBackdrop({super.key, this.child, this.warm = true});
  final Widget? child;
  final bool warm;

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      ColoredBox(color: warm ? ToroColors.bgWarm : ToroColors.bg),
      const Positioned(top: -140, right: -120, child: IgnorePointer(child: _Haze(size: 460, color: Color(0x261769FF)))),
      const Positioned(top: 160, left: -180, child: IgnorePointer(child: _Haze(size: 380, color: Color(0x12D4AF37)))),
      const Positioned(bottom: -200, right: -60, child: IgnorePointer(child: _Haze(size: 420, color: Color(0x14D4AF37)))),
      if (child != null) child!,
    ]);
  }
}

class _Haze extends StatelessWidget {
  const _Haze({required this.size, required this.color});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(width: size, height: size,
      decoration: BoxDecoration(shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)])));
}

// =============================================================================
// MARCA (logo real, sin redibujar)
// =============================================================================

/// El logo oficial de TORO: assets/images/toro_logo.png, el mismo del ícono de
/// la app. Solo se le pone aire y luz alrededor; nunca se redibuja.
class ToroLogo extends StatelessWidget {
  const ToroLogo({super.key, this.size = 48, this.glow = true});
  final double size;
  final bool glow;
  @override
  Widget build(BuildContext context) => Container(
        width: size, height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * .31),
          boxShadow: glow ? [
            BoxShadow(color: const Color(0x8C1769FF), blurRadius: size * .6, offset: Offset(0, size * .2)),
            BoxShadow(color: const Color(0x5935C6FF), blurRadius: size * .5),
          ] : null,
          border: Border.all(color: const Color(0x597FD8FF), width: .8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.asset('assets/images/toro_logo.png', width: size, height: size,
            fit: BoxFit.cover, filterQuality: FilterQuality.medium, semanticLabel: 'TORO'),
      );
}

/// Logo + palabra TORO (+ eslogan opcional). [onDark] para la franja.
class ToroBrand extends StatelessWidget {
  const ToroBrand({super.key, this.size = 44, this.showName = true, this.tagline,
    this.onDark = true, this.markColor, this.nameColor});
  final double size;
  final bool showName;
  final String? tagline;
  final bool onDark;
  // Compatibilidad con llamadas viejas; se ignoran (el logo es la imagen real).
  final Color? markColor;
  final Color? nameColor;

  @override
  Widget build(BuildContext context) {
    final name = nameColor ?? (onDark ? Colors.white : ToroColors.navy);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ToroLogo(size: size, glow: onDark),
      if (showName) ...[
        SizedBox(width: size * .25),
        Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('TORO', style: ToroType.display(context, size: size * .5, color: name).copyWith(
              letterSpacing: size * .03, shadows: onDark ? const [Shadow(color: Color(0x8035C6FF), blurRadius: 18)] : null)),
          if (tagline != null)
            Text(tagline!, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: ToroType.body(context, size: size * .26, color: onDark ? const Color(0xB3FFFFFF) : ToroColors.textMid)),
        ]),
      ],
    ]);
  }
}

// =============================================================================
// 3D: decoraciones con volumen y el gesto de hundirse
// =============================================================================

enum ToroTone { blue, gold, white, green, red, navy }

/// Decoración con volumen: degradado de luz arriba a sombra abajo, un "canto"
/// del mismo color y sombra profunda. [pressed] baja el canto.
abstract final class ToroRaised {
  static const double lift = 5;

  static ({List<Color> face, Color edge, Color shadow, Color fg}) palette(ToroTone t) {
    switch (t) {
      case ToroTone.blue:
        return (face: const [Color(0xFF4F93FF), Color(0xFF1769FF), Color(0xFF0F55D6)], edge: ToroColors.blueEdge, shadow: const Color(0x6B1769FF), fg: Colors.white);
      case ToroTone.gold:
        return (face: const [Color(0xFFF6D97A), Color(0xFFE2B84A), Color(0xFFC9982F)], edge: ToroColors.goldEdge, shadow: const Color(0x61B8860B), fg: const Color(0xFF2B1B00));
      case ToroTone.green:
        return (face: const [Color(0xFF4FD6B5), Color(0xFF17B897), Color(0xFF0F9A7D)], edge: ToroColors.greenEdge, shadow: const Color(0x6117B897), fg: Colors.white);
      case ToroTone.red:
        return (face: const [Color(0xFFFF7A80), Color(0xFFE5484D), Color(0xFFC63A3F)], edge: const Color(0xFF9E2A2F), shadow: const Color(0x61E5484D), fg: Colors.white);
      case ToroTone.navy:
        return (face: const [Color(0xFF1E3A70), Color(0xFF102A56), Color(0xFF0A1C3D)], edge: const Color(0xFF061233), shadow: const Color(0x66061233), fg: Colors.white);
      case ToroTone.white:
        return (face: const [Color(0xFFFFFFFF), Color(0xFFF3F6FB)], edge: ToroColors.edge, shadow: const Color(0x24102A56), fg: ToroColors.navy);
    }
  }

  static BoxDecoration decoration(ToroTone tone, {bool pressed = false, double radius = ToroRadius.button,
      BoxShape shape = BoxShape.rectangle, bool enabled = true}) {
    final p = palette(tone);
    final liftNow = pressed ? 2.0 : lift;
    return BoxDecoration(
      shape: shape,
      borderRadius: shape == BoxShape.circle ? null : BorderRadius.circular(radius),
      gradient: enabled
          ? LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: p.face)
          : const LinearGradient(colors: [Color(0xFFE6EAF0), Color(0xFFDCE2EB)]),
      border: Border(top: BorderSide(color: tone == ToroTone.white ? Colors.white : const Color(0x8CFFFFFF), width: 1)),
      boxShadow: !enabled ? null : [
        BoxShadow(color: p.edge, offset: Offset(0, liftNow)),
        BoxShadow(color: p.shadow, blurRadius: pressed ? 14 : 26, offset: Offset(0, pressed ? 6 : 12)),
        const BoxShadow(color: Color(0x14061233), blurRadius: 3, offset: Offset(0, 1)),
      ],
    );
  }
}

/// Se hunde al tocar (baja 3 px y se encoge 1.5 %). Da el estado presionado al
/// [builder] para que la decoración baje el canto.
class ToroPressable extends StatefulWidget {
  const ToroPressable({super.key, required this.builder, this.onTap, this.onLongPress, this.semanticLabel});
  final Widget Function(BuildContext context, bool pressed) builder;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;
  @override
  State<ToroPressable> createState() => _ToroPressableState();
}

class _ToroPressableState extends State<ToroPressable> {
  bool _down = false;
  void _set(bool v) { if (_down != v && mounted) setState(() => _down = v); }
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    final pressed = _down && enabled;
    return Semantics(
      button: enabled, label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: enabled ? () => _set(false) : null,
        onTap: widget.onTap, onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: pressed ? .985 : 1, duration: const Duration(milliseconds: 110), curve: Curves.easeOut,
          child: AnimatedSlide(
            offset: Offset(0, pressed ? .035 : 0), duration: const Duration(milliseconds: 110), curve: Curves.easeOut,
            child: widget.builder(context, pressed),
          ),
        ),
      ),
    );
  }
}

/// Botón principal con volumen.
class ToroPrimaryButton extends StatelessWidget {
  const ToroPrimaryButton({super.key, required this.label, this.onPressed, this.icon,
    this.loading = false, this.expanded = true, this.tone = ToroTone.blue, this.height = 52,
    this.color, this.foreground});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expanded;
  final ToroTone tone;
  final double height;
  // Compatibilidad: un color suelto se trata como tono plano.
  final Color? color;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final p = ToroRaised.palette(tone);
    final fg = enabled ? (foreground ?? p.fg) : ToroColors.textMid;
    return ToroPressable(
      onTap: enabled ? onPressed : null, semanticLabel: label,
      builder: (context, pressed) => AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        height: height, width: expanded ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: color != null && enabled
            ? BoxDecoration(color: color, borderRadius: BorderRadius.circular(ToroRadius.button),
                boxShadow: [BoxShadow(color: color!.withValues(alpha: .35), blurRadius: 20, offset: const Offset(0, 10))])
            : ToroRaised.decoration(tone, pressed: pressed, enabled: enabled),
        child: Center(
          child: loading
              ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  if (icon != null) ...[Icon(icon, size: 20, color: fg), const SizedBox(width: 8)],
                  Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: fg, fontSize: 15.5, fontWeight: FontWeight.w800, letterSpacing: .1))),
                ]),
        ),
      ),
    );
  }
}

/// Botón secundario: blanco con canto, o azul suave plano ([tinted]).
class ToroSecondaryButton extends StatelessWidget {
  const ToroSecondaryButton({super.key, required this.label, this.onPressed, this.icon,
    this.expanded = true, this.color = ToroColors.blue, this.height = 52, this.tinted = false});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;
  final Color color;
  final double height;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return ToroPressable(
      onTap: onPressed, semanticLabel: label,
      builder: (context, pressed) => AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        height: height, width: expanded ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: tinted
            ? BoxDecoration(color: color.withValues(alpha: pressed ? .14 : .09), borderRadius: BorderRadius.circular(ToroRadius.button))
            : ToroRaised.decoration(ToroTone.white, pressed: pressed, enabled: enabled),
        child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 19, color: enabled ? color : ToroColors.textLow), const SizedBox(width: 8)],
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: enabled ? (tinted ? color : ToroColors.navy) : ToroColors.textLow,
                  fontSize: 15, fontWeight: FontWeight.w800))),
        ])),
      ),
    );
  }
}

/// Cuadro de ícono con volumen (el "azulejo" de los bento y las acciones).
class ToroIconTile extends StatelessWidget {
  const ToroIconTile({super.key, required this.icon, this.color = ToroColors.blue,
    this.size = 52, this.radius = 16, this.filled = false, this.tone, this.onTap});
  final IconData icon;
  final Color color;
  final double size;
  final double radius;
  /// Relleno sólido con volumen (tono según [tone] o azul).
  final bool filled;
  final ToroTone? tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Widget box(bool pressed) {
      if (filled) {
        final t = tone ?? ToroTone.blue;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 110), width: size, height: size,
          decoration: ToroRaised.decoration(t, pressed: pressed, radius: radius),
          child: Icon(icon, color: ToroRaised.palette(t).fg, size: size * .48),
        );
      }
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .11), borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: color.withValues(alpha: .10)),
        ),
        child: Icon(icon, color: color, size: size * .5),
      );
    }
    if (onTap == null) return box(false);
    return ToroPressable(onTap: onTap, builder: (_, p) => box(p));
  }
}

/// Acción redonda translúcida para la franja (campana, regresar, favoritos).
class ToroGhostAction extends StatelessWidget {
  const ToroGhostAction({super.key, required this.icon, required this.onPressed,
    this.tooltip, this.badge, this.dot = false, this.size = 44});
  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final String? badge;
  final bool dot;
  final double size;
  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: const Color(0x1AFFFFFF),
      shape: const CircleBorder(side: BorderSide(color: Color(0x38FFFFFF), width: .9)),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: tooltip, onPressed: onPressed,
        icon: Icon(icon, color: Colors.white, size: size * .47),
        constraints: BoxConstraints(minWidth: size, minHeight: size), padding: EdgeInsets.zero,
      ),
    );
    return _withBadge(btn, badge: badge, dot: dot, ring: ToroColors.ink2);
  }
}

/// Acción redonda blanca con canto (en el contenido claro).
class ToroRoundAction extends StatelessWidget {
  const ToroRoundAction({super.key, required this.icon, required this.onPressed,
    this.tooltip, this.badge, this.dot = false, this.color = ToroColors.navy, this.size = 46});
  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final String? badge;
  final bool dot;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) {
    final btn = Tooltip(
      message: tooltip ?? '',
      child: ToroPressable(
        onTap: onPressed, semanticLabel: tooltip,
        builder: (_, pressed) => AnimatedContainer(
          duration: const Duration(milliseconds: 110), width: size, height: size,
          decoration: ToroRaised.decoration(ToroTone.white, pressed: pressed, shape: BoxShape.circle),
          child: Icon(icon, color: color, size: size * .47),
        ),
      ),
    );
    return _withBadge(btn, badge: badge, dot: dot, ring: Colors.white);
  }
}

Widget _withBadge(Widget child, {String? badge, bool dot = false, required Color ring}) {
  if (badge == null && !dot) return child;
  return Stack(clipBehavior: Clip.none, children: [
    child,
    Positioned(
      top: dot ? 9 : 2, right: dot ? 9 : 0,
      child: Container(
        padding: dot ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        constraints: BoxConstraints(minWidth: dot ? 10 : 18, minHeight: dot ? 10 : 18),
        decoration: BoxDecoration(color: const Color(0xFFFF5D6C), borderRadius: BorderRadius.circular(9),
            border: Border.all(color: ring, width: 1.5),
            boxShadow: const [BoxShadow(color: Color(0x80FF5D6C), blurRadius: 8)]),
        child: dot ? null : Center(child: Text(badge!, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, height: 1.2))),
      ),
    ),
  ]);
}

/// Regresar: translúcido en la franja ([onDark]) o blanco con canto.
class ToroBackButton extends StatelessWidget {
  const ToroBackButton({super.key, this.onPressed, this.onDark = false, this.icon = Icons.arrow_back_rounded});
  final VoidCallback? onPressed;
  final bool onDark;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final tip = MaterialLocalizations.of(context).backButtonTooltip;
    final go = onPressed ?? () => Navigator.of(context).maybePop();
    return onDark ? ToroGhostAction(icon: icon, onPressed: go, tooltip: tip)
                  : ToroRoundAction(icon: icon, onPressed: go, tooltip: tip);
  }
}

// =============================================================================
// SUPERFICIES
// =============================================================================

/// Tarjeta blanca con canto suave (la tarjeta estándar).
class ToroCard extends StatelessWidget {
  const ToroCard({super.key, required this.child, this.padding = const EdgeInsets.all(18),
    this.onTap, this.color, this.borderRadius = ToroRadius.card, this.shadow = ToroShadows.card,
    this.raised = true});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final double borderRadius;
  final List<BoxShadow> shadow;
  /// Con canto (3D). false = plana con sombra suave.
  final bool raised;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    Widget body(bool pressed) => AnimatedContainer(
      duration: const Duration(milliseconds: 110),
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: color == null ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFD)]) : null,
        color: color,
        border: Border.all(color: Colors.white, width: 1),
        boxShadow: raised
            ? [BoxShadow(color: ToroColors.edge, offset: Offset(0, pressed ? 2 : 5)), ...shadow]
            : shadow,
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return body(false);
    return ToroPressable(onTap: onTap, builder: (_, p) => body(p));
  }
}

/// Tarjeta de cristal: blanca translúcida con brillo, para montarse sobre la
/// franja (buscador, "lo que sigue", acciones).
class ToroGlass extends StatelessWidget {
  const ToroGlass({super.key, required this.child, this.padding = const EdgeInsets.all(16),
    this.onTap, this.borderRadius = ToroRadius.card, this.dark = false});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double borderRadius;
  /// Cristal oscuro (sobre la franja, sin salir de ella).
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    Widget body(bool pressed) => AnimatedContainer(
      duration: const Duration(milliseconds: 110),
      decoration: BoxDecoration(
        borderRadius: radius,
        color: dark ? const Color(0x1FFFFFFF) : const Color(0xF2FFFFFF),
        border: Border.all(color: dark ? const Color(0x40FFFFFF) : Colors.white, width: 1),
        boxShadow: dark ? null : [
          BoxShadow(color: ToroColors.edge, offset: Offset(0, pressed ? 2 : 4)),
          ...ToroShadows.floating,
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return body(false);
    return ToroPressable(onTap: onTap, builder: (_, p) => body(p));
  }
}

/// Tarjeta "bento": ícono en cuadro, título, subtítulo y flecha en círculo.
/// [hero] = azul eléctrico con volumen (la acción principal del grupo).
class ToroBentoTile extends StatelessWidget {
  const ToroBentoTile({super.key, required this.icon, required this.title, required this.onTap,
    this.subtitle, this.color = ToroColors.blue, this.trailing, this.titleExtras = const [],
    this.dense = false, this.filledIcon = false, this.hero = false, this.tone});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Color color;
  final Widget? trailing;
  final List<Widget> titleExtras;
  final bool dense;
  final bool filledIcon;
  final bool hero;
  final ToroTone? tone;

  @override
  Widget build(BuildContext context) {
    final fg = hero ? Colors.white : ToroColors.navy;
    final sub = hero ? const Color(0xD6FFFFFF) : ToroColors.textMid;
    final row = Row(children: [
      hero
          ? Container(width: dense ? 46 : 54, height: dense ? 46 : 54,
              decoration: BoxDecoration(color: const Color(0x2EFFFFFF), borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x59FFFFFF))),
              child: Icon(icon, color: Colors.white, size: dense ? 23 : 27))
          : ToroIconTile(icon: icon, color: color, size: dense ? 46 : 54, filled: filledIcon, tone: tone),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: ToroType.title(context, size: hero ? 19 : (dense ? 15.5 : 17), color: fg))),
          ...titleExtras,
        ]),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: ToroType.body(context, size: 13, color: sub)),
        ],
      ])),
      const SizedBox(width: 8),
      if (trailing != null) ...[trailing!, const SizedBox(width: 8)],
      ToroChevron(onDark: hero),
    ]);
    if (hero) {
      return ToroPressable(
        onTap: onTap, semanticLabel: title,
        builder: (_, pressed) => AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          padding: EdgeInsets.all(dense ? 14 : 18),
          decoration: ToroRaised.decoration(tone ?? ToroTone.blue, pressed: pressed, radius: ToroRadius.card).copyWith(
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xFF2E7BFF), Color(0xFF1769FF), Color(0xFF0A3FA8)], stops: [0, .45, 1]),
          ),
          child: row,
        ),
      );
    }
    return ToroCard(onTap: onTap, padding: EdgeInsets.all(dense ? 14 : 18), child: row);
  }
}

class ToroChevron extends StatelessWidget {
  const ToroChevron({super.key, this.onDark = false, this.size = 32});
  final bool onDark;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size, height: size,
        decoration: BoxDecoration(color: onDark ? const Color(0x33FFFFFF) : ToroColors.surface2, shape: BoxShape.circle),
        child: Icon(Icons.chevron_right_rounded, color: onDark ? Colors.white : ToroColors.navy, size: size * .62),
      );
}

// =============================================================================
// ENCABEZADOS
// =============================================================================

/// Encabezado de página. Con [showLogo]: marca grande + acciones y debajo el
/// título. Sin él: regresar + título + acciones. [onDark] para usarlo dentro de
/// [ToroBand] (texto blanco, acciones translúcidas).
class ToroPageHeader extends StatelessWidget {
  const ToroPageHeader({super.key, required this.title, this.subtitle, this.showLogo = false,
    this.actions = const [], this.leading, this.onDark = false, this.tagline,
    this.padding = const EdgeInsets.fromLTRB(0, 4, 0, 8)});
  final String title;
  final String? subtitle;
  final bool showLogo;
  final List<Widget> actions;
  final Widget? leading;
  final bool onDark;
  final String? tagline;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? Colors.white : ToroColors.navy;
    final sub = onDark ? const Color(0xB8FFFFFF) : ToroColors.textMid;
    final titleBlock = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(title, style: ToroType.display(context, size: showLogo ? 28 : 24, color: fg)),
      if (subtitle != null) ...[const SizedBox(height: 4), Text(subtitle!, style: ToroType.body(context, size: 13.5, color: sub))],
    ]);
    final acts = [for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(width: 8), actions[i]]];
    return Padding(
      padding: padding,
      child: showLogo
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (leading != null) ...[leading!, const SizedBox(width: 12)],
                Flexible(child: ToroBrand(size: 44, onDark: onDark, tagline: tagline)),
                const Spacer(), ...acts,
              ]),
              const SizedBox(height: 18),
              titleBlock,
            ])
          : Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Expanded(child: titleBlock),
              const SizedBox(width: 8), ...acts,
            ]),
    );
  }
}

class ToroSectionHeader extends StatelessWidget {
  const ToroSectionHeader({super.key, required this.title, this.subtitle, this.trailing, this.icon,
    this.iconColor = ToroColors.gold, this.padding = const EdgeInsets.fromLTRB(2, 10, 2, 10)});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final IconData? icon;
  final Color iconColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (icon != null) ...[Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, color: iconColor, size: 22)), const SizedBox(width: 10)],
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: ToroType.title(context, size: 18)),
            if (subtitle != null) ...[const SizedBox(height: 3), Text(subtitle!, style: ToroType.body(context))],
          ])),
          if (trailing != null) trailing!,
        ]),
      );
}

class ToroSeeAll extends StatelessWidget {
  const ToroSeeAll({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 36), foregroundColor: ToroColors.blue),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
          const Icon(Icons.chevron_right_rounded, size: 18),
        ]),
      );
}

// =============================================================================
// CONTROLES
// =============================================================================

/// Buscador TORO: cristal blanco, lupa azul, botón de filtros con volumen.
class ToroSearchBar extends StatelessWidget {
  const ToroSearchBar({super.key, required this.hint, this.controller, this.onChanged, this.onSubmitted,
    this.onTap, this.onFilterTap, this.onClear, this.readOnly = false, this.autofocus = false,
    this.showClear = false, this.margin = EdgeInsets.zero, this.focusNode, this.leadingIcon = Icons.search_rounded});
  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final VoidCallback? onFilterTap;
  final VoidCallback? onClear;
  final bool readOnly;
  final bool autofocus;
  final bool showClear;
  final EdgeInsetsGeometry margin;
  final FocusNode? focusNode;
  final IconData leadingIcon;

  @override
  Widget build(BuildContext context) {
    Widget? suffix;
    if (showClear && onClear != null) {
      suffix = IconButton(icon: const Icon(Icons.close_rounded, color: ToroColors.textMid), onPressed: onClear);
    } else if (onFilterTap != null) {
      suffix = Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Center(widthFactor: 1, child: ToroIconTile(icon: Icons.tune_rounded, size: 38, radius: 19, filled: true, onTap: onFilterTap)),
      );
    }
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: [
          const BoxShadow(color: ToroColors.edge, offset: Offset(0, 4)), ...ToroShadows.floating]),
        child: TextField(
          controller: controller, focusNode: focusNode, onChanged: onChanged, onSubmitted: onSubmitted,
          onTap: onTap, readOnly: readOnly, autofocus: autofocus,
          textInputAction: TextInputAction.search, cursorColor: ToroColors.blue,
          style: const TextStyle(color: ToroColors.navy, fontSize: 15.5, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: ToroColors.textMid, fontSize: 14.5, fontWeight: FontWeight.w500),
            prefixIcon: Icon(leadingIcon, color: ToroColors.blue, size: 26),
            prefixIconConstraints: const BoxConstraints(minWidth: 56, minHeight: 56),
            suffixIcon: suffix,
            filled: true, fillColor: Colors.white, isDense: false,
            contentPadding: const EdgeInsets.symmetric(vertical: 17, horizontal: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Colors.white)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Colors.white)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: ToroColors.blue, width: 1.6)),
          ),
        ),
      ),
    );
  }
}

enum ToroChipTone { neutral, available }

/// Pastilla de filtro con volumen: blanca inactiva, azul eléctrico activa,
/// verde suave para "abierto/disponible". [onDark] = translúcida en la franja.
class ToroFilterChip extends StatelessWidget {
  const ToroFilterChip({super.key, required this.label, required this.onTap, this.selected = false,
    this.icon, this.emoji, this.tone = ToroChipTone.neutral, this.count, this.height = 42, this.onDark = false});
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final IconData? icon;
  final String? emoji;
  final ToroChipTone tone;
  final int? count;
  final double height;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final available = tone == ToroChipTone.available;
    Color fg = ToroColors.navy;
    BoxDecoration deco(bool pressed) {
      if (onDark) {
        if (selected) { fg = ToroColors.blue; return BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(ToroRadius.pill),
            boxShadow: const [BoxShadow(color: Color(0x4D000000), blurRadius: 14, offset: Offset(0, 6))]); }
        if (available) { fg = const Color(0xFFC8FFF0); return BoxDecoration(color: const Color(0x4017B897), borderRadius: BorderRadius.circular(ToroRadius.pill), border: Border.all(color: const Color(0x8017B897))); }
        fg = Colors.white; return BoxDecoration(color: const Color(0x1FFFFFFF), borderRadius: BorderRadius.circular(ToroRadius.pill), border: Border.all(color: const Color(0x40FFFFFF)));
      }
      if (selected) { fg = Colors.white; return ToroRaised.decoration(ToroTone.blue, pressed: pressed, radius: ToroRadius.pill); }
      if (available) {
        fg = ToroColors.greenText;
        return BoxDecoration(borderRadius: BorderRadius.circular(ToroRadius.pill),
            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF2FDF9), Color(0xFFDDF7EF)]),
            border: const Border(top: BorderSide(color: Colors.white)),
            boxShadow: [BoxShadow(color: const Color(0xFFB6E6D6), offset: Offset(0, pressed ? 1 : 3)), const BoxShadow(color: Color(0x2417B897), blurRadius: 14, offset: Offset(0, 8))]);
      }
      fg = ToroColors.navy;
      return ToroRaised.decoration(ToroTone.white, pressed: pressed, radius: ToroRadius.pill).copyWith(
          boxShadow: [BoxShadow(color: ToroColors.edge, offset: Offset(0, pressed ? 1 : 3)), const BoxShadow(color: Color(0x1A102A56), blurRadius: 14, offset: Offset(0, 8))]);
    }
    return ToroPressable(
      onTap: onTap, semanticLabel: label,
      builder: (context, pressed) {
        final d = deco(pressed);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 110), height: height,
          padding: const EdgeInsets.symmetric(horizontal: 14), decoration: d,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 17, color: fg), const SizedBox(width: 7)],
            if (emoji != null) ...[Text(emoji!, style: const TextStyle(fontSize: 15)), const SizedBox(width: 6)],
            Text(label, style: TextStyle(color: fg, fontSize: 13.5, fontWeight: selected ? FontWeight.w800 : FontWeight.w700)),
            if (count != null) ...[const SizedBox(width: 7),
              Text('$count', style: TextStyle(color: fg.withValues(alpha: .65), fontSize: 12.5, fontWeight: FontWeight.w700))],
          ]),
        );
      },
    );
  }
}

/// Fila deslizable de pastillas con el aire estándar.
class ToroChipRow extends StatelessWidget {
  const ToroChipRow({super.key, required this.children, this.height = 42,
    this.padding = const EdgeInsets.symmetric(horizontal: 20), this.gap = 8});
  final List<Widget> children;
  final double height;
  final EdgeInsetsGeometry padding;
  final double gap;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: height + 12, // aire para el canto/sombra
        child: ListView.separated(
          scrollDirection: Axis.horizontal, padding: padding.add(const EdgeInsets.only(top: 2, bottom: 10)),
          clipBehavior: Clip.none,
          itemCount: children.length, separatorBuilder: (_, __) => SizedBox(width: gap),
          itemBuilder: (_, i) => children[i],
        ),
      );
}

// =============================================================================
// ESTADOS
// =============================================================================

class ToroStatusChip extends StatelessWidget {
  const ToroStatusChip({super.key, required this.label, this.icon, this.color = ToroColors.blue, this.background});
  final String label;
  final IconData? icon;
  final Color color;
  final Color? background;

  const ToroStatusChip.success(this.label, {super.key, this.icon = Icons.check_circle_rounded}) : color = ToroColors.greenText, background = ToroColors.greenSoft;
  const ToroStatusChip.pending(this.label, {super.key, this.icon = Icons.schedule_rounded}) : color = ToroColors.amber, background = ToroColors.amberSoft;
  const ToroStatusChip.danger(this.label, {super.key, this.icon = Icons.cancel_rounded}) : color = ToroColors.red, background = ToroColors.redSoft;
  const ToroStatusChip.info(this.label, {super.key, this.icon}) : color = ToroColors.blue, background = ToroColors.blueSoft;
  const ToroStatusChip.neutral(this.label, {super.key, this.icon}) : color = ToroColors.textMid, background = ToroColors.surface2;
  const ToroStatusChip.gold(this.label, {super.key, this.icon = Icons.star_rounded}) : color = ToroColors.goldDeep, background = ToroColors.goldSoft;

  /// Del estado de una cita/pedido a su insignia (confirmada verde, por
  /// confirmar ámbar, en curso azul, cancelada roja, lo demás gris).
  factory ToroStatusChip.forStatus(String status, String label) {
    switch (status) {
      case 'confirmed': case 'completed': case 'delivered': case 'paid': case 'accepted':
        return ToroStatusChip.success(label);
      case 'requested': case 'pending': case 'placed':
        return ToroStatusChip.pending(label);
      case 'in_progress': case 'active': case 'scheduled': case 'preparing': case 'in_transit':
        return ToroStatusChip.info(label, icon: Icons.circle, );
      case 'cancelled': case 'rejected': case 'no_show': case 'expired': case 'failed':
        return ToroStatusChip.danger(label);
      default:
        return ToroStatusChip.neutral(label);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(color: background ?? color.withValues(alpha: .10), borderRadius: BorderRadius.circular(ToroRadius.pill)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, color: color, size: icon == Icons.circle ? 9 : 15), const SizedBox(width: 5)],
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800))),
        ]),
      );
}

class ToroEmptyState extends StatelessWidget {
  const ToroEmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 360),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ToroIconTile(icon: icon, size: 72, radius: 24),
            const SizedBox(height: 20),
            Text(title, textAlign: TextAlign.center, style: ToroType.title(context, size: 18)),
            if (message != null) ...[const SizedBox(height: 8), Text(message!, textAlign: TextAlign.center, style: ToroType.body(context))],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ])),
      ));
}

/// Aviso en línea (ámbar = atención, rojo = error, azul = información).
class ToroInlineNotice extends StatelessWidget {
  const ToroInlineNotice({super.key, required this.text, this.icon = Icons.info_outline_rounded,
    this.color = ToroColors.amber, this.background = ToroColors.amberSoft, this.onTap, this.action,
    this.margin = EdgeInsets.zero});
  final String text;
  final IconData icon;
  final Color color;
  final Color background;
  final VoidCallback? onTap;
  final Widget? action;
  final EdgeInsetsGeometry margin;
  @override
  Widget build(BuildContext context) => Padding(
        padding: margin,
        child: Material(
          color: background,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: color.withValues(alpha: .25))),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(children: [
                Icon(icon, color: color, size: 20), const SizedBox(width: 10),
                Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700, height: 1.35))),
                if (action != null) action! else if (onTap != null) Icon(Icons.chevron_right_rounded, color: color),
              ]),
            ),
          ),
        ),
      );
}

// =============================================================================
// REJILLA
// =============================================================================

class ToroAdaptiveGrid extends StatelessWidget {
  const ToroAdaptiveGrid({super.key, required this.children, this.minItemWidth = 320, this.spacing = 16, this.maxColumns = 3});
  final List<Widget> children;
  final double minItemWidth;
  final double spacing;
  final int maxColumns;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final columns = ((constraints.maxWidth + spacing) / (minItemWidth + spacing)).floor().clamp(1, maxColumns);
        final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(spacing: spacing, runSpacing: spacing, children: [for (final c in children) SizedBox(width: width, child: c)]);
      });
}

// =============================================================================
// DOCK INFERIOR FLOTANTE
// =============================================================================

class ToroDockItem {
  const ToroDockItem({required this.icon, required this.activeIcon, required this.label});
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Navegación inferior flotante: cristal blanco con canto, íconos azul marino,
/// el activo en pastilla azul eléctrico con volumen y su nombre.
class ToroBottomDock extends StatelessWidget {
  const ToroBottomDock({super.key, required this.items, required this.currentIndex, required this.onTap,
    this.pulseIndex, this.pulse});
  final List<ToroDockItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final int? pulseIndex;
  final Animation<double>? pulse;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final wide = ToroBreakpoints.isWide(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, bottom + 10),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wide ? 560 : double.infinity),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xF0FFFFFF),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white, width: 1),
              boxShadow: const [BoxShadow(color: Color(0xFFDDE5F0), offset: Offset(0, 6)), ...ToroShadows.dock],
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(flex: i == currentIndex ? 5 : 3,
                    child: _DockButton(item: items[i], selected: i == currentIndex, onTap: () => onTap(i),
                        pulse: (pulseIndex == i && i != currentIndex) ? pulse : null)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({required this.item, required this.selected, required this.onTap, this.pulse});
  final ToroDockItem item;
  final bool selected;
  final VoidCallback onTap;
  final Animation<double>? pulse;

  @override
  Widget build(BuildContext context) {
    Widget content(bool pressed) => AnimatedContainer(
      duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic, height: 50,
      decoration: selected ? ToroRaised.decoration(ToroTone.blue, pressed: pressed, radius: 20) : const BoxDecoration(),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(selected ? item.activeIcon : item.icon, color: selected ? Colors.white : ToroColors.navy, size: 23),
        if (selected) ...[const SizedBox(width: 7),
          Flexible(child: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800)))],
      ]),
    );
    Widget body = ToroPressable(onTap: onTap, semanticLabel: item.label, builder: (_, p) => content(p));
    if (pulse != null) {
      body = AnimatedBuilder(animation: pulse!, builder: (_, child) => Stack(alignment: Alignment.center, children: [
        child!,
        Positioned(top: 8, right: 14, child: Container(width: 8 + 2 * pulse!.value, height: 8 + 2 * pulse!.value,
          decoration: BoxDecoration(color: ToroColors.green, shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: ToroColors.green.withValues(alpha: .5 * pulse!.value), blurRadius: 10, spreadRadius: 2)]))),
      ]), child: body);
    }
    return body;
  }
}
