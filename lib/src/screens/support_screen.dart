import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/app_colors.dart';
import 'create_ticket_screen.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

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
            Icon(Icons.support_agent, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('support'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Quick Actions
          _buildSectionTitle('quick_actions'.tr()),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildQuickAction(
                Icons.report_problem,
                'report_problem'.tr(),
                Colors.orange,
                () => _openTicketForm(context, 'general', 'report_problem'.tr(), 'report_problem_desc'.tr())
              )),
              const SizedBox(width: 8),
              Expanded(child: _buildQuickAction(
                Icons.receipt_long,
                'payment_issue'.tr(),
                AppColors.error,
                () => _openTicketForm(context, 'payment', 'payment_issue'.tr(), 'payment_issue_desc'.tr(), requiresTripSelection: true)
              )),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildQuickAction(
                Icons.person_off,
                'passenger_issue'.tr(),
                Colors.purple,
                () => _openTicketForm(context, 'general', 'passenger_issue'.tr(), 'passenger_issue_desc'.tr(), requiresTripSelection: true)
              )),
              const SizedBox(width: 8),
              Expanded(child: _buildQuickAction(
                Icons.car_crash,
                'accident'.tr(),
                Colors.red.shade700,
                () => _openTicketForm(context, 'general', 'accident'.tr(), 'accident_desc'.tr())
              )),
            ],
          ),

          const SizedBox(height: 24),

          // FAQ Section
          _buildSectionTitle('faq'.tr()),
          const SizedBox(height: 8),
          _buildFAQItem('faq_withdraw'.tr(), 'faq_withdraw_answer'.tr()),
          _buildFAQItem('faq_noshow'.tr(), 'faq_noshow_answer'.tr()),
          _buildFAQItem('faq_documents'.tr(), 'faq_documents_answer'.tr()),
          _buildFAQItem('faq_bonus'.tr(), 'faq_bonus_answer'.tr()),

          const SizedBox(height: 24),

          // Contact Section
          _buildSectionTitle('contact_us'.tr()),
          const SizedBox(height: 8),
          _buildContactItem(Icons.email, 'email'.tr(), 'drivers@toro-ride.com', AppColors.primary, () => _launchEmail()),
          _buildContactItem(Icons.schedule, 'hours'.tr(), 'Mon-Sun 7AM - 11PM', Colors.purple, null),

          const SizedBox(height: 24),

          // Emergency Section
          _buildEmergencyCard(context),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFAQItem(String question, String answer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: Theme(
        data: ThemeData(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Text(question, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary)),
          iconColor: AppColors.textSecondary,
          collapsedIconColor: AppColors.textSecondary,
          children: [
            Text(answer, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildContactItem(IconData icon, String title, String subtitle, Color color, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary)),
          subtitle: Text(subtitle, style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          trailing: onTap != null ? Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 18) : null,
        ),
      ),
    );
  }

  Widget _buildEmergencyCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.emergency, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('emergency'.tr(), style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                    Text('emergency_subtitle'.tr(), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _call911(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.error,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.phone, size: 16),
                  label: Text('call_911'.tr(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.share_location, size: 16),
                  label: Text('share_location'.tr(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _launchEmail() async {
    final uri = Uri.parse('mailto:drivers@toro-ride.com');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _call911() async {
    final uri = Uri.parse('tel:911');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  static void _openTicketForm(BuildContext context, String category, String subject, String description, {bool requiresTripSelection = false}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateTicketScreen(
          category: category,
          subject: subject,
          initialDescription: description,
          requiresTripSelection: requiresTripSelection,
        ),
      ),
    );
  }
}
