import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/app_theme.dart';
import '../utils/money_format.dart';
import '../providers/riverpod_providers.dart';
import '../models/driver_model.dart';
import '../services/stripe_connect_service.dart';
import 'bank_account_screen.dart';

/// Instant Cash Out Screen - Like Uber/Lyft instant pay
class CashOutScreen extends ConsumerStatefulWidget {
  final String driverId;

  const CashOutScreen({super.key, required this.driverId});

  @override
  ConsumerState<CashOutScreen> createState() => _CashOutScreenState();
}

class _CashOutScreenState extends ConsumerState<CashOutScreen> {
  bool _isLoading = true;
  bool _isProcessing = false;
  double _availableBalance = 0;
  double _pendingBalance = 0;
  double _selectedAmount = 0;
  String _countryCode = 'US';
  String _stripeProvider = 'us';
  bool _connectReady = false; // payouts_enabled en la cuenta Stripe Connect
  Map<String, dynamic>? _openPayout;

  final _amountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _amountController.addListener(() => setState(() {}));
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final driverService = ref.read(driverServiceProvider);

      // Stripe Connect is the only payout destination. Legacy bank/card tables
      // are intentionally not queried because they do not control the payout.
      final stats = await driverService.getFinancialStats(widget.driverId);
      final driver = await driverService.getDriver(widget.driverId);

      // CANONICAL: Stripe Connect balance es la verdad de cuánto puede retirar.
      // El driverService.getFinancialStats es agregación de DB; Stripe API es
      // lo que el banco realmente le va a transferir.
      final stripeProvider =
          ((driver?.countryCode ?? 'US').toUpperCase() == 'MX') ? 'mx' : 'us';
      final stripeBalance = await StripeConnectService.instance.getBalance(
        widget.driverId,
        provider: stripeProvider,
      );
      final openPayout = await StripeConnectService.instance.getOpenPayout(
        widget.driverId,
      );

      final stripeStatus = await StripeConnectService.instance.getAccountStatus(
        widget.driverId,
        provider: stripeProvider,
      );
      final connectReady = stripeStatus == StripeAccountStatus.active;

      // Si Stripe responde, esa es la verdad. Si no, DB stats como fallback.
      final canonicalAvailable = stripeBalance != null
          ? stripeBalance.availableCents / 100.0
          : (stats['available_balance'] as num?)?.toDouble() ?? 0;
      final canonicalPending = stripeBalance != null
          ? stripeBalance.pendingCents / 100.0
          : (stats['pending_balance'] as num?)?.toDouble() ?? 0;

