import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../core/logging/app_logger.dart';

// =============================================================================
// Report category enum - matches report_category in the database
// =============================================================================
enum ReportCategory {
  sexualMisconduct,
  harassment,
  violence,
  threats,
  discrimination,
  substanceImpairment,
  unsafeDriving,
  fraud,
  theft,
  vehicleCondition,
  routeDeviation,
  overcharging,
  noShow,
  cancellationAbuse,
  other;

  String toDatabase() {
    switch (this) {
      case ReportCategory.sexualMisconduct:
        return 'sexual_misconduct';
      case ReportCategory.harassment:
        return 'harassment';
      case ReportCategory.violence:
        return 'violence';
      case ReportCategory.threats:
        return 'threats';
      case ReportCategory.discrimination:
        return 'discrimination';
      case ReportCategory.substanceImpairment:
        return 'substance_impairment';
      case ReportCategory.unsafeDriving:
        return 'unsafe_driving';
      case ReportCategory.fraud:
        return 'fraud';
      case ReportCategory.theft:
        return 'theft';
      case ReportCategory.vehicleCondition:
        return 'vehicle_condition';
      case ReportCategory.routeDeviation:
        return 'route_deviation';
      case ReportCategory.overcharging:
        return 'overcharging';
      case ReportCategory.noShow:
        return 'no_show';
      case ReportCategory.cancellationAbuse:
        return 'cancellation_abuse';
      case ReportCategory.other:
        return 'other';
    }
  }

  static ReportCategory fromDatabase(String value) {
    switch (value) {
      case 'sexual_misconduct':
        return ReportCategory.sexualMisconduct;
      case 'harassment':
        return ReportCategory.harassment;
      case 'violence':
        return ReportCategory.violence;
      case 'threats':
        return ReportCategory.threats;
      case 'discrimination':
        return ReportCategory.discrimination;
      case 'substance_impairment':
        return ReportCategory.substanceImpairment;
      case 'unsafe_driving':
        return ReportCategory.unsafeDriving;
      case 'fraud':
        return ReportCategory.fraud;
      case 'theft':
        return ReportCategory.theft;
      case 'vehicle_condition':
        return ReportCategory.vehicleCondition;
      case 'route_deviation':
        return ReportCategory.routeDeviation;
      case 'overcharging':
        return ReportCategory.overcharging;
      case 'no_show':
        return ReportCategory.noShow;
      case 'cancellation_abuse':
        return ReportCategory.cancellationAbuse;
      default:
        return ReportCategory.other;
    }
  }

  /// Human-readable label for UI display
  String get label {
    switch (this) {
      case ReportCategory.sexualMisconduct:
        return 'Sexual Misconduct';
      case ReportCategory.harassment:
        return 'Harassment';
      case ReportCategory.violence:
        return 'Violence';
      case ReportCategory.threats:
        return 'Threats';
      case ReportCategory.discrimination:
        return 'Discrimination';
      case ReportCategory.substanceImpairment:
        return 'Substance Impairment';
      case ReportCategory.unsafeDriving:
        return 'Unsafe Driving';
      case ReportCategory.fraud:
        return 'Fraud';
      case ReportCategory.theft:
        return 'Theft';
      case ReportCategory.vehicleCondition:
        return 'Vehicle Condition';
      case ReportCategory.routeDeviation:
        return 'Route Deviation';
      case ReportCategory.overcharging:
        return 'Overcharging';
      case ReportCategory.noShow:
        return 'No Show';
      case ReportCategory.cancellationAbuse:
        return 'Cancellation Abuse';
      case ReportCategory.other:
        return 'Other';
    }
  }
}

// =============================================================================
// Report severity enum - matches report_severity in the database
// =============================================================================
enum ReportSeverity {
  low,
  medium,
  high,
  critical;

  String toDatabase() => name;

  static ReportSeverity fromDatabase(String value) {
    switch (value) {
      case 'low':
        return ReportSeverity.low;
      case 'medium':
        return ReportSeverity.medium;
      case 'high':
        return ReportSeverity.high;
      case 'critical':
        return ReportSeverity.critical;
      default:
        return ReportSeverity.medium;
    }
  }

