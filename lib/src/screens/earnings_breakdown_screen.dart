import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/riverpod_providers.dart';
import '../services/statement_export_service.dart';
import '../utils/app_theme.dart';

/// Uber/Lyft style earnings breakdown screen
class EarningsBreakdownScreen extends ConsumerStatefulWidget {
  final String driverId;
  final DateTime? weekStart;

  const EarningsBreakdownScreen({
    super.key,
    required this.driverId,
    this.weekStart,
  });

  @override
  ConsumerState<EarningsBreakdownScreen> createState() => _EarningsBreakdownScreenState();
}

class _EarningsBreakdownScreenState extends ConsumerState<EarningsBreakdownScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  Map<String, dynamic> _breakdown = {};
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _dailyBreakdown = [];
  List<Map<String, dynamic>> _transactions = [];

  // Current period
  late DateTime _weekStart;
  late DateTime _weekEnd;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _weekStart = widget.weekStart ?? _getWeekStart(DateTime.now());
    _weekEnd = _weekStart.add(const Duration(days: 6));
    _loadData();
  }

  DateTime _getWeekStart(DateTime date) {
    final weekday = date.weekday;
    return DateTime(date.year, date.month, date.day - (weekday - 1));
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final driverService = ref.read(driverServiceProvider);

      // Load breakdown data
      final breakdown = await driverService.getEarningsBreakdown(
        widget.driverId,
        _weekStart,
        _weekEnd,
      );

      // Load recent transactions
      final transactions = await driverService.getRecentEarnings(
        widget.driverId,
        limit: 50,
      );

      setState(() {
        _breakdown = breakdown ?? {};
        _summary = _breakdown['summary'] ?? {};
        _dailyBreakdown = List<Map<String, dynamic>>.from(
          _breakdown['daily_breakdown'] ?? [],
        );
        _transactions = transactions;
        _isLoading = false;
      });
    } catch (e) {
      //Error loading earnings breakdown: $e');
      setState(() => _isLoading = false);
    }
  }

  void _previousWeek() {
    setState(() {
      _weekStart = _weekStart.subtract(const Duration(days: 7));
      _weekEnd = _weekStart.add(const Duration(days: 6));
    });
    _loadData();
  }

  void _nextWeek() {
    final now = DateTime.now();
    if (_weekStart.add(const Duration(days: 7)).isBefore(now)) {
      setState(() {
        _weekStart = _weekStart.add(const Duration(days: 7));
        _weekEnd = _weekStart.add(const Duration(days: 6));
      });
      _loadData();
    }
  }

  Future<void> _downloadStatement() async {
    try {
      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Generating statement...'),
            ],
          ),
          duration: Duration(seconds: 2),
        ),
      );

      // Get driver data from provider
      final driverService = ref.read(driverServiceProvider);
      final driver = await driverService.getDriver(widget.driverId);

      // Generate PDF
      await StatementExportService.instance.generateWeeklyStatement(
        driver: {
          'name': driver?.name ?? 'Driver',
          'phone': driver?.phone ?? '',
          'email': driver?.email ?? '',
        },
        weekStart: _weekStart,
        weekEnd: _weekEnd,
        summary: _summary,
        transactions: _transactions,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating statement: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          // App Bar with total
          _buildSliverAppBar(),

          // Content
          SliverToBoxAdapter(
            child: _isLoading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(50),
                      child: CircularProgressIndicator(color: AppTheme.primary),
                    ),
                  )
                : Column(
                    children: [
                      // Tab bar
                      _buildTabBar(),
                      // Tab content
                      SizedBox(
                        height: MediaQuery.of(context).size.height - 300,
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildSummaryTab(),
                            _buildDailyTab(),
                            _buildTransactionsTab(),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar() {
    final totalEarnings = (_summary['total_earnings'] as num?)?.toDouble() ?? 0;
    final dateFormat = DateFormat('MMM d');

    return SliverAppBar(
      expandedHeight: 220,
      pinned: true,
      backgroundColor: AppTheme.background,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        // Download Statement PDF button
        IconButton(
          icon: const Icon(Icons.picture_as_pdf, color: AppTheme.primary),
          tooltip: 'Download Statement',
          onPressed: _isLoading ? null : _downloadStatement,
        ),
        const SizedBox(width: 8),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppTheme.primary.withValues(alpha: 0.3),
                AppTheme.background,
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
              child: Column(
                children: [
                  // Week selector
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left, color: Colors.white70),
                        onPressed: _previousWeek,
                      ),
                      Text(
                        '${dateFormat.format(_weekStart)} - ${dateFormat.format(_weekEnd)}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.chevron_right,
                          color: _weekStart.add(const Duration(days: 7)).isBefore(DateTime.now())
                              ? Colors.white70
                              : Colors.white24,
                        ),
                        onPressed: _nextWeek,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Total earnings
                  Text(
                    '\$${totalEarnings.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'Total Ganado',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(10),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: AppTheme.textMuted,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        tabs: const [
          Tab(text: 'Resumen'),
          Tab(text: 'Por Día'),
          Tab(text: 'Viajes'),
        ],
      ),
    );
  }

  Widget _buildSummaryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Earnings breakdown
          _buildSection(
            '💰 DESGLOSE DE GANANCIAS',
            [
              _buildRow('Tarifas Base', _summary['base_fares']),
              _buildRow('Por Distancia', _summary['distance_earnings']),
              _buildRow('Por Tiempo', _summary['time_earnings']),
              _buildRow('Surge', _summary['surge_earnings'], color: AppTheme.warning),
              _buildDivider(),
              _buildRow('Tarifa Bruta', _summary['gross_fares'], bold: true),
              _buildRow('Comisión Toro (30%)', _summary['platform_fee'], negative: true),
              _buildDivider(),
              _buildRow('Tarifa Neta', _summary['net_fares'], bold: true, color: AppTheme.success),
            ],
          ),
          const SizedBox(height: 16),

          // Extras
          _buildSection(
            '🎁 EXTRAS',
            [
              _buildRow('Propinas', _summary['tips'], icon: Icons.volunteer_activism),
              _buildRow('Quest Bonos', _summary['quest_bonuses'], icon: Icons.emoji_events),
              _buildRow('Streak Bonos', _summary['streak_bonuses'], icon: Icons.local_fire_department),
              _buildRow('Referidos', _summary['referral_bonuses'], icon: Icons.people),
              _buildRow('Promociones', _summary['promotion_bonuses'], icon: Icons.celebration),
              _buildDivider(),
              _buildRow('Total Extras', _summary['total_bonuses'], bold: true, color: AppTheme.primary),
            ],
          ),
          const SizedBox(height: 16),

          // Deductions
          if ((_summary['total_deductions'] ?? 0) > 0)
            _buildSection(
              '📉 DEDUCCIONES',
              [
                _buildRow('Fees Instant Payout', _summary['instant_payout_fees'], negative: true),
                _buildRow('Otros', _summary['other_deductions'], negative: true),
                _buildDivider(),
                _buildRow('Total Deducciones', _summary['total_deductions'], negative: true, bold: true),
              ],
            ),
          const SizedBox(height: 16),

          // Activity
          _buildSection(
            '📊 TU ACTIVIDAD',
            [
              _buildStatRow('Viajes Completados', '${_summary['total_trips'] ?? 0}', Icons.directions_car),
              _buildStatRow('Horas Online', '${(_summary['total_hours'] ?? 0).toStringAsFixed(1)} hrs', Icons.access_time),
              _buildStatRow('Millas Recorridas', '${(_summary['total_miles'] ?? 0).toStringAsFixed(1)} mi', Icons.straighten),
            ],
          ),
          const SizedBox(height: 16),

          // Averages
          _buildSection(
            '📈 PROMEDIOS',
            [
              _buildStatRow(
                'Por Hora',
                '\$${(_summary['avg_per_hour'] ?? 0).toStringAsFixed(2)}',
                Icons.schedule,
                highlight: true,
              ),
              _buildStatRow(
                'Por Viaje',
                '\$${(_summary['avg_per_trip'] ?? 0).toStringAsFixed(2)}',
                Icons.local_taxi,
              ),
              _buildStatRow(
                'Por Milla',
                '\$${(_summary['avg_per_mile'] ?? 0).toStringAsFixed(2)}',
                Icons.speed,
              ),
              _buildStatRow(
                'Propina Promedio',
                '${(_summary['avg_tip_percent'] ?? 0).toStringAsFixed(0)}%',
                Icons.favorite,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Payout info
          _buildPayoutCard(),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildDailyTab() {
    if (_dailyBreakdown.isEmpty) {
      return const Center(
        child: Text(
          'No hay datos para esta semana',
          style: TextStyle(color: AppTheme.textMuted),
        ),
      );
    }

    // Find best day
    double maxEarnings = 0;
    for (var day in _dailyBreakdown) {
      final earnings = (day['earnings'] as num?)?.toDouble() ?? 0;
      if (earnings > maxEarnings) maxEarnings = earnings;
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _dailyBreakdown.length,
      itemBuilder: (context, index) {
        final day = _dailyBreakdown[index];
        final earnings = (day['earnings'] as num?)?.toDouble() ?? 0;
        final trips = day['trips'] ?? 0;
        final hours = (day['hours'] as num?)?.toDouble() ?? 0;
        final isBestDay = earnings == maxEarnings && maxEarnings > 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(12),
            border: isBestDay
                ? Border.all(color: AppTheme.success, width: 2)
                : null,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // Day info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              day['day'] ?? '',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (isBestDay) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.success.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  '🏆 Mejor día',
                                  style: TextStyle(color: AppTheme.success, fontSize: 10),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          day['date'] ?? '',
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  // Earnings
                  Text(
                    '\$${earnings.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: earnings > 0 ? AppTheme.success : AppTheme.textMuted,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Stats bar
              Row(
                children: [
                  _buildMiniStat(Icons.directions_car, '$trips viajes'),
                  const SizedBox(width: 16),
                  _buildMiniStat(Icons.access_time, '${hours.toStringAsFixed(1)} hrs'),
                  const SizedBox(width: 16),
                  _buildMiniStat(
                    Icons.trending_up,
                    hours > 0 ? '\$${(earnings / hours).toStringAsFixed(2)}/hr' : '-',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: maxEarnings > 0 ? earnings / maxEarnings : 0,
                  backgroundColor: AppTheme.border,
                  valueColor: AlwaysStoppedAnimation(
                    isBestDay ? AppTheme.success : AppTheme.primary,
                  ),
                  minHeight: 4,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTransactionsTab() {
    if (_transactions.isEmpty) {
      return const Center(
        child: Text(
          'No hay transacciones esta semana',
          style: TextStyle(color: AppTheme.textMuted),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _transactions.length,
      itemBuilder: (context, index) {
        final tx = _transactions[index];
        return _buildTransactionItem(tx);
      },
    );
  }

  Widget _buildTransactionItem(Map<String, dynamic> tx) {
    final type = tx['type'] ?? 'ride';
    final earnings = (tx['total_earnings'] as num?)?.toDouble() ?? 0;
    final tip = (tx['tip_amount'] as num?)?.toDouble() ?? 0;
    final earnedAt = DateTime.tryParse(tx['earned_at'] ?? '');

    IconData icon;
    Color color;
    String label;

    switch (type) {
      case 'ride':
        icon = Icons.directions_car;
        color = AppTheme.primary;
        label = 'Viaje';
        break;
      case 'delivery':
        icon = Icons.restaurant;
        color = AppTheme.warning;
        label = 'Delivery';
        break;
      case 'package':
        icon = Icons.inventory_2;
        color = AppTheme.info;
        label = 'Paquete';
        break;
      case 'tip':
        icon = Icons.volunteer_activism;
        color = AppTheme.success;
        label = 'Propina';
        break;
      case 'bonus':
      case 'quest':
        icon = Icons.emoji_events;
        color = AppTheme.warning;
        label = 'Bono';
        break;
      case 'streak':
        icon = Icons.local_fire_department;
        color = Colors.orange;
        label = 'Streak';
        break;
      default:
        icon = Icons.attach_money;
        color = AppTheme.textMuted;
        label = type;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (earnedAt != null)
                  Text(
                    DateFormat('MMM d, h:mm a').format(earnedAt),
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                  ),
              ],
            ),
          ),
          // Earnings
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${earnings.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: AppTheme.success,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              if (tip > 0)
                Text(
                  '+\$${tip.toStringAsFixed(2)} tip',
                  style: const TextStyle(color: AppTheme.primary, fontSize: 11),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              title,
              style: const TextStyle(
                color: AppTheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...children,
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildRow(
    String label,
    dynamic value, {
    bool bold = false,
    bool negative = false,
    Color? color,
    IconData? icon,
  }) {
    final amount = (value as num?)?.toDouble() ?? 0;
    final displayValue = negative ? '-\$${amount.abs().toStringAsFixed(2)}' : '\$${amount.toStringAsFixed(2)}';
    final displayColor = color ?? (negative ? AppTheme.error : AppTheme.textMuted);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: displayColor, size: 16),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: bold ? Colors.white : AppTheme.textMuted,
                fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          Text(
            displayValue,
            style: TextStyle(
              color: bold ? displayColor : displayColor,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              fontSize: bold ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, IconData icon, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (highlight ? AppTheme.success : AppTheme.primary).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: highlight ? AppTheme.success : AppTheme.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: const TextStyle(color: AppTheme.textMuted)),
          ),
          Text(
            value,
            style: TextStyle(
              color: highlight ? AppTheme.success : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: highlight ? 18 : 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(color: AppTheme.border, height: 20, indent: 16, endIndent: 16);
  }

  Widget _buildMiniStat(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppTheme.textMuted, size: 14),
        const SizedBox(width: 4),
        Text(value, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
      ],
    );
  }

  Widget _buildPayoutCard() {
    final payoutAmount = (_summary['net_payout'] as num?)?.toDouble() ?? 0;
    final payoutStatus = _summary['payout_status'] ?? 'pending';

    String statusText;
    IconData statusIcon;

    switch (payoutStatus) {
      case 'paid':
        statusText = 'Pagado';
        statusIcon = Icons.check_circle;
        break;
      case 'processing':
        statusText = 'Procesando';
        statusIcon = Icons.hourglass_empty;
        break;
      default:
        statusText = 'Pendiente';
        statusIcon = Icons.schedule;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primary, AppTheme.info],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              const Text(
                'TU PAYOUT',
                style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(statusText, style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '\$${payoutAmount.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Deposito cada Domingo',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}
