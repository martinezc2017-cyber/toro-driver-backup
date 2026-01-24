import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/earnings_provider.dart';
import '../providers/driver_provider.dart';
import '../utils/app_colors.dart';

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  DateTime _selectedWeekStart = _getWeekStart(DateTime.now());

  static DateTime _getWeekStart(DateTime date) {
    return DateTime(date.year, date.month, date.day)
        .subtract(Duration(days: date.weekday - 1));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  void _loadData() async {
    final driverId = context.read<DriverProvider>().driver?.id;
    if (driverId != null) {
      context.read<EarningsProvider>().initialize(driverId);
      context.read<EarningsProvider>().loadTransactions(driverId);
    }
  }

  void _previousWeek() => setState(() => _selectedWeekStart = _selectedWeekStart.subtract(const Duration(days: 7)));

  void _nextWeek() {
    final nextWeek = _selectedWeekStart.add(const Duration(days: 7));
    if (!nextWeek.isAfter(_getWeekStart(DateTime.now()))) {
      setState(() => _selectedWeekStart = nextWeek);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _previousWeek,
              child: const Icon(Icons.chevron_left, size: 20),
            ),
            const SizedBox(width: 4),
            Text(
              '${DateFormat('MMM d').format(_selectedWeekStart)} - ${DateFormat('d').format(_selectedWeekStart.add(const Duration(days: 6)))}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: _nextWeek,
              child: Icon(Icons.chevron_right, size: 20, color: _selectedWeekStart == _getWeekStart(DateTime.now()) ? AppColors.textSecondary : null),
            ),
          ],
        ),
      ),
      body: Consumer<EarningsProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.summary == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final summary = provider.summary;
          if (summary == null) return const Center(child: Text('No data'));

          // ═══════════════════════════════════════════════════════════════
          // CALCULAR NET FARE Y TOTAL
          // ═══════════════════════════════════════════════════════════════
          // CAMBIO (2026-01-14): weekEarnings ahora incluye TODO (bonuses + tips)
          // total = weekEarnings (ya tiene todo incluido)
          // netFare = total - tips - todos los bonuses
          // ═══════════════════════════════════════════════════════════════
          final total = summary.weekEarnings; // Ya incluye TODOS los bonuses y tips
          final tips = summary.weekTips;
          // Net Fare = Total - Tips - Bonuses
          final netFare = total - tips - summary.weekQRBoost - summary.weekPeakHoursBonus -
                          summary.weekPromotions - summary.weekExtraBonus - summary.weekDamageFee;

          return RefreshIndicator(
            onRefresh: () async {
              final id = context.read<DriverProvider>().driver?.id;
              if (id != null) await provider.refresh(id);
            },
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                // Total
                Center(
                  child: Text(
                    '\$${total.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 24),

                // Chart
                SizedBox(
                  height: 135,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: provider.weeklyBreakdown.map((d) {
                      final max = provider.weeklyBreakdown.fold<double>(1, (m, e) => e.amount > m ? e.amount : m);
                      final pct = d.amount / max;
                      final isToday = d.date.day == DateTime.now().day && d.date.month == DateTime.now().month;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (d.amount > 0) Text('\$${d.amount.toInt()}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                              const SizedBox(height: 4),
                              Container(
                                height: (85 * pct).clamp(4.0, 85.0),
                                decoration: BoxDecoration(
                                  color: isToday ? AppColors.primary : AppColors.primary.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                ['M', 'T', 'W', 'T', 'F', 'S', 'S'][d.date.weekday - 1],
                                style: TextStyle(fontSize: 10, fontWeight: isToday ? FontWeight.bold : FontWeight.normal, color: isToday ? AppColors.primary : AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 32),

                // Breakdown
                const Text('Breakdown', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                _row('Net Fare', netFare),
                if (summary.weekQRBoost > 0) _row('QR Boost', summary.weekQRBoost),
                if (summary.weekPeakHoursBonus > 0) _row('Peak Hours', summary.weekPeakHoursBonus),
                if (summary.weekPromotions > 0) _row('Promotions', summary.weekPromotions),
                if (summary.weekExtraBonus > 0) _row('Extra Bonus', summary.weekExtraBonus),
                if (summary.weekDamageFee > 0) _row('Damage Fee', summary.weekDamageFee),
                _row('Tips', tips),
                const Divider(height: 24),
                _row('Total', total, bold: true),
                const SizedBox(height: 32),

                // Stats row at bottom (without Points)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stat('Online Hours', _fmtTime(summary.weekOnlineMinutes)),
                    _stat('Total Trips', '${summary.weekRides}'),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _row(String label, double amount, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text('\$${amount.toStringAsFixed(2)}', style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }

  String _fmtTime(double min) {
    final h = (min / 60).floor();
    final m = (min % 60).floor();
    return h > 0 ? '${h}h${m}m' : '${m}m';
  }
}
