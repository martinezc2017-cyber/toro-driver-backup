import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Reusable galaxy / starfield background (ported from the rider home screen).
/// Pure-black background with responsive, twinkling stars that scale to the
/// real available size (fills phones AND tablets). Pass [child] to render
/// content on top of the galaxy.
class GalaxyBackground extends StatefulWidget {
  final Widget? child;
  const GalaxyBackground({super.key, this.child});

  @override
  State<GalaxyBackground> createState() => _GalaxyBackgroundState();
}

class _GalaxyBackgroundState extends State<GalaxyBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Consistent random star positions (seeded so they don't jump on rebuild).
  static final _rng = math.Random(77);
  static const int _maxStars = 60;
  static final _stars = List.generate(_maxStars, (_) => [
        _rng.nextDouble(), // x fraction (0-1)
        _rng.nextDouble(), // y fraction (0-1)
        _rng.nextDouble() * 2.5 + 1.5, // base size (1.5-4)
        _rng.nextDouble(), // phase offset
      ]);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = MediaQuery.of(context).size;
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : size.width;
        final h = constraints.maxHeight.isFinite ? constraints.maxHeight : size.height;
        // Density + star size scale with the real area (no phone-sized box).
        final count = (w * h / 14000).round().clamp(30, _maxStars);
        final shortest = w < h ? w : h;
        final sizeBoost = (shortest / 380).clamp(1.0, 1.9);

        return Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Colors.black)),
            ...List.generate(count, (i) {
              final xf = _stars[i][0];
              final yf = _stars[i][1];
              final starSize = _stars[i][2] * sizeBoost;
              final phase = _stars[i][3];
              return Positioned(
                left: xf * w,
                top: yf * h,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final t = _controller.value;
                    final dx = math.sin((t + phase) * 2 * math.pi) * 8;
                    final dy = math.cos((t + phase * 1.3) * 2 * math.pi) * 10;
                    final opacity = 0.55 +
                        math.sin((t + phase * 0.7) * 2 * math.pi) * 0.35;
                    return Transform.translate(
                      offset: Offset(dx, dy),
                      child: Container(
                        width: starSize,
                        height: starSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: opacity),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: opacity * 0.6),
                              blurRadius: starSize * 2.2,
                              spreadRadius: 0.4,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            }),
            if (widget.child != null) Positioned.fill(child: widget.child!),
          ],
        );
      },
    );
  }
}
