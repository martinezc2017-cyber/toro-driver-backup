import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/app_theme.dart';
import '../providers/riverpod_providers.dart';
import '../widgets/custom_keyboard.dart';

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
  String _selectedMethod = 'debit_card';

  List<Map<String, dynamic>> _bankAccounts = [];
  List<Map<String, dynamic>> _debitCards = [];
  Map<String, dynamic>? _selectedDestination;

  final _amountController = TextEditingController();

  // Custom keyboard state
  bool _showNumericKeyboard = false;
  late FocusNode _keyboardListenerFocus;

  @override
  void initState() {
    super.initState();
    _keyboardListenerFocus = FocusNode();
    _amountController.addListener(() => setState(() {}));
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final driverService = ref.read(driverServiceProvider);

      // Get financial stats
      final stats = await driverService.getFinancialStats(widget.driverId);

      // Get payment methods
      final accounts = await driverService.getBankAccounts(widget.driverId);
      final cards = await driverService.getDebitCards(widget.driverId);

      setState(() {
        _availableBalance =
            (stats['available_balance'] as num?)?.toDouble() ?? 0;
        _pendingBalance = (stats['pending_balance'] as num?)?.toDouble() ?? 0;
        _bankAccounts = accounts;
        _debitCards = cards;
        _selectedAmount = _availableBalance;
        _amountController.text = _availableBalance.toStringAsFixed(2);

        // Select default destination
        if (_debitCards.isNotEmpty) {
          _selectedDestination = _debitCards.firstWhere(
            (c) => c['is_default'] == true,
            orElse: () => _debitCards.first,
          );
          _selectedMethod = 'debit_card';
        } else if (_bankAccounts.isNotEmpty) {
          _selectedDestination = _bankAccounts.firstWhere(
            (a) => a['is_default'] == true,
            orElse: () => _bankAccounts.first,
          );
          _selectedMethod = 'bank_account';
        }

        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading cash out data: $e');
      setState(() => _isLoading = false);
    }
  }

  double get _fee {
    if (_selectedAmount <= 0) return 0;
    // 1.5% or $0.50, whichever is higher
    final percentFee = _selectedAmount * 0.015;
    return percentFee < 0.50 ? 0.50 : percentFee;
  }

  double get _netAmount => _selectedAmount - _fee;

  bool get _canCashOut =>
      _selectedAmount > 0 &&
      _selectedAmount <= _availableBalance &&
      _selectedDestination != null &&
      _netAmount > 0;

  Future<void> _processCashOut() async {
    if (!_canCashOut || _isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      final driverService = ref.read(driverServiceProvider);
      final success = await driverService.requestInstantPayout(
        widget.driverId,
        _selectedAmount,
        _selectedMethod,
        _selectedDestination!['id'],
      );

      if (success && mounted) {
        _showSuccessDialog();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error procesando el pago. Intenta de nuevo.'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error),
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
            const Text(
              '¡Cash Out Exitoso!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '\$${_netAmount.toStringAsFixed(2)}',
              style: const TextStyle(
                color: AppTheme.success,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _selectedMethod == 'debit_card'
                  ? 'El dinero llegará a tu tarjeta en minutos'
                  : 'El dinero llegará a tu cuenta en 1-3 días',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _selectedMethod == 'debit_card'
                        ? Icons.credit_card
                        : Icons.account_balance,
                    color: AppTheme.textMuted,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '****${_selectedDestination?['card_last4'] ?? _selectedDestination?['account_last4'] ?? ''}',
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
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
              child: const Text(
                'Listo',
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
    return KeyboardListener(
      focusNode: _keyboardListenerFocus,
      onKeyEvent: (event) {
        if (!_showNumericKeyboard) return;
        if (event is! KeyDownEvent) return;
        if (event.logicalKey == LogicalKeyboardKey.backspace) {
          _handleExternalBackspace();
        } else if (event.character != null && event.character!.isNotEmpty) {
          _handleExternalKeyboardInput(event.character!);
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.background,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'Cash Out',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
        ),
        body: Stack(
          children: [
            _isLoading
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
            // Custom Keyboard Overlay
            if (_showNumericKeyboard)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: CustomNumericKeyboard(
                  controller: _amountController,
                  onDone: () {
                    setState(() => _showNumericKeyboard = false);
                  },
                  onChanged: () => setState(() {}),
                ),
              ),
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
              const Text(
                'Balance Disponible',
                style: TextStyle(color: Colors.white70, fontSize: 13),
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
                    '\$${_pendingBalance.toStringAsFixed(2)} pendiente',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '\$${_availableBalance.toStringAsFixed(2)}',
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

  Widget _buildAmountSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Monto a retirar',
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
                  keyboardType: TextInputType.none,
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
                  onTap: _toggleNumericKeyboard,
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
                  'Monto excede tu balance disponible',
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
                  ? 'Todo (\$${amount.toStringAsFixed(0)})'
                  : '\$${amount.toStringAsFixed(0)}',
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
        const Text(
          'Método de pago',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),

        // Debit cards (instant)
        if (_debitCards.isNotEmpty) ...[
          _buildMethodHeader('⚡ Instant (Tarjeta)', 'Minutos'),
          ..._debitCards.map(
            (card) => _buildPaymentOption(
              card,
              'debit_card',
              Icons.credit_card,
              '****${card['card_last4']}',
              card['card_brand'] ?? 'Tarjeta',
              isInstant: true,
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Bank accounts (1-3 days)
        if (_bankAccounts.isNotEmpty) ...[
          _buildMethodHeader('🏦 Transferencia', '1-3 días'),
          ..._bankAccounts.map(
            (account) => _buildPaymentOption(
              account,
              'bank_account',
              Icons.account_balance,
              '****${account['account_last4']}',
              account['bank_name'] ?? 'Banco',
              isInstant: false,
            ),
          ),
        ],

        // Add new method
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _addPaymentMethod,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Agregar método de pago'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.textMuted,
            side: const BorderSide(color: AppTheme.border),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMethodHeader(String title, String timing) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              timing,
              style: const TextStyle(color: AppTheme.primary, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentOption(
    Map<String, dynamic> data,
    String method,
    IconData icon,
    String number,
    String name, {
    bool isInstant = false,
  }) {
    final isSelected = _selectedDestination?['id'] == data['id'];

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedDestination = data;
          _selectedMethod = method;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary.withValues(alpha: 0.1) : AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (isInstant ? AppTheme.warning : AppTheme.info)
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: isInstant ? AppTheme.warning : AppTheme.info,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    number,
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (isInstant)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt, color: AppTheme.warning, size: 12),
                    SizedBox(width: 2),
                    Text(
                      'Instant',
                      style: TextStyle(
                        color: AppTheme.warning,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(width: 8),
            Icon(
              isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isSelected ? AppTheme.primary : AppTheme.textMuted,
            ),
          ],
        ),
      ),
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
          _buildFeeRow('Monto', '\$${_selectedAmount.toStringAsFixed(2)}'),
          _buildFeeRow(
            'Fee de servicio',
            '-\$${_fee.toStringAsFixed(2)}',
            isNegative: true,
          ),
          const Divider(color: AppTheme.border, height: 20),
          _buildFeeRow(
            'Recibirás',
            '\$${_netAmount.toStringAsFixed(2)}',
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
                    'Cash Out \$${_netAmount.toStringAsFixed(2)}',
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
              _selectedMethod == 'debit_card'
                  ? 'Los fondos llegarán a tu tarjeta en minutos. Fee: 1.5% (mín. \$0.50)'
                  : 'Los fondos llegarán a tu cuenta en 1-3 días hábiles.',
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
            const Text(
              'Agregar Método de Pago',
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
                  color: AppTheme.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.credit_card, color: AppTheme.warning),
              ),
              title: const Text(
                'Tarjeta de Débito',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Instant - Recibe en minutos',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: AppTheme.textMuted,
              ),
              onTap: () {
                Navigator.pop(context);
                // TODO: Navigate to add debit card screen
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Agregar tarjeta - Próximamente'),
                  ),
                );
              },
            ),
            const Divider(color: AppTheme.border),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.info.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.account_balance, color: AppTheme.info),
              ),
              title: const Text(
                'Cuenta Bancaria',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                '1-3 días hábiles',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: AppTheme.textMuted,
              ),
              onTap: () {
                Navigator.pop(context);
                // TODO: Navigate to add bank account screen
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Agregar cuenta - Próximamente'),
                  ),
                );
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
    _keyboardListenerFocus.dispose();
    super.dispose();
  }

  void _handleExternalKeyboardInput(String char) {
    final value = _amountController.value;
    final start = value.selection.baseOffset;
    final end = value.selection.extentOffset;

    if (start < 0) {
      _amountController.text += char;
    } else {
      final newText = value.text.replaceRange(start, end, char);
      _amountController.value = value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: start + char.length),
      );
    }
    setState(() {});
  }

  void _handleExternalBackspace() {
    if (_amountController.text.isEmpty) return;

    final value = _amountController.value;
    final start = value.selection.baseOffset;
    final end = value.selection.extentOffset;

    if (start < 0) {
      _amountController.text = value.text.substring(0, value.text.length - 1);
    } else if (start == end) {
      _amountController.value = value.copyWith(
        text: value.text.replaceRange(start - 1, end, ''),
        selection: TextSelection.collapsed(offset: start - 1),
      );
    } else {
      _amountController.value = value.copyWith(
        text: value.text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
      );
    }
    setState(() {});
  }

  void _toggleNumericKeyboard() {
    _keyboardListenerFocus.requestFocus();
    setState(() {
      _showNumericKeyboard = true;
    });
  }
}
