/// Estados posibles del conductor
enum DriverStatus { pending, active, approved, suspended, rejected }

extension DriverStatusExtension on DriverStatus {
  String get value {
    switch (this) {
      case DriverStatus.pending: return 'pending';
      case DriverStatus.active: return 'active';
      case DriverStatus.approved: return 'approved';
      case DriverStatus.suspended: return 'suspended';
      case DriverStatus.rejected: return 'rejected';
    }
  }
  static DriverStatus fromString(String? v) {
    switch (v) {
      case 'active': return DriverStatus.active;
      case 'approved': return DriverStatus.approved;
      case 'suspended': return DriverStatus.suspended;
      case 'rejected': return DriverStatus.rejected;
      default: return DriverStatus.pending;
    }
  }
}

class DriverModel {
  final String id;
  final String? odUserId; // user_id from Supabase auth
  final String email;
  final String phone;
  final String name; // Combined name (table uses 'name' not first_name/last_name)
  final String? address; // Driver's address
  final String? vehicleType;
  final String? vehiclePlate;
  final String? vehicleModel;
  final String? vehicleMake;
  final String? vehicleColor;
  final int? vehicleYear;
  final String? profileImageUrl;
  final double rating;
  final int totalRides;
  final double totalEarnings;
  final double availableBalance;
  final int? stateRank;  // Ranking estatal basado en puntos de clientes
  final int? usaRank;    // Ranking nacional USA basado en puntos de clientes
  final String? state;   // Estado del driver (para ranking estatal)
  final bool isOnline;
  final bool isVerified;
  final bool isActive;
  final double? currentLat;
  final double? currentLng;
  final DateTime? locationUpdatedAt;
  final String role; // 'driver' or 'organizer'
  final bool canOrganize; // Whether this driver can organize tourism events
  final DriverStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Tourism mode fields
  final String vehicleMode; // 'personal' or 'tourism'
  final String? activeTourismEventId;

  // Driver credential / business card fields
  final String? contactEmail;
  final String? contactPhone;
  final String? contactFacebook;
  final String? businessCardUrl;

  // Country & tax fields (MX/US)
  final String countryCode; // 'US' or 'MX'
  final String? rfc; // Mexico: Registro Federal de Contribuyentes
  final bool rfcValidated;
  final String? curp; // Mexico: Clave Única de Registro de Población
  final String? stateCode; // State/entity code

  // Document fields - synced with admin panel
  final String? licenseNumber;
  final DateTime? licenseExpiry;
  final String? insurancePolicy;
  final DateTime? insuranceExpiry;
  final String? rideshareEndorsementId;
  final DateTime? rideshareEndorsementExpiry;
  final String? qrCode;

  // Onboarding document status - Uber-style
  final bool agreementSigned;
  final bool icaSigned;
  final bool safetyPolicySigned;
  final bool bgcConsentSigned;

  // Admin approval fields
  final bool adminApproved;
  final DateTime? adminApprovedAt;
  final String? onboardingStage;
  final bool canReceiveRides;

  // Compatibility fields (not in DB but used by UI)
  final String? username;
  final String? currentVehicleId;
  final int totalHours;
  final double acceptanceRate;
  final bool isEmailVerified;
  final Map<String, dynamic> preferences;

  // Computed properties for compatibility
  String get firstName {
    final parts = name.split(' ');
    return parts.isNotEmpty ? parts.first : '';
  }

  String get lastName {
    final parts = name.split(' ');
    return parts.length > 1 ? parts.sublist(1).join(' ') : '';
  }

  String get fullName => name;

  // For compatibility with old code
  bool get termsAccepted => isVerified;

  // Check if all required documents are signed
  bool get allDocumentsSigned => agreementSigned && icaSigned && safetyPolicySigned && bgcConsentSigned;

  // Check if driver can go online (all docs + admin approved)
  bool get canGoOnline => allDocumentsSigned && adminApproved && canReceiveRides && onboardingStage == 'approved';

