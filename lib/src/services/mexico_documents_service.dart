import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

/// Service for handling Mexican driver documents
class MexicoDocumentsService {
  final SupabaseClient _client = SupabaseConfig.client;

  /// Document types for Mexico
  static const List<MexicoDocumentType> allDocumentTypes = [
    MexicoDocumentType(
      type: 'ine',
      displayName: 'INE/IFE',
      description: 'Credencial para votar vigente',
      isRequired: true,
      hasExpiry: true,
      hasFrontBack: true,
    ),
    MexicoDocumentType(
      type: 'rfcConstancia',
      displayName: 'Constancia RFC',
      description: 'Constancia de situación fiscal del SAT',
      isRequired: true,
      hasExpiry: false,
      hasFrontBack: false,
    ),
    MexicoDocumentType(
      type: 'licenciaE1',
      displayName: 'Licencia E1',
      description: 'Licencia de conducir tipo E1 para CDMX',
      isRequired: true,
      hasExpiry: true,
      hasFrontBack: true,
      requiredInStates: ['CDMX'],
    ),
    MexicoDocumentType(
      type: 'tarjeton',
      displayName: 'Tarjetón de Conductor',
      description: 'Tarjetón expedido por SEMOVI',
      isRequired: true,
      hasExpiry: true,
      hasFrontBack: false,
      requiredInStates: ['CDMX'],
    ),
    MexicoDocumentType(
      type: 'constanciaSemovi',
      displayName: 'Constancia SEMOVI',
      description: 'Constancia de registro de conductor',
      isRequired: true,
      hasExpiry: true,
      hasFrontBack: false,
      requiredInStates: ['CDMX'],
    ),
    MexicoDocumentType(
      type: 'constanciaVehicular',
      displayName: 'Constancia Vehicular',
      description: 'Constancia de registro vehicular SEMOVI',
      isRequired: true,
      hasExpiry: true,
      hasFrontBack: false,
      requiredInStates: ['CDMX'],
    ),
    MexicoDocumentType(
      type: 'seguroERT',
      displayName: 'Seguro ERT',
      description: 'Póliza de seguro para plataformas de transporte',
      isRequired: true,
      hasExpiry: true,
      hasFrontBack: false,
    ),
    MexicoDocumentType(
      type: 'comprobanteDomicilio',
      displayName: 'Comprobante de Domicilio',
      description: 'Recibo de servicios no mayor a 3 meses',
      isRequired: true,
      hasExpiry: true,
      hasFrontBack: false,
    ),
    MexicoDocumentType(
      type: 'cartaNoAntecedentes',
      displayName: 'Carta de No Antecedentes',
      description: 'Carta de no antecedentes penales',
      isRequired: false,
      hasExpiry: true,
      hasFrontBack: false,
    ),
    MexicoDocumentType(
      type: 'driverLicense',
      displayName: 'Licencia de Conducir',
      description: 'Licencia tipo A o B vigente',
      isRequired: true,
      hasExpiry: true,
      hasFrontBack: true,
      requiredInStates: ['JAL', 'NL', 'GTO', 'QRO'], // Non-CDMX states
    ),
  ];

  /// Get required documents for a specific state
  List<MexicoDocumentType> getRequiredDocuments(String stateCode) {
    return allDocumentTypes.where((doc) {
      if (!doc.isRequired) return false;
      if (doc.requiredInStates == null) return true;
      return doc.requiredInStates!.contains(stateCode);
    }).toList();
  }

  /// Get driver's uploaded documents
  Future<List<MexicoDocument>> getDriverDocuments(String driverId) async {
    try {
      final response = await _client
          .from('driver_documents_mx')
          .select()
          .eq('driver_id', driverId)
          .order('created_at', ascending: false);

      return (response as List).map((data) {
        return MexicoDocument.fromJson(data);
      }).toList();
    } catch (e) {
      rethrow;
    }
  }

