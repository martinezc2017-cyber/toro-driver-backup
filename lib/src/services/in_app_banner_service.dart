import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../utils/haptic_service.dart';

/// Global in-app notification banner that slides from top.
/// Works on ALL screens via Navigator overlay.
class InAppBannerService {
  InAppBannerService._();
  static final InAppBannerService _instance = InAppBannerService._();
  static InAppBannerService get instance => _instance;

  /// Global navigator key - must be set in MaterialApp
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  OverlayEntry? _currentEntry;
  Timer? _autoDismissTimer;

  /// Show a notification banner that slides from top
  void show({
    required String title,
    required String body,
    String? type,
    Map<String, dynamic>? data,
    VoidCallback? onTap,
    Duration duration = const Duration(seconds: 4),
  }) {
    // Dismiss previous banner if showing
    dismiss();

    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;

    _currentEntry = OverlayEntry(
      builder: (context) => _BannerWidget(
        title: title,
        body: body,
        type: type,
        onTap: () {
          dismiss();
          onTap?.call();
        },
        onDismiss: dismiss,
      ),
    );

    overlay.insert(_currentEntry!);
    HapticService.lightImpact();

    // Auto-dismiss
    _autoDismissTimer = Timer(duration, dismiss);
  }

  /// Dismiss current banner
  void dismiss() {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;
    _currentEntry?.remove();
    _currentEntry = null;
  }
}

class _BannerWidget extends StatefulWidget {
  final String title;
  final String body;
  final String? type;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _BannerWidget({
    required this.title,
    required this.body,
    this.type,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_BannerWidget> createState() => _BannerWidgetState();
}

class _BannerWidgetState extends State<_BannerWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _animateOut() async {
    await _controller.reverse();
    widget.onDismiss();
  }

  IconData _iconForType(String? type) {
    switch (type) {
      case 'tourism':
      case 'bid_request':
        return Icons.directions_bus;
      case 'ride_request':
        return Icons.directions_car;
      case 'message':
      case 'chat':
        return Icons.message;
      case 'earning':
      case 'payment':
        return Icons.attach_money;
      case 'bid_counter_offer':
        return Icons.price_change;
      case 'join_request_new':
        return Icons.person_add;
      case 'join_request_accepted':
      case 'join_request_rejected':
        return Icons.person_outline;
      case 'review_submitted':
        return Icons.star;
      case 'abuse_report_update':
        return Icons.warning;
      default:
        return Icons.notifications;
    }
  }

  Color _colorForType(String? type) {
    switch (type) {
      case 'tourism':
      case 'bid_request':
        return AppColors.primaryCyan;
      case 'ride_request':
        return AppColors.primary;
      case 'message':
      case 'chat':
        return AppColors.success;
      case 'earning':
      case 'payment':
        return AppColors.gold;
      case 'bid_counter_offer':
        return AppColors.warning;
      case 'join_request_new':
        return AppColors.success;
      case 'join_request_accepted':
        return AppColors.success;
      case 'join_request_rejected':
        return AppColors.error;
      case 'review_submitted':
        return AppColors.gold;
      case 'abuse_report_update':
        return AppColors.error;
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final accentColor = _colorForType(widget.type);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: GestureDetector(
            onTap: widget.onTap,
            onVerticalDragEnd: (details) {
              // Swipe up to dismiss
              if (details.velocity.pixelsPerSecond.dy < -100) {
                _animateOut();
              }
            },
            child: Container(
              margin: EdgeInsets.only(
                top: topPadding + 8,
                left: 12,
                right: 12,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.3),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.15),
                    blurRadius: 15,
                    spreadRadius: -2,
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Icon
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _iconForType(widget.type),
                      color: accentColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.body,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Small pill indicator
                  Container(
                    width: 4,
                    height: 32,
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
