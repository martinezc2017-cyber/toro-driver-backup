import 'dart:convert';
import 'package:http/http.dart' as http;

/// Servicio para obtener rutas y direcciones de Mapbox Directions API
class DirectionsService {
  static const String _baseUrl = 'https://api.mapbox.com/directions/v5/mapbox';
  final String _accessToken;

  DirectionsService(this._accessToken);

  /// Obtiene una ruta con instrucciones turn-by-turn
  /// [profile] puede ser: driving-traffic, driving, walking, cycling
  /// [bearing] es la dirección actual del vehículo (0-360, donde 0=norte, 90=este, 180=sur, 270=oeste)
  /// Si se proporciona, la ruta evitará requerir giros en U inmediatos
  /// [alternatives] si es true, devuelve hasta 3 rutas alternativas
  /// [approaches] controla por qué lado llegar: 'unrestricted', 'curb' (acera derecha)
  /// [exclude] tipos de vías a excluir: 'toll', 'motorway', 'ferry'
  Future<DirectionsRoute?> getRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    double? bearing, // Dirección actual del vehículo
    String profile = 'driving-traffic',
    String language = 'es',
    bool alternatives = false,
    bool steps = true,
    bool bannerInstructions = true,
    bool voiceInstructions = true,
    String geometries = 'geojson',
    String overview = 'full',
    String? approaches, // 'unrestricted;curb' - por waypoint
    String? exclude, // 'toll,motorway,ferry'
    bool continueStraight = true, // Evita U-turns innecesarios
  }) async {
    final coordinates = '$originLng,$originLat;$destLng,$destLat';

    // Construir parámetros de consulta
    final queryParams = {
      'access_token': _accessToken,
      'language': language,
      'alternatives': alternatives.toString(),
      'steps': steps.toString(),
      'banner_instructions': bannerInstructions.toString(),
      'voice_instructions': voiceInstructions.toString(),
      'geometries': geometries,
      'overview': overview,
      // Annotations incluyendo closure (incidentes) y toll info
      'annotations': 'maxspeed,congestion,distance,duration,closure',
      'continue_straight': continueStraight.toString(),
    };

    // Si tenemos bearing, agregarlo para evitar rutas con U-turn
    if (bearing != null && bearing >= 0 && bearing <= 360) {
      queryParams['bearings'] = '${bearing.round()},90;';
    }

    // Approach: controla por qué lado llegar al destino
    // 'curb' = lado de la acera (derecha en países con conducción derecha)
    // 'unrestricted' = cualquier lado
    if (approaches != null) {
      queryParams['approaches'] = approaches;
    }

    // Excluir tipos de vías
    if (exclude != null) {
      queryParams['exclude'] = exclude;
    }

    final uri = Uri.parse('$_baseUrl/$profile/$coordinates').replace(
      queryParameters: queryParams,
    );

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          return DirectionsRoute.fromJson(data['routes'][0]);
        }
      }
    } catch (_) {
      // Silently handle API errors
    }

    return null;
  }

  /// Obtiene ruta optimizada para aeropuertos (llegadas/salidas)
  /// Usa 'curb' approach para llegar por el lado correcto de la terminal
  Future<DirectionsRoute?> getAirportRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    double? bearing,
    bool isPickup = true, // true = llegadas, false = salidas
  }) async {
    return getRoute(
      originLat: originLat,
      originLng: originLng,
      destLat: destLat,
      destLng: destLng,
      bearing: bearing,
      // 'curb' hace que llegue por el lado de la acera (terminal)
      // en lugar de dar la vuelta
      approaches: 'unrestricted;curb',
      continueStraight: true,
      alternatives: true,
    );
  }

  /// Obtiene múltiples rutas alternativas
  /// Devuelve una lista de rutas ordenadas por duración (más rápida primero)
  Future<List<DirectionsRoute>> getRouteAlternatives({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    double? bearing,
    String profile = 'driving-traffic',
    String language = 'es',
    String? approaches,
    String? exclude,
    bool continueStraight = true,
  }) async {
    final coordinates = '$originLng,$originLat;$destLng,$destLat';

    final queryParams = {
      'access_token': _accessToken,
      'language': language,
      'alternatives': 'true', // Pedir alternativas
      'steps': 'true',
      'banner_instructions': 'true',
      'voice_instructions': 'true',
      'geometries': 'geojson',
      'overview': 'full',
      'annotations': 'maxspeed,congestion,distance,duration,closure',
      'continue_straight': continueStraight.toString(),
    };

    if (bearing != null && bearing >= 0 && bearing <= 360) {
      queryParams['bearings'] = '${bearing.round()},90;';
    }

    if (approaches != null) {
      queryParams['approaches'] = approaches;
    }

    if (exclude != null) {
      queryParams['exclude'] = exclude;
    }

    final uri = Uri.parse('$_baseUrl/$profile/$coordinates').replace(
      queryParameters: queryParams,
    );

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final routes = (data['routes'] as List)
              .map((r) => DirectionsRoute.fromJson(r))
              .toList();

          // Ordenar por duración (más rápida primero)
          routes.sort((a, b) => a.duration.compareTo(b.duration));
          return routes;
        }
      }
    } catch (_) {
      // Silently handle API errors
    }

    return [];
  }

  /// Obtiene rutas con tráfico histórico (para predicción de ETA)
  /// [departAt] usa fecha ISO 8601 para calcular tráfico en ese momento
  /// Ejemplo: departAt = DateTime.now().add(Duration(hours: 1)).toIso8601String()
  Future<List<DirectionsRoute>> getRoutesWithHistoricalTraffic({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    DateTime? departAt,
    double? bearing,
    String profile = 'driving-traffic',
    String language = 'es',
  }) async {
    final coordinates = '$originLng,$originLat;$destLng,$destLat';

    final queryParams = {
      'access_token': _accessToken,
      'language': language,
      'alternatives': 'true',
      'steps': 'true',
      'banner_instructions': 'true',
      'voice_instructions': 'true',
      'geometries': 'geojson',
      'overview': 'full',
      'annotations': 'maxspeed,congestion,distance,duration,closure',
    };

    // Usar depart_at para tráfico histórico/predictivo
    if (departAt != null) {
      queryParams['depart_at'] = departAt.toUtc().toIso8601String();
    }

    if (bearing != null && bearing >= 0 && bearing <= 360) {
      queryParams['bearings'] = '${bearing.round()},90;';
    }

    final uri = Uri.parse('$_baseUrl/$profile/$coordinates').replace(
      queryParameters: queryParams,
    );

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          return (data['routes'] as List)
              .map((r) => DirectionsRoute.fromJson(r))
              .toList();
        }
      }
    } catch (_) {}

    return [];
  }

  /// Actualiza la ruta actual y obtiene alternativas si hay mejor opción
  /// Retorna la mejor ruta (puede ser la actual o una alternativa más rápida)
  Future<RouteUpdateResult?> checkForBetterRoute({
    required double currentLat,
    required double currentLng,
    required double destLat,
    required double destLng,
    required double currentRouteDuration,
    double? bearing,
    String profile = 'driving-traffic',
    String language = 'es',
  }) async {
    final routes = await getRouteAlternatives(
      originLat: currentLat,
      originLng: currentLng,
      destLat: destLat,
      destLng: destLng,
      bearing: bearing,
      profile: profile,
      language: language,
    );

    if (routes.isEmpty) return null;

    final bestRoute = routes.first; // Ya ordenadas por duración

    // Calcular ahorro de tiempo
    final timeSaved = currentRouteDuration - bestRoute.duration;

    // Solo sugerir si ahorra más de 2 minutos
    if (timeSaved > 120) {
      return RouteUpdateResult(
        newRoute: bestRoute,
        alternatives: routes.skip(1).toList(),
        timeSavedSeconds: timeSaved,
        hasBetterRoute: true,
      );
    }

    return RouteUpdateResult(
      newRoute: bestRoute,
      alternatives: routes.skip(1).toList(),
      timeSavedSeconds: 0,
      hasBetterRoute: false,
    );
  }

  /// Obtiene una ruta con múltiples waypoints
  Future<DirectionsRoute?> getRouteWithWaypoints({
    required List<LatLng> waypoints,
    String profile = 'driving-traffic',
    String language = 'es',
  }) async {
    if (waypoints.length < 2) return null;

    final coordinates = waypoints
        .map((w) => '${w.lng},${w.lat}')
        .join(';');

    final uri = Uri.parse('$_baseUrl/$profile/$coordinates').replace(
      queryParameters: {
        'access_token': _accessToken,
        'language': language,
        'steps': 'true',
        'banner_instructions': 'true',
        'voice_instructions': 'true',
        'geometries': 'geojson',
        'overview': 'full',
        'annotations': 'maxspeed,congestion,distance,duration',
      },
    );

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          return DirectionsRoute.fromJson(data['routes'][0]);
        }
      }
    } catch (_) {
      // Silently handle API errors
    }

    return null;
  }
}

