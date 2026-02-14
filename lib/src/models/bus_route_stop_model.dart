class BusRouteStopModel {
  final String id;
  final String routeId;
  final String stopName;
  final double stopLat;
  final double stopLng;
  final int stopOrder;
  final String? estimatedArrival;

  BusRouteStopModel({
    required this.id,
    required this.routeId,
    required this.stopName,
    required this.stopLat,
    required this.stopLng,
    required this.stopOrder,
    this.estimatedArrival,
  });

  factory BusRouteStopModel.fromJson(Map<String, dynamic> json) {
    return BusRouteStopModel(
      id: json['id'] as String,
      routeId: json['route_id'] as String,
      stopName: json['stop_name'] as String? ?? '',
      stopLat: (json['stop_lat'] as num?)?.toDouble() ?? 0.001,
      stopLng: (json['stop_lng'] as num?)?.toDouble() ?? 0.001,
      stopOrder: json['stop_order'] as int? ?? 0,
      estimatedArrival: json['estimated_arrival'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'route_id': routeId,
      'stop_name': stopName,
      'stop_lat': stopLat,
      'stop_lng': stopLng,
      'stop_order': stopOrder,
      'estimated_arrival': estimatedArrival,
    };
  }

  BusRouteStopModel copyWith({
    String? id,
    String? routeId,
    String? stopName,
    double? stopLat,
    double? stopLng,
    int? stopOrder,
    String? estimatedArrival,
  }) {
    return BusRouteStopModel(
      id: id ?? this.id,
      routeId: routeId ?? this.routeId,
      stopName: stopName ?? this.stopName,
      stopLat: stopLat ?? this.stopLat,
      stopLng: stopLng ?? this.stopLng,
      stopOrder: stopOrder ?? this.stopOrder,
      estimatedArrival: estimatedArrival ?? this.estimatedArrival,
    );
  }
}
