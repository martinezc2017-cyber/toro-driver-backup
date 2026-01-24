import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_colors.dart';
import '../utils/haptic_service.dart';
import '../providers/driver_provider.dart';

class ReferScreen extends StatefulWidget {
  const ReferScreen({super.key});

  @override
  State<ReferScreen> createState() => _ReferScreenState();
}

class _ReferScreenState extends State<ReferScreen> {
  String _referralCode = '';
  bool _isLoading = true;
  final String _appLink = 'https://toro.app/download';

  @override
  void initState() {
    super.initState();
    _loadOrCreateReferralCode();
  }

  Future<void> _loadOrCreateReferralCode() async {
    final driverProvider = context.read<DriverProvider>();
    final driverId = driverProvider.driver?.id;

    if (driverId == null) {
      setState(() {
        _referralCode = 'TORO0000';
        _isLoading = false;
      });
      return;
    }

    try {
      final response = await Supabase.instance.client
          .from('drivers')
          .select('referral_code')
          .eq('id', driverId)
          .single();

      if (response['referral_code'] != null && response['referral_code'].toString().isNotEmpty) {
        setState(() {
          _referralCode = response['referral_code'];
          _isLoading = false;
        });
      } else {
        await _generateAndSaveCode(driverId);
      }
    } catch (e) {
      await _generateAndSaveCode(driverId);
    }
  }

  Future<void> _generateAndSaveCode(String driverId) async {
    final driverProvider = context.read<DriverProvider>();
    final driverName = driverProvider.driver?.fullName ?? 'TORO';
    final firstName = driverName.split(' ').first.toUpperCase();
    final shortName = firstName.length > 6 ? firstName.substring(0, 6) : firstName;
    final random = Random();
    final digits = List.generate(4, (_) => random.nextInt(10)).join();
    final newCode = '$shortName$digits';

    try {
      await Supabase.instance.client
          .from('drivers')
          .update({'referral_code': newCode})
          .eq('id', driverId);
    } catch (e) {
      // Continue even if save fails
    }

    setState(() {
      _referralCode = newCode;
      _isLoading = false;
    });
  }

  String get _shareMessage => 'Únete a TORO con mi código: $_referralCode\n$_appLink';

  Future<void> _shareViaWhatsApp() async {
    HapticService.lightImpact();
    final url = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(_shareMessage)}');
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _shareViaFacebook() async {
    HapticService.lightImpact();
    final url = Uri.parse('https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(_appLink)}');
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _shareViaTelegram() async {
    HapticService.lightImpact();
    final url = Uri.parse('https://t.me/share/url?url=${Uri.encodeComponent(_appLink)}&text=${Uri.encodeComponent(_shareMessage)}');
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _shareMore() async {
    HapticService.lightImpact();
    await Share.share(_shareMessage, subject: 'download_toro'.tr());
  }

  void _copyCode() {
    HapticService.success();
    Clipboard.setData(ClipboardData(text: _referralCode));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('code_copied'.tr()),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
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
            Icon(Icons.card_giftcard, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('refer_friends'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // QR Code Card - Compact
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                if (_isLoading)
                  const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
                else ...[
                  // QR
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: QrImageView(
                      data: '$_appLink?ref=$_referralCode',
                      version: QrVersions.auto,
                      size: 120,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Code
                  GestureDetector(
                    onTap: _copyCode,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _referralCode,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.copy, size: 16, color: AppColors.primary),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Share Options - Compact row
          Container(
            padding: const EdgeInsets.all(12),
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
                    Icon(Icons.share, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text('share_via'.tr(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildShareBtn(Icons.chat, 'WhatsApp', const Color(0xFF25D366), _shareViaWhatsApp),
                    _buildShareBtn(Icons.facebook, 'Facebook', const Color(0xFF1877F2), _shareViaFacebook),
                    _buildShareBtn(Icons.telegram, 'Telegram', const Color(0xFF0088CC), _shareViaTelegram),
                    _buildShareBtn(Icons.more_horiz, 'more'.tr(), AppColors.textSecondary, _shareMore),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // How it works - Compact list
          Container(
            padding: const EdgeInsets.all(12),
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
                    Icon(Icons.lightbulb_outline, size: 16, color: AppColors.star),
                    const SizedBox(width: 8),
                    Text('how_it_works'.tr(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 12),
                _buildStep(1, 'step_share'.tr()),
                _buildStep(2, 'step_register'.tr()),
                _buildStep(3, 'step_first_trip'.tr()),
                _buildStep(4, 'step_earn'.tr()),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Stats row
          Row(
            children: [
              Expanded(child: _buildStatCard('0', 'referrals_stat'.tr(), AppColors.primary)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatCard('${(context.watch<DriverProvider>().driver?.totalRides ?? 0) * 50}', 'points_stat'.tr(), AppColors.star)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShareBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildStep(int num, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text('$num', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary))),
        ],
      ),
    );
  }

  Widget _buildStatCard(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