  DriverModel({
    required this.id,
    this.odUserId,
    required this.email,
    required this.phone,
    required this.name,
    this.vehicleType,
    this.vehiclePlate,
    this.vehicleModel,
    this.profileImageUrl,
    this.rating = 5.0,
    this.totalRides = 0,
    this.totalEarnings = 0.0,
    this.stateRank,
    this.usaRank,
    this.state,
    this.isOnline = false,
    this.isVerified = false,
    this.isActive = true,
    this.currentLat,
    this.currentLng,
    this.role = 'driver',
    this.canOrganize = false,
    this.status = DriverStatus.pending,
    required this.createdAt,
    required this.updatedAt,
    // Additional fields
    this.address,
    this.vehicleMake,
    this.vehicleColor,
    this.vehicleYear,
    this.availableBalance = 0.0,
    this.locationUpdatedAt,
    // Document fields - synced with admin
    this.licenseNumber,
    this.licenseExpiry,
    this.insurancePolicy,
    this.insuranceExpiry,
    this.rideshareEndorsementId,
    this.rideshareEndorsementExpiry,
    this.qrCode,
    // Onboarding document status
    this.agreementSigned = false,
    this.icaSigned = false,
    this.safetyPolicySigned = false,
    this.bgcConsentSigned = false,
    // Admin approval fields
    this.adminApproved = false,
    this.adminApprovedAt,
    this.onboardingStage,
    this.canReceiveRides = false,
    // Tourism mode
    this.vehicleMode = 'personal',
    this.activeTourismEventId,
    // Driver credential / business card
    this.contactEmail,
    this.contactPhone,
    this.contactFacebook,
    this.businessCardUrl,
    // Country & tax fields
    this.countryCode = 'MX',
    this.rfc,
    this.rfcValidated = false,
    this.curp,
    this.stateCode,
    // Compatibility fields
    this.username,
    this.currentVehicleId,
    this.totalHours = 0,
    this.acceptanceRate = 1.0,
    this.isEmailVerified = false,
    this.preferences = const {},
  });

  // Alternative constructor for compatibility with old code
  factory DriverModel.fromNames({
    required String id,
    String? odUserId,
    required String email,
    required String phone,
    required String firstName,
    required String lastName,
    String? vehicleType,
    String? vehiclePlate,
    String? vehicleModel,
    String? profileImageUrl,
    double rating = 5.0,
    int totalRides = 0,
    double totalEarnings = 0.0,
    bool isOnline = false,
    bool isVerified = false,
    bool isActive = true,
    double? currentLat,
    double? currentLng,
    DriverStatus status = DriverStatus.pending,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? username,
    String? licenseNumber,
    String? currentVehicleId,
    int totalHours = 0,
    double acceptanceRate = 1.0,
    bool isEmailVerified = false,
    Map<String, dynamic> preferences = const {},
  }) {
    return DriverModel(
      id: id,
      odUserId: odUserId,
      email: email,
      phone: phone,
      name: '$firstName $lastName'.trim(),
      vehicleType: vehicleType,
      vehiclePlate: vehiclePlate,
      vehicleModel: vehicleModel,
      profileImageUrl: profileImageUrl,
      rating: rating,
      totalRides: totalRides,
      totalEarnings: totalEarnings,
      isOnline: isOnline,
      isVerified: isVerified,
      isActive: isActive,
      currentLat: currentLat,
      currentLng: currentLng,
      status: status,
      createdAt: createdAt,
      updatedAt: updatedAt,
      username: username,
      licenseNumber: licenseNumber,
      currentVehicleId: currentVehicleId,
      totalHours: totalHours,
      acceptanceRate: acceptanceRate,
      isEmailVerified: isEmailVerified,
      preferences: preferences,
    );
  }

