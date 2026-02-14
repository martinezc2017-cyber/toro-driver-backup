// Legal document version constants and configuration for TORO DRIVER
// Update these versions whenever legal documents change
// Users who accepted older versions will be prompted to accept new versions

class LegalConstants {
  LegalConstants._();

  // ============================================================================
  // DOCUMENT VERSIONS - INCREMENT WHEN CONTENT CHANGES
  // ============================================================================

  /// Current Terms and Conditions version
  /// Format: MAJOR.MINOR (MAJOR = requires re-acceptance, MINOR = informational)
  static const String termsVersion = '2.0';

  /// Current Privacy Policy version
  static const String privacyVersion = '2.0';

  /// Current Independent Contractor Agreement version
  static const String icaVersion = '2.0';

  /// Current Liability Waiver version
  static const String waiverVersion = '2.0';

  /// Current Safety Policy version
  static const String safetyVersion = '2.0';

  /// Current Background Check Consent version
  static const String backgroundCheckVersion = '1.0';

  /// Current Damage Policy version
  static const String damageVersion = '1.0';

  /// Current Recording Consent version
  static const String recordingVersion = '1.0';

  /// Mexico addendum version
  static const String mexicoAddendumVersion = '1.0';

  /// Combined legal bundle version (for quick checking)
  static const String legalBundleVersion = '2026.02.09.1';

  // ============================================================================
  // LEGAL ENTITY INFORMATION
  // ============================================================================

  static const String companyName = 'TORO DRIVER';
  static const String companyLegalName = 'TORO DRIVER LLC';
  static const String companyJurisdiction = 'State of Delaware, United States';
  static const String companyEmail = 'legal@toro-ride.com';
  static const String privacyEmail = 'privacy@toro-ride.com';
  static const String supportEmail = 'drivers@toro-ride.com';
  static const String safetyEmail = 'safety@toro-ride.com';

  // ============================================================================
  // CONSENT REQUIREMENTS
  // ============================================================================

  /// Minimum scroll percentage required before allowing acceptance
  static const double minScrollPercentage = 0.75;

  /// Whether to require separate acceptance for each document
  static const bool requireSeparateAcceptance = false;

  /// Whether to log acceptance to remote server (Supabase)
  static const bool logToServer = true;

  /// Days before prompting user to review updated terms (0 = immediate)
  static const int gracePeriodDays = 0;

  /// SharedPreferences key for terms accepted with language
  static const String termsAcceptedKey = 'toro_driver_terms_accepted_v2';

  /// SharedPreferences key for the language used at acceptance
  static const String termsLanguageKey = 'toro_driver_terms_language';

  /// SharedPreferences key for the version accepted
  static const String termsVersionKey = 'toro_driver_terms_version_accepted';

  // ============================================================================
  // SUPPORTED LEGAL LANGUAGES
  // ============================================================================

  static const List<String> supportedLegalLanguages = ['en', 'es'];
}