/// Coordenada simple
class LatLng {
  final double lat;
  final double lng;

  const LatLng(this.lat, this.lng);
}

/// Ruta completa con instrucciones
class DirectionsRoute {
  final double distance; // metros
  final double duration; // segundos
  final double? durationTypical; // duración típica (tráfico histórico)
  final String geometry; // GeoJSON o polyline
  final List<List<double>> coordinates; // [[lng, lat], ...]
  final List<RouteLeg> legs;
  final String? routeId; // ID unico de la ruta
  final bool hasTolls; // ¿Tiene peajes?
  final double? tollCost; // Costo estimado de peajes (si disponible)
  final List<RouteIncident> incidents; // Incidentes en la ruta

  DirectionsRoute({
    required this.distance,
    required this.duration,
    this.durationTypical,
    required this.geometry,
    required this.coordinates,
    required this.legs,
    this.routeId,
    this.hasTolls = false,
    this.tollCost,
    this.incidents = const [],
  });

  factory DirectionsRoute.fromJson(Map<String, dynamic> json) {
    final geometryData = json['geometry'];
    List<List<double>> coords = [];

    if (geometryData is Map && geometryData['coordinates'] != null) {
      coords = (geometryData['coordinates'] as List)
          .map((c) => [
                (c[0] as num).toDouble(),
                (c[1] as num).toDouble(),
              ])
          .toList();
    }

    // Detectar peajes en la ruta (via road classes o toll_costs)
    bool hasTolls = false;
    double? tollCost;

    // Verificar si hay toll_costs en la respuesta
    if (json['toll_costs'] != null) {
      final tollCosts = json['toll_costs'] as List?;
      if (tollCosts != null && tollCosts.isNotEmpty) {
        hasTolls = true;
        // Sumar todos los costos de peaje
        tollCost = tollCosts.fold<double>(0, (sum, toll) {
          final amount = toll['payment_methods']?['cash']?['amount'];
          return sum + ((amount as num?)?.toDouble() ?? 0);
        });
      }
    }

    // Extraer incidentes de las anotaciones de closure
    List<RouteIncident> incidents = [];
    final legs = json['legs'] as List?;
    if (legs != null) {
      for (final leg in legs) {
        final annotation = leg['annotation'];
        if (annotation != null && annotation['closure'] != null) {
          final closures = annotation['closure'] as List?;
          if (closures != null) {
            for (int i = 0; i < closures.length; i++) {
              if (closures[i] == true) {
                incidents.add(RouteIncident(
                  type: 'closure',
                  description: 'Cierre de carretera',
                  segmentIndex: i,
                ));
              }
            }
          }
        }
      }
    }

    return DirectionsRoute(
      distance: (json['distance'] as num).toDouble(),
      duration: (json['duration'] as num).toDouble(),
      durationTypical: (json['duration_typical'] as num?)?.toDouble(),
      geometry: json['geometry'] is String
          ? json['geometry']
          : jsonEncode(json['geometry']),
      coordinates: coords,
      legs: (json['legs'] as List?)
              ?.map((l) => RouteLeg.fromJson(l))
              .toList() ??
          [],
      routeId: json['uuid'] as String?,
      hasTolls: hasTolls,
      tollCost: tollCost,
      incidents: incidents,
    );
  }

