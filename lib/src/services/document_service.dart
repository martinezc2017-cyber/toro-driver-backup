import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../core/logging/app_logger.dart';
import 'document_ocr_service.dart';

/// Service for managing driver documents with automatic OCR
/// Uses existing tables: drivers, vehicles, vehicle_inspections
/// Syncs with Admin Panel (Fleet, Inspections screens)
/// OCR automatically extracts data from documents (ML Kit - offline, free)
class DocumentService {
  static final DocumentService _instance = DocumentService._();
  static DocumentService get instance => _instance;
  DocumentService._();

  final SupabaseClient _client = SupabaseConfig.client;
  final DocumentOcrService _ocrService = DocumentOcrService();
  static const String _bucketName = 'driver-documents';

  // ============================================================================
  // DRIVER DOCUMENTS (Personal - stored in drivers table)
  // ============================================================================

  /// Get driver's personal document status
  Future<DriverDocumentStatus> getDriverDocumentStatus(String driverId) async {
    try {
      final response = await _client
          .from(SupabaseConfig.driversTable)
          .select('''
            license_number, license_expiry, license_image_url,
            profile_image_url,
            agreement_signed, agreement_signed_at,
            background_check_status, background_check_date
          ''')
          .eq('id', driverId)
          .maybeSingle();

      if (response == null) {
        return DriverDocumentStatus.empty();
      }

      return DriverDocumentStatus.fromJson(response);
    } catch (e) {
      AppLogger.log('DocumentService: Error getting driver docs: $e');
      return DriverDocumentStatus.empty();
    }
  }

