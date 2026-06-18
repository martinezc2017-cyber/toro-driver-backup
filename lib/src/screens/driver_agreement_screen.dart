import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../utils/app_colors.dart';
import '../utils/haptic_service.dart';
import '../config/supabase_config.dart';
import '../core/legal/legal_documents.dart';
import '../providers/location_provider.dart';

class DriverAgreementScreen extends StatefulWidget {
  const DriverAgreementScreen({super.key});

  @override
  State<DriverAgreementScreen> createState() => _DriverAgreementScreenState();
}

class _DriverAgreementScreenState extends State<DriverAgreementScreen> {
  final List<Offset?> _signaturePoints = [];
  bool _isSigning = false;
  bool _isSubmitting = false;
  bool _hasAgreed = false;
  bool _showFullContract = false;
  String _appVersion = '1.0.0';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = info.version);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'driver_agreement_title'.tr(),
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Quick Summary
            _buildQuickSummary(),
            const SizedBox(height: 16),

            // Full Contract (expandable)
            _buildContractSection(),
            const SizedBox(height: 20),

            // Signature Pad
            _buildSignaturePad(),
            const SizedBox(height: 16),

            // Checkbox
            _buildAgreeCheckbox(),
            const SizedBox(height: 16),

            // Submit Button
            _buildSubmitButton(),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickSummary() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary.withValues(alpha: 0.2), AppColors.primary.withValues(alpha: 0.05)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                'driver_agreement_screen_key_points'.tr(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildBulletPoint('driver_agreement_screen_bullet1'.tr()),
          _buildBulletPoint('driver_agreement_screen_bullet2'.tr()),
          _buildBulletPoint('driver_agreement_screen_bullet3'.tr()),
          _buildBulletPoint('driver_agreement_screen_bullet4'.tr()),
          _buildBulletPoint('driver_agreement_screen_bullet5'.tr()),
        ],
      ),
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 4,
            height: 4,
            decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContractSection() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          // Header - tap to expand
          GestureDetector(
            onTap: () => setState(() => _showFullContract = !_showFullContract),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.2))),
              ),
              child: Row(
                children: [
                  Icon(Icons.description, color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'driver_agreement_screen_section_header'.tr(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  Icon(
                    _showFullContract ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          // Contract content
          AnimatedCrossFade(
            firstChild: const SizedBox(height: 0),
            secondChild: Container(
              constraints: const BoxConstraints(maxHeight: 300),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _buildContractText(context),
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    height: 1.6,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            crossFadeState: _showFullContract ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
          // Tap to read indicator
          if (!_showFullContract)
            Container(
              padding: const EdgeInsets.all(10),
              child: Text(
                'driver_agreement_screen_tap_to_read'.tr(),
                style: TextStyle(color: AppColors.primary, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSignaturePad() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.draw, color: AppColors.primary, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'driver_agreement_screen_your_signature'.tr(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: () {
                    HapticService.lightImpact();
                    setState(() => _signaturePoints.clear());
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('driver_agreement_clear'.tr(), style: TextStyle(color: AppColors.error, fontSize: 11)),
                  ),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            height: 120,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isSigning ? AppColors.primary : AppColors.border.withValues(alpha: 0.3),
                width: _isSigning ? 2 : 1,
              ),
            ),
            child: Stack(
              children: [
                if (_signaturePoints.isEmpty)
                  Center(
                    child: Text(
                      'driver_agreement_screen_draw_here'.tr(),
                      style: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.5), fontSize: 12),
                    ),
                  ),
                GestureDetector(
                  onPanStart: (details) {
                    setState(() {
                      _isSigning = true;
                      _signaturePoints.add(details.localPosition);
                    });
                  },
                  onPanUpdate: (details) {
                    setState(() => _signaturePoints.add(details.localPosition));
                  },
                  onPanEnd: (details) {
                    setState(() {
                      _isSigning = false;
                      _signaturePoints.add(null);
                    });
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: CustomPaint(
                      painter: SignaturePainter(_signaturePoints),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgreeCheckbox() {
    return GestureDetector(
      onTap: () {
        HapticService.lightImpact();
        setState(() => _hasAgreed = !_hasAgreed);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _hasAgreed ? AppColors.success.withValues(alpha: 0.1) : AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _hasAgreed ? AppColors.success.withValues(alpha: 0.5) : AppColors.border.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: _hasAgreed ? AppColors.success : AppColors.surface,
                borderRadius: BorderRadius.circular(6),
                border: _hasAgreed ? null : Border.all(color: AppColors.border),
              ),
              child: _hasAgreed
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'driver_agreement_screen_checkbox'.tr(),
                style: TextStyle(
                  color: _hasAgreed ? Colors.white : AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    final bool canSubmit = _signaturePoints.isNotEmpty && _hasAgreed && !_isSubmitting;

    return GestureDetector(
      onTap: canSubmit ? _submitAgreement : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: canSubmit ? AppColors.primaryGradient : null,
          color: canSubmit ? null : AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: canSubmit ? null : Border.all(color: AppColors.border.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isSubmitting)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
              )
            else ...[
              Icon(Icons.check_circle, color: canSubmit ? Colors.white : AppColors.textSecondary, size: 20),
              const SizedBox(width: 8),
              Text(
                'driver_agreement_screen_submit'.tr(),
                style: TextStyle(
                  color: canSubmit ? Colors.white : AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Get public IP address for legal audit
  Future<String?> _getPublicIP() async {
    try {
      final response = await http.get(Uri.parse('https://api.ipify.org?format=json'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['ip'];
      }
    } catch (e) {
      //Could not get IP: $e');
    }
    return null;
  }

  /// Get device info for legal audit (includes device model + OS version)
  Future<String> _getDeviceInfo() async {
    if (kIsWeb) {
      return 'Web Browser';
    }
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        return 'Android ${android.version.release} - ${android.brand} ${android.model}';
      }
      if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        return 'iOS ${ios.systemVersion} - ${ios.utsname.machine}';
      }
      if (Platform.isWindows) return 'Windows';
      if (Platform.isMacOS) return 'macOS';
      if (Platform.isLinux) return 'Linux';
    } catch (e) {
      return 'Unknown';
    }
    return 'Unknown';
  }

  /// Get current location for legal audit (Uber-style)
  Future<Position?> _getCurrentLocation() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;

      // Get current position
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (e) {
      //Could not get location: $e');
      return null;
    }
  }

  /// Generate SHA256 hash of document for legal audit
  String _generateDocumentHash(String document) {
    final bytes = utf8.encode(document);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Get user's timezone
  String _getTimezone() {
    return DateTime.now().timeZoneName;
  }

  Future<void> _submitAgreement() async {
    if (_signaturePoints.isEmpty) return;

    setState(() => _isSubmitting = true);
    HapticService.mediumImpact();

    // Get context-dependent objects FIRST (before any await)
    final locationProvider = context.read<LocationProvider>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // Capture the ACTUAL displayed contract text synchronously (needs context)
    // so the audit hash matches exactly what the driver saw and signed.
    final displayedContract = _buildContractText(context);

    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Generate session ID for this signing session
      final sessionId = const Uuid().v4();

      // Get legal audit info (all in parallel for speed)
      final ipFuture = _getPublicIP();
      final locationFuture = _getCurrentLocation();

      final ipAddress = await ipFuture;
      final location = await locationFuture;
      final deviceInfo = await _getDeviceInfo();
      final userAgent = kIsWeb ? 'Flutter Web' : 'Flutter Mobile - $deviceInfo';
      final documentHash = _generateDocumentHash(displayedContract);
      final timezone = _getTimezone();

      // First get driver by user_id
      final driverResponse = await SupabaseConfig.client
          .from('drivers')
          .select('id')
          .eq('user_id', user.id)
          .maybeSingle();

      if (driverResponse == null) throw Exception('Driver profile not found');

      // Update agreement signed with ALL audit fields (Uber-style)
      await SupabaseConfig.client.from('drivers').update({
        'agreement_signed': true,
        'agreement_signed_at': DateTime.now().toIso8601String(),
        'agreement_ip_address': ipAddress,
        'agreement_device_info': deviceInfo,
        'agreement_user_agent': userAgent,
        'agreement_latitude': location?.latitude,
        'agreement_longitude': location?.longitude,
        'agreement_app_version': _appVersion,
        'agreement_document_hash': documentHash,
        'agreement_session_id': sessionId,
        'agreement_timezone': timezone,
      }).eq('id', driverResponse['id']);

      // Check if all documents are complete to activate driver
      await _checkAndActivateDriver(driverResponse['id']);

      if (mounted) {
        HapticService.success();

        // Initialize GPS immediately after signing agreement
        await locationProvider.initialize();

        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('driver_agreement_screen_success'.tr()),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        navigator.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Check if all required documents are complete and activate driver
  Future<void> _checkAndActivateDriver(String driverId) async {
    try {
      // Get driver data
      final driver = await SupabaseConfig.client
          .from('drivers')
          .select()
          .eq('id', driverId)
          .single();

      // Check all required documents
      final bool hasAgreement = driver['agreement_signed'] == true;
      final bool hasLicense = driver['license_number'] != null &&
                              driver['license_image_url'] != null;
      final bool hasProfilePhoto = driver['profile_photo_url'] != null;
      final bool hasBackgroundCheck = driver['background_check_status'] == 'approved';
      final bool hasVehicle = driver['vehicle_make'] != null &&
                              driver['vehicle_model'] != null;
      final bool hasInsurance = driver['insurance_policy'] != null;

      // All documents complete?
      final bool allComplete = hasAgreement &&
                               hasLicense &&
                               hasProfilePhoto &&
                               hasBackgroundCheck &&
                               hasVehicle &&
                               hasInsurance;

      if (allComplete) {
        await SupabaseConfig.client.from('drivers').update({
          'status': 'active',
          'is_active': true,
          'can_receive_rides': true,
        }).eq('id', driverId);
      } else {
        // Still pending - update status to show what's missing
        await SupabaseConfig.client.from('drivers').update({
          'status': 'pending_documents',
        }).eq('id', driverId);
      }
    } catch (e) {
      //Error checking driver activation: $e');
    }
  }

  /// The displayed full contract is the approved, language-aware
  /// MEXICO OPERATIONS ADDENDUM (commercial marketplace framing).
  /// Every line containing a date header ("Effective Date" / "Fecha Efectiva")
  /// is stripped so NO dates appear in the displayed contract.
  String _buildContractText(BuildContext context) {
    final lang = context.locale.languageCode;
    final addendum = LegalDocuments.getMexicoAddendum(lang);
    final filtered = addendum
        .split('\n')
        .where((line) =>
            !line.contains('Effective Date') &&
            !line.contains('Fecha Efectiva'))
        .join('\n');
    return filtered;
  }
}

class SignaturePainter extends CustomPainter {
  final List<Offset?> points;

  SignaturePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.5;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(SignaturePainter oldDelegate) => oldDelegate.points != points;
}
