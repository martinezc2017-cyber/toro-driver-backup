import 'package:flutter/material.dart';

import '../utils/app_colors.dart';

/// Fondo claro de toda la app del conductor: blanco cálido con bruma azul y
/// dorada (dos degradados radiales). Sustituye a la galaxia negra con estrellas;
/// conserva el nombre para no tocar main.dart ni las pantallas.
class GalaxyBackground extends StatelessWidget {
  final Widget? child;
  const GalaxyBackground({super.key, this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: AppColors.backgroundWarm),
        const Positioned(top: -140, right: -120, child: IgnorePointer(child: _Haze(size: 460, color: Color(0x261769FF)))),
        const Positioned(top: 160, left: -180, child: IgnorePointer(child: _Haze(size: 380, color: Color(0x12D4AF37)))),
        const Positioned(bottom: -200, right: -60, child: IgnorePointer(child: _Haze(size: 420, color: Color(0x14D4AF37)))),
        if (child != null) child!,
      ],
    );
  }
}

class _Haze extends StatelessWidget {
  const _Haze({required this.size, required this.color});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      );
}
