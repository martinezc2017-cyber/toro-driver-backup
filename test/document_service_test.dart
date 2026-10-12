import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:toro_driver/src/services/document_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  http.Response rows(List<Map<String, dynamic>> values) => http.Response(
    jsonEncode(values),
    200,
    headers: {'content-type': 'application/json'},
  );

  DocumentService serviceFor(
    Future<http.Response> Function(http.Request) handler,
  ) {
    final client = SupabaseClient(
      'https://documents.test',
      'test-key',
      // postgrest lee response.request (método y Accept): la respuesta falsa debe traerlo.
      httpClient: MockClient((request) async {
        final r = await handler(request);
        return http.Response.bytes(r.bodyBytes, r.statusCode,
            headers: r.headers, request: request);
      }),
    );
    addTearDown(client.dispose);
    return DocumentService.withClient(client);
  }

  group('Vehicle selection shared by documents and vehicle details', () {
    test('selected vehicle takes precedence when auth and driver IDs differ', () async {
      final requests = <Uri>[];
      final service = serviceFor((request) async {
        requests.add(request.url);
        if (request.url.path.endsWith('/drivers')) {
          expect(request.url.queryParameters['id'], 'eq.driver-id');
          return rows([
            {
              'id': 'driver-id',
              'user_id': 'auth-id',
              'current_vehicle_id': 'selected-vehicle',
            },
          ]);
        }
        expect(request.url.queryParameters['id'], 'eq.selected-vehicle');
        return rows([
          {'id': 'selected-vehicle', 'driver_id': 'driver-id'},
        ]);
      });

      expect(await service.getDriverVehicleId('driver-id'), 'selected-vehicle');
      expect(requests, hasLength(2));
    });

    test('a registered vehicle is found when current_vehicle_id is absent', () async {
      final service = serviceFor((request) async {
        if (request.url.path.endsWith('/drivers')) {
          return rows([
            {'id': 'driver-id', 'user_id': 'auth-id'},
          ]);
        }
        expect(request.url.queryParameters['driver_id'], 'eq.driver-id');
        expect(request.url.queryParameters['order'], 'updated_at.desc.nullslast');
        return rows([
          {'id': 'owned-vehicle', 'driver_id': 'driver-id'},
        ]);
      });

      expect(await service.getDriverVehicleId('driver-id'), 'owned-vehicle');
    });

    test('legacy registrations keyed to auth ID remain visible', () async {
      final checkedIds = <String?>[];
      final service = serviceFor((request) async {
        if (request.url.path.endsWith('/drivers')) {
          return rows([
            {'id': 'driver-id', 'user_id': 'auth-id'},
          ]);
        }
        final checkedId = request.url.queryParameters['driver_id'];
        checkedIds.add(checkedId);
        return checkedId == 'eq.auth-id'
            ? rows([
                {'id': 'legacy-vehicle', 'driver_id': 'auth-id'},
              ])
            : rows([]);
      });

      expect(await service.getDriverVehicleId('driver-id'), 'legacy-vehicle');
      expect(checkedIds, ['eq.driver-id', 'eq.auth-id']);
    });

    test('legacy user_id fallback is attempted only after driver matches', () async {
      final service = serviceFor((request) async {
        if (request.url.path.endsWith('/drivers')) {
          return rows([
            {'id': 'driver-id', 'user_id': 'auth-id'},
          ]);
        }
        return request.url.queryParameters['user_id'] == 'eq.auth-id'
            ? rows([
                {'id': 'user-vehicle', 'user_id': 'auth-id'},
              ])
            : rows([]);
      });

      expect(await service.getDriverVehicleId('driver-id'), 'user-vehicle');
    });

    test('missing driver does not look like an empty set of documents', () async {
      final service = serviceFor((_) async => rows([]));
      await expectLater(
        service.getDriverDocumentStatus('unknown'),
        throwsStateError,
      );
      await expectLater(service.getDriverVehicleId('unknown'), throwsStateError);
    });

    test('permission errors propagate instead of becoming missing documents', () async {
      final service = serviceFor((_) async => http.Response(
        jsonEncode({'code': '42501', 'message': 'permission denied'}),
        403,
        headers: {'content-type': 'application/json'},
      ));
      await expectLater(
        service.getDriverDocumentStatus('driver-id'),
        throwsA(isA<PostgrestException>()),
      );
      await expectLater(
        service.getVehicleDocumentStatus('vehicle-id'),
        throwsA(isA<PostgrestException>()),
      );
    });
  });

  group('Existing document data', () {
    test('legacy profile photo survives an empty canonical field', () {
      final status = DriverDocumentStatus.fromJson({
        'profile_image_url': ' ',
        'profile_photo_url': 'https://example.test/profile.jpg',
      });
      expect(status.hasProfilePhoto, isTrue);
      expect(status.profileImageUrl, 'https://example.test/profile.jpg');
    });

    test('insurance uses canonical policy and legacy uploaded file', () {
      final status = VehicleDocumentStatus.fromJson({
        'insurance_policy_number': 'POL-123',
        'insurance_card_front_url': '',
        'insurance_document_url': 'https://example.test/insurance.jpg',
        'insurance_verified': false,
      });
      expect(status.insurancePolicy, 'POL-123');
      expect(status.hasInsurance, isTrue);
      expect(status.insuranceStatus, 'pending');
    });

    test('an empty URL is never treated as an uploaded document', () {
      final status = VehicleDocumentStatus.fromJson({
        'insurance_card_front_url': ' ',
        'endorsement_document_url': '',
        'registration_url': ' ',
        'vehicle_photo_front_url': '',
        'vehicle_photo_back_url': ' ',
        'vehicle_photo_interior_url': 'https://example.test/interior.jpg',
      });
      expect(status.hasInsurance, isFalse);
      expect(status.hasEndorsement, isFalse);
      expect(status.hasRegistration, isFalse);
      expect(status.vehiclePhotosCount, 1);
      expect(status.hasAllPhotos, isFalse);
      expect(DriverDocumentStatus(profileImageUrl: ' ').hasProfilePhoto, isFalse);
    });

    test('complete status returns the same selected vehicle and its files', () async {
      final service = serviceFor((request) async {
        if (request.url.path.endsWith('/drivers')) {
          return rows([
            {
              'id': 'driver-id',
              'user_id': 'auth-id',
              'current_vehicle_id': 'selected',
              'license_image_url': 'license.jpg',
              'profile_image_url': 'profile.jpg',
            },
          ]);
        }
        if (request.url.path.endsWith('/vehicle_inspections')) return rows([]);
        return rows([
          {
            'id': 'selected',
            'insurance_policy_number': 'POL-123',
            'insurance_card_front_url': 'insurance.jpg',
          },
        ]);
      });

      final status = await service.getCompleteStatus('driver-id');
      expect(status.vehicleId, 'selected');
      expect(status.hasVehicle, isTrue);
      expect(status.driverDocs.hasLicenseImage, isTrue);
      expect(status.vehicleDocs?.insurancePolicy, 'POL-123');
      expect(status.vehicleDocs?.insuranceStatus, 'pending');
    });
  });
}
