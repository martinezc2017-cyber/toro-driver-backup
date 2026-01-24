enum VehicleStatus {
  active,
  inactive,
  maintenance,
  pendingVerification,
  rejected,
}

enum VehicleType {
  sedan,
  suv,
  van,
  truck,
}

/// Vehicle model - synced with Supabase 'vehicles' table
/// Used for both Driver App and Admin Panel
class VehicleModel {
  final String id;
  final String driverId;
  final String make;       // 'make' in Supabase (brand)
  final String model;
  final int year;
  final String color;
  final String plate;      // 'plate' in Supabase (plate number)
  final String? vin;
  final VehicleType type;
  final VehicleStatus status;
  final bool isVerified;
  final int mileage;       // 'mileage' in Supabase (total kilometers)
  final int totalRides;
  final double rating;
  final List<String> imageUrls;

  // Insurance fields
  final String? insuranceCompany;
  final String? insurancePolicyNumber;
  final DateTime? insuranceExpiry;
  final bool insuranceVerified;
  final bool hasRideshareEndorsement;
  final String? insuranceDocumentUrl;

  // Maintenance & Inspection
  final bool maintenanceDue;
  final bool inspectionDue;
  final DateTime? lastInspection;
  final DateTime? inspectionExpiry;
  final DateTime? registrationExpiry;

  final DateTime createdAt;
  final DateTime updatedAt;

  VehicleModel({
    required this.id,
    required this.driverId,
    required this.make,
    required this.model,
    required this.year,
    required this.color,
    required this.plate,
    this.vin,
    this.type = VehicleType.sedan,
    this.status = VehicleStatus.pendingVerification,
    this.isVerified = false,
    this.mileage = 0,
    this.totalRides = 0,
    this.rating = 5.0,
    this.imageUrls = const [],
    this.insuranceCompany,
    this.insurancePolicyNumber,
    this.insuranceExpiry,
    this.insuranceVerified = false,
    this.hasRideshareEndorsement = false,
    this.insuranceDocumentUrl,
    this.maintenanceDue = false,
    this.inspectionDue = false,
    this.lastInspection,
    this.inspectionExpiry,
    this.registrationExpiry,
    required this.createdAt,
    required this.updatedAt,
  });

  // Aliases for UI compatibility
  String get brand => make;
  String get plateNumber => plate;
  int get totalKilometers => mileage;
  String get fullName => '$make $model $year';

  factory VehicleModel.fromJson(Map<String, dynamic> json) {
    return VehicleModel(
      id: json['id'] as String,
      driverId: json['driver_id'] as String,
      make: json['make'] as String? ?? json['brand'] as String? ?? '',
      model: json['model'] as String,
      year: json['year'] as int? ?? 0,
      color: json['color'] as String? ?? '',
      plate: json['plate'] as String? ?? json['plate_number'] as String? ?? '',
      vin: json['vin'] as String?,
      type: VehicleType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => VehicleType.sedan,
      ),
      status: VehicleStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => VehicleStatus.pendingVerification,
      ),
      isVerified: json['is_verified'] as bool? ?? false,
      mileage: json['mileage'] as int? ?? json['total_kilometers'] as int? ?? 0,
      totalRides: json['total_rides'] as int? ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 5.0,
      imageUrls: (json['image_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      insuranceCompany: json['insurance_company'] as String?,
      insurancePolicyNumber: json['insurance_policy_number'] as String?,
      insuranceExpiry: json['insurance_expiry'] != null
          ? DateTime.tryParse(json['insurance_expiry'] as String)
          : null,
      insuranceVerified: json['insurance_verified'] as bool? ?? false,
      hasRideshareEndorsement: json['has_rideshare_endorsement'] as bool? ?? false,
      insuranceDocumentUrl: json['insurance_document_url'] as String?,
      maintenanceDue: json['maintenance_due'] as bool? ?? false,
      inspectionDue: json['inspection_due'] as bool? ?? false,
      lastInspection: json['last_inspection'] != null
          ? DateTime.tryParse(json['last_inspection'] as String)
          : null,
      inspectionExpiry: json['inspection_expiry'] != null
          ? DateTime.tryParse(json['inspection_expiry'] as String)
          : null,
      registrationExpiry: json['registration_expiry'] != null
          ? DateTime.tryParse(json['registration_expiry'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'driver_id': driverId,
      'make': make,
      'model': model,
      'year': year,
      'color': color,
      'plate': plate,
      'vin': vin,
      'type': type.name,
      'status': status.name,
      'is_verified': isVerified,
      'mileage': mileage,
      'total_rides': totalRides,
      'rating': rating,
      'image_urls': imageUrls,
      'insurance_company': insuranceCompany,
      'insurance_policy_number': insurancePolicyNumber,
      'insurance_expiry': insuranceExpiry?.toIso8601String(),
      'insurance_verified': insuranceVerified,
      'has_rideshare_endorsement': hasRideshareEndorsement,
      'insurance_document_url': insuranceDocumentUrl,
      'maintenance_due': maintenanceDue,
      'inspection_due': inspectionDue,
      'last_inspection': lastInspection?.toIso8601String(),
      'inspection_expiry': inspectionExpiry?.toIso8601String(),
      'registration_expiry': registrationExpiry?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  VehicleModel copyWith({
    String? id,
    String? driverId,
    String? make,
    String? model,
    int? year,
    String? color,
    String? plate,
    String? vin,
    VehicleType? type,
    VehicleStatus? status,
    bool? isVerified,
    int? mileage,
    int? totalRides,
    double? rating,
    List<String>? imageUrls,
    String? insuranceCompany,
    String? insurancePolicyNumber,
    DateTime? insuranceExpiry,
    bool? insuranceVerified,
    bool? hasRideshareEndorsement,
    String? insuranceDocumentUrl,
    bool? maintenanceDue,
    bool? inspectionDue,
    DateTime? lastInspection,
    DateTime? inspectionExpiry,
    DateTime? registrationExpiry,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return VehicleModel(
      id: id ?? this.id,
      driverId: driverId ?? this.driverId,
      make: make ?? this.make,
      model: model ?? this.model,
      year: year ?? this.year,
      color: color ?? this.color,
      plate: plate ?? this.plate,
      vin: vin ?? this.vin,
      type: type ?? this.type,
      status: status ?? this.status,
      isVerified: isVerified ?? this.isVerified,
      mileage: mileage ?? this.mileage,
      totalRides: totalRides ?? this.totalRides,
      rating: rating ?? this.rating,
      imageUrls: imageUrls ?? this.imageUrls,
      insuranceCompany: insuranceCompany ?? this.insuranceCompany,
      insurancePolicyNumber: insurancePolicyNumber ?? this.insurancePolicyNumber,
      insuranceExpiry: insuranceExpiry ?? this.insuranceExpiry,
      insuranceVerified: insuranceVerified ?? this.insuranceVerified,
      hasRideshareEndorsement: hasRideshareEndorsement ?? this.hasRideshareEndorsement,
      insuranceDocumentUrl: insuranceDocumentUrl ?? this.insuranceDocumentUrl,
      maintenanceDue: maintenanceDue ?? this.maintenanceDue,
      inspectionDue: inspectionDue ?? this.inspectionDue,
      lastInspection: lastInspection ?? this.lastInspection,
      inspectionExpiry: inspectionExpiry ?? this.inspectionExpiry,
      registrationExpiry: registrationExpiry ?? this.registrationExpiry,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
