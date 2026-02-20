import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';

/// Sprinter EPIC - Vista aérea estilo GT7 con perspectiva real
class SprinterEpicWidget extends StatefulWidget {
  final double size;

  const SprinterEpicWidget({
    super.key,
    this.size = 220,
  });

  @override
  State<SprinterEpicWidget> createState() => _SprinterEpicWidgetState();
}

class _SprinterEpicWidgetState extends State<SprinterEpicWidget>
    with TickerProviderStateMixin {
  late AnimationController _roadController;
  late AnimationController _suspensionController;
  late AnimationController _lightController;

  @override
  void initState() {
    super.initState();
    _roadController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..repeat();

    _suspensionController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _lightController = AnimationController(
      duration: const Duration(seconds: 4),
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
      height: widget.size * 1.3,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Carretera con perspectiva GT7
          AnimatedBuilder(
            animation: _roadController,
            builder: (context, child) {
              return CustomPaint(
                size: Size(widget.size, widget.size * 1.3),
                painter: _HighwayGTPainter(
                  progress: _roadController.value,
                ),
              );
            },
          ),

          // Sprinter con perspectiva real
          AnimatedBuilder(
            animation: Listenable.merge([_suspensionController, _lightController]),
            builder: (context, child) {
              final bounce = sin(_suspensionController.value * 2 * pi) * 1.5;
              return Transform.translate(
                offset: Offset(0, bounce),
                child: CustomPaint(
                  size: Size(widget.size * 0.75, widget.size * 0.6),
                  painter: _SprinterGTPainter(
                    lightProgress: _lightController.value,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Carretera estilo Gran Turismo - perspectiva real con asfalto texturizado
class _HighwayGTPainter extends CustomPainter {
  final double progress;

  _HighwayGTPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final horizonY = size.height * 0.25;
    final bottomY = size.height;

    // === CIELO GRADIENTE ===
    final skyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF0A1628),
          const Color(0xFF1A2332).withOpacity(0.8),
          const Color(0xFF0D1B2A),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Offset.zero & size, skyPaint);

    // === CARRETERA CON PERSPECTIVA REAL ===
    // Punto de fuga
    final vanishingPoint = Offset(centerX, horizonY);
    
    // Ancho de la carretera en el horizonte vs abajo
    final topWidth = size.width * 0.08;
    final bottomWidth = size.width * 1.2;

    // Path de la carretera (trapezoide con perspectiva)
    final roadPath = Path()
      ..moveTo(centerX - topWidth / 2, horizonY)
      ..lineTo(centerX + topWidth / 2, horizonY)
      ..lineTo(centerX + bottomWidth / 2, bottomY)
      ..lineTo(centerX - bottomWidth / 2, bottomY)
      ..close();

    // Asfalto con textura de ruido
    final asphaltPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF1A1A2E),
          const Color(0xFF16213E),
          const Color(0xFF0F0F23),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, horizonY, size.width, bottomY - horizonY));

    canvas.drawPath(roadPath, asphaltPaint);

    // === BORDES DE LA CARRETERA (glow azul) ===
    final edgeGlow = Paint()
      ..color = const Color(0xFF3B82F6).withOpacity(0.3)
      ..strokeWidth = 2
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    // Borde izquierdo
    canvas.drawLine(
      Offset(centerX - topWidth / 2, horizonY),
      Offset(centerX - bottomWidth / 2 + 10, bottomY),
      edgeGlow,
    );

    // Borde derecho
    canvas.drawLine(
      Offset(centerX + topWidth / 2, horizonY),
      Offset(centerX + bottomWidth / 2 - 10, bottomY),
      edgeGlow,
    );

    // === LÍNEAS CENTRALES ANIMADAS ===
    final linePaint = Paint()
      ..color = const Color(0xFF60A5FA).withOpacity(0.7)
      ..strokeWidth = 2
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);

    // Múltiples líneas que se mueven hacia el horizonte
    for (int i = 0; i < 8; i++) {
      final lineProgress = ((i + progress * 8) % 8) / 8;
      final y = horizonY + (bottomY - horizonY) * lineProgress;
      
      // Interpolación del ancho basada en la perspectiva
      final currentWidth = topWidth + (bottomWidth - topWidth) * lineProgress;
      final lineLength = 15 + (40 - 15) * lineProgress;
      final lineWidth = 2 + (6 - 2) * lineProgress;

      // Línea izquierda
      canvas.drawLine(
        Offset(centerX - currentWidth * 0.15, y),
        Offset(centerX - currentWidth * 0.15 - lineLength, y),
        linePaint..strokeWidth = lineWidth,
      );

      // Línea derecha
      canvas.drawLine(
        Offset(centerX + currentWidth * 0.15, y),
        Offset(centerX + currentWidth * 0.15 + lineLength, y),
        linePaint,
      );
    }

    // === LÍNEAS DE CARRIL ADICIONALES ===
    for (int i = 0; i < 6; i++) {
      final lineProgress = ((i + progress * 6) % 6) / 6;
      final y = horizonY + (bottomY - horizonY) * lineProgress;
      final currentWidth = topWidth + (bottomWidth - topWidth) * lineProgress;
      
      // Líneas más alejadas del centro
      canvas.drawLine(
        Offset(centerX - currentWidth * 0.35, y),
        Offset(centerX - currentWidth * 0.35 - 10, y),
        Paint()
          ..color = const Color(0xFF3B82F6).withOpacity(0.3)
          ..strokeWidth = 1.5,
      );
      
      canvas.drawLine(
        Offset(centerX + currentWidth * 0.35, y),
        Offset(centerX + currentWidth * 0.35 + 10, y),
        Paint()
          ..color = const Color(0xFF3B82F6).withOpacity(0.3)
          ..strokeWidth = 1.5,
      );
    }

    // === EFECTO DE VELOCIDAD (líneas laterales) ===
    for (int i = 0; i < 12; i++) {
      final speedProgress = ((i + progress * 12) % 12) / 12;
      final y = horizonY + (bottomY - horizonY) * speedProgress;
      final length = 20 + speedProgress * 60;
      final opacity = 0.1 + speedProgress * 0.2;

      // Línea de velocidad izquierda
      canvas.drawLine(
        Offset(centerX - bottomWidth * 0.6, y),
        Offset(centerX - bottomWidth * 0.6 - length, y),
        Paint()
          ..color = Colors.white.withOpacity(opacity)
          ..strokeWidth = 1,
      );

      // Línea de velocidad derecha
      canvas.drawLine(
        Offset(centerX + bottomWidth * 0.6, y),
        Offset(centerX + bottomWidth * 0.6 + length, y),
        Paint()
          ..color = Colors.white.withOpacity(opacity)
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Sprinter con forma REAL - no un cubo
class _SprinterGTPainter extends CustomPainter {
  final double lightProgress;

  _SprinterGTPainter({required this.lightProgress});

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // === SOMBRA PROYECTADA (realista, alargada) ===
    final shadowPath = Path()
      ..moveTo(centerX - size.width * 0.35, centerY + size.height * 0.35)
      ..lineTo(centerX + size.width * 0.35, centerY + size.height * 0.35)
      ..lineTo(centerX + size.width * 0.5, centerY + size.height * 0.55)
      ..lineTo(centerX - size.width * 0.5, centerY + size.height * 0.55)
      ..close();

    final shadowPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, 0.9),
        radius: 1.0,
        colors: [
          Colors.black.withOpacity(0.5),
          Colors.black.withOpacity(0.2),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCenter(
        center: Offset(centerX, centerY + size.height * 0.45),
        width: size.width * 1.2,
        height: size.height * 0.4,
      ));

    canvas.drawPath(shadowPath, shadowPaint);

    // === CUERPO DE LA SPRINTER (forma real, no cubo) ===
    // Vista cenital con perspectiva
    
    // 1. PARTE TRASERA (más ancha, más cerca)
    final rearWidth = size.width * 0.55;
    final rearY = centerY + size.height * 0.25;
    
    // 2. PARTE FRONTAL (más estrecha, más lejana)
    final frontWidth = size.width * 0.35;
    final frontY = centerY - size.height * 0.30;
    
    // 3. TECHO
    final roofWidth = size.width * 0.40;
    final roofY = centerY - size.height * 0.15;

    // Path del cuerpo principal (con curvas, no rectángulos)
    final bodyPath = Path()
      // Esquina trasera izquierda
      ..moveTo(centerX - rearWidth / 2, rearY)
      // Línea trasera con curva suave
      ..quadraticBezierTo(
        centerX, rearY + 5,
        centerX + rearWidth / 2, rearY,
      )
      // Lado derecho hacia adelante
      ..lineTo(centerX + roofWidth / 2, roofY)
      // Parabrisas (inclinado)
      ..lineTo(centerX + frontWidth / 2, frontY + size.height * 0.1)
      // Capó delantero
      ..quadraticBezierTo(
        centerX + frontWidth / 3, frontY - 5,
        centerX, frontY - 8,
      )
      ..quadraticBezierTo(
        centerX - frontWidth / 3, frontY - 5,
        centerX - frontWidth / 2, frontY + size.height * 0.1,
      )
      // Lado izquierdo
      ..lineTo(centerX - roofWidth / 2, roofY)
      ..close();

    // Gradiente metálico de carrocería (blanco/plata)
    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFFF8FAFC),      // Blanco brillante
          const Color(0xFFE2E8F0),      // Plata
          const Color(0xFFCBD5E1),      // Gris plata
          const Color(0xFFF1F5F9),      // Reflejo
          const Color(0xFF94A3B8),      // Sombra
        ],
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      ).createShader(Rect.fromCenter(
        center: Offset(centerX, centerY),
        width: size.width,
        height: size.height,
      ))
      ..style = PaintingStyle.fill;

    canvas.drawPath(bodyPath, bodyPaint);

    // Borde del cuerpo
    final bodyStroke = Paint()
      ..color = const Color(0xFF475569)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(bodyPath, bodyStroke);

    // === CABINA/PARABRISAS ===
    final windshieldPath = Path()
      ..moveTo(centerX - frontWidth * 0.4, frontY + size.height * 0.12)
      ..lineTo(centerX + frontWidth * 0.4, frontY + size.height * 0.12)
      ..lineTo(centerX + roofWidth * 0.35, roofY + size.height * 0.05)
      ..lineTo(centerX - roofWidth * 0.35, roofY + size.height * 0.05)
      ..close();

    final glassPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF1E293B),
          const Color(0xFF0F172A),
          const Color(0xFF334155),
        ],
      ).createShader(Rect.fromCenter(
        center: Offset(centerX, frontY + size.height * 0.1),
        width: frontWidth * 0.8,
        height: size.height * 0.15,
      ));

    canvas.drawPath(windshieldPath, glassPaint);

    // Reflejo en el parabrisas
    canvas.drawLine(
      Offset(centerX - frontWidth * 0.2, frontY + size.height * 0.08),
      Offset(centerX + frontWidth * 0.15, frontY + size.height * 0.14),
      Paint()
        ..color = Colors.white.withOpacity(0.3)
        ..strokeWidth = 2,
    );

    // === VENTANAS LATERALES ===
    // Ventana izquierda
    final leftWindow = Path()
      ..moveTo(centerX - roofWidth * 0.42, centerY - size.height * 0.05)
      ..lineTo(centerX - roofWidth * 0.38, centerY + size.height * 0.15)
      ..lineTo(centerX - roofWidth * 0.25, centerY + size.height * 0.18)
      ..lineTo(centerX - roofWidth * 0.30, centerY - size.height * 0.02)
      ..close();

    final windowPaint = Paint()
      ..color = const Color(0xFF1E293B);
    canvas.drawPath(leftWindow, windowPaint);

    // Ventana derecha
    final rightWindow = Path()
      ..moveTo(centerX + roofWidth * 0.30, centerY - size.height * 0.02)
      ..lineTo(centerX + roofWidth * 0.25, centerY + size.height * 0.18)
      ..lineTo(centerX + roofWidth * 0.38, centerY + size.height * 0.15)
      ..lineTo(centerX + roofWidth * 0.42, centerY - size.height * 0.05)
      ..close();

    canvas.drawPath(rightWindow, windowPaint);

    // === LUCES DELANTERAS ===
    final headlightPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withOpacity(0.95),
          const Color(0xFF60A5FA).withOpacity(0.6),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCenter(
        center: Offset(centerX - frontWidth * 0.3, frontY + size.height * 0.1),
        width: 12,
        height: 8,
      ));

    // Luz izquierda
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX - frontWidth * 0.3, frontY + size.height * 0.08),
        width: 10,
        height: 6,
      ),
      headlightPaint,
    );

    // Luz derecha
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centerX + frontWidth * 0.3, frontY + size.height * 0.08),
        width: 10,
        height: 6,
      ),
      headlightPaint,
    );

    // === LUCES TRASERAS (rojas) ===
    final taillightPaint = Paint()
      ..color = const Color(0xFFDC2626)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(centerX - rearWidth * 0.4, rearY - 5),
        width: 8,
        height: 4,
      ),
      taillightPaint,
    );

    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(centerX + rearWidth * 0.4, rearY - 5),
        width: 8,
        height: 4,
      ),
      taillightPaint,
    );

    // === REFLEJO EN EL CAPÓ (no logo, solo brillo metálico) ===
    final hoodReflection = Path()
      ..moveTo(centerX - frontWidth * 0.25, frontY + size.height * 0.12)
      ..lineTo(centerX + frontWidth * 0.15, frontY + size.height * 0.12)
      ..lineTo(centerX + frontWidth * 0.10, frontY + size.height * 0.18)
      ..lineTo(centerX - frontWidth * 0.20, frontY + size.height * 0.18)
      ..close();

    canvas.drawPath(
      hoodReflection,
      Paint()
        ..color = Colors.white.withOpacity(0.25)
        ..style = PaintingStyle.fill,
    );

    // === RUEDAS (4 ruedas con perspectiva) ===
    _drawWheel(
      canvas,
      Offset(centerX - rearWidth * 0.35, centerY + size.height * 0.22),
      14,
      8,
    );
    _drawWheel(
      canvas,
      Offset(centerX + rearWidth * 0.35, centerY + size.height * 0.22),
      14,
      8,
    );
    _drawWheel(
      canvas,
      Offset(centerX - frontWidth * 0.3, centerY - size.height * 0.15),
      12,
      6,
    );
    _drawWheel(
      canvas,
      Offset(centerX + frontWidth * 0.3, centerY - size.height * 0.15),
      12,
      6,
    );

    // === EFECTO DE LUZ DINÁMICA (barre el vehículo) ===
    final lightX = centerX - size.width * 0.4 + (size.width * 0.8 * lightProgress);
    final lightPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          Colors.white.withOpacity(0.12),
          Colors.white.withOpacity(0.20),
          Colors.white.withOpacity(0.12),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(lightX - 25, centerY - 40, 50, 80));

    canvas.drawRect(
      Rect.fromLTWH(lightX - 25, centerY - 40, 50, 80),
      lightPaint,
    );
  }

  void _drawWheel(Canvas canvas, Offset center, double width, double height) {
    // Neumático
    canvas.drawOval(
      Rect.fromCenter(center: center, width: width, height: height),
      Paint()..color = const Color(0xFF1E293B),
    );

    // Llanta
    canvas.drawOval(
      Rect.fromCenter(center: center, width: width - 4, height: height - 2),
      Paint()..color = const Color(0xFF475569),
    );

    // Centro de la llanta
    canvas.drawOval(
      Rect.fromCenter(center: center, width: width - 8, height: height - 4),
      Paint()..color = const Color(0xFF94A3B8),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
