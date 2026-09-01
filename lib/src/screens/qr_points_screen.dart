import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../services/driver_qr_points_service.dart';
import '../providers/driver_provider.dart';
import '../utils/app_colors.dart';
import '../utils/haptic_service.dart';
import '../utils/money_format.dart';

/// Driver QR Points & Commission Screen
/// Shows driver's QR tier and how it reduces platform commission
/// Commission Reduction Model (percentages loaded from pricing_config):
///   US/AZ: Platform 20.4%, Driver 57% | MX/CDMX: Platform 25%, Driver 75%
///   Each tier reduces platform by 1%, driver gains the difference
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
  int? _previewTier;

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
      backgroundColor: Colors.transparent,
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
                        _buildCommissionTab(service),
                        _buildRankingTab(service),
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
          Tab(text: 'qr_tab_commission'.tr()),
          Tab(text: 'qr_tab_ranking'.tr()),
          Tab(text: 'qr_tab_tips'.tr()),
        ],
      ),
    );
  }

  // ==================== COMMISSION TAB ====================
  Widget _buildCommissionTab(DriverQRPointsService service) {
    final level = service.currentLevel;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildCommissionCard(service, level),
          const SizedBox(height: 20),
          _buildTierCard(service),
          const SizedBox(height: 20),
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

  /// Donut chart showing commission breakdown
  Widget _buildCommissionCard(
    DriverQRPointsService service,
    DriverQRPointsLevel level,
  ) {
    // If previewing a tier, use that tier's percentages; otherwise use current
    final isPreview = _previewTier != null;
    final tier = isPreview ? _previewTier! : service.currentTier;
    final driverPercent = isPreview
        ? service.driverPercentForTier(tier)
        : service.effectiveDriverPercent;
    final platformPercent = isPreview
        ? service.platformPercentForTier(tier)
        : service.effectivePlatformPercent;
    final insurancePercent = service.insurancePercent;
    final ivaPercent = service.ivaPercent;
    final reduction = isPreview
        ? service.reductionForTier(tier)
        : service.currentCommissionReduction;

    // Build pie sections — ONLY Driver vs TORO so the green slice dominates.
    // Insurance/IVA are fixed costs shown separately below.
    final sections = <PieChartSectionData>[
      PieChartSectionData(
        value: driverPercent,
        color: const Color(0xFF00FF66),
        radius: 32,
        showTitle: false,
      ),
      PieChartSectionData(
        value: platformPercent.clamp(0.5, 100), // min visible sliver
        color: const Color(0xFF1E88E5),
        radius: 24,
        showTitle: false,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1E88E5).withValues(alpha: 0.25),
            const Color(0xFF00BCD4).withValues(alpha: 0.15),
            AppColors.card,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF1E88E5).withValues(alpha: 0.4),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E88E5).withValues(alpha: 0.2),
            blurRadius: 20,
            spreadRadius: -5,
          ),
        ],
      ),
      child: Column(
        children: [
          // Donut chart with center text
          SizedBox(
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sections: sections,
                    centerSpaceRadius: 55,
                    sectionsSpace: 2,
                    startDegreeOffset: -90,
                  ),
                  swapAnimationDuration: const Duration(milliseconds: 500),
                  swapAnimationCurve: Curves.easeInOut,
                ),
                // Center text
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Tier badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        gradient: tier > 0
                            ? const LinearGradient(colors: [
                                Color(0xFF1E88E5),
                                Color(0xFF00BCD4)
                              ])
                            : null,
                        color: tier == 0 ? AppColors.surface : null,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        tier > 0 ? 'TIER $tier' : 'BASE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color:
                              tier > 0 ? Colors.white : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Large driver percentage
                    Text(
                      '${driverPercent.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00FF66),
                        height: 1.1,
                      ),
                    ),
                    Text(
                      'qr_your_earnings'.tr(),
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Legend row — Driver vs TORO only
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              _buildLegendItem(
                const Color(0xFF00FF66),
                'Driver',
                '${driverPercent.toStringAsFixed(0)}%',
              ),
              _buildLegendItem(
                const Color(0xFF1E88E5),
                'TORO',
                '${platformPercent.toStringAsFixed(0)}%',
                badge: reduction > 0
                    ? '-${reduction.toStringAsFixed(0)}%'
                    : null,
              ),
            ],
          ),
          // Fixed costs row (Insurance + IVA) — shown as subtle info
          if (insurancePercent > 0 || ivaPercent > 0) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (insurancePercent > 0)
                  Text(
                    '${'qr_insurance_segment'.tr()} ${insurancePercent.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary.withValues(alpha: 0.7),
                    ),
                  ),
                if (insurancePercent > 0 && ivaPercent > 0)
                  Text(
                    '  •  ',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary.withValues(alpha: 0.4),
                    ),
                  ),
                if (ivaPercent > 0)
                  Text(
                    'IVA ${ivaPercent.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary.withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
          ],
          if (isPreview) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1E88E5).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF1E88E5).withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                'qr_preview_tier'.tr(namedArgs: {
                  'tier': tier > 0 ? 'Tier $tier' : 'Base',
                }),
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF1E88E5),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
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

  /// Legend item for the donut chart
  Widget _buildLegendItem(
    Color color,
    String label,
    String value, {
    String? badge,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$label $value',
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (badge != null) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF00FF66).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badge,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Color(0xFF00FF66),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Horizontal tier selector with tappable circles
  Widget _buildTierCard(DriverQRPointsService service) {
    final currentTier = service.currentTier;
    final nextTierQrs = service.qrsForNextTier;

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
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.workspace_premium_rounded,
                  color: AppColors.star, size: 24),
              const SizedBox(width: 10),
              Text(
                'qr_commission_tiers'.tr(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Tier circles row: Base (0) + Tier 1-5
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(6, (i) {
              final tierNum = i; // 0 = Base, 1-5 = Tiers
              final isCurrent = tierNum == currentTier;
              final isReached = tierNum <= currentTier;
              final isSelected = _previewTier == tierNum;

              return GestureDetector(
                onTap: () {
                  HapticService.lightImpact();
                  setState(() {
                    if (_previewTier == tierNum) {
                      _previewTier = null; // deselect
                    } else {
                      _previewTier = tierNum;
                    }
                  });
                },
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      width: isSelected ? 48 : 42,
                      height: isSelected ? 48 : 42,
                      decoration: BoxDecoration(
                        gradient: isCurrent
                            ? const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF1E88E5),
                                  Color(0xFF00BCD4),
                                ],
                              )
                            : null,
                        color: !isCurrent && isReached
                            ? const Color(0xFF00FF66)
                            : !isCurrent && !isReached
                                ? Colors.transparent
                                : null,
                        shape: BoxShape.circle,
                        border: !isReached && !isCurrent
                            ? Border.all(
                                color: isSelected
                                    ? const Color(0xFF1E88E5)
                                    : AppColors.border.withValues(alpha: 0.5),
                                width: isSelected ? 2 : 1.5,
                              )
                            : isSelected
                                ? Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  )
                                : null,
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF1E88E5)
                                      .withValues(alpha: 0.4),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          tierNum == 0 ? 'B' : '$tierNum',
                          style: TextStyle(
                            fontSize: isSelected ? 18 : 16,
                            fontWeight: FontWeight.bold,
                            color: isReached || isCurrent
                                ? Colors.white
                                : isSelected
                                    ? const Color(0xFF1E88E5)
                                    : AppColors.textSecondary
                                        .withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tierNum == 0 ? 'Base' : 'T$tierNum',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight:
                            isCurrent ? FontWeight.bold : FontWeight.w500,
                        color: isCurrent
                            ? const Color(0xFF1E88E5)
                            : isReached
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          // Next tier info text
          if (currentTier < 5 && nextTierQrs > 0)
            Text(
              'qr_next_tier'.tr(namedArgs: {'count': '$nextTierQrs'}),
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            )
          else if (currentTier >= 5)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.star_rounded, color: AppColors.star, size: 18),
                const SizedBox(width: 6),
                Text(
                  'qr_max_tier'.tr(),
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.star,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
        ],
      ),
    ).animate(delay: 150.ms).fadeIn().slideY(begin: 0.1, end: 0);
  }

  Widget _buildProgressBar(DriverQRPointsService service, DriverQRPointsLevel level) {
    final maxLevel = service.qrMaxLevel;
    final progress = maxLevel > 0 ? level.level / maxLevel : 0.0;

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
                '${level.qrsAccepted} QRs',
                style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
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
                          colors: [Color(0xFF1E88E5), Color(0xFF00BCD4)],
                        ),
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1E88E5).withValues(alpha: 0.4),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  )
                  .animate(delay: 300.ms)
                  .slideX(begin: -1, end: 0, duration: 800.ms, curve: Curves.easeOutCubic),
            ],
          ),
          const SizedBox(height: 12),
          // Tier markers
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMarker(0, level.level),
              for (final bp in service.tierBreakpoints)
                _buildMarker(bp.max, level.level),
            ],
          ),
        ],
      ),
    ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.1, end: 0);
  }

  Widget _buildMarker(int value, int currentLevel) {
    final isActive = value <= currentLevel;
    return Column(
      children: [
        Container(
          width: 3,
          height: 8,
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF1E88E5)
                : AppColors.textSecondary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$value',
          style: TextStyle(
            fontSize: 11,
            color: isActive ? const Color(0xFF1E88E5) : AppColors.textSecondary,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow(DriverQRPointsService service) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            Icons.qr_code_scanner_rounded,
            '${service.currentLevel.qrsAccepted}',
            'QRs',
            const Color(0xFF1E88E5),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            Icons.trending_down_rounded,
            '${service.effectivePlatformPercent.toStringAsFixed(0)}%',
            'qr.commission'.tr(),
            const Color(0xFF00BCD4),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            Icons.trending_up_rounded,
            '${service.effectiveDriverPercent.toStringAsFixed(0)}%',
            'qr_your_earnings'.tr(),
            const Color(0xFF00FF66),
          ),
        ),
      ],
    ).animate(delay: 300.ms).fadeIn();
  }

  Widget _buildStatCard(IconData icon, String value, String label, Color color) {
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
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorks(DriverQRPointsService service) {
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
              Icon(Icons.lightbulb_outline_rounded, color: AppColors.star, size: 22),
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
          _buildStep(3, 'qr_step_commission_title'.tr(), 'qr_step_commission_desc'.tr()),
          _buildStep(4, 'qr_step_tier_title'.tr(), 'qr_step_tier_desc'.tr()),
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
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF1E88E5), Color(0xFF00BCD4)]),
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
                  style: const TextStyle(
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

  // ==================== RANKING TAB ====================
  Widget _buildRankingTab(DriverQRPointsService service) {
    final ranking = service.stateRanking;
    final myRank = service.myStateRank;
    final stateCode = service.stateCode;

    return RefreshIndicator(
      onRefresh: () => service.refresh(),
      color: const Color(0xFF1E88E5),
      child: ranking.isEmpty
          ? _buildEmptyRanking(stateCode)
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.all(16),
              itemCount: ranking.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildRankingHeader(service, myRank, stateCode);
                }
                return _buildRankItem(ranking[index - 1], index - 1);
              },
            ),
    );
  }

  Widget _buildEmptyRanking(String stateCode) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.leaderboard_rounded,
            size: 64,
            color: AppColors.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'qr_ranking_empty'.tr(),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'qr_ranking_empty_desc'.tr(namedArgs: {'state': stateCode}),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildRankingHeader(DriverQRPointsService service, int myRank, String stateCode) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1E88E5).withValues(alpha: 0.25),
            const Color(0xFF00BCD4).withValues(alpha: 0.15),
            AppColors.card,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1E88E5).withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.leaderboard_rounded, color: Color(0xFF1E88E5), size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ranking $stateCode',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'qr_ranking_subtitle'.tr(),
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (myRank > 0) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E88E5), Color(0xFF00BCD4)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'qr_your_rank'.tr(),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '#$myRank',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.1, end: 0);
  }

  Widget _buildRankItem(StateRankEntry entry, int index) {
    final isTop3 = entry.rank <= 3;
    final rankColors = [
      const Color(0xFFFFD700), // Gold
      const Color(0xFFC0C0C0), // Silver
      const Color(0xFFCD7F32), // Bronze
    ];
    final rankColor = isTop3 ? rankColors[entry.rank - 1] : AppColors.textSecondary;
    final rankIcons = ['🥇', '🥈', '🥉'];

    return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: entry.isMe
                ? const Color(0xFF1E88E5).withValues(alpha: 0.15)
                : AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: entry.isMe
                ? Border.all(color: const Color(0xFF1E88E5).withValues(alpha: 0.5), width: 2)
                : Border.all(color: AppColors.border.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              // Rank number
              SizedBox(
                width: 40,
                child: isTop3
                    ? Text(
                        rankIcons[entry.rank - 1],
                        style: const TextStyle(fontSize: 24),
                        textAlign: TextAlign.center,
                      )
                    : Text(
                        '#${entry.rank}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: entry.isMe ? const Color(0xFF1E88E5) : AppColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
              ),
              const SizedBox(width: 12),
              // Driver info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            entry.isMe ? '${entry.driverName} (${'qr_you'.tr()})' : entry.driverName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: entry.isMe ? FontWeight.bold : FontWeight.w500,
                              color: entry.isMe ? const Color(0xFF1E88E5) : AppColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'Tier ${entry.tier}',
                      style: TextStyle(
                        fontSize: 11,
                        color: entry.tier >= 4
                            ? const Color(0xFF00FF66)
                            : AppColors.textSecondary,
                        fontWeight: entry.tier >= 4 ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              // QR Level
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: (isTop3 ? rankColor : const Color(0xFF1E88E5)).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${entry.qrLevel} QRs',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isTop3 ? rankColor : const Color(0xFF1E88E5),
                  ),
                ),
              ),
            ],
          ),
        )
        .animate(delay: Duration(milliseconds: 30 * index))
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
            style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
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
                  formatMoney(service.allTimeTipsTotal, country: context.read<DriverProvider>().driver?.countryCode ?? 'US'),
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
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00FF66).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${tip.pointsSpent} pts',
                            style: const TextStyle(
                              fontSize: 11,
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
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '+${formatMoney(tip.tipAmount, country: context.read<DriverProvider>().driver?.countryCode ?? 'US')}',
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
