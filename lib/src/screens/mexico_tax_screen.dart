import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../utils/app_colors.dart';
import '../services/mexico_tax_service.dart';
import '../config/supabase_config.dart';

class MexicoTaxScreen extends StatefulWidget {
  const MexicoTaxScreen({super.key});

  @override
  State<MexicoTaxScreen> createState() => _MexicoTaxScreenState();
}

class _MexicoTaxScreenState extends State<MexicoTaxScreen> {
  final MexicoTaxService _taxService = MexicoTaxService();

  bool _isLoading = true;
  String? _driverId;
  bool _hasRfc = false;
  String? _rfc;
  int _selectedYear = DateTime.now().year;

  List<TaxMonthlySummary> _monthlySummaries = [];
  TaxSummary? _yearSummary;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Get driver info
      final driverResponse = await SupabaseConfig.client
          .from('drivers')
          .select('id, rfc, rfc_validated')
          .eq('user_id', user.id)
          .maybeSingle();

      if (driverResponse != null) {
        _driverId = driverResponse['id'];
        _rfc = driverResponse['rfc'];
        _hasRfc = driverResponse['rfc_validated'] == true;

        // Get year summary
        _yearSummary = await _taxService.getTaxSummary(
          driverId: _driverId!,
          year: _selectedYear,
        );

        // Get monthly summaries
        _monthlySummaries = await _taxService.getMonthlySummaries(
          driverId: _driverId!,
          year: _selectedYear,
        );
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Icon(Icons.account_balance, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('mx_tax_title'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          // Year selector
          PopupMenuButton<int>(
            initialValue: _selectedYear,
            onSelected: (year) {
              setState(() => _selectedYear = year);
              _loadData();
            },
            itemBuilder: (context) => [
              for (int year = DateTime.now().year; year >= 2024; year--)
                PopupMenuItem(value: year, child: Text('$year')),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$_selectedYear', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // RFC Status Card
                  _buildRfcCard(),
                  const SizedBox(height: 16),

                  // Tax Info Card
                  _buildTaxInfoCard(),
                  const SizedBox(height: 16),

                  // Year Summary Card
                  if (_yearSummary != null) ...[
                    _buildYearSummaryCard(),
                    const SizedBox(height: 16),
                  ],

                  // Monthly Breakdown
                  Text(
                    'mx_monthly_breakdown'.tr(),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),

                  if (_monthlySummaries.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          'mx_no_transactions'.tr(),
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    )
                  else
                    ..._monthlySummaries.map((summary) => _buildMonthCard(summary)),

                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _buildRfcCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _hasRfc ? AppColors.success.withValues(alpha: 0.3) : AppColors.warning.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (_hasRfc ? AppColors.success : AppColors.warning).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _hasRfc ? Icons.verified : Icons.warning_amber,
                  color: _hasRfc ? AppColors.success : AppColors.warning,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'mx_rfc_status'.tr(),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    Text(
                      _hasRfc ? _rfc ?? 'RFC registrado' : 'mx_rfc_not_registered'.tr(),
                      style: TextStyle(
                        color: _hasRfc ? AppColors.success : AppColors.warning,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (!_hasRfc)
                TextButton(
                  onPressed: _showRfcDialog,
                  child: Text('mx_register'.tr(), style: TextStyle(color: AppColors.primary)),
                ),
            ],
          ),
          if (!_hasRfc) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.warning, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'mx_rfc_warning'.tr(),
                      style: TextStyle(color: AppColors.warning, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTaxInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary.withValues(alpha: 0.15), AppColors.primary.withValues(alpha: 0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('mx_tax_rates'.tr(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildRateCard(
                  'ISR',
                  _hasRfc ? '2.5%' : '20%',
                  'mx_isr_description'.tr(),
                  Icons.trending_down,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildRateCard(
                  'IVA',
                  '8%',
                  'mx_iva_description'.tr(),
                  Icons.account_balance_wallet,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRateCard(String title, String rate, String description, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 16),
              const SizedBox(width: 6),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 4),
          Text(rate, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.primary)),
          const SizedBox(height: 4),
          Text(description, style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildYearSummaryCard() {
    final summary = _yearSummary!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'mx_year_summary'.tr(namedArgs: {'year': '$_selectedYear'}),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 16),
          _buildSummaryRow('mx_gross_income'.tr(), '\$${summary.totalGross.toStringAsFixed(2)}'),
          _buildSummaryRow('mx_isr_retained'.tr(), '-\$${summary.totalIsr.toStringAsFixed(2)}', color: AppColors.error),
          _buildSummaryRow('mx_iva_retained'.tr(), '-\$${summary.totalIvaRetained.toStringAsFixed(2)}', color: AppColors.error),
          _buildSummaryRow('mx_iva_to_pay'.tr(), '\$${summary.totalIvaOwes.toStringAsFixed(2)}', color: AppColors.warning),
          const Divider(height: 24),
          _buildSummaryRow('mx_net_income'.tr(), '\$${summary.totalNet.toStringAsFixed(2)} MXN', bold: true),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.receipt_long, color: AppColors.textSecondary, size: 14),
              const SizedBox(width: 4),
              Text(
                'mx_transactions'.tr(namedArgs: {'count': '${summary.transactionCount}'}),
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              color: color ?? (bold ? AppColors.primary : AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthCard(TaxMonthlySummary summary) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              summary.month.toString().padLeft(2, '0'),
              style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
            ),
          ),
        ),
        title: Text(summary.monthName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          'mx_net'.tr(namedArgs: {'amount': summary.totalNet.toStringAsFixed(2)}),
          style: TextStyle(color: AppColors.success, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (summary.constanciaUrl != null)
              IconButton(
                icon: Icon(Icons.download, color: AppColors.primary, size: 20),
                onPressed: () => _downloadConstancia(summary.constanciaUrl!),
              ),
            Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 20),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                _buildMonthDetailRow('mx_gross'.tr(), '\$${summary.totalGross.toStringAsFixed(2)}'),
                _buildMonthDetailRow('ISR', '-\$${summary.totalIsrRetained.toStringAsFixed(2)}', color: AppColors.error),
                _buildMonthDetailRow('IVA ${'mx_retained'.tr()}', '-\$${summary.totalIvaRetained.toStringAsFixed(2)}', color: AppColors.error),
                _buildMonthDetailRow('IVA ${'mx_to_pay'.tr()}', '\$${summary.totalIvaDriverOwes.toStringAsFixed(2)}', color: AppColors.warning),
                const Divider(),
                _buildMonthDetailRow('mx_net'.tr(namedArgs: {'amount': ''}), '\$${summary.totalNet.toStringAsFixed(2)}', bold: true),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${summary.transactionCount} ${'mx_transactions_count'.tr()}', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: summary.hadRfc ? AppColors.success.withValues(alpha: 0.15) : AppColors.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        summary.hadRfc ? 'RFC 2.5%' : 'Sin RFC 20%',
                        style: TextStyle(
                          color: summary.hadRfc ? AppColors.success : AppColors.warning,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthDetailRow(String label, String value, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              color: color ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  void _showRfcDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('mx_register_rfc'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'mx_rfc_format_hint'.tr(),
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              maxLength: 13,
              decoration: InputDecoration(
                labelText: 'RFC',
                hintText: 'AAAA000000XXX',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: AppColors.card,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('mx_cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () async {
              final rfc = controller.text.trim().toUpperCase();
              if (rfc.length < 12) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('mx_rfc_invalid'.tr()), backgroundColor: AppColors.error),
                );
                return;
              }

              Navigator.pop(context);

              try {
                await _taxService.updateRfc(_driverId!, rfc);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('mx_rfc_saved'.tr()), backgroundColor: AppColors.success),
                );
                _loadData();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text('mx_save'.tr()),
          ),
        ],
      ),
    );
  }

  void _downloadConstancia(String url) {
    // TODO: Implement constancia download
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('mx_downloading_constancia'.tr())),
    );
  }
}