  /// Diferencia entre duración actual y típica (tráfico inusual)
  Duration? get trafficDelay {
    if (durationTypical == null) return null;
    final delay = duration - durationTypical!;
    if (delay <= 0) return null;
    return Duration(seconds: delay.round());
  }

  /// Texto del retraso por tráfico
  String? get trafficDelayText {
    final delay = trafficDelay;
    if (delay == null) return null;
    final mins = delay.inMinutes;
    if (mins < 1) return null;
    if (mins < 60) return '+$mins min por tráfico';
    final hours = mins ~/ 60;
    final remainMins = mins % 60;
    return '+${hours}h ${remainMins}min por tráfico';
  }

  /// Duración formateada (ej: "15 min", "1h 30min")
  String get formattedDuration {
    final mins = (duration / 60).round();
    if (mins < 60) {
      return '$mins min';
    } else {
      final hours = mins ~/ 60;
      final remainMins = mins % 60;
      return remainMins > 0 ? '${hours}h ${remainMins}min' : '${hours}h';
    }
  }

  /// Distancia formateada (ej: "500 m", "2.5 km")
  String get formattedDistance {
    if (distance < 1000) {
      return '${distance.round()} m';
    } else {
      return '${(distance / 1000).toStringAsFixed(1)} km';
    }
  }

