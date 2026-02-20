class OrganizerModel {
  final String id;
  final String userId;
  final String? companyName;
  final String? phone;
  final String? state;
  final String countryCode;
  final bool isVerified;
  final double commissionRate;
  final double totalEarnings;
  final String? stripeAccountId;
  final String? createdAt;
  final String? updatedAt;

  // Agreement / contract fields
  final bool agreementSigned;
  final String? agreementSignedAt;
  final String? agreementCountry;
  final String? agreementState;
  final String? agreementDocumentHash;
  final String? agreementSessionId;

  OrganizerModel({
    required this.id,
    required this.userId,
    this.companyName,
    this.phone,
    this.state,
    required this.countryCode,
    this.isVerified = false,
    this.commissionRate = 0.0,
    this.totalEarnings = 0.0,
    this.stripeAccountId,
    this.createdAt,
    this.updatedAt,
    this.agreementSigned = false,
    this.agreementSignedAt,
    this.agreementCountry,
    this.agreementState,
    this.agreementDocumentHash,
    this.agreementSessionId,
  });

  factory OrganizerModel.fromJson(Map<String, dynamic> json) {
    return OrganizerModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      companyName: json['company_name'] as String?,
      phone: json['phone'] as String?,
      state: json['state'] as String?,
      countryCode: json['country_code'] as String? ?? '',
      isVerified: json['is_verified'] as bool? ?? false,
      commissionRate: (json['commission_rate'] as num?)?.toDouble() ?? 0.0,
      totalEarnings: (json['total_earnings'] as num?)?.toDouble() ?? 0.0,
      stripeAccountId: json['stripe_account_id'] as String?,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
      agreementSigned: json['agreement_signed'] as bool? ?? false,
      agreementSignedAt: json['agreement_signed_at'] as String?,
      agreementCountry: json['agreement_country'] as String?,
      agreementState: json['agreement_state'] as String?,
      agreementDocumentHash: json['agreement_document_hash'] as String?,
      agreementSessionId: json['agreement_session_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'company_name': companyName,
      'phone': phone,
      'state': state,
      'country_code': countryCode,
      'is_verified': isVerified,
      'commission_rate': commissionRate,
      'total_earnings': totalEarnings,
      'stripe_account_id': stripeAccountId,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'agreement_signed': agreementSigned,
      'agreement_signed_at': agreementSignedAt,
      'agreement_country': agreementCountry,
      'agreement_state': agreementState,
      'agreement_document_hash': agreementDocumentHash,
      'agreement_session_id': agreementSessionId,
    };
  }

  OrganizerModel copyWith({
    String? id,
    String? userId,
    String? companyName,
    String? phone,
    String? state,
    String? countryCode,
    bool? isVerified,
    double? commissionRate,
    double? totalEarnings,
    String? stripeAccountId,
    String? createdAt,
    String? updatedAt,
    bool? agreementSigned,
    String? agreementSignedAt,
    String? agreementCountry,
    String? agreementState,
    String? agreementDocumentHash,
    String? agreementSessionId,
  }) {
    return OrganizerModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      companyName: companyName ?? this.companyName,
      phone: phone ?? this.phone,
      state: state ?? this.state,
      countryCode: countryCode ?? this.countryCode,
      isVerified: isVerified ?? this.isVerified,
      commissionRate: commissionRate ?? this.commissionRate,
      totalEarnings: totalEarnings ?? this.totalEarnings,
      stripeAccountId: stripeAccountId ?? this.stripeAccountId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      agreementSigned: agreementSigned ?? this.agreementSigned,
      agreementSignedAt: agreementSignedAt ?? this.agreementSignedAt,
      agreementCountry: agreementCountry ?? this.agreementCountry,
      agreementState: agreementState ?? this.agreementState,
      agreementDocumentHash: agreementDocumentHash ?? this.agreementDocumentHash,
      agreementSessionId: agreementSessionId ?? this.agreementSessionId,
    );
  }
}
