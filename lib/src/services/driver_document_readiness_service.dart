import '../config/supabase_config.dart';
import '../models/driver_document_readiness.dart';

/// Shared source for the Home summary and the document center.
/// A failed check is deliberately propagated instead of implying completion.
class DriverDocumentReadinessService {
  static final instance = DriverDocumentReadinessService();

  final Future<dynamic> Function(String driverId) _fetch;
  int _revision = 0;
  int get revision => _revision;
  void invalidate() => _revision++;

  DriverDocumentReadinessService({
    Future<dynamic> Function(String driverId)? fetch,
  }) : _fetch = fetch ?? _fetchFromServer;

  static Future<dynamic> _fetchFromServer(String driverId) =>
      SupabaseConfig.client.rpc(
        'estado_documentos_conductor',
        params: {'p_driver_id': driverId},
      );

  Future<DriverDocumentReadiness> load(String driverId) async {
    if (driverId.trim().isEmpty) {
      throw ArgumentError.value(driverId, 'driverId', 'Driver ID is required');
    }
    return DriverDocumentReadiness.fromJson(await _fetch(driverId));
  }
}
