import 'dart:convert';

/// Complete immutable record of a driver's legal consent
/// Contains ALL data required for legal evidence and audit trails
/// This record can be presented in court as proof of driver acceptance
class ConsentRecord {
  // Document identification
  final String documentType;
  final String documentVersion;
  final String documentLanguage;

  // Timestamp information
  final DateTime acceptedAt;
  final String acceptedAtIso;
  final String acceptedAtLocal;
  final String timezone;

  // User identification
  final String userId;
  final String? userEmail;
  final String? userPhone;
  final String? userName;
  final String? userAddress;

  // Device information
  final String deviceId;
  final String deviceModel;
  final String deviceManufacturer;
  final String osVersion;
  final String appVersion;
  final String platform;

  // Network information
  final String ipAddress;
  final String? networkType;
  final String? carrier;

  // Location information (at time of acceptance)
  final double? latitude;
  final double? longitude;
  final String? city;
  final String? state;
  final String? country;
  final String? postalCode;

  // Acceptance behavior metrics
  final String locale;
  final double scrollPercentage;
  final int timeSpentReadingMs;
  final int totalScrollEvents;
  final bool readTermsSection;
  final bool readPrivacySection;
  final bool readWaiverSection;
  final bool readRecordingSection;
  final bool readDamageSection;

  // Specific consents granted
  final bool consentedToTerms;
  final bool consentedToPrivacy;
  final bool consentedToWaiver;
  final bool consentedToLocationTracking;
  final bool consentedToVoiceRecording;
  final bool consentedToVideoRecording;
  final bool consentedToDataSharing;
  final bool consentedToDamagePolicy;
  final bool consentedToArbitration;

  // State-specific recording consent
  final String? userState;
  final bool isTwoPartyConsentState;
  final bool explicitRecordingConsent;

  // Legal checksums and verification
  final String checksum;
  final String documentHash;

  ConsentRecord({
    required this.documentType,
    required this.documentVersion,
    this.documentLanguage = 'en',
    required this.acceptedAt,
    required this.userId,
    this.userEmail,
    this.userPhone,
    this.userName,
    this.userAddress,
    required this.deviceId,
    this.deviceModel = 'unknown',
    this.deviceManufacturer = 'unknown',
    this.osVersion = 'unknown',
    required this.appVersion,
    required this.platform,
    this.ipAddress = 'unknown',
    this.networkType,
    this.carrier,
    this.latitude,
    this.longitude,
    this.city,
    this.state,
    this.country,
    this.postalCode,
    required this.locale,
    required this.scrollPercentage,
    required this.timeSpentReadingMs,
    this.totalScrollEvents = 0,
    this.readTermsSection = true,
    this.readPrivacySection = true,
    this.readWaiverSection = true,
    this.readRecordingSection = true,
    this.readDamageSection = true,
    this.consentedToTerms = true,
    this.consentedToPrivacy = true,
    this.consentedToWaiver = true,
    this.consentedToLocationTracking = true,
    this.consentedToVoiceRecording = false,
    this.consentedToVideoRecording = false,
    this.consentedToDataSharing = true,
    this.consentedToDamagePolicy = true,
    this.consentedToArbitration = true,
    this.userState,
    this.isTwoPartyConsentState = false,
    this.explicitRecordingConsent = false,
    this.timezone = 'UTC',
  })  : acceptedAtIso = acceptedAt.toUtc().toIso8601String(),
        acceptedAtLocal = acceptedAt.toLocal().toString(),
        checksum = _generateChecksum(
          documentType,
          documentVersion,
          acceptedAt,
          userId,
          deviceId,
        ),
        documentHash = _generateDocumentHash(documentType, documentVersion);