  String get label {
    switch (this) {
      case ReportSeverity.low:
        return 'Low';
      case ReportSeverity.medium:
        return 'Medium';
      case ReportSeverity.high:
        return 'High';
      case ReportSeverity.critical:
        return 'Critical';
    }
  }
}

// =============================================================================
// Abuse report data model
// =============================================================================
class AbuseReport {
  final String id;
  final String reporterId;
  final String reporterRole;
  final String? reporterName;
  final String? reportedUserId;
  final String? reportedUserRole;
  final String? reportedUserName;
  final String? rideId;
  final String? rideType;
  final ReportCategory category;
  final ReportSeverity severity;
  final String status;
  final String? title;
  final String description;
  final List<String> evidenceUrls;
  final double? incidentLatitude;
  final double? incidentLongitude;
  final String? incidentAddress;
  final DateTime? incidentAt;
  final String? adminNotes;
  final String? resolutionSummary;
  final bool hasAppeal;
  final String appName;
  final DateTime createdAt;
  final DateTime? updatedAt;

  AbuseReport({
    required this.id,
    required this.reporterId,
    required this.reporterRole,
    this.reporterName,
    this.reportedUserId,
    this.reportedUserRole,
    this.reportedUserName,
    this.rideId,
    this.rideType,
    required this.category,
    required this.severity,
    required this.status,
    this.title,
    required this.description,
    this.evidenceUrls = const [],
    this.incidentLatitude,
    this.incidentLongitude,
    this.incidentAddress,
    this.incidentAt,
    this.adminNotes,
    this.resolutionSummary,
    this.hasAppeal = false,
    this.appName = 'toro_driver',
    required this.createdAt,
    this.updatedAt,
  });

