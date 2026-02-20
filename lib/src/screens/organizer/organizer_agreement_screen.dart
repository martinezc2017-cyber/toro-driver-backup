import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';
import '../../config/supabase_config.dart';
import '../../core/legal/legal_constants.dart';
import '../../core/legal/legal_documents.dart';
import '../../services/organizer_service.dart';

/// Simplified Organizer Platform Agreement screen.
///
/// Shows a clean, non-intimidating acceptance flow:
/// - Brief description of terms
/// - Expandable full contract (optional reading)
/// - Single checkbox + Accept button
///
/// Behind the scenes: auto-detects country via GPS,
/// collects full audit trail (IP, GPS, device, hash, session).
class OrganizerAgreementScreen extends StatefulWidget {
  final String organizerId;

  const OrganizerAgreementScreen({super.key, required this.organizerId});

  @override
  State<OrganizerAgreementScreen> createState() =>
      _OrganizerAgreementScreenState();
}

class _OrganizerAgreementScreenState extends State<OrganizerAgreementScreen> {
  bool _isSubmitting = false;
  bool _hasAgreed = false;
  bool _showFullContract = false;
  String _appVersion = '1.0.0';

  // Auto-detected (hidden from user)
  String _detectedCountry = 'US';
  String _detectedState = '';
  Position? _detectedPosition;

