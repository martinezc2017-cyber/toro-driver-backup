// ============================================================================
// TORO DRIVER - NAVIGATION MAP SCREEN
// Mapa de navegación completo conectado con RideProvider
// ============================================================================

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/ride_provider.dart';
import '../models/ride_model.dart';
import '../services/geocoding_service.dart';
import '../services/directions_service.dart';
import '../services/navigation_service.dart';
import '../services/poi_service.dart';
// Map matching removido - usamos los steps de la ruta para nombre de calle (gratis)
import '../widgets/navigation_ui.dart';

const String _mapboxToken = 'pk.eyJ1IjoibWFydGluZXpjMjAxNyIsImEiOiJjbWtocWtoZHIwbW1iM2dvdXZ3bmp0ZjBiIn0.MjYgv6DuvLTkrBVbrhtFbg';

class NavigationMapScreen extends StatefulWidget {
  const NavigationMapScreen({super.key});

  @override
  State<NavigationMapScreen> createState() => _NavigationMapScreenState();
}

class _NavigationMapScreenState extends State<NavigationMapScreen> {
  MapboxMap? _map;
  bool _isMapReady = false;
  double _currentSpeed = 0;
  double _currentLat = 33.4484;
  double _currentLng = -112.0740;
  double _currentBearing = 0;
  StreamSubscription<geo.Position>? _gpsStream;
  // Variable removida: _navUpdateTimer no se usaba

  // Navegación
  late final GeocodingService _geocodingService;
  late final NavigationService _navigationService;
  late final PoiService _poiService;
  late final FlutterTts _tts;
  NavigationState _navState = NavigationState.idle();
  bool _isMuted = false;
  PolylineAnnotationManager? _routeLineManager;
  PointAnnotationManager? _parkingMarkersManager;

  // Asistencia de navegación
  List<ParkingPlace> _nearbyParkings = [];
  bool _showParkingPanel = false;
  bool _tollAlertShown = false;

  // Vanishing route
  List<List<double>> _fullRouteCoords = [];
  List<String> _routeCongestion = [];
  DateTime? _lastRouteUpdate;
  DateTime? _lastStreetUpdate;

  // Zoom y pitch - 2D plano para mejor rendimiento
  double _currentZoom = 17.0;
  final double _currentPitch = 0.0;  // 0 = 2D plano, 60 = 3D
  DateTime? _lastZoomUpdate;  // Throttle para adaptive zoom

  // UI de navegación
  bool _isOverviewMode = false;
  String? _currentStreetName;
  String? _currentCounty;
  String? _currentHighwayShield;
  int _lastStepIndex = -1;

  // Cámara libre
  bool _isFreeCameraMode = false;
  Timer? _returnToCenterTimer;

  // Control de ride actual
  String? _currentRideId;
  String? _currentTargetType; // 'pickup' o 'dropoff'
  String? _lastCheckedRideId;  // Para evitar re-checks innecesarios
  RideStatus? _lastCheckedStatus;

  @override
  void initState() {
    super.initState();
    _geocodingService = GeocodingService(_mapboxToken);
    _navigationService = NavigationService(_mapboxToken);
    _poiService = PoiService(_mapboxToken);
    _tts = FlutterTts();
    _initTts();
    _initWakelock();
    _checkPermissions();
    _setupNavigationCallbacks();
  }

  void _initTts() async {
    await _tts.setLanguage('es-ES');
    await _tts.setSpeechRate(0.5);
  }