  /// ETA estimada
  DateTime get estimatedArrival {
    return DateTime.now().add(Duration(seconds: duration.round()));
  }

  /// ETA formateada (ej: "10:45 AM")
  String get formattedETA {
    final eta = estimatedArrival;
    final hour = eta.hour;
    final minute = eta.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$hour12:$minute $period';
  }
}

/// Segmento de ruta (entre waypoints)
class RouteLeg {
  final double distance;
  final double duration;
  final String? summary;
  final List<RouteStep> steps;
  final RouteAnnotations? annotations;

  RouteLeg({
    required this.distance,
    required this.duration,
    this.summary,
    required this.steps,
    this.annotations,
  });

  factory RouteLeg.fromJson(Map<String, dynamic> json) {
    return RouteLeg(
      distance: (json['distance'] as num).toDouble(),
      duration: (json['duration'] as num).toDouble(),
      summary: json['summary'] as String?,
      steps: (json['steps'] as List?)
              ?.map((s) => RouteStep.fromJson(s))
              .toList() ??
          [],
      annotations: json['annotation'] != null
          ? RouteAnnotations.fromJson(json['annotation'])
          : null,
    );
  }
}

/// Annotations de la ruta (velocidad maxima, congestion, etc.)
class RouteAnnotations {
  final List<double>? distance; // Distancia por segmento
  final List<double>? duration; // Duracion por segmento
  final List<SpeedLimit>? maxspeed; // Limite de velocidad por segmento
  final List<String>? congestion; // Nivel de congestion: low, moderate, heavy, severe

  RouteAnnotations({
    this.distance,
    this.duration,
    this.maxspeed,
    this.congestion,
  });

  factory RouteAnnotations.fromJson(Map<String, dynamic> json) {
    return RouteAnnotations(
      distance: (json['distance'] as List?)
          ?.map((d) => (d as num).toDouble())
          .toList(),
      duration: (json['duration'] as List?)
          ?.map((d) => (d as num).toDouble())
          .toList(),
      maxspeed: (json['maxspeed'] as List?)
          ?.map((s) => SpeedLimit.fromJson(s))
          .toList(),
      congestion: (json['congestion'] as List?)
          ?.map((c) => c.toString())
          .toList(),
    );
  }
}

/// Limite de velocidad
class SpeedLimit {
  final double? speed; // En km/h o mph segun unit
  final String? unit; // "km/h" o "mph"
  final bool unknown; // Si el limite es desconocido

  SpeedLimit({
    this.speed,
    this.unit,
    this.unknown = false,
  });

  factory SpeedLimit.fromJson(Map<String, dynamic> json) {
    if (json['unknown'] == true) {
      return SpeedLimit(unknown: true);
    }
    return SpeedLimit(
      speed: (json['speed'] as num?)?.toDouble(),
      unit: json['unit'] as String?,
      unknown: false,
    );
  }

  /// Devuelve la velocidad en km/h
  double? get speedKmh {
    if (unknown || speed == null) return null;

    // Si la unidad es mph, convertir a km/h
    if (unit == 'mph') {
      return speed! * 1.60934;
    }

    // Si no hay unidad pero el valor parece ser mph (valores típicos USA: 25, 35, 40, 45, 55, 65, 70, 75)
    // Asumimos mph si es un valor común de USA y lo convertimos
    if (unit == null && speed! <= 85) {
      // Valores típicos de mph en USA
      const mphValues = [15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85];
      if (mphValues.contains(speed!.round())) {
        return speed! * 1.60934;
      }
    }

    return speed;
  }

