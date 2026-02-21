import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/earnings_provider.dart';
import '../providers/driver_provider.dart';
import '../providers/cash_account_provider.dart';
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
      context.read<CashAccountProvider>().initialize(driverId);
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

          final total = summary.weekEarnings;
          final tips = summary.weekTips;
          final netFare = total - tips - summary.weekQRBoost - summary.weekPeakHoursBonus -
                          summary.weekPromotions - summary.weekExtraBonus - summary.weekDamageFee;

          return RefreshIndicator(
            onRefresh: () async {
              final id = context.read<DriverProvider>().driver?.id;
              if (id != null) {
                await provider.refresh(id);
                await context.read<CashAccountProvider>().refresh();
              }
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

                // Stats row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stat('Online Hours', _fmtTime(summary.weekOnlineMinutes)),
                    _stat('Total Trips', '${summary.weekRides}'),
                  ],
                ),
                const SizedBox(height: 32),

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

  Widget _buildCashControlSection() {
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
                        '\$${cashOwed.toStringAsFixed(2)}',
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
              _cashRow('DEBES A TORO', '\$${cashOwed.toStringAsFixed(2)}', Icons.payments, cashOwed > 0 ? AppColors.warning : AppColors.success),

              // Breakdown by type
              if (byType.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                  child: Text('Desglose por tipo:', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ),
                for (final entry in byType.entries)
                  _cashRow(
                    _sourceTypeLabel(entry.key),
                    '\$${entry.value.toStringAsFixed(2)}',
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
    String selectedMethod = 'transfer';
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
                    Text('\$${amountOwed.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.warning, fontSize: 28, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Payment method
              const Text('Metodo de pago:', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 8),
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
                setDialogState(() => _submitting = true);
                final driverId = context.read<DriverProvider>().driver?.id;
                if (driverId != null) {
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
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _submitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Enviar Solicitud', style: TextStyle(fontWeight: FontWeight.bold)),
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
