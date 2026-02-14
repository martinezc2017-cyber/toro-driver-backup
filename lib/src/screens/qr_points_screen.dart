import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../services/driver_qr_points_service.dart';
import '../providers/driver_provider.dart';
import '../utils/app_colors.dart';
import '../utils/haptic_service.dart';

/// Driver QR Points & Tips Screen
/// Shows driver's QR points and tips received from riders
/// Adapts to tier mode (MX) or linear mode (US)
class QRPointsScreen extends StatefulWidget {
  const QRPointsScreen({super.key});

  @override
  State<QRPointsScreen> createState() => _QRPointsScreenState();
}

class _QRPointsScreenState extends State<QRPointsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late DriverQRPointsService _qrService;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _qrService = DriverQRPointsService();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final driverId = context.read<DriverProvider>().driver?.id;
      if (driverId != null) {
        _qrService.initialize(driverId);
        _initialized = true;
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _qrService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            Expanded(
              child: ChangeNotifierProvider.value(
                value: _qrService,
                child: Consumer<DriverQRPointsService>(
                  builder: (context, service, child) {
                    if (service.isLoading) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      );
                    }

                    return TabBarView(
                      controller: _tabController,
                      children: [
                        _buildPointsTab(service),
                        _buildDonationsTab(service),
                        _buildTipsTab(service),
                      ],
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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(
            color: AppColors.border.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              HapticService.lightImpact();
              Navigator.pop(context);
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.border.withValues(alpha: 0.5),
                ),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: AppColors.textPrimary,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: AppColors.successGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.success.withValues(alpha: 0.3),
                  blurRadius: 10,
                ),
              ],
            ),
            child: const Icon(
              Icons.qr_code_2_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'qr_title'.tr(),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0);
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: AppColors.successGradient,
          borderRadius: BorderRadius.circular(12),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        tabs: [
          Tab(text: 'qr_tab_points'.tr()),
          Tab(text: 'qr_tab_donations'.tr()),
          Tab(text: 'qr_tab_tips'.tr()),
        ],
      ),
    );
  }

  Widget _buildPointsTab(DriverQRPointsService service) {
    final level = service.currentLevel;
    final baseCommission = 50.0;
    final totalCommission = service.getTotalCommissionPercent(baseCommission);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildLevelCard(service, level, totalCommission, baseCommission),
          const SizedBox(height: 20),
          if (service.qrUseTiers) ...[
            _buildTierCard(service),
            const SizedBox(height: 20),
          ],
          _buildProgressBar(service, level),
          const SizedBox(height: 20),
          _buildStatsRow(service),
          const SizedBox(height: 20),
          _buildHowItWorks(service),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildLevelCard(
    DriverQRPointsService service,
    DriverQRPointsLevel level,
    double totalCommission,
    double baseCommission,
  ) {
    final maxLevel = service.qrMaxLevel;
    final bonusPercent = service.qrUseTiers
        ? service.currentTierBonusPercent
        : level.bonusPercent;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF00FF66).withValues(alpha: 0.2),
            const Color(0xFF00CC66).withValues(alpha: 0.1),
            AppColors.card,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF00FF66).withValues(alpha: 0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00FF66).withValues(alpha: 0.2),
            blurRadius: 20,
            spreadRadius: -5,
          ),
        ],
      ),
      child: Column(
        children: [
          // Level Number
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${level.level}',
                style: const TextStyle(
                  fontSize: 72,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00FF66),
                  height: 1,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '/$maxLevel',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'qr_points_label'.tr(),
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),
          // Commission Display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Column(
                  children: [
                    Text(
                      '${baseCommission.toInt()}%',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'qr_base'.tr(),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                const Text(
                  '+',
                  style: TextStyle(
                    fontSize: 24,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  children: [
                    Text(
                      '+${bonusPercent.toStringAsFixed(bonusPercent == bonusPercent.roundToDouble() ? 0 : 1)}%',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00FF66),
                      ),
                    ),
                    Text(
                      'qr_bonus'.tr(),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                const Text(
                  '=',
                  style: TextStyle(
                    fontSize: 24,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  children: [
                    Text(
                      '${(baseCommission + bonusPercent).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.success,
                      ),
                    ),
                    Text(
                      'qr_total'.tr(),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Weekly Reset Timer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.warning.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.timer_outlined, color: AppColors.warning, size: 16),
                const SizedBox(width: 8),
                Text(
                  '${'qr_reset'.tr()}: ${_formatDuration(level.timeUntilReset)}',
                  style: TextStyle(
                    color: AppColors.warning,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate(delay: 100.ms).fadeIn().scale(begin: const Offset(0.95, 0.95));
  }

  /// Tier card - only shown in tier mode (MX)
  Widget _buildTierCard(DriverQRPointsService service) {
    final tier = service.currentTier;
    final bonusPercent = service.currentTierBonusPercent;
    final nextTierQrs = service.qrsForNextTier;
    final currentQrs = service.currentLevel.level;
    final breakpoints = service.tierBreakpoints;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.15),
            AppColors.primary.withValues(alpha: 0.05),
            AppColors.card,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tier header
          Row(
            children: [
              Icon(Icons.workspace_premium_rounded, color: AppColors.star, size: 24),
              const SizedBox(width: 10),
              Text(
                'qr_current_tier'.tr(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: tier > 0
                      ? AppColors.successGradient
                      : null,
                  color: tier == 0 ? AppColors.surface : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  tier > 0
                      ? 'qr_tier_label'.tr(namedArgs: {'tier': '$tier'})
                      : 'qr_tier_no_tier'.tr(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: tier > 0 ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          if (tier > 0) ...[
            const SizedBox(height: 8),
            Text(
              'qr_tier_bonus_info'.tr(namedArgs: {
                'percent': bonusPercent.toStringAsFixed(
                  bonusPercent == bonusPercent.roundToDouble() ? 0 : 1,
                ),
              }),
              style: TextStyle(
                fontSize: 13,
                color: AppColors.success,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (nextTierQrs > 0) ...[
            const SizedBox(height: 4),
            Text(
              'qr_next_tier'.tr(namedArgs: {'count': '$nextTierQrs'}),
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ] else if (tier == 5) ...[
            const SizedBox(height: 4),
            Text(
              'qr_max_tier'.tr(),
              style: TextStyle(
                fontSize: 12,
                color: AppColors.star,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Tier breakdown table
          ...List.generate(breakpoints.length, (i) {
            final (max, bonus) = breakpoints[i];
            final tierNum = i + 1;
            final prevMax = i == 0 ? 0 : breakpoints[i - 1].$1;
            final isCurrentTier = tier == tierNum;
            final isReached = currentQrs >= (prevMax + 1);

            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isCurrentTier
                    ? const Color(0xFF00FF66).withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: isCurrentTier
                    ? Border.all(
                        color: const Color(0xFF00FF66).withValues(alpha: 0.3),
                      )
                    : null,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 50,
                    child: Text(
                      'Tier $tierNum',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isCurrentTier ? FontWeight.bold : FontWeight.w500,
                        color: isCurrentTier
                            ? const Color(0xFF00FF66)
                            : isReached
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${prevMax + 1}-$max QRs',
                      style: TextStyle(
                        fontSize: 12,
                        color: isCurrentTier
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    '+${bonus.toStringAsFixed(bonus == bonus.roundToDouble() ? 0 : 1)}%',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isCurrentTier
                          ? const Color(0xFF00FF66)
                          : isReached
                              ? AppColors.success
                              : AppColors.textSecondary,
                    ),
                  ),
                  if (isCurrentTier) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_back_rounded,
                      size: 14,
                      color: const Color(0xFF00FF66),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    ).animate(delay: 150.ms).fadeIn().slideY(begin: 0.1, end: 0);
  }

  Widget _buildProgressBar(DriverQRPointsService service, DriverQRPointsLevel level) {
    final maxLevel = service.qrMaxLevel;
    final progress = maxLevel > 0 ? level.level / maxLevel : 0.0;

    // For tier mode, show tier markers; for linear, show numeric markers
    final markerCount = service.qrUseTiers ? 6 : (maxLevel + 1).clamp(2, 16);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'qr_weekly_progress'.tr(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                '${level.qrsAccepted} ${'qr_referrals'.tr()}',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Progress bar
          Stack(
            children: [
              Container(
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              FractionallySizedBox(
                    widthFactor: progress.clamp(0, 1).toDouble(),
                    child: Container(
                      height: 12,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00FF66), Color(0xFF00CC99)],
                        ),
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF00FF66,
                            ).withValues(alpha: 0.4),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  )
                  .animate(delay: 300.ms)
                  .slideX(
                    begin: -1,
                    end: 0,
                    duration: 800.ms,
                    curve: Curves.easeOutCubic,
                  ),
            ],
          ),
          const SizedBox(height: 12),
          // Level markers
          if (service.qrUseTiers) ...[
            // Tier mode: show tier breakpoints
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildMarker(0, level.level, true),
                for (final (max, _) in service.tierBreakpoints)
                  _buildMarker(max, level.level, true),
              ],
            ),
          ] else ...[
            // Linear mode: show numbered markers
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(markerCount, (i) {
                final markerValue = maxLevel <= 15
                    ? i
                    : (i * maxLevel / (markerCount - 1)).round();
                final isActive = markerValue <= level.level;
                final isMultiple = i == 0 || i == markerCount - 1 || i % 5 == 0;
                return Column(
                  children: [
                    Container(
                      width: isMultiple ? 3 : 2,
                      height: isMultiple ? 8 : 4,
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFF00FF66)
                            : AppColors.textSecondary.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    if (isMultiple) ...[
                      const SizedBox(height: 4),
                      Text(
                        '$markerValue',
                        style: TextStyle(
                          fontSize: 9,
                          color: isActive
                              ? const Color(0xFF00FF66)
                              : AppColors.textSecondary,
                          fontWeight: isActive
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ],
                );
              }),
            ),
          ],
        ],
      ),
    ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.1, end: 0);
  }

  Widget _buildMarker(int value, int currentLevel, bool showLabel) {
    final isActive = value <= currentLevel;
    return Column(
      children: [
        Container(
          width: 3,
          height: 8,
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF00FF66)
                : AppColors.textSecondary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        if (showLabel) ...[
          const SizedBox(height: 4),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 9,
              color: isActive ? const Color(0xFF00FF66) : AppColors.textSecondary,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatsRow(DriverQRPointsService service) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            Icons.people_rounded,
            '${service.currentLevel.qrsAccepted}',
            'qr_referrals_stat'.tr(),
            AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            Icons.card_giftcard_rounded,
            '\$${service.weeklyDonationsTotal.toStringAsFixed(0)}',
            'qr_donations_this_week'.tr(),
            AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            Icons.attach_money_rounded,
            '\$${service.currentLevel.totalBonusEarned.toStringAsFixed(0)}',
            'qr_bonus_earned'.tr(),
            AppColors.success,
          ),
        ),
      ],
    ).animate(delay: 300.ms).fadeIn();
  }

  Widget _buildStatCard(
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorks(DriverQRPointsService service) {
    final isTierMode = service.qrUseTiers;
    final maxLevel = service.qrMaxLevel;
    final breakpoints = service.tierBreakpoints;
    final minBonus = breakpoints.isNotEmpty ? breakpoints.first.$2 : 2.0;
    final maxBonus = breakpoints.isNotEmpty ? breakpoints.last.$2 : 10.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_outline_rounded,
                color: AppColors.star,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                'qr_how_it_works'.tr(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildStep(1, 'qr_step1_title'.tr(), 'qr_step1_desc'.tr()),
          _buildStep(2, 'qr_step2_title'.tr(), 'qr_step2_desc'.tr()),
          if (isTierMode) ...[
            _buildStep(3, 'qr_step3_title_tier'.tr(), 'qr_step3_desc_tier'.tr()),
            _buildStep(
              4,
              'qr_step4_title_tier'.tr(),
              'qr_step4_desc_tier'.tr(namedArgs: {
                'min': minBonus.toStringAsFixed(0),
                'max': maxBonus.toStringAsFixed(0),
              }),
            ),
          ] else ...[
            _buildStep(3, 'qr_step3_title_linear'.tr(), 'qr_step3_desc_linear'.tr()),
            _buildStep(
              4,
              'qr_step4_title_linear'.tr(namedArgs: {'max': '$maxLevel'}),
              'qr_step4_desc_linear'.tr(namedArgs: {'max': '$maxLevel'}),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.warning.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.warning, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'qr_reset_info'.tr(),
                    style: TextStyle(fontSize: 12, color: AppColors.warning),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate(delay: 400.ms).fadeIn().slideY(begin: 0.1, end: 0);
  }

  Widget _buildStep(int num, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: AppColors.successGradient,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$num',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  desc,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== DONATIONS TAB ====================
  Widget _buildDonationsTab(DriverQRPointsService service) {
    final donations = service.donationsReceived;

    return RefreshIndicator(
      onRefresh: () => service.refresh(),
      color: AppColors.primary,
      child: donations.isEmpty
          ? _buildEmptyDonations()
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.all(16),
              itemCount: donations.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildDonationsSummary(service);
                }
                return _buildDonationItem(donations[index - 1], index - 1);
              },
            ),
    );
  }

  Widget _buildEmptyDonations() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.card_giftcard_rounded,
            size: 64,
            color: AppColors.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'qr_donations_empty'.tr(),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'qr_donations_empty_desc'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildDonationsSummary(DriverQRPointsService service) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.2),
            AppColors.primary.withValues(alpha: 0.1),
            AppColors.card,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'qr_donations_total'.tr(),
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '\$${service.allTimeDonationsTotal.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.card_giftcard_rounded,
                  color: AppColors.primary,
                  size: 28,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today_rounded, color: AppColors.success, size: 14),
                const SizedBox(width: 8),
                Text(
                  '${'qr_donations_this_week'.tr()}: \$${service.weeklyDonationsTotal.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: AppColors.success,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.1, end: 0);
  }

  Widget _buildDonationItem(QRDonationReceived donation, int index) {
    final timeAgo = _formatTimeAgo(donation.createdAt);

    return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.card_giftcard_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'qr_donation_from'.tr(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00FF66).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'qr_donation_level'.tr(namedArgs: {'level': '${donation.riderQrLevel}'}),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF00FF66),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${donation.riderName ?? 'Rider'} · $timeAgo',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '+\$${donation.donationAmount.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        )
        .animate(delay: Duration(milliseconds: 50 * index))
        .fadeIn()
        .slideX(begin: 0.1, end: 0);
  }

  // ==================== TIPS TAB ====================
  Widget _buildTipsTab(DriverQRPointsService service) {
    final tips = service.tipsReceived;

    return RefreshIndicator(
      onRefresh: () => service.refresh(),
      color: AppColors.primary,
      child: tips.isEmpty
          ? _buildEmptyTips()
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.all(16),
              itemCount: tips.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildTipsSummary(service);
                }
                return _buildTipItem(tips[index - 1], index - 1);
              },
            ),
    );
  }

  Widget _buildEmptyTips() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.volunteer_activism_rounded,
            size: 64,
            color: AppColors.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'qr_no_tips'.tr(),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'qr_no_tips_desc'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildTipsSummary(DriverQRPointsService service) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.star.withValues(alpha: 0.2),
            AppColors.star.withValues(alpha: 0.1),
            AppColors.card,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.star.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'qr_total_tips'.tr(),
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '\$${service.allTimeTipsTotal.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: AppColors.star,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.star.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.volunteer_activism_rounded,
              color: AppColors.star,
              size: 28,
            ),
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.1, end: 0);
  }

  Widget _buildTipItem(QRTipReceived tip, int index) {
    final timeAgo = _formatTimeAgo(tip.createdAt);

    return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.star.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.star.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.volunteer_activism_rounded,
                  color: AppColors.star,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'qr_tip_label'.tr(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF00FF66,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${tip.pointsSpent} pts',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF00FF66),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      timeAgo,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '+\$${tip.tipAmount.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.star,
                ),
              ),
            ],
          ),
        )
        .animate(delay: Duration(milliseconds: 50 * index))
        .fadeIn()
        .slideX(begin: 0.1, end: 0);
  }

  String _formatDuration(Duration duration) {
    if (duration.isNegative) return '0m';

    final days = duration.inDays;
    final hours = duration.inHours % 24;

    if (days > 0) {
      return '${days}d ${hours}h';
    } else if (hours > 0) {
      final minutes = duration.inMinutes % 60;
      return '${hours}h ${minutes}m';
    } else {
      return '${duration.inMinutes}m';
    }
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 60) {
      return 'min_ago'.tr(args: ['${difference.inMinutes}']);
    } else if (difference.inHours < 24) {
      return 'hours_ago'.tr(args: ['${difference.inHours}']);
    } else if (difference.inDays == 1) {
      return 'yesterday'.tr();
    } else if (difference.inDays < 7) {
      return 'days_ago'.tr(args: ['${difference.inDays}']);
    } else {
      return DateFormat('dd/MM/yyyy').format(dateTime);
    }
  }
}
