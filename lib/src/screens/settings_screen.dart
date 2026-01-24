import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/driver_provider.dart';
import '../providers/auth_provider.dart';
import '../services/biometric_service.dart';
import '../utils/app_colors.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _autoAcceptRides = false;

  // Biometric settings
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  String _biometricName = 'biometric'.tr();

  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loadSettings();
      _loaded = true;
    }
  }

  void _loadSettings() async {
    final driverProvider = context.read<DriverProvider>();
    final preferences = driverProvider.driver?.preferences;
    if (preferences != null) {
      setState(() {
        _notificationsEnabled = preferences['notifications_enabled'] ?? true;
        _soundEnabled = preferences['sound_enabled'] ?? true;
        _vibrationEnabled = preferences['vibration_enabled'] ?? true;
        _autoAcceptRides = preferences['auto_accept_rides'] ?? false;
      });
    }

    // Check biometric availability
    final biometricAvailable = await BiometricService.instance.isBiometricAvailable();
    final biometricEnabled = await BiometricService.instance.isBiometricEnabled();
    final biometricName = await BiometricService.instance.getBiometricTypeName();

    if (mounted) {
      setState(() {
        _biometricAvailable = biometricAvailable;
        _biometricEnabled = biometricEnabled;
        _biometricName = biometricName;
      });
    }
  }

  Future<void> _toggleBiometric(bool enable) async {
    if (enable) {
      final success = await BiometricService.instance.authenticate(
        reason: 'confirm_identity'.tr(args: [_biometricName]),
      );
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('biometric_logout_required'.tr(args: [_biometricName])),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    } else {
      await BiometricService.instance.disableBiometric();
      setState(() => _biometricEnabled = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('biometric_disabled'.tr(args: [_biometricName])),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  Future<void> _updatePreference(String key, dynamic value) async {
    final driverProvider = context.read<DriverProvider>();
    await driverProvider.updatePreference(key, value);
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
            Icon(Icons.settings, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('configuration'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Notifications Section
          _buildSectionTitle('notifications'.tr()),
          const SizedBox(height: 8),
          _buildSwitchTile(
            Icons.notifications,
            'push_notifications'.tr(),
            'receive_trip_alerts'.tr(),
            _notificationsEnabled,
            (value) {
              setState(() => _notificationsEnabled = value);
              _updatePreference('notifications_enabled', value);
            },
          ),
          _buildSwitchTile(
            Icons.volume_up,
            'sounds'.tr(),
            'audio_alerts'.tr(),
            _soundEnabled,
            (value) {
              setState(() => _soundEnabled = value);
              _updatePreference('sound_enabled', value);
            },
          ),
          _buildSwitchTile(
            Icons.vibration,
            'vibration'.tr(),
            'haptic_feedback'.tr(),
            _vibrationEnabled,
            (value) {
              setState(() => _vibrationEnabled = value);
              _updatePreference('vibration_enabled', value);
            },
          ),

          const SizedBox(height: 20),

          // Security Section
          if (_biometricAvailable) ...[
            _buildSectionTitle('security'.tr()),
            const SizedBox(height: 8),
            _buildSwitchTile(
              _biometricName == 'Face ID' ? Icons.face : Icons.fingerprint,
              _biometricName,
              _biometricEnabled ? 'quick_access_enabled'.tr() : 'sign_in_with_biometric'.tr(args: [_biometricName]),
              _biometricEnabled,
              (value) => _toggleBiometric(value),
            ),
            const SizedBox(height: 20),
          ],

          // Rides Section
          _buildSectionTitle('rides_section'.tr()),
          const SizedBox(height: 8),
          _buildSwitchTile(
            Icons.flash_auto,
            'auto_accept'.tr(),
            'auto_accept_desc'.tr(),
            _autoAcceptRides,
            (value) {
              setState(() => _autoAcceptRides = value);
              _updatePreference('auto_accept_rides', value);
            },
          ),

          const SizedBox(height: 32),

          // Danger Zone
          _buildDangerZone(),

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
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSwitchTile(
    IconData icon,
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Container(
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
            color: (value ? AppColors.primary : AppColors.textSecondary).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: value ? AppColors.primary : AppColors.textSecondary, size: 18),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary)),
        subtitle: Text(subtitle, style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        trailing: Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeTrackColor: AppColors.primary,
          activeThumbColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildDangerZone() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning, color: AppColors.error, size: 16),
              const SizedBox(width: 8),
              Text(
                'danger_zone'.tr(),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.error),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showLogoutConfirmation(),
              icon: Icon(Icons.logout, size: 18, color: AppColors.error),
              label: Text('logout'.tr()),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: BorderSide(color: AppColors.error),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () => _showDeleteAccountConfirmation(),
              child: Text(
                'delete_account_permanent'.tr(),
                style: TextStyle(color: AppColors.error.withValues(alpha: 0.7), fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showLogoutConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('logout_confirm'.tr(), style: const TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: Text('logout_message'.tr(), style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('cancel'.tr(), style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('exit'.tr(), style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<AuthProvider>().logout();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
    }
  }

  Future<void> _showDeleteAccountConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning, color: AppColors.error, size: 20),
            const SizedBox(width: 8),
            Text('delete_account_confirm'.tr(), style: TextStyle(color: AppColors.error, fontSize: 16)),
          ],
        ),
        content: Text('delete_warning'.tr(), style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('cancel'.tr(), style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('delete'.tr(), style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<AuthProvider>().deleteAccount();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
    }
  }
}
