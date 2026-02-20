import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ToroSplashScreen extends StatefulWidget {
  final VoidCallback? onComplete;
  final Duration duration;

  const ToroSplashScreen({
    super.key,
    this.onComplete,
    this.duration = const Duration(seconds: 3),
  });

  @override
  State<ToroSplashScreen> createState() => _ToroSplashScreenState();
}

class _ToroSplashScreenState extends State<ToroSplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _particleController;
  late AnimationController _textController;
  late Animation<double> _logoScale;
  late Animation<double> _logoGlow;
  late Animation<double> _textOpacity;
  late Animation<double> _loadingProgress;

  final List<Particle> _particles = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    // Modo edge-to-edge: barras transparentes pero visibles
    // Evita el mensaje "Viewing full screen" del sistema
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
    
    _initParticles();
    _initAnimations();
    _startAnimation();
  }

  void _initParticles() {
    for (int i = 0; i < 50; i++) {
      _particles.add(Particle(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        size: _random.nextDouble() * 2 + 0.5,
        speedX: (_random.nextDouble() - 0.5) * 0.002,
        speedY: (_random.nextDouble() - 0.5) * 0.002,
        opacity: _random.nextDouble(),
      ));
    }
  }

  void _initAnimations() {
    _logoController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _particleController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat();

    _textController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _logoScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: Curves.easeOutBack,
      ),
    );

    _logoGlow = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: Curves.easeInOut,
      ),
    );

    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _textController,
        curve: Curves.easeIn,
      ),
    );

    _loadingProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: Curves.easeInOut,
      ),
    );
  }

  void _startAnimation() async {
    await _logoController.forward();
    await _textController.forward();
    
    await Future.delayed(widget.duration - const Duration(seconds: 2));
    
    if (mounted) {
      widget.onComplete?.call();
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _particleController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Fondo con partículas animadas
          AnimatedBuilder(
            animation: _particleController,
            builder: (context, child) {
              return CustomPaint(
                size: Size.infinite,
                painter: GalaxyPainter(
                  particles: _particles,
                  progress: _particleController.value,
                ),
              );
            },
          ),

          // Contenido centrado
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                
                // Logo con efecto de brillo
                AnimatedBuilder(
                  animation: _logoController,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _logoScale.value,
                      child: Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00D4FF).withOpacity(0.6 * _logoGlow.value),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                            BoxShadow(
                              color: const Color(0xFF0064FF).withOpacity(0.4 * _logoGlow.value),
                              blurRadius: 60,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(32),
                          child: Image.asset(
                            'assets/images/toro-driver-splash.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 40),

                // Texto TORO DRIVER
                FadeTransition(
                  opacity: _textOpacity,
                  child: Column(
                    children: [
                      const Text(
                        'TORO DRIVER',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 8,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: Color(0xFF00D4FF),
                              blurRadius: 20,
                            ),
                            Shadow(
                              color: Color(0xFF0064FF),
                              blurRadius: 40,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'CONDUCE EL FUTURO',
                        style: TextStyle(
                          fontSize: 12,
                          letterSpacing: 4,
                          color: const Color(0xFF00D4FF).withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 60),

                // Loading bar
                FadeTransition(
                  opacity: _textOpacity,
                  child: Column(
                    children: [
                      Container(
                        width: 200,
                        height: 3,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: AnimatedBuilder(
                          animation: _loadingProgress,
                          builder: (context, child) {
                            return FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: _loadingProgress.value,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF00D4FF),
                                      Color(0xFF0064FF),
                                      Color(0xFF00D4FF),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(3),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF00D4FF).withOpacity(0.8),
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 15),
                      Text(
                        'CARGANDO...',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 3,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class Particle {
  double x, y;
  double size;
  double speedX, speedY;
  double opacity;

  Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speedX,
    required this.speedY,
    required this.opacity,
  });
}

class GalaxyPainter extends CustomPainter {
  final List<Particle> particles;
  final double progress;

  GalaxyPainter({
    required this.particles,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Dibujar fondo degradado
    final bgPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF001a33).withOpacity(0.4),
          const Color(0xFF000d1a).withOpacity(0.2),
          Colors.black.withOpacity(0.3),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(
        Rect.fromCenter(
          center: Offset(size.width / 2, size.height / 2),
          width: size.width,
          height: size.height,
        ),
      );
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Efecto de pulso en el centro
    final pulsePaint = Paint()
      ..color = const Color(0xFF00D4FF).withOpacity(0.1 + sin(progress * pi * 2) * 0.05)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 50);
    
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      100 + sin(progress * pi * 3) * 30,
      pulsePaint,
    );

    // Dibujar partículas
    for (var particle in particles) {
      // Actualizar posición
      particle.x += particle.speedX;
      particle.y += particle.speedY;

      // Efecto de atracción al centro
      final centerX = 0.5;
      final centerY = 0.5;
      final dx = centerX - particle.x;
      final dy = centerY - particle.y;
      final dist = sqrt(dx * dx + dy * dy);

      if (dist < 0.3) {
        particle.x += dx * 0.002;
        particle.y += dy * 0.002;
      }

      // Wrap around
      if (particle.x < 0) particle.x = 1;
      if (particle.x > 1) particle.x = 0;
      if (particle.y < 0) particle.y = 1;
      if (particle.y > 1) particle.y = 0;

      // Dibujar partícula
      final paint = Paint()
        ..color = const Color(0xFF00D4FF).withOpacity(particle.opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

      canvas.drawCircle(
        Offset(particle.x * size.width, particle.y * size.height),
        particle.size,
        paint,
      );
    }

    // Dibujar líneas de conexión
    final linePaint = Paint()
      ..strokeWidth = 0.5
      ..color = const Color(0xFF00D4FF).withOpacity(0.1);

    for (int i = 0; i < particles.length; i++) {
      for (int j = i + 1; j < particles.length; j++) {
        final dx = (particles[i].x - particles[j].x) * size.width;
        final dy = (particles[i].y - particles[j].y) * size.height;
        final dist = sqrt(dx * dx + dy * dy);

        if (dist < 80) {
          linePaint.color = const Color(0xFF00D4FF).withOpacity(0.1 * (1 - dist / 80));
          canvas.drawLine(
            Offset(particles[i].x * size.width, particles[i].y * size.height),
            Offset(particles[j].x * size.width, particles[j].y * size.height),
            linePaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