      setState(() {
        _countryCode = driver?.countryCode ?? 'US';
        _stripeProvider = stripeProvider;
        _connectReady = connectReady;
        _openPayout = openPayout;
        _availableBalance = canonicalAvailable;
        _pendingBalance = canonicalPending;
        _selectedAmount = _availableBalance;
        _amountController.text = _availableBalance.toStringAsFixed(2);

        _isLoading = false;
      });
    } catch (e) {
      //Error loading cash out data: $e');
      setState(() => _isLoading = false);
    }
  }

  // stripe-instant-payout is authoritative. It currently reserves and pays the
  // exact requested amount, so the app must not invent a client-side fee.
  double get _fee => 0;

  double get _netAmount => _selectedAmount - _fee;

  bool get _canCashOut =>
      _selectedAmount > 0 &&
      _selectedAmount <= _availableBalance &&
      _connectReady &&
      _openPayout == null &&
      _netAmount > 0;

  Future<void> _processCashOut() async {
    if (!_canCashOut || _isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      // Retiro vía Stripe Connect → deposita al banco/tarjeta del onboarding.
      // Usa la fn canónica stripe-instant-payout (NO un método local).
      final result = await StripeConnectService.instance.requestPayout(
        driverId: widget.driverId,
        amountCents: (_selectedAmount * 100).round(),
        provider: _stripeProvider,
      );

      // Refrescar el balance tras el intento: el servidor ya actualizó
      // drivers.available_balance (ganado − retirado). Así la pantalla muestra el
      // saldo REAL (baja a $0 si ya retiró) y no el viejo.
      if (mounted) await _loadData();

      if (result.success && mounted) {
        _showSuccessDialog();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.error ?? 'screens.cash_out.error_processing'.tr(),
            ),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'screens.cash_out.error_generic'.tr(
                namedArgs: {'error': e.toString()},
              ),
            ),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: AppTheme.success, size: 50),
            ),
            const SizedBox(height: 20),
            Text(
              'screens.cash_out.cash_out_success'.tr(),
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              formatMoney(_netAmount, country: _countryCode),
              style: const TextStyle(
                color: AppTheme.success,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'screens.cash_out.arrival_managed'.tr(),
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context, true); // Return success
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.success,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'screens.cash_out.done'.tr(),
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'screens.cash_out.title'.tr(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Balance card
                  _buildBalanceCard(),
                  if (_openPayout != null) ...[
                    const SizedBox(height: 12),
                    _buildOpenPayoutCard(),
                  ],
                  const SizedBox(height: 24),
                  // Amount input
                  _buildAmountSection(),
                  const SizedBox(height: 24),
                  // Quick amounts
                  _buildQuickAmounts(),
                  const SizedBox(height: 24),
                  // Payment method
                  _buildPaymentMethodSection(),
                  const SizedBox(height: 24),
                  // Fee breakdown
                  _buildFeeBreakdown(),
                  const SizedBox(height: 32),
                  // Cash out button
                  _buildCashOutButton(),
                  const SizedBox(height: 16),
                  // Disclaimer
                  _buildDisclaimer(),
                ],
              ),
            ),
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primary, AppTheme.info],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet,
                color: Colors.white70,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'screens.cash_out.available_balance'.tr(),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const Spacer(),
              if (_pendingBalance > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${formatMoney(_pendingBalance, country: _countryCode)} ${'screens.cash_out.pending_suffix'.tr()}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            // EXACTO, sin redondeo (Carlos: el balance = lo que se retira, sin imaginación).
            formatMoney(_availableBalance, country: _countryCode),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOpenPayoutCard() {
    final amount = (_openPayout?['amount'] as num?)?.toDouble() ?? 0;
    final status = (_openPayout?['status'] ?? 'processing').toString();
    final stripeId = (_openPayout?['stripe_payout_id'] ?? '').toString();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule, color: AppTheme.warning, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'screens.cash_out.processing_payout'.tr(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${formatMoney(amount, country: _countryCode)} · $status${stripeId.isNotEmpty ? ' · ${stripeId.substring(0, 8)}...' : ''}',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'screens.cash_out.amount_to_withdraw'.tr(),
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.primary.withValues(alpha: 0.5),
              width: 2,
            ),
          ),
          child: Row(
            children: [
              const Text(
                '\$',
                style: TextStyle(
                  color: AppTheme.primary,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}'),
                    ),
                  ],
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: '0.00',
                    hintStyle: TextStyle(color: AppTheme.textMuted),
                  ),
                  onChanged: (value) {
                    final amount = double.tryParse(value) ?? 0;
                    setState(() => _selectedAmount = amount);
                  },
                ),
              ),
              TextButton(
                onPressed: () {
                  _amountController.text = _availableBalance.toStringAsFixed(2);
                  setState(() => _selectedAmount = _availableBalance);
                },
                child: const Text(
                  'MAX',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_selectedAmount > _availableBalance)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppTheme.error,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  'screens.cash_out.exceeds_balance'.tr(),
                  style: TextStyle(color: AppTheme.error, fontSize: 12),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildQuickAmounts() {
    final quickAmounts = [25.0, 50.0, 100.0, _availableBalance];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: quickAmounts.map((amount) {
        if (amount > _availableBalance) return const SizedBox.shrink();
        final isSelected = _selectedAmount == amount;
        final isMax = amount == _availableBalance;

        return GestureDetector(
          onTap: () {
            _amountController.text = amount.toStringAsFixed(2);
            setState(() => _selectedAmount = amount);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.primary.withValues(alpha: 0.2)
                  : AppTheme.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? AppTheme.primary : AppTheme.border,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Text(
              isMax
                  ? '${'screens.cash_out.all'.tr()} (${formatMoney(amount, country: _countryCode)})'
                  : formatMoney(amount, country: _countryCode),
              style: TextStyle(
                color: isSelected ? AppTheme.primary : Colors.white,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPaymentMethodSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'screens.cash_out.payment_method'.tr(),
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),

        // El retiro SIEMPRE va a la cuenta Stripe Connect que el chofer vinculó
        // en el onboarding (su banco/tarjeta). NO se agrega método aparte.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _connectReady
                ? AppTheme.primary.withValues(alpha: 0.1)
                : AppTheme.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _connectReady ? AppTheme.primary : AppTheme.border,
              width: _connectReady ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.info.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.account_balance,
                  color: AppTheme.info,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'screens.cash_out.stripe_bank_destination'.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _connectReady
                          ? 'screens.cash_out.stripe_ready'.tr()
                          : 'screens.cash_out.stripe_not_ready'.tr(),
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                _connectReady ? Icons.check_circle : Icons.error_outline,
                color: _connectReady ? AppTheme.success : AppTheme.warning,
              ),
            ],
          ),
        ),
        if (!_connectReady) ...[
          // BOTON, no solo texto. Antes decia "ve a Ganancias" sin llevarte:
          // el chofer quedaba atorado sin poder retirar y sin saber a donde ir.
          // Abre la pantalla que crea la cuenta y lanza la liga de Stripe sola.
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BankAccountScreen(),
                    ),
                  );
                  // Al volver, re-checa por si ya completo su registro.
                  if (mounted) _loadData();
                },
                icon: const Icon(Icons.account_balance, size: 18),
                label: Text(
                  'screens.cash_out.complete_payment_registration'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.warning,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              (_countryCode == 'MX'
                      ? 'screens.cash_out.registration_note_mx'
                      : 'screens.cash_out.registration_note_us')
                  .tr(),
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFeeBreakdown() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _buildFeeRow(
            'screens.cash_out.amount_label'.tr(),
            formatMoney(_selectedAmount, country: _countryCode),
          ),
          _buildFeeRow(
            'screens.cash_out.service_fee'.tr(),
            '-${formatMoney(_fee, country: _countryCode)}',
            isNegative: true,
          ),
          const Divider(color: AppTheme.border, height: 20),
          _buildFeeRow(
            'screens.cash_out.you_receive'.tr(),
            formatMoney(_netAmount, country: _countryCode),
            isTotal: true,
          ),
        ],
      ),
    );
  }

  Widget _buildFeeRow(
    String label,
    String value, {
    bool isNegative = false,
    bool isTotal = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isTotal ? Colors.white : AppTheme.textMuted,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: isNegative
                  ? AppTheme.error
                  : (isTotal ? AppTheme.success : Colors.white),
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
              fontSize: isTotal ? 18 : 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCashOutButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _canCashOut && !_isProcessing ? _processCashOut : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.success,
          disabledBackgroundColor: AppTheme.border,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: _isProcessing
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.bolt, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    '${'screens.cash_out.withdraw'.tr()} ${formatMoney(_netAmount, country: _countryCode)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildDisclaimer() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.info.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: AppTheme.info, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'screens.cash_out.arrival_managed'.tr(),
              style: TextStyle(color: AppTheme.info, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _addPaymentMethod() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'screens.cash_out.add_payment_method'.tr(),
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.info.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.account_balance, color: AppTheme.info),
              ),
              title: Text(
                'screens.cash_out.bank_account_label'.tr(),
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                'screens.cash_out.one_three_business_days'.tr(),
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: AppTheme.textMuted,
              ),
              onTap: () async {
                Navigator.pop(context);
                await Navigator.push(
                  this.context,
                  MaterialPageRoute(builder: (_) => const BankAccountScreen()),
                );
                if (mounted) _loadData();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }
}