  /// Devuelve la velocidad en mph
  double? get speedMph {
    if (unknown || speed == null) return null;

    if (unit == 'mph') {
      return speed;
    }

    // Convertir de km/h a mph
    return speed! / 1.60934;
  }
}

/// Paso individual de navegación
class RouteStep {
  final double distance;
  final double duration;
  final String? name; // nombre de la calle
  final String? ref;  // número de ruta (ej: "AZ 202", "I-10")
  final String? instruction; // instrucción de texto
  final StepManeuver maneuver;
  final List<List<double>> coordinates;
  final List<BannerInstruction> bannerInstructions; // TODAS las instrucciones
  final List<VoiceInstruction> voiceInstructions;   // TODAS las instrucciones

  RouteStep({
    required this.distance,
    required this.duration,
    this.name,
    this.ref,
    this.instruction,
    required this.maneuver,
    required this.coordinates,
    this.bannerInstructions = const [],
    this.voiceInstructions = const [],
  });

  /// Nombre para mostrar: prefiere "ref • name" si ambos existen
  String get displayName {
    if (ref != null && ref!.isNotEmpty && name != null && name!.isNotEmpty) {
      // Si el ref ya está en el name, solo mostrar name
      if (name!.contains(ref!)) return name!;
      return '$ref • $name';
    }
    return ref ?? name ?? '';
  }

  /// Obtiene la banner instruction apropiada según la distancia actual al maneuver
  /// distanceAlongGeometry = distancia desde donde se debe EMPEZAR a mostrar el banner
  /// Ejemplo: Si hay banners a [2000m, 400m, 100m] y estoy a 300m,
  /// debo mostrar el de 400m (ya pasé ese umbral pero no el de 100m)
  BannerInstruction? getBannerForDistance(double distanceToManeuver) {
    if (bannerInstructions.isEmpty) return null;

    // Filtrar banners cuyo umbral ya pasamos (distanceAlongGeometry >= distancia actual)
    final activeBanners = bannerInstructions
        .where((bi) => bi.distanceAlongGeometry >= distanceToManeuver)
        .toList();

    if (activeBanners.isEmpty) {
      // Estamos más cerca que todos los umbrales, usar el más cercano
      return bannerInstructions.reduce((a, b) =>
          a.distanceAlongGeometry < b.distanceAlongGeometry ? a : b);
    }

    // De los banners activos, usar el que tiene el umbral más pequeño
    // (el más reciente que se activó)
    return activeBanners.reduce((a, b) =>
        a.distanceAlongGeometry < b.distanceAlongGeometry ? a : b);
  }

  /// Obtiene la voice instruction apropiada según la distancia
  VoiceInstruction? getVoiceForDistance(double distanceToManeuver) {
    if (voiceInstructions.isEmpty) return null;

    final sorted = List<VoiceInstruction>.from(voiceInstructions)
      ..sort((a, b) => b.distanceAlongGeometry.compareTo(a.distanceAlongGeometry));

    for (final vi in sorted) {
      if (distanceToManeuver <= vi.distanceAlongGeometry) {
        return vi;
      }
    }

    return sorted.first;
  }

  /// Getter de compatibilidad - retorna la primera instrucción
  BannerInstruction? get bannerInstruction =>
      bannerInstructions.isNotEmpty ? bannerInstructions.first : null;

  factory RouteStep.fromJson(Map<String, dynamic> json) {
    final geometryData = json['geometry'];
    List<List<double>> coords = [];

    if (geometryData is Map && geometryData['coordinates'] != null) {
      coords = (geometryData['coordinates'] as List)
          .map((c) => [
                (c[0] as num).toDouble(),
                (c[1] as num).toDouble(),
              ])
          .toList();
    }

    final bannerInstructionsList = json['bannerInstructions'] as List?;
    final voiceInstructionsList = json['voiceInstructions'] as List?;

    return RouteStep(
      distance: (json['distance'] as num).toDouble(),
      duration: (json['duration'] as num).toDouble(),
      name: json['name'] as String?,
      ref: json['ref'] as String?,  // Número de ruta (AZ 202, I-10, etc.)
      instruction: json['maneuver']?['instruction'] as String?,
      maneuver: StepManeuver.fromJson(json['maneuver'] ?? {}),
      coordinates: coords,
      bannerInstructions: bannerInstructionsList != null
          ? bannerInstructionsList.map((b) => BannerInstruction.fromJson(b)).toList()
          : [],
      voiceInstructions: voiceInstructionsList != null
          ? voiceInstructionsList.map((v) => VoiceInstruction.fromJson(v)).toList()
          : [],
    );
  }

