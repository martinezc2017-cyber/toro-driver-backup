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
  static const String termsVersion = '1.0';

  /// Current Privacy Policy version
  static const String privacyVersion = '1.0';

  /// Current Liability Waiver version
  static const String waiverVersion = '1.0';

  /// Current Damage Policy version
  static const String damageVersion = '1.0';

  /// Current Recording Consent version
  static const String recordingVersion = '1.0';

  /// Combined legal bundle version (for quick checking)
  static const String legalBundleVersion = '2025.01.01.1';

  // ============================================================================
  // LEGAL ENTITY INFORMATION
  // ============================================================================

  static const String companyName = 'TORO DRIVER';
  static const String companyLegalName = 'TORO DRIVER LLC';
  static const String companyJurisdiction = 'State of Delaware, United States';
  static const String companyEmail = 'legal@toro-ride.com';
  static const String privacyEmail = 'privacy@toro-ride.com';
  static const String supportEmail = 'drivers@toro-ride.com';

  // ============================================================================
  // CONSENT REQUIREMENTS
  // ============================================================================

  /// Minimum scroll percentage required before allowing acceptance
  static const double minScrollPercentage = 0.95;

  /// Whether to require separate acceptance for each document
  static const bool requireSeparateAcceptance = false;

  /// Whether to log acceptance to remote server
  static const bool logToServer = true;

  /// Days before prompting user to review updated terms (0 = immediate)
  static const int gracePeriodDays = 0;
}
