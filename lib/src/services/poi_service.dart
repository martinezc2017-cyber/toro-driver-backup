import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

/// Servicio para buscar Points of Interest (POI) usando Mapbox Search API
class PoiService {
  static const String _baseUrl = 'https://api.mapbox.com/search/searchbox/v1';
  final String _accessToken;

  PoiService(this._accessToken);

  /// Busca parkings cerca de una ubicación
  /// [lat], [lng] - Centro de búsqueda
  /// [radiusMeters] - Radio de búsqueda (default 500m)
  Future<List<ParkingPlace>> searchNearbyParkings({
    required double lat,
    required double lng,
    int radiusMeters = 500,
    int limit = 5,
  }) async {
    final uri = Uri.parse('$_baseUrl/category/parking').replace(
      queryParameters: {
        'access_token': _accessToken,
        'proximity': '$lng,$lat',
        'limit': limit.toString(),
        'language': 'es',
      },
    );

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List?;

        if (features != null && features.isNotEmpty) {
          return features
              .map((f) => ParkingPlace.fromJson(f))
              .where((p) => _haversine(lat, lng, p.lat, p.lng) <= radiusMeters)
              .toList();
        }
      }
    } catch (_) {
      // Silently handle API errors
    }

    // Fallback: usar Geocoding API para buscar "parking"
    return _searchParkingFallback(lat, lng, radiusMeters, limit);
  }

  /// Búsqueda alternativa usando Geocoding API
  Future<List<ParkingPlace>> _searchParkingFallback(
    double lat,
    double lng,
    int radiusMeters,
    int limit,
  ) async {
    final uri = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/parking.json',
    ).replace(
      queryParameters: {
        'access_token': _accessToken,
        'proximity': '$lng,$lat',
        'types': 'poi',
        'limit': limit.toString(),
        'language': 'es',
      },
    );

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List?;

        if (features != null && features.isNotEmpty) {
          return features.map((f) {
            final coords = f['center'] as List;
            final props = f['properties'] ?? {};
            return ParkingPlace(
              id: f['id'] ?? '',
              name: f['text'] ?? 'Parking',
              address: f['place_name'] ?? '',
              lat: (coords[1] as num).toDouble(),
              lng: (coords[0] as num).toDouble(),
              category: props['category'] ?? 'parking',
            );
          }).where((p) => _haversine(lat, lng, p.lat, p.lng) <= radiusMeters)
            .toList();
        }
      }
    } catch (_) {}

    return [];
  }

  /// Haversine distance in meters
  double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}

/// Lugar de estacionamiento
class ParkingPlace {
  final String id;
  final String name;
  final String address;
  final double lat;
  final double lng;
  final String? category;

  ParkingPlace({
    required this.id,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    this.category,
  });

  factory ParkingPlace.fromJson(Map<String, dynamic> json) {
    final geometry = json['geometry'] ?? {};
    final coords = geometry['coordinates'] as List? ?? [0, 0];
    final props = json['properties'] ?? {};

    return ParkingPlace(
      id: props['mapbox_id'] ?? json['id'] ?? '',
      name: props['name'] ?? 'Parking',
      address: props['full_address'] ?? props['address'] ?? '',
      lat: (coords[1] as num?)?.toDouble() ?? 0,
      lng: (coords[0] as num?)?.toDouble() ?? 0,
      category: props['poi_category'] ?? 'parking',
    );
  }
}