  /// Distancia formateada
  String get formattedDistance {
    if (distance < 1000) {
      return '${distance.round()} m';
    } else {
      return '${(distance / 1000).toStringAsFixed(1)} km';
    }
  }
}

/// Maniobra (giro, salida, etc.)
class StepManeuver {
  final String type; // turn, depart, arrive, merge, fork, roundabout, etc.
  final String? modifier; // left, right, straight, slight left, etc.
  final double? bearingBefore;
  final double? bearingAfter;
  final List<double>? location; // [lng, lat]
  final String? instruction;
  final int? exit; // para rotondas

  StepManeuver({
    required this.type,
    this.modifier,
    this.bearingBefore,
    this.bearingAfter,
    this.location,
    this.instruction,
    this.exit,
  });

  factory StepManeuver.fromJson(Map<String, dynamic> json) {
    return StepManeuver(
      type: json['type'] as String? ?? 'unknown',
      modifier: json['modifier'] as String?,
      bearingBefore: (json['bearing_before'] as num?)?.toDouble(),
      bearingAfter: (json['bearing_after'] as num?)?.toDouble(),
      location: (json['location'] as List?)
          ?.map((e) => (e as num).toDouble())
          .toList(),
      instruction: json['instruction'] as String?,
      exit: json['exit'] as int?,
    );
  }

  /// Obtiene el ícono correspondiente a la maniobra
  String get iconName {
    switch (type) {
      case 'depart':
        return 'depart';
      case 'arrive':
        return 'arrive';
      case 'turn':
        return _getTurnIcon();
      case 'merge':
        return 'merge_${modifier ?? 'straight'}';
      case 'fork':
        return 'fork_${modifier ?? 'straight'}';
      case 'roundabout':
      case 'rotary':
        return 'roundabout';
      case 'roundabout turn':
        return 'roundabout_${modifier ?? 'straight'}';
      case 'exit roundabout':
        return 'exit_roundabout';
      case 'ramp':
        return 'ramp_${modifier ?? 'straight'}';
      case 'on ramp':
        return 'on_ramp_${modifier ?? 'straight'}';
      case 'off ramp':
        return 'off_ramp_${modifier ?? 'straight'}';
      case 'end of road':
        return 'end_road_${modifier ?? 'straight'}';
      case 'continue':
        return modifier == 'straight' ? 'straight' : _getTurnIcon();
      case 'new name':
        return 'straight';
      default:
        return 'straight';
    }
  }

  String _getTurnIcon() {
    switch (modifier) {
      case 'left':
        return 'turn_left';
      case 'right':
        return 'turn_right';
      case 'slight left':
        return 'slight_left';
      case 'slight right':
        return 'slight_right';
      case 'sharp left':
        return 'sharp_left';
      case 'sharp right':
        return 'sharp_right';
      case 'uturn':
        return 'uturn';
      case 'straight':
      default:
        return 'straight';
    }
  }
}

/// Instrucción de banner (visual)
class BannerInstruction {
  final double distanceAlongGeometry;
  final BannerContent primary;
  final BannerContent? secondary;
  final BannerContent? sub; // Sub-maniobra (lane guidance)

  BannerInstruction({
    required this.distanceAlongGeometry,
    required this.primary,
    this.secondary,
    this.sub,
  });

  factory BannerInstruction.fromJson(Map<String, dynamic> json) {
    return BannerInstruction(
      distanceAlongGeometry: (json['distanceAlongGeometry'] as num).toDouble(),
      primary: BannerContent.fromJson(json['primary'] ?? {}),
      secondary: json['secondary'] != null
          ? BannerContent.fromJson(json['secondary'])
          : null,
      sub: json['sub'] != null
          ? BannerContent.fromJson(json['sub'])
          : null,
    );
  }

