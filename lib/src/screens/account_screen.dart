import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/driver_provider.dart';
import '../utils/app_colors.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _emailCtrl;

  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    final driver = context.read<DriverProvider>().driver;
    _nameCtrl = TextEditingController(text: driver?.fullName ?? '');
    _phoneCtrl = TextEditingController(text: driver?.phone ?? '');
    _emailCtrl = TextEditingController(text: driver?.email ?? '');

    _nameCtrl.addListener(_onFieldChanged);
    _phoneCtrl.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    if (!_hasChanges) setState(() => _hasChanges = true);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final driverProvider = context.read<DriverProvider>();

    final nameParts = _nameCtrl.text.split(' ');
    final firstName = nameParts.isNotEmpty ? nameParts.first : '';
    final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

    final success = await driverProvider.updateProfileFields(
      firstName: firstName,
      lastName: lastName,
      phone: _phoneCtrl.text,
      email: _emailCtrl.text,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'account_updated'.tr() : 'error_saving'.tr()),
          backgroundColor: success ? AppColors.success : AppColors.error,
        ),
      );
      if (success) setState(() => _hasChanges = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DriverProvider>(
      builder: (context, driverProvider, child) {
        final driver = driverProvider.driver;
        final memberSince = driver?.createdAt ?? DateTime.now();
        final rating = driver?.rating ?? 5.0;
        final totalRides = driver?.totalRides ?? 0;
        final isLoading = driverProvider.isLoading;

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
                Icon(Icons.person, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text('my_account'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Name field
              _buildInputField(
                icon: Icons.badge,
                label: 'full_name'.tr(),
                controller: _nameCtrl,
                hint: 'your_name'.tr(),
              ),
              const SizedBox(height: 12),

              // Phone field
              _buildInputField(
                icon: Icons.phone,
                label: 'phone'.tr(),
                controller: _phoneCtrl,
                hint: 'phone_hint'.tr(),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),

              // Email field (read only)
              _buildReadOnlyField(
                icon: Icons.email,
                label: 'Email',
                value: _emailCtrl.text,
                subtitle: 'contact_support_to_change'.tr(),
              ),
              const SizedBox(height: 20),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _hasChanges && !isLoading ? _save : null,
                  icon: isLoading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save, size: 18),
                  label: Text(isLoading ? 'saving'.tr() : 'save_changes'.tr()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _hasChanges ? AppColors.success : AppColors.card,
                    foregroundColor: _hasChanges ? Colors.white : AppColors.textSecondary,
                    disabledBackgroundColor: AppColors.card,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Driver Info Card
              _buildInfoCard(memberSince, rating, totalRides),
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputField({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppColors.primary, size: 16),
              ),
              const SizedBox(width: 10),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
              const Spacer(),
              Icon(Icons.edit, size: 14, color: AppColors.success),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              hintText: hint,
              hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.5)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadOnlyField({
    required IconData icon,
    required String label,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppColors.textSecondary, size: 16),
              ),
              const SizedBox(width: 10),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('read_only'.tr(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
        ],
      ),
    );
  }

  Widget _buildInfoCard(DateTime memberSince, double rating, int totalRides) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info, color: AppColors.primary, size: 16),
              const SizedBox(width: 8),
              Text('driver_info'.tr(), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.calendar_today, 'driver_since'.tr(), '${_getMonthName(memberSince.month)} ${memberSince.year}'),
          _buildInfoRow(Icons.star, 'rating_label'.tr(), rating.toStringAsFixed(2)),
          _buildInfoRow(Icons.drive_eta, 'completed_trips'.tr(), '$totalRides'),
          _buildInfoRow(Icons.verified_user, 'status_label'.tr(), 'active'.tr()),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.primary.withValues(alpha: 0.8)),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
        ],
      ),
    );
  }

  String _getMonthName(int month) {
    final months = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december'];
    return months[month - 1].tr();
  }
}
