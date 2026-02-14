import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../logging/app_logger.dart';
import 'consent_record.dart';
import 'legal_constants.dart';

/// Consent management service for TORO DRIVER
/// Handles local + server persistence, language tracking, and audit logging
class ConsentService {
  static ConsentService? _instance;
  static ConsentService get instance => _instance ??= ConsentService._();

  ConsentService._();

  static const String _consentsKey = 'driver_legal_consents';
  static const String _supabaseTable = 'legal_consents';
  List<ConsentRecord> _consents = [];
  bool _initialized = false;

  /// Initialize the consent service
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

    final termsOk = termsConsent.documentVersion == LegalConstants.termsVersion;
    final privacyOk = privacyConsent.documentVersion == LegalConstants.privacyVersion;

    return termsOk && privacyOk;
  }

  /// Check if driver has accepted terms in the given language
  bool hasAcceptedTermsInLanguage(String languageCode) {
    final termsConsent = _getLatestConsent(LegalDocumentType.termsAndConditions.key);
    if (termsConsent == null) return false;

    final lang = languageCode.toLowerCase().split('_').first.split('-').first;
    final acceptedLang = termsConsent.documentLanguage.toLowerCase().split('_').first.split('-').first;

    return acceptedLang == lang &&
        termsConsent.documentVersion == LegalConstants.termsVersion;
  }

  /// Check if driver needs to accept updated terms (version mismatch)
  bool needsToAcceptUpdatedTerms() {
    final termsConsent = _getLatestConsent(LegalDocumentType.termsAndConditions.key);
    final privacyConsent = _getLatestConsent(LegalDocumentType.privacyPolicy.key);

    if (termsConsent == null && privacyConsent == null) {
      return false;
    }

    return !hasAcceptedCurrentTerms();
  }

  /// Get the language the terms were last accepted in
  String? getAcceptedLanguage() {
    final termsConsent = _getLatestConsent(LegalDocumentType.termsAndConditions.key);
    return termsConsent?.documentLanguage;
  }

  /// Record acceptance of all required documents at once
  Future<void> recordFullAcceptance({
    required String userId,
    String? userEmail,
    required String languageCode,
    required double scrollPercentage,
    required int timeSpentReadingMs,
    bool ageVerified = true,
    bool backgroundCheckConsent = true,
  }) async {
    final now = DateTime.now();
    final deviceId = await _getDeviceId();
    final platform = _getPlatform();
    final locale = _getLocale(languageCode);
    final lang = languageCode.toLowerCase().split('_').first.split('-').first;

    final documentTypes = [
      (LegalDocumentType.termsAndConditions, LegalConstants.termsVersion),
      (LegalDocumentType.privacyPolicy, LegalConstants.privacyVersion),
      (LegalDocumentType.driverAgreement, LegalConstants.icaVersion),
      (LegalDocumentType.liabilityWaiver, LegalConstants.waiverVersion),
    ];

    final records = <ConsentRecord>[];
    for (final (docType, version) in documentTypes) {
      records.add(ConsentRecord(
        documentType: docType.key,
        documentVersion: version,
        documentLanguage: lang,
        acceptedAt: now,
        userId: userId,
        userEmail: userEmail,
        deviceId: deviceId,
        appVersion: LegalConstants.legalBundleVersion,
        platform: platform,
        locale: locale,
        scrollPercentage: scrollPercentage,
        timeSpentReadingMs: timeSpentReadingMs,
      ));
    }

    _consents.addAll(records);
    await _saveConsents();

    // Save language of acceptance
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(LegalConstants.termsLanguageKey, lang);
      await prefs.setString(LegalConstants.termsVersionKey, LegalConstants.legalBundleVersion);
    } catch (e) {
      AppLogger.log('LEGAL_SERVICE -> Error saving language preference: $e');
    }

    // Persist to Supabase server
    if (LegalConstants.logToServer) {
      _persistToServer(records, ageVerified: ageVerified);
    }

    AppLogger.log(
      'FULL_CONSENT_RECORDED -> user=$userId, lang=$lang, '
      'terms=${LegalConstants.termsVersion}, scroll=${scrollPercentage.toStringAsFixed(2)}, '
      'timeMs=$timeSpentReadingMs, ageVerified=$ageVerified',
    );
  }

  /// Record a single consent
  Future<void> recordConsent({
    required LegalDocumentType documentType,
    required String userId,
    String? userEmail,
    required String languageCode,
    required double scrollPercentage,
    required int timeSpentReadingMs,
  }) async {
    final lang = languageCode.toLowerCase().split('_').first.split('-').first;
    final record = ConsentRecord(
      documentType: documentType.key,
      documentVersion: _getVersionForType(documentType),
      documentLanguage: lang,
      acceptedAt: DateTime.now(),
      userId: userId,
      userEmail: userEmail,
      deviceId: await _getDeviceId(),
      appVersion: LegalConstants.legalBundleVersion,
      platform: _getPlatform(),
      locale: _getLocale(languageCode),
      scrollPercentage: scrollPercentage,
      timeSpentReadingMs: timeSpentReadingMs,
    );

    _consents.add(record);
    await _saveConsents();

    if (LegalConstants.logToServer) {
      _persistToServer([record]);
    }

    AppLogger.log('CONSENT_RECORDED -> ${documentType.key} lang=$lang');
  }

  /// Get all consent records for export/audit
  List<ConsentRecord> getAllConsents() => List.unmodifiable(_consents);

  /// Export all consents as JSON for legal/audit purposes
  String exportConsentsAsJson() {
    return const JsonEncoder.withIndent('  ').convert({
      'export_date': DateTime.now().toUtc().toIso8601String(),
      'app': 'toro_driver',
      'bundle_version': LegalConstants.legalBundleVersion,
      'total_records': _consents.length,
      'records': _consents.map((c) => c.toJson()).toList(),
    });
  }

  // ===========================================================================
  // Server persistence
  // ===========================================================================

  /// Persist consent records to Supabase
  Future<void> _persistToServer(
    List<ConsentRecord> records, {
    bool ageVerified = true,
  }) async {
    try {
      final client = Supabase.instance.client;

      for (final record in records) {
        await client.from(_supabaseTable).insert({
          'user_id': record.userId,
          'user_email': record.userEmail,
          'document_type': record.documentType,
          'document_version': record.documentVersion,
          'document_language': record.documentLanguage,
          'accepted_at': record.acceptedAt.toUtc().toIso8601String(),
          'device_id': record.deviceId,
          'platform': record.platform,
          'app_version': record.appVersion,
          'locale': record.locale,
          'scroll_percentage': record.scrollPercentage,
          'time_spent_reading_ms': record.timeSpentReadingMs,
          'age_verified': ageVerified,
          'checksum': record.checksum,
          'consent_json': record.toJson(),
        });
      }

      AppLogger.log('LEGAL_SERVER -> ${records.length} records persisted to Supabase');
    } catch (e) {
      AppLogger.log('LEGAL_SERVER -> Error persisting to server (will retry): $e');
      // Queue for retry - save failed records to SharedPreferences
      _queueForRetry(records);
    }
  }

  /// Queue failed records for retry
  Future<void> _queueForRetry(List<ConsentRecord> records) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingKey = 'legal_consents_pending_sync';
      final existing = prefs.getString(pendingKey);
      final List<dynamic> pending = existing != null ? jsonDecode(existing) : [];
      for (final r in records) {
        pending.add(r.toJson());
      }
      await prefs.setString(pendingKey, jsonEncode(pending));
      AppLogger.log('LEGAL_SERVER -> ${records.length} records queued for retry');
    } catch (e) {
      AppLogger.log('LEGAL_SERVER -> Error queuing for retry: $e');
    }
  }

  /// Retry syncing pending consent records to server
  Future<void> syncPendingConsents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingKey = 'legal_consents_pending_sync';
      final existing = prefs.getString(pendingKey);
      if (existing == null) return;

      final List<dynamic> pending = jsonDecode(existing);
      if (pending.isEmpty) return;

      final client = Supabase.instance.client;
      final synced = <int>[];

      for (var i = 0; i < pending.length; i++) {
        try {
          final json = pending[i] as Map<String, dynamic>;
          await client.from(_supabaseTable).insert({
            'user_id': json['user_id'],
            'user_email': json['user_email'],
            'document_type': json['document_type'],
            'document_version': json['document_version'],
            'document_language': json['document_language'],
            'accepted_at': json['accepted_at_utc'],
            'device_id': json['device_id'],
            'platform': json['platform'],
            'app_version': json['app_version'],
            'locale': json['acceptance_behavior']?['locale'] ?? 'unknown',
            'scroll_percentage': json['acceptance_behavior']?['scroll_percentage'] ?? 0.0,
            'time_spent_reading_ms': json['acceptance_behavior']?['time_spent_reading_ms'] ?? 0,
            'checksum': json['checksum'],
            'consent_json': json,
          });
          synced.add(i);
        } catch (e) {
          AppLogger.log('LEGAL_SERVER -> Failed to sync record $i: $e');
        }
      }

      // Remove synced records
      if (synced.isNotEmpty) {
        for (final i in synced.reversed) {
          pending.removeAt(i);
        }
        if (pending.isEmpty) {
          await prefs.remove(pendingKey);
        } else {
          await prefs.setString(pendingKey, jsonEncode(pending));
        }
        AppLogger.log('LEGAL_SERVER -> Synced ${synced.length} pending records');
      }
    } catch (e) {
      AppLogger.log('LEGAL_SERVER -> Error syncing pending: $e');
    }
  }

  // ===========================================================================
  // Private helpers
  // ===========================================================================

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
      case LegalDocumentType.driverAgreement:
        return LegalConstants.icaVersion;
      case LegalDocumentType.liabilityWaiver:
        return LegalConstants.waiverVersion;
      default:
        return '1.0';
    }
  }

  Future<String> _getDeviceId() async {
    // Use a persistent device ID from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final key = 'toro_device_id';
    var id = prefs.getString(key);
    if (id == null) {
      id = '${_getPlatform()}_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString(key, id);
    }
    return id;
  }

  String _getLocale(String languageCode) {
    final lang = languageCode.toLowerCase().split('_').first.split('-').first;
    switch (lang) {
      case 'es':
        return 'es_MX';
      case 'en':
        return 'en_US';
      default:
        return '${lang}_XX';
    }
  }

  String _getPlatform() {
    if (kIsWeb) return 'web';
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
