import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../src/utils/app_colors.dart';
import '../../src/widgets/toro_design_system.dart';

/// Arranque del conductor: la franja eléctrica de la marca a pantalla completa,
/// el logo REAL (assets/images/toro_logo.png) con su luz y una barra de progreso
/// fina. Mismo arranque que el rider para que las dos apps se sientan una.
class ToroSplashScreen extends StatefulWidget {
  final VoidCallback? onComplete;
  final Duration duration;

  const ToroSplashScreen({
    super.key,
    this.onComplete,
    this.duration = const Duration(milliseconds: 3500),
  });

  @override
  State<ToroSplashScreen> createState() => _ToroSplashScreenState();
}

class _ToroSplashScreenState extends State<ToroSplashScreen>
    with TickerProviderStateMixin {
  bool get _isSpanish =>
      PlatformDispatcher.instance.locale.languageCode.toLowerCase() == 'es';

  late AnimationController _mainController;
  late AnimationController _glowController;
  late AnimationController _progressController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    _mainController = AnimationController(duration: const Duration(milliseconds: 2000), vsync: this);
    _glowController = AnimationController(duration: const Duration(milliseconds: 1500), vsync: this)..repeat(reverse: true);
    _progressController = AnimationController(duration: widget.duration - const Duration(milliseconds: 400), vsync: this);

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _mainController, curve: const Interval(0.0, 0.5, curve: Curves.easeOut)),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _mainController, curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack)),
    );
    _glowAnimation = Tween<double>(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeInOut),
    );

    _mainController.forward();
    _progressController.forward();
    Timer(widget.duration, () {
      if (mounted) widget.onComplete?.call();
    });
  }

  @override
  void dispose() {
    _mainController.dispose();
    _glowController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: AppColors.ink,
        body: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedBuilder(
              animation: _glowAnimation,
              builder: (context, _) => ToroBand(
                overlap: 0,
                padding: EdgeInsets.zero,
                intensity: _glowAnimation.value,
                child: const SizedBox.expand(),
              ),
            ),
            SafeArea(
              child: Center(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_mainController, _glowController]),
                  builder: (context, child) {
                    return FadeTransition(
                      opacity: _fadeAnimation,
                      child: ScaleTransition(
                        scale: _scaleAnimation,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Spacer(flex: 2),
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(44),
                                boxShadow: [
                                  BoxShadow(
                                    color: ToroColors.blue.withValues(alpha: 0.45 * _glowAnimation.value),
                                    blurRadius: 70,
                                    spreadRadius: 10,
                                  ),
                                  BoxShadow(
                                    color: ToroColors.cyan.withValues(alpha: 0.25 * _glowAnimation.value),
                                    blurRadius: 36,
                                  ),
                                ],
                              ),
                              child: const ToroLogo(size: 150, glow: false),
                            ),
                            const SizedBox(height: 28),
                            Text(
                              'TORO',
                              style: ToroType.display(context, size: 34).copyWith(
                                letterSpacing: 6,
                                shadows: const [Shadow(color: Color(0x8035C6FF), blurRadius: 20)],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _isSpanish ? 'CONDUCTOR' : 'DRIVER',
                              style: const TextStyle(
                                color: ToroColors.gold,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 5,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _isSpanish ? 'Conduce el futuro' : 'Drive the future',
                              style: ToroType.body(context, size: 14, color: const Color(0xB8FFFFFF)),
                            ),
                            const Spacer(),
                            Container(
                              width: 180,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: AnimatedBuilder(
                                animation: _progressAnimation,
                                builder: (context, child) => FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: _progressAnimation.value,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(colors: [ToroColors.blue, ToroColors.cyan]),
                                      borderRadius: BorderRadius.circular(2),
                                      boxShadow: const [BoxShadow(color: Color(0x8035C6FF), blurRadius: 10, spreadRadius: 1)],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _isSpanish ? 'CARGANDO' : 'LOADING',
                              style: const TextStyle(color: Color(0x8CFFFFFF), fontSize: 11.5, letterSpacing: 3, fontWeight: FontWeight.w600),
                            ),
                            const Spacer(flex: 1),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
