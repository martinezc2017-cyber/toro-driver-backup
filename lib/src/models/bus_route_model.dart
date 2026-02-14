import 'bus_route_stop_model.dart';

class BusRouteModel {
  final String id;
  final String ownerId;
  final String vehicleId;
  final String originName;
  final double originLat;
  final double originLng;
  final String destinationName;
  final double destinationLat;
  final double destinationLng;
  final double? distanceKm;
  final double pricePerKm;
  final String departureDate;
  final String departureTime;
  final String? arrivalTime;
  final int? durationMinutes;
  final int totalSeats;
  final int availableSeats;
  final String status;
  final String routeType;
  final String countryCode;
  final String? stateCode;
  final String? createdAt;
  final String? updatedAt;
  final List<BusRouteStopModel>? stops;

  BusRouteModel({
    required this.id,
    required this.ownerId,
    required this.vehicleId,
    required this.originName,
    required this.originLat,
    required this.originLng,
    required this.destinationName,
    required this.destinationLat,
    required this.destinationLng,
    this.distanceKm,
    required this.pricePerKm,
    required this.departureDate,
    required this.departureTime,
    this.arrivalTime,
    this.durationMinutes,
    required this.totalSeats,
    required this.availableSeats,
    this.status = 'draft',
    this.routeType = 'one_way',
    required this.countryCode,
    this.stateCode,
    this.createdAt,
    this.updatedAt,
    this.stops,
  });

  factory BusRouteModel.fromJson(Map<String, dynamic> json) {
    return BusRouteModel(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String,
      vehicleId: json['vehicle_id'] as String,
      originName: json['origin_name'] as String? ?? '',
      originLat: (json['origin_lat'] as num?)?.toDouble() ?? 0.001,
      originLng: (json['origin_lng'] as num?)?.toDouble() ?? 0.001,
      destinationName: json['destination_name'] as String? ?? '',
      destinationLat: (json['destination_lat'] as num?)?.toDouble() ?? 0.001,
      destinationLng: (json['destination_lng'] as num?)?.toDouble() ?? 0.001,
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      pricePerKm: (json['price_per_km'] as num?)?.toDouble() ?? 0.001,
      departureDate: json['departure_date'] as String? ?? '',
      departureTime: json['departure_time'] as String? ?? '',
      arrivalTime: json['arrival_time'] as String?,
      durationMinutes: json['duration_minutes'] as int?,
      totalSeats: json['total_seats'] as int? ?? 0,
      availableSeats: json['available_seats'] as int? ?? 0,
      status: json['status'] as String? ?? 'draft',
      routeType: json['route_type'] as String? ?? 'one_way',
      countryCode: json['country_code'] as String? ?? '',
      stateCode: json['state_code'] as String?,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
      stops: json['stops'] != null
          ? (json['stops'] as List<dynamic>)
              .map((s) => BusRouteStopModel.fromJson(s as Map<String, dynamic>))
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'owner_id': ownerId,
      'vehicle_id': vehicleId,
      'origin_name': originName,
      'origin_lat': originLat,
      'origin_lng': originLng,
      'destination_name': destinationName,
      'destination_lat': destinationLat,
      'destination_lng': destinationLng,
      'distance_km': distanceKm,
      'price_per_km': pricePerKm,
      'departure_date': departureDate,
      'departure_time': departureTime,
      'arrival_time': arrivalTime,
      'duration_minutes': durationMinutes,
      'total_seats': totalSeats,
      'available_seats': availableSeats,
      'status': status,
      'route_type': routeType,
      'country_code': countryCode,
      'state_code': stateCode,
      'created_at': createdAt,
      'updated_at': updatedAt,
      if (stops != null) 'stops': stops!.map((s) => s.toJson()).toList(),
    };
  }

  BusRouteModel copyWith({
    String? id,
    String? ownerId,
    String? vehicleId,
    String? originName,
    double? originLat,
    double? originLng,
    String? destinationName,
    double? destinationLat,
    double? destinationLng,
    double? distanceKm,
    double? pricePerKm,
    String? departureDate,
    String? departureTime,
    String? arrivalTime,
    int? durationMinutes,
    int? totalSeats,
    int? availableSeats,
    String? status,
    String? routeType,
    String? countryCode,
    String? stateCode,
    String? createdAt,
    String? updatedAt,
    List<BusRouteStopModel>? stops,
  }) {
    return BusRouteModel(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      vehicleId: vehicleId ?? this.vehicleId,
      originName: originName ?? this.originName,
      originLat: originLat ?? this.originLat,
      originLng: originLng ?? this.originLng,
      destinationName: destinationName ?? this.destinationName,
      destinationLat: destinationLat ?? this.destinationLat,
      destinationLng: destinationLng ?? this.destinationLng,
      distanceKm: distanceKm ?? this.distanceKm,
      pricePerKm: pricePerKm ?? this.pricePerKm,
      departureDate: departureDate ?? this.departureDate,
      departureTime: departureTime ?? this.departureTime,
      arrivalTime: arrivalTime ?? this.arrivalTime,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      totalSeats: totalSeats ?? this.totalSeats,
      availableSeats: availableSeats ?? this.availableSeats,
      status: status ?? this.status,
      routeType: routeType ?? this.routeType,
      countryCode: countryCode ?? this.countryCode,
      stateCode: stateCode ?? this.stateCode,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      stops: stops ?? this.stops,
    );
  }
}