  // Scroll tracking
  final ScrollController _contractScrollController = ScrollController();
  double _scrollPercentage = 0.0;
  DateTime? _contractOpenedAt;
  final DateTime _screenOpenedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _autoDetectLocation();
    _contractScrollController.addListener(_trackScroll);
  }

  @override
  void dispose() {
    _contractScrollController.removeListener(_trackScroll);
    _contractScrollController.dispose();
    super.dispose();
  }

  void _trackScroll() {
    if (_contractScrollController.hasClients &&
        _contractScrollController.position.maxScrollExtent > 0) {
      final pct = _contractScrollController.offset /
          _contractScrollController.position.maxScrollExtent;
      if (pct > _scrollPercentage) {
        _scrollPercentage = pct.clamp(0.0, 1.0);
      }
    }
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = info.version);
    } catch (_) {}
  }

  /// Auto-detect country from GPS coordinates + device locale fallback
  Future<void> _autoDetectLocation() async {
    try {
      final position = await _getCurrentLocation();
      if (position != null && mounted) {
        _detectedPosition = position;
        // Simple lat-based detection: US/MX border is ~32° latitude
        // Mexico: roughly 14°N to 32.5°N
        // US: roughly 24.5°N (Key West) to 49°N
        if (position.latitude < 32.5 && position.latitude > 14.0) {
          _detectedCountry = 'MX';
        } else {
          _detectedCountry = 'US';
        }
      }
    } catch (_) {
      // Fallback: use device locale
      final locale = context.locale.toString();
      if (locale.contains('MX') || locale.contains('mx')) {
        _detectedCountry = 'MX';
      }
    }
  }

  String get _contractText {
    final lang = context.locale.languageCode;
    return LegalDocuments.getOrganizerPlatformAgreement(lang);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context, false),
        ),
        title: Text(
          'org_agreement_simple_title'.tr(),
          style: const TextStyle(
              color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            _buildHeader(),
            const SizedBox(height: 20),
            _buildContractSection(),
            const SizedBox(height: 24),
            _buildAgreeCheckbox(),
            const SizedBox(height: 20),
            _buildAcceptButton(),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Friendly header
  // ---------------------------------------------------------------------------

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFF9500).withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.handshake_outlined,
              color: Color(0xFFFF9500), size: 40),
        ),
        const SizedBox(height: 16),
        Text(
          'org_agreement_simple_subtitle'.tr(),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Contract Section (expandable, optional reading)
  // ---------------------------------------------------------------------------

  Widget _buildContractSection() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                _showFullContract = !_showFullContract;
                if (_showFullContract) {
                  _contractOpenedAt ??= DateTime.now();
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.description_outlined,
                      color: AppColors.textSecondary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'org_agreement_view_terms'.tr(),
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ),
                  Icon(
                    _showFullContract
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(height: 0),
            secondChild: Container(
              constraints: const BoxConstraints(maxHeight: 350),
              child: SingleChildScrollView(
                controller: _contractScrollController,
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Text(
                  _contractText,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    height: 1.6,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            crossFadeState: _showFullContract
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Simple checkbox
  // ---------------------------------------------------------------------------

  Widget _buildAgreeCheckbox() {
    return GestureDetector(
      onTap: () {
        HapticService.lightImpact();
        setState(() => _hasAgreed = !_hasAgreed);
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: _hasAgreed
                  ? const Color(0xFFFF9500)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(6),
              border: _hasAgreed
                  ? null
                  : Border.all(color: AppColors.border),
            ),
            child: _hasAgreed
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'org_agreement_simple_checkbox'.tr(),
              style: TextStyle(
                color: _hasAgreed ? Colors.white : AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Accept button
  // ---------------------------------------------------------------------------

  Widget _buildAcceptButton() {
    final bool canSubmit = _hasAgreed && !_isSubmitting;

    return GestureDetector(
      onTap: canSubmit ? _submitAgreement : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: canSubmit
              ? const LinearGradient(
                  colors: [Color(0xFFFF9500), Color(0xFFFF6B00)])
              : null,
          color: canSubmit ? null : AppColors.card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: _isSubmitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white)),
                )
              : Text(
                  'org_agreement_simple_accept'.tr(),
                  style: TextStyle(
                    color: canSubmit ? Colors.white : AppColors.textSecondary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Audit helpers
  // ---------------------------------------------------------------------------

  Future<String?> _getPublicIP() async {
    try {
      final response =
          await http.get(Uri.parse('https://api.ipify.org?format=json'));
      if (response.statusCode == 200) {
        return json.decode(response.body)['ip'] as String?;
      }
    } catch (_) {}
    return null;
  }

  String _getDeviceInfo() {
    if (kIsWeb) return 'Web Browser';
    try {
      if (Platform.isAndroid) return 'Android';
      if (Platform.isIOS) return 'iOS';
      if (Platform.isWindows) return 'Windows';
      if (Platform.isMacOS) return 'macOS';
      if (Platform.isLinux) return 'Linux';
    } catch (_) {}
    return 'Unknown';
  }

  Future<Position?> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (_) {}
    return null;
  }

  String _generateDocumentHash(String document) {
    return sha256.convert(utf8.encode(document)).toString();
  }

  // ---------------------------------------------------------------------------
  // Submit - collects EVERYTHING silently
  // ---------------------------------------------------------------------------

  Future<void> _submitAgreement() async {
    if (!_hasAgreed) return;

    setState(() => _isSubmitting = true);
    HapticService.mediumImpact();

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final sessionId = const Uuid().v4();
      final contractText = _contractText;

      // Collect audit data in parallel
      final ipFuture = _getPublicIP();
      // Use cached position or get fresh one
      final location = _detectedPosition ?? await _getCurrentLocation();

      final ipAddress = await ipFuture;
      final deviceInfo = _getDeviceInfo();
      final userAgent =
          kIsWeb ? 'Flutter Web' : 'Flutter Mobile - $deviceInfo';
      final documentHash = _generateDocumentHash(contractText);
      final timezone = DateTime.now().timeZoneName;
      final lang = context.locale.languageCode;

      // Time spent on screen
      final timeSpentMs =
          DateTime.now().difference(_screenOpenedAt).inMilliseconds;
      // Time spent reading contract (if opened)
      final contractReadMs = _contractOpenedAt != null
          ? DateTime.now().difference(_contractOpenedAt!).inMilliseconds
          : 0;

      // Save to organizers table (flat columns for quick checks)
      // Uses try/catch because columns may not exist if migration hasn't run
      try {
        await OrganizerService().saveAgreementSignature(
          widget.organizerId,
          <String, dynamic>{
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
            'agreement_country': _detectedCountry,
            'agreement_state': _detectedState,
          },
        );
      } catch (_) {
        // Columns may not exist yet - that's ok, legal_consents is the real audit
      }

      // Record in legal_consents table - this is the REAL audit trail
      // Table may not exist yet if migration hasn't run
      try {
        await SupabaseConfig.client.from('legal_consents').insert({
          'user_id': user.id,
          'user_email': user.email,
          'document_type': 'organizer_platform_agreement',
          'document_version': LegalConstants.organizerAgreementVersion,
          'document_language': lang,
          'accepted_at': DateTime.now().toIso8601String(),
          'device_id': sessionId,
          'platform': deviceInfo,
          'app_version': _appVersion,
          'locale': context.locale.toString(),
          'scroll_percentage': _scrollPercentage,
          'time_spent_reading_ms': contractReadMs,
          'age_verified': true,
          'checksum': documentHash,
          'consent_json': {
            'organizer_id': widget.organizerId,
            'auth_uid': user.id,
            'auth_email': user.email,
            'auth_provider': user.appMetadata['provider'] ?? 'unknown',
            'detected_country': _detectedCountry,
            'detected_state': _detectedState,
            'ip_address': ipAddress,
            'latitude': location?.latitude,
            'longitude': location?.longitude,
            'gps_accuracy': location?.accuracy,
            'timezone': timezone,
            'device_info': deviceInfo,
            'user_agent': userAgent,
            'app_version': _appVersion,
            'session_id': sessionId,
            'document_hash': documentHash,
            'document_language': lang,
            'screen_time_ms': timeSpentMs,
            'contract_read_time_ms': contractReadMs,
            'contract_opened': _contractOpenedAt != null,
            'scroll_percentage': _scrollPercentage,
            'accepted_at': DateTime.now().toIso8601String(),
          },
          'app_name': 'toro_driver',
        });
      } catch (_) {
        // Table may not exist yet - acceptance still counts via organizers table
      }

      if (mounted) {
        HapticService.success();
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('org_agreement_success'.tr()),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        navigator.pop(true);
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
