// Package delivery enums matching SQL schema
enum ServiceType { normal, express, carpoolPackage }

enum PackageSize { small, medium, large }

enum DeliveryStatus {
  draft,
  pending,
  accepted,
  driverEnRoute,
  pickedUp,
  inTransit,
  delivered,
  cancelled,
}

enum PaymentStatus { pending, authorized, captured, failed, refunded }

enum DeliveryLocation {
  frontDoor,
  backDoor,
  sideDoor,
  lobby,
  mailroom,
  other,
}

class PackageDeliveryModel {
  final String id;
  final String? visaTripNumber;
  final String? userId;
  final ServiceType serviceType;

  // Pickup info
  final String pickupAddress;
  final double pickupLat;
  final double pickupLng;
  final DateTime pickupTime;

  // Destination info
  final String destinationAddress;
  final double destinationLat;
  final double destinationLng;

  // Package info
  final String? packageDescription;
  final String? photoUrl;
  final PackageSize size;
  final int packageQuantity;
  final String? driverNotes;
  final DeliveryLocation deliveryLocation;
  final String? otherLocationDetails;
  final String senderName;
  final String recipientName;

  // Driver info
  final String? driverId;
  final double? driverLat;
  final double? driverLng;
  final int? etaMinutes;

  // Pricing
  final double estimatedPrice;
  final double? finalPrice;
  final double distanceMiles;
  final int estimatedMinutes;
  final double tipAmount;
  final double platformFee;
  final double driverEarnings;
  final double cancellationFee;

  // Payment
  final PaymentStatus paymentStatus;
  final String? stripePaymentIntentId;
  final String? stripeChargeId;

  // Status
  final DeliveryStatus status;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final DateTime? cancelledAt;
  final String? cancellationReason;

  // Customer mood
  final String? customerMoodEmoji;
  final String? customerMoodText;
  final int? customerMoodPercentage;
  final int? customerRankState;
  final int? customerRankUsa;

  // Route
  final List<Map<String, dynamic>> routePoints;

  final DateTime? updatedAt;

  PackageDeliveryModel({
    required this.id,
    this.visaTripNumber,
    this.userId,
    this.serviceType = ServiceType.normal,
    required this.pickupAddress,
    required this.pickupLat,
    required this.pickupLng,
    required this.pickupTime,
    required this.destinationAddress,
    required this.destinationLat,
    required this.destinationLng,
    this.packageDescription,
    this.photoUrl,
    this.size = PackageSize.medium,
    this.packageQuantity = 1,
    this.driverNotes,
    this.deliveryLocation = DeliveryLocation.frontDoor,
    this.otherLocationDetails,
    required this.senderName,
    required this.recipientName,
    this.driverId,
    this.driverLat,
    this.driverLng,
    this.etaMinutes,
    required this.estimatedPrice,
    this.finalPrice,
    required this.distanceMiles,
    required this.estimatedMinutes,
    this.tipAmount = 0,
    this.platformFee = 0,
    this.driverEarnings = 0,
    this.cancellationFee = 0,
    this.paymentStatus = PaymentStatus.pending,
    this.stripePaymentIntentId,
    this.stripeChargeId,
    this.status = DeliveryStatus.draft,
    required this.createdAt,
    this.acceptedAt,
    this.pickedUpAt,
    this.deliveredAt,
    this.cancelledAt,
    this.cancellationReason,
    this.customerMoodEmoji,
    this.customerMoodText,
    this.customerMoodPercentage,
    this.customerRankState,
    this.customerRankUsa,
    this.routePoints = const [],
    this.updatedAt,
  });

