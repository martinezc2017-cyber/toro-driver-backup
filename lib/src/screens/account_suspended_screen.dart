import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/driver_provider.dart';
import '../services/cash_account_service.dart';
import '../services/notification_service.dart';
import '../config/supabase_config.dart';
import '../utils/app_colors.dart';
import 'cash_balance_screen.dart';

/// Blocking overlay when driver's cash account is suspended.
/// Shows amount owed, deposit button, contact admin button, and reset request.
class AccountSuspendedScreen extends StatefulWidget {
  final double amountOwed;
  final String? blockedReason;

  const AccountSuspendedScreen({
    super.key,
    required this.amountOwed,
    this.blockedReason,
  });

  @override
  State<AccountSuspendedScreen> createState() => _AccountSuspendedScreenState();
}

class _AccountSuspendedScreenState extends State<AccountSuspendedScreen> {
  final CashAccountService _cashService = CashAccountService();
  bool _isSendingRequest = false;
  bool _requestSent = false;
  bool _isCheckingStatus = false;

  // Stream to listen for reactivation
  late final Stream<Map<String, dynamic>> _accountStream;
  String? _driverId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final driver = Provider.of<DriverProvider>(context, listen: false).driver;
      if (driver != null) {
        _driverId = driver.id;
        _accountStream = _cashService.streamCashAccount(driver.id);
        // Listen for reactivation
        _accountStream.listen((data) {
          if (data.isNotEmpty && data['status'] == 'active' && mounted) {
            // Account reactivated! Show notification and pop
            _showReactivatedNotification();
          }
        });
      }
    });
  }

  void _showReactivatedNotification() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Tu cuenta ha sido reactivada!',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: Color(0xFF10B981),
        duration: Duration(seconds: 4),
      ),
    );

    // Pop back to home after a brief delay
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  /// Contact admin — sends a week_reset_request that shows up in
  /// admin Cash Control > Reset Requests tab
  Future<void> _contactAdmin() async {
    if (_driverId == null) return;

    setState(() => _isSendingRequest = true);

    try {
      // 1. Create reset request (shows in admin Cash Control tab)
      final result = await _cashService.requestWeekReset(
        driverId: _driverId!,
        amountOwed: widget.amountOwed,
        message: 'Cuenta suspendida. Solicito revision de pagos para reactivacion.',
      );

      // 2. Also send a push notification to admin
      await _notifyAdminSuspendedDriver();

      if (mounted) {
        setState(() {
          _isSendingRequest = false;
          _requestSent = result != null;
        });

        if (result != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Solicitud enviada al administrador'),
              backgroundColor: Color(0xFF10B981),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSendingRequest = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  /// Notify admin via audit_log entry (admin can see in Cash Control)
  Future<void> _notifyAdminSuspendedDriver() async {
    try {
      final client = SupabaseConfig.client;
      await client.from('audit_log').insert({
        'entity_type': 'driver_credit_account',
        'entity_id': _driverId,
        'action': 'suspended_driver_contact_request',
        'new_values': {
          'driver_id': _driverId,
          'amount_owed': widget.amountOwed,
          'message': 'Driver solicita revision de cuenta suspendida',
          'requested_at': DateTime.now().toIso8601String(),
        },
        'performed_by': _driverId,
        'performed_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error notifying admin: $e');
    }
  }

  /// Check if account has been reactivated
  Future<void> _checkStatus() async {
    if (_driverId == null) return;

    setState(() => _isCheckingStatus = true);

    final account = await _cashService.getCashAccount(_driverId!);

    if (mounted) {
      setState(() => _isCheckingStatus = false);

      if (account != null && account['status'] == 'active') {
        _showReactivatedNotification();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tu cuenta sigue suspendida. Contacta al admin.'),
            backgroundColor: Color(0xFFF59E0B),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(flex: 1),

              // Warning icon
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626).withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.block_rounded,
                  color: Color(0xFFDC2626),
                  size: 56,
                ),
              ),

              const SizedBox(height: 24),

              const Text(
                'CUENTA SUSPENDIDA',
                style: TextStyle(
                  color: Color(0xFFDC2626),
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),

              const SizedBox(height: 12),

              Text(
                'Tu cuenta ha sido suspendida por saldo pendiente de efectivo.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 15,
                ),
              ),

              const SizedBox(height: 32),

              // Amount owed card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFDC2626), Color(0xFFB91C1C)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    const Text(
                      'SALDO PENDIENTE',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '\$${widget.amountOwed.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (widget.blockedReason != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        widget.blockedReason!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Instructions
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
                    const Text(
                      'Para reactivar tu cuenta:',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildStep('1', 'Realiza el deposito por transferencia bancaria'),
                    _buildStep('2', 'Sube el comprobante en "Depositar"'),
                    _buildStep('3', 'El admin aprobara y tu cuenta se reactiva automaticamente'),
                  ],
                ),
              ),

              const Spacer(flex: 1),

              // Action buttons
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CashBalanceScreen()),
                    );
                  },
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text(
                    'Depositar Ahora',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Contact admin button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _isSendingRequest || _requestSent ? null : _contactAdmin,
                  icon: Icon(
                    _requestSent ? Icons.check : Icons.support_agent_rounded,
                    color: _requestSent ? const Color(0xFF10B981) : Colors.white70,
                  ),
                  label: Text(
                    _isSendingRequest
                        ? 'Enviando...'
                        : _requestSent
                            ? 'Solicitud Enviada'
                            : 'Contactar Administrador',
                    style: TextStyle(
                      color: _requestSent ? const Color(0xFF10B981) : Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: _requestSent ? const Color(0xFF10B981) : Colors.white24,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Check status button
              TextButton.icon(
                onPressed: _isCheckingStatus ? null : _checkStatus,
                icon: _isCheckingStatus
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38),
                      )
                    : const Icon(Icons.refresh, color: Colors.white38, size: 18),
                label: Text(
                  _isCheckingStatus ? 'Verificando...' : 'Verificar estado de cuenta',
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
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
                  fontSize: 11,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
