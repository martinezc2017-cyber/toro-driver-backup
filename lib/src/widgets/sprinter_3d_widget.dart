import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';

/// Widget 3D de Sprinter TORO estilo Gran Turismo 7
/// Vista aérea de seguimiento con carretera animada
class Sprinter3DWidget extends StatefulWidget {
  final double size;

  const Sprinter3DWidget({
    super.key,
    this.size = 200,
  });

  @override
  State<Sprinter3DWidget> createState() => _Sprinter3DWidgetState();
}

class _Sprinter3DWidgetState extends State<Sprinter3DWidget>
    with TickerProviderStateMixin {
  late AnimationController _roadController;
  late AnimationController _suspensionController;
  late AnimationController _lightController;

  @override
  void initState() {
    super.initState();
    _roadController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat();

    _suspensionController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();

    _lightController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _roadController.dispose();
    _suspensionController.dispose();
    _lightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size * 1.2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Carretera animada 3D con perspectiva
          CustomPaint(
            size: Size(widget.size, widget.size * 1.2),
            painter: _RoadPainter(
              animation: _roadController,
            ),
          ),

          // Sprinter 3D con sombras y reflejos
          AnimatedBuilder(
            animation: _suspensionController,
            builder: (context, child) {
              final bounce = sin(_suspensionController.value * 2 * pi) * 2;
              return Transform.translate(
                offset: Offset(0, bounce),
                child: child,
              );
            },
            child: CustomPaint(
              size: Size(widget.size * 0.7, widget.size * 0.5),
              painter: _Sprinter3DPainter(),
            ),
          ),

          // Efecto de brillo/luz dinámica
          AnimatedBuilder(
            animation: _lightController,
            builder: (context, child) {
              return CustomPaint(
                size: Size(widget.size, widget.size * 1.2),
                painter: _LightEffectPainter(
                  progress: _lightController.value,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Pintor de la carretera con perspectiva 3D animada
class _RoadPainter extends CustomPainter {
  final Animation<double> animation;

  _RoadPainter({required this.animation}) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final bottomY = size.height;
    final horizonY = size.height * 0.35;

    // Fondo oscuro de la carretera
    final roadPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF0A1628),
          const Color(0xFF1A2332),
          const Color(0xFF0D1B2A),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, horizonY, size.width, bottomY - horizonY));

    // Dibujar la carretera con perspectiva (trapezoide)
    final roadPath = Path()
      ..moveTo(centerX - 15, horizonY)
      ..lineTo(centerX + 15, horizonY)
      ..lineTo(size.width + 20, bottomY)
      ..lineTo(-20, bottomY)
      ..close();

    canvas.drawPath(roadPath, roadPaint);

    // Líneas de la carretera animadas
    final linePaint = Paint()
      ..color = const Color(0xFF3B82F6).withOpacity(0.8)
      ..strokeWidth = 2
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);

    // Líneas centrales animadas con efecto de movimiento
    final offset = animation.value;
    for (int i = 0; i < 6; i++) {
      final progress = (i + offset) % 6 / 6;
      final y = horizonY + (bottomY - horizonY) * progress;
      final widthAtY = 30 + (size.width * 0.8 - 30) * progress;
      final x = centerX - widthAtY / 2;

      // Línea izquierda
      canvas.drawLine(
        Offset(x, y),
        Offset(x + widthAtY * 0.15, y),
        linePaint..strokeWidth = 3 * (0.5 + progress * 0.5),
      );

      // Línea derecha
      canvas.drawLine(
        Offset(centerX + widthAtY / 2 - widthAtY * 0.15, y),
        Offset(centerX + widthAtY / 2, y),
        linePaint,
      );
    }

    // Líneas blancas del borde con glow
    final edgeGlow = Paint()
      ..color = const Color(0xFF60A5FA).withOpacity(0.4)
      ..strokeWidth = 3
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    // Borde izquierdo
    canvas.drawLine(
      Offset(centerX - 20, horizonY),
      Offset(-10, bottomY),
      edgeGlow,
    );

    // Borde derecho
    canvas.drawLine(
      Offset(centerX + 20, horizonY),
      Offset(size.width + 10, bottomY),
      edgeGlow,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Pintor de la Sprinter 3D con sombras y reflejos estilo GT7
class _Sprinter3DPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // ===== SOMBRA PROYECTADA (realista) =====
    final shadowPath = Path()
      ..moveTo(centerX - size.width * 0.35, centerY + size.height * 0.25)
      ..lineTo(centerX + size.width * 0.35, centerY + size.height * 0.25)
      ..lineTo(centerX + size.width * 0.45, centerY + size.height * 0.45)
      ..lineTo(centerX - size.width * 0.45, centerY + size.height * 0.45)
      ..close();

    final shadowPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, 0.8),
        radius: 0.8,
        colors: [
          Colors.black.withOpacity(0.6),
          Colors.black.withOpacity(0.2),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCenter(
        center: Offset(centerX, centerY + size.height * 0.35),
        width: size.width,
        height: size.height * 0.5,
      ));

    canvas.drawPath(shadowPath, shadowPaint);

    // ===== CUERPO PRINCIPAL DE LA SPRINTER (perspectiva cenital) =====
    // Forma de la Sprinter desde arriba con perspectiva
    final bodyPath = Path()
      // Parte trasera (más ancha - más cerca)
      ..moveTo(centerX - size.width * 0.3, centerY + size.height * 0.2)
      ..lineTo(centerX + size.width * 0.3, centerY + size.height * 0.2)
      // Lado derecho
      ..lineTo(centerX + size.width * 0.25, centerY - size.height * 0.25)
      // Parabrisas delantero
      ..lineTo(centerX + size.width * 0.15, centerY - size.height * 0.35)
      // Capó
      ..lineTo(centerX - size.width * 0.15, centerY - size.height * 0.35)
      // Lado izquierdo
      ..lineTo(centerX - size.width * 0.25, centerY - size.height * 0.25)
      ..close();

    // Gradiente metálico de la carrocería (blanco/plata brillante estilo TORO)
    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFFF8FAFC), // Blanco brillante
          const Color(0xFFE2E8F0), // Plata
          const Color(0xFFCBD5E1), // Gris plata
          const Color(0xFFF1F5F9), // Reflejo
        ],
        stops: const [0.0, 0.3, 0.7, 1.0],
      ).createShader(Rect.fromCenter(
        center: Offset(centerX, centerY),
        width: size.width,
        height: size.height,
      ))
      ..style = PaintingStyle.fill;

    canvas.drawPath(bodyPath, bodyPaint);

    // Borde del cuerpo para definición
    final bodyStroke = Paint()
      ..color = const Color(0xFF475569)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawPath(bodyPath, bodyStroke);

    // ===== PARABRISAS (negro brillante con reflejo) =====
    final windshieldPath = Path()
      ..moveTo(centerX - size.width * 0.14, centerY - size.height * 0.32)
      ..lineTo(centerX + size.width * 0.14, centerY - size.height * 0.32)
      ..lineTo(centerX + size.width * 0.22, centerY - size.height * 0.18)
      ..lineTo(centerX - size.width * 0.22, centerY - size.height * 0.18)
      ..close();

    final windshieldPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF1E293B),
          const Color(0xFF0F172A),
          const Color(0xFF334155),
        ],
      ).createShader(Rect.fromCenter(
        center: Offset(centerX, centerY - size.height * 0.25),
        width: size.width * 0.4,
        height: size.height * 0.15,
      ));

    canvas.drawPath(windshieldPath, windshieldPaint);

    // Reflejo en el parabrisas
    final reflectionPaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawLine(
      Offset(centerX - size.width * 0.08, centerY - size.height * 0.28),
      Offset(centerX + size.width * 0.05, centerY - size.height * 0.22),
      reflectionPaint,
    );

    // ===== TECHO =====
    final roofPath = Path()
      ..moveTo(centerX - size.width * 0.22, centerY - size.height * 0.18)
      ..lineTo(centerX + size.width * 0.22, centerY - size.height * 0.18)
      ..lineTo(centerX + size.width * 0.26, centerY + size.height * 0.15)
      ..lineTo(centerX - size.width * 0.26, centerY + size.height * 0.15)
      ..close();

    final roofPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.fill;

    canvas.drawPath(roofPath, roofPaint);

    // Línea de techo
    canvas.drawLine(
      Offset(centerX, centerY - size.height * 0.18),
      Offset(centerX, centerY + size.height * 0.15),
      Paint()
        ..color = const Color(0xFF94A3B8)
        ..strokeWidth = 1,
    );

    // ===== VENTANAS LATERALES =====
    // Ventana izquierda
    final leftWindow = Path()
      ..moveTo(centerX - size.width * 0.24, centerY - size.height * 0.12)
      ..lineTo(centerX - size.width * 0.22, centerY + size.height * 0.12)
      ..lineTo(centerX - size.width * 0.18, centerY + size.height * 0.12)
      ..lineTo(centerX - size.width * 0.20, centerY - size.height * 0.12)
      ..close();

    final windowPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFF334155),
          const Color(0xFF1E293B),
        ],
      ).createShader(Rect.fromLTWH(
        centerX - size.width * 0.25,
        centerY - size.height * 0.15,
        size.width * 0.1,
        size.height * 0.3,
      ));

    canvas.drawPath(leftWindow, windowPaint);

    // Ventana derecha
    final rightWindow = Path()
      ..moveTo(centerX + size.width * 0.20, centerY - size.height * 0.12)
      ..lineTo(centerX + size.width * 0.18, centerY + size.height * 0.12)
      ..lineTo(centerX + size.width * 0.22, centerY + size.height * 0.12)
      ..lineTo(centerX + size.width * 0.24, centerY - size.height * 0.12)
      ..close();

    canvas.drawPath(rightWindow, windowPaint);

    // ===== LUCES DELANTERAS =====
    final headlightPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withOpacity(0.9),
          const Color(0xFF60A5FA).withOpacity(0.6),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCenter(
        center: Offset(centerX - size.width * 0.12, centerY - size.height * 0.32),
        width: 15,
        height: 8,
      ));

    // Luz izquierda
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX - size.width * 0.12, centerY - size.height * 0.32),
        width: 12,
        height: 6,
      ),
      headlightPaint,
    );

    // Luz derecha
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX + size.width * 0.12, centerY - size.height * 0.32),
        width: 12,
        height: 6,
      ),
      headlightPaint,
    );

    // ===== LUCES TRASERAS =====
    final taillightPaint = Paint()
      ..color = const Color(0xFFDC2626)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(centerX - size.width * 0.25, centerY + size.height * 0.18),
        width: 10,
        height: 5,
      ),
      taillightPaint,
    );

    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(centerX + size.width * 0.25, centerY + size.height * 0.18),
        width: 10,
        height: 5,
      ),
      taillightPaint,
    );

    // ===== LOGO TORO EN EL CAPÓ =====
    // Círculo base del logo
    final logoCenter = Offset(centerX, centerY - size.height * 0.28);
    final logoRadius = size.width * 0.08;

    // Glow del logo
    final logoGlow = Paint()
      ..color = const Color(0xFF3B82F6).withOpacity(0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    canvas.drawCircle(logoCenter, logoRadius + 3, logoGlow);

    // Círculo del logo
    final logoBg = Paint()
      ..color = const Color(0xFF1E40AF)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(logoCenter, logoRadius, logoBg);

    // Borde del logo
    canvas.drawCircle(
      logoCenter,
      logoRadius,
      Paint()
        ..color = const Color(0xFF60A5FA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Silueta estilizada del toro (simplificada)
    final bullPath = Path()
      // Cuernos
      ..moveTo(logoCenter.dx - 8, logoCenter.dy - 6)
      ..quadraticBezierTo(
        logoCenter.dx - 12, logoCenter.dy - 10,
        logoCenter.dx - 6, logoCenter.dy - 12,
      )
      // Cabeza
      ..lineTo(logoCenter.dx, logoCenter.dy - 8)
      ..lineTo(logoCenter.dx + 6, logoCenter.dy - 12)
      ..quadraticBezierTo(
        logoCenter.dx + 12, logoCenter.dy - 10,
        logoCenter.dx + 8, logoCenter.dy - 6,
      )
      // Cuerpo
      ..lineTo(logoCenter.dx + 6, logoCenter.dy + 4)
      ..lineTo(logoCenter.dx - 6, logoCenter.dy + 4)
      ..close();

    final bullPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawPath(bullPath, bullPaint);

    // Detalles del toro
    canvas.drawCircle(
      Offset(logoCenter.dx - 3, logoCenter.dy - 4),
      1.5,
      Paint()..color = const Color(0xFF1E40AF),
    );

    canvas.drawCircle(
      Offset(logoCenter.dx + 3, logoCenter.dy - 4),
      1.5,
      Paint()..color = const Color(0xFF1E40AF),
    );

    // ===== RUEDAS =====
    final wheelPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.fill;

    final wheelGlow = Paint()
      ..color = const Color(0xFF475569)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Rueda delantera izquierda
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX - size.width * 0.22, centerY - size.height * 0.22),
        width: 14,
        height: 8,
      ),
      wheelPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX - size.width * 0.22, centerY - size.height * 0.22),
        width: 14,
        height: 8,
      ),
      wheelGlow,
    );

    // Rueda delantera derecha
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX + size.width * 0.22, centerY - size.height * 0.22),
        width: 14,
        height: 8,
      ),
      wheelPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX + size.width * 0.22, centerY - size.height * 0.22),
        width: 14,
        height: 8,
      ),
      wheelGlow,
    );

    // Rueda trasera izquierda
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX - size.width * 0.28, centerY + size.height * 0.15),
        width: 16,
        height: 10,
      ),
      wheelPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX - size.width * 0.28, centerY + size.height * 0.15),
        width: 16,
        height: 10,
      ),
      wheelGlow,
    );

    // Rueda trasera derecha
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX + size.width * 0.28, centerY + size.height * 0.15),
        width: 16,
        height: 10,
      ),
      wheelPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX + size.width * 0.28, centerY + size.height * 0.15),
        width: 16,
        height: 10,
      ),
      wheelGlow,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Efecto de luz dinámica que pasa por el vehículo
class _LightEffectPainter extends CustomPainter {
  final double progress;

  _LightEffectPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Rayo de luz que barre el vehículo
    final lightX = centerX - size.width * 0.4 + (size.width * 0.8 * progress);

    final lightPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          Colors.white.withOpacity(0.15),
          Colors.white.withOpacity(0.25),
          Colors.white.withOpacity(0.15),
          Colors.transparent,
        ],
        stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
      ).createShader(Rect.fromLTWH(
        lightX - 30,
        centerY - size.height * 0.3,
        60,
        size.height * 0.6,
      ));

    canvas.drawRect(
      Rect.fromLTWH(
        lightX - 30,
        centerY - size.height * 0.3,
        60,
        size.height * 0.6,
      ),
      lightPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
