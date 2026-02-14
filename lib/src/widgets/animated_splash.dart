import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Videogame-style animated splash screen
///
/// Three phases:
/// 1. INTRO: particles start, image fades in, text slides, scan line sweeps (~2s)
/// 2. HOLD: image + particles + loading ring visible indefinitely
/// 3. EXIT: triggered externally via [triggerExit], fade out → onComplete
class AnimatedSplash extends StatefulWidget {
  final String title;
  final String? subtitle;
  final VoidCallback onComplete;
  /// When this notifier becomes true, the splash starts its exit fade.
  /// If null, exits after [minDuration].
  final ValueNotifier<bool>? triggerExit;
  /// Minimum time the splash is visible before exit can trigger (default 2s).
  final Duration minDuration;

  const AnimatedSplash({
    super.key,
    this.title = 'TORO',
    this.subtitle,
    required this.onComplete,
    this.triggerExit,
    this.minDuration = const Duration(milliseconds: 3500),
  });

  @override
  State<AnimatedSplash> createState() => _AnimatedSplashState();
}

class _AnimatedSplashState extends State<AnimatedSplash>
    with TickerProviderStateMixin {
  // Breathing glow overlay
  late AnimationController _breatheController;
  late Animation<double> _breatheAnimation;

  // Text animations
  late AnimationController _textController;
  late Animation<double> _textOpacity;
  late Animation<Offset> _textSlide;

  // Particles (sparks floating up)
  late AnimationController _particleController;
  final List<_Particle> _particles = [];

  // Energy scan line
  late AnimationController _scanController;

  // Loading ring
  late AnimationController _ringController;

  // Smooth fade-out
  late AnimationController _exitController;
  late Animation<double> _exitOpacity;

  // Colors
  static const Color _neonCyan = Color(0xFF00D4FF);
  static const Color _neonBlue = Color(0xFF60A5FA);
  static const Color _deepBlue = Color(0xFF030B1A);

  /// Channel to tell native side the first Flutter frame is ready.
  /// Native removes the splash overlay instantly on receiving "ready".
  static const _splashChannel = MethodChannel('com.tororide.driver/splash');

  bool _introComplete = false;
  bool _exitStarted = false;
  late final Stopwatch _sw;

  // Smooth-time accumulator: measures ACTUAL visible rendering time.
  // Frame deltas are capped at 50ms so Impeller/Vulkan blocks (which show
  // a frozen screen) don't consume the splash time budget.
  int _smoothTimeMs = 0;
  Duration? _prevTimestamp;
  int _renderedFrames = 0;
  bool _textStarted = false;
  bool _scanStarted = false;
  /// Frames taking longer than this are "frozen" and get capped.
  /// Higher value = smooth time accumulates faster despite jank.
  static const int _maxFrameDeltaMs = 150;

  @override
  void initState() {
    super.initState();
    _sw = Stopwatch()..start();
    debugPrint('[SPLASH] initState at ${_sw.elapsedMilliseconds}ms');
    HapticFeedback.mediumImpact();
    _initParticles();
    _initAnimations();
    // Listen for external exit trigger
    widget.triggerExit?.addListener(_onExitTriggered);
    // Start looping animations immediately (visible once rendering starts)
    _breatheController.repeat(reverse: true);
    // No image to load — the cosmic background comes from the Android window
    // background (@drawable/launch_background). Flutter renders particles, text,
    // and loading ring on a transparent Scaffold, so the window bg shows through.
    // Smooth-time accumulator starts from first rendered frame.
    WidgetsBinding.instance.addPersistentFrameCallback(_onFrame);
  }

  /// Called when triggerExit becomes true
  void _onExitTriggered() {
    if (widget.triggerExit?.value == true) {
      debugPrint('[SPLASH] exit TRIGGERED at ${_sw.elapsedMilliseconds}ms (introComplete=$_introComplete)');
      _tryStartExit();
    }
  }

  /// Start exit only if intro is complete AND exit was triggered
  void _tryStartExit() {
    if (_exitStarted || !mounted) return;
    final triggered = widget.triggerExit?.value ?? true;
    if (_introComplete && triggered) {
      _startExit();
    }
  }

  void _initParticles() {
    final random = math.Random();
    for (int i = 0; i < 40; i++) {
      _particles.add(_Particle(
        x: random.nextDouble(),
        y: random.nextDouble(),
        size: random.nextDouble() * 2.0 + 0.8,
        speed: random.nextDouble() * 0.4 + 0.15,
        drift: (random.nextDouble() - 0.5) * 0.3,
        opacity: random.nextDouble() * 0.25 + 0.15, // 0.15–0.40 (subtle)
        type: random.nextInt(3), // 0=white, 1=cyan trail, 2=white
      ));
    }
  }

  void _initAnimations() {
    // Breathing glow pulse
    _breatheController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _breatheAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _breatheController, curve: Curves.easeInOut),
    );

    // Text slide up (fast)
    _textController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOut),
    );
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.8),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _textController, curve: Curves.easeOutCubic));

    // Particles loop (fast cycle for energetic motion)
    _particleController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();

    // Scan line sweep
    _scanController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );

    // Loading ring
    _ringController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    )..repeat();

    // Smooth gradient exit (fast)
    _exitController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _exitOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeInQuart),
    );
  }

  /// Called every rendered frame. Accumulates "smooth time" by measuring the
  /// delta between consecutive frame timestamps. Frame deltas are CAPPED at
  /// [_maxFrameDeltaMs] so that Impeller/Vulkan blocks (which freeze the screen
  /// for seconds) only contribute a tiny amount to the time budget.
  ///
  /// No image to wait for — the cosmic background is the Android window
  /// background. Flutter only renders particles/text on a transparent surface.
  /// Smooth-time starts counting from the very first rendered frame.
  void _onFrame(Duration timestamp) {
    if (!mounted || _introComplete) return;
    _renderedFrames++;

    if (_prevTimestamp == null) {
      // First rendered frame
      _prevTimestamp = timestamp;
      debugPrint('[SPLASH] FIRST frame at ${_sw.elapsedMilliseconds}ms wall');
      HapticFeedback.lightImpact();
      // Signal native (no-op now, but kept for compatibility)
      _splashChannel.invokeMethod('ready').catchError((_) {});
      return;
    }

    // Measure actual frame delta from engine timestamps
    final deltaMs = (timestamp - _prevTimestamp!).inMilliseconds;
    _prevTimestamp = timestamp;

    // Cap slow frames: a 3-second Impeller block contributes only 50ms,
    // while normal 60fps frames contribute their full ~16ms.
    _smoothTimeMs += deltaMs.clamp(0, _maxFrameDeltaMs);

    // Text slides in at 150ms of smooth rendering
    if (_smoothTimeMs >= 150 && !_textStarted) {
      _textStarted = true;
      _textController.forward();
      debugPrint('[SPLASH] text at ${_smoothTimeMs}ms smooth (frame $_renderedFrames, delta=${deltaMs}ms)');
    }

    // Scan line at 400ms of smooth rendering
    if (_smoothTimeMs >= 400 && !_scanStarted) {
      _scanStarted = true;
      _scanController.forward();
      HapticFeedback.heavyImpact();
      debugPrint('[SPLASH] scan at ${_smoothTimeMs}ms smooth (frame $_renderedFrames, delta=${deltaMs}ms)');
    }

    // Intro complete after minDuration of smooth rendering
    if (_smoothTimeMs >= widget.minDuration.inMilliseconds) {
      debugPrint('[SPLASH] intro COMPLETE at ${_smoothTimeMs}ms smooth (frame $_renderedFrames, ${_sw.elapsedMilliseconds}ms wall)');
      _introComplete = true;
      // If exit was already triggered while intro was running, start exit now
      _tryStartExit();
    }
  }

  /// Phase 3: EXIT - fade out and call onComplete
  void _startExit() {
    if (_exitStarted || !mounted) return;
    _exitStarted = true;
    debugPrint('[SPLASH] exit fade started at ${_sw.elapsedMilliseconds}ms');

    _exitController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        debugPrint('[SPLASH] onComplete at ${_sw.elapsedMilliseconds}ms');
        widget.onComplete();
      }
    });

    _exitController.forward();
  }

  @override
  void dispose() {
    widget.triggerExit?.removeListener(_onExitTriggered);
    _breatheController.dispose();
    _textController.dispose();
    _particleController.dispose();
    _scanController.dispose();
    _ringController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Transparent Scaffold — the Android window background
    // (@drawable/launch_background = cosmic TORO branding) shows through.
    // Flutter only renders particles, text, scan line, and loading ring.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Floating energy particles (sparks rising up like embers)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _particleController,
              builder: (context, child) {
                return CustomPaint(
                  painter: _EnergyParticlePainter(
                    particles: _particles,
                    progress: _particleController.value,
                    cyan: _neonCyan,
                    blue: _neonBlue,
                  ),
                );
              },
            ),
          ),

          // Energy scan line (horizontal light beam sweeping down)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _scanController,
              builder: (context, child) {
                if (!_scanController.isAnimating &&
                    _scanController.value == 0) {
                  return const SizedBox.shrink();
                }
                return CustomPaint(
                  painter: _ScanLinePainter(
                    progress: _scanController.value,
                    color: _neonCyan,
                  ),
                );
              },
            ),
          ),

          // Text + loading at bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 32,
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  SlideTransition(
                    position: _textSlide,
                    child: FadeTransition(
                      opacity: _textOpacity,
                      child: Column(
                        children: [
                          AnimatedBuilder(
                            animation: _breatheController,
                            builder: (context, child) {
                              final glow = _breatheController.isAnimating
                                  ? _breatheAnimation.value
                                  : 0.5;
                              return Text(
                                widget.title,
                                style: TextStyle(
                                  fontSize: 42,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 14,
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(
                                      color: _neonCyan.withValues(
                                          alpha: 0.9 * glow),
                                      blurRadius: 24,
                                    ),
                                    Shadow(
                                      color: _neonBlue.withValues(
                                          alpha: 0.6 * glow),
                                      blurRadius: 48,
                                    ),
                                    Shadow(
                                      color: _neonCyan.withValues(
                                          alpha: 0.3 * glow),
                                      blurRadius: 80,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          if (widget.subtitle != null) ...[
                            const SizedBox(height: 6),
                            AnimatedBuilder(
                              animation: _breatheController,
                              builder: (context, child) {
                                final glow = _breatheController.isAnimating
                                    ? _breatheAnimation.value
                                    : 0.5;
                                return Text(
                                  widget.subtitle!,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 12,
                                    color:
                                        _neonCyan.withValues(alpha: 0.7 + 0.3 * glow),
                                    shadows: [
                                      Shadow(
                                        color: _neonCyan.withValues(
                                            alpha: 0.4 * glow),
                                        blurRadius: 16,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Loading ring visible from the FIRST frame — not tied to text fade
                  _buildLoadingIndicator(),
                ],
              ),
            ),
          ),

          // Smooth gradient fade-out
          AnimatedBuilder(
            animation: _exitController,
            builder: (context, child) {
              if (_exitController.value == 0) {
                return const SizedBox.shrink();
              }
              return IgnorePointer(
                child: Container(
                  color: _deepBlue.withValues(alpha: _exitOpacity.value),
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
          width: 36,
          height: 36,
          child: Stack(
            children: [
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
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(5),
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

// Particle data
class _Particle {
  double x, y, size, speed, drift, opacity;
  int type;

  _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.drift,
    required this.opacity,
    required this.type,
  });
}

// Energy particles painter - bright sparks that contrast against cosmic bg
class _EnergyParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;
  final Color cyan;
  final Color blue;

  // High-contrast colors visible on dark cosmic backgrounds
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _gold = Color(0xFFFFD700);

  _EnergyParticlePainter({
    required this.particles,
    required this.progress,
    required this.cyan,
    required this.blue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final yOffset = (p.y - progress * p.speed) % 1.0;
      final xOffset = p.x + math.sin(progress * math.pi * 2 + p.drift * 10) * 0.05;

      final x = xOffset * size.width;
      final y = yOffset * size.height;

      final edgeFade = (yOffset < 0.1 ? yOffset / 0.1 : yOffset > 0.9 ? (1.0 - yOffset) / 0.1 : 1.0).clamp(0.0, 1.0);
      final alpha = p.opacity * edgeFade;

      // Subtle white/cyan mix
      final color = p.type == 1 ? cyan : _white;

      // Soft glow halo (small)
      final glowPaint = Paint()
        ..color = color.withValues(alpha: alpha * 0.2)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size * 2);
      canvas.drawCircle(Offset(x, y), p.size, glowPaint);

      // Core dot
      final corePaint = Paint()
        ..color = color.withValues(alpha: alpha * 0.7);
      canvas.drawCircle(Offset(x, y), p.size * 0.6, corePaint);

      // Short trail on some particles
      if (p.type == 1) {
        final trailPaint = Paint()
          ..color = color.withValues(alpha: alpha * 0.2)
          ..strokeWidth = p.size * 0.3
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(x, y),
          Offset(x, y + p.size * 4),
          trailPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EnergyParticlePainter oldDelegate) => true;
}

// Scan line painter - horizontal energy beam
class _ScanLinePainter extends CustomPainter {
  final double progress;
  final Color color;

  _ScanLinePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final y = progress * size.height;
    final fade = progress < 0.1
        ? progress / 0.1
        : progress > 0.8
            ? (1.0 - progress) / 0.2
            : 1.0;
    final alpha = (fade * 0.6).clamp(0.0, 1.0);

    final linePaint = Paint()
      ..color = color.withValues(alpha: alpha)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);

    final glowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0),
          color.withValues(alpha: alpha * 0.15),
          color.withValues(alpha: alpha * 0.3),
          color.withValues(alpha: alpha * 0.15),
          color.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(0, y - 40, size.width, 80));
    canvas.drawRect(Rect.fromLTWH(0, y - 40, size.width, 80), glowPaint);
  }

  @override
  bool shouldRepaint(covariant _ScanLinePainter oldDelegate) =>
      oldDelegate.progress != progress;
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