  /// Upload a document
  Future<MexicoDocument> uploadDocument({
    required String driverId,
    required String documentType,
    required File frontFile,
    File? backFile,
    String? documentNumber,
    DateTime? issueDate,
    DateTime? expiryDate,
  }) async {
    try {
      // Upload front file
      final frontFileName = '${driverId}_${documentType}_front_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final frontPath = 'documents/$driverId/$frontFileName';

      await _client.storage
          .from('documents')
          .upload(frontPath, frontFile);

      final frontUrl = _client.storage
          .from('documents')
          .getPublicUrl(frontPath);

      // Upload back file if provided
      String? backUrl;
      if (backFile != null) {
        final backFileName = '${driverId}_${documentType}_back_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final backPath = 'documents/$driverId/$backFileName';

        await _client.storage
            .from('documents')
            .upload(backPath, backFile);

        backUrl = _client.storage
            .from('documents')
            .getPublicUrl(backPath);
      }

      // Insert document record
      final response = await _client
          .from('driver_documents_mx')
          .upsert({
            'driver_id': driverId,
            'document_type': documentType,
            'document_number': documentNumber,
            'issue_date': issueDate?.toIso8601String(),
            'expiry_date': expiryDate?.toIso8601String(),
            'front_file_url': frontUrl,
            'back_file_url': backUrl,
            'verification_status': 'pending',
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'driver_id, document_type')
          .select()
          .single();

      return MexicoDocument.fromJson(response);
    } catch (e) {
      rethrow;
    }
  }

  /// Validate all driver documents
  Future<DocumentValidationResult> validateDocuments(String driverId) async {
    try {
      final response = await _client.functions.invoke(
        'validate-driver-mx',
        body: {
          'driver_id': driverId,
          'validation_type': 'all',
        },
      );

      if (response.status != 200) {
        throw Exception('Error validating documents: ${response.data}');
      }

      final data = response.data['data'];
      return DocumentValidationResult(
        isComplete: data['is_complete'] as bool,
        missingDocuments: List<String>.from(data['missing_documents'] ?? []),
        expiringSoon: List<String>.from(data['expiring_soon'] ?? []),
        rfcValidated: data['rfc_validated'] as bool,
        validations: (data['validations'] as List?)?.map((v) {
          return DocumentValidation(
            isValid: v['is_valid'] as bool,
            field: v['field'] as String,
            message: v['message'] as String,
          );
        }).toList() ?? [],
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Get documents expiring soon
  Future<List<MexicoDocument>> getExpiringDocuments(String driverId, {int days = 30}) async {
    try {
      final cutoffDate = DateTime.now().add(Duration(days: days));

      final response = await _client
          .from('driver_documents_mx')
          .select()
          .eq('driver_id', driverId)
          .not('expiry_date', 'is', null)
          .lte('expiry_date', cutoffDate.toIso8601String())
          .order('expiry_date');

      return (response as List).map((data) {
        return MexicoDocument.fromJson(data);
      }).toList();
    } catch (e) {
      rethrow;
    }
  }

  /// Delete a document
  Future<void> deleteDocument(String documentId) async {
    try {
      await _client
          .from('driver_documents_mx')
          .delete()
          .eq('id', documentId);
    } catch (e) {
      rethrow;
    }
  }
}

/// Document type definition
class MexicoDocumentType {
  final String type;
  final String displayName;
  final String description;
  final bool isRequired;
  final bool hasExpiry;
  final bool hasFrontBack;
  final List<String>? requiredInStates;

  const MexicoDocumentType({
    required this.type,
    required this.displayName,
    required this.description,
    required this.isRequired,
    required this.hasExpiry,
    required this.hasFrontBack,
    this.requiredInStates,
  });
}

/// Uploaded document
class MexicoDocument {
  final String id;
  final String driverId;
  final String documentType;
  final String? documentNumber;
  final DateTime? issueDate;
  final DateTime? expiryDate;
  final String? frontFileUrl;
  final String? backFileUrl;
  final String verificationStatus;
  final String? rejectionReason;
  final DateTime? verifiedAt;
  final DateTime createdAt;

  MexicoDocument({
    required this.id,
    required this.driverId,
    required this.documentType,
    this.documentNumber,
    this.issueDate,
    this.expiryDate,
    this.frontFileUrl,
    this.backFileUrl,
    required this.verificationStatus,
    this.rejectionReason,
    this.verifiedAt,
    required this.createdAt,
  });

  factory MexicoDocument.fromJson(Map<String, dynamic> json) {
    return MexicoDocument(
      id: json['id'],
      driverId: json['driver_id'],
      documentType: json['document_type'],
      documentNumber: json['document_number'],
      issueDate: json['issue_date'] != null
          ? DateTime.parse(json['issue_date'])
          : null,
      expiryDate: json['expiry_date'] != null
          ? DateTime.parse(json['expiry_date'])
          : null,
      frontFileUrl: json['front_file_url'],
      backFileUrl: json['back_file_url'],
      verificationStatus: json['verification_status'],
      rejectionReason: json['rejection_reason'],
      verifiedAt: json['verified_at'] != null
          ? DateTime.parse(json['verified_at'])
          : null,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  bool get isPending => verificationStatus == 'pending';
  bool get isApproved => verificationStatus == 'approved';
  bool get isRejected => verificationStatus == 'rejected';

  bool get isExpired =>
      expiryDate != null && expiryDate!.isBefore(DateTime.now());

  bool get isExpiringSoon {
    if (expiryDate == null) return false;
    final daysUntilExpiry = expiryDate!.difference(DateTime.now()).inDays;
    return daysUntilExpiry >= 0 && daysUntilExpiry <= 30;
  }

  int get daysUntilExpiry =>
      expiryDate?.difference(DateTime.now()).inDays ?? 999;

  MexicoDocumentType? get documentTypeInfo {
    try {
      return MexicoDocumentsService.allDocumentTypes
          .firstWhere((t) => t.type == documentType);
    } catch (e) {
      return null;
    }
  }
}

/// Validation result
class DocumentValidationResult {
  final bool isComplete;
  final List<String> missingDocuments;
  final List<String> expiringSoon;
  final bool rfcValidated;
  final List<DocumentValidation> validations;

  DocumentValidationResult({
    required this.isComplete,
    required this.missingDocuments,
    required this.expiringSoon,
    required this.rfcValidated,
    required this.validations,
  });
}

/// Individual validation
class DocumentValidation {
  final bool isValid;
  final String field;
  final String message;

  DocumentValidation({
    required this.isValid,
    required this.field,
    required this.message,
  });
}
