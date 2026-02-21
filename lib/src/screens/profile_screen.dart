import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
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
  late AnimationController _menuNeonController;
  bool _uploadingPhoto = false;

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

    _menuNeonController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _sparkleController.dispose();
    _pulseController.dispose();
    _menuNeonController.dispose();
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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
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
                  _buildCommunityCard(driver),
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

    return Stack(
      alignment: Alignment.center,
      children: [
        // Outer rotating cyan ring (matches Rider)
        AnimatedBuilder(
          animation: _sparkleController,
          builder: (context, child) {
            return Transform.rotate(
              angle: _sparkleController.value * 2 * math.pi,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.transparent, width: 3),
                  gradient: SweepGradient(
                    colors: [
                      AppColors.neonCyan.withValues(alpha: 0.0),
                      AppColors.neonCyan,
                      AppColors.primaryCyan,
                      AppColors.neonCyan.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            );
          },
        ),

        // Static outer ring with cyan tint
        Container(
          width: 150,
          height: 150,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.neonCyan.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
        ),

        // Pulsing cyan glow ring
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final scale = 1.0 + (_pulseController.value * 0.03);
            final opacity = 0.3 + (_pulseController.value * 0.2);
            return Transform.scale(
              scale: scale,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.neonCyan.withValues(alpha: opacity),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.neonCyan.withValues(alpha: opacity * 0.5),
                      blurRadius: 10,
                      spreadRadius: -2,
                    ),
                  ],
                ),
              ),
            );
          },
        ),

        // Cyan gradient ring + avatar
        Container(
          width: 130,
          height: 130,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.neonCyan,
                AppColors.primaryCyan,
                AppColors.primary,
              ],
            ),
          ),
          padding: const EdgeInsets.all(3),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.card,
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
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w300,
                        color: AppColors.primaryBright,
                        letterSpacing: -1,
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
            onTap: _uploadingPhoto ? null : () {
              HapticService.lightImpact();
              AppLogger.log('PROFILE -> Edit photo tapped');
              _uploadProfilePhoto();
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.card,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.neonCyan.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: _uploadingPhoto
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.neonCyan),
                      ),
                    )
                  : const Icon(Icons.camera_alt_outlined, color: AppColors.neonCyan, size: 16),
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
    final displayRating = rating ?? 5.0;
    final isNew = totalRides == 0;
    final label = isNew ? 'NEW' : _getRatingLabel(displayRating);

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
          const Icon(Icons.star_rounded, color: AppColors.textPrimary, size: 22),
          const SizedBox(width: 8),
          Text(
            displayRating.toStringAsFixed(2),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.textPrimary.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
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

    // Always show rating (5.0 default for new drivers)
    final displayRating = rating ?? 5.0;
    final ratingValue = displayRating.toStringAsFixed(1);
    final ratingLabel = totalRides > 0 ? 'rating'.tr() : 'rating'.tr();

    return AnimatedBuilder(
      animation: _sparkleController,
      builder: (context, child) {
        final value = _sparkleController.value;
        final beginX = -3.0 + (value * 6.0);
        final endX = -1.0 + (value * 6.0);

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment(beginX, -1),
              end: Alignment(endX, 1),
              colors: [
                AppColors.neonCyan,
                AppColors.primaryCyan,
                AppColors.primaryBright,
                AppColors.primaryPale,
                AppColors.primaryCyan,
                AppColors.neonCyan,
              ],
              tileMode: TileMode.repeated,
            ),
          ),
          child: Container(
            margin: const EdgeInsets.all(2),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.analytics_rounded, color: AppColors.textSecondary, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'statistics'.tr(),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _buildStatItem(Icons.star_rounded, ratingValue, ratingLabel, AppColors.star)),
                    _buildStatDivider(),
                    Expanded(
                      child: _buildStatItem(
                        Icons.leaderboard_rounded,
                        stateRank != null ? '#$stateRank' : '-',
                        driverState.isNotEmpty ? driverState : 'state_rank'.tr(),
                        AppColors.success,
                      ),
                    ),
                    _buildStatDivider(),
                    Expanded(child: _buildStatItemWithFlag(usaRank != null ? '#$usaRank' : '-', 'usa_rank'.tr(), AppColors.warning)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ).animate().fadeIn(delay: 400.ms);
  }

  Widget _buildStatDivider() {
    return Container(
      width: 1,
      height: 50,
      color: AppColors.border,
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Icon(icon, color: AppColors.textSecondary, size: 22),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  // USA Rank with flag icon
  Widget _buildStatItemWithFlag(String value, String label, Color color) {
    return Column(
      children: [
        Icon(Icons.flag_outlined, color: AppColors.textSecondary, size: 22),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildCommunityCard(DriverModel? driver) {
    final isMexico = driver?.countryCode == 'MX';
    final groupUrl = isMexico
        ? 'https://www.facebook.com/groups/891201387249906'
        : 'https://www.facebook.com/groups/788083457055317';
    final groupLabel = isMexico ? 'community_facebook_mx'.tr() : 'community_facebook'.tr();
    final groupSubtitle = isMexico ? 'TORO Comunidad México' : 'TORO Community USA';

    return AnimatedBuilder(
      animation: _sparkleController,
      builder: (context, child) {
        final value = _sparkleController.value;
        final beginX = -3.0 + (value * 6.0);
        final endX = -1.0 + (value * 6.0);

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment(beginX, -1),
              end: Alignment(endX, 1),
              colors: [
                AppColors.neonCyan,
                AppColors.primaryCyan,
                AppColors.primaryBright,
                AppColors.primaryPale,
                AppColors.primaryCyan,
                AppColors.neonCyan,
              ],
              tileMode: TileMode.repeated,
            ),
          ),
          child: Container(
            margin: const EdgeInsets.all(2),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.people_rounded, color: AppColors.textSecondary, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'community_title'.tr(),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.facebook.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.facebook, color: AppColors.facebook, size: 12),
                          const SizedBox(width: 4),
                          Text(
                            'Facebook',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: AppColors.facebook.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Official page
                _buildSocialRow(
                  icon: Icons.facebook,
                  label: 'TORO Rideshare',
                  subtitle: 'community_facebook'.tr(),
                  url: 'https://www.facebook.com/TORORIDESHARE',
                ),
                const SizedBox(height: 8),
                // Country group
                _buildSocialRow(
                  icon: Icons.groups_rounded,
                  label: groupLabel,
                  subtitle: groupSubtitle,
                  url: groupUrl,
                ),
              ],
            ),
          ),
        );
      },
    ).animate().fadeIn(duration: 450.ms);
  }

  Widget _buildSocialRow({
    required IconData icon,
    required String label,
    required String subtitle,
    required String url,
  }) {
    return GestureDetector(
      onTap: () {
        HapticService.lightImpact();
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.facebook.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.facebook.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.facebook.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.facebook, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.facebook,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'community_join'.tr(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard() {
    // All items use neon blue glow except logout (red)
    const neonBlue = AppColors.primary;
    const neonRed = AppColors.error;

    final menuItems = [
      {'icon': Icons.badge_rounded, 'label': 'cred_title'.tr(), 'route': '/driver-credential', 'color': neonBlue},
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
      // Mexico specific options
      {'icon': Icons.flag_rounded, 'label': 'mx_documents_title'.tr(), 'route': '/mexico-documents', 'color': neonBlue},
      {'icon': Icons.account_balance_rounded, 'label': 'mx_tax_title'.tr(), 'route': '/mexico-tax', 'color': neonBlue},
      {'icon': Icons.receipt_long_rounded, 'label': 'mx_cfdi_title'.tr(), 'route': '/mexico-invoices', 'color': neonBlue},
      {'icon': Icons.logout_rounded, 'label': 'logout'.tr(), 'route': '/logout', 'color': neonRed},
    ];

    return AnimatedBuilder(
      animation: _sparkleController,
      builder: (context, child) {
        final value = _sparkleController.value;
        final beginX = -3.0 + (value * 6.0);
        final endX = -1.0 + (value * 6.0);

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment(beginX, -1),
              end: Alignment(endX, 1),
              colors: [
                AppColors.neonCyan,
                AppColors.primaryCyan,
                AppColors.primaryBright,
                AppColors.primaryPale,
                AppColors.primaryCyan,
                AppColors.neonCyan,
              ],
              tileMode: TileMode.repeated,
            ),
          ),
          child: Container(
            margin: const EdgeInsets.all(2),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.grid_view_outlined, color: AppColors.textSecondary, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      'menu'.tr(),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary, size: 20),
                  ],
                ),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.85,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
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
          ),
        );
      },
    ).animate().fadeIn(delay: 500.ms);
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
      neonController: _menuNeonController,
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

  /// Upload profile photo
  Future<void> _uploadProfilePhoto() async {
    try {
      // Pick image from gallery
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (pickedFile == null) return;
      if (!mounted) return;

      setState(() => _uploadingPhoto = true);

      // Upload using DriverProvider (updates UI automatically)
      // Use bytes instead of File for web compatibility
      final driverProvider = Provider.of<DriverProvider>(context, listen: false);
      final imageBytes = await pickedFile.readAsBytes();
      final imageUrl = await driverProvider.uploadProfileImage(imageBytes);

      if (mounted) {
        setState(() => _uploadingPhoto = false);

        if (imageUrl != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('profile_photo_updated'.tr()),
              backgroundColor: AppColors.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('profile_photo_error'.tr()),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      AppLogger.error('Error uploading profile photo: $e');
      if (mounted) {
        setState(() => _uploadingPhoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${'profile_photo_error'.tr()}: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
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
  final AnimationController neonController;
  final VoidCallback onTap;

  const _ProfileMenuButton({
    required this.icon,
    required this.label,
    required this.route,
    required this.color,
    required this.index,
    required this.neonController,
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
      child: AnimatedBuilder(
        animation: widget.neonController,
        builder: (context, child) {
          final neonValue = widget.neonController.value;
          final beginX = -3.0 + (neonValue * 8.0);
          final endX = -1.0 + (neonValue * 8.0);

          return AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                begin: Alignment(beginX, -1),
                end: Alignment(endX, 1),
                colors: [
                  _isPressed ? Colors.white : AppColors.neonCyan,
                  _isPressed ? AppColors.neonCyan : AppColors.primaryCyan,
                  AppColors.primaryBright,
                  AppColors.primaryLight,
                  _isPressed ? AppColors.neonCyan : AppColors.primaryCyan,
                  _isPressed ? Colors.white : AppColors.neonCyan,
                ],
                tileMode: TileMode.repeated,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.neonCyan.withValues(alpha: _isPressed ? 0.6 : 0.25),
                  blurRadius: _isPressed ? 12 : 6,
                  spreadRadius: _isPressed ? 1 : -3,
                ),
              ],
            ),
            child: Container(
              margin: const EdgeInsets.all(1.5),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              decoration: BoxDecoration(
                color: _isPressed ? AppColors.cardHover : AppColors.card,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: _isPressed ? AppColors.neonCyan : AppColors.border,
                  width: _isPressed ? 1 : 0.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isPressed
                          ? AppColors.neonCyan.withValues(alpha: 0.2)
                          : widget.color.withValues(alpha: 0.1),
                      border: Border.all(
                        color: _isPressed ? AppColors.neonCyan : AppColors.border,
                        width: _isPressed ? 1.5 : 0.5,
                      ),
                    ),
                    child: Icon(
                      widget.icon,
                      color: _isPressed ? AppColors.neonCyan : widget.color.withValues(alpha: 0.8),
                      size: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: _isPressed ? FontWeight.w700 : FontWeight.w500,
                      color: _isPressed ? AppColors.neonCyan : AppColors.textSecondary,
                      letterSpacing: 0.2,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    )
        .animate(delay: Duration(milliseconds: 50 * widget.index))
        .fadeIn()
        .scale(begin: const Offset(0.9, 0.9));
  }
}
