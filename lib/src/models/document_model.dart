enum DocumentType {
  driverLicense,
  nationalId,
  proofOfAddress,
  criminalRecord,
  taxId,
  profilePhoto,
  vehicleRegistration,
  vehicleInsurance,
  vehicleInspection,
  vehiclePhoto,
}

enum DocumentStatus {
  pending,
  approved,
  rejected,
  expired,
}

class DocumentModel {
  final String id;
  final String driverId;
  final String? vehicleId;
  final DocumentType type;
  final String name;
  final String fileUrl;
  final DocumentStatus status;
  final String? rejectionReason;
  final DateTime? expirationDate;
  final DateTime uploadedAt;
  final DateTime? reviewedAt;

  DocumentModel({
    required this.id,
    required this.driverId,
    this.vehicleId,
    required this.type,
    required this.name,
    required this.fileUrl,
    this.status = DocumentStatus.pending,
    this.rejectionReason,
    this.expirationDate,
    required this.uploadedAt,
    this.reviewedAt,
  });

  bool get isExpired {
    if (expirationDate == null) return false;
    return expirationDate!.isBefore(DateTime.now());
  }

  bool get isExpiringSoon {
    if (expirationDate == null) return false;
    final daysUntilExpiration = expirationDate!.difference(DateTime.now()).inDays;
    return daysUntilExpiration <= 30 && daysUntilExpiration > 0;
  }

  factory DocumentModel.fromJson(Map<String, dynamic> json) {
    return DocumentModel(
      id: json['id'] as String,
      driverId: json['driver_id'] as String,
      vehicleId: json['vehicle_id'] as String?,
      type: DocumentType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => DocumentType.nationalId,
      ),
      name: json['name'] as String,
      fileUrl: json['file_url'] as String,
      status: DocumentStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => DocumentStatus.pending,
      ),
      rejectionReason: json['rejection_reason'] as String?,
      expirationDate: json['expiration_date'] != null
          ? DateTime.parse(json['expiration_date'] as String)
          : null,
      uploadedAt: DateTime.parse(json['uploaded_at'] as String),
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'driver_id': driverId,
      'vehicle_id': vehicleId,
      'type': type.name,
      'name': name,
      'file_url': fileUrl,
      'status': status.name,
      'rejection_reason': rejectionReason,
      'expiration_date': expirationDate?.toIso8601String(),
      'uploaded_at': uploadedAt.toIso8601String(),
      'reviewed_at': reviewedAt?.toIso8601String(),
    };
  }
}
