import 'dart:convert';
import 'package:http/http.dart' as http;

/// Servicio de geocodificación usando Mapbox Geocoding API
class GeocodingService {
  static const String _baseUrl = 'https://api.mapbox.com/geocoding/v5/mapbox.places';
  final String _accessToken;

  GeocodingService(this._accessToken);

  /// Convierte una dirección a coordenadas
  /// country: 'us' para Estados Unidos, 'mx' para México, 'us,mx' para ambos
  Future<GeocodingResult?> searchAddress(String query, {
    double? proximityLat,
    double? proximityLng,
    String country = 'us',
    int limit = 5,
  }) async {
    if (query.trim().isEmpty) return null;

    final encodedQuery = Uri.encodeComponent(query);

    var url = '$_baseUrl/$encodedQuery.json?access_token=$_accessToken'
        '&country=$country'
        '&limit=$limit'
        '&types=address,place,poi';

    // Si tenemos ubicación de proximidad, priorizar resultados cercanos
    if (proximityLat != null && proximityLng != null) {
      url += '&proximity=$proximityLng,$proximityLat';
    }

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List?;

        if (features != null && features.isNotEmpty) {
          return GeocodingResult.fromFeatureCollection(features);
        }
      }
    } catch (_) {
      // Silently handle geocoding errors
    }

    return null;
  }

  /// Búsqueda de autocompletado mientras el usuario escribe
  Future<List<GeocodingPlace>> autocomplete(String query, {
    double? proximityLat,
    double? proximityLng,
  }) async {
    final result = await searchAddress(
      query,
      proximityLat: proximityLat,
      proximityLng: proximityLng,
      limit: 5,
    );

    return result?.places ?? [];
  }

  /// Reverse geocoding - obtiene información de ubicación desde coordenadas
  /// Retorna la calle/highway donde está el usuario, ciudad y condado
  Future<ReverseGeocodingResult?> reverseGeocode(double lat, double lng) async {
    final url = '$_baseUrl/$lng,$lat.json?access_token=$_accessToken'
        '&types=address';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List?;

        if (features != null && features.isNotEmpty) {
          return ReverseGeocodingResult.fromFeatures(features);
        }
      }
    } catch (_) {
      // Silently handle reverse geocoding errors
    }

    return null;
  }
}

/// Resultado de reverse geocoding
class ReverseGeocodingResult {
  final String? streetName;  // Nombre de calle o highway
  final String? highwayShield; // Shield si es highway (I-10, US-60, AZ-101)
  final String? city;
  final String? county;
  final String? state;

  ReverseGeocodingResult({
    this.streetName,
    this.highwayShield,
    this.city,
    this.county,
    this.state,
  });

  factory ReverseGeocodingResult.fromFeatures(List features) {
    String? streetName;
    String? highwayShield;
    String? city;
    String? county;
    String? state;

    if (features.isEmpty) {
      return ReverseGeocodingResult();
    }

    // Tomar el primer resultado (más cercano)
    final feature = features[0];
    final placeName = feature['place_name'] as String? ?? '';

    // Extraer nombre de calle del place_name
    // Formato típico: "123 W Broadway, Mesa, Arizona 85210, United States"
    if (placeName.isNotEmpty) {
      final parts = placeName.split(',');
      if (parts.isNotEmpty) {
        // Primera parte: "123 W Broadway" - quitar el número
        String firstPart = parts[0].trim();
        // Remover números del inicio (dirección)
        firstPart = firstPart.replaceFirst(RegExp(r'^\d+\s*'), '');
        if (firstPart.isNotEmpty) {
          streetName = firstPart;
        }
      }
    }

    // Detectar si es highway y extraer shield
    if (streetName != null) {
      final upperName = streetName.toUpperCase();

      // Patrones de highway
      final patterns = [
        RegExp(r'\b(I-\d{1,3})\b'),
        RegExp(r'\b(US-?\s?\d{1,3})\b'),
        RegExp(r'\b(AZ-?\s?\d{1,3})\b'),
        RegExp(r'\bAZ\s+(\d{1,3})\s*LOOP\b', caseSensitive: false),
        RegExp(r'\b(LOOP\s*\d{1,3})\b', caseSensitive: false),
        RegExp(r'\b(SR-?\s?\d{1,3})\b'),
        RegExp(r'\b(HWY\s*\d{1,3})\b', caseSensitive: false),
      ];

      for (final pattern in patterns) {
        final match = pattern.firstMatch(upperName);
        if (match != null) {
          highwayShield = match.group(1)?.replaceAll(' ', '-').toUpperCase();
          // Para AZ Loop, formatear mejor
          if (upperName.contains('LOOP')) {
            final loopMatch = RegExp(r'(\d{1,3})').firstMatch(upperName);
            if (loopMatch != null) {
              highwayShield = 'AZ-${loopMatch.group(1)} Loop';
            }
          }
          break;
        }
      }
    }

    // Buscar ciudad, condado, estado en el context
    final context = feature['context'] as List?;
    if (context != null) {
      for (final ctx in context) {
        final ctxId = ctx['id'] as String? ?? '';
        final ctxText = ctx['text'] as String?;

        if (ctxId.startsWith('place') && city == null) {
          city = ctxText;
        } else if (ctxId.startsWith('district') && county == null) {
          county = ctxText;
        } else if (ctxId.startsWith('region') && state == null) {
          state = ctxText;
        }
      }
    }

    return ReverseGeocodingResult(
      streetName: streetName,
      highwayShield: highwayShield,
      city: city,
      county: county,
      state: state,
    );
  }

  /// Es un highway?
  bool get isHighway => highwayShield != null && highwayShield!.isNotEmpty;

  /// Retorna "Ciudad, Condado" o solo uno si el otro no existe
  String get displayLocation {
    final parts = <String>[];
    if (city != null) parts.add(city!);
    if (county != null && county != city) parts.add(county!);
    return parts.join(', ');
  }
}

/// Resultado de geocodificación
class GeocodingResult {
  final List<GeocodingPlace> places;

  GeocodingResult({required this.places});

  factory GeocodingResult.fromFeatureCollection(List features) {
    final places = features.map((f) => GeocodingPlace.fromJson(f)).toList();
    return GeocodingResult(places: places);
  }

  GeocodingPlace? get firstPlace => places.isNotEmpty ? places.first : null;
}

/// Lugar encontrado
class GeocodingPlace {
  final String id;
  final String name;
  final String fullAddress;
  final double lat;
  final double lng;
  final String? type;

  GeocodingPlace({
    required this.id,
    required this.name,
    required this.fullAddress,
    required this.lat,
    required this.lng,
    this.type,
  });

  factory GeocodingPlace.fromJson(Map<String, dynamic> json) {
    final center = json['center'] as List;
    final placeName = json['place_name'] as String? ?? '';
    final text = json['text'] as String? ?? '';
    final placeType = (json['place_type'] as List?)?.firstOrNull as String?;

    return GeocodingPlace(
      id: json['id'] as String? ?? '',
      name: text,
      fullAddress: placeName,
      lng: (center[0] as num).toDouble(),
      lat: (center[1] as num).toDouble(),
      type: placeType,
    );
  }

  @override
  String toString() => '$name ($lat, $lng)';
}
