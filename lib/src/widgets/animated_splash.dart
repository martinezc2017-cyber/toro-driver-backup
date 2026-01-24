import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Extravagant CapCut-style animated splash screen
/// Features: Logo zoom + glow burst, energy particles, glitch text, flash transition
class AnimatedSplash extends StatefulWidget {
  final String title;
  final String? subtitle;
  final VoidCallback onComplete;
  final Duration duration;

  const AnimatedSplash({
    super.key,
    this.title = 'TORO',
    this.subtitle,
    required this.onComplete,
    this.duration = const Duration(milliseconds: 4500),
  });

  @override
  State<AnimatedSplash> createState() => _AnimatedSplashState();
}

class _AnimatedSplashState extends State<AnimatedSplash> with TickerProviderStateMixin {
  // Main logo animations
  late AnimationController _logoController;
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _logoRotation;

  // Glow burst animation
  late AnimationController _glowBurstController;
  late Animation<double> _glowBurstScale;
  late Animation<double> _glowBurstOpacity;

  // Breathing glow animation
  late AnimationController _breatheController;
  late Animation<double> _breatheAnimation;

  // Text animations
  late AnimationController _textController;
  late Animation<double> _textOpacity;
  late Animation<Offset> _textSlide;

  // Particles
  late AnimationController _particleController;
  final List<_Particle> _particles = [];

  // Flash transition
  late AnimationController _flashController;
  late Animation<double> _flashOpacity;

  // Energy ring
  late AnimationController _ringController;

