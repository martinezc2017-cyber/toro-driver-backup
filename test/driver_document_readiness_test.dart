import 'package:flutter_test/flutter_test.dart';
import 'package:toro_driver/src/models/driver_document_readiness.dart';
import 'package:toro_driver/src/services/driver_document_readiness_service.dart';

void main() {
  test('US accounts surface a country mismatch without dropping server blockers', () {
    final status = DriverDocumentReadiness.fromJson({
      'faltantes': ['rfc_constancia', 'driver_license'],
      'vencidos': ['ine'],
    });
    expect(status.hasCountryMismatch('US'), isTrue);
    expect(status.hasCountryMismatch('MX'), isFalse);
    expect(status.hasRequiredDocuments, isFalse);
    expect(status.outstandingCount, 3);
    final us = DriverDocumentReadiness.fromJson({'faltantes': ['driver_license']});
    expect(us.hasCountryMismatch('US'), isFalse);
  });

  test('expiry alone keeps documents incomplete', () {
    final status = DriverDocumentReadiness.fromJson({
      'faltantes': <String>[],
      'vencidos': ['seguro'],
    });
    expect(status.hasRequiredDocuments, isFalse);
    expect(status.outstandingCount, 1);
  });

  test('deduplicates requirements without losing a server requirement', () {
    final status = DriverDocumentReadiness.fromJson({
      'faltantes': ['rfc_constancia', 'licencia', 'licencia'],
      'vencidos': ['licencia'],
    });
    expect(status.missing, ['rfc_constancia', 'licencia']);
    expect(status.expired, ['licencia']);
    expect(status.outstandingCount, 2);
  });

  test('only a valid empty server result means documents are complete', () {
    expect(
      DriverDocumentReadiness.fromJson({
        'faltantes': <String>[],
        'vencidos': <String>[],
      }).hasRequiredDocuments,
      isTrue,
    );
    for (final payload in <dynamic>[
      null,
      <dynamic>[],
      <String, dynamic>{},
      {'faltantes': 'licencia'},
      {'faltantes': [null]},
      {'faltantes': [' ']},
      {'faltantes': <String>[], 'vencidos': 'seguro'},
    ]) {
      expect(
        () => DriverDocumentReadiness.fromJson(payload),
        throwsFormatException,
      );
    }
  });

  test('refresh fetches new server status and preserves the driver ID', () async {
    var calls = 0;
    final service = DriverDocumentReadinessService(fetch: (driverId) async {
      expect(driverId, 'driver-123');
      calls++;
      return {
        'faltantes': calls == 1 ? ['licencia'] : <String>[],
        'vencidos': <String>[],
      };
    });
    expect((await service.load('driver-123')).hasRequiredDocuments, isFalse);
    expect((await service.load('driver-123')).hasRequiredDocuments, isTrue);
    expect(calls, 2);
  });

  test('connection failure is not converted into complete documents', () async {
    final service = DriverDocumentReadinessService(fetch: (_) async {
      throw StateError('offline');
    });
    await expectLater(service.load('driver-123'), throwsStateError);
  });
}
