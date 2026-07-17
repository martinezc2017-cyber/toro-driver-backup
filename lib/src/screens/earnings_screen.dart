import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as riverpod;
import 'package:easy_localization/easy_localization.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/earnings_provider.dart';
import '../providers/driver_provider.dart';
import '../providers/cash_account_provider.dart';
import '../utils/app_colors.dart';
import '../utils/money_format.dart';
import '../utils/money_logger.dart';
import '../services/driver_qr_points_service.dart';
import '../services/stripe_connect_service.dart';
import 'qr_points_screen.dart';
import 'cash_out_screen.dart';

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  DateTime _selectedWeekStart = _getWeekStart(DateTime.now());
  DriverBalance? _stripeBalance;
  Map<String, dynamic>? _openPayout;

  static DateTime _getWeekStart(DateTime date) {
    return DateTime(date.year, date.month, date.day)
        .subtract(Duration(days: date.weekday - 1));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    final driver = context.read<DriverProvider>().driver;
    if (driver != null) {
      context.read<EarningsProvider>().initialize(driver.id);
      context.read<EarningsProvider>().loadTransactions(driver.id);
      context.read<CashAccountProvider>().initialize(driver.id);
      // CANONICAL: Stripe balance = lo que TORO le va a depositar al driver.
      // Available = ya disponible para retiro. Pending = en hold 2-7 días.
      final provider = (driver.countryCode.toUpperCase() == 'MX') ? 'mx' : 'us';
      final bal = await StripeConnectService.instance
          .getBalance(driver.id, provider: provider);
      final openPayout = await StripeConnectService.instance.getOpenPayout(driver.id);
      if (mounted) {
        setState(() {
          _stripeBalance = bal;
          _openPayout = openPayout;
        });
      }
    }
  }

  void _previousWeek() => setState(() => _selectedWeekStart = _selectedWeekStart.subtract(const Duration(days: 7)));

  void _nextWeek() {
    final nextWeek = _selectedWeekStart.add(const Duration(days: 7));
    if (!nextWeek.isAfter(_getWeekStart(DateTime.now()))) {
      setState(() => _selectedWeekStart = nextWeek);
    }
  }

  /// Calculate next Sunday (cutoff date for cash deposits)
  DateTime _getNextCutoff() {
    final now = DateTime.now();
    final daysUntilSunday = DateTime.sunday - now.weekday;
    if (daysUntilSunday <= 0) {
      return DateTime(now.year, now.month, now.day).add(Duration(days: daysUntilSunday + 7));
    }
    return DateTime(now.year, now.month, now.day).add(Duration(days: daysUntilSunday));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
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

          final countryCode = context.read<DriverProvider>().driver?.countryCode ?? 'US';
          final total = summary.weekEarnings;
          final tips = summary.weekTips;
          final netFare = total - tips - summary.weekQRBoost - summary.weekPeakHoursBonus -
                          summary.weekPromotions - summary.weekExtraBonus - summary.weekDamageFee;

          // Audit: log what this screen renders so it can be matched vs admin/rider/vendor.
          MoneyLogger.snapshot('driver_earnings', {
            'WEEK_EARNINGS': total,
            'TIPS': tips,
            'NET_FARE': netFare,
            'STRIPE_AVAIL': (_stripeBalance?.availableCents ?? 0) / 100,
            'STRIPE_PENDING': (_stripeBalance?.pendingCents ?? 0) / 100,
          }, context: {'country': countryCode, 'week': _selectedWeekStart.toIso8601String()});

          return RefreshIndicator(
            onRefresh: () async {
              final id = context.read<DriverProvider>().driver?.id;
              if (id != null) {
                await provider.refresh(id);
                await context.read<CashAccountProvider>().refresh();
                await _loadData();
              }
            },
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                // Total ganado esta semana
                Center(
                  child: Column(
                    children: [
                      Text(
                        formatMoney(total, country: countryCode),
                        style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Ganado esta semana',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // CANONICAL: Balance Stripe Connect del driver.
                // Available = listo para retirar AHORA.
                // Pending = cobrado pero en hold de Stripe (2-7 días).
                if (_stripeBalance != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.account_balance, size: 14, color: AppColors.success),
                                  SizedBox(width: 6),
                                  Text('Disponible Stripe',
                                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                formatMoney(_stripeBalance!.availableCents / 100, country: countryCode),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.success,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 36, color: AppColors.divider),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.schedule, size: 14, color: AppColors.warning),
                                  SizedBox(width: 6),
                                  Text('Pendiente',
                                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                formatMoney(_stripeBalance!.pendingCents / 100, country: countryCode),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.warning,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_openPayout != null) ...[
                    _buildOpenPayoutNotice(countryCode),
                    const SizedBox(height: 10),
                  ],
                  // RETIRAR — abre el flujo de cash-out (saldo, banco/tarjeta).
                  // Si el onboarding de Stripe no está completo, esa pantalla
                  // guía a terminarlo; aquí solo conectamos la entrada.
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _openPayout == null ? () async {
                        final id = context.read<DriverProvider>().driver?.id;
                        if (id == null) return;
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            // CashOutScreen usa riverpod (ref) y la app NO tiene
                            // ProviderScope global -> lo envolvemos aquí para que
                            // no truene al abrirlo.
                            builder: (_) => riverpod.ProviderScope(
                              child: CashOutScreen(driverId: id),
                            ),
                          ),
                        );
                        // Al volver del retiro, recargar para mostrar el saldo real
                        // (el servidor ya bajó drivers.available_balance).
                        if (mounted) _loadData();
                      } : null,
                      icon: const Icon(Icons.account_balance_wallet, size: 18),
                      label: const Text('Retirar a mi banco'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

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

                // Stats row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    if (countryCode != 'MX') _stat('Online Hours', _fmtTime(summary.weekOnlineMinutes)),
                    _stat('Total Trips', '${summary.weekRides}'),
                  ],
                ),
                const SizedBox(height: 32),

                // ═══════════════════════════════════════════════════════════
                // QR TIER BANNER
                // ═══════════════════════════════════════════════════════════
                _buildQRTierBanner(context),
                const SizedBox(height: 24),

                // ═══════════════════════════════════════════════════════════
                // CASH CONTROL — Balance de Efectivo
                // ═══════════════════════════════════════════════════════════
                _buildCashControlSection(),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CASH CONTROL SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildOpenPayoutNotice(String countryCode) {
    final amount = (_openPayout?['amount'] as num?)?.toDouble() ?? 0;
    final status = (_openPayout?['status'] ?? 'processing').toString();
    final stripeId = (_openPayout?['stripe_payout_id'] ?? '').toString();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule, size: 20, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Retiro en proceso',
                  style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatMoney(amount, country: countryCode)} · $status${stripeId.isNotEmpty ? ' · ${stripeId.substring(0, 8)}...' : ''}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQRTierBanner(BuildContext context) {
    final driver = context.read<DriverProvider>().driver;
    if (driver == null) return const SizedBox.shrink();

    final qrService = DriverQRPointsService();
    final tier = qrService.currentTier;
    final driverPercent = qrService.effectiveDriverPercent;
    final toroPercent = qrService.effectivePlatformPercent;

    const tierColors = [
      Color(0xFF9E9E9E), // Tier 0 - grey
      Color(0xFF795548), // Tier 1 - bronze
      Color(0xFF9E9E9E), // Tier 2 - silver
      Color(0xFFFFB300), // Tier 3 - gold
      Color(0xFF1E88E5), // Tier 4 - diamond blue
      Color(0xFF00FF66), // Tier 5 - neon green
    ];
    final color = tierColors[tier.clamp(0, 5)];

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const QRPointsScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.15),
              Colors.black.withValues(alpha: 0.3),
            ],
          ),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.2),
                border: Border.all(color: color, width: 1.5),
              ),
              child: Center(
                child: Text(
                  '$tier',
                  style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'QR Tier $tier — Tú llevas ${driverPercent.toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'TORO cobra ${toroPercent.toStringAsFixed(0)}% · Sube de tier para ganar más',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildCashControlSection() {
    final countryCode = context.read<DriverProvider>().driver?.countryCode ?? 'US';
    return Consumer<CashAccountProvider>(
      builder: (context, cashProvider, _) {
        if (cashProvider.status == CashAccountStatus.loading) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }

        // Show section even without a cash account record (default $0 state)

        final cashOwed = cashProvider.cashOwed;
        final threshold = cashProvider.autoSuspendThreshold;
        final isSuspended = cashProvider.isSuspended || cashProvider.isBlocked;
        final isNearThreshold = cashOwed >= threshold * 0.8;
        final totalCashRides = cashProvider.totalCashRides;
        final byType = cashProvider.owedByType;
        final cutoff = _getNextCutoff();
        final cutoffStr = DateFormat('EEEE d MMM').format(cutoff);

        // Border color based on status
        final borderColor = isSuspended
            ? AppColors.error
            : isNearThreshold
                ? AppColors.warning
                : AppColors.border;

        return Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: borderColor,
              width: isSuspended ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isSuspended
                      ? AppColors.error.withValues(alpha: 0.1)
                      : isNearThreshold
                          ? AppColors.warning.withValues(alpha: 0.08)
                          : null,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSuspended ? Icons.block : Icons.account_balance_wallet,
                      color: isSuspended ? AppColors.error : AppColors.warning,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isSuspended ? 'CUENTA SUSPENDIDA' : 'BALANCE EFECTIVO',
                      style: TextStyle(
                        color: isSuspended ? AppColors.error : AppColors.warning,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (isSuspended ? AppColors.error : AppColors.warning).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        formatMoney(cashOwed, country: countryCode),
                        style: TextStyle(
                          color: isSuspended ? AppColors.error : AppColors.warning,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Cutoff date
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 13, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text('Fecha de corte: ', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    Text(cutoffStr, style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Cash rides + Debes a TORO
              _cashRow('Viajes en Efectivo', '$totalCashRides', Icons.local_taxi, AppColors.textPrimary),
              _cashRow('DEBES A TORO', formatMoney(cashOwed, country: countryCode), Icons.payments, cashOwed > 0 ? AppColors.warning : AppColors.success),

              // Breakdown by type
              if (byType.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                  child: Text('Desglose por tipo:', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ),
                for (final entry in byType.entries)
                  _cashRow(
                    _sourceTypeLabel(entry.key),
                    formatMoney(entry.value, country: countryCode),
                    _sourceTypeIcon(entry.key),
                    AppColors.textPrimary,
                  ),
              ],

              // Threshold progress bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: threshold > 0 ? (cashOwed / threshold).clamp(0.0, 1.0) : 0,
                          backgroundColor: AppColors.border,
                          valueColor: AlwaysStoppedAnimation(
                            cashOwed >= threshold ? AppColors.error : AppColors.warning,
                          ),
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Limite: \$${threshold.toStringAsFixed(0)}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),

              // Suspension warning
              if (isSuspended)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Tu cuenta esta suspendida. Deposita para reactivar.',
                            style: TextStyle(color: AppColors.error, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // PAGAR AHORA button (main action)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: cashOwed > 0 ? () => _showPayNowDialog(cashOwed) : null,
                    icon: const Icon(Icons.payment, size: 18),
                    label: Text(cashOwed > 0 ? 'Pagar Ahora' : 'Sin saldo pendiente', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.card,
                      disabledForegroundColor: AppColors.textSecondary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ),

              // Contact Support button
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _contactSupport,
                    icon: const Icon(Icons.headset_mic, size: 14),
                    label: const Text('Contactar Soporte', style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _cashRow(String label, String value, IconData icon, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12))),
          Text(value, style: TextStyle(color: valueColor, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  String _sourceTypeLabel(String type) {
    switch (type) {
      case 'ride': return 'Viajes';
      case 'carpool': return 'Carpool';
      case 'package': return 'Paquetes';
      case 'tourism': return 'Turismo';
      default: return type;
    }
  }

  IconData _sourceTypeIcon(String type) {
    switch (type) {
      case 'ride': return Icons.local_taxi;
      case 'carpool': return Icons.people;
      case 'package': return Icons.inventory_2;
      case 'tourism': return Icons.tour;
      default: return Icons.receipt;
    }
  }

  void _showPayNowDialog(double amountOwed) {
    final countryCode = context.read<DriverProvider>().driver?.countryCode ?? 'US';
    // Default = TARJETA (la única opción instantánea que SÍ funciona). SPEI y
    // Depósito están "pendiente de configurar" (sin cuenta) -> caer ahí por
    // defecto hacía ver el flujo roto.
    String selectedMethod = 'card';
    bool _submitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.payment, color: AppColors.success, size: 22),
              SizedBox(width: 8),
              Text('Pagar Ahora', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Amount
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    const Text('Monto a pagar', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(formatMoney(amountOwed, country: countryCode), style: const TextStyle(color: AppColors.warning, fontSize: 28, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Payment method
              const Text('Metodo de pago:', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 8),
              _payMethodOption(ctx, setDialogState, selectedMethod, 'card', Icons.credit_card, 'Tarjeta de crédito/débito (instantáneo)', (v) => selectedMethod = v),
              const SizedBox(height: 6),
              _payMethodOption(ctx, setDialogState, selectedMethod, 'transfer', Icons.account_balance, 'Transferencia Bancaria (SPEI)', (v) => selectedMethod = v),
              const SizedBox(height: 6),
              _payMethodOption(ctx, setDialogState, selectedMethod, 'deposit', Icons.storefront, 'Deposito en Sucursal', (v) => selectedMethod = v),
              const SizedBox(height: 16),

              // Bank details
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Datos de deposito:', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                    SizedBox(height: 6),
                    Text('Banco: BBVA Mexico', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                    Text('Cuenta: Pendiente de configurar', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    SizedBox(height: 4),
                    Text('Se te notificara cuando los datos esten disponibles.', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: _submitting ? null : () async {
                final driverId = context.read<DriverProvider>().driver?.id;
                if (driverId == null) return;

                // ── TARJETA: cobro instantáneo vía Stripe PaymentSheet ──
                if (selectedMethod == 'card') {
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _payDebtWithCard(amountOwed);
                  return;
                }

                // ── Transferencia / depósito: solicitud manual (admin aprueba) ──
                setDialogState(() => _submitting = true);
                final success = await context.read<CashAccountProvider>().submitDeposit(
                  amount: amountOwed,
                  paymentMethod: selectedMethod,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(success
                        ? 'Solicitud de pago enviada. El admin sera notificado.'
                        : 'Error al enviar solicitud. Intenta de nuevo.'),
                    backgroundColor: success ? AppColors.success : AppColors.error,
                  ));
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _submitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(selectedMethod == 'card' ? 'Pagar' : 'Enviar Solicitud', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _payMethodOption(BuildContext ctx, StateSetter setDialogState, String current, String value, IconData icon, String label, Function(String) onChanged) {
    final selected = current == value;
    return GestureDetector(
      onTap: () => setDialogState(() => onChanged(value)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.success.withValues(alpha: 0.1) : AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? AppColors.success : AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: selected ? AppColors.success : AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: TextStyle(color: selected ? AppColors.success : AppColors.textPrimary, fontSize: 13))),
            if (selected) const Icon(Icons.check_circle, color: AppColors.success, size: 18),
          ],
        ),
      ),
    );
  }

  // Pago de la comisión adeudada CON TARJETA (cobro instantáneo vía Stripe).
  Future<void> _payDebtWithCard(double amount) async {
    final driver = context.read<DriverProvider>().driver;
    final driverId = driver?.id;
    if (driverId == null) return;
    final currency = (driver?.countryCode == 'US') ? 'usd' : 'mxn';

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Preparando pago seguro…'), duration: Duration(seconds: 2)));
    }
    try {
      // 1) PaymentIntent en el edge (cobro directo a la cuenta plataforma, sin split)
      final res = await Supabase.instance.client.functions.invoke(
        'stripe-driver-pay-debt',
        body: {'amount': amount, 'driverId': driverId, 'currency': currency},
      );
      final data = res.data as Map?;
      final clientSecret = data?['clientSecret'] as String?;
      if (clientSecret == null) {
        throw Exception(data?['error']?.toString() ?? 'No se pudo iniciar el pago');
      }

      // CRÍTICO: usar la pk de la MISMA cuenta donde el edge creó el PaymentIntent.
      // Si la pk del SDK es de otra cuenta, el PaymentSheet truena con
      // "No such payment_intent" (mismo patrón que marketplace).
      final pubKey = data?['publishable_key'] as String?;
      if (pubKey != null && pubKey.isNotEmpty && Stripe.publishableKey != pubKey) {
        Stripe.publishableKey = pubKey;
        await Stripe.instance.applySettings();
      }

      // 2) Stripe PaymentSheet (el SDK ya está inicializado en PaymentService.initialize)
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'TORO',
        ),
      );
      await Stripe.instance.presentPaymentSheet();

      // 3) Éxito → registrar el pago como tarjeta (la reconciliación final del
      //    saldo la confirma el webhook payment_intent.succeeded en el server).
      await context.read<CashAccountProvider>().submitDeposit(
            amount: amount,
            paymentMethod: 'card',
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('¡Pago con tarjeta exitoso! Tu saldo se actualizará.'),
          backgroundColor: AppColors.success));
      }
    } on StripeException catch (e) {
      if (mounted && e.error.code != FailureCode.Canceled) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Pago rechazado: ${e.error.localizedMessage ?? e.error.code}'),
          backgroundColor: AppColors.error));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error en el pago: $e'), backgroundColor: AppColors.error));
      }
    }
  }

  void _contactSupport() async {
    final uri = Uri.parse('https://wa.me/+526865551234?text=Hola,%20necesito%20ayuda%20con%20mi%20balance%20de%20efectivo');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        Navigator.pushNamed(context, '/support');
      }
    }
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
    final countryCode = context.read<DriverProvider>().driver?.countryCode ?? 'US';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text(formatMoney(amount, country: countryCode), style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
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
