// lib/widgets/toro_3d_pin.dart
import 'package:flutter/material.dart';

/// Tipo de PIN según el propósito
enum ToroPinKind {
  pickup,      // Naranja - punto de recogida
  destination, // Verde - destino final
  waypoint,    // Morado - parada intermedia
  riderGps,    // Azul - ubicación GPS del rider
}

/// Toro3DPin — Pin 3D glossy para el mapa
/// Úsalo como overlay o renderízalo a PNG vía RepaintBoundary
class Toro3DPin extends StatelessWidget {
  final ToroPinKind kind;
  final double size;
  final Widget? center;
  final String? label; // Texto opcional debajo del pin

  const Toro3DPin({
    super.key,
    required this.kind,
    this.size = 64,
    this.center,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = _pinTheme(kind);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size * 1.25,
          child: CustomPaint(
            painter: _Toro3DPinPainter(theme: theme),
            child: Padding(
              padding: EdgeInsets.only(top: size * 0.20),
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: size * 0.50,
                  height: size * 0.50,
                  child: Center(
                    child: center ??
                        Container(
                          width: size * 0.30,
                          height: size * 0.30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.centerFill,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 2,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.base,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              label!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ToroPinTheme {
  final Color base;
  final Color baseDark;
  final Color rimLight;
  final Color rimDark;
  final Color centerFill;
  final Color shadow;

  const _ToroPinTheme({
    required this.base,
    required this.baseDark,
    required this.rimLight,
    required this.rimDark,
    required this.centerFill,
    required this.shadow,
  });
}

_ToroPinTheme _pinTheme(ToroPinKind kind) {
  switch (kind) {
    case ToroPinKind.pickup:
      // Naranja glossy - PICKUP
      return const _ToroPinTheme(
        base: Color(0xFFFF9500),
        baseDark: Color(0xFFE68600),
        rimLight: Color(0xFFFFFFFF),
        rimDark: Color(0x22000000),
        centerFill: Color(0xFFF2F4F7),
        shadow: Color(0x55000000),
      );
    case ToroPinKind.destination:
      // Verde glossy - DESTINO
      return const _ToroPinTheme(
        base: Color(0xFF34C759),
        baseDark: Color(0xFF2AA84A),
        rimLight: Color(0xFFFFFFFF),
        rimDark: Color(0x22000000),
        centerFill: Color(0xFFF2F4F7),
        shadow: Color(0x55000000),
      );
    case ToroPinKind.waypoint:
      // Morado glossy - PARADAS INTERMEDIAS
      return const _ToroPinTheme(
        base: Color(0xFF5856D6),
        baseDark: Color(0xFF4745B5),
        rimLight: Color(0xFFFFFFFF),
        rimDark: Color(0x22000000),
        centerFill: Color(0xFFF2F4F7),
        shadow: Color(0x55000000),
      );
    case ToroPinKind.riderGps:
      // Azul glossy - GPS DEL RIDER
      return const _ToroPinTheme(
        base: Color(0xFF007AFF),
        baseDark: Color(0xFF0062CC),
        rimLight: Color(0xFFFFFFFF),
        rimDark: Color(0x22000000),
        centerFill: Color(0xFFF2F4F7),
        shadow: Color(0x55000000),
      );
  }
}

class _Toro3DPinPainter extends CustomPainter {
  final _ToroPinTheme theme;

  _Toro3DPinPainter({required this.theme});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Geometría
    final cx = w / 2;
    final top = h * 0.05;
    final bulbR = w * 0.46; // radio del "bulbo" (parte redonda)
    final bulbCenter = Offset(cx, top + bulbR);

    // Punta
    final tipY = h * 0.97;

    // Path del pin (círculo + gota)
    final pinPath = Path()
      ..addOval(Rect.fromCircle(center: bulbCenter, radius: bulbR))
      ..moveTo(cx - bulbR * 0.70, bulbCenter.dy + bulbR * 0.62)
      ..quadraticBezierTo(cx - bulbR * 0.35, h * 0.78, cx, tipY)
      ..quadraticBezierTo(cx + bulbR * 0.35, h * 0.78, cx + bulbR * 0.70,
          bulbCenter.dy + bulbR * 0.62)
      ..close();

    // Sombra al piso (elipse)
    final shadowRect = Rect.fromCenter(
      center: Offset(cx, tipY + h * 0.01),
      width: w * 0.62,
      height: h * 0.10,
    );
    final shadowPaint = Paint()
      ..color = theme.shadow
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawOval(shadowRect, shadowPaint);

    // Relleno principal con gradiente (3D)
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          theme.base,
          theme.base,
          theme.baseDark,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(pinPath, fillPaint);

    // Rim/edge (borde sutil)
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.04
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [theme.rimLight.withOpacity(0.75), theme.rimDark],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(pinPath, rimPaint);

    // Highlight superior (brillo glossy)
    final highlightPath = Path();
    final highlightCenter = Offset(cx - bulbR * 0.25, bulbCenter.dy - bulbR * 0.25);
    highlightPath.addOval(Rect.fromCircle(center: highlightCenter, radius: bulbR * 0.35));

    final highlightPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.0,
        colors: [
          Colors.white.withOpacity(0.6),
          Colors.white.withOpacity(0.0),
        ],
      ).createShader(Rect.fromCircle(center: highlightCenter, radius: bulbR * 0.35));
    canvas.drawPath(highlightPath, highlightPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
