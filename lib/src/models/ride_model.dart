enum RideStatus {
  pending,
  accepted,
  arrivedAtPickup, // DB: 'in_progress' + picked_up_at != null
  inProgress,      // DB: 'in_progress' + started_at != null
  completed,       // DB: 'completed'
  cancelled,
}

// Helper to convert client status to driver status
// ACTUAL DB constraint: pending, accepted, in_progress, completed, cancelled
RideStatus parseClientStatus(String? status, {DateTime? pickedUpAt, DateTime? startedAt}) {
  switch (status) {
    case 'pending':
      return RideStatus.pending;
    case 'accepted':
      return RideStatus.accepted;
    case 'in_progress':
      // Distinguir entre arrivedAtPickup e inProgress usando timestamps
      if (startedAt != null) {
        return RideStatus.inProgress;
      }
      return RideStatus.arrivedAtPickup;
    // Legacy values (por si hay datos viejos)
    case 'picked_up':
      return RideStatus.arrivedAtPickup;
    case 'in_transit':
      return RideStatus.inProgress;
    case 'delivered':
      return RideStatus.completed;
    case 'completed':
      return RideStatus.completed;
    case 'cancelled':
      return RideStatus.cancelled;
    default:
      return RideStatus.pending;
  }
}

// Helper to convert driver status to database status string
// ACTUAL DB constraint: pending, accepted, in_progress, completed, cancelled
String statusToDatabase(RideStatus status) {
  switch (status) {
    case RideStatus.pending:
      return 'pending';
    case RideStatus.accepted:
      return 'accepted';
    case RideStatus.arrivedAtPickup:
      return 'in_progress'; // DB no tiene 'picked_up', usa 'in_progress'
    case RideStatus.inProgress:
      return 'in_progress';
    case RideStatus.completed:
      return 'completed'; // DB no tiene 'delivered', usa 'completed'
    case RideStatus.cancelled:
      return 'cancelled';
  }
}

enum RideType {
  passenger, // Maps to 'ride' in client
  package,   // Maps to 'package' in client
  carpool,   // Maps to 'carpool' in client
}

// Helper to convert client service_type to driver RideType
RideType parseServiceType(String? serviceType) {
  switch (serviceType) {
    case 'ride':
      return RideType.passenger;
    case 'package':
      return RideType.package;
    case 'carpool':
      return RideType.carpool;
    default:
      return RideType.package; // Default to package since it's most common
  }
}

enum PaymentMethod {
  card,
  wallet,
}

class LocationPoint {
  final double latitude;
  final double longitude;
  final String? address;

  LocationPoint({
    required this.latitude,
    required this.longitude,
    this.address,
  });

  factory LocationPoint.fromJson(Map<String, dynamic> json) {
    return LocationPoint(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      address: json['address'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
    };
  }
}

class RideModel {
  final String id;
  final String? driverId;
  final String passengerId;
  final String passengerName;
  final String? passengerPhone;
  final String? passengerImageUrl;
  final double passengerRating;
  final int passengerTotalRides;    // Total rides completed by passenger
  final double passengerAverageTip; // Average tip percentage from passenger
  final bool isGoodTipper;          // True if passenger tips > 15% on average
  final bool hidePassengerName;     // Privacy: hide passenger name from driver
  final bool hidePassengerPhoto;    // Privacy: hide passenger photo from driver
  final RideType type;
  final RideStatus status;
  final LocationPoint pickupLocation;
  final LocationPoint dropoffLocation;
  final double distanceKm;
  final int estimatedMinutes;
  final double fare;
  final double tip;
  final double platformFee;
  final double driverEarnings;
  final PaymentMethod paymentMethod;
  final bool isPaid;
  final String? notes;
  final bool isUrgent;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? arrivedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? cancellationReason;
  // Round trip / Carpool fields
  final List<int> recurringDays;           // Days of week (1-7) for recurring rides
  final int filledSeats;                   // Number of passengers in carpool
  final String? linkedReturnBookingId;     // ID of linked return trip
  final bool isRoundTrip;                  // Is part of round trip
  final String? returnTime;                // Formatted return time for display