  /// Obtiene los lanes del banner (primary, sub, o secondary)
  List<LaneInfo>? get lanes {
    return sub?.lanes ?? primary.lanes ?? secondary?.lanes;
  }

  /// Obtiene los shields de carretera
  List<BannerComponent> get shields {
    final fromComponents = primary.components.where((c) => c.isShield).toList();
    if (fromComponents.isNotEmpty) return fromComponents;

    // Fallback: extraer del texto si contiene patrones de carretera
    final extractedShields = <BannerComponent>[];
    final text = primary.text;

    // Buscar patrones como "AZ 101", "I-10", "US 60", "Loop 202"
    final patterns = [
      RegExp(r'\b(I-\d{1,3})\b'),
      RegExp(r'\b(US-?\s?\d{1,3})\b'),
      RegExp(r'\b(AZ-?\s?\d{1,3})\b'),
      RegExp(r'\b(Loop\s?\d{1,3})\b', caseSensitive: false),
      RegExp(r'\b(SR-?\s?\d{1,3})\b'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        extractedShields.add(BannerComponent(
          text: match.group(1)!.replaceAll(' ', '-'),
          type: 'icon',
        ));
      }
    }

    return extractedShields;
  }
}

/// Contenido de banner
class BannerContent {
  final String text;
  final String? type;
  final String? modifier;
  final List<BannerComponent> components;
  final List<LaneInfo>? lanes;

  BannerContent({
    required this.text,
    this.type,
    this.modifier,
    this.components = const [],
    this.lanes,
  });

  factory BannerContent.fromJson(Map<String, dynamic> json) {
    return BannerContent(
      text: json['text'] as String? ?? '',
      type: json['type'] as String?,
      modifier: json['modifier'] as String?,
      components: (json['components'] as List?)
              ?.map((c) => BannerComponent.fromJson(c))
              .toList() ??
          [],
      lanes: (json['lanes'] as List?)
              ?.map((l) => LaneInfo.fromJson(l))
              .toList(),
    );
  }
}

/// Componente de banner (texto, iconos de carretera, etc.)
class BannerComponent {
  final String text;
  final String type; // text, icon, delimiter, exit, exit-number, lane
  final String? imageBaseUrl; // Para shields de carretera
  final String? imageUrl;
  final List<String>? directions; // Para lanes
  final bool? active; // Para lanes

  BannerComponent({
    required this.text,
    required this.type,
    this.imageBaseUrl,
    this.imageUrl,
    this.directions,
    this.active,
  });

  factory BannerComponent.fromJson(Map<String, dynamic> json) {
    return BannerComponent(
      text: json['text'] as String? ?? '',
      type: json['type'] as String? ?? 'text',
      imageBaseUrl: json['imageBaseURL'] as String?,
      imageUrl: json['imageURL'] as String?,
      directions: (json['directions'] as List?)?.map((d) => d.toString()).toList(),
      active: json['active'] as bool?,
    );
  }

  /// Es un shield de carretera (I-10, AZ-202, US-60, etc.)
  bool get isShield {
    // Shield con imagen
    if (type == 'icon' && imageBaseUrl != null) return true;

    // Detectar por patrón de texto (I-10, US-60, AZ-101, Loop 202, etc.)
    final t = text.toUpperCase();
    if (t.startsWith('I-') || t.startsWith('I ')) return true;
    if (t.startsWith('US-') || t.startsWith('US ')) return true;
    if (t.startsWith('AZ-') || t.startsWith('AZ ')) return true;
    if (t.startsWith('CA-') || t.startsWith('TX-') || t.startsWith('NV-')) return true;
    if (t.contains('LOOP') && RegExp(r'\d').hasMatch(t)) return true;
    if (t.startsWith('SR-') || t.startsWith('SR ')) return true;
    if (t.startsWith('HWY') || t.startsWith('HIGHWAY')) return true;

    // Número de ruta simple (101, 202, etc.) si el tipo es icon
    if (type == 'icon' && RegExp(r'^\d{1,3}$').hasMatch(text)) return true;

    return false;
  }
}