  // Colors
  static const Color _neonBlue = Color(0xFF60A5FA);
  static const Color _neonCyan = Color(0xFF00D4FF);
  static const Color _deepBlue = Color(0xFF0A1628);
  static const Color _electricBlue = Color(0xFF3B82F6);

  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
    _initParticles();
    _initAnimations();
    _startSequence();
  }

  void _initParticles() {
    final random = math.Random();
    for (int i = 0; i < 30; i++) {
      _particles.add(_Particle(
        x: random.nextDouble() * 400 - 200,
        y: random.nextDouble() * 400 - 200,
        size: random.nextDouble() * 4 + 1,
        speed: random.nextDouble() * 2 + 0.5,
        angle: random.nextDouble() * math.pi * 2,
        opacity: random.nextDouble() * 0.6 + 0.2,
      ));
    }
  }

  void _initAnimations() {
    // Logo entrance: scale from 0 to 1.2 to 1 with rotation
    _logoController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _logoScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.3), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 0.9), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0), weight: 25),
    ]).animate(CurvedAnimation(parent: _logoController, curve: Curves.easeOut));

    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: const Interval(0.0, 0.3)),
    );

    _logoRotation = Tween<double>(begin: -0.1, end: 0.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOut),
    );

    // Glow burst: expands outward when logo lands
    _glowBurstController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _glowBurstScale = Tween<double>(begin: 0.5, end: 2.5).animate(
      CurvedAnimation(parent: _glowBurstController, curve: Curves.easeOut),
    );

    _glowBurstOpacity = Tween<double>(begin: 0.8, end: 0.0).animate(
      CurvedAnimation(parent: _glowBurstController, curve: Curves.easeOut),
    );

    // Breathing glow
    _breatheController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _breatheAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _breatheController, curve: Curves.easeInOut),
    );

    // Text slide up with fade
    _textController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOut),
    );

    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _textController, curve: Curves.easeOutCubic));

    // Particles floating
    _particleController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    )..repeat();

    // Energy ring rotation
    _ringController = AnimationController(
      duration: const Duration(milliseconds: 4000),
      vsync: this,
    )..repeat();

    // Flash at the end
    _flashController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _flashOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 70),
    ]).animate(_flashController);
  }

  void _startSequence() async {
    // Initial delay
    await Future.delayed(const Duration(milliseconds: 300));

    // Logo entrance with haptic
    if (mounted) {
      _logoController.forward();
      HapticFeedback.lightImpact();
    }

    // Glow burst when logo lands
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) {
      _glowBurstController.forward();
      HapticFeedback.heavyImpact();
    }

    // Start breathing and particles
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) {
      _breatheController.repeat(reverse: true);
    }

    // Text appears
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      _textController.forward();
    }

    // Wait then flash out
    await Future.delayed(Duration(milliseconds: widget.duration.inMilliseconds - 2200));
    if (mounted) {
      HapticFeedback.mediumImpact();
      _flashController.forward();
    }

    // Complete
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) {
      widget.onComplete();
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _glowBurstController.dispose();
    _breatheController.dispose();
    _textController.dispose();
    _particleController.dispose();
    _ringController.dispose();
    _flashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _deepBlue,
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.5,
                colors: [
                  _deepBlue.withValues(alpha: 1),
                  const Color(0xFF050A12),
                ],
              ),
            ),
          ),

          // Floating particles
          AnimatedBuilder(
            animation: _particleController,
            builder: (context, child) {
              return CustomPaint(
                painter: _ParticlePainter(
                  particles: _particles,
                  progress: _particleController.value,
                  color: _neonCyan,
                ),
                size: Size.infinite,
              );
            },
          ),

          // Energy ring
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([_ringController, _breatheController]),
              builder: (context, child) {
                return Transform.rotate(
                  angle: _ringController.value * math.pi * 2,
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _neonCyan.withValues(alpha: 0.1 + (_breatheAnimation.value * 0.15)),
                        width: 1,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Second energy ring (counter-rotate)
          Center(
            child: AnimatedBuilder(
              animation: _ringController,
              builder: (context, child) {
                return Transform.rotate(
                  angle: -_ringController.value * math.pi * 2 * 0.7,
                  child: Container(
                    width: 320,
                    height: 320,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _electricBlue.withValues(alpha: 0.08),
                        width: 0.5,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Glow burst effect
          Center(
            child: AnimatedBuilder(
              animation: _glowBurstController,
              builder: (context, child) {
                return Transform.scale(
                  scale: _glowBurstScale.value,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _neonCyan.withValues(alpha: _glowBurstOpacity.value * 0.6),
                          blurRadius: 100,
                          spreadRadius: 50,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Main content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo with animations
                AnimatedBuilder(
                  animation: Listenable.merge([_logoController, _breatheController]),
                  builder: (context, child) {
                    final breatheValue = _breatheController.isAnimating
                        ? _breatheAnimation.value.clamp(0.0, 1.0)
                        : 0.5;

                    // Clamp values to prevent assertion errors
                    final scaleValue = _logoScale.value.clamp(0.0, 2.0);
                    final opacityValue = _logoOpacity.value.clamp(0.0, 1.0);

                    return Transform.rotate(
                      angle: _logoRotation.value,
                      child: Transform.scale(
                        scale: scaleValue,
                        child: Opacity(
                          opacity: opacityValue,
                          child: Container(
                            width: 180,
                            height: 180,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(36),
                              boxShadow: [
                                // Outer glow
                                BoxShadow(
                                  color: _neonCyan.withValues(alpha: 0.3 * breatheValue),
                                  blurRadius: 40 + (20 * breatheValue),
                                  spreadRadius: 5,
                                ),
                                // Inner glow
                                BoxShadow(
                                  color: _neonBlue.withValues(alpha: 0.4 * breatheValue),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(36),
                              child: Image.asset(
                                'assets/images/splash_logo.png',
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 40),

                // Text with slide animation
                SlideTransition(
                  position: _textSlide,
                  child: FadeTransition(
                    opacity: _textOpacity,
                    child: Column(
                      children: [
                        // TORO text with glow
                        AnimatedBuilder(
                          animation: _breatheController,
                          builder: (context, child) {
                            final glow = _breatheController.isAnimating ? _breatheAnimation.value : 0.5;
                            return Text(
                              widget.title,
                              style: TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 16,
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    color: _neonCyan.withValues(alpha: 0.8 * glow),
                                    blurRadius: 20,
                                  ),
                                  Shadow(
                                    color: _neonBlue.withValues(alpha: 0.6 * glow),
                                    blurRadius: 40,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                        if (widget.subtitle != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            widget.subtitle!,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 12,
                              color: _neonCyan.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 60),

                // Loading indicator
                FadeTransition(
                  opacity: _textOpacity,
                  child: _buildLoadingIndicator(),
                ),
              ],
            ),
          ),

          // Flash overlay
          AnimatedBuilder(
            animation: _flashController,
            builder: (context, child) {
              return IgnorePointer(
                child: Container(
                  color: Colors.white.withValues(alpha: _flashOpacity.value),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return AnimatedBuilder(
      animation: _ringController,
      builder: (context, child) {
        return SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            children: [
              // Outer ring
              Positioned.fill(
                child: Transform.rotate(
                  angle: _ringController.value * math.pi * 2,
                  child: CustomPaint(
                    painter: _LoadingRingPainter(
                      color: _neonCyan,
                      strokeWidth: 2,
                      progress: 0.7,
                    ),
                  ),
                ),
              ),
              // Inner ring (counter-rotate)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Transform.rotate(
                    angle: -_ringController.value * math.pi * 2 * 1.5,
                    child: CustomPaint(
                      painter: _LoadingRingPainter(
                        color: _neonBlue,
                        strokeWidth: 1.5,
                        progress: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Particle data class
class _Particle {
  double x, y, size, speed, angle, opacity;

  _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.angle,
    required this.opacity,
  });
}

// Particle painter
class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;
  final Color color;

  _ParticlePainter({
    required this.particles,
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    for (final particle in particles) {
      // Calculate position with circular motion
      final angle = particle.angle + (progress * math.pi * 2 * particle.speed);
      final radius = 100 + (particle.x.abs() % 150);

      final x = center.dx + math.cos(angle) * radius;
      final y = center.dy + math.sin(angle) * radius;

      final paint = Paint()
        ..color = color.withValues(alpha: particle.opacity * 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

      canvas.drawCircle(Offset(x, y), particle.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) => true;
}

// Loading ring painter
class _LoadingRingPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double progress;

  _LoadingRingPainter({
    required this.color,
    required this.strokeWidth,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, 0, progress * math.pi * 2, false, paint);
  }

  @override
  bool shouldRepaint(covariant _LoadingRingPainter oldDelegate) => false;
}
