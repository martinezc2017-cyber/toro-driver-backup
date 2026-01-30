import 'dart:math';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Controlador de navegación estilo Google Maps
///
/// Características:
/// - Cámara instantánea (sin animaciones)
/// - Smoothing con thresholds configurables
/// - Sin edificios 3D durante navegación
/// - Optimizado para bajo consumo de GPU
///
/// NOTA: Los freezes en emulador son causados por GPU virtualizada,
/// no por este código. Probar en dispositivo físico para validar.
class GoogleNavigationController {
  final MapboxMap map;

  // === THRESHOLDS CONFIGURABLES ===
  /// Distancia mínima en metros para actualizar cámara
  final double minDistanceMeters;

  /// Cambio mínimo de bearing en grados para actualizar cámara
  final double minBearingDegrees;

  /// Tiempo mínimo entre actualizaciones en ms
  final int minUpdateIntervalMs;

  // === ESTADO INTERNO ===
  double? _lastLat;
  double? _lastLng;
  double? _lastBearing;
  DateTime? _lastUpdateTime;
  int _updateCount = 0;

  // === CONFIGURACIÓN DE CÁMARA ===
  final double defaultZoom;
  final double defaultPitch;

  GoogleNavigationController(
    this.map, {
    this.minDistanceMeters = 8.0,      // Google usa ~8-15m
    this.minBearingDegrees = 8.0,      // Google usa ~8-12°
    this.minUpdateIntervalMs = 250,    // Google usa ~250-500ms
    this.defaultZoom = 20.0,           // ZOOM CERCANO: Vista de calle
    this.defaultPitch = 60.0,          // Pitch alto para vista 3D inmersiva
  });

  // ============================
  // INIT
  // ============================
  Future<void> init() async {
    await _disable3DBuildings();
    await _setInitialCamera();
  }

  /// Desactiva edificios 3D (Google no los usa en navegación activa)
  Future<void> _disable3DBuildings() async {
    try {
      // Intenta remover la capa de edificios 3D
      await map.style.removeStyleLayer('building-extrusion');
    } catch (_) {
      // Si no existe, ignorar
    }
    try {
      await map.style.removeStyleLayer('building');
    } catch (_) {}
  }

  /// Configura cámara inicial con vista cercana de calle
  Future<void> _setInitialCamera() async {
    await map.setCamera(
      CameraOptions(
        zoom: defaultZoom,      // 20.0 - Vista cercana de calle
        pitch: defaultPitch,    // 60.0 - Vista 3D inmersiva
        bearing: 0,
      ),
    );
  }

  // ============================
  // HAVERSINE DISTANCE
  // ============================
  /// Calcula distancia en metros entre dos puntos usando fórmula Haversine
  double _haversineDistance(double lat1, double lng1, double lat2, double lng2) {
    const double earthRadius = 6371000; // metros

    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
              cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
              sin(dLng / 2) * sin(dLng / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * pi / 180;

  // ============================
  // SHOULD UPDATE CHECK
  // ============================
  /// Determina si la cámara debe actualizarse basado en thresholds
  bool _shouldUpdate(double lat, double lng, double bearing) {
    // Primera actualización siempre
    if (_lastLat == null || _lastLng == null) return true;

    // Throttle por tiempo
    if (_lastUpdateTime != null) {
      final elapsed = DateTime.now().difference(_lastUpdateTime!).inMilliseconds;
      if (elapsed < minUpdateIntervalMs) return false;
    }

    // Calcular distancia en metros
    final distance = _haversineDistance(_lastLat!, _lastLng!, lat, lng);

    // Calcular diferencia de bearing (normalizada 0-180)
    double bearingDiff = (bearing - (_lastBearing ?? 0)).abs();
    if (bearingDiff > 180) bearingDiff = 360 - bearingDiff;

    // Actualizar si supera cualquier threshold
    if (distance >= minDistanceMeters || bearingDiff >= minBearingDegrees) {
      return true;
    }

    return false;
  }

  // ============================
  // UPDATE POSITION (Google Style)
  // ============================
  /// Actualiza la posición de la cámara estilo Google Maps
  ///
  /// Retorna true si se actualizó, false si se skipeó
  Future<bool> updatePosition({
    required double lat,
    required double lng,
    required double bearing,
    double? customZoom,
    double? customPitch,
  }) async {
    // Verificar si debe actualizar
    if (!_shouldUpdate(lat, lng, bearing)) {
      return false;
    }

    // Guardar estado
    _lastLat = lat;
    _lastLng = lng;
    _lastBearing = bearing;
    _lastUpdateTime = DateTime.now();
    _updateCount++;

    // Crear punto
    final point = Point(coordinates: Position(lng, lat));

    // Movimiento instantáneo (Google no usa animaciones durante nav)
    await map.setCamera(
      CameraOptions(
        center: point,
        bearing: bearing,
        zoom: customZoom ?? defaultZoom,
        pitch: customPitch ?? defaultPitch,
      ),
    );

    return true;
  }

  // ============================
  // ZOOM DINÁMICO POR VELOCIDAD
  // ============================
  /// Calcula zoom óptimo basado en velocidad (mph)
  /// ZOOM CERCANO: Vista de calle, no de avión
  double calculateZoomForSpeed(double speedMph) {
    if (speedMph > 60) {
      return 18.5; // Autopista - un poco más alejado pero aún cercano
    } else if (speedMph > 40) {
      return 19.0;
    } else if (speedMph > 20) {
      return 19.5;
    } else if (speedMph > 10) {
      return 20.0;
    } else {
      return 21.0; // Detenido/lento - muy cercano (vista de calle)
    }
  }

  /// Calcula pitch óptimo basado en velocidad (mph)
  /// PITCH ALTO: Vista 3D inmersiva estilo conductor
  double calculatePitchForSpeed(double speedMph) {
    if (speedMph > 50) {
      return 70.0; // Muy inclinado en autopista (vista lejana del horizonte)
    } else if (speedMph > 20) {
      return 65.0; // Inclinado en ciudad
    } else {
      return 60.0; // Vista inmersiva cuando lento/detenido
    }
  }

  // ============================
  // UPDATE CON VELOCIDAD
  // ============================
  /// Actualiza posición con zoom/pitch dinámico por velocidad
  Future<bool> updatePositionWithSpeed({
    required double lat,
    required double lng,
    required double bearing,
    required double speedMph,
  }) async {
    final dynamicZoom = calculateZoomForSpeed(speedMph);
    final dynamicPitch = calculatePitchForSpeed(speedMph);

    return updatePosition(
      lat: lat,
      lng: lng,
      bearing: bearing,
      customZoom: dynamicZoom,
      customPitch: dynamicPitch,
    );
  }

  // ============================
  // GETTERS
  // ============================
  int get updateCount => _updateCount;
  double? get lastLat => _lastLat;
  double? get lastLng => _lastLng;
  double? get lastBearing => _lastBearing;

  // ============================
  // RESET
  // ============================
  void reset() {
    _lastLat = null;
    _lastLng = null;
    _lastBearing = null;
    _lastUpdateTime = null;
    _updateCount = 0;
  }
}