  static String _generateChecksum(
    String docType,
    String docVersion,
    DateTime acceptedAt,
    String userId,
    String deviceId,
  ) {
    final data = '$docType|$docVersion|${acceptedAt.millisecondsSinceEpoch}|$userId|$deviceId';
    var hash = 0;
    for (var i = 0; i < data.length; i++) {
      hash = ((hash << 5) - hash) + data.codeUnitAt(i);
      hash = hash & hash;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  static String _generateDocumentHash(String docType, String docVersion) {
    final data = '$docType|$docVersion|TORO_DRIVER_LEGAL';
    var hash = 0;
    for (var i = 0; i < data.length; i++) {
      hash = ((hash << 5) - hash) + data.codeUnitAt(i);
      hash = hash & hash;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  Map<String, dynamic> toJson() => {
        // Document info
        'document_type': documentType,
        'document_version': documentVersion,
        'document_language': documentLanguage,
        'document_hash': documentHash,

        // Timestamps
        'accepted_at_utc': acceptedAtIso,
        'accepted_at_local': acceptedAtLocal,
        'accepted_at_timestamp': acceptedAt.millisecondsSinceEpoch,
        'timezone': timezone,

        // User identification
        'user_id': userId,
        'user_email': userEmail,
        'user_phone': userPhone,
        'user_name': userName,
        'user_address': userAddress,

        // Device info
        'device_id': deviceId,
        'device_model': deviceModel,
        'device_manufacturer': deviceManufacturer,
        'os_version': osVersion,
        'app_version': appVersion,
        'platform': platform,

        // Network info
        'ip_address': ipAddress,
        'network_type': networkType,
        'carrier': carrier,

        // Location at acceptance
        'location': {
          'latitude': latitude,
          'longitude': longitude,
          'city': city,
          'state': state,
          'country': country,
          'postal_code': postalCode,
        },

        // Behavior metrics
        'acceptance_behavior': {
          'locale': locale,
          'scroll_percentage': scrollPercentage,
          'time_spent_reading_ms': timeSpentReadingMs,
          'total_scroll_events': totalScrollEvents,
          'sections_read': {
            'terms': readTermsSection,
            'privacy': readPrivacySection,
            'waiver': readWaiverSection,
            'recording': readRecordingSection,
            'damage': readDamageSection,
          },
        },

        // Specific consents
        'consents_granted': {
          'terms_and_conditions': consentedToTerms,
          'privacy_policy': consentedToPrivacy,
          'liability_waiver': consentedToWaiver,
          'location_tracking': consentedToLocationTracking,
          'voice_recording': consentedToVoiceRecording,
          'video_recording': consentedToVideoRecording,
          'data_sharing': consentedToDataSharing,
          'damage_policy': consentedToDamagePolicy,
          'arbitration_agreement': consentedToArbitration,
        },

        // State-specific recording consent
        'recording_consent': {
          'user_state': userState,
          'is_two_party_consent_state': isTwoPartyConsentState,
          'explicit_recording_consent': explicitRecordingConsent,
        },

        // Verification
        'checksum': checksum,
      };

  factory ConsentRecord.fromJson(Map<String, dynamic> json) {
    final location = json['location'] as Map<String, dynamic>? ?? {};
    final behavior = json['acceptance_behavior'] as Map<String, dynamic>? ?? {};
    final sectionsRead = behavior['sections_read'] as Map<String, dynamic>? ?? {};
    final consents = json['consents_granted'] as Map<String, dynamic>? ?? {};
    final recording = json['recording_consent'] as Map<String, dynamic>? ?? {};

    return ConsentRecord(
      documentType: json['document_type'] as String,
      documentVersion: json['document_version'] as String,
      documentLanguage: json['document_language'] as String? ?? 'en',
      acceptedAt: DateTime.fromMillisecondsSinceEpoch(json['accepted_at_timestamp'] as int),
      userId: json['user_id'] as String,
      userEmail: json['user_email'] as String?,
      userPhone: json['user_phone'] as String?,
      userName: json['user_name'] as String?,
      userAddress: json['user_address'] as String?,
      deviceId: json['device_id'] as String,
      deviceModel: json['device_model'] as String? ?? 'unknown',
      deviceManufacturer: json['device_manufacturer'] as String? ?? 'unknown',
      osVersion: json['os_version'] as String? ?? 'unknown',
      appVersion: json['app_version'] as String,
      platform: json['platform'] as String,
      ipAddress: json['ip_address'] as String? ?? 'unknown',
      networkType: json['network_type'] as String?,
      carrier: json['carrier'] as String?,
      latitude: (location['latitude'] as num?)?.toDouble(),
      longitude: (location['longitude'] as num?)?.toDouble(),
      city: location['city'] as String?,
      state: location['state'] as String?,
      country: location['country'] as String?,
      postalCode: location['postal_code'] as String?,
      locale: behavior['locale'] as String? ?? 'en_US',
      scrollPercentage: (behavior['scroll_percentage'] as num?)?.toDouble() ?? 1.0,
      timeSpentReadingMs: behavior['time_spent_reading_ms'] as int? ?? 0,
      totalScrollEvents: behavior['total_scroll_events'] as int? ?? 0,
      readTermsSection: sectionsRead['terms'] as bool? ?? true,
      readPrivacySection: sectionsRead['privacy'] as bool? ?? true,
      readWaiverSection: sectionsRead['waiver'] as bool? ?? true,
      readRecordingSection: sectionsRead['recording'] as bool? ?? true,
      readDamageSection: sectionsRead['damage'] as bool? ?? true,
      consentedToTerms: consents['terms_and_conditions'] as bool? ?? true,
      consentedToPrivacy: consents['privacy_policy'] as bool? ?? true,
      consentedToWaiver: consents['liability_waiver'] as bool? ?? true,
      consentedToLocationTracking: consents['location_tracking'] as bool? ?? true,
      consentedToVoiceRecording: consents['voice_recording'] as bool? ?? false,
      consentedToVideoRecording: consents['video_recording'] as bool? ?? false,
      consentedToDataSharing: consents['data_sharing'] as bool? ?? true,
      consentedToDamagePolicy: consents['damage_policy'] as bool? ?? true,
      consentedToArbitration: consents['arbitration_agreement'] as bool? ?? true,
      userState: recording['user_state'] as String?,
      isTwoPartyConsentState: recording['is_two_party_consent_state'] as bool? ?? false,
      explicitRecordingConsent: recording['explicit_recording_consent'] as bool? ?? false,
      timezone: json['timezone'] as String? ?? 'UTC',
    );
  }

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  @override
  String toString() =>
      'ConsentRecord(type: $documentType v$documentVersion, user: $userId, at: $acceptedAtIso, state: $userState)';
}

/// Types of legal documents
enum LegalDocumentType {
  termsAndConditions('terms_and_conditions', 'Terms and Conditions', 'Terminos y Condiciones'),
  privacyPolicy('privacy_policy', 'Privacy Policy', 'Politica de Privacidad'),
  liabilityWaiver('liability_waiver', 'Liability Waiver', 'Exoneracion de Responsabilidad'),
  damagePolicy('damage_policy', 'Damage Policy', 'Politica de Danos'),
  recordingConsent('recording_consent', 'Recording Consent', 'Consentimiento de Grabacion'),
  dataProcessing('data_processing', 'Data Processing', 'Procesamiento de Datos'),
  locationConsent('location_consent', 'Location Consent', 'Consentimiento de Ubicacion'),
  arbitrationAgreement('arbitration_agreement', 'Arbitration Agreement', 'Acuerdo de Arbitraje'),
  driverAgreement('driver_agreement', 'Driver Agreement', 'Acuerdo del Conductor'),
  backgroundCheck('background_check', 'Background Check Consent', 'Consentimiento de Verificacion');

  final String key;
  final String displayNameEn;
  final String displayNameEs;

  const LegalDocumentType(this.key, this.displayNameEn, this.displayNameEs);

  String getDisplayName(String languageCode) {
    return languageCode == 'es' ? displayNameEs : displayNameEn;
  }
}

/// US States that require two-party consent for recording
class TwoPartyConsentStates {
  TwoPartyConsentStates._();

  static const List<String> states = [
    'CA', 'CT', 'FL', 'IL', 'MD', 'MA', 'MI', 'MT', 'NV', 'NH', 'PA', 'WA',
  ];

  static const Map<String, String> stateNames = {
    'CA': 'California',
    'CT': 'Connecticut',
    'FL': 'Florida',
    'IL': 'Illinois',
    'MD': 'Maryland',
    'MA': 'Massachusetts',
    'MI': 'Michigan',
    'MT': 'Montana',
    'NV': 'Nevada',
    'NH': 'New Hampshire',
    'PA': 'Pennsylvania',
    'WA': 'Washington',
  };

  static bool isTwoPartyState(String stateCode) {
    return states.contains(stateCode.toUpperCase());
  }

  static String? getStateName(String stateCode) {
    return stateNames[stateCode.toUpperCase()];
  }
}