  void _initWakelock() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {}
  }

  Future<void> _checkPermissions() async {
    bool serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    geo.LocationPermission permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }
  }

  void _setupNavigationCallbacks() {
    _navigationService.onStateChanged = (state) {
      if (mounted) {
        setState(() => _navState = state);
      }
    };

    _navigationService.onVoiceInstruction = (instruction) {
      if (!_isMuted) _tts.speak(instruction);
    };

    _navigationService.onArrival = () {
      _onArrivalAtTarget();
    };

    _navigationService.onReroute = (newRoute) {
      // PLAYBOOK: Polyline solo en reroute
      _drawRoute(newRoute);
    };

    _navigationService.onTollWarning = (tollCost) {
      if (!_tollAlertShown) {
        _tollAlertShown = true;
        if (!_isMuted) {
          if (tollCost != null && tollCost > 0) {
            _tts.speak('Esta ruta tiene peajes. Costo estimado: ${tollCost.toStringAsFixed(0)} dólares');
          } else {
            _tts.speak('Atención: esta ruta tiene peajes');
          }
        }
      }
    };

    _navigationService.onNearDestinationForParking = (destLat, destLng) async {
      final parkings = await _poiService.searchNearbyParkings(
        lat: destLat,
        lng: destLng,
        radiusMeters: 500,
        limit: 5,
      );

      if (parkings.isNotEmpty && mounted) {
        setState(() {
          _nearbyParkings = parkings;
          _showParkingPanel = true;
        });
        _showParkingMarkers(parkings);
        if (!_isMuted) {
          _tts.speak('Hay ${parkings.length} estacionamientos cerca del destino');
        }
      }
    };
  }

  void _onMapCreated(MapboxMap map) async {
    _map = map;

    // OPTIMIZACIÓN: Desactivar elementos de UI innecesarios
    await map.compass.updateSettings(CompassSettings(enabled: false));
    await map.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
    await map.attribution.updateSettings(AttributionSettings(enabled: false));
    await map.logo.updateSettings(LogoSettings(enabled: false));

    // Habilitar gestos para cámara libre
    await map.gestures.updateSettings(GesturesSettings(
      scrollEnabled: true,
      rotateEnabled: true,
      pitchEnabled: true,
      doubleTapToZoomInEnabled: true,
      doubleTouchToZoomOutEnabled: true,
      quickZoomEnabled: true,
      pinchToZoomEnabled: true,
      pinchPanEnabled: true,
    ));

    await map.location.updateSettings(LocationComponentSettings(
      enabled: true,
      puckBearingEnabled: true,
      pulsingEnabled: false,
      showAccuracyRing: false,
      puckBearing: PuckBearing.COURSE,
      locationPuck: LocationPuck(
        locationPuck2D: DefaultLocationPuck2D(
          topImage: null,
          bearingImage: null,
          shadowImage: null,
          scaleExpression: '1.5',  // Puck 50% más grande
        ),
      ),
    ));

    _routeLineManager = await map.annotations.createPolylineAnnotationManager();
    _parkingMarkersManager = await map.annotations.createPointAnnotationManager();


    setState(() => _isMapReady = true);

    // PATCH: distanceFilter=5 evita callbacks constantes (menos CPU/GC/jank)
    _gpsStream = geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).listen(_onGpsUpdate);
  }

  // Variables para throttling según playbook
  double _lastUpdateLat = 0;
  double _lastUpdateLng = 0;
  double _lastUpdateBearing = 0;
  DateTime? _lastGpsTime;

  void _onGpsUpdate(geo.Position pos) {
    // PATCH: Evitar NaN/heading basura
    if (!pos.latitude.isFinite || !pos.longitude.isFinite) return;
    final heading = (pos.heading.isFinite && pos.heading >= 0) ? pos.heading : _lastUpdateBearing;
    final speed = (pos.speed.isFinite && pos.speed >= 0) ? pos.speed : _currentSpeed;

    // Throttle GPS a 1 Hz máximo para UI
    final now = DateTime.now();
    if (_lastGpsTime != null && now.difference(_lastGpsTime!).inMilliseconds < 1000) {
      return;
    }

    // Ignorar GPS con mala precisión (> 35m)
    if (pos.accuracy > 35) {
      return;
    }

    // Deadband thresholds - ignorar cambios pequeños
    final distMoved = _quickDistance(_lastUpdateLat, _lastUpdateLng, pos.latitude, pos.longitude);
    final bearingChange = (heading - _lastUpdateBearing).abs();
    final speedChange = (speed - _currentSpeed).abs();

    if (distMoved < 5 && bearingChange < 10 && speedChange < 1.0) {
      return;
    }

    _lastGpsTime = now;
    _lastUpdateLat = pos.latitude;
    _lastUpdateLng = pos.longitude;
    _lastUpdateBearing = heading;

    _currentLat = pos.latitude;
    _currentLng = pos.longitude;
    _currentSpeed = speed;

    if (speed > 1.5) {
      _currentBearing = heading;
    }

    // FollowPuckViewportState maneja el seguimiento de cámara automáticamente

    // LOG PUCK: posición actual
    debugPrint('📍 PUCK: ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)} | spd:${(speed*3.6).toStringAsFixed(0)}km/h | hdg:${heading.toStringAsFixed(0)}°');

    if (_navigationService.isNavigating) {
      _navigationService.updateLocation(
        pos.latitude,
        pos.longitude,
        pos.speed,
        pos.heading,
      );

      // LOG BANNER: step actual y distancia
      final stepIdx = _navState.currentStepIndex;
      final distNext = _navState.distanceToNextManeuver;
      final instruction = _navState.currentInstruction;
      debugPrint('🎯 BANNER: step=$stepIdx | dist=${distNext.toStringAsFixed(0)}m | "$instruction"');

      // PLAYBOOK: Nombre de calle solo cada 10 segundos
      if (_lastStreetUpdate == null ||
          now.difference(_lastStreetUpdate!).inMilliseconds >= 10000) {
        _lastStreetUpdate = now;
        _updateCurrentStreetName();
      }

      // Vanish line: actualizar en tiempo real con cada GPS
      _updateVanishingRoute();
    }
  }

  void _updateAdaptiveZoom() {
    // OPTIMIZACIÓN: Solo actualizar cada 2 segundos
    final now = DateTime.now();
    if (_lastZoomUpdate != null &&
        now.difference(_lastZoomUpdate!).inMilliseconds < 2000) {
      return;
    }
    _lastZoomUpdate = now;

    final kmh = _currentSpeed * 3.6;

    double targetZoom;
    if (kmh < 10) {
      targetZoom = 19.0;  // Parado/muy lento - muy cerca
    } else if (kmh < 30) {
      targetZoom = 19.0 - ((kmh - 10) / 20) * 1.0;  // 19 → 18
    } else if (kmh < 60) {
      targetZoom = 18.0 - ((kmh - 30) / 30) * 1.0;  // 18 → 17
    } else if (kmh < 100) {
      targetZoom = 17.0 - ((kmh - 60) / 40) * 1.0;  // 17 → 16
    } else {
      targetZoom = 16.0;  // Muy rápido
    }

    // Solo actualizar si el cambio es significativo (> 0.2)
    final newZoom = _currentZoom + (targetZoom - _currentZoom) * 0.1;
    if ((newZoom - _currentZoom).abs() > 0.2) {
      _currentZoom = newZoom;
    }
  }

  /// Actualiza el nombre de calle consultando el MAPA en la posición del puck (GRATIS)
  /// OPTIMIZADO: Una sola query con todas las capas combinadas
  Future<void> _updateCurrentStreetName() async {
    if (_map == null) return;

    try {
      // Convertir coordenadas GPS a punto en pantalla
      final screenPoint = await _map!.pixelForCoordinate(
        Point(coordinates: Position(_currentLng, _currentLat)),
      );

      // OPTIMIZADO: Una sola query con TODAS las capas de calles
      final features = await _map!.queryRenderedFeatures(
        RenderedQueryGeometry.fromScreenCoordinate(screenPoint),
        RenderedQueryOptions(
          layerIds: [
            // Labels (prioridad)
            'road-label', 'road-street-label', 'road-primary-label',
            'road-secondary-tertiary-label', 'road-motorway-label',
            // Roads (fallback)
            'road', 'road-street', 'road-primary', 'road-secondary-tertiary'
          ],
        ),
      );

      String? streetName;
      String? shield;

      for (final feature in features) {
        final props = feature?.queriedFeature.feature['properties'] as Map<String, dynamic>?;
        if (props != null) {
          // Buscar nombre de calle
          final name = props['name'] as String? ??
                       props['name_en'] as String? ??
                       props['name_es'] as String?;
          if (name != null && name.isNotEmpty) {
            streetName = name;
          }

          // Buscar shield de highway (ref = número de ruta)
          final ref = props['ref'] as String?;
          if (ref != null && ref.isNotEmpty) {
            shield = ref;
          }

          if (streetName != null) break;
        }
      }

      if (streetName != null && streetName != _currentStreetName && mounted) {
        setState(() {
          _currentStreetName = streetName;
          if (shield != null) {
            _currentHighwayShield = shield;
          }
        });
      }
    } catch (_) {
      // Silently handle errors
    }
  }

  // ============================================================================
  // CONEXIÓN CON RIDEPROVIDER
  // ============================================================================

  void _checkAndStartNavigation(RideModel? ride) {
    // OPTIMIZACIÓN: Evitar re-checks si nada cambió
    if (ride?.id == _lastCheckedRideId && ride?.status == _lastCheckedStatus) {
      return;  // Ya verificamos este ride con este status
    }
    _lastCheckedRideId = ride?.id;
    _lastCheckedStatus = ride?.status;

    if (ride == null) {
      if (_currentRideId != null) {
        _clearRoute();
        _currentRideId = null;
        _currentTargetType = null;
      }
      return;
    }

    String targetType;
    double targetLat;
    double targetLng;
    String targetName;

    if (ride.status == RideStatus.accepted ||
        ride.status == RideStatus.pending) {
      targetType = 'pickup';
      targetLat = ride.pickupLocation.latitude;
      targetLng = ride.pickupLocation.longitude;
      targetName = ride.pickupLocation.address ?? 'Punto de recogida';
    } else if (ride.status == RideStatus.inProgress ||
               ride.status == RideStatus.arrivedAtPickup) {
      targetType = 'dropoff';
      targetLat = ride.dropoffLocation.latitude;
      targetLng = ride.dropoffLocation.longitude;
      targetName = ride.dropoffLocation.address ?? 'Destino';
    } else {
      if (_currentRideId != null) {
        _clearRoute();
        _currentRideId = null;
        _currentTargetType = null;
      }
      return;
    }

    if (_currentRideId == ride.id && _currentTargetType == targetType) {
      return;
    }

    _currentRideId = ride.id;
    _currentTargetType = targetType;
    _startNavigationTo(targetLat, targetLng, targetName, targetType);
  }

  Future<void> _startNavigationTo(double lat, double lng, String name, String targetType) async {
    // Reset street tracking for new navigation
    _lastStepIndex = -1;
    
    final success = await _navigationService.startNavigation(
      originLat: _currentLat,
      originLng: _currentLng,
      destLat: lat,
      destLng: lng,
      bearing: _currentBearing > 0 ? _currentBearing : null,
    );

    if (success && _navigationService.currentRoute != null) {
      _drawRoute(_navigationService.currentRoute!);
      if (!_isMuted) {
        if (targetType == 'pickup') {
          _tts.speak('Navegando al punto de recogida');
        } else {
          _tts.speak('Navegando al destino del pasajero');
        }
      }
    }
  }

  void _onArrivalAtTarget() {
    if (mounted) {
      final message = _currentTargetType == 'pickup'
          ? 'Has llegado al punto de recogida'
          : 'Has llegado al destino';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }

    _clearRoute();
    _currentTargetType = null;
  }

  Future<void> _callPassenger(RideModel? ride) async {
    if (ride == null || ride.passengerPhone == null) return;

    final phone = ride.passengerPhone!.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$phone');

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  // ============================================================================
  // DIBUJO DE RUTA
  // ============================================================================

  Future<void> _drawRoute(DirectionsRoute route) async {
    if (_routeLineManager == null) return;

    // PATCH: Simplificar a 500 puntos máx
    final newCoords = _simplifyRoute(route.coordinates, targetCount: 500);

    // PATCH: Evitar redraw si ruta similar
    if (_fullRouteCoords.isNotEmpty && _areRoutesSimilar(_fullRouteCoords, newCoords)) {
      return;
    }

    _fullRouteCoords = newCoords;
    _lastRouteUpdate = null;

    _routeCongestion = [];
    for (final leg in route.legs) {
      if (leg.annotations?.congestion != null) {
        _routeCongestion.addAll(leg.annotations!.congestion!);
      }
    }

    await _routeLineManager!.deleteAll();
    // PATCH: Micro delay reduce picos de GC/composición
    await Future<void>.delayed(const Duration(milliseconds: 16));

    if (_fullRouteCoords.isEmpty) return;

    await _drawRouteWithVanish();
  }

  // PATCH: Verificar si rutas son similares (evitar redraw innecesario)
  bool _areRoutesSimilar(List<List<double>> old, List<List<double>> newRoute) {
    if (old.isEmpty || newRoute.isEmpty) return false;
    if ((old.length - newRoute.length).abs() > 50) return false;
    // Comparar primer y último punto
    final oldFirst = old.first;
    final newFirst = newRoute.first;
    final oldLast = old.last;
    final newLast = newRoute.last;
    final distFirst = _quickDistance(oldFirst[1], oldFirst[0], newFirst[1], newFirst[0]);
    final distLast = _quickDistance(oldLast[1], oldLast[0], newLast[1], newLast[0]);
    return distFirst < 50 && distLast < 50;  // Menos de 50m de diferencia
  }

  Future<void> _drawRouteWithVanish() async {
    if (_routeLineManager == null) return;
    if (_fullRouteCoords.length < 2) return;

    await _routeLineManager!.deleteAll();

    // Encontrar punto más cercano al puck
    int closestIdx = 0;
    double minDist = double.infinity;

    for (int i = 0; i < _fullRouteCoords.length; i++) {
      final coord = _fullRouteCoords[i];
      final dist = _quickDistance(_currentLat, _currentLng, coord[1], coord[0]);
      if (dist < minDist) {
        minDist = dist;
        closestIdx = i;
      }
    }

    // Si estamos muy lejos (> 500m), mostrar ruta completa
    if (minDist > 500) {
      final points = _fullRouteCoords.map((c) => Position(c[0], c[1])).toList();
      await _routeLineManager!.create(PolylineAnnotationOptions(
        geometry: LineString(coordinates: points),
        lineColor: 0xFF4285F4,
        lineWidth: 10.0,
        lineOpacity: 0.9,
      ));
      return;
    }

    // === GAP de 5m desde el puck ===
    int gapEndIdx = closestIdx;
    double gapDist = 0.0;
    for (int i = closestIdx; i < _fullRouteCoords.length - 1; i++) {
      final c1 = _fullRouteCoords[i];
      final c2 = _fullRouteCoords[i + 1];
      gapDist += _quickDistance(c1[1], c1[0], c2[1], c2[0]);
      if (gapDist >= 5.0) {
        gapEndIdx = i + 1;
        break;
      }
    }

    // === FADE de 0% a 100% en los siguientes 20m (4 segmentos) ===
    final fadeSegments = <Map<String, dynamic>>[];
    int fadeStartIdx = gapEndIdx;
    double fadeDist = 0.0;
    final fadeSteps = [
      {'dist': 5.0, 'opacity': 0.2},   // 5-10m: 20%
      {'dist': 5.0, 'opacity': 0.4},   // 10-15m: 40%
      {'dist': 5.0, 'opacity': 0.6},   // 15-20m: 60%
      {'dist': 5.0, 'opacity': 0.8},   // 20-25m: 80%
    ];

    for (final step in fadeSteps) {
      final targetDist = step['dist'] as double;
      final opacity = step['opacity'] as double;
      int segEndIdx = fadeStartIdx;
      double segDist = 0.0;

      for (int i = fadeStartIdx; i < _fullRouteCoords.length - 1; i++) {
        final c1 = _fullRouteCoords[i];
        final c2 = _fullRouteCoords[i + 1];
        segDist += _quickDistance(c1[1], c1[0], c2[1], c2[0]);
        if (segDist >= targetDist) {
          segEndIdx = i + 1;
          break;
        }
        segEndIdx = i + 1;
      }

      if (segEndIdx > fadeStartIdx && segEndIdx <= _fullRouteCoords.length) {
        fadeSegments.add({
          'start': fadeStartIdx,
          'end': segEndIdx,
          'opacity': opacity,
        });
        fadeStartIdx = segEndIdx;
      }
    }

    // Dibujar segmentos de fade
    for (final seg in fadeSegments) {
      final start = seg['start'] as int;
      final end = seg['end'] as int;
      final opacity = seg['opacity'] as double;

      if (end > start && end <= _fullRouteCoords.length) {
        final coords = _fullRouteCoords.sublist(start, end + 1 > _fullRouteCoords.length ? _fullRouteCoords.length : end + 1);
        if (coords.length >= 2) {
          final points = coords.map((c) => Position(c[0], c[1])).toList();
          await _routeLineManager!.create(PolylineAnnotationOptions(
            geometry: LineString(coordinates: points),
            lineColor: 0xFF4285F4,
            lineWidth: 10.0,
            lineOpacity: opacity,
          ));
        }
      }
    }

    // === LÍNEA PRINCIPAL (100% opacidad) desde el fin del fade hasta el destino ===
    final mainStartIdx = fadeStartIdx;
    if (mainStartIdx < _fullRouteCoords.length - 1) {
      final coords = _fullRouteCoords.sublist(mainStartIdx);
      if (coords.length >= 2) {
        final points = coords.map((c) => Position(c[0], c[1])).toList();
        await _routeLineManager!.create(PolylineAnnotationOptions(
          geometry: LineString(coordinates: points),
          lineColor: 0xFF4285F4,
          lineWidth: 10.0,
          lineOpacity: 1.0,
        ));
        debugPrint('🗺️ VANISH: gap5m→fade${fadeSegments.length}segs→main${coords.length}pts (closest=$closestIdx dist=${minDist.toStringAsFixed(0)}m)');
      }
    }
  }

  /// Dibuja la ruta completa sin vanishing (cuando el usuario está lejos)
  Future<void> _drawFullRoute() async {
    if (_routeLineManager == null || _fullRouteCoords.length < 2) return;
    await _drawRouteWithCongestion(_fullRouteCoords, _routeCongestion, 0);
  }

  Future<void> _drawRouteWithCongestion(
    List<List<double>> coords,
    List<String> congestion,
    int startIndex,
  ) async {
    if (_routeLineManager == null || coords.length < 2) return;

    List<_CongestionSegment> segments = [];
    int segmentStart = 0;
    String? currentLevel;

    for (int i = 0; i < coords.length - 1; i++) {
      final congestionIdx = startIndex + i;
      String level = 'low';
      if (congestionIdx < congestion.length) {
        level = congestion[congestionIdx];
      }

      if (level == 'unknown') level = 'low';

      if (currentLevel == null) {
        currentLevel = level;
        segmentStart = i;
      } else if (level != currentLevel) {
        segments.add(_CongestionSegment(
          startIdx: segmentStart,
          endIdx: i,
          level: currentLevel,
        ));
        currentLevel = level;
        segmentStart = i;
      }
    }

    if (currentLevel != null) {
      segments.add(_CongestionSegment(
        startIdx: segmentStart,
        endIdx: coords.length - 1,
        level: currentLevel,
      ));
    }

    for (final segment in segments) {
      final segmentCoords = coords.sublist(segment.startIdx, segment.endIdx + 1);
      if (segmentCoords.length < 2) continue;

      final points = segmentCoords.map((c) => Position(c[0], c[1])).toList();
      final color = _getCongestionColor(segment.level);

      await _routeLineManager!.create(PolylineAnnotationOptions(
        geometry: LineString(coordinates: points),
        lineColor: color,
        lineWidth: 12.0,
        lineOpacity: 0.95,
      ));
    }
  }

  int _getCongestionColor(String level) {
    switch (level) {
      case 'severe':
        return 0xFFB71C1C;
      case 'heavy':
        return 0xFFE53935;
      case 'moderate':
        return 0xFFFFA726;
      case 'low':
      case 'unknown':
      default:
        return 0xFF4285F4;
    }
  }

  double _quickDistance(double lat1, double lng1, double lat2, double lng2) {
    const metersPerDegLat = 111320.0;
    final metersPerDegLng = 111320.0 * math.cos(lat1 * math.pi / 180);
    final dLat = (lat2 - lat1) * metersPerDegLat;
    final dLng = (lng2 - lng1) * metersPerDegLng;
    return math.sqrt(dLat * dLat + dLng * dLng);
  }

  /// PLAYBOOK SECRETO #3: Douglas-Peucker simplification
  /// Reduce puntos de ruta a máximo targetCount (default 500)
  List<List<double>> _simplifyRoute(List<List<double>> coords, {int targetCount = 500}) {
    if (coords.length <= targetCount) return coords;

    // Simplificación por sampling uniforme (rápido y efectivo)
    final step = coords.length / targetCount;
    final result = <List<double>>[];

    for (var i = 0.0; i < coords.length; i += step) {
      result.add(coords[i.floor()]);
    }

    // Siempre incluir el último punto
    if (result.last != coords.last) {
      result.add(coords.last);
    }

    return result;
  }

  Future<void> _updateVanishingRoute() async {
    if (_routeLineManager == null) return;
    if (_fullRouteCoords.length < 2) return; // Mismo requisito que _drawRouteWithVanish
    await _drawRouteWithVanish();
  }

  void _clearRoute() async {
    await _routeLineManager?.deleteAll();
    await _parkingMarkersManager?.deleteAll();
    _navigationService.stopNavigation();
    _fullRouteCoords = [];
    _routeCongestion = [];
    _lastRouteUpdate = null;
    _nearbyParkings = [];
    _showParkingPanel = false;
    _tollAlertShown = false;
    // Reset street name tracking
    _lastStepIndex = -1;
        _currentStreetName = null;
    _currentHighwayShield = null;
    if (mounted) setState(() => _navState = NavigationState.idle());
  }

  Future<void> _showParkingMarkers(List<ParkingPlace> parkings) async {
    if (_parkingMarkersManager == null) return;

    await _parkingMarkersManager!.deleteAll();

    for (final parking in parkings) {
      await _parkingMarkersManager!.create(PointAnnotationOptions(
        geometry: Point(coordinates: Position(parking.lng, parking.lat)),
        iconSize: 0.8,
        textField: 'P',
        textSize: 12,
        textColor: 0xFFFFFFFF,
        textHaloColor: 0xFF1565C0,
        textHaloWidth: 2,
      ));
    }
  }

  void _toggleOverviewMode() async {
    setState(() => _isOverviewMode = !_isOverviewMode);

    if (_map == null || _navigationService.currentRoute == null) return;

    if (_isOverviewMode) {
      final coords = _navigationService.currentRoute!.coordinates;
      if (coords.length < 2) return;

      double minLat = double.infinity, maxLat = -double.infinity;
      double minLng = double.infinity, maxLng = -double.infinity;

      for (final c in coords) {
        if (c[1] < minLat) minLat = c[1];
        if (c[1] > maxLat) maxLat = c[1];
        if (c[0] < minLng) minLng = c[0];
        if (c[0] > maxLng) maxLng = c[0];
      }

      await _map!.setCamera(CameraOptions(
        center: Point(coordinates: Position(
          (minLng + maxLng) / 2,
          (minLat + maxLat) / 2,
        )),
        zoom: 11.0,
        pitch: 0,
        bearing: 0,
      ));
    }
  }

  void _showAllSteps() {
    if (_navState.currentRoute == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final steps = _navState.currentRoute!.legs
            .expand((leg) => leg.steps)
            .toList();

        return Container(
          padding: const EdgeInsets.all(16),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Pasos de la ruta',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: steps.length,
                  itemBuilder: (context, index) {
                    final step = steps[index];
                    final isCurrentStep = index == _navState.currentStepIndex;

                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      decoration: BoxDecoration(
                        color: isCurrentStep ? Colors.blue.withAlpha(50) : null,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: isCurrentStep ? Colors.blue : Colors.grey[700],
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  step.instruction ?? step.name ?? 'Continúa',
                                  style: TextStyle(
                                    color: isCurrentStep ? Colors.white : Colors.white70,
                                    fontWeight: isCurrentStep ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                                if (step.distance > 0)
                                  Text(
                                    step.distance < 1000
                                        ? '${step.distance.round()} m'
                                        : '${(step.distance / 1000).toStringAsFixed(1)} km',
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _gpsStream?.cancel();
    _returnToCenterTimer?.cancel();
    _tts.stop();
    WakelockPlus.disable();
    super.dispose();
  }

  /// Recentrar cámara en el conductor
  void _centerOnDriver() async {
    if (_map == null) return;

    _returnToCenterTimer?.cancel();
    setState(() => _isFreeCameraMode = false);

    await _map!.setCamera(CameraOptions(
      center: Point(coordinates: Position(_currentLng, _currentLat)),
      zoom: _currentZoom,
      bearing: _currentBearing,
      pitch: _currentPitch,
    ));
  }

  /// Cuando el usuario interactúa con el mapa
  void _onUserCameraMove() {
    if (!_isFreeCameraMode) {
      setState(() => _isFreeCameraMode = true);
    }

    // Cancelar timer anterior
    _returnToCenterTimer?.cancel();

    // Auto-recentrar después de 10 segundos de inactividad
    _returnToCenterTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && _isFreeCameraMode) {
        _centerOnDriver();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Consumer<RideProvider>(
      builder: (context, rideProvider, child) {
        final ride = rideProvider.activeRide;

        // Solo verificar navegación si el mapa está listo y el ride cambió
        if (_isMapReady) {
          _checkAndStartNavigation(ride);
        }

        return Scaffold(
          body: Stack(
            children: [
              // Mapa de navegación - desplazado hacia abajo para que el puck quede cerca del widget inferior
              Transform.translate(
                offset: Offset(0, screenHeight * 0.20),  // Mover mapa hacia abajo = puck más abajo
                child: SizedBox(
                  width: double.infinity,
                  height: screenHeight * 1.4,  // Mapa más alto para compensar
                  child: MapWidget(
                    key: const ValueKey('nav_map'),
                    viewport: FollowPuckViewportState(
                      zoom: 17.0,
                      bearing: FollowPuckViewportStateBearingCourse(),
                      pitch: 45.0,  // Inclinación para mejor perspectiva
                    ),
                    styleUri: 'mapbox://styles/mapbox/navigation-night-v1',
                    onMapCreated: _onMapCreated,
                    androidHostingMode: AndroidPlatformViewHostingMode.VD,
                  ),
                ),
              ),

              // NavigationUI restaurado
              if (_navState.isNavigating)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: NavigationUI(
                    state: _navState,
                    isMuted: _isMuted,
                    isOverviewMode: _isOverviewMode,
                    hasTolls: _navState.hasTolls,
                    incidentCount: 0,
                    currentSpeed: _currentSpeed,
                    speedLimit: _navState.speedLimit,
                    currentStreetName: _currentStreetName,
                    currentCounty: _currentCounty,
                    gpsHighwayShield: _currentHighwayShield,
                    ride: rideProvider.activeRide,
                    onMute: () => setState(() => _isMuted = !_isMuted),
                    onOverview: _toggleOverviewMode,
                    onShowSteps: _showAllSteps,
                    onClose: _clearRoute,
                    onCallPassenger: () => _callPassenger(rideProvider.activeRide),
                  ),
                ),

              // Panel de parkings cercanos
              if (_showParkingPanel && _nearbyParkings.isNotEmpty)
                Positioned(
                  bottom: 100,
                  left: 12,
                  right: 12,
                  child: _buildParkingPanel(),
                ),

              // Indicador minimalista de carga - abajo del puck
              if (!_navState.isNavigating && rideProvider.activeRide != null && _isMapReady)
                Positioned(
                  bottom: 80,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Calculando...',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Indicador de estado (cuando no hay ride)
              if (!_navState.isNavigating && rideProvider.activeRide == null)
                Positioned(
                  bottom: 30,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _isMapReady ? Colors.green : Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('TORO NAV',
                          style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        const Text('Esperando viaje...',
                          style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                ),

              // Botón retroceder (solo cuando NO hay navegación activa)
              if (!_navState.isNavigating)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  left: 12,
                  child: Material(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(24),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => Navigator.of(context).pop(),
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(Icons.arrow_back, color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRideInfoBanner(RideModel ride) {
    final isGoingToPickup = ride.status == RideStatus.accepted ||
                            ride.status == RideStatus.pending;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D).withAlpha(230),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(100),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                isGoingToPickup ? Icons.person_pin_circle : Icons.flag,
                color: isGoingToPickup ? Colors.blue : Colors.green,
              ),
              const SizedBox(width: 8),
              Text(
                isGoingToPickup ? 'Recogida' : 'Destino',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isGoingToPickup
                ? (ride.pickupLocation.address ?? 'Punto de recogida')
                : (ride.dropoffLocation.address ?? 'Destino'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            'Iniciando navegación...',
            style: TextStyle(
              color: Colors.orange.shade300,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParkingPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(100),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_parking, color: Colors.blue, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Estacionamientos cercanos',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _showParkingPanel = false),
                child: const Icon(Icons.close, color: Colors.white54, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 60,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _nearbyParkings.length,
              itemBuilder: (context, index) {
                final parking = _nearbyParkings[index];
                return Container(
                  width: 140,
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        parking.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.location_on, color: Colors.white54, size: 12),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              parking.address.isNotEmpty
                                  ? parking.address
                                  : 'Cerca del destino',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 10,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CongestionSegment {
  final int startIdx;
  final int endIdx;
  final String level;

  _CongestionSegment({
    required this.startIdx,
    required this.endIdx,
    required this.level,
  });
}