  factory DriverModel.fromJson(Map<String, dynamic> json) {
    return DriverModel(
      id: json['id'] as String,
      odUserId: json['user_id'] as String?,
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      name: json['name'] as String? ?? '',
      address: json['address'] as String?,
      vehicleType: json['vehicle_type'] as String?,
      vehiclePlate: json['vehicle_plate'] as String?,
      vehicleModel: json['vehicle_model'] as String?,
      vehicleMake: json['vehicle_make'] as String?,
      vehicleColor: json['vehicle_color'] as String?,
      vehicleYear: json['vehicle_year'] as int?,
      profileImageUrl: json['profile_image_url'] as String?,
      rating: (json['rating'] as num?)?.toDouble() ?? 5.0,
      totalRides: json['total_rides'] as int? ?? 0,
      totalEarnings: (json['total_earnings'] as num?)?.toDouble() ?? 0.0,
      availableBalance: (json['available_balance'] as num?)?.toDouble() ?? 0.0,
      stateRank: json['state_rank'] as int?,
      usaRank: json['usa_rank'] as int?,
      state: json['state'] as String?,
      isOnline: json['is_online'] as bool? ?? false,
      isVerified: json['is_verified'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      currentLat: (json['current_lat'] as num?)?.toDouble(),
      currentLng: (json['current_lng'] as num?)?.toDouble(),
      locationUpdatedAt: json['location_updated_at'] != null
          ? DateTime.parse(json['location_updated_at'] as String)
          : null,
      role: json['role'] as String? ?? 'driver',
      canOrganize: json['can_organize'] as bool? ?? false,
      status: DriverStatusExtension.fromString(json['status'] as String?),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      // Document fields
      licenseNumber: json['license_number'] as String?,
      licenseExpiry: json['license_expiry'] != null
          ? DateTime.parse(json['license_expiry'] as String)
          : null,
      insurancePolicy: json['insurance_policy'] as String?,
      insuranceExpiry: json['insurance_expiry'] != null
          ? DateTime.parse(json['insurance_expiry'] as String)
          : null,
      rideshareEndorsementId: json['rideshare_endorsement_id'] as String?,
      rideshareEndorsementExpiry: json['rideshare_endorsement_expiry'] != null
          ? DateTime.parse(json['rideshare_endorsement_expiry'] as String)
          : null,
      qrCode: json['qr_code'] as String?,
      // Onboarding document status
      agreementSigned: json['agreement_signed'] as bool? ?? false,
      icaSigned: json['ica_signed'] as bool? ?? false,
      safetyPolicySigned: json['safety_policy_signed'] as bool? ?? false,
      bgcConsentSigned: json['bgc_consent_signed'] as bool? ?? false,
      // Admin approval fields
      adminApproved: json['admin_approved'] as bool? ?? false,
      adminApprovedAt: json['admin_approved_at'] != null
          ? DateTime.parse(json['admin_approved_at'] as String)
          : null,
      onboardingStage: json['onboarding_stage'] as String?,
      canReceiveRides: json['can_receive_rides'] as bool? ?? false,
      // Tourism mode
      vehicleMode: json['vehicle_mode'] as String? ?? 'personal',
      activeTourismEventId: json['active_tourism_event_id'] as String?,
      // Driver credential / business card
      contactEmail: json['contact_email'] as String?,
      contactPhone: json['contact_phone'] as String?,
      contactFacebook: json['contact_facebook'] as String?,
      businessCardUrl: json['business_card_url'] as String?,
      // Country & tax fields
      countryCode: json['country_code'] as String? ?? 'MX',
      rfc: json['rfc'] as String?,
      rfcValidated: json['rfc_validated'] as bool? ?? false,
      curp: json['curp'] as String?,
      stateCode: json['state_code'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': odUserId,
      'email': email,
      'phone': phone,
      'name': name,
      'address': address,
      'vehicle_type': vehicleType,
      'vehicle_plate': vehiclePlate,
      'vehicle_model': vehicleModel,
      'vehicle_make': vehicleMake,
      'vehicle_color': vehicleColor,
      'vehicle_year': vehicleYear,
      'profile_image_url': profileImageUrl,
      'rating': rating,
      'total_rides': totalRides,
      'total_earnings': totalEarnings,
      'available_balance': availableBalance,
      'state_rank': stateRank,
      'usa_rank': usaRank,
      'state': state,
      'is_online': isOnline,
      'is_verified': isVerified,
      'is_active': isActive,
      'current_lat': currentLat,
      'current_lng': currentLng,
      'location_updated_at': locationUpdatedAt?.toIso8601String(),
      'role': role,
      'can_organize': canOrganize,
      'status': status.value,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      // Document fields
      'license_number': licenseNumber,
      'license_expiry': licenseExpiry?.toIso8601String(),
      'insurance_policy': insurancePolicy,
      'insurance_expiry': insuranceExpiry?.toIso8601String(),
      'rideshare_endorsement_id': rideshareEndorsementId,
      'rideshare_endorsement_expiry': rideshareEndorsementExpiry?.toIso8601String(),
      'qr_code': qrCode,
      // Onboarding document status
      'agreement_signed': agreementSigned,
      'ica_signed': icaSigned,
      'safety_policy_signed': safetyPolicySigned,
      'bgc_consent_signed': bgcConsentSigned,
      // Admin approval fields
      'admin_approved': adminApproved,
      'admin_approved_at': adminApprovedAt?.toIso8601String(),
      'onboarding_stage': onboardingStage,
      'can_receive_rides': canReceiveRides,
      // Tourism mode
      'vehicle_mode': vehicleMode,
      'active_tourism_event_id': activeTourismEventId,
      // Driver credential / business card
      'contact_email': contactEmail,
      'contact_phone': contactPhone,
      'contact_facebook': contactFacebook,
      'business_card_url': businessCardUrl,
      // Country & tax fields
      'country_code': countryCode,
      'rfc': rfc,
      'rfc_validated': rfcValidated,
      'curp': curp,
      'state_code': stateCode,
    };
  }

  DriverModel copyWith({
    String? id,
    String? odUserId,
    String? email,
    String? phone,
    String? name,
    String? firstName, // For compatibility - will update name
    String? lastName,  // For compatibility - will update name
    String? address,
    String? vehicleType,
    String? vehiclePlate,
    String? vehicleModel,
    String? vehicleMake,
    String? vehicleColor,
    int? vehicleYear,
    String? profileImageUrl,
    double? rating,
    int? totalRides,
    double? totalEarnings,
    double? availableBalance,
    int? stateRank,
    int? usaRank,
    String? state,
    bool? isOnline,
    bool? isVerified,
    bool? isActive,
    double? currentLat,
    double? currentLng,
    DateTime? locationUpdatedAt,
    String? role,
    DriverStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    // Document fields
    String? licenseNumber,
    DateTime? licenseExpiry,
    String? insurancePolicy,
    DateTime? insuranceExpiry,
    String? rideshareEndorsementId,
    DateTime? rideshareEndorsementExpiry,
    String? qrCode,
    // Onboarding document status
    bool? agreementSigned,
    bool? icaSigned,
    bool? safetyPolicySigned,
    bool? bgcConsentSigned,
    // Admin approval fields
    bool? adminApproved,
    DateTime? adminApprovedAt,
    String? onboardingStage,
    bool? canReceiveRides,
    // Tourism mode
    String? vehicleMode,
    String? activeTourismEventId,
    // Driver credential / business card
    String? contactEmail,
    String? contactPhone,
    String? contactFacebook,
    String? businessCardUrl,
    // Country & tax fields
    String? countryCode,
    String? rfc,
    bool? rfcValidated,
    String? curp,
    String? stateCode,
    // Compatibility fields
    String? username,
    String? currentVehicleId,
    int? totalHours,
    double? acceptanceRate,
    bool? isEmailVerified,
    Map<String, dynamic>? preferences,
  }) {
    // Handle firstName/lastName updates
    String newName = name ?? this.name;
    if (firstName != null || lastName != null) {
      final fn = firstName ?? this.firstName;
      final ln = lastName ?? this.lastName;
      newName = '$fn $ln'.trim();
    }

    return DriverModel(
      id: id ?? this.id,
      odUserId: odUserId ?? this.odUserId,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      name: newName,
      address: address ?? this.address,
      vehicleType: vehicleType ?? this.vehicleType,
      vehiclePlate: vehiclePlate ?? this.vehiclePlate,
      vehicleModel: vehicleModel ?? this.vehicleModel,
      vehicleMake: vehicleMake ?? this.vehicleMake,
      vehicleColor: vehicleColor ?? this.vehicleColor,
      vehicleYear: vehicleYear ?? this.vehicleYear,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      rating: rating ?? this.rating,
      totalRides: totalRides ?? this.totalRides,
      totalEarnings: totalEarnings ?? this.totalEarnings,
      availableBalance: availableBalance ?? this.availableBalance,
      stateRank: stateRank ?? this.stateRank,
      usaRank: usaRank ?? this.usaRank,
      state: state ?? this.state,
      isOnline: isOnline ?? this.isOnline,
      isVerified: isVerified ?? this.isVerified,
      isActive: isActive ?? this.isActive,
      currentLat: currentLat ?? this.currentLat,
      currentLng: currentLng ?? this.currentLng,
      locationUpdatedAt: locationUpdatedAt ?? this.locationUpdatedAt,
      role: role ?? this.role,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      // Document fields
      licenseNumber: licenseNumber ?? this.licenseNumber,
      licenseExpiry: licenseExpiry ?? this.licenseExpiry,
      insurancePolicy: insurancePolicy ?? this.insurancePolicy,
      insuranceExpiry: insuranceExpiry ?? this.insuranceExpiry,
      rideshareEndorsementId: rideshareEndorsementId ?? this.rideshareEndorsementId,
      rideshareEndorsementExpiry: rideshareEndorsementExpiry ?? this.rideshareEndorsementExpiry,
      qrCode: qrCode ?? this.qrCode,
      // Onboarding document status
      agreementSigned: agreementSigned ?? this.agreementSigned,
      icaSigned: icaSigned ?? this.icaSigned,
      safetyPolicySigned: safetyPolicySigned ?? this.safetyPolicySigned,
      bgcConsentSigned: bgcConsentSigned ?? this.bgcConsentSigned,
      // Admin approval fields
      adminApproved: adminApproved ?? this.adminApproved,
      adminApprovedAt: adminApprovedAt ?? this.adminApprovedAt,
      onboardingStage: onboardingStage ?? this.onboardingStage,
      canReceiveRides: canReceiveRides ?? this.canReceiveRides,
      // Tourism mode
      vehicleMode: vehicleMode ?? this.vehicleMode,
      activeTourismEventId: activeTourismEventId ?? this.activeTourismEventId,
      // Driver credential / business card
      contactEmail: contactEmail ?? this.contactEmail,
      contactPhone: contactPhone ?? this.contactPhone,
      contactFacebook: contactFacebook ?? this.contactFacebook,
      businessCardUrl: businessCardUrl ?? this.businessCardUrl,
      // Country & tax fields
      countryCode: countryCode ?? this.countryCode,
      rfc: rfc ?? this.rfc,
      rfcValidated: rfcValidated ?? this.rfcValidated,
      curp: curp ?? this.curp,
      stateCode: stateCode ?? this.stateCode,
      // Compatibility fields
      username: username ?? this.username,
      currentVehicleId: currentVehicleId ?? this.currentVehicleId,
      totalHours: totalHours ?? this.totalHours,
      acceptanceRate: acceptanceRate ?? this.acceptanceRate,
      isEmailVerified: isEmailVerified ?? this.isEmailVerified,
      preferences: preferences ?? this.preferences,
    );
  }
}