  factory AbuseReport.fromJson(Map<String, dynamic> json) {
    return AbuseReport(
      id: json['id'] as String,
      reporterId: json['reporter_id'] as String,
      reporterRole: json['reporter_role'] as String? ?? 'driver',
      reporterName: json['reporter_name'] as String?,
      reportedUserId: json['reported_user_id'] as String?,
      reportedUserRole: json['reported_user_role'] as String?,
      reportedUserName: json['reported_user_name'] as String?,
      rideId: json['ride_id'] as String?,
      rideType: json['ride_type'] as String?,
      category: ReportCategory.fromDatabase(json['category'] as String? ?? 'other'),
      severity: ReportSeverity.fromDatabase(json['severity'] as String? ?? 'medium'),
      status: json['status'] as String? ?? 'pending',
      title: json['title'] as String?,
      description: json['description'] as String? ?? '',
      evidenceUrls: _parseStringList(json['evidence_urls']),
      incidentLatitude: (json['incident_latitude'] as num?)?.toDouble(),
      incidentLongitude: (json['incident_longitude'] as num?)?.toDouble(),
      incidentAddress: json['incident_address'] as String?,
      incidentAt: json['incident_at'] != null
          ? DateTime.tryParse(json['incident_at'] as String)
          : null,
      adminNotes: json['admin_notes'] as String?,
      resolutionSummary: json['resolution_summary'] as String?,
      hasAppeal: json['has_appeal'] as bool? ?? false,
      appName: json['app_name'] as String? ?? 'toro_driver',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  static List<String> _parseStringList(dynamic value) {
    if (value == null) return [];
    if (value is List) return value.map((e) => e.toString()).toList();
    return [];
  }
}

// =============================================================================
// Appeal data model
// =============================================================================
class ReportAppeal {
  final String id;
  final String reportId;
  final String appellantId;
  final String appellantRole;
  final String reason;
  final List<String> evidenceUrls;
  final String? counterDescription;
  final String status;
  final String? reviewNotes;
  final DateTime createdAt;
  final DateTime? reviewedAt;

  ReportAppeal({
    required this.id,
    required this.reportId,
    required this.appellantId,
    required this.appellantRole,
    required this.reason,
    this.evidenceUrls = const [],
    this.counterDescription,
    required this.status,
    this.reviewNotes,
    required this.createdAt,
    this.reviewedAt,
  });

  factory ReportAppeal.fromJson(Map<String, dynamic> json) {
    return ReportAppeal(
      id: json['id'] as String,
      reportId: json['report_id'] as String,
      appellantId: json['appellant_id'] as String,
      appellantRole: json['appellant_role'] as String? ?? 'driver',
      reason: json['reason'] as String? ?? '',
      evidenceUrls: AbuseReport._parseStringList(json['evidence_urls']),
      counterDescription: json['counter_description'] as String?,
      status: json['status'] as String? ?? 'pending',
      reviewNotes: json['review_notes'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.tryParse(json['reviewed_at'] as String)
          : null,
    );
  }
}

// =============================================================================
// User safety score data model
// =============================================================================
class UserSafetyScore {
  final String userId;
  final String role;
  final int score;
  final int totalReportsFiled;
  final int totalReportsReceived;
  final int totalReportsDismissed;
  final int totalWarnings;
  final int totalSuspensions;
  final bool isFlagged;
  final String? flagReason;
  final DateTime? lastIncidentAt;
  final DateTime? lastReviewedAt;

  UserSafetyScore({
    required this.userId,
    required this.role,
    required this.score,
    this.totalReportsFiled = 0,
    this.totalReportsReceived = 0,
    this.totalReportsDismissed = 0,
    this.totalWarnings = 0,
    this.totalSuspensions = 0,
    this.isFlagged = false,
    this.flagReason,
    this.lastIncidentAt,
    this.lastReviewedAt,
  });

  factory UserSafetyScore.fromJson(Map<String, dynamic> json) {
    return UserSafetyScore(
      userId: json['user_id'] as String,
      role: json['role'] as String? ?? 'driver',
      score: json['score'] as int? ?? 100,
      totalReportsFiled: json['total_reports_filed'] as int? ?? 0,
      totalReportsReceived: json['total_reports_received'] as int? ?? 0,
      totalReportsDismissed: json['total_reports_dismissed'] as int? ?? 0,
      totalWarnings: json['total_warnings'] as int? ?? 0,
      totalSuspensions: json['total_suspensions'] as int? ?? 0,
      isFlagged: json['is_flagged'] as bool? ?? false,
      flagReason: json['flag_reason'] as String?,
      lastIncidentAt: json['last_incident_at'] != null
          ? DateTime.tryParse(json['last_incident_at'] as String)
          : null,
      lastReviewedAt: json['last_reviewed_at'] != null
          ? DateTime.tryParse(json['last_reviewed_at'] as String)
          : null,
    );
  }

  /// Whether the score is considered healthy (above 70)
  bool get isHealthy => score > 70;

  /// Whether the score is in warning range (50-70)
  bool get isWarning => score > 50 && score <= 70;

  /// Whether the score is critical (50 or below)
  bool get isCritical => score <= 50;
}

// =============================================================================
// ABUSE REPORT SERVICE
// Handles general abuse reporting for the TORO DRIVER app.
// Reports go to the `abuse_reports` table in Supabase.
// Appeals go to the `report_appeals` table.
// Safety scores read from the `user_safety_scores` table.
// =============================================================================
class AbuseReportService {
  final SupabaseClient _client = SupabaseConfig.client;

  static const String _reportsTable = 'abuse_reports';
  static const String _appealsTable = 'report_appeals';
  static const String _safetyScoresTable = 'user_safety_scores';
  static const String _appName = 'toro_driver';

  /// Get the current authenticated driver's user ID.
  /// Returns null if not authenticated.
  String? get _currentUserId => _client.auth.currentUser?.id;

  // ===========================================================================
  // SUBMIT REPORT
  // Inserts a new abuse report into the `abuse_reports` table.
  // The reporter_role is always 'driver' since this is the driver app.
  // ===========================================================================

  /// Submit an abuse report against a rider or other user.
  ///
  /// [rideId] - The ride/delivery/booking associated with the incident.
  /// [rideType] - 'ride', 'carpool', 'delivery', 'tourism', or 'bus'.
  /// [reportedUserId] - The UUID of the user being reported.
  /// [category] - The category of the abuse (from ReportCategory enum).
  /// [severity] - The severity level (from ReportSeverity enum).
  /// [description] - Detailed description of the incident.
  /// [evidenceUrls] - Optional list of URLs to evidence (photos, screenshots).
  /// [incidentLatitude] - Optional latitude where the incident occurred.
  /// [incidentLongitude] - Optional longitude where the incident occurred.
  /// [incidentAddress] - Optional address where the incident occurred.
  /// [incidentAt] - Optional timestamp of when the incident occurred.
  /// [title] - Optional short title for the report.
  /// [reportedUserName] - Optional name of the reported user for reference.
  ///
  /// Returns the created [AbuseReport] on success.
  /// Throws an exception if the user is not authenticated or the insert fails.
  Future<AbuseReport> submitReport({
    String? rideId,
    String? rideType,
    required String reportedUserId,
    required ReportCategory category,
    required ReportSeverity severity,
    required String description,
    List<String>? evidenceUrls,
    double? incidentLatitude,
    double? incidentLongitude,
    String? incidentAddress,
    DateTime? incidentAt,
    String? title,
    String? reportedUserName,
    // Reporter context fields
    String? reporterName,
    String? reporterEmail,
    String? reporterPhone,
    // GPS/context data (JSONB)
    Map<String, dynamic>? gpsData,
  }) async {
    final userId = _currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated. Cannot submit abuse report.');
    }

    AppLogger.log('AbuseReportService: Submitting report - '
        'category=${category.toDatabase()}, severity=${severity.toDatabase()}, '
        'ride=$rideId, reported_user=$reportedUserId');

    try {
      final data = <String, dynamic>{
        'reporter_id': userId,
        'reporter_role': 'driver',
        'reporter_name': reporterName,
        'reporter_email': reporterEmail,
        'reporter_phone': reporterPhone,
        'reported_user_id': reportedUserId,
        'reported_user_role': 'rider',
        'reported_user_name': reportedUserName,
        'ride_id': rideId,
        'ride_type': rideType,
        'category': category.toDatabase(),
        'severity': severity.toDatabase(),
        'description': description,
        'evidence_urls': evidenceUrls ?? [],
        'incident_latitude': incidentLatitude,
        'incident_longitude': incidentLongitude,
        'incident_address': incidentAddress,
        'incident_at': incidentAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
        'title': title,
        'app_name': _appName,
        'gps_data': gpsData,
      };

      // Remove null values to avoid overwriting defaults in the database
      data.removeWhere((key, value) => value == null);

      final response = await _client
          .from(_reportsTable)
          .insert(data)
          .select()
          .single();

      final report = AbuseReport.fromJson(response);
      AppLogger.log('AbuseReportService: Report submitted successfully - id=${report.id}');
      return report;
    } catch (e, stackTrace) {
      AppLogger.error('AbuseReportService: Failed to submit report', e, stackTrace);
      rethrow;
    }
  }

  // ===========================================================================
  // SUBMIT APPEAL
  // Inserts an appeal into the `report_appeals` table.
  // Used when a driver receives a report and wants to contest it.
  // ===========================================================================

  /// Submit an appeal against a report filed against the current driver.
  ///
  /// [reportId] - The UUID of the report being appealed.
  /// [reason] - The reason for the appeal.
  /// [counterDescription] - Optional detailed counter-description of events.
  /// [evidenceUrls] - Optional list of URLs to supporting evidence.
  ///
  /// Returns the created [ReportAppeal] on success.
  /// Throws an exception if the user is not authenticated or the insert fails.
  Future<ReportAppeal> submitAppeal({
    required String reportId,
    required String reason,
    String? counterDescription,
    List<String>? evidenceUrls,
  }) async {
    final userId = _currentUserId;
    if (userId == null) {
      throw Exception('User not authenticated. Cannot submit appeal.');
    }

    AppLogger.log('AbuseReportService: Submitting appeal for report=$reportId');

    try {
      final data = <String, dynamic>{
        'report_id': reportId,
        'appellant_id': userId,
        'appellant_role': 'driver',
        'reason': reason,
        'evidence_urls': evidenceUrls ?? [],
      };

      if (counterDescription != null && counterDescription.isNotEmpty) {
        data['counter_description'] = counterDescription;
      }

      final response = await _client
          .from(_appealsTable)
          .insert(data)
          .select()
          .single();

      // Also update the original report to mark it as having an appeal
      try {
        await _client
            .from(_reportsTable)
            .update({
              'has_appeal': true,
              'status': 'appealed',
            })
            .eq('id', reportId);
      } catch (e) {
        // Non-critical: RLS may prevent the driver from updating the report
        // The admin backend should handle status transitions
        AppLogger.log('AbuseReportService: Could not update report status to appealed '
            '(may require admin privileges): $e');
      }

      final appeal = ReportAppeal.fromJson(response);
      AppLogger.log('AbuseReportService: Appeal submitted successfully - id=${appeal.id}');
      return appeal;
    } catch (e, stackTrace) {
      AppLogger.error('AbuseReportService: Failed to submit appeal', e, stackTrace);
      rethrow;
    }
  }

  // ===========================================================================
  // GET MY FILED REPORTS
  // Retrieves reports that the current driver has filed.
  // ===========================================================================

  /// Get all abuse reports filed by the current driver.
  ///
  /// [limit] - Maximum number of reports to return (default 50).
  /// [offset] - Number of reports to skip for pagination (default 0).
  ///
  /// Returns a list of [AbuseReport] filed by the current driver.
  /// Returns an empty list if the user is not authenticated or on error.
  Future<List<AbuseReport>> getMyFiledReports({
    int limit = 50,
    int offset = 0,
  }) async {
    final userId = _currentUserId;
    if (userId == null) {
      AppLogger.log('AbuseReportService: Cannot get filed reports - not authenticated');
      return [];
    }

    AppLogger.log('AbuseReportService: Fetching filed reports for driver=$userId');

    try {
      final response = await _client
          .from(_reportsTable)
          .select()
          .eq('reporter_id', userId)
          .eq('app_name', _appName)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      final reports = (response as List)
          .map((json) => AbuseReport.fromJson(json as Map<String, dynamic>))
          .toList();

      AppLogger.log('AbuseReportService: Found ${reports.length} filed reports');
      return reports;
    } catch (e, stackTrace) {
      AppLogger.error('AbuseReportService: Failed to fetch filed reports', e, stackTrace);
      return [];
    }
  }

  // ===========================================================================
  // GET REPORTS AGAINST ME
  // Retrieves reports filed against the current driver.
  // ===========================================================================

  /// Get all abuse reports filed against the current driver.
  ///
  /// [limit] - Maximum number of reports to return (default 50).
  /// [offset] - Number of reports to skip for pagination (default 0).
  ///
  /// Returns a list of [AbuseReport] where the driver is the reported user.
  /// Returns an empty list if the user is not authenticated or on error.
  Future<List<AbuseReport>> getReportsAgainstMe({
    int limit = 50,
    int offset = 0,
  }) async {
    final userId = _currentUserId;
    if (userId == null) {
      AppLogger.log('AbuseReportService: Cannot get reports against me - not authenticated');
      return [];
    }

    AppLogger.log('AbuseReportService: Fetching reports against driver=$userId');

    try {
      final response = await _client
          .from(_reportsTable)
          .select()
          .eq('reported_user_id', userId)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      final reports = (response as List)
          .map((json) => AbuseReport.fromJson(json as Map<String, dynamic>))
          .toList();

      AppLogger.log('AbuseReportService: Found ${reports.length} reports against me');
      return reports;
    } catch (e, stackTrace) {
      AppLogger.error('AbuseReportService: Failed to fetch reports against me', e, stackTrace);
      return [];
    }
  }

  // ===========================================================================
  // GET MY SAFETY SCORE
  // Reads the driver's safety score from `user_safety_scores`.
  // ===========================================================================

  /// Get the current driver's safety score.
  ///
  /// Returns a [UserSafetyScore] with the driver's cumulative safety data.
  /// Returns null if the user is not authenticated, has no score yet, or on error.
  Future<UserSafetyScore?> getMySafetyScore() async {
    final userId = _currentUserId;
    if (userId == null) {
      AppLogger.log('AbuseReportService: Cannot get safety score - not authenticated');
      return null;
    }

    AppLogger.log('AbuseReportService: Fetching safety score for driver=$userId');

    try {
      final response = await _client
          .from(_safetyScoresTable)
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) {
        AppLogger.log('AbuseReportService: No safety score found for driver (new user)');
        return null;
      }

      final score = UserSafetyScore.fromJson(response);
      AppLogger.log('AbuseReportService: Safety score=${score.score}, '
          'flagged=${score.isFlagged}');
      return score;
    } catch (e, stackTrace) {
      AppLogger.error('AbuseReportService: Failed to fetch safety score', e, stackTrace);
      return null;
    }
  }

  // ===========================================================================
  // HELPER: GET REPORT BY ID
  // ===========================================================================

  /// Get a single abuse report by its ID.
  ///
  /// Returns the [AbuseReport] if found and accessible, null otherwise.
  Future<AbuseReport?> getReportById(String reportId) async {
    try {
      final response = await _client
          .from(_reportsTable)
          .select()
          .eq('id', reportId)
          .maybeSingle();

      if (response == null) return null;
      return AbuseReport.fromJson(response);
    } catch (e, stackTrace) {
      AppLogger.error('AbuseReportService: Failed to fetch report $reportId', e, stackTrace);
      return null;
    }
  }

  // ===========================================================================
  // HELPER: GET APPEALS FOR A REPORT
  // ===========================================================================

  /// Get all appeals for a specific report.
  ///
  /// Returns a list of [ReportAppeal] for the given report.
  Future<List<ReportAppeal>> getAppealsForReport(String reportId) async {
    try {
      final response = await _client
          .from(_appealsTable)
          .select()
          .eq('report_id', reportId)
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) => ReportAppeal.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e, stackTrace) {
      AppLogger.error('AbuseReportService: Failed to fetch appeals for report $reportId', e, stackTrace);
      return [];
    }
  }