  /// Upload driver's license image with automatic OCR extraction
  /// Extracts: license number, name, expiry date, DOB, address, state
  Future<String?> uploadLicenseImage(String driverId, File file) async {
    try {
      final url = await _uploadFile(driverId, 'license', file);

      final updateData = <String, dynamic>{
        'license_image_url': url,
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Run OCR to auto-extract license data
      if (_ocrService.isAvailable) {
        AppLogger.log('DocumentService: Running OCR on license...');
        final ocrData = await _ocrService.extractLicenseFromFile(file);

        if (ocrData != null && ocrData.hasAnyData) {
          AppLogger.log('DocumentService: OCR extracted - License: ${ocrData.licenseNumber}, Name: ${ocrData.fullName}, Expiry: ${ocrData.expiryDate}');

          if (ocrData.licenseNumber != null) {
            updateData['license_number'] = ocrData.licenseNumber;
          }
          if (ocrData.expiryDate != null) {
            updateData['license_expiry'] = ocrData.expiryDate!.toIso8601String().split('T')[0];
          }
          // Store raw OCR text for admin review
          updateData['license_ocr_raw'] = ocrData.rawText;
        }
      }

      await _client
          .from(SupabaseConfig.driversTable)
          .update(updateData)
          .eq('id', driverId);

      return url;
    } catch (e) {
      AppLogger.log('DocumentService: Error uploading license: $e');
      return null;
    }
  }

  /// Update driver's license info
  Future<bool> updateLicenseInfo({
    required String driverId,
    required String licenseNumber,
    required DateTime expiryDate,
    String? imageUrl,
  }) async {
    try {
      final updateData = {
        'license_number': licenseNumber,
        'license_expiry': expiryDate.toIso8601String().split('T')[0],
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (imageUrl != null) {
        updateData['license_image_url'] = imageUrl;
      }

      await _client
          .from(SupabaseConfig.driversTable)
          .update(updateData)
          .eq('id', driverId);

      return true;
    } catch (e) {
      AppLogger.log('DocumentService: Error updating license: $e');
      return false;
    }
  }

  /// Upload profile photo
  Future<String?> uploadProfilePhoto(String driverId, File file) async {
    try {
      final url = await _uploadFile(driverId, 'profile', file);

      await _client
          .from(SupabaseConfig.driversTable)
          .update({
            'profile_image_url': url,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', driverId);

      return url;
    } catch (e) {
      AppLogger.log('DocumentService: Error uploading profile photo: $e');
      return null;
    }
  }

  // ============================================================================
  // VEHICLE DOCUMENTS (stored in vehicles table)
  // Admin reads from: admin_fleet_screen.dart
  // ============================================================================

  /// Get vehicle document status
  Future<VehicleDocumentStatus?> getVehicleDocumentStatus(String vehicleId) async {
    try {
      final response = await _client
          .from('vehicles')
          .select('''
            insurance_company, insurance_policy, insurance_expiry,
            insurance_card_front_url, insurance_card_back_url,
            insurance_verified,
            rideshare_endorsement, endorsement_expiry,
            endorsement_document_url,
            registration_url,
            vehicle_photo_front_url, vehicle_photo_back_url,
            vehicle_photo_interior_url, vehicle_photo_side_url,
            inspection_due, maintenance_due,
            status
          ''')
          .eq('id', vehicleId)
          .maybeSingle();

      if (response == null) return null;
      return VehicleDocumentStatus.fromJson(response);
    } catch (e) {
      AppLogger.log('DocumentService: Error getting vehicle docs: $e');
      return null;
    }
  }

  /// Get vehicle for driver
  Future<String?> getDriverVehicleId(String driverId) async {
    try {
      final response = await _client
          .from(SupabaseConfig.driversTable)
          .select('current_vehicle_id')
          .eq('id', driverId)
          .maybeSingle();

      return response?['current_vehicle_id'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Upload insurance card with automatic OCR extraction
  /// Extracts: VIN, policy number, expiry date, company, driver name, vehicle info
  Future<bool> uploadInsuranceCard({
    required String vehicleId,
    required File frontImage,
    File? backImage,
    String? insuranceCompany,
    String? policyNumber,
    DateTime? expiryDate,
  }) async {
    try {
      final frontUrl = await _uploadFile(vehicleId, 'insurance_front', frontImage);
      String? backUrl;
      if (backImage != null) {
        backUrl = await _uploadFile(vehicleId, 'insurance_back', backImage);
      }

      final updateData = <String, dynamic>{
        'insurance_card_front_url': frontUrl,
        'insurance_verified': false, // Reset for admin review
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (backUrl != null) updateData['insurance_card_back_url'] = backUrl;

      // Run OCR to auto-extract insurance data
      if (_ocrService.isAvailable) {
        AppLogger.log('DocumentService: Running OCR on insurance card...');
        final ocrData = await _ocrService.extractFromFile(frontImage);

        if (ocrData != null && ocrData.hasAnyData) {
          AppLogger.log('DocumentService: OCR extracted - Company: ${ocrData.insuranceCompany}, Policy: ${ocrData.policyNumber}, Expiry: ${ocrData.expiryDate}, VIN: ${ocrData.vin}');

          // Use OCR data if not provided manually
          if (insuranceCompany == null && ocrData.insuranceCompany != null) {
            updateData['insurance_company'] = ocrData.insuranceCompany;
          }
          if (policyNumber == null && ocrData.policyNumber != null) {
            updateData['insurance_policy'] = ocrData.policyNumber;
          }
          if (expiryDate == null && ocrData.expiryDate != null) {
            updateData['insurance_expiry'] = ocrData.expiryDate!.toIso8601String().split('T')[0];
          }
          // VIN can auto-update vehicle record
          if (ocrData.vin != null) {
            updateData['vin'] = ocrData.vin;
          }
          // Store raw OCR text for admin review
          updateData['insurance_ocr_raw'] = ocrData.rawText;
        }
      }

      // Override with manual values if provided
      if (insuranceCompany != null) updateData['insurance_company'] = insuranceCompany;
      if (policyNumber != null) updateData['insurance_policy'] = policyNumber;
      if (expiryDate != null) {
        updateData['insurance_expiry'] = expiryDate.toIso8601String().split('T')[0];
      }

      await _client.from('vehicles').update(updateData).eq('id', vehicleId);
      return true;
    } catch (e) {
      AppLogger.log('DocumentService: Error uploading insurance: $e');
      return false;
    }
  }

  /// Upload endorsement document
  Future<bool> uploadEndorsementDocument({
    required String vehicleId,
    required File file,
    String? endorsementId,
    DateTime? expiryDate,
  }) async {
    try {
      final url = await _uploadFile(vehicleId, 'endorsement', file);

      final updateData = <String, dynamic>{
        'endorsement_document_url': url,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (endorsementId != null) updateData['rideshare_endorsement'] = endorsementId;
      if (expiryDate != null) {
        updateData['endorsement_expiry'] = expiryDate.toIso8601String().split('T')[0];
      }

      await _client.from('vehicles').update(updateData).eq('id', vehicleId);
      return true;
    } catch (e) {
      AppLogger.log('DocumentService: Error uploading endorsement: $e');
      return false;
    }
  }

  /// Upload vehicle registration
  Future<bool> uploadRegistration(String vehicleId, File file) async {
    try {
      final url = await _uploadFile(vehicleId, 'registration', file);

      await _client.from('vehicles').update({
        'registration_url': url,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', vehicleId);

      return true;
    } catch (e) {
      AppLogger.log('DocumentService: Error uploading registration: $e');
      return false;
    }
  }

  /// Upload vehicle photos (4 required: front, back, interior, side)
  Future<bool> uploadVehiclePhotos({
    required String vehicleId,
    File? frontPhoto,
    File? backPhoto,
    File? interiorPhoto,
    File? sidePhoto,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (frontPhoto != null) {
        updateData['vehicle_photo_front_url'] =
            await _uploadFile(vehicleId, 'vehicle_front', frontPhoto);
      }
      if (backPhoto != null) {
        updateData['vehicle_photo_back_url'] =
            await _uploadFile(vehicleId, 'vehicle_back', backPhoto);
      }
      if (interiorPhoto != null) {
        updateData['vehicle_photo_interior_url'] =
            await _uploadFile(vehicleId, 'vehicle_interior', interiorPhoto);
      }
      if (sidePhoto != null) {
        updateData['vehicle_photo_side_url'] =
            await _uploadFile(vehicleId, 'vehicle_side', sidePhoto);
      }

      await _client.from('vehicles').update(updateData).eq('id', vehicleId);
      return true;
    } catch (e) {
      AppLogger.log('DocumentService: Error uploading vehicle photos: $e');
      return false;
    }
  }

  // ============================================================================
  // VEHICLE INSPECTIONS (stored in vehicle_inspections table)
  // Admin reads from: admin_inspections_screen.dart
  // ============================================================================

  /// Get inspection history for a vehicle
  Future<List<VehicleInspection>> getInspections(String vehicleId) async {
    try {
      final response = await _client
          .from('vehicle_inspections')
          .select()
          .eq('vehicle_id', vehicleId)
          .order('inspection_date', ascending: false);

      return (response as List)
          .map((json) => VehicleInspection.fromJson(json))
          .toList();
    } catch (e) {
      AppLogger.log('DocumentService: Error getting inspections: $e');
      return [];
    }
  }

  /// Get latest inspection
  Future<VehicleInspection?> getLatestInspection(String vehicleId) async {
    try {
      final response = await _client
          .from('vehicle_inspections')
          .select()
          .eq('vehicle_id', vehicleId)
          .order('inspection_date', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;
      return VehicleInspection.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  /// Upload inspection document (for admin to review)
  Future<bool> uploadInspectionDocument({
    required String vehicleId,
    required String driverId,
    required File document,
    required DateTime inspectionDate,
    DateTime? expiryDate,
    String? inspectorName,
    String? shopName,
  }) async {
    try {
      final url = await _uploadFile(vehicleId, 'inspection', document);

      await _client.from('vehicle_inspections').insert({
        'vehicle_id': vehicleId,
        'driver_id': driverId,
        'inspection_date': inspectionDate.toIso8601String().split('T')[0],
        'expiry_date': expiryDate?.toIso8601String().split('T')[0],
        'document_url': url,
        'inspector_name': inspectorName,
        'shop_name': shopName,
        'passed': null, // Admin will set this
        'created_at': DateTime.now().toIso8601String(),
      });

      // Mark vehicle as having inspection uploaded
      await _client.from('vehicles').update({
        'inspection_due': false,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', vehicleId);

      return true;
    } catch (e) {
      AppLogger.log('DocumentService: Error uploading inspection: $e');
      return false;
    }
  }

  // ============================================================================
  // COMBINED STATUS SUMMARY
  // ============================================================================

  /// Get complete document status for driver (personal + vehicle)
  Future<CompleteDocumentStatus> getCompleteStatus(String driverId) async {
    final driverDocs = await getDriverDocumentStatus(driverId);

    VehicleDocumentStatus? vehicleDocs;
    VehicleInspection? latestInspection;

    final vehicleId = await getDriverVehicleId(driverId);
    if (vehicleId != null) {
      vehicleDocs = await getVehicleDocumentStatus(vehicleId);
      latestInspection = await getLatestInspection(vehicleId);
    }

    return CompleteDocumentStatus(
      driverDocs: driverDocs,
      vehicleDocs: vehicleDocs,
      latestInspection: latestInspection,
      hasVehicle: vehicleId != null,
    );
  }

  // ============================================================================
  // HELPERS
  // ============================================================================

  Future<String> _uploadFile(String entityId, String type, File file) async {
    final extension = file.path.split('.').last.toLowerCase();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = '$entityId/${type}_$timestamp.$extension';

    await _client.storage.from(_bucketName).upload(
      fileName,
      file,
      fileOptions: FileOptions(
        contentType: _getContentType(extension),
        upsert: false,
      ),
    );

    return _client.storage.from(_bucketName).getPublicUrl(fileName);
  }

  String _getContentType(String extension) {
    switch (extension.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'pdf':
        return 'application/pdf';
      case 'heic':
        return 'image/heic';
      default:
        return 'application/octet-stream';
    }
  }
}

// ============================================================================
// MODELS
// ============================================================================

/// Status of driver's personal documents
class DriverDocumentStatus {
  final String? licenseNumber;
  final DateTime? licenseExpiry;
  final String? licenseImageUrl;
  final String? profileImageUrl;
  final bool agreementSigned;
  final DateTime? agreementSignedAt;
  final String? backgroundCheckStatus;
  final DateTime? backgroundCheckDate;

  DriverDocumentStatus({
    this.licenseNumber,
    this.licenseExpiry,
    this.licenseImageUrl,
    this.profileImageUrl,
    this.agreementSigned = false,
    this.agreementSignedAt,
    this.backgroundCheckStatus,
    this.backgroundCheckDate,
  });

  factory DriverDocumentStatus.empty() => DriverDocumentStatus();

  factory DriverDocumentStatus.fromJson(Map<String, dynamic> json) {
    return DriverDocumentStatus(
      licenseNumber: json['license_number'] as String?,
      licenseExpiry: json['license_expiry'] != null
          ? DateTime.tryParse(json['license_expiry'])
          : null,
      licenseImageUrl: json['license_image_url'] as String?,
      profileImageUrl: json['profile_image_url'] as String?,
      agreementSigned: json['agreement_signed'] == true,
      agreementSignedAt: json['agreement_signed_at'] != null
          ? DateTime.tryParse(json['agreement_signed_at'])
          : null,
      backgroundCheckStatus: json['background_check_status'] as String?,
      backgroundCheckDate: json['background_check_date'] != null
          ? DateTime.tryParse(json['background_check_date'])
          : null,
    );
  }

  bool get hasLicense => licenseNumber != null && licenseNumber!.isNotEmpty;
  bool get hasLicenseImage => licenseImageUrl != null;
  bool get hasProfilePhoto => profileImageUrl != null;

  bool get isLicenseExpired {
    if (licenseExpiry == null) return false;
    return licenseExpiry!.isBefore(DateTime.now());
  }

  bool get isLicenseExpiringSoon {
    if (licenseExpiry == null) return false;
    final days = licenseExpiry!.difference(DateTime.now()).inDays;
    return days > 0 && days <= 30;
  }

  String get licenseStatus {
    if (!hasLicense) return 'missing';
    if (isLicenseExpired) return 'expired';
    if (isLicenseExpiringSoon) return 'expiring';
    return 'approved';
  }
}

/// Status of vehicle documents
class VehicleDocumentStatus {
  final String? insuranceCompany;
  final String? insurancePolicy;
  final DateTime? insuranceExpiry;
  final String? insuranceCardFrontUrl;
  final String? insuranceCardBackUrl;
  final bool insuranceVerified;
  final String? endorsementId;
  final DateTime? endorsementExpiry;
  final String? endorsementDocumentUrl;
  final String? registrationUrl;
  final String? vehiclePhotoFrontUrl;
  final String? vehiclePhotoBackUrl;
  final String? vehiclePhotoInteriorUrl;
  final String? vehiclePhotoSideUrl;
  final bool inspectionDue;
  final bool maintenanceDue;
  final String status;

  VehicleDocumentStatus({
    this.insuranceCompany,
    this.insurancePolicy,
    this.insuranceExpiry,
    this.insuranceCardFrontUrl,
    this.insuranceCardBackUrl,
    this.insuranceVerified = false,
    this.endorsementId,
    this.endorsementExpiry,
    this.endorsementDocumentUrl,
    this.registrationUrl,
    this.vehiclePhotoFrontUrl,
    this.vehiclePhotoBackUrl,
    this.vehiclePhotoInteriorUrl,
    this.vehiclePhotoSideUrl,
    this.inspectionDue = false,
    this.maintenanceDue = false,
    this.status = 'pending',
  });

  factory VehicleDocumentStatus.fromJson(Map<String, dynamic> json) {
    return VehicleDocumentStatus(
      insuranceCompany: json['insurance_company'] as String?,
      insurancePolicy: json['insurance_policy'] as String?,
      insuranceExpiry: json['insurance_expiry'] != null
          ? DateTime.tryParse(json['insurance_expiry'])
          : null,
      insuranceCardFrontUrl: json['insurance_card_front_url'] as String?,
      insuranceCardBackUrl: json['insurance_card_back_url'] as String?,
      insuranceVerified: json['insurance_verified'] == true,
      endorsementId: json['rideshare_endorsement'] as String?,
      endorsementExpiry: json['endorsement_expiry'] != null
          ? DateTime.tryParse(json['endorsement_expiry'])
          : null,
      endorsementDocumentUrl: json['endorsement_document_url'] as String?,
      registrationUrl: json['registration_url'] as String?,
      vehiclePhotoFrontUrl: json['vehicle_photo_front_url'] as String?,
      vehiclePhotoBackUrl: json['vehicle_photo_back_url'] as String?,
      vehiclePhotoInteriorUrl: json['vehicle_photo_interior_url'] as String?,
      vehiclePhotoSideUrl: json['vehicle_photo_side_url'] as String?,
      inspectionDue: json['inspection_due'] == true,
      maintenanceDue: json['maintenance_due'] == true,
      status: json['status'] as String? ?? 'pending',
    );
  }

  bool get hasInsurance => insuranceCardFrontUrl != null;
  bool get hasEndorsement => endorsementDocumentUrl != null;
  bool get hasRegistration => registrationUrl != null;

  int get vehiclePhotosCount {
    int count = 0;
    if (vehiclePhotoFrontUrl != null) count++;
    if (vehiclePhotoBackUrl != null) count++;
    if (vehiclePhotoInteriorUrl != null) count++;
    if (vehiclePhotoSideUrl != null) count++;
    return count;
  }

  bool get hasAllPhotos => vehiclePhotosCount == 4;

  bool get isInsuranceExpired {
    if (insuranceExpiry == null) return false;
    return insuranceExpiry!.isBefore(DateTime.now());
  }

  String get insuranceStatus {
    if (!hasInsurance) return 'missing';
    if (isInsuranceExpired) return 'expired';
    if (!insuranceVerified) return 'pending';
    return 'approved';
  }
}

/// Vehicle inspection record
class VehicleInspection {
  final String id;
  final String vehicleId;
  final String? driverId;
  final DateTime inspectionDate;
  final DateTime? expiryDate;
  final bool? passed;
  final String? documentUrl;
  final String? inspectorName;
  final String? shopName;
  final String? notes;

  VehicleInspection({
    required this.id,
    required this.vehicleId,
    this.driverId,
    required this.inspectionDate,
    this.expiryDate,
    this.passed,
    this.documentUrl,
    this.inspectorName,
    this.shopName,
    this.notes,
  });

  factory VehicleInspection.fromJson(Map<String, dynamic> json) {
    return VehicleInspection(
      id: json['id'] as String,
      vehicleId: json['vehicle_id'] as String,
      driverId: json['driver_id'] as String?,
      inspectionDate: DateTime.parse(json['inspection_date'] as String),
      expiryDate: json['expiry_date'] != null
          ? DateTime.tryParse(json['expiry_date'])
          : null,
      passed: json['passed'] as bool?,
      documentUrl: json['document_url'] as String?,
      inspectorName: json['inspector_name'] as String?,
      shopName: json['shop_name'] as String?,
      notes: json['notes'] as String?,
    );
  }

  bool get isExpired {
    if (expiryDate == null) return false;
    return expiryDate!.isBefore(DateTime.now());
  }

  String get status {
    if (passed == null) return 'pending';
    if (passed == false) return 'failed';
    if (isExpired) return 'expired';
    return 'passed';
  }
}

/// Complete document status combining driver + vehicle
class CompleteDocumentStatus {
  final DriverDocumentStatus driverDocs;
  final VehicleDocumentStatus? vehicleDocs;
  final VehicleInspection? latestInspection;
  final bool hasVehicle;

  CompleteDocumentStatus({
    required this.driverDocs,
    this.vehicleDocs,
    this.latestInspection,
    required this.hasVehicle,
  });

  /// Check if driver can go online
  bool get canGoOnline {
    // Must have license
    if (driverDocs.licenseStatus != 'approved' &&
        driverDocs.licenseStatus != 'expiring') {
      return false;
    }
    // Must have signed agreement
    if (!driverDocs.agreementSigned) return false;
    // Must have vehicle
    if (!hasVehicle || vehicleDocs == null) return false;
    // Must have verified insurance
    if (vehicleDocs!.insuranceStatus == 'missing' ||
        vehicleDocs!.insuranceStatus == 'expired') {
      return false;
    }
    return true;
  }

  /// Get list of missing/expired documents
  List<String> get issues {
    final issues = <String>[];

    // Driver docs
    if (!driverDocs.hasLicense) issues.add('Licencia de conducir requerida');
    if (driverDocs.isLicenseExpired) issues.add('Licencia expirada');
    if (!driverDocs.hasProfilePhoto) issues.add('Foto de perfil requerida');
    if (!driverDocs.agreementSigned) issues.add('Contrato no firmado');

    // Vehicle docs
    if (!hasVehicle) {
      issues.add('Registrar vehículo');
    } else if (vehicleDocs != null) {
      if (!vehicleDocs!.hasInsurance) issues.add('Seguro requerido');
      if (vehicleDocs!.isInsuranceExpired) issues.add('Seguro expirado');
      if (!vehicleDocs!.insuranceVerified) issues.add('Seguro pendiente de verificación');
      if (!vehicleDocs!.hasAllPhotos) issues.add('Faltan fotos del vehículo (${vehicleDocs!.vehiclePhotosCount}/4)');
      if (vehicleDocs!.inspectionDue) issues.add('Inspección vencida');
    }

    return issues;
  }

  /// Overall status
  String get overallStatus {
    if (issues.isEmpty) return 'complete';
    if (issues.any((i) => i.contains('expirad'))) return 'expired';
    if (issues.any((i) => i.contains('pendiente'))) return 'pending';
    return 'incomplete';
  }

  /// Completion percentage
  double get completionPercent {
    int total = 6; // license, photo, agreement, vehicle, insurance, photos
    int done = 0;

    if (driverDocs.hasLicense) done++;
    if (driverDocs.hasProfilePhoto) done++;
    if (driverDocs.agreementSigned) done++;
    if (hasVehicle) done++;
    if (vehicleDocs?.insuranceVerified == true) done++;
    if (vehicleDocs?.hasAllPhotos == true) done++;

    return done / total;
  }
}
