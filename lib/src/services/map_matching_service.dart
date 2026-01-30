import 'dart:convert';
import 'package:http/http.dart' as http;

/// Servicio de Map Matching para snap-to-road preciso
/// Usa Mapbox Map Matching API para ajustar coordenadas GPS a la red de calles
class MapMatchingService {
  static const String _baseUrl = 'https://api.mapbox.com/matching/v5/mapbox';
  final String _accessToken;

  // Cache del último match para evitar llamadas excesivas
  MatchedLocation? _lastMatch;
  DateTime? _lastMatchTime;
  double _lastLat = 0;
  double _lastLng = 0;
  static const int _matchCooldownMs = 1000; // 1 segundo entre matches
  static const double _minDistanceForNewMatch = 5.0; // metros

  MapMatchingService(this._accessToken);

  /// Hace snap de una coordenada GPS a la calle más cercana
  /// Retorna la ubicación ajustada con el nombre de calle preciso
  Future<MatchedLocation?> snapToRoad({
    required double lat,
    required double lng,
    double? bearing,
    double? speed,
    List<List<double>>? recentCoordinates, // Para mejor precisión
  }) async {
    // Cooldown y distancia mínima
    final now = DateTime.now();
    if (_lastMatch != null && _lastMatchTime != null) {
      final elapsed = now.difference(_lastMatchTime!).inMilliseconds;
      final dist = _haversine(lat, lng, _lastLat, _lastLng);

      // Si no ha pasado suficiente tiempo y no nos hemos movido mucho, usar cache
      if (elapsed < _matchCooldownMs && dist < _minDistanceForNewMatch) {
        return _lastMatch;
      }
    }

    try {
      // Construir coordenadas para el match
      // Usar coordenadas recientes si están disponibles para mejor precisión
      String coordinates;
      String? radiuses;
      String? timestamps;

      if (recentCoordinates != null && recentCoordinates.length >= 2) {
        // Usar las últimas coordenadas para mejor match
        final coords = recentCoordinates.take(5).toList();
        coords.add([lng, lat]); // Agregar posición actual
        coordinates = coords.map((c) => '${c[0]},${c[1]}').join(';');
        radiuses = coords.map((_) => '10').join(';'); // 10m de radio
      } else {
        // Solo la coordenada actual
        coordinates = '$lng,$lat';
        radiuses = '25'; // Radio más amplio para single point
      }

      final queryParams = <String, String>{
        'access_token': _accessToken,
        'geometries': 'geojson',
        'overview': 'full',
        'steps': 'true', // Para obtener nombres de calle
        'annotations': 'distance,duration',
      };

      queryParams['radiuses'] = radiuses;
    
      final uri = Uri.parse('$_baseUrl/driving/$coordinates').replace(
        queryParameters: queryParams,
      );

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['matchings'] != null && (data['matchings'] as List).isNotEmpty) {
          final matching = data['matchings'][0];
          final tracepoints = data['tracepoints'] as List?;

          // Obtener la ubicación snapeada del último tracepoint
          MatchedLocation? result;

          if (tracepoints != null && tracepoints.isNotEmpty) {
            // Buscar el último tracepoint válido
            for (int i = tracepoints.length - 1; i >= 0; i--) {
              final tp = tracepoints[i];
              if (tp != null && tp['location'] != null) {
                final loc = tp['location'] as List;

                // Obtener nombre de calle de los legs/steps
                String? streetName;
                final legs = matching['legs'] as List?;
                if (legs != null && legs.isNotEmpty) {
                  // Obtener el step más cercano al punto actual
                  for (final leg in legs.reversed) {
                    final steps = leg['steps'] as List?;
                    if (steps != null && steps.isNotEmpty) {
                      for (final step in steps.reversed) {
                        final name = step['name'] as String?;
                        if (name != null && name.isNotEmpty) {
                          streetName = name;
                          break;
                        }
                      }
                      if (streetName != null) break;
                    }
                  }
                }

                result = MatchedLocation(
                  latitude: (loc[1] as num).toDouble(),
                  longitude: (loc[0] as num).toDouble(),
                  streetName: streetName,
                  confidence: matching['confidence'] as double? ?? 0.0,
                  waypointIndex: tp['waypoint_index'] as int? ?? 0,
                );
                break;
              }
            }
          }

          // Si no hay tracepoints, usar la geometría del matching
          if (result == null) {
            final geometry = matching['geometry'];
            if (geometry != null && geometry['coordinates'] != null) {
              final coords = geometry['coordinates'] as List;
              if (coords.isNotEmpty) {
                final lastCoord = coords.last as List;

                // Obtener nombre de calle
                String? streetName;
                final legs = matching['legs'] as List?;
                if (legs != null && legs.isNotEmpty) {
                  final lastLeg = legs.last;
                  final steps = lastLeg['steps'] as List?;
                  if (steps != null && steps.isNotEmpty) {
                    streetName = steps.last['name'] as String?;
                  }
                }

                result = MatchedLocation(
                  latitude: (lastCoord[1] as num).toDouble(),
                  longitude: (lastCoord[0] as num).toDouble(),
                  streetName: streetName,
                  confidence: matching['confidence'] as double? ?? 0.0,
                  waypointIndex: 0,
                );
              }
            }
          }

          // Guardar en cache
          if (result != null) {
            _lastMatch = result;
            _lastMatchTime = now;
            _lastLat = lat;
            _lastLng = lng;
          }

          return result;
        }
      }
    } catch (_) {
      // Silently handle errors, return null
    }

    return null;
  }

  /// Calcula distancia Haversine entre dos puntos
  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0; // Radio de la tierra en metros
    final dLat = (lat2 - lat1) * 3.141592653589793 / 180;
    final dLon = (lon2 - lon1) * 3.141592653589793 / 180;
    final a =
        0.5 - (1 - dLat.abs() < 0.0001 ? 1 : (1 + dLat * dLat / 2 - 1)) / 2 +
        (1 - dLon.abs() < 0.0001 ? 1 : (1 + dLon * dLon / 2 - 1)) / 2 *
        (1 - (lat1 * 3.141592653589793 / 180).abs() < 0.0001 ? 1 : 1) *
        (1 - (lat2 * 3.141592653589793 / 180).abs() < 0.0001 ? 1 : 1);

    // Simplified haversine for small distances
    final latDiff = lat2 - lat1;
    final lonDiff = lon2 - lon1;
    final avgLat = (lat1 + lat2) / 2;
    final x = lonDiff * 111320 * (avgLat * 3.141592653589793 / 180).abs().clamp(0.5, 1.0);
    final y = latDiff * 110540;
    return (x * x + y * y).abs() < 0.0001 ? 0 : (x * x + y * y).abs();
  }

  /// Limpia el cache
  void clearCache() {
    _lastMatch = null;
    _lastMatchTime = null;
  }
}

/// Ubicación después de map matching
class MatchedLocation {
  final double latitude;
  final double longitude;
  final String? streetName;
  final double confidence; // 0.0 a 1.0
  final int waypointIndex;

  MatchedLocation({
    required this.latitude,
    required this.longitude,
    this.streetName,
    this.confidence = 0.0,
    this.waypointIndex = 0,
  });

  @override
  String toString() => 'MatchedLocation($streetName @ $latitude,$longitude, conf: $confidence)';
}