  factory PackageDeliveryModel.fromJson(Map<String, dynamic> json) {
    return PackageDeliveryModel(
      id: json['id'] as String,
      visaTripNumber: json['visa_trip_number'] as String?,
      userId: json['user_id'] as String?,
      serviceType: ServiceType.values.firstWhere(
        (e) => e.name == json['service_type'],
        orElse: () => ServiceType.normal,
      ),
      pickupAddress: json['pickup_address'] as String,
      pickupLat: (json['pickup_lat'] as num).toDouble(),
      pickupLng: (json['pickup_lng'] as num).toDouble(),
      pickupTime: DateTime.parse(json['pickup_time'] as String),
      destinationAddress: json['destination_address'] as String,
      destinationLat: (json['destination_lat'] as num).toDouble(),
      destinationLng: (json['destination_lng'] as num).toDouble(),
      packageDescription: json['package_description'] as String?,
      photoUrl: json['photo_url'] as String?,
      size: PackageSize.values.firstWhere(
        (e) => e.name == json['size'],
        orElse: () => PackageSize.medium,
      ),
      packageQuantity: json['package_quantity'] as int? ?? 1,
      driverNotes: json['driver_notes'] as String?,
      deliveryLocation: DeliveryLocation.values.firstWhere(
        (e) => e.name == json['delivery_location'],
        orElse: () => DeliveryLocation.frontDoor,
      ),
      otherLocationDetails: json['other_location_details'] as String?,
      senderName: json['sender_name'] as String,
      recipientName: json['recipient_name'] as String,
      driverId: json['driver_id'] as String?,
      driverLat: (json['driver_lat'] as num?)?.toDouble(),
      driverLng: (json['driver_lng'] as num?)?.toDouble(),
      etaMinutes: json['eta_minutes'] as int?,
      estimatedPrice: (json['estimated_price'] as num).toDouble(),
      finalPrice: (json['final_price'] as num?)?.toDouble(),
      distanceMiles: (json['distance_miles'] as num).toDouble(),
      estimatedMinutes: json['estimated_minutes'] as int,
      tipAmount: (json['tip_amount'] as num?)?.toDouble() ?? 0,
      platformFee: (json['platform_fee'] as num?)?.toDouble() ?? 0,
      driverEarnings: (json['driver_earnings'] as num?)?.toDouble() ?? 0,
      cancellationFee: (json['cancellation_fee'] as num?)?.toDouble() ?? 0,
      paymentStatus: PaymentStatus.values.firstWhere(
        (e) => e.name == json['payment_status'],
        orElse: () => PaymentStatus.pending,
      ),
      stripePaymentIntentId: json['stripe_payment_intent_id'] as String?,
      stripeChargeId: json['stripe_charge_id'] as String?,
      status: DeliveryStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => DeliveryStatus.draft,
      ),
      createdAt: DateTime.parse(json['created_at'] as String),
      acceptedAt: json['accepted_at'] != null
          ? DateTime.parse(json['accepted_at'] as String)
          : null,
      pickedUpAt: json['picked_up_at'] != null
          ? DateTime.parse(json['picked_up_at'] as String)
          : null,
      deliveredAt: json['delivered_at'] != null
          ? DateTime.parse(json['delivered_at'] as String)
          : null,
      cancelledAt: json['cancelled_at'] != null
          ? DateTime.parse(json['cancelled_at'] as String)
          : null,
      cancellationReason: json['cancellation_reason'] as String?,
      customerMoodEmoji: json['customer_mood_emoji'] as String?,
      customerMoodText: json['customer_mood_text'] as String?,
      customerMoodPercentage: json['customer_mood_percentage'] as int?,
      customerRankState: json['customer_rank_state'] as int?,
      customerRankUsa: json['customer_rank_usa'] as int?,
      routePoints: (json['route_points'] as List<dynamic>?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [],
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'visa_trip_number': visaTripNumber,
      'user_id': userId,
      'service_type': serviceType.name,
      'pickup_address': pickupAddress,
      'pickup_lat': pickupLat,
      'pickup_lng': pickupLng,
      'pickup_time': pickupTime.toIso8601String(),
      'destination_address': destinationAddress,
      'destination_lat': destinationLat,
      'destination_lng': destinationLng,
      'package_description': packageDescription,
      'photo_url': photoUrl,
      'size': size.name,
      'package_quantity': packageQuantity,
      'driver_notes': driverNotes,
      'delivery_location': deliveryLocation.name,
      'other_location_details': otherLocationDetails,
      'sender_name': senderName,
      'recipient_name': recipientName,
      'driver_id': driverId,
      'driver_lat': driverLat,
      'driver_lng': driverLng,
      'eta_minutes': etaMinutes,
      'estimated_price': estimatedPrice,
      'final_price': finalPrice,
      'distance_miles': distanceMiles,
      'estimated_minutes': estimatedMinutes,
      'tip_amount': tipAmount,
      'platform_fee': platformFee,
      'driver_earnings': driverEarnings,
      'cancellation_fee': cancellationFee,
      'payment_status': paymentStatus.name,
      'stripe_payment_intent_id': stripePaymentIntentId,
      'stripe_charge_id': stripeChargeId,
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
      'accepted_at': acceptedAt?.toIso8601String(),
      'picked_up_at': pickedUpAt?.toIso8601String(),
      'delivered_at': deliveredAt?.toIso8601String(),
      'cancelled_at': cancelledAt?.toIso8601String(),
      'cancellation_reason': cancellationReason,
      'customer_mood_emoji': customerMoodEmoji,
      'customer_mood_text': customerMoodText,
      'customer_mood_percentage': customerMoodPercentage,
      'customer_rank_state': customerRankState,
      'customer_rank_usa': customerRankUsa,
      'route_points': routePoints,
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  PackageDeliveryModel copyWith({
    String? id,
    String? visaTripNumber,
    String? userId,
    ServiceType? serviceType,
    String? pickupAddress,
    double? pickupLat,
    double? pickupLng,
    DateTime? pickupTime,
    String? destinationAddress,
    double? destinationLat,
    double? destinationLng,
    String? packageDescription,
    String? photoUrl,
    PackageSize? size,
    int? packageQuantity,
    String? driverNotes,
    DeliveryLocation? deliveryLocation,
    String? otherLocationDetails,
    String? senderName,
    String? recipientName,
    String? driverId,
    double? driverLat,
    double? driverLng,
    int? etaMinutes,
    double? estimatedPrice,
    double? finalPrice,
    double? distanceMiles,
    int? estimatedMinutes,
    double? tipAmount,
    double? platformFee,
    double? driverEarnings,
    double? cancellationFee,
    PaymentStatus? paymentStatus,
    String? stripePaymentIntentId,
    String? stripeChargeId,
    DeliveryStatus? status,
    DateTime? createdAt,
    DateTime? acceptedAt,
    DateTime? pickedUpAt,
    DateTime? deliveredAt,
    DateTime? cancelledAt,
    String? cancellationReason,
    String? customerMoodEmoji,
    String? customerMoodText,
    int? customerMoodPercentage,
    int? customerRankState,
    int? customerRankUsa,
    List<Map<String, dynamic>>? routePoints,
    DateTime? updatedAt,
  }) {
    return PackageDeliveryModel(
      id: id ?? this.id,
      visaTripNumber: visaTripNumber ?? this.visaTripNumber,
      userId: userId ?? this.userId,
      serviceType: serviceType ?? this.serviceType,
      pickupAddress: pickupAddress ?? this.pickupAddress,
      pickupLat: pickupLat ?? this.pickupLat,
      pickupLng: pickupLng ?? this.pickupLng,
      pickupTime: pickupTime ?? this.pickupTime,
      destinationAddress: destinationAddress ?? this.destinationAddress,
      destinationLat: destinationLat ?? this.destinationLat,
      destinationLng: destinationLng ?? this.destinationLng,
      packageDescription: packageDescription ?? this.packageDescription,
      photoUrl: photoUrl ?? this.photoUrl,
      size: size ?? this.size,
      packageQuantity: packageQuantity ?? this.packageQuantity,
      driverNotes: driverNotes ?? this.driverNotes,
      deliveryLocation: deliveryLocation ?? this.deliveryLocation,
      otherLocationDetails: otherLocationDetails ?? this.otherLocationDetails,
      senderName: senderName ?? this.senderName,
      recipientName: recipientName ?? this.recipientName,
      driverId: driverId ?? this.driverId,
      driverLat: driverLat ?? this.driverLat,
      driverLng: driverLng ?? this.driverLng,
      etaMinutes: etaMinutes ?? this.etaMinutes,
      estimatedPrice: estimatedPrice ?? this.estimatedPrice,
      finalPrice: finalPrice ?? this.finalPrice,
      distanceMiles: distanceMiles ?? this.distanceMiles,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      tipAmount: tipAmount ?? this.tipAmount,
      platformFee: platformFee ?? this.platformFee,
      driverEarnings: driverEarnings ?? this.driverEarnings,
      cancellationFee: cancellationFee ?? this.cancellationFee,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      stripePaymentIntentId:
          stripePaymentIntentId ?? this.stripePaymentIntentId,
      stripeChargeId: stripeChargeId ?? this.stripeChargeId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      pickedUpAt: pickedUpAt ?? this.pickedUpAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      customerMoodEmoji: customerMoodEmoji ?? this.customerMoodEmoji,
      customerMoodText: customerMoodText ?? this.customerMoodText,
      customerMoodPercentage:
          customerMoodPercentage ?? this.customerMoodPercentage,
      customerRankState: customerRankState ?? this.customerRankState,
      customerRankUsa: customerRankUsa ?? this.customerRankUsa,
      routePoints: routePoints ?? this.routePoints,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Helper getters
  bool get isActive => status == DeliveryStatus.accepted ||
      status == DeliveryStatus.driverEnRoute ||
      status == DeliveryStatus.pickedUp ||
      status == DeliveryStatus.inTransit;

  bool get isCompleted => status == DeliveryStatus.delivered;
  bool get isCancelled => status == DeliveryStatus.cancelled;

  String get statusDisplay {
    switch (status) {
      case DeliveryStatus.draft:
        return 'Borrador';
      case DeliveryStatus.pending:
        return 'Pendiente';
      case DeliveryStatus.accepted:
        return 'Aceptado';
      case DeliveryStatus.driverEnRoute:
        return 'En camino';
      case DeliveryStatus.pickedUp:
        return 'Recogido';
      case DeliveryStatus.inTransit:
        return 'En tránsito';
      case DeliveryStatus.delivered:
        return 'Entregado';
      case DeliveryStatus.cancelled:
        return 'Cancelado';
    }
  }

  String get sizeDisplay {
    switch (size) {
      case PackageSize.small:
        return 'Pequeño';
      case PackageSize.medium:
        return 'Mediano';
      case PackageSize.large:
        return 'Grande';
    }
  }

  double get totalEarnings => driverEarnings + tipAmount;
}

// Driver Ticket model (snapshot for driver view)
class DriverTicketModel {
  final String id;
  final String deliveryId;
  final String? driverId;
  final String pickupAddress;
  final double pickupLat;
  final double pickupLng;
  final String destinationAddress;
  final double destinationLat;
  final double destinationLng;
  final double distanceMiles;
  final int estimatedMinutes;
  final double driverEarnings;
  final double tipAmount;
  final PackageSize? packageSize;
  final int packageQuantity;
  final String? notes;
  final String? customerMoodEmoji;
  final String? customerMoodText;
  final String status;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? completedAt;

  DriverTicketModel({
    required this.id,
    required this.deliveryId,
    this.driverId,
    required this.pickupAddress,
    required this.pickupLat,
    required this.pickupLng,
    required this.destinationAddress,
    required this.destinationLat,
    required this.destinationLng,
    required this.distanceMiles,
    required this.estimatedMinutes,
    required this.driverEarnings,
    this.tipAmount = 0,
    this.packageSize,
    this.packageQuantity = 1,
    this.notes,
    this.customerMoodEmoji,
    this.customerMoodText,
    this.status = 'available',
    required this.createdAt,
    this.acceptedAt,
    this.completedAt,
  });

  factory DriverTicketModel.fromJson(Map<String, dynamic> json) {
    return DriverTicketModel(
      id: json['id'] as String,
      deliveryId: json['delivery_id'] as String,
      driverId: json['driver_id'] as String?,
      pickupAddress: json['pickup_address'] as String,
      pickupLat: (json['pickup_lat'] as num).toDouble(),
      pickupLng: (json['pickup_lng'] as num).toDouble(),
      destinationAddress: json['destination_address'] as String,
      destinationLat: (json['destination_lat'] as num).toDouble(),
      destinationLng: (json['destination_lng'] as num).toDouble(),
      distanceMiles: (json['distance_miles'] as num).toDouble(),
      estimatedMinutes: json['estimated_minutes'] as int,
      driverEarnings: (json['driver_earnings'] as num).toDouble(),
      tipAmount: (json['tip_amount'] as num?)?.toDouble() ?? 0,
      packageSize: json['package_size'] != null
          ? PackageSize.values.firstWhere(
              (e) => e.name == json['package_size'],
              orElse: () => PackageSize.medium,
            )
          : null,
      packageQuantity: json['package_quantity'] as int? ?? 1,
      notes: json['notes'] as String?,
      customerMoodEmoji: json['customer_mood_emoji'] as String?,
      customerMoodText: json['customer_mood_text'] as String?,
      status: json['status'] as String? ?? 'available',
      createdAt: DateTime.parse(json['created_at'] as String),
      acceptedAt: json['accepted_at'] != null
          ? DateTime.parse(json['accepted_at'] as String)
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'delivery_id': deliveryId,
      'driver_id': driverId,
      'pickup_address': pickupAddress,
      'pickup_lat': pickupLat,
      'pickup_lng': pickupLng,
      'destination_address': destinationAddress,
      'destination_lat': destinationLat,
      'destination_lng': destinationLng,
      'distance_miles': distanceMiles,
      'estimated_minutes': estimatedMinutes,
      'driver_earnings': driverEarnings,
      'tip_amount': tipAmount,
      'package_size': packageSize?.name,
      'package_quantity': packageQuantity,
      'notes': notes,
      'customer_mood_emoji': customerMoodEmoji,
      'customer_mood_text': customerMoodText,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'accepted_at': acceptedAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
    };
  }

  bool get isAvailable => status == 'available';
  bool get isAccepted => status == 'accepted';
  bool get isCompleted => status == 'completed';

  double get totalEarnings => driverEarnings + tipAmount;
}

// Tax summary for IRS 1099-K
class TaxSummary {
  final int totalDeliveries;
  final double grossEarnings;
  final double tipsReceived;
  final double platformFees;
  final double netEarnings;
  final bool needs1099K;

  TaxSummary({
    required this.totalDeliveries,
    required this.grossEarnings,
    required this.tipsReceived,
    required this.platformFees,
    required this.netEarnings,
    required this.needs1099K,
  });

  factory TaxSummary.fromJson(Map<String, dynamic> json) {
    return TaxSummary(
      totalDeliveries: json['total_deliveries'] as int? ?? 0,
      grossEarnings: (json['gross_earnings'] as num?)?.toDouble() ?? 0,
      tipsReceived: (json['tips_received'] as num?)?.toDouble() ?? 0,
      platformFees: (json['platform_fees'] as num?)?.toDouble() ?? 0,
      netEarnings: (json['net_earnings'] as num?)?.toDouble() ?? 0,
      needs1099K: json['needs_1099k'] as bool? ?? false,
    );
  }
}
