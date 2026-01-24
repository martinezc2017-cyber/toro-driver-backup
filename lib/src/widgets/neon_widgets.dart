import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/app_colors.dart';

/// TORO DRIVER - Neon UI Widgets
/// Animated glowing buttons and inputs with flowing gradient effect
/// Same style as Rider Web

// =============================================================================
// RESPONSIVE WEB WRAPPER - Constrains width on web for mobile-like experience
// =============================================================================
class ResponsiveWebWrapper extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ResponsiveWebWrapper({
    super.key,
    required this.child,
    this.maxWidth = 480,
  });

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

// =============================================================================
// NEON BUTTON - Animated flowing gradient border
// =============================================================================
class NeonButton extends StatefulWidget {
  final String text;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool outlined;
  final bool fullWidth;
  final double height;
  final NeonButtonStyle style;

  const NeonButton({
    super.key,
    required this.text,
    this.icon,
    this.onPressed,
    this.isLoading = false,
    this.outlined = false,
    this.fullWidth = true,
    this.height = 54,
    this.style = NeonButtonStyle.primary,
  });

  @override
  State<NeonButton> createState() => _NeonButtonState();
}

enum NeonButtonStyle { primary, success, danger, subtle }

class _NeonButtonState extends State<NeonButton>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Color> _getGradientColors() {
    switch (widget.style) {
      case NeonButtonStyle.success:
        return const [
          Color(0xFF059669),
          Color(0xFF10B981),
          Color(0xFF34D399),
          Color(0xFF6EE7B7),
          Color(0xFF10B981),
          Color(0xFF059669),
        ];
      case NeonButtonStyle.danger:
        return const [
          Color(0xFFDC2626),
          Color(0xFFEF4444),
          Color(0xFFF87171),
          Color(0xFFFCA5A5),
          Color(0xFFEF4444),
          Color(0xFFDC2626),
        ];
      case NeonButtonStyle.subtle:
        return const [
          Color(0xFF4B5563),
          Color(0xFF6B7280),
          Color(0xFF9CA3AF),
          Color(0xFF6B7280),
          Color(0xFF4B5563),
        ];
      case NeonButtonStyle.primary:
        return const [
          Color(0xFF0066FF),
          Color(0xFF00BFFF),
          Color(0xFF60A5FA),
          Color(0xFF93C5FD),
          Color(0xFF00D4FF),
          Color(0xFF0066FF),
          Color(0xFF00BFFF),
        ];
    }
  }

  Color _getNeonColor() {
    switch (widget.style) {
      case NeonButtonStyle.success:
        return AppColors.success;
      case NeonButtonStyle.danger:
        return AppColors.error;
      case NeonButtonStyle.subtle:
        return AppColors.textTertiary;
      case NeonButtonStyle.primary:
        return AppColors.primaryBright;
    }
  }

  @override
  Widget build(BuildContext context) {
    final neonColor = _getNeonColor();
    final isDisabled = widget.onPressed == null || widget.isLoading;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: isDisabled
            ? null
            : () {
                HapticFeedback.mediumImpact();
                widget.onPressed?.call();
              },
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final value = _controller.value;
            final beginX = -3.0 + (value * 6.0);
            final endX = -1.0 + (value * 6.0);

            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: widget.fullWidth ? double.infinity : null,
              height: widget.height,
              transform: Matrix4.diagonal3Values(_isPressed ? 0.98 : 1.0, _isPressed ? 0.98 : 1.0, 1.0),
              transformAlignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: isDisabled
                    ? null
                    : LinearGradient(
                        begin: Alignment(beginX, -1),
                        end: Alignment(endX, 1),
                        colors: _getGradientColors(),
                        tileMode: TileMode.repeated,
                      ),
                color: isDisabled ? const Color(0xFF2A2A2A) : null,
                boxShadow: isDisabled
                    ? null
                    : [
                        BoxShadow(
                          color: neonColor
                              .withValues(alpha: _isHovered ? 0.7 : 0.4),
                          blurRadius: _isHovered ? 25 : 15,
                          spreadRadius: _isHovered ? 2 : 0,
                        ),
                      ],
              ),
              child: Container(
                margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0A0A),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Center(
                  child: widget.isLoading
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: neonColor,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.icon != null) ...[
                              Icon(
                                widget.icon,
                                color: isDisabled
                                    ? const Color(0xFF6B7280)
                                    : neonColor,
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                            ],
                            Text(
                              widget.text,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isDisabled
                                    ? AppColors.textTertiary
                                    : _isHovered
                                        ? AppColors.primaryPale
                                        : Colors.white,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// =============================================================================
// NEON TEXT FIELD - Glowing input field
// =============================================================================
class NeonTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? hintText;
  final String? labelText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final FocusNode? focusNode;
  final bool enabled;

  const NeonTextField({
    super.key,
    this.controller,
    this.hintText,
    this.labelText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.enabled = true,
  });

  @override
  State<NeonTextField> createState() => _NeonTextFieldState();
}

class _NeonTextFieldState extends State<NeonTextField> {
  bool _isFocused = false;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {
      _isFocused = _focusNode.hasFocus;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isFocused
              ? AppColors.primaryBright.withValues(alpha: 0.6)
              : AppColors.border,
          width: _isFocused ? 1.5 : 1,
        ),
        boxShadow: _isFocused
            ? [
                BoxShadow(
                  color: AppColors.primaryBright.withValues(alpha: 0.2),
                  blurRadius: 15,
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
      child: TextFormField(
        controller: widget.controller,
        focusNode: _focusNode,
        obscureText: widget.obscureText,
        keyboardType: widget.keyboardType,
        validator: widget.validator,
        onChanged: widget.onChanged,
        onFieldSubmitted: widget.onSubmitted,
        enabled: widget.enabled,
        style: const TextStyle(
          fontSize: 16,
          color: Colors.white,
        ),
        decoration: InputDecoration(
          hintText: widget.hintText,
          labelText: widget.labelText,
          hintStyle: const TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 15,
          ),
          labelStyle: TextStyle(
            color: _isFocused ? AppColors.primaryBright : AppColors.textTertiary,
            fontSize: 14,
          ),
          prefixIcon: widget.prefixIcon != null
              ? Icon(
                  widget.prefixIcon,
                  color: _isFocused ? AppColors.primaryBright : AppColors.textTertiary,
                  size: 22,
                )
              : null,
          suffixIcon: widget.suffixIcon,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          errorStyle: const TextStyle(
            color: Color(0xFFFF6B6B),
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// NEON CARD - Card with subtle glow
// =============================================================================
class NeonCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final Color? glowColor;
  final double glowIntensity;
  final VoidCallback? onTap;

  const NeonCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.glowColor,
    this.glowIntensity = 0.15,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = glowColor ?? AppColors.primaryBright;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: margin,
        padding: padding ?? const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: color.withValues(alpha: 0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: glowIntensity),
              blurRadius: 20,
              spreadRadius: 0,
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

// =============================================================================
// NEON ICON BUTTON - Circular button with glow
// =============================================================================
class NeonIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final Color? color;
  final Color? backgroundColor;
  final bool showGlow;

  const NeonIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 48,
    this.color,
    this.backgroundColor,
    this.showGlow = true,
  });

  @override
  State<NeonIconButton> createState() => _NeonIconButtonState();
}

class _NeonIconButtonState extends State<NeonIconButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppColors.primaryBright;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onPressed?.call();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: widget.size,
        height: widget.size,
        transform: Matrix4.diagonal3Values(_isPressed ? 0.95 : 1.0, _isPressed ? 0.95 : 1.0, 1.0),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          color: widget.backgroundColor ?? const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(widget.size / 4),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 1,
          ),
          boxShadow: widget.showGlow
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 12,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: Icon(
          widget.icon,
          color: color,
          size: widget.size * 0.5,
        ),
      ),
    );
  }
}

