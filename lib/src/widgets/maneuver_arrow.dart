import 'package:flutter/material.dart';

/// Widget de flecha de maniobra usando iconos de Material Design
/// Diseño limpio y profesional
class ManeuverArrow extends StatefulWidget {
  final String maneuverType;
  final String? modifier;
  final String? exitRef;  // Número de salida/ruta (ej: "51A", "AZ 202")
  final double size;
  final Color color;
  final Color backgroundColor;
  final bool animate;
  final double distanceToManeuver;

  const ManeuverArrow({
    super.key,
    required this.maneuverType,
    this.modifier,
    this.exitRef,
    this.size = 64,
    this.color = Colors.white,
    this.backgroundColor = const Color(0xFF1A73E8),
    this.animate = true,
    this.distanceToManeuver = 1000,
  });

  @override
  State<ManeuverArrow> createState() => _ManeuverArrowState();
}

class _ManeuverArrowState extends State<ManeuverArrow>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _updateAnimation();
  }

  void _updateAnimation() {
    if (widget.animate && widget.distanceToManeuver < 300) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
      if (widget.distanceToManeuver < 100) {
        _controller.duration = const Duration(milliseconds: 500);
      } else {
        _controller.duration = const Duration(milliseconds: 1000);
      }
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void didUpdateWidget(ManeuverArrow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateAnimation();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  IconData _getIcon() {
    switch (widget.maneuverType) {
      case 'turn':
        return _getTurnIcon();
      case 'depart':
        return Icons.trip_origin;
      case 'arrive':
        return Icons.flag;
      case 'merge':
        return Icons.merge;
      case 'fork':
        return widget.modifier == 'left'
            ? Icons.fork_left
            : Icons.fork_right;
      case 'roundabout':
      case 'rotary':
        return Icons.roundabout_left;
      case 'off ramp':
        return widget.modifier == 'left'
            ? Icons.ramp_left
            : Icons.ramp_right;
      case 'on ramp':
        return Icons.merge;
      case 'end of road':
        return widget.modifier == 'left'
            ? Icons.turn_left
            : Icons.turn_right;
      case 'continue':
      case 'new name':
      case 'straight':
      default:
        return Icons.arrow_upward;
    }
  }

  IconData _getTurnIcon() {
    switch (widget.modifier) {
      case 'left':
        return Icons.turn_left;
      case 'right':
        return Icons.turn_right;
      case 'slight left':
        return Icons.turn_slight_left;
      case 'slight right':
        return Icons.turn_slight_right;
      case 'sharp left':
        return Icons.turn_sharp_left;
      case 'sharp right':
        return Icons.turn_sharp_right;
      case 'uturn':
        return Icons.u_turn_left;
      default:
        return Icons.arrow_upward;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final shouldPulse = widget.distanceToManeuver < 300;
        final scale = shouldPulse ? _pulseAnimation.value : 1.0;

        final hasRef = widget.exitRef != null && widget.exitRef!.isNotEmpty;

        return Transform.scale(
          scale: scale,
          child: Container(
            width: widget.size,
            height: hasRef ? widget.size * 1.3 : widget.size,
            decoration: BoxDecoration(
              color: widget.backgroundColor,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Número de referencia (si existe)
                if (hasRef)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 2),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        widget.exitRef!,
                        style: TextStyle(
                          color: widget.backgroundColor,
                          fontSize: widget.size * 0.18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                // Icono de maniobra
                Icon(
                  _getIcon(),
                  size: hasRef ? widget.size * 0.55 : widget.size * 0.65,
                  color: widget.color,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
