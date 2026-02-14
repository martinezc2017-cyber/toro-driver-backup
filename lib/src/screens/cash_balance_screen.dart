import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/driver_provider.dart';
import '../services/cash_account_service.dart';
import '../utils/app_colors.dart';

/// Cash Balance Screen - 3 tabs: Resumen, Historial, Depositar
class CashBalanceScreen extends StatefulWidget {
  const CashBalanceScreen({super.key});

  @override
  State<CashBalanceScreen> createState() => _CashBalanceScreenState();
}

class _CashBalanceScreenState extends State<CashBalanceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final CashAccountService _service = CashAccountService();

  Map<String, dynamic>? _account;
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _ledger = [];
  List<Map<String, dynamic>> _deposits = [];
  List<Map<String, dynamic>> _statements = [];
  bool _isLoading = true;

  // Deposit form
  final _depositAmountController = TextEditingController();
  final _depositRefController = TextEditingController();
  String _depositMethod = 'transfer';
  String? _proofUrl;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _depositAmountController.dispose();
    _depositRefController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final driver = Provider.of<DriverProvider>(context, listen: false).driver;
    if (driver == null) return;

    setState(() => _isLoading = true);

    final results = await Future.wait([
      _service.getCashAccount(driver.id),
      _service.getLedgerSummary(driver.id),
      _service.getCashLedger(driver.id, limit: 50),
      _service.getDepositHistory(driver.id, limit: 20),
      _service.getWeeklyStatements(driver.id, limit: 10),
    ]);

    if (mounted) {
      setState(() {
        _account = results[0] as Map<String, dynamic>?;
        _summary = results[1] as Map<String, dynamic>;
        _ledger = results[2] as List<Map<String, dynamic>>;
        _deposits = results[3] as List<Map<String, dynamic>>;
        _statements = results[4] as List<Map<String, dynamic>>;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Balance de Efectivo',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFF59E0B),
          labelColor: const Color(0xFFF59E0B),
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'Resumen'),
            Tab(text: 'Historial'),
            Tab(text: 'Depositar'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B)))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildResumenTab(),
                _buildHistorialTab(),
                _buildDepositarTab(),
              ],
            ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 1: RESUMEN
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildResumenTab() {
    final cashOwed = (_account?['current_balance'] as num?)?.toDouble() ?? 0;
    final status = _account?['status'] as String? ?? 'active';
    final totalRides = (_account?['total_cash_rides_completed'] as num?)?.toInt() ?? 0;
    final threshold = (_account?['auto_suspend_threshold'] as num?)?.toDouble() ?? 500;
    final byType = Map<String, double>.from(_summary['by_source_type'] ?? {});

    final isSuspended = status == 'suspended' || status == 'blocked';

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Main balance card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isSuspended
                    ? [const Color(0xFFDC2626), const Color(0xFFB91C1C)]
                    : cashOwed > 0
                        ? [const Color(0xFFF59E0B), const Color(0xFFD97706)]
                        : [const Color(0xFF10B981), const Color(0xFF059669)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Icon(
                  isSuspended
                      ? Icons.block_rounded
                      : cashOwed > 0
                          ? Icons.account_balance_wallet_rounded
                          : Icons.check_circle_rounded,
                  color: Colors.white,
                  size: 48,
                ),
                const SizedBox(height: 12),
                Text(
                  isSuspended ? 'CUENTA SUSPENDIDA' : 'BALANCE EFECTIVO',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '\$${cashOwed.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (isSuspended) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Deposita para reactivar',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Stats row
          Row(
            children: [
              _buildStatCard('Viajes Cash', totalRides.toString(), Icons.directions_car),
              const SizedBox(width: 12),
              _buildStatCard(
                'Limite',
                '\$${threshold.toStringAsFixed(0)}',
                Icons.warning_amber_rounded,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Breakdown by type
          if (byType.isNotEmpty) ...[
            const Text(
              'DESGLOSE POR TIPO',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            ...byType.entries.map((entry) => _buildBreakdownRow(
                  _sourceTypeLabel(entry.key),
                  entry.value,
                )),
          ],

          const SizedBox(height: 20),

          // Deposit instructions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFFF59E0B), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Como depositar',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildInstruction('1', 'Realiza una transferencia bancaria'),
                _buildInstruction('2', 'Toma foto del comprobante'),
                _buildInstruction('3', 'Sube el comprobante en la tab "Depositar"'),
                _buildInstruction('4', 'Admin aprueba y tu cuenta se actualiza'),
              ],
            ),
          ),

          // Recent statements
          if (_statements.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              'ESTADOS DE CUENTA',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            ..._statements.take(3).map(_buildStatementCard),
          ],
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFFF59E0B), size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreakdownRow(String label, double amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          Text(
            '\$${amount.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstruction(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: Color(0xFFF59E0B),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatementCard(Map<String, dynamic> statement) {
    final weekStart = statement['week_start_date'] as String? ?? '';
    final weekEnd = statement['week_end_date'] as String? ?? '';
    final netOwed = (statement['net_owed'] as num?)?.toDouble() ?? 0;
    final paymentStatus = statement['payment_status'] as String? ?? 'pending';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$weekStart → $weekEnd',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(
                  'Adeudo: \$${netOwed.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: paymentStatus == 'paid'
                  ? const Color(0xFF10B981).withOpacity(0.2)
                  : const Color(0xFFF59E0B).withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              paymentStatus == 'paid' ? 'Pagado' : 'Pendiente',
              style: TextStyle(
                color: paymentStatus == 'paid'
                    ? const Color(0xFF10B981)
                    : const Color(0xFFF59E0B),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _sourceTypeLabel(String type) {
    switch (type) {
      case 'ride':
        return 'Viajes';
      case 'carpool':
        return 'Carpool';
      case 'package':
        return 'Paquetes';
      case 'tourism':
        return 'Turismo';
      default:
        return type;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 2: HISTORIAL (Ledger)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHistorialTab() {
    if (_ledger.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, color: Colors.white24, size: 64),
            SizedBox(height: 16),
            Text(
              'Sin movimientos de efectivo',
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _ledger.length,
        itemBuilder: (context, index) {
          final entry = _ledger[index];
          return _buildLedgerEntry(entry);
        },
      ),
    );
  }

  Widget _buildLedgerEntry(Map<String, dynamic> entry) {
    final direction = entry['direction'] as String? ?? 'debit';
    final isDebit = direction == 'debit';
    final amount = (entry['amount'] as num?)?.toDouble() ?? 0;
    final balanceAfter = (entry['balance_after'] as num?)?.toDouble() ?? 0;
    final sourceType = entry['source_type'] as String? ?? '';
    final description = entry['description'] as String? ?? '';
    final createdAt = entry['created_at'] as String? ?? '';
    final grossAmount = (entry['gross_amount'] as num?)?.toDouble() ?? 0;
    final platformFee = (entry['platform_fee'] as num?)?.toDouble() ?? 0;
    final insuranceFee = (entry['insurance_fee'] as num?)?.toDouble() ?? 0;
    final taxFee = (entry['tax_fee'] as num?)?.toDouble() ?? 0;

    // Parse date
    String dateStr = '';
    if (createdAt.isNotEmpty) {
      try {
        final dt = DateTime.parse(createdAt).toLocal();
        dateStr = '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {
        dateStr = createdAt;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDebit ? const Color(0xFFF59E0B).withOpacity(0.3) : const Color(0xFF10B981).withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: (isDebit ? const Color(0xFFF59E0B) : const Color(0xFF10B981)).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isDebit ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                  color: isDebit ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isDebit ? _sourceTypeLabel(sourceType) : 'Deposito',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      dateStr,
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isDebit ? '+' : '-'}\$${amount.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: isDebit ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    'Bal: \$${balanceAfter.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          // Show breakdown for debit entries
          if (isDebit && grossAmount > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  _buildMiniRow('Gross cobrado', grossAmount),
                  _buildMiniRow('Platform fee', platformFee),
                  _buildMiniRow('Insurance', insuranceFee),
                  _buildMiniRow('Tax', taxFee),
                  const Divider(color: Colors.white12, height: 12),
                  _buildMiniRow('Debes a Toro', amount, bold: true),
                ],
              ),
            ),
          ],
          if (description.isNotEmpty && !isDebit) ...[
            const SizedBox(height: 6),
            Text(
              description,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMiniRow(String label, double value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          Text(
            '\$${value.toStringAsFixed(2)}',
            style: TextStyle(
              color: bold ? const Color(0xFFF59E0B) : Colors.white70,
              fontSize: 12,
              fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 3: DEPOSITAR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDepositarTab() {
    final cashOwed = (_account?['current_balance'] as num?)?.toDouble() ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Amount owed reminder
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet, color: Color(0xFFF59E0B)),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Saldo pendiente',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    Text(
                      '\$${cashOwed.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Color(0xFFF59E0B),
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Amount field
          const Text(
            'Monto a depositar',
            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _depositAmountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white, fontSize: 18),
            decoration: InputDecoration(
              prefixText: '\$ ',
              prefixStyle: const TextStyle(color: Color(0xFFF59E0B), fontSize: 18),
              hintText: cashOwed.toStringAsFixed(2),
              hintStyle: const TextStyle(color: Colors.white24),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFF59E0B)),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Payment method
          const Text(
            'Metodo de pago',
            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _depositMethod,
                isExpanded: true,
                dropdownColor: AppColors.surface,
                style: const TextStyle(color: Colors.white),
                items: const [
                  DropdownMenuItem(value: 'transfer', child: Text('Transferencia Bancaria')),
                  DropdownMenuItem(value: 'spei', child: Text('SPEI')),
                  DropdownMenuItem(value: 'oxxo', child: Text('OXXO')),
                  DropdownMenuItem(value: 'zelle', child: Text('Zelle')),
                  DropdownMenuItem(value: 'venmo', child: Text('Venmo')),
                  DropdownMenuItem(value: 'cash_office', child: Text('Efectivo en oficina')),
                ],
                onChanged: (v) => setState(() => _depositMethod = v ?? 'transfer'),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Reference number
          const Text(
            'Numero de referencia',
            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _depositRefController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Ej: TRF-123456',
              hintStyle: const TextStyle(color: Colors.white24),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFF59E0B)),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Proof upload
          const Text(
            'Comprobante de pago',
            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickProofImage,
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _proofUrl != null ? const Color(0xFF10B981) : Colors.white12,
                  style: _proofUrl != null ? BorderStyle.solid : BorderStyle.none,
                ),
              ),
              child: _proofUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(File(_proofUrl!), fit: BoxFit.cover),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check, color: Colors.white, size: 16),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt_rounded, color: Colors.white24, size: 36),
                        SizedBox(height: 8),
                        Text(
                          'Toca para subir foto del comprobante',
                          style: TextStyle(color: Colors.white38, fontSize: 13),
                        ),
                      ],
                    ),
            ),
          ),

          const SizedBox(height: 24),

          // Submit button
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submitDeposit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                disabledBackgroundColor: Colors.white12,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Text(
                      'Enviar Comprobante',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
            ),
          ),

          const SizedBox(height: 24),

          // Previous deposits
          if (_deposits.isNotEmpty) ...[
            const Text(
              'DEPOSITOS ANTERIORES',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            ..._deposits.map(_buildDepositCard),
          ],

          // Reset request button
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _requestReset,
            icon: const Icon(Icons.restart_alt, color: Colors.white54),
            label: const Text(
              'Solicitar Reset de Semana',
              style: TextStyle(color: Colors.white54),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildDepositCard(Map<String, dynamic> deposit) {
    final amount = (deposit['amount'] as num?)?.toDouble() ?? 0;
    final status = deposit['status'] as String? ?? 'pending';
    final method = deposit['payment_method'] as String? ?? 'transfer';
    final createdAt = deposit['created_at'] as String? ?? '';

    String dateStr = '';
    if (createdAt.isNotEmpty) {
      try {
        final dt = DateTime.parse(createdAt).toLocal();
        dateStr = '${dt.month}/${dt.day}/${dt.year}';
      } catch (_) {}
    }

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'approved':
        statusColor = const Color(0xFF10B981);
        statusLabel = 'Aprobado';
        break;
      case 'rejected':
        statusColor = const Color(0xFFDC2626);
        statusLabel = 'Rechazado';
        break;
      default:
        statusColor = const Color(0xFFF59E0B);
        statusLabel = 'Pendiente';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              status == 'approved'
                  ? Icons.check_circle
                  : status == 'rejected'
                      ? Icons.cancel
                      : Icons.hourglass_top,
              color: statusColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '\$${amount.toStringAsFixed(2)} - ${_methodLabel(method)}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                ),
                Text(dateStr, style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(color: statusColor, fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  String _methodLabel(String method) {
    switch (method) {
      case 'transfer':
        return 'Transferencia';
      case 'spei':
        return 'SPEI';
      case 'oxxo':
        return 'OXXO';
      case 'zelle':
        return 'Zelle';
      case 'venmo':
        return 'Venmo';
      case 'cash_office':
        return 'Efectivo';
      case 'stripe':
        return 'Stripe';
      default:
        return method;
    }
  }

  Future<void> _pickProofImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.camera, maxWidth: 1200);
    if (image != null) {
      setState(() => _proofUrl = image.path);
    }
  }

  Future<void> _submitDeposit() async {
    final amountText = _depositAmountController.text.trim();
    if (amountText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa el monto del deposito')),
      );
      return;
    }

    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Monto invalido')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final driver = Provider.of<DriverProvider>(context, listen: false).driver;
    if (driver == null) {
      setState(() => _isSubmitting = false);
      return;
    }

    // Upload proof image if provided
    String? uploadedProofUrl;
    if (_proofUrl != null) {
      uploadedProofUrl = await _service.uploadProofImage(driver.id, _proofUrl!);
    }

    final result = await _service.submitDeposit(
      driverId: driver.id,
      amount: amount,
      paymentMethod: _depositMethod,
      referenceNumber: _depositRefController.text.trim().isNotEmpty
          ? _depositRefController.text.trim()
          : null,
      proofUrl: uploadedProofUrl,
      countryCode: 'MX',
    );

    setState(() => _isSubmitting = false);

    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Deposito enviado. Esperando aprobacion del admin.'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
      _depositAmountController.clear();
      _depositRefController.clear();
      setState(() => _proofUrl = null);
      await _loadData();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al enviar deposito. Intenta de nuevo.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
    }
  }

  Future<void> _requestReset() async {
    final driver = Provider.of<DriverProvider>(context, listen: false).driver;
    if (driver == null) return;

    final cashOwed = (_account?['current_balance'] as num?)?.toDouble() ?? 0;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Solicitar Reset', style: TextStyle(color: Colors.white)),
        content: Text(
          'Solicitar al admin que resetee tu balance de \$${cashOwed.toStringAsFixed(2)}?\n\nSolo se aprueba si ya depositaste.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B)),
            child: const Text('Solicitar', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final result = await _service.requestWeekReset(
        driverId: driver.id,
        amountOwed: cashOwed,
        message: 'Solicitud de reset desde app',
      );

      if (result != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Solicitud enviada al admin'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    }
  }
}