  // === RIDER LOCATION TRACKING (Para el pickup) ===
  // GPS del rider en tiempo real (actualizado por la app rider)
  final double? riderGpsLat;
  final double? riderGpsLng;
  final DateTime? riderGpsUpdatedAt;

  // Walking pad: ruta caminando del GPS del rider hacia el PIN (pickup)
  // Encoded polyline string
  final String? riderWalkingPad;

  // Flag: Si el ride es para otra persona (no mostrar GPS ni walking pad)
  final bool isBookingForSomeoneElse;

  // === MULTIPLE STOPS / WAYPOINTS ===
  // Lista de paradas intermedias [{name, lat, lng, order}]
  final List<Map<String, dynamic>>? waypoints;

  // === STRIPE PAYMENT ===
  // Payment Intent ID for capturing payment when ride completes
  final String? stripePaymentIntentId;

  RideModel({
    required this.id,
    this.driverId,
    required this.passengerId,
    required this.passengerName,
    this.passengerPhone,
    this.passengerImageUrl,
    this.passengerRating = 0.0,
    this.passengerTotalRides = 0,
    this.passengerAverageTip = 0.0,
    this.isGoodTipper = false,
    this.hidePassengerName = false,
    this.hidePassengerPhoto = false,
    required this.type,
    required this.status,
    required this.pickupLocation,
    required this.dropoffLocation,
    required this.distanceKm,
    required this.estimatedMinutes,
    required this.fare,
    this.tip = 0.0,
    required this.platformFee,
    required this.driverEarnings,
    required this.paymentMethod,
    this.isPaid = false,
    this.notes,
    this.isUrgent = false,
    required this.createdAt,
    this.acceptedAt,
    this.arrivedAt,
    this.startedAt,
    this.completedAt,
    this.cancelledAt,
    this.cancellationReason,
    this.recurringDays = const [],
    this.filledSeats = 1,
    this.linkedReturnBookingId,
    this.isRoundTrip = false,
    this.returnTime,
    // Rider location tracking
    this.riderGpsLat,
    this.riderGpsLng,
    this.riderGpsUpdatedAt,
    this.riderWalkingPad,
    this.isBookingForSomeoneElse = false,
    this.waypoints,
    this.stripePaymentIntentId,
  });

  double get totalEarnings => driverEarnings + tip;

  // Helper: tiene GPS del rider válido (y no es para otra persona)
  bool get hasRiderGps =>
      riderGpsLat != null &&
      riderGpsLng != null &&
      !isBookingForSomeoneElse;

  // Helper: tiene walking pad válido
  bool get hasWalkingPad =>
      riderWalkingPad != null &&
      riderWalkingPad!.isNotEmpty &&
      !isBookingForSomeoneElse;

  // Privacy-aware getters - return anonymous info when privacy is enabled
  // Note: Translation is handled in the UI layer, this returns the key
  String get displayName => hidePassengerName ? 'Anonymous Customer' : passengerName;
  String? get displayImageUrl => hidePassengerPhoto ? null : passengerImageUrl;

