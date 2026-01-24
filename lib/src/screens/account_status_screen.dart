import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/driver_provider.dart';
import '../services/support_service.dart';
import '../utils/app_colors.dart';

/// Account Status Screen - Shows driver why they can't go online
/// and provides help request functionality
class AccountStatusScreen extends StatefulWidget {
  const AccountStatusScreen({super.key});

  @override
  State<AccountStatusScreen> createState() => _AccountStatusScreenState();
}

class _AccountStatusScreenState extends State<AccountStatusScreen> {
  bool _isRequestingHelp = false;
  final _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('account_status_title'.tr(), style: const TextStyle(color: AppColors.textPrimary)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Consumer<DriverProvider>(
        builder: (context, driverProvider, child) {
          final driver = driverProvider.driver;
          if (driver == null) {
            return Center(
              child: Text('no_driver_data'.tr(), style: const TextStyle(color: AppColors.textSecondary)),
            );
          }

          final canGoOnline = driver.canGoOnline;
          final statusColor = canGoOnline ? AppColors.success : const Color(0xFFFF9500);
          final statusIcon = canGoOnline ? Icons.check_circle : Icons.warning_rounded;
          final statusText = canGoOnline ? 'account_active'.tr() : 'account_restricted'.tr();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status Header Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: statusColor.withOpacity(0.3), width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(statusIcon, color: statusColor, size: 32),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              statusText,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              canGoOnline
                                  ? 'can_accept_trips'.tr()
                                  : 'complete_pending_steps'.tr(),
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Requirements Section
                Text(
                  'activation_requirements'.tr(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),

                // Documents Status
                _buildRequirementCard(
                  icon: Icons.description_outlined,
                  title: 'documents'.tr(),
                  subtitle: driver.allDocumentsSigned
                      ? 'documents_completed'.tr()
                      : 'documents_pending_sign'.tr(),
                  isComplete: driver.allDocumentsSigned,
                  onTap: () => Navigator.pushNamed(context, '/documents'),
                  details: [
                    _RequirementDetail('Driver Agreement', driver.agreementSigned),
                    _RequirementDetail('Contractor Agreement (ICA)', driver.icaSigned),
                    _RequirementDetail('Safety Policy', driver.safetyPolicySigned),
                    _RequirementDetail('Background Check Consent', driver.bgcConsentSigned),
                  ],
                ),
                const SizedBox(height: 12),

                // Admin Approval Status
                _buildRequirementCard(
                  icon: Icons.admin_panel_settings_outlined,
                  title: 'admin_approval'.tr(),
                  subtitle: driver.adminApproved
                      ? 'account_approved'.tr()
                      : 'pending_team_review'.tr(),
                  isComplete: driver.adminApproved,
                  showPending: !driver.adminApproved && driver.allDocumentsSigned,
                ),
                const SizedBox(height: 12),

                // Account Status
                _buildRequirementCard(
                  icon: Icons.verified_user_outlined,
                  title: 'account_status_title'.tr(),
                  subtitle: _getOnboardingStageText(driver.onboardingStage ?? 'documents_pending'),
                  isComplete: driver.onboardingStage == 'approved',
                  isBlocked: driver.onboardingStage == 'suspended' || driver.onboardingStage == 'rejected',
                ),

                // Show warning if suspended or rejected
                if (driver.onboardingStage == 'suspended' || driver.onboardingStage == 'rejected') ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B30).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFF3B30).withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Color(0xFFFF3B30), size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            driver.onboardingStage == 'suspended'
                                ? 'account_suspended_msg'.tr()
                                : 'application_rejected_msg'.tr(),
                            style: const TextStyle(color: Color(0xFFFF3B30), fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 32),

                // Help Request Section
                Text(
                  'need_help'.tr(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'describe_problem'.tr(),
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _messageController,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: 'describe_problem_hint'.tr(),
                          hintStyle: TextStyle(color: AppColors.textTertiary.withOpacity(0.5)),
                          filled: true,
                          fillColor: AppColors.cardHover,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isRequestingHelp ? null : () => _requestHelp(driver.id),
                          icon: _isRequestingHelp
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.support_agent, size: 18),
                          label: Text(_isRequestingHelp ? 'sending'.tr() : 'request_help'.tr()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8B5CF6),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Contact Info
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _buildContactOption(
                        icon: Icons.email_outlined,
                        title: 'Email',
                        subtitle: 'support@toro-ride.com',
                        color: const Color(0xFF3B82F6),
                      ),
                      const Divider(color: AppColors.border, height: 24),
                      _buildContactOption(
                        icon: Icons.phone_outlined,
                        title: 'phone'.tr(),
                        subtitle: '+1 (602) 555-0123',
                        color: const Color(0xFF22C55E),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRequirementCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isComplete,
    bool isBlocked = false,
    bool showPending = false,
    VoidCallback? onTap,
    List<_RequirementDetail>? details,
  }) {
    final color = isBlocked
        ? const Color(0xFFFF3B30)
        : isComplete
            ? AppColors.success
            : showPending
                ? const Color(0xFFFFD60A)
                : const Color(0xFFFF9500);

    final statusIcon = isBlocked
        ? Icons.block
        : isComplete
            ? Icons.check_circle
            : showPending
                ? Icons.hourglass_top
                : Icons.radio_button_unchecked;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(color: color, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Icon(statusIcon, color: color, size: 24),
                if (onTap != null) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, color: AppColors.textTertiary, size: 20),
                ],
              ],
            ),
            // Show details if available
            if (details != null && details.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(color: AppColors.border, height: 1),
              const SizedBox(height: 12),
              ...details.map((detail) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      detail.isComplete ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: detail.isComplete ? AppColors.success : AppColors.textTertiary,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      detail.title,
                      style: TextStyle(
                        color: detail.isComplete ? AppColors.textPrimary : AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContactOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            Text(subtitle, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }

  String _getOnboardingStageText(String stage) {
    switch (stage) {
      case 'pending':
        return 'registration_pending'.tr();
      case 'documents':
        return 'completing_documents'.tr();
      case 'review':
        return 'under_review'.tr();
      case 'approved':
        return 'account_approved_active'.tr();
      case 'suspended':
        return 'account_suspended'.tr();
      case 'rejected':
        return 'application_rejected'.tr();
      default:
        return 'unknown_status'.tr();
    }
  }

  Future<void> _requestHelp(String driverId) async {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('please_describe_problem'.tr()),
          backgroundColor: const Color(0xFFFF9500),
        ),
      );
      return;
    }

    setState(() => _isRequestingHelp = true);

    try {
      await SupportService.instance.createHelpRequest(
        driverId: driverId,
        message: message,
        category: 'account_recovery',
      );

      _messageController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('request_sent_contact'.tr()),
            backgroundColor: const Color(0xFF22C55E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${'error_sending'.tr()}: $e'),
            backgroundColor: const Color(0xFFFF3B30),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRequestingHelp = false);
      }
    }
  }
}

class _RequirementDetail {
  final String title;
  final bool isComplete;

  _RequirementDetail(this.title, this.isComplete);
}
