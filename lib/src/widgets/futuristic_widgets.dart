import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../utils/app_colors.dart';
import '../utils/app_theme.dart';
import '../utils/haptic_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// BOTÓN NEÓN FUTURISTA
// ═══════════════════════════════════════════════════════════════════════════════

class NeonButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool isOutlined;
  final Color? color;
  final Gradient? gradient;
  final double? width;
  final double height;
  final bool enableHaptic;

  const NeonButton({
    super.key,
    required this.text,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.isOutlined = false,
    this.color,
    this.gradient,
    this.width,
    this.height = 56,
    this.enableHaptic = true,
  });

  @override
  State<NeonButton> createState() => _NeonButtonState();
}

class _NeonButtonState extends State<NeonButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _glowAnimation = Tween<double>(begin: 0.4, end: 0.8).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.onPressed != null && !widget.isLoading) {
      _controller.forward();
      if (widget.enableHaptic) {
        HapticService.lightImpact();
      }
    }
  }

  void _handleTapUp(TapUpDetails details) {
    _controller.reverse();
  }

  void _handleTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final buttonColor = widget.color ?? AppColors.primary;
    final buttonGradient = widget.gradient ??
        LinearGradient(
          colors: [buttonColor, buttonColor.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: () {
        if (widget.onPressed != null && !widget.isLoading) {
          if (widget.enableHaptic) {
            HapticService.buttonPress();
          }
          widget.onPressed!();
        }
      },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: widget.width,
              height: widget.height,
              decoration: BoxDecoration(
                gradient: widget.isOutlined ? null : buttonGradient,
                borderRadius: BorderRadius.circular(16),
                border: widget.isOutlined
                    ? Border.all(color: buttonColor, width: 2)
                    : null,
                boxShadow: widget.isOutlined
                    ? null
                    : [
                        BoxShadow(
                          color: buttonColor.withValues(alpha: _glowAnimation.value),
                          blurRadius: 20,
                          spreadRadius: 0,
                        ),
                      ],
              ),
              child: Material(
                color: Colors.transparent,
                child: Center(
                  child: widget.isLoading
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              widget.isOutlined
                                  ? buttonColor
                                  : AppColors.background,
                            ),
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.icon != null) ...[
                              Icon(
                                widget.icon,
                                color: widget.isOutlined
                                    ? buttonColor
                                    : AppColors.background,
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                            ],
                            Text(
                              widget.text,
                              style: TextStyle(
                                color: widget.isOutlined
                                    ? buttonColor
                                    : AppColors.background,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TARJETA GLASS FUTURISTA
// ═══════════════════════════════════════════════════════════════════════════════

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Color? borderColor;
  final VoidCallback? onTap;
  final bool animate;
  final Duration? animationDelay;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 20,
    this.borderColor,
    this.onTap,
    this.animate = true,
    this.animationDelay,
  });

  @override
  Widget build(BuildContext context) {
    Widget card = GestureDetector(
      onTap: onTap != null
          ? () {
              HapticService.lightImpact();
              onTap!();
            }
          : null,
      child: Container(
        margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: borderColor ?? const Color(0xFF00FFFF).withValues(alpha: 0.35),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00FFFF).withValues(alpha: 0.15),
              blurRadius: 12,
              spreadRadius: 0,
            ),
            BoxShadow(
              color: const Color(0xFF00D4FF).withValues(alpha: 0.1),
              blurRadius: 20,
              spreadRadius: -4,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: padding ?? const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.card.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(borderRadius),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );

    if (animate) {
      return card
          .animate(delay: animationDelay ?? Duration.zero)
          .fadeIn(duration: 400.ms)
          .slideY(begin: 0.1, end: 0, duration: 400.ms, curve: Curves.easeOutCubic);
    }

    return card;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// INDICADOR DE ESTADO CON GLOW
// ═══════════════════════════════════════════════════════════════════════════════

class GlowingStatusIndicator extends StatefulWidget {
  final bool isActive;
  final double size;
  final Color? activeColor;
  final Color? inactiveColor;

  const GlowingStatusIndicator({
    super.key,
    required this.isActive,
    this.size = 12,
    this.activeColor,
    this.inactiveColor,
  });

  @override
  State<GlowingStatusIndicator> createState() => _GlowingStatusIndicatorState();
}

class _GlowingStatusIndicatorState extends State<GlowingStatusIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isActive
        ? (widget.activeColor ?? AppColors.success)
        : (widget.inactiveColor ?? AppColors.textSecondary);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: widget.isActive
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: _animation.value * 0.6),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AVATAR FUTURISTA CON BORDE NEÓN
// ═══════════════════════════════════════════════════════════════════════════════

class NeonAvatar extends StatelessWidget {
  final String? imageUrl;
  final String? initials;
  final double size;
  final Color? borderColor;
  final bool showGlow;
  final bool isOnline;

  const NeonAvatar({
    super.key,
    this.imageUrl,
    this.initials,
    this.size = 60,
    this.borderColor,
    this.showGlow = true,
    this.isOnline = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = borderColor ?? AppColors.primary;

    return Stack(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [color, color.withValues(alpha: 0.6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: showGlow
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 15,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.all(3),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.card,
              image: imageUrl != null
                  ? DecorationImage(
                      image: NetworkImage(imageUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: imageUrl == null
                ? Center(
                    child: Text(
                      initials ?? '?',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: size * 0.35,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : null,
          ),
        ),
        if (isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.25,
              height: size * 0.25,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.success,
                border: Border.all(color: AppColors.background, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.success.withValues(alpha: 0.5),
                    blurRadius: 6,
                    spreadRadius: 0,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CHIP FUTURISTA
// ═══════════════════════════════════════════════════════════════════════════════

class NeonChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? color;
  final bool isSelected;
  final VoidCallback? onTap;

  const NeonChip({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? AppColors.primary;

    return GestureDetector(
      onTap: () {
        HapticService.selectionClick();
        onTap?.call();
      },
      child: AnimatedContainer(
        duration: AppTheme.animFast,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? chipColor.withValues(alpha: 0.2) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? chipColor : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
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
                size: 18,
                color: isSelected ? chipColor : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? chipColor : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STAT CARD FUTURISTA
// ═══════════════════════════════════════════════════════════════════════════════

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final String? subtitle;
  final VoidCallback? onTap;
  final int animationIndex;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.subtitle,
    this.onTap,
    this.animationIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = color ?? AppColors.primary;

    return GestureDetector(
      onTap: onTap != null
          ? () {
              HapticService.lightImpact();
              onTap!();
            }
          : null,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
          boxShadow: AppColors.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: cardColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: cardColor,
                size: 24,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 12,
                  color: cardColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    )
        .animate(delay: Duration(milliseconds: 100 * animationIndex))
        .fadeIn(duration: 400.ms)
        .slideX(begin: 0.1, end: 0, duration: 400.ms, curve: Curves.easeOutCubic);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TOGGLE SWITCH FUTURISTA
// ═══════════════════════════════════════════════════════════════════════════════

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
    final color = activeColor ?? AppColors.primary;

    return GestureDetector(
      onTap: () {
        HapticService.toggle();
        onChanged?.call(!value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 56,
        height: 32,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: value ? color : AppColors.border,
          boxShadow: value
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 10,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.textPrimary,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROGRESS BAR FUTURISTA
// ═══════════════════════════════════════════════════════════════════════════════

class NeonProgressBar extends StatelessWidget {
  final double progress;
  final Color? color;
  final double height;
  final bool showGlow;

  const NeonProgressBar({
    super.key,
    required this.progress,
    this.color,
    this.height = 8,
    this.showGlow = true,
  });

  @override
  Widget build(BuildContext context) {
    final barColor = color ?? AppColors.primary;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                width: constraints.maxWidth * progress.clamp(0.0, 1.0),
                height: height,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [barColor, barColor.withValues(alpha: 0.8)],
                  ),
                  borderRadius: BorderRadius.circular(height / 2),
                  boxShadow: showGlow
                      ? [
                          BoxShadow(
                            color: barColor.withValues(alpha: 0.5),
                            blurRadius: 8,
                            spreadRadius: 0,
                          ),
                        ]
                      : null,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HEADER FUTURISTA
// ═══════════════════════════════════════════════════════════════════════════════

class FuturisticHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget>? actions;
  final bool showBackButton;
  final VoidCallback? onBack;

  const FuturisticHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions,
    this.showBackButton = false,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 20,
        right: 20,
        bottom: 20,
      ),
      decoration: BoxDecoration(
        gradient: AppColors.headerGradient,
        border: Border(
          bottom: BorderSide(
            color: AppColors.border.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          if (showBackButton)
            GestureDetector(
              onTap: () {
                HapticService.lightImpact();
                if (onBack != null) {
                  onBack!();
                } else {
                  Navigator.of(context).pop();
                }
              },
              child: Container(
                width: 44,
                height: 44,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 18,
                  color: AppColors.textPrimary,
                ),
              ),
            )
          else if (leading != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: leading,
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actions != null) ...actions!,
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 300.ms)
        .slideY(begin: -0.1, end: 0, duration: 300.ms);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BOTTOM NAV BAR FUTURISTA
// ═══════════════════════════════════════════════════════════════════════════════

class FuturisticBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<FuturisticNavItem> items;

  const FuturisticBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(
            color: AppColors.border.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final isSelected = index == currentIndex;

          return GestureDetector(
            onTap: () {
              HapticService.selectionClick();
              onTap(index);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isSelected ? item.activeIcon : item.icon,
                    color: isSelected ? AppColors.primary : AppColors.textSecondary,
                    size: 24,
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: 8),
                    Text(
                      item.label,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class FuturisticNavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const FuturisticNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHIMMER LOADING FUTURISTA
// ═══════════════════════════════════════════════════════════════════════════════

class NeonShimmer extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const NeonShimmer({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 12,
  });

  @override
  State<NeonShimmer> createState() => _NeonShimmerState();
}

class _NeonShimmerState extends State<NeonShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2.0 * _controller.value, 0),
              end: Alignment(1.0 + 2.0 * _controller.value, 0),
              colors: [
                AppColors.surface,
                AppColors.border,
                AppColors.surface,
              ],
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// INPUT FIELD FUTURISTA
// ═══════════════════════════════════════════════════════════════════════════════

class NeonTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final IconData? prefixIcon;
  final Widget? suffix;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  const NeonTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.prefixIcon,
    this.suffix,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.onChanged,
    this.enabled = true,
  });

  @override
  State<NeonTextField> createState() => _NeonTextFieldState();
}

class _NeonTextFieldState extends State<NeonTextField> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _isFocused ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Focus(
          onFocusChange: (focused) {
            setState(() => _isFocused = focused);
            if (focused) {
              HapticService.selectionClick();
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.2),
                        blurRadius: 15,
                        spreadRadius: 0,
                      ),
                    ]
                  : null,
            ),
            child: TextFormField(
              controller: widget.controller,
              obscureText: widget.obscureText,
              keyboardType: widget.keyboardType,
              validator: widget.validator,
              onChanged: widget.onChanged,
              enabled: widget.enabled,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
              ),
              decoration: InputDecoration(
                hintText: widget.hint,
                prefixIcon: widget.prefixIcon != null
                    ? Icon(
                        widget.prefixIcon,
                        color:
                            _isFocused ? AppColors.primary : AppColors.textSecondary,
                      )
                    : null,
                suffix: widget.suffix,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NEON GLOW BUTTON - Premium Neon Blue Navigation Button
// ═══════════════════════════════════════════════════════════════════════════════

class FireGlowButton extends StatefulWidget {
  final IconData icon;
  final IconData? activeIcon;
  final String label;
  final bool isSelected;
  final bool hasActiveGlow; // Green glow for active ride
  final VoidCallback onTap;

  const FireGlowButton({
    super.key,
    required this.icon,
    this.activeIcon,
    required this.label,
    required this.isSelected,
    this.hasActiveGlow = false,
    required this.onTap,
  });

  @override
  State<FireGlowButton> createState() => _FireGlowButtonState();
}

class _FireGlowButtonState extends State<FireGlowButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _glowAnimation;
  bool _isPressed = false;

  // Neon Blue colors for the glow effect (matching rider web theme)
  static const Color _neonPrimary = Color(0xFF0066FF);
  static const Color _neonBright = Color(0xFF60A5FA);
  static const Color _neonLight = Color(0xFF00BFFF);

  // Green colors for active ride glow
  static const Color _activeGreen = Color(0xFF10B981);
  static const Color _activeGreenBright = Color(0xFF34D399);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _glowAnimation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    // Animate if selected OR has active glow (for active ride)
    if (widget.isSelected || widget.hasActiveGlow) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(FireGlowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shouldAnimate = widget.isSelected || widget.hasActiveGlow;
    final wasAnimating = oldWidget.isSelected || oldWidget.hasActiveGlow;

    if (shouldAnimate && !wasAnimating) {
      _controller.repeat(reverse: true);
    } else if (!shouldAnimate && wasAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        HapticService.selectionClick();
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _glowAnimation,
        builder: (context, child) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon with neon glow border (green for active ride, blue for selected)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: widget.hasActiveGlow
                        ? _activeGreen.withValues(alpha: 0.15)
                        : widget.isSelected
                            ? _neonPrimary.withValues(alpha: 0.12)
                            : _isPressed
                                ? AppColors.cardHover
                                : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: widget.hasActiveGlow
                          ? _activeGreenBright.withValues(alpha: 0.5 + _glowAnimation.value * 0.5)
                          : widget.isSelected
                              ? _neonBright.withValues(alpha: 0.4 + _glowAnimation.value * 0.4)
                              : Colors.transparent,
                      width: widget.hasActiveGlow ? 2 : 1.5,
                    ),
                    boxShadow: widget.hasActiveGlow
                        ? [
                            // Green pulsing glow for active ride
                            BoxShadow(
                              color: _activeGreen.withValues(alpha: _glowAnimation.value * 0.7),
                              blurRadius: 18,
                              spreadRadius: 2,
                            ),
                            BoxShadow(
                              color: _activeGreenBright.withValues(alpha: _glowAnimation.value * 0.5),
                              blurRadius: 30,
                              spreadRadius: 0,
                            ),
                          ]
                        : widget.isSelected
                            ? [
                                // Inner neon glow
                                BoxShadow(
                                  color: _neonPrimary.withValues(alpha: _glowAnimation.value * 0.5),
                                  blurRadius: 14,
                                  spreadRadius: 1,
                                ),
                                // Outer cyan glow (stronger)
                                BoxShadow(
                                  color: _neonLight.withValues(alpha: _glowAnimation.value * 0.35),
                                  blurRadius: 24,
                                  spreadRadius: -1,
                                ),
                              ]
                            : null,
                  ),
                  child: Icon(
                    widget.isSelected || widget.hasActiveGlow
                        ? (widget.activeIcon ?? widget.icon)
                        : widget.icon,
                    color: widget.hasActiveGlow
                        ? _activeGreenBright
                        : widget.isSelected
                            ? _neonBright
                            : AppColors.textTertiary,
                    size: 24,
                  ),
                ),
                const SizedBox(height: 4),
                // Label
                Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.hasActiveGlow
                        ? _activeGreenBright
                        : widget.isSelected
                            ? _neonBright
                            : AppColors.textTertiary,
                    fontSize: 9,
                    fontWeight: (widget.isSelected || widget.hasActiveGlow) ? FontWeight.w600 : FontWeight.w400,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                // Neon indicator dot (green for active ride, blue for selected)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: (widget.isSelected || widget.hasActiveGlow) ? 6 : 0,
                  height: 6,
                  decoration: BoxDecoration(
                    gradient: widget.hasActiveGlow
                        ? LinearGradient(
                            colors: [_activeGreen, _activeGreenBright],
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                          )
                        : widget.isSelected
                            ? LinearGradient(
                                colors: [_neonPrimary, _neonLight],
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                              )
                            : null,
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: widget.hasActiveGlow
                        ? [
                            BoxShadow(
                              color: _activeGreenBright.withValues(alpha: 0.8),
                              blurRadius: 8,
                              spreadRadius: 0,
                            ),
                          ]
                        : widget.isSelected
                            ? [
                                BoxShadow(
                                  color: _neonLight.withValues(alpha: 0.6),
                                  blurRadius: 6,
                                  spreadRadius: 0,
                                ),
                              ]
                            : null,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NEON GLOW BOTTOM NAV BAR - Premium Navigation with Neon Blue Effect
// ═══════════════════════════════════════════════════════════════════════════════

class FireGlowBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<FireGlowNavItem> items;

  const FireGlowBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
            blurRadius: 12,
            spreadRadius: 0,
          ),
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.1),
            blurRadius: 20,
            spreadRadius: -4,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;

              return FireGlowButton(
                icon: item.icon,
                activeIcon: item.activeIcon,
                label: item.label,
                isSelected: index == currentIndex,
                hasActiveGlow: item.hasActiveGlow,
                onTap: () => onTap(index),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class FireGlowNavItem {
  final IconData icon;
  final IconData? activeIcon;
  final String label;
  final bool hasActiveGlow; // Green glow for active ride

  const FireGlowNavItem({
    required this.icon,
    this.activeIcon,
    required this.label,
    this.hasActiveGlow = false,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// FAB FUTURISTA
// ═══════════════════════════════════════════════════════════════════════════════

class NeonFAB extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color? color;
  final bool mini;

  const NeonFAB({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color,
    this.mini = false,
  });

  @override
  State<NeonFAB> createState() => _NeonFABState();
}

class _NeonFABState extends State<NeonFAB> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fabColor = widget.color ?? AppColors.primary;
    final size = widget.mini ? 48.0 : 60.0;

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      onTap: () {
        HapticService.buttonPress();
        widget.onPressed();
      },
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [fabColor, fabColor.withValues(alpha: 0.8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: fabColor.withValues(alpha: 0.4),
                    blurRadius: 20,
                    spreadRadius: 0,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                widget.icon,
                color: AppColors.background,
                size: widget.mini ? 24 : 28,
              ),
            ),
          );
        },
      ),
    );
  }
}
