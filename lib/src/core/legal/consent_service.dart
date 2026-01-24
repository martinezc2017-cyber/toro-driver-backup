import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../logging/app_logger.dart';
import 'consent_record.dart';
import 'legal_constants.dart';

/// Enterprise-grade consent management service for TORO DRIVER
/// Handles persistence, verification, and audit logging of legal consents
class ConsentService {
  static ConsentService? _instance;
  static ConsentService get instance => _instance ??= ConsentService._();

  ConsentService._();

  static const String _consentsKey = 'driver_legal_consents';
  List<ConsentRecord> _consents = [];
  bool _initialized = false;

  /// Initialize the consent service - must be called before use
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      await _loadConsents();
      _initialized = true;
      AppLogger.log('LEGAL_SERVICE -> Initialized with ${_consents.length} consent records');
    } catch (e) {
      AppLogger.log('LEGAL_SERVICE -> Error initializing: $e');
      _consents = [];
      _initialized = true;
    }
  }

  /// Check if driver has accepted the current version of all required documents
  bool hasAcceptedCurrentTerms() {
    final termsConsent = _getLatestConsent(LegalDocumentType.termsAndConditions.key);
    final privacyConsent = _getLatestConsent(LegalDocumentType.privacyPolicy.key);

    if (termsConsent == null || privacyConsent == null) {
      return false;
    }

    // Check if accepted versions match current versions
    final termsOk = termsConsent.documentVersion == LegalConstants.termsVersion;
    final privacyOk = privacyConsent.documentVersion == LegalConstants.privacyVersion;

    AppLogger.log('LEGAL_CHECK -> Terms: $termsOk, Privacy: $privacyOk');

    return termsOk && privacyOk;
  }

  /// Check if driver needs to accept updated terms (version mismatch)
  bool needsToAcceptUpdatedTerms() {
    final termsConsent = _getLatestConsent(LegalDocumentType.termsAndConditions.key);
    final privacyConsent = _getLatestConsent(LegalDocumentType.privacyPolicy.key);

    // Never accepted anything
    if (termsConsent == null && privacyConsent == null) {
      return false;
    }

    return !hasAcceptedCurrentTerms();
  }

  /// Record a new consent
  Future<void> recordConsent({
    required LegalDocumentType documentType,
    required String userId,
    String? userEmail,
    required double scrollPercentage,
    required int timeSpentReadingMs,
  }) async {
    final record = ConsentRecord(
      documentType: documentType.key,
      documentVersion: _getVersionForType(documentType),
      acceptedAt: DateTime.now(),
      userId: userId,
      userEmail: userEmail,
      deviceId: await _getDeviceId(),
      appVersion: '1.0.0',
      platform: _getPlatform(),
      locale: 'en_US',
      scrollPercentage: scrollPercentage,
      timeSpentReadingMs: timeSpentReadingMs,
    );

    _consents.add(record);
    await _saveConsents();

    AppLogger.log('CONSENT_RECORDED -> ${record.toJsonString()}');
  }

  /// Record acceptance of all required documents at once for drivers
  Future<void> recordFullAcceptance({
    required String userId,
    String? userEmail,
    required double scrollPercentage,
    required int timeSpentReadingMs,
    bool ageVerified = true,
    bool backgroundCheckConsent = true,
  }) async {
    final now = DateTime.now();
    final deviceId = await _getDeviceId();
    final platform = _getPlatform();
    const locale = 'en_US';

    // Record Terms acceptance
    final termsRecord = ConsentRecord(
      documentType: LegalDocumentType.termsAndConditions.key,
      documentVersion: LegalConstants.termsVersion,
      acceptedAt: now,
      userId: userId,
      userEmail: userEmail,
      deviceId: deviceId,
      appVersion: '1.0.0',
      platform: platform,
      locale: locale,
      scrollPercentage: scrollPercentage,
      timeSpentReadingMs: timeSpentReadingMs,
    );

    // Record Privacy acceptance
    final privacyRecord = ConsentRecord(
      documentType: LegalDocumentType.privacyPolicy.key,
      documentVersion: LegalConstants.privacyVersion,
      acceptedAt: now,
      userId: userId,
      userEmail: userEmail,
      deviceId: deviceId,
      appVersion: '1.0.0',
      platform: platform,
      locale: locale,
      scrollPercentage: scrollPercentage,
      timeSpentReadingMs: timeSpentReadingMs,
    );

    // Record Driver Agreement acceptance
    final driverRecord = ConsentRecord(
      documentType: LegalDocumentType.driverAgreement.key,
      documentVersion: LegalConstants.termsVersion,
      acceptedAt: now,
      userId: userId,
      userEmail: userEmail,
      deviceId: deviceId,
      appVersion: '1.0.0',
      platform: platform,
      locale: locale,
      scrollPercentage: scrollPercentage,
      timeSpentReadingMs: timeSpentReadingMs,
    );

    // Record Liability Waiver acceptance
    final waiverRecord = ConsentRecord(
      documentType: LegalDocumentType.liabilityWaiver.key,
      documentVersion: LegalConstants.waiverVersion,
      acceptedAt: now,
      userId: userId,
      userEmail: userEmail,
      deviceId: deviceId,
      appVersion: '1.0.0',
      platform: platform,
      locale: locale,
      scrollPercentage: scrollPercentage,
      timeSpentReadingMs: timeSpentReadingMs,
    );

    _consents.addAll([termsRecord, privacyRecord, driverRecord, waiverRecord]);
    await _saveConsents();

    AppLogger.log('FULL_CONSENT_RECORDED -> user=$userId, terms=${LegalConstants.termsVersion}, ageVerified=$ageVerified, backgroundCheck=$backgroundCheckConsent');
  }

  /// Get all consent records for export/audit
  List<ConsentRecord> getAllConsents() => List.unmodifiable(_consents);

  /// Export all consents as JSON for legal/audit purposes
  String exportConsentsAsJson() {
    return const JsonEncoder.withIndent('  ').convert({
      'export_date': DateTime.now().toUtc().toIso8601String(),
      'total_records': _consents.length,
      'records': _consents.map((c) => c.toJson()).toList(),
    });
  }

  // Private helpers

  ConsentRecord? _getLatestConsent(String documentType) {
    final matching = _consents.where((c) => c.documentType == documentType).toList();
    if (matching.isEmpty) return null;
    matching.sort((a, b) => b.acceptedAt.compareTo(a.acceptedAt));
    return matching.first;
  }

  String _getVersionForType(LegalDocumentType type) {
    switch (type) {
      case LegalDocumentType.termsAndConditions:
        return LegalConstants.termsVersion;
      case LegalDocumentType.privacyPolicy:
        return LegalConstants.privacyVersion;
      case LegalDocumentType.liabilityWaiver:
        return LegalConstants.waiverVersion;
      default:
        return '1.0';
    }
  }

  Future<String> _getDeviceId() async {
    return '${_getPlatform()}_${DateTime.now().millisecondsSinceEpoch}';
  }

  String _getPlatform() {
    if (kIsWeb) return 'web';
    // For non-web, use defaultTargetPlatform
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  Future<void> _loadConsents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_consentsKey);
      if (jsonString != null) {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        _consents = jsonList.map((j) => ConsentRecord.fromJson(j)).toList();
      }
    } catch (e) {
      AppLogger.log('LEGAL_SERVICE -> Error loading consents: $e');
      _consents = [];
    }
  }

  Future<void> _saveConsents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _consents.map((c) => c.toJson()).toList();
      await prefs.setString(_consentsKey, jsonEncode(jsonList));
    } catch (e) {
      AppLogger.log('LEGAL_SERVICE -> Error saving consents: $e');
    }
  }

  /// Clear all consents (for testing/debug only)
  @visibleForTesting
  Future<void> clearAllConsents() async {
    _consents = [];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_consentsKey);
    } catch (e) {
      AppLogger.log('LEGAL_SERVICE -> Error clearing consents: $e');
    }
    AppLogger.log('LEGAL_SERVICE -> All consents cleared');
  }
}
