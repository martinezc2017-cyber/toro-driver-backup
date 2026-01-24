import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

/// Service for reporting riders and incidents
/// All reports are stored in Supabase for admin review
class ReportService {
  final SupabaseClient _client = SupabaseConfig.client;

  // Table name for driver reports
  static const String _reportsTable = 'driver_reports';

  /// Submit a report about a rider
  Future<Map<String, dynamic>> submitRiderReport({
    required String driverId,
    required String rideId,
    required String riderId,
    required String riderName,
    required String reason,
    String? details,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final response = await _client.from(_reportsTable).insert({
        'driver_id': driverId,
        'ride_id': rideId,
        'rider_id': riderId,
        'rider_name': riderName,
        'reason': reason,
        'details': details,
        'latitude': latitude,
        'longitude': longitude,
        'status': 'pending', // pending, reviewed, resolved, dismissed
        'created_at': DateTime.now().toIso8601String(),
      }).select().single();

      return response;
    } catch (e) {
      // If table doesn't exist, try creating a minimal record
      debugPrint('ReportService: Error submitting report: $e');
      rethrow;
    }
  }

  /// Get driver's report history
  Future<List<Map<String, dynamic>>> getDriverReports(String driverId) async {
    try {
      final response = await _client
          .from(_reportsTable)
          .select()
          .eq('driver_id', driverId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('ReportService: Error getting reports: $e');
      return [];
    }
  }

  /// Get report by ID
  Future<Map<String, dynamic>?> getReport(String reportId) async {
    try {
      final response = await _client
          .from(_reportsTable)
          .select()
          .eq('id', reportId)
          .maybeSingle();

      return response;
    } catch (e) {
      debugPrint('ReportService: Error getting report: $e');
      return null;
    }
  }

  /// Update report with admin response
  Future<void> updateReportStatus({
    required String reportId,
    required String status,
    String? adminNotes,
  }) async {
    await _client.from(_reportsTable).update({
      'status': status,
      'admin_notes': adminNotes,
      'reviewed_at': DateTime.now().toIso8601String(),
    }).eq('id', reportId);
  }
}

/// Report reason types
enum ReportReason {
  rude('rude', 'Rude behavior'),
  noShow('no_show', 'No show'),
  wrongAddress('wrong_address', 'Wrong address'),
  unsafe('unsafe', 'Felt unsafe'),
  intoxicated('intoxicated', 'Passenger intoxicated'),
  damage('damage', 'Damage to vehicle'),
  harassment('harassment', 'Harassment'),
  other('other', 'Other');

  final String id;
  final String label;

  const ReportReason(this.id, this.label);

  static ReportReason fromId(String id) {
    return ReportReason.values.firstWhere(
      (r) => r.id == id,
      orElse: () => ReportReason.other,
    );
  }
}