  // ===========================================================================
  // HELPER: GET MY APPEALS
  // ===========================================================================

  /// Get all appeals submitted by the current driver.
  ///
  /// Returns a list of [ReportAppeal] filed by the current driver.
  Future<List<ReportAppeal>> getMyAppeals() async {
    final userId = _currentUserId;
    if (userId == null) return [];

    try {
      final response = await _client
          .from(_appealsTable)
          .select()
          .eq('appellant_id', userId)
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) => ReportAppeal.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e, stackTrace) {
      AppLogger.error('AbuseReportService: Failed to fetch my appeals', e, stackTrace);
      return [];
    }
  }

  // ===========================================================================
  // HELPER: COUNT PENDING REPORTS AGAINST ME
  // Useful for showing badge counts in the UI.
  // ===========================================================================

  /// Get the count of unresolved reports filed against the current driver.
  ///
  /// Returns the count of reports with status 'pending', 'under_review',
  /// or 'investigating'. Returns 0 on error or if not authenticated.
  Future<int> getPendingReportsAgainstMeCount() async {
    final userId = _currentUserId;
    if (userId == null) return 0;

    try {
      final response = await _client
          .from(_reportsTable)
          .select('id')
          .eq('reported_user_id', userId)
          .inFilter('status', ['pending', 'under_review', 'investigating']);

      return (response as List).length;
    } catch (e) {
      AppLogger.error('AbuseReportService: Failed to count pending reports', e);
      return 0;
    }
  }
}
