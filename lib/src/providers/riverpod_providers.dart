import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/driver_service.dart';
import '../services/statement_export_service.dart';

/// Provider for DriverService - used for data access
final driverServiceProvider = Provider<DriverService>((ref) {
  return DriverService();
});

/// Provider for StatementExportService - PDF generation
final statementExportServiceProvider = Provider<StatementExportService>((ref) {
  return StatementExportService.instance;
});