/// Informacion de carril
class LaneInfo {
  final List<String> indications; // straight, left, right, slight left, etc.
  final bool valid; // Si este carril es valido para la maniobra
  final bool? active; // Si este carril es el recomendado

  LaneInfo({
    required this.indications,
    required this.valid,
    this.active,
  });

  factory LaneInfo.fromJson(Map<String, dynamic> json) {
    return LaneInfo(
      indications: (json['indications'] as List?)
              ?.map((i) => i.toString())
              .toList() ??
          [],
      valid: json['valid'] as bool? ?? false,
      active: json['active'] as bool?,
    );
  }
}

/// Instrucción de voz
class VoiceInstruction {
  final double distanceAlongGeometry;
  final String announcement;
  final String? ssmlAnnouncement;

  VoiceInstruction({
    required this.distanceAlongGeometry,
    required this.announcement,
    this.ssmlAnnouncement,
  });

  factory VoiceInstruction.fromJson(Map<String, dynamic> json) {
    return VoiceInstruction(
      distanceAlongGeometry: (json['distanceAlongGeometry'] as num).toDouble(),
      announcement: json['announcement'] as String? ?? '',
      ssmlAnnouncement: json['ssmlAnnouncement'] as String?,
    );
  }
}

/// Incidente en la ruta (cierre, accidente, etc.)
class RouteIncident {
  final String type; // closure, accident, construction, etc.
  final String description;
  final int? segmentIndex;
  final List<double>? location; // [lng, lat]
  final DateTime? startTime;
  final DateTime? endTime;
  final String? severity; // minor, moderate, major, critical

  RouteIncident({
    required this.type,
    required this.description,
    this.segmentIndex,
    this.location,
    this.startTime,
    this.endTime,
    this.severity,
  });

  /// Icono del incidente
  String get iconName {
    switch (type) {
      case 'closure':
        return 'road_closed';
      case 'accident':
        return 'car_crash';
      case 'construction':
        return 'construction';
      case 'congestion':
        return 'traffic';
      case 'weather':
        return 'weather_severe';
      default:
        return 'warning';
    }
  }

  /// Color del incidente según severidad
  int get color {
    switch (severity) {
      case 'critical':
        return 0xFFD32F2F; // Rojo oscuro
      case 'major':
        return 0xFFF44336; // Rojo
      case 'moderate':
        return 0xFFFF9800; // Naranja
      case 'minor':
      default:
        return 0xFFFFC107; // Amarillo
    }
  }
}

/// Información de tráfico para una ruta
class TrafficInfo {
  final double currentDuration; // Duración con tráfico actual
  final double? typicalDuration; // Duración típica (histórica)
  final double? freeFlowDuration; // Duración sin tráfico
  final String congestionLevel; // low, moderate, heavy, severe
  final List<CongestionSegment> segments;

  TrafficInfo({
    required this.currentDuration,
    this.typicalDuration,
    this.freeFlowDuration,
    required this.congestionLevel,
    this.segments = const [],
  });

  /// Porcentaje de retraso por tráfico
  double get delayPercentage {
    if (typicalDuration == null || typicalDuration! <= 0) return 0;
    return ((currentDuration - typicalDuration!) / typicalDuration! * 100).clamp(0, 200);
  }
}

/// Segmento con congestión
class CongestionSegment {
  final int startIndex;
  final int endIndex;
  final String level; // low, moderate, heavy, severe

  CongestionSegment({
    required this.startIndex,
    required this.endIndex,
    required this.level,
  });
}

/// Resultado de actualización de ruta
class RouteUpdateResult {
  final DirectionsRoute newRoute;
  final List<DirectionsRoute> alternatives;
  final double timeSavedSeconds;
  final bool hasBetterRoute;

  RouteUpdateResult({
    required this.newRoute,
    required this.alternatives,
    required this.timeSavedSeconds,
    required this.hasBetterRoute,
  });

  /// Tiempo ahorrado formateado
  String get timeSavedText {
    if (timeSavedSeconds <= 0) return '';
    final mins = (timeSavedSeconds / 60).round();
    if (mins < 1) return '';
    if (mins < 60) return '$mins min más rápida';
    final hours = mins ~/ 60;
    final remainMins = mins % 60;
    return '${hours}h ${remainMins}min más rápida';
  }
}
