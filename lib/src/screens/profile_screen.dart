import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../core/logging/app_logger.dart';
import '../providers/driver_provider.dart';
import '../providers/auth_provider.dart';
import '../models/driver_model.dart';
import '../utils/app_colors.dart';
import '../utils/haptic_service.dart';
import '../widgets/futuristic_widgets.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  late AnimationController _sparkleController;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    AppLogger.log('OPEN -> ProfileScreen');
    _sparkleController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _sparkleController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  String _getRatingLabel(double rating) {
    if (rating >= 4.8) return 'rating_excellent'.tr();
    if (rating >= 4.5) return 'rating_very_good'.tr();
    if (rating >= 4.0) return 'rating_good'.tr();
    if (rating >= 3.5) return 'rating_regular'.tr();
    return 'rating_improve'.tr();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Consumer<DriverProvider>(
          builder: (context, driverProvider, child) {
            final driver = driverProvider.driver;
            final isLoading = driverProvider.isLoading;

            if (isLoading && driver == null) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }

            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
              child: Column(
                children: [
                  _buildAvatar(driver),
                  const SizedBox(height: 16),
                  _buildNameSection(driver),
                  const SizedBox(height: 10),
                  _buildRatingBadge(
                    rating: driver?.rating,
                    totalRides: driver?.totalRides ?? 0,
                  ),
                  const SizedBox(height: 24),
                  _buildStatsCard(driver),
                  const SizedBox(height: 20),
                  _buildMenuCard(),
                  const SizedBox(height: 80),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildAvatar(DriverModel? driver) {
    final driverName = driver?.fullName ?? 'driver'.tr();
    final isOnline = driver?.isOnline ?? false;
    final profileImageUrl = driver?.profileImageUrl;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer glow ring
            Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.2 + (_pulseController.value * 0.1)),
                    AppColors.purple.withValues(alpha: 0.2 + (_pulseController.value * 0.1)),
                  ],
                ),
              ),
            ),
            // Main avatar container
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.cyberGradient,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.purple.withValues(alpha: 0.4),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              padding: const EdgeInsets.all(4),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.card,
                  border: Border.all(
                    color: AppColors.border,
                    width: 2,
                  ),
                  image: profileImageUrl != null
                      ? DecorationImage(
                          image: NetworkImage(profileImageUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: profileImageUrl == null
                    ? Center(
                        child: Text(
                          driverName.isNotEmpty ? driverName[0].toUpperCase() : 'D',
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
            // Camera button
            Positioned(
              bottom: 8,
              right: 8,
              child: GestureDetector(
                onTap: () {
                  HapticService.lightImpact();
                  AppLogger.log('PROFILE -> Edit photo tapped');
                  // TODO: Implement image picker
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.background, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 18),
                ),
              ),
            ),
            // Online indicator
            Positioned(
              top: 10,
              right: 15,
              child: GlowingStatusIndicator(isActive: isOnline, size: 14),
            ),
          ],
        );
      },
    ).animate().fadeIn(delay: 100.ms).scale(begin: const Offset(0.8, 0.8));
  }

  Widget _buildNameSection(DriverModel? driver) {
    final driverName = driver?.fullName ?? 'driver'.tr();
    final isVerified = driver?.isVerified ?? false;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              driverName,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            if (isVerified) ...[
              const SizedBox(width: 8),
              Icon(Icons.verified_rounded, color: AppColors.primary, size: 24),
            ],
          ],
        ),
      ],
    ).animate().fadeIn(delay: 200.ms);
  }

  Widget _buildRatingBadge({double? rating, required int totalRides}) {
    // Si no hay viajes completados, mostrar "Sin calificaciones"
    final hasRatings = totalRides > 0 && rating != null;

    if (!hasRatings) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.border.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.star_outline_rounded,
              color: AppColors.textSecondary,
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              'no_ratings'.tr(),
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.2, end: 0);
    }

    // Con calificaciones
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.star,
            AppColors.star.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.star.withValues(alpha: 0.4),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, color: Colors.white, size: 22),
          const SizedBox(width: 8),
          Text(
            rating.toStringAsFixed(2),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _getRatingLabel(rating),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.2, end: 0);
  }

  Widget _buildStatsCard(DriverModel? driver) {
    final totalRides = driver?.totalRides ?? 0;
    final rating = driver?.rating;
    final stateRank = driver?.stateRank;
    final usaRank = driver?.usaRank;
    final driverState = driver?.state ?? '';

    // Determinar si hay calificaciones
    final hasRatings = totalRides > 0 && rating != null;
    final ratingValue = hasRatings ? rating.toStringAsFixed(1) : '-';
    final ratingLabel = hasRatings ? 'rating'.tr() : 'no_ratings'.tr();

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      animationDelay: 400.ms,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Icon(Icons.analytics_rounded, color: AppColors.primary, size: 16),
                const SizedBox(width: 6),
                Text(
                  'statistics'.tr(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(Icons.star_rounded, ratingValue, ratingLabel, AppColors.star),
              _buildStatDivider(),
              _buildStatItem(
                Icons.leaderboard_rounded,
                stateRank != null ? '#$stateRank' : '-',
                driverState.isNotEmpty ? driverState : 'state_rank'.tr(),
                AppColors.success,
              ),
              _buildStatDivider(),
              _buildStatItemWithFlag(usaRank != null ? '#$usaRank' : '-', 'usa_rank'.tr(), AppColors.warning),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(
      width: 1,
      height: 40,
      color: AppColors.border.withValues(alpha: 0.5),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  // USA Rank with flag emoji instead of icon
  Widget _buildStatItemWithFlag(String value, String label, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: const Text(
            '🇺🇸',
            style: TextStyle(fontSize: 18),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildMenuCard() {
    // All items use neon blue glow except logout (red)
    const neonBlue = Color(0xFF0066FF);
    const neonRed = Color(0xFFEF4444);

    final menuItems = [
      {'icon': Icons.account_circle_rounded, 'label': 'account'.tr(), 'route': '/account', 'color': neonBlue},
      {'icon': Icons.settings_rounded, 'label': 'settings'.tr(), 'route': '/settings', 'color': neonBlue},
      {'icon': Icons.history_rounded, 'label': 'history'.tr(), 'route': '/rides', 'color': neonBlue},
      {'icon': Icons.account_balance_wallet_rounded, 'label': 'nav_earnings'.tr(), 'route': '/earnings', 'color': neonBlue},
      {'icon': Icons.account_balance_rounded, 'label': 'bank_account'.tr(), 'route': '/bank-account', 'color': neonBlue},
      {'icon': Icons.directions_car_rounded, 'label': 'vehicle'.tr(), 'route': '/vehicle', 'color': neonBlue},
      {'icon': Icons.support_agent_rounded, 'label': 'support'.tr(), 'route': '/support', 'color': neonBlue},
      {'icon': Icons.gavel_rounded, 'label': 'legal'.tr(), 'route': '/legal', 'color': neonBlue},
      {'icon': Icons.description_rounded, 'label': 'documents'.tr(), 'route': '/documents', 'color': neonBlue},
      {'icon': Icons.leaderboard_rounded, 'label': 'ranking'.tr(), 'route': '/ranking', 'color': neonBlue},
      {'icon': Icons.card_giftcard_rounded, 'label': 'refer'.tr(), 'route': '/refer', 'color': neonBlue},
      {'icon': Icons.language_rounded, 'label': 'language'.tr(), 'route': '/language', 'color': neonBlue},
      {'icon': Icons.logout_rounded, 'label': 'logout'.tr(), 'route': '/logout', 'color': neonRed},
    ];

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      animationDelay: 500.ms,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Icon(Icons.menu_rounded, color: AppColors.primary, size: 16),
                const SizedBox(width: 6),
                Text(
                  'menu'.tr(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary, size: 16),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: menuItems.asMap().entries.map((entry) {
              final item = entry.value;
              final index = entry.key;
              return _buildMenuItem(
                icon: item['icon'] as IconData,
                label: item['label'] as String,
                route: item['route'] as String,
                color: item['color'] as Color,
                index: index,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required String route,
    required Color color,
    required int index,
  }) {
    return _ProfileMenuButton(
      icon: icon,
      label: label,
      route: route,
      color: color,
      index: index,
      onTap: () async {
        HapticService.lightImpact();
        AppLogger.log('PROFILE -> Navigate to $route');

        if (route == '/logout') {
          final confirmed = await _showLogoutConfirmation();
          if (confirmed == true && mounted) {
            await context.read<AuthProvider>().logout();
            if (mounted) {
              Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
            }
          }
        } else {
          Navigator.pushNamed(context, route);
        }
      },
    );
  }

  Future<bool?> _showLogoutConfirmation() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'logout_confirm'.tr(),
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'logout_message'.tr(),
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('cancel'.tr(), style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('exit'.tr(), style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROFILE MENU BUTTON - Only glows on press (FireGlow style)
// ═══════════════════════════════════════════════════════════════════════════════

class _ProfileMenuButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final String route;
  final Color color;
  final int index;
  final VoidCallback onTap;

  const _ProfileMenuButton({
    required this.icon,
    required this.label,
    required this.route,
    required this.color,
    required this.index,
    required this.onTap,
  });

  @override
  State<_ProfileMenuButton> createState() => _ProfileMenuButtonState();
}

class _ProfileMenuButtonState extends State<_ProfileMenuButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 75,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: _isPressed ? AppColors.cardHover : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _isPressed
                ? widget.color.withValues(alpha: 0.6)
                : AppColors.border.withValues(alpha: 0.3),
            width: _isPressed ? 2 : 1,
          ),
          boxShadow: _isPressed
              ? [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.3),
                    blurRadius: 15,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: _isPressed
                    ? widget.color.withValues(alpha: 0.2)
                    : widget.color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _isPressed
                      ? widget.color.withValues(alpha: 0.5)
                      : widget.color.withValues(alpha: 0.2),
                  width: 1.5,
                ),
                boxShadow: _isPressed
                    ? [
                        BoxShadow(
                          color: widget.color.withValues(alpha: 0.4),
                          blurRadius: 12,
                          spreadRadius: 0,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                widget.icon,
                color: _isPressed ? widget.color : widget.color.withValues(alpha: 0.8),
                size: 16,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: _isPressed ? FontWeight.w700 : FontWeight.w500,
                color: _isPressed ? widget.color : AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    )
        .animate(delay: Duration(milliseconds: 50 * widget.index))
        .fadeIn()
        .scale(begin: const Offset(0.9, 0.9));
  }
}