// =============================================================================
// NEON CHIP - Tag/Badge with glow
// =============================================================================
class NeonChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? color;
  final bool selected;
  final VoidCallback? onTap;

  const NeonChip({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? AppColors.primaryBright;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap?.call();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? chipColor.withValues(alpha: 0.2)
              : const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? chipColor.withValues(alpha: 0.6)
                : const Color(0xFF2A2A2A),
            width: 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: chipColor.withValues(alpha: 0.3),
                    blurRadius: 10,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: selected ? chipColor : const Color(0xFF9CA3AF),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: selected ? chipColor : const Color(0xFF9CA3AF),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// NEON DIVIDER - Glowing line divider
// =============================================================================
class NeonDivider extends StatelessWidget {
  final double thickness;
  final Color? color;
  final double indent;
  final double endIndent;

  const NeonDivider({
    super.key,
    this.thickness = 1,
    this.color,
    this.indent = 0,
    this.endIndent = 0,
  });

  @override
  Widget build(BuildContext context) {
    final dividerColor = color ?? AppColors.primaryBright;

    return Container(
      margin: EdgeInsets.only(left: indent, right: endIndent),
      height: thickness,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            dividerColor.withValues(alpha: 0.5),
            dividerColor.withValues(alpha: 0.5),
            Colors.transparent,
          ],
          stops: const [0.0, 0.2, 0.8, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: dividerColor.withValues(alpha: 0.3),
            blurRadius: 4,
            spreadRadius: 0,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// NEON PROGRESS INDICATOR - Glowing loading indicator
// =============================================================================
class NeonProgressIndicator extends StatelessWidget {
  final double? value;
  final double size;
  final Color? color;
  final double strokeWidth;

  const NeonProgressIndicator({
    super.key,
    this.value,
    this.size = 40,
    this.color,
    this.strokeWidth = 3,
  });

  @override
  Widget build(BuildContext context) {
    final indicatorColor = color ?? AppColors.primaryBright;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: indicatorColor.withValues(alpha: 0.4),
            blurRadius: 15,
            spreadRadius: 0,
          ),
        ],
      ),
      child: CircularProgressIndicator(
        value: value,
        strokeWidth: strokeWidth,
        color: indicatorColor,
        backgroundColor: indicatorColor.withValues(alpha: 0.2),
      ),
    );
  }
}

// =============================================================================
// NEON SWITCH - Toggle with glow effect
// =============================================================================
class NeonSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;

  const NeonSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = activeColor ?? AppColors.primaryBright;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onChanged?.call(!value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 52,
        height: 30,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: value ? color.withValues(alpha: 0.3) : const Color(0xFF2A2A2A),
          border: Border.all(
            color: value ? color.withValues(alpha: 0.6) : const Color(0xFF3A3A3A),
            width: 1,
          ),
          boxShadow: value
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 12,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? color : const Color(0xFF6B7280),
              boxShadow: value
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.6),
                        blurRadius: 8,
                        spreadRadius: 0,
                      ),
                    ]
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