  factory RideModel.fromJson(Map<String, dynamic> json) {
    // Handle multiple field formats from different clients
    LocationPoint pickupLocation;
    LocationPoint dropoffLocation;

    if (json['pickup_location'] != null) {
      // Nested format
      pickupLocation = LocationPoint.fromJson(json['pickup_location']);
      dropoffLocation = LocationPoint.fromJson(json['dropoff_location']);
    } else {
      // Flat database format - handle both naming conventions
      // Client uses: pickup_lat/pickup_lng, destination_lat/destination_lng
      // Driver uses: pickup_latitude/pickup_longitude, dropoff_latitude/dropoff_longitude
      pickupLocation = LocationPoint(
        latitude: (json['pickup_lat'] as num?)?.toDouble() ??
                  (json['pickup_latitude'] as num?)?.toDouble() ?? 0.0,
        longitude: (json['pickup_lng'] as num?)?.toDouble() ??
                   (json['pickup_longitude'] as num?)?.toDouble() ?? 0.0,
        address: json['pickup_address'] as String?,
      );
      dropoffLocation = LocationPoint(
        latitude: (json['destination_lat'] as num?)?.toDouble() ??
                  (json['dropoff_latitude'] as num?)?.toDouble() ?? 0.0,
        longitude: (json['destination_lng'] as num?)?.toDouble() ??
                   (json['dropoff_longitude'] as num?)?.toDouble() ?? 0.0,
        address: json['destination_address'] as String? ??
                 json['dropoff_address'] as String?,
      );
    }

    return RideModel(
      id: json['id'] as String? ?? '',
      driverId: json['driver_id'] as String?,
      // Handle both user_id (client) and passenger_id (driver)
      passengerId: json['user_id'] as String? ?? json['passenger_id'] as String? ?? '',
      passengerName: json['passenger_name'] as String? ?? json['sender_name'] as String? ?? 'Cliente',
      passengerPhone: json['passenger_phone'] as String? ?? json['sender_phone'] as String?,
      passengerImageUrl: json['passenger_image_url'] as String?,
      passengerRating: (json['passenger_rating'] as num?)?.toDouble() ??
                       (json['user_rating'] as num?)?.toDouble() ?? 0.0,
      passengerTotalRides: (json['passenger_total_rides'] as num?)?.toInt() ??
                           (json['user_total_rides'] as num?)?.toInt() ?? 0,
      passengerAverageTip: (json['passenger_average_tip'] as num?)?.toDouble() ??
                           (json['user_average_tip'] as num?)?.toDouble() ?? 0.0,
      isGoodTipper: json['is_good_tipper'] as bool? ??
                    json['user_is_good_tipper'] as bool? ?? false,
      // Privacy settings
      hidePassengerName: json['hide_passenger_name'] as bool? ??
                         json['user_hide_name'] as bool? ?? false,
      hidePassengerPhoto: json['hide_passenger_photo'] as bool? ??
                          json['user_hide_photo'] as bool? ?? false,
      // Handle both 'type' (driver format) and 'service_type' (client format)
      type: json['service_type'] != null
          ? parseServiceType(json['service_type'] as String?)
          : RideType.values.firstWhere(
              (e) => e.name == json['type'],
              orElse: () => RideType.package,
            ),
      // Use parseClientStatus to handle client's status values
      // Parse timestamps first to distinguish arrivedAtPickup vs inProgress
      status: parseClientStatus(
        json['status'] as String?,
        pickedUpAt: json['picked_up_at'] != null
            ? DateTime.tryParse(json['picked_up_at'] as String)
            : null,
        startedAt: json['started_at'] != null
            ? DateTime.tryParse(json['started_at'] as String)
            : null,
      ),
      pickupLocation: pickupLocation,
      dropoffLocation: dropoffLocation,
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0.0,
      estimatedMinutes: (json['estimated_minutes'] as num?)?.toInt() ?? 0,
      fare: (json['estimated_price'] as num?)?.toDouble() ??
            (json['total_price'] as num?)?.toDouble() ??
            (json['fare'] as num?)?.toDouble() ?? 0.0,
      tip: (json['tip'] as num?)?.toDouble() ?? 0.0,
      platformFee: (json['platform_fee'] as num?)?.toDouble() ?? 0.0,
      driverEarnings: (json['driver_earnings'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: PaymentMethod.values.firstWhere(
        (e) => e.name == json['payment_method'],
        orElse: () => PaymentMethod.card,
      ),
      isPaid: json['is_paid'] as bool? ?? false,
      notes: json['notes'] as String?,
      isUrgent: json['is_urgent'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      acceptedAt: json['accepted_at'] != null
          ? DateTime.parse(json['accepted_at'] as String)
          : null,
      arrivedAt: json['picked_up_at'] != null
          ? DateTime.parse(json['picked_up_at'] as String)
          : (json['arrived_at'] != null
              ? DateTime.parse(json['arrived_at'] as String)
              : null),
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String)
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      cancelledAt: json['cancelled_at'] != null
          ? DateTime.parse(json['cancelled_at'] as String)
          : null,
      cancellationReason: json['cancellation_reason'] as String?,
      // Round trip / Carpool fields
      recurringDays: (json['recurring_days'] as List?)?.map((e) => e as int).toList() ??
        (json['recurringDays'] as List?)?.map((e) => e as int).toList() ??
        const [],
      filledSeats: (json['filled_seats'] as num?)?.toInt() ??
        (json['filledSeats'] as num?)?.toInt() ?? 1,
      linkedReturnBookingId: json['linked_return_booking_id'] as String? ?? json['linkedReturnBookingId'] as String?,
      isRoundTrip: json['is_round_trip'] as bool? ?? json['isRoundTrip'] as bool? ?? false,
      returnTime: json['return_time'] as String? ?? json['returnTime'] as String?,
      // Rider location tracking
      riderGpsLat: (json['rider_gps_lat'] as num?)?.toDouble(),
      riderGpsLng: (json['rider_gps_lng'] as num?)?.toDouble(),
      riderGpsUpdatedAt: json['rider_gps_updated_at'] != null
          ? DateTime.parse(json['rider_gps_updated_at'] as String)
          : null,
      riderWalkingPad: json['rider_walking_pad'] as String?,
      isBookingForSomeoneElse: json['is_booking_for_someone_else'] as bool? ??
          json['booking_for_someone_else'] as bool? ?? false,
      waypoints: json['waypoints'] != null
          ? List<Map<String, dynamic>>.from(json['waypoints'])
          : null,
      stripePaymentIntentId: json['stripe_payment_intent_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'driver_id': driverId,
      'passenger_id': passengerId,
      'passenger_name': passengerName,
      'passenger_phone': passengerPhone,
      'passenger_image_url': passengerImageUrl,
      'passenger_rating': passengerRating,
      'type': type.name,
      'status': status.name,
      // Flat database format for locations
      'pickup_latitude': pickupLocation.latitude,
      'pickup_longitude': pickupLocation.longitude,
      'pickup_address': pickupLocation.address,
      'dropoff_latitude': dropoffLocation.latitude,
      'dropoff_longitude': dropoffLocation.longitude,
      'dropoff_address': dropoffLocation.address,
      'distance_km': distanceKm,
      'estimated_minutes': estimatedMinutes,
      'fare': fare,
      'tip': tip,
      'platform_fee': platformFee,
      'driver_earnings': driverEarnings,
      'payment_method': paymentMethod.name,
      'is_paid': isPaid,
      'notes': notes,
      'is_urgent': isUrgent,
      'created_at': createdAt.toIso8601String(),
      'accepted_at': acceptedAt?.toIso8601String(),
      'picked_up_at': arrivedAt?.toIso8601String(),
      'started_at': startedAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'cancelled_at': cancelledAt?.toIso8601String(),
      // Round trip / Carpool fields
      'recurring_days': recurringDays,
      'filled_seats': filledSeats,
      'linked_return_booking_id': linkedReturnBookingId,
      'is_round_trip': isRoundTrip,
      'return_time': returnTime,
      // Rider location tracking
      'rider_gps_lat': riderGpsLat,
      'rider_gps_lng': riderGpsLng,
      'rider_gps_updated_at': riderGpsUpdatedAt?.toIso8601String(),
      'rider_walking_pad': riderWalkingPad,
      'is_booking_for_someone_else': isBookingForSomeoneElse,
      'waypoints': waypoints,
      'stripe_payment_intent_id': stripePaymentIntentId,
    };
  }

  RideModel copyWith({
    String? id,
    String? driverId,
    String? passengerId,
    String? passengerName,
    String? passengerPhone,
    String? passengerImageUrl,
    double? passengerRating,
    int? passengerTotalRides,
    double? passengerAverageTip,
    bool? isGoodTipper,
    bool? hidePassengerName,
    bool? hidePassengerPhoto,
    RideType? type,
    RideStatus? status,
    LocationPoint? pickupLocation,
    LocationPoint? dropoffLocation,
    double? distanceKm,
    int? estimatedMinutes,
    double? fare,
    double? tip,
    double? platformFee,
    double? driverEarnings,
    PaymentMethod? paymentMethod,
    bool? isPaid,
    String? notes,
    bool? isUrgent,
    DateTime? createdAt,
    DateTime? acceptedAt,
    DateTime? arrivedAt,
    DateTime? startedAt,
    DateTime? completedAt,
    DateTime? cancelledAt,
    String? cancellationReason,
    List<int>? recurringDays,
    int? filledSeats,
    String? linkedReturnBookingId,
    bool? isRoundTrip,
    String? returnTime,
    // Rider location tracking
    double? riderGpsLat,
    double? riderGpsLng,
    DateTime? riderGpsUpdatedAt,
    String? riderWalkingPad,
    bool? isBookingForSomeoneElse,
    List<Map<String, dynamic>>? waypoints,
    String? stripePaymentIntentId,
  }) {
    return RideModel(
      id: id ?? this.id,
      driverId: driverId ?? this.driverId,
      passengerId: passengerId ?? this.passengerId,
      passengerName: passengerName ?? this.passengerName,
      passengerPhone: passengerPhone ?? this.passengerPhone,
      passengerImageUrl: passengerImageUrl ?? this.passengerImageUrl,
      passengerRating: passengerRating ?? this.passengerRating,
      passengerTotalRides: passengerTotalRides ?? this.passengerTotalRides,
      passengerAverageTip: passengerAverageTip ?? this.passengerAverageTip,
      isGoodTipper: isGoodTipper ?? this.isGoodTipper,
      hidePassengerName: hidePassengerName ?? this.hidePassengerName,
      hidePassengerPhoto: hidePassengerPhoto ?? this.hidePassengerPhoto,
      type: type ?? this.type,
      status: status ?? this.status,
      pickupLocation: pickupLocation ?? this.pickupLocation,
      dropoffLocation: dropoffLocation ?? this.dropoffLocation,
      distanceKm: distanceKm ?? this.distanceKm,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      fare: fare ?? this.fare,
      tip: tip ?? this.tip,
      platformFee: platformFee ?? this.platformFee,
      driverEarnings: driverEarnings ?? this.driverEarnings,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      isPaid: isPaid ?? this.isPaid,
      notes: notes ?? this.notes,
      isUrgent: isUrgent ?? this.isUrgent,
      createdAt: createdAt ?? this.createdAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      arrivedAt: arrivedAt ?? this.arrivedAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      recurringDays: recurringDays ?? this.recurringDays,
      filledSeats: filledSeats ?? this.filledSeats,
      linkedReturnBookingId: linkedReturnBookingId ?? this.linkedReturnBookingId,
      isRoundTrip: isRoundTrip ?? this.isRoundTrip,
      returnTime: returnTime ?? this.returnTime,
      // Rider location tracking
      riderGpsLat: riderGpsLat ?? this.riderGpsLat,
      riderGpsLng: riderGpsLng ?? this.riderGpsLng,
      riderGpsUpdatedAt: riderGpsUpdatedAt ?? this.riderGpsUpdatedAt,
      riderWalkingPad: riderWalkingPad ?? this.riderWalkingPad,
      isBookingForSomeoneElse: isBookingForSomeoneElse ?? this.isBookingForSomeoneElse,
      waypoints: waypoints ?? this.waypoints,
      stripePaymentIntentId: stripePaymentIntentId ?? this.stripePaymentIntentId,
    );
  }
}




