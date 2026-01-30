import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../config/supabase_config.dart';
import '../services/stripe_connect_service.dart';
import '../utils/app_colors.dart';

class BankAccountScreen extends StatefulWidget {
  const BankAccountScreen({super.key});

  @override
  State<BankAccountScreen> createState() => _BankAccountScreenState();
}

class _BankAccountScreenState extends State<BankAccountScreen> {
  bool _isLoading = true;
  bool _isConnecting = false;
  Map<String, dynamic>? _driverData;
  StripeAccountStatus _accountStatus = StripeAccountStatus.notCreated;

  @override
  void initState() {
    super.initState();
    _loadDriverData();
  }

  Future<void> _loadDriverData() async {
    setState(() => _isLoading = true);
    try {
      final supabase = SupabaseConfig.client;
      final userId = supabase.auth.currentUser?.id;

      if (userId == null) {
        setState(() => _isLoading = false);
        return;
      }

      final driverResponse = await supabase
          .from('drivers')
          .select('*')
          .eq('user_id', userId)
          .maybeSingle();

      if (driverResponse != null) {
        _driverData = Map<String, dynamic>.from(driverResponse);

        final stripeAccountId = _driverData!['stripe_account_id'];
        if (stripeAccountId != null && stripeAccountId.toString().isNotEmpty) {
          _accountStatus = await StripeConnectService.instance
              .getAccountStatus(_driverData!['id']);
        } else {
          _accountStatus = StripeAccountStatus.notCreated;
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      //ERROR loading driver data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _connectStripe() async {
    if (_driverData == null) return;

    setState(() => _isConnecting = true);

    try {
      final supabase = SupabaseConfig.client;
      final user = supabase.auth.currentUser;

      String? onboardingUrl;

      if (_accountStatus == StripeAccountStatus.notCreated) {
        onboardingUrl = await StripeConnectService.instance.createConnectAccount(
          driverId: _driverData!['id'],
          email: user?.email ?? '',
          firstName: _driverData!['first_name'],
          lastName: _driverData!['last_name'],
        );
      } else if (_accountStatus == StripeAccountStatus.incomplete) {
        onboardingUrl = await StripeConnectService.instance
            .getOnboardingLink(_driverData!['id']);
      }

      if (onboardingUrl != null) {
        final opened = await StripeConnectService.instance
            .openOnboardingLink(onboardingUrl);

        if (!opened && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('no_open_link'.tr()), backgroundColor: AppColors.error),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('stripe_connect_error'.tr()), backgroundColor: AppColors.error),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
        Future.delayed(const Duration(seconds: 2), _loadDriverData);
      }
    }
  }

  Future<void> _openDashboard() async {
    if (_driverData == null) return;

    setState(() => _isConnecting = true);

    try {
      final url = await StripeConnectService.instance
          .getDashboardLink(_driverData!['id']);

      if (url != null) {
        await StripeConnectService.instance.openOnboardingLink(url);
      }
    } catch (e) {
      //ERROR opening dashboard: $e');
    } finally {
      if (mounted) setState(() => _isConnecting = false);
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
            Text('receive_payments'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, size: 20, color: AppColors.textSecondary),
            onPressed: _loadDriverData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _driverData == null
              ? _buildNotDriverMessage()
              : _buildMainContent(),
    );
  }

  Widget _buildNotDriverMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.drive_eta, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(
              'not_a_driver'.tr(),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'register_driver_payments'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Status Card
        _buildStatusCard(),
        const SizedBox(height: 16),

        // Balance Card
        if (_accountStatus == StripeAccountStatus.active)
          _buildBalanceCard(),

        if (_accountStatus == StripeAccountStatus.active)
          const SizedBox(height: 16),

        // Action Button
        _buildActionButton(),
        const SizedBox(height: 24),

        // Benefits List
        _buildBenefitsList(),
        const SizedBox(height: 16),

        // Stripe Badge
        _buildStripeBadge(),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildStatusCard() {
    IconData icon;
    Color color;
    String title;
    String subtitle;

    switch (_accountStatus) {
      case StripeAccountStatus.active:
        icon = Icons.check_circle;
        color = AppColors.success;
        title = 'account_connected'.tr();
        subtitle = 'can_receive_payments'.tr();
        break;
      case StripeAccountStatus.pendingVerification:
        icon = Icons.hourglass_empty;
        color = Colors.orange;
        title = 'pending_verification'.tr();
        subtitle = 'stripe_verifying'.tr();
        break;
      case StripeAccountStatus.incomplete:
        icon = Icons.warning;
        color = Colors.orange;
        title = 'incomplete_setup'.tr();
        subtitle = 'complete_info_payments'.tr();
        break;
      default:
        icon = Icons.account_balance;
        color = AppColors.primary;
        title = 'connect_account'.tr();
        subtitle = 'setup_earnings'.tr();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard() {
    final available = (_driverData?['available_balance'] as num?)?.toDouble() ?? 0;
    final pending = (_driverData?['pending_balance'] as num?)?.toDouble() ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('available_balance'.tr(), style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            '\$${available.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.schedule, color: Colors.white70, size: 14),
              const SizedBox(width: 4),
              Text(
                '${'pending'.tr()}: \$${pending.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    String buttonText;
    IconData buttonIcon;
    VoidCallback? onPressed;

    switch (_accountStatus) {
      case StripeAccountStatus.active:
        buttonText = 'view_payment_dashboard'.tr();
        buttonIcon = Icons.dashboard;
        onPressed = _openDashboard;
        break;
      case StripeAccountStatus.pendingVerification:
        buttonText = 'verification_in_progress'.tr();
        buttonIcon = Icons.hourglass_top;
        onPressed = null;
        break;
      case StripeAccountStatus.incomplete:
        buttonText = 'complete_setup'.tr();
        buttonIcon = Icons.edit;
        onPressed = _connectStripe;
        break;
      default:
        buttonText = 'connect_bank_account'.tr();
        buttonIcon = Icons.add_card;
        onPressed = _connectStripe;
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isConnecting ? null : onPressed,
        icon: _isConnecting
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Icon(buttonIcon, size: 18),
        label: Text(buttonText),
        style: ElevatedButton.styleFrom(
          backgroundColor: _accountStatus == StripeAccountStatus.active ? AppColors.card : AppColors.primary,
          foregroundColor: _accountStatus == StripeAccountStatus.active ? AppColors.primary : Colors.black,
          disabledBackgroundColor: AppColors.card,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: _accountStatus == StripeAccountStatus.active
                ? BorderSide(color: AppColors.primary)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildBenefitsList() {
    final benefits = [
      {'icon': Icons.flash_on, 'title': 'instant_payments'.tr(), 'subtitle': 'receive_money_minutes'.tr()},
      {'icon': Icons.security, 'title': 'secure_reliable'.tr(), 'subtitle': 'protected_by_stripe'.tr()},
      {'icon': Icons.account_balance, 'title': 'direct_to_bank'.tr(), 'subtitle': 'no_intermediaries'.tr()},
      {'icon': Icons.receipt_long, 'title': 'tax_reports'.tr(), 'subtitle': 'automatic_1099'.tr()},
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('benefits'.tr(), style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...benefits.map((b) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(b['icon'] as IconData, color: AppColors.primary, size: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b['title'] as String, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
                      Text(b['subtitle'] as String, style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildStripeBadge() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF635BFF).withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock, color: const Color(0xFF635BFF), size: 16),
            const SizedBox(width: 6),
            const Text(
              'Powered by Stripe',
              style: TextStyle(color: Color(0xFF635BFF), fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
