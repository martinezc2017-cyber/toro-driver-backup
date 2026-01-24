import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../utils/app_colors.dart';
import '../core/legal/legal_documents.dart';

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

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
            Icon(Icons.gavel, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('legal'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildLegalItem(
            context,
            Icons.description,
            'terms_conditions'.tr(),
            'terms_subtitle'.tr(),
            Colors.blue,
            () => _showDocument(context, 'terms_conditions'.tr(), LegalDocuments.termsAndConditions),
          ),
          _buildLegalItem(
            context,
            Icons.privacy_tip,
            'privacy_policy'.tr(),
            'privacy_subtitle'.tr(),
            Colors.green,
            () => _showDocument(context, 'privacy_policy'.tr(), LegalDocuments.privacyPolicy),
          ),
          _buildLegalItem(
            context,
            Icons.handshake,
            'driver_agreement'.tr(),
            'driver_agreement_subtitle'.tr(),
            Colors.orange,
            () => _showDocument(context, 'driver_agreement'.tr(), LegalDocuments.driverAgreement),
          ),
          _buildLegalItem(
            context,
            Icons.security,
            'liability_waiver'.tr(),
            'liability_subtitle'.tr(),
            Colors.red,
            () => _showDocument(context, 'liability_waiver'.tr(), LegalDocuments.liabilityWaiver),
          ),

          const SizedBox(height: 40),

          // Footer
          Center(
            child: Column(
              children: [
                Icon(Icons.verified_user, size: 32, color: AppColors.primary),
                const SizedBox(height: 8),
                Text(
                  'TORO Driver',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  'Version 1.0.0',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  '2025 Toro Driver Inc.',
                  style: TextStyle(fontSize: 10, color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildLegalItem(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    Color color,
    VoidCallback onTap,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
        trailing: Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 18),
        onTap: onTap,
      ),
    );
  }

  void _showDocument(BuildContext context, String title, String content) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.3))),
              ),
              child: Row(
                children: [
                  Icon(Icons.gavel, color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                        Row(
                          children: [
                            Icon(Icons.lock, size: 10, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Text('protected_document'.tr(), style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 20, color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.all(16),
                children: [
                  SelectableText(
                    content,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.6,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.verified_user, size: 14, color: AppColors.success),
                        const SizedBox(width: 6),
                        Text(
                          'protected_visibility'.tr(),
                          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
