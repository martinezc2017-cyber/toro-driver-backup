import 'dart:async';
import 'dart:math' as math;
import 'directions_service.dart';

/// Servicio de navegación turn-by-turn
class NavigationService {
  final DirectionsService _directionsService;

  DirectionsRoute? _currentRoute;
  int _currentStepIndex = 0;
  int _currentLegIndex = 0;
  double _distanceToNextManeuver = 0;
  double _distanceRemaining = 0;
  double _durationRemaining = 0;

  // Callbacks
  Function(NavigationState)? onStateChanged;
  Function(String)? onVoiceInstruction;
  Function()? onArrival;
  Function(DirectionsRoute)? onReroute;

  // Estado
  bool _isNavigating = false;
  double _lastLat = 0;
  double _lastLng = 0;

  // Control de audio para evitar repeticiones
  String _lastSpokenInstruction = '';
  DateTime? _lastVoiceTime;
  bool _isRerouting = false;
  DateTime? _lastRerouteTime;
  static const int _voiceCooldownMs = 5000; // 5 segundos entre instrucciones
  static const int _rerouteCooldownMs = 5000; // 5 segundos entre recálculos

  // Flags para alertas de voz por distancia (evitar repetición)
  bool _alerted500m = false;
  bool _alerted200m = false;
  bool _alerted100m = false;
  bool _alerted50m = false;

  // Dead reckoning (navegacion sin GPS)
  bool _isDeadReckoning = false;
  DateTime? _lastValidGpsTime;
  double _lastValidSpeed = 0;
  double _lastValidBearing = 0;
  double _deadReckonLat = 0;
  double _deadReckonLng = 0;
  static const int _gpsLostThresholdMs = 3000; // 3 segundos sin GPS = dead reckoning
  static const int _deadReckonMaxMs = 30000; // Maximo 30 segundos de dead reckoning

  // Annotations actuales
  double? _currentSpeedLimit;
  String? _currentCongestion;

  // Configuración
  double offRouteThreshold = 30.0; // metros para considerar fuera de ruta (más sensible)
  double maneuverAlertDistance = 200.0; // metros para alertar maniobra
  double arrivalThreshold = 30.0; // metros para considerar llegada

  // Contador para confirmar off-route (evitar falsos positivos)
  int _offRouteCount = 0;
  static const int _offRouteCountThreshold = 2; // Necesita 2 detecciones seguidas

  // Tracking de distancia para detectar cuando pasamos un maneuver
  double _lastDistToManeuver = double.infinity;
  bool _wasApproaching = false; // true si la distancia estaba disminuyendo

  // Exit guidance (guía de salidas)
  bool _exitAlerted1km = false;
  bool _exitAlerted500m = false;
  bool _exitAlerted300m = false;
  String? _pendingExitName;

  // Toll warnings (alertas de peajes)
  bool _tollAlertedOnStart = false;

  // Parking near destination
  bool _parkingAlertSent = false;
  static const double _parkingAlertDistance = 800.0; // metros

  // Airport assistance
  bool _isAirportDestination = false;
  bool _airportAlert2km = false;
  bool _airportAlert500m = false;

  // Callbacks adicionales
  Function(String exitName, double distance)? onExitApproaching;
  Function(double? tollCost)? onTollWarning;
  Function(double destLat, double destLng)? onNearDestinationForParking;
  Function(String instruction)? onAirportInstruction;

  NavigationService(String accessToken)
      : _directionsService = DirectionsService(accessToken);

  /// Inicia navegación hacia un destino
  Future<bool> startNavigation({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    double? bearing,
    String? approaches,
    bool isAirport = false,
  }) async {
    _isAirportDestination = isAirport;
    final route = await _directionsService.getRoute(
      originLat: originLat,
      originLng: originLng,
      destLat: destLat,
      destLng: destLng,
      bearing: bearing,
      approaches: approaches ?? 'unrestricted;curb',
      continueStraight: true,
    );

    if (route == null) return false;

    // RESET completo para nueva ruta
    _currentRoute = route;
    _currentStepIndex = 0;
    _currentLegIndex = 0;
    _distanceRemaining = route.distance;
    _durationRemaining = route.duration;
    _distanceToNextManeuver = 0;
    _isNavigating = true;
    _lastLat = originLat;
    _lastLng = originLng;

    // Reset control de audio y recálculo
    _lastSpokenInstruction = '';
    _lastVoiceTime = null;
    _isRerouting = false;
    _lastRerouteTime = null;

    // Reset alertas de voz por distancia
    _alerted500m = false;
    _alerted200m = false;
    _alerted100m = false;
    _alerted50m = false;

    // Reset asistencia de navegación
    _exitAlerted1km = false;
    _exitAlerted500m = false;
    _exitAlerted300m = false;
    _airportAlert2km = false;
    _airportAlert500m = false;
    _pendingExitName = null;
    _tollAlertedOnStart = false;
    _parkingAlertSent = false;
    _offRouteCount = 0;

    // Alerta de peajes al inicio de la ruta
    if (route.hasTolls) {
      _tollAlertedOnStart = true;
      onTollWarning?.call(route.tollCost);
    }

    _updateDistanceToNextManeuver(originLat, originLng);
    _notifyStateChanged();

    return true;
  }

  /// Actualiza la posición actual del usuario
  void updateLocation(double lat, double lng, double speed, double bearing) {
    if (!_isNavigating || _currentRoute == null) return;

    final now = DateTime.now();

    // GPS valido recibido - salir de dead reckoning
    _isDeadReckoning = false;
    _lastValidGpsTime = now;
    _lastValidSpeed = speed;
    _lastValidBearing = bearing >= 0 ? bearing : _lastValidBearing;

    // Guardar posición actual ANTES de cualquier actualización
    _lastLat = lat;
    _lastLng = lng;

    // Verificar si está fuera de ruta (distancia)
    final distanceToRoute = _getDistanceToRoute(lat, lng);
    bool isOffRoute = false;

    if (distanceToRoute > offRouteThreshold) {
      isOffRoute = true;
    }

    // Verificar si va en dirección opuesta a la ruta
    if (speed > 5 && bearing >= 0) {
      final routeBearing = _getRouteBearing(lat, lng);
      if (routeBearing != null) {
        final bearingDiff = _getBearingDifference(bearing, routeBearing);
        if (bearingDiff > 150) { // Solo si va MUY opuesto
          isOffRoute = true;
        }
      }
    }

    // Contar detecciones de off-route antes de actuar
    if (isOffRoute) {
      _offRouteCount++;
      if (_offRouteCount >= _offRouteCountThreshold) {
        _handleOffRoute(lat, lng, userBearing: bearing >= 0 ? bearing : null);
        _offRouteCount = 0;
        // NO retornar - seguir actualizando el estado mientras se recalcula
      }
    } else {
      _offRouteCount = 0; // Reset si está en ruta
    }

    // IMPORTANTE: Actualizar PRIMERO la distancia al próximo maneuver
    _updateDistanceToNextManeuver(lat, lng);

    // Luego verificar si pasó el maneuver actual
    _checkManeuverProgress(lat, lng);

    // IMPORTANTE: Recalcular distancia después de posible avance de step
    if (_currentStepIndex > 0) {
      _updateDistanceToNextManeuver(lat, lng);
    }

    // Actualizar distancia/tiempo restante
    _updateRemainingDistance(lat, lng);

    // Actualizar annotations (speed limit, congestion)
    _updateAnnotations(lat, lng);

    // Verificar llegada
    if (_checkArrival(lat, lng)) {
      _handleArrival();
      return;
    }

    // Verificar si debe dar instrucción de voz
    _checkVoiceInstruction();

    // Verificar guía de salidas (exit guidance)
    _checkExitGuidance();

    // Verificar parking cerca del destino
    _checkParkingNearDestination(lat, lng);

    // Verificar asistencia de aeropuerto
    _checkAirportAssistance();

    // SIEMPRE notificar cambio de estado
    _notifyStateChanged();
  }

  /// Actualiza posicion usando dead reckoning cuando no hay GPS
  bool updateWithDeadReckoning() {
    if (!_isNavigating || _currentRoute == null) return false;
    if (_lastValidGpsTime == null) return false;

    final now = DateTime.now();
    final elapsed = now.difference(_lastValidGpsTime!).inMilliseconds;

    if (elapsed < _gpsLostThresholdMs) return false;
    if (elapsed > _deadReckonMaxMs) {
      _isDeadReckoning = false;
      return false;
    }

    _isDeadReckoning = true;

    final elapsedSec = elapsed / 1000.0;
    final distance = _lastValidSpeed * elapsedSec;

    final newPos = _projectPosition(_lastLat, _lastLng, _lastValidBearing, distance);
    _deadReckonLat = newPos[0];
    _deadReckonLng = newPos[1];

    _updateDistanceToNextManeuver(_deadReckonLat, _deadReckonLng);
    _checkManeuverProgress(_deadReckonLat, _deadReckonLng);
    _updateRemainingDistance(_deadReckonLat, _deadReckonLng);

    _notifyStateChanged();
    return true;
  }

  List<double> _projectPosition(double lat, double lng, double bearing, double distance) {
    const R = 6371000.0;
    final bearingRad = bearing * math.pi / 180;
    final latRad = lat * math.pi / 180;
    final lngRad = lng * math.pi / 180;

    final newLatRad = math.asin(
      math.sin(latRad) * math.cos(distance / R) +
      math.cos(latRad) * math.sin(distance / R) * math.cos(bearingRad)
    );

    final newLngRad = lngRad + math.atan2(
      math.sin(bearingRad) * math.sin(distance / R) * math.cos(latRad),
      math.cos(distance / R) - math.sin(latRad) * math.sin(newLatRad)
    );

    return [newLatRad * 180 / math.pi, newLngRad * 180 / math.pi];
  }

  void _updateAnnotations(double lat, double lng) {
    if (_currentRoute == null) return;
    final legs = _currentRoute!.legs;
    if (_currentLegIndex >= legs.length) return;

    final annotations = legs[_currentLegIndex].annotations;
    if (annotations == null) return;

    final coords = _currentRoute!.coordinates;
    int closestIdx = 0;
    double minDist = double.infinity;

    for (int i = 0; i < coords.length; i++) {
      final dist = _haversine(lat, lng, coords[i][1], coords[i][0]);
      if (dist < minDist) {
        minDist = dist;
        closestIdx = i;
      }
    }

    if (annotations.maxspeed != null && closestIdx < annotations.maxspeed!.length) {
      _currentSpeedLimit = annotations.maxspeed![closestIdx].speedKmh;
    }

    if (annotations.congestion != null && closestIdx < annotations.congestion!.length) {
      _currentCongestion = annotations.congestion![closestIdx];
    }
  }

  void stopNavigation() {
    _isNavigating = false;
    _currentRoute = null;
    _currentStepIndex = 0;
    _currentLegIndex = 0;
    _offRouteCount = 0;
    _notifyStateChanged();
  }

  /// Obtiene el estado actual de navegación
  NavigationState get currentState {
    if (!_isNavigating || _currentRoute == null) {
      return NavigationState.idle();
    }

    final currentStep = _getCurrentStep();
    final nextStep = _getNextStep();

    // SIMPLE: Siempre mostrar el step actual
    RouteStep? displayStep = currentStep;
    RouteStep? displayNextStep = nextStep;

    // Calcular distancia DIRECTA al maneuver del step actual
    double displayDistance = 0;
    if (currentStep != null) {
      final loc = currentStep.maneuver.location;
      if (loc != null && loc.length >= 2) {
        displayDistance = _haversine(_lastLat, _lastLng, loc[1], loc[0]);
      }
    }

    // El nombre de calle es hacia donde giras
    String turnOntoStreetName;
    final displayType = displayStep?.maneuver.type ?? '';

    if (displayType == 'arrive') {
      turnOntoStreetName = 'Destino';
    } else {
      // Usar displayName que muestra "ref • name" (ej: "AZ 202 • Red Mountain Fwy")
      turnOntoStreetName = displayStep?.displayName ?? '';
    }

    // Instrucción principal
    String mainInstruction = displayStep?.instruction ?? '';
    if (mainInstruction.isEmpty && displayStep != null) {
      mainInstruction = _buildInstruction(displayStep.maneuver);
    }

    // Obtener lanes del banner instruction actual
    List<LaneInfo>? currentLanes;
    List<BannerComponent>? currentShields;
    if (displayStep?.bannerInstruction != null) {
      currentLanes = displayStep!.bannerInstruction!.lanes;
      currentShields = displayStep.bannerInstruction!.shields;
    }

    // Verificar si hay una salida próxima
    bool hasExit = false;
    String? exitName;
    String? exitRef;
    if (displayStep != null && _isExitManeuver(displayStep.maneuver.type)) {
      hasExit = true;
      exitName = displayStep.name;
      exitRef = displayStep.ref;
    } else if (displayNextStep != null && _isExitManeuver(displayNextStep.maneuver.type)) {
      hasExit = true;
      exitName = displayNextStep.name;
      exitRef = displayNextStep.ref;
    }
    // También obtener ref si no es una salida pero tiene referencia de ruta
    exitRef ??= displayStep?.ref;

    return NavigationState(
      isNavigating: true,
      currentRoute: _currentRoute,
      currentStepIndex: _currentStepIndex,
      currentStep: displayStep,
      nextStep: displayNextStep,
      distanceToNextManeuver: displayDistance,
      distanceRemaining: _distanceRemaining,
      durationRemaining: _durationRemaining,
      currentInstruction: mainInstruction,
      nextInstruction: displayNextStep?.instruction,
      maneuverType: displayStep?.maneuver.type ?? 'straight',
      maneuverModifier: displayStep?.maneuver.modifier,
      streetName: turnOntoStreetName,
      lanes: currentLanes,
      speedLimit: _currentSpeedLimit,
      congestionLevel: _currentCongestion,
      shields: currentShields,
      isDeadReckoning: _isDeadReckoning,
      hasTolls: _currentRoute?.hasTolls ?? false,
      tollCost: _currentRoute?.tollCost,
      hasUpcomingExit: hasExit,
      upcomingExitName: exitName,
      exitRef: exitRef,
    );
  }

  bool get isDeadReckoning => _isDeadReckoning;
  double? get currentSpeedLimit => _currentSpeedLimit;
  String? get currentCongestion => _currentCongestion;

  RouteStep? _getPreviousStep() {
    if (_currentRoute == null || _currentStepIndex == 0) return null;
    final legs = _currentRoute!.legs;
    if (_currentLegIndex >= legs.length) return null;
    final steps = legs[_currentLegIndex].steps;
    if (_currentStepIndex - 1 < 0) return null;
    return steps[_currentStepIndex - 1];
  }

  RouteStep? _getCurrentStep() {
    if (_currentRoute == null) return null;
    final legs = _currentRoute!.legs;
    if (_currentLegIndex >= legs.length) return null;
    final steps = legs[_currentLegIndex].steps;
    if (_currentStepIndex >= steps.length) return null;
    return steps[_currentStepIndex];
  }

  RouteStep? _getNextStep() {
    if (_currentRoute == null) return null;
    final legs = _currentRoute!.legs;
    if (_currentLegIndex >= legs.length) return null;
    final steps = legs[_currentLegIndex].steps;
    if (_currentStepIndex + 1 >= steps.length) {
      if (_currentLegIndex + 1 < legs.length) {
        final nextLegSteps = legs[_currentLegIndex + 1].steps;
        if (nextLegSteps.isNotEmpty) return nextLegSteps[0];
      }
      return null;
    }
    return steps[_currentStepIndex + 1];
  }

  RouteStep? _getStepAfterNext() {
    if (_currentRoute == null) return null;
    final legs = _currentRoute!.legs;
    if (_currentLegIndex >= legs.length) return null;
    final steps = legs[_currentLegIndex].steps;
    if (_currentStepIndex + 2 >= steps.length) {
      // Intentar del siguiente leg
      if (_currentLegIndex + 1 < legs.length) {
        final nextLegSteps = legs[_currentLegIndex + 1].steps;
        final offset = (_currentStepIndex + 2) - steps.length;
        if (offset < nextLegSteps.length) return nextLegSteps[offset];
      }
      return null;
    }
    return steps[_currentStepIndex + 2];
  }

  void _updateDistanceToNextManeuver(double lat, double lng) {
    final currentStep = _getCurrentStep();
    if (currentStep == null) return;

    // Obtener ubicación del maneuver actual
    final maneuverLoc = currentStep.maneuver.location;
    if (maneuverLoc != null && maneuverLoc.length >= 2) {
      // Distancia directa al punto del maneuver
      _distanceToNextManeuver = _haversine(lat, lng, maneuverLoc[1], maneuverLoc[0]);
    } else if (currentStep.coordinates.isNotEmpty) {
      // Fallback: última coordenada del step
      final lastCoord = currentStep.coordinates.last;
      _distanceToNextManeuver = _haversine(lat, lng, lastCoord[1], lastCoord[0]);
    } else {
      // Usar distancia del step
      _distanceToNextManeuver = currentStep.distance;
    }
  }

  void _checkManeuverProgress(double lat, double lng) {
    if (_currentRoute == null) return;

    final legs = _currentRoute!.legs;
    if (_currentLegIndex >= legs.length) return;
    final steps = legs[_currentLegIndex].steps;
    if (_currentStepIndex >= steps.length) return;

    // Distancia al maneuver actual
    final currentStep = steps[_currentStepIndex];
    final currentLoc = currentStep.maneuver.location;
    double distToCurrent = double.infinity;

    if (currentLoc != null && currentLoc.length >= 2) {
      distToCurrent = _haversine(lat, lng, currentLoc[1], currentLoc[0]);
    }

    // Detectar si estamos acercándonos o alejándonos del maneuver
    final isApproaching = distToCurrent < _lastDistToManeuver;

    // CONDICIÓN 1: Pasamos el maneuver (estábamos cerca y ahora nos alejamos)
    if (_wasApproaching && !isApproaching && _lastDistToManeuver < 40) {
      // Acabamos de pasar el maneuver - avanzar al siguiente
      if (_currentStepIndex + 1 < steps.length) {
        _currentStepIndex++;
        _resetVoiceAlerts();
        _lastDistToManeuver = double.infinity;
        _wasApproaching = false;
        return;
      }
    }

    // CONDICIÓN 2: Estamos muy cerca del maneuver (< 15m) - avanzar inmediatamente
    if (distToCurrent < 15 && _currentStepIndex + 1 < steps.length) {
      _currentStepIndex++;
      _resetVoiceAlerts();
      _lastDistToManeuver = double.infinity;
      _wasApproaching = false;
      return;
    }

    // CONDICIÓN 3: Buscar si hay un step más cercano hacia adelante
    if (_currentStepIndex + 1 < steps.length) {
      final nextStep = steps[_currentStepIndex + 1];
      final nextLoc = nextStep.maneuver.location;
      if (nextLoc != null && nextLoc.length >= 2) {
        final distToNext = _haversine(lat, lng, nextLoc[1], nextLoc[0]);
        // Si estamos más cerca del siguiente que del actual, avanzar
        if (distToNext < distToCurrent) {
          _currentStepIndex++;
          _resetVoiceAlerts();
          _lastDistToManeuver = double.infinity;
          _wasApproaching = false;
          return;
        }
      }
    }

    // Guardar estado para la próxima iteración
    _lastDistToManeuver = distToCurrent;
    _wasApproaching = isApproaching;
  }

  void _resetVoiceAlerts() {
    _alerted500m = false;
    _alerted200m = false;
    _alerted100m = false;
    _alerted50m = false;
  }

  void _advanceToNextStep() {
    if (_currentRoute == null) return;

    final legs = _currentRoute!.legs;
    if (_currentLegIndex >= legs.length) return;

    final steps = legs[_currentLegIndex].steps;

    if (_currentStepIndex + 1 < steps.length) {
      _currentStepIndex++;
    } else if (_currentLegIndex + 1 < legs.length) {
      _currentLegIndex++;
      _currentStepIndex = 0;
    }

    _alerted500m = false;
    _alerted200m = false;
    _alerted100m = false;
    _alerted50m = false;

    _updateDistanceToNextManeuver(_lastLat, _lastLng);
    _notifyStateChanged();
  }

  void _updateRemainingDistance(double lat, double lng) {
    if (_currentRoute == null) return;

    final legs = _currentRoute!.legs;
    if (_currentLegIndex >= legs.length) return;

    final coords = _currentRoute!.coordinates;
    if (coords.isEmpty) return;

    int closestIdx = 0;
    double minDist = double.infinity;
    for (int i = 0; i < coords.length; i++) {
      final dist = _haversine(lat, lng, coords[i][1], coords[i][0]);
      if (dist < minDist) {
        minDist = dist;
        closestIdx = i;
      }
    }

    double remainingDistance = 0;
    for (int i = closestIdx; i < coords.length - 1; i++) {
      remainingDistance += _haversine(
        coords[i][1], coords[i][0],
        coords[i + 1][1], coords[i + 1][0],
      );
    }

    final totalDistance = _currentRoute!.distance;
    final totalDuration = _currentRoute!.duration;

    double remainingDuration;
    if (totalDistance > 0) {
      final proportion = remainingDistance / totalDistance;
      remainingDuration = totalDuration * proportion;
    } else {
      remainingDuration = 0;
    }

    double stepBasedDistance = _distanceToNextManeuver;
    double stepBasedDuration = 0;

    final currentStep = _getCurrentStep();
    if (currentStep != null && currentStep.distance > 0) {
      final stepProgress = 1 - (_distanceToNextManeuver / currentStep.distance).clamp(0.0, 1.0);
      stepBasedDuration = currentStep.duration * (1 - stepProgress);
    }

    final currentLegSteps = legs[_currentLegIndex].steps;
    for (int i = _currentStepIndex + 1; i < currentLegSteps.length; i++) {
      stepBasedDistance += currentLegSteps[i].distance;
      stepBasedDuration += currentLegSteps[i].duration;
    }

    for (int l = _currentLegIndex + 1; l < legs.length; l++) {
      stepBasedDistance += legs[l].distance;
      stepBasedDuration += legs[l].duration;
    }

    _distanceRemaining = (remainingDistance + stepBasedDistance) / 2;
    _durationRemaining = (remainingDuration + stepBasedDuration) / 2;
  }

  double _getDistanceToRoute(double lat, double lng) {
    if (_currentRoute == null) return double.infinity;

    final coords = _currentRoute!.coordinates;
    if (coords.isEmpty) return double.infinity;

    double minDist = double.infinity;

    for (final coord in coords) {
      final dist = _haversine(lat, lng, coord[1], coord[0]);
      if (dist < minDist) minDist = dist;
    }

    return minDist;
  }

  void _handleOffRoute(double lat, double lng, {double? userBearing}) async {
    if (_isRerouting || _currentRoute == null) return;

    final now = DateTime.now();
    if (_lastRerouteTime != null) {
      final elapsed = now.difference(_lastRerouteTime!).inMilliseconds;
      if (elapsed < _rerouteCooldownMs) {
        return;
      }
    }

    _isRerouting = true;
    _lastRerouteTime = now;

    final dest = _currentRoute!.coordinates.last;

    // Guardar distancia actual al destino para comparar
    final currentDistToDest = _haversine(lat, lng, dest[1], dest[0]);

    final newRoute = await _directionsService.getRoute(
      originLat: lat,
      originLng: lng,
      destLat: dest[1],
      destLng: dest[0],
      bearing: userBearing,
      approaches: 'unrestricted;curb',
      continueStraight: true,
    );

    if (newRoute != null) {
      // Calcular qué tan lejos estamos de la ruta actual
      final distToCurrentRoute = _getDistanceToRoute(lat, lng);

      // Si estamos MUY lejos de la ruta (> 500m), aceptar la nueva ruta sin validación
      // porque la ruta actual ya no es válida
      bool shouldAcceptRoute = distToCurrentRoute > 500;

      if (!shouldAcceptRoute) {
        // Solo validar si estamos relativamente cerca de la ruta actual
        final maxReasonableDistance = currentDistToDest * 2.5;

        if (newRoute.distance > maxReasonableDistance && currentDistToDest > 500) {
          // Ruta parece estúpida - rechazar
          _isRerouting = false;
          return;
        }

        if (newRoute.distance > _distanceRemaining * 1.5 && _distanceRemaining > 1000) {
          // La nueva ruta es 50% más larga - rechazar
          _isRerouting = false;
          return;
        }
      }

      // Aceptar la nueva ruta
      _currentRoute = newRoute;
      _currentStepIndex = 0;
      _currentLegIndex = 0;

      _updateDistanceToNextManeuver(lat, lng);
      _updateRemainingDistance(lat, lng);

      _lastSpokenInstruction = '';

      onReroute?.call(newRoute);
    }

    _isRerouting = false;
    _notifyStateChanged();
  }

  void _speakIfNotRecent(String instruction) {
    final now = DateTime.now();

    if (_lastSpokenInstruction == instruction && _lastVoiceTime != null) {
      final elapsed = now.difference(_lastVoiceTime!).inMilliseconds;
      if (elapsed < _voiceCooldownMs) {
        return;
      }
    }

    _lastSpokenInstruction = instruction;
    _lastVoiceTime = now;
    onVoiceInstruction?.call(instruction);
  }

  bool _checkArrival(double lat, double lng) {
    if (_currentRoute == null) return false;

    final dest = _currentRoute!.coordinates.last;
    final distToDest = _haversine(lat, lng, dest[1], dest[0]);

    return distToDest < arrivalThreshold;
  }

  void _handleArrival() {
    _speakIfNotRecent('Has llegado a tu destino');
    onArrival?.call();
    stopNavigation();
  }

  void _checkVoiceInstruction() {
    final currentStep = _getCurrentStep();
    if (currentStep == null) return;

    final instruction = currentStep.instruction ??
        _buildInstruction(currentStep.maneuver);

    if (_distanceToNextManeuver <= 500 && !_alerted500m) {
      _alerted500m = true;
      _speakIfNotRecent('En 500 metros, $instruction');
    }

    if (_distanceToNextManeuver <= 200 && !_alerted200m) {
      _alerted200m = true;
      _speakIfNotRecent('En 200 metros, $instruction');
    }

    if (_distanceToNextManeuver <= 100 && !_alerted100m) {
      _alerted100m = true;
      _speakIfNotRecent(instruction);
    }

    if (_distanceToNextManeuver <= 50 && !_alerted50m) {
      _alerted50m = true;
      _speakIfNotRecent('Ahora, $instruction');
    }
  }

  void _checkExitGuidance() {
    final currentStep = _getCurrentStep();
    final nextStep = _getNextStep();

    if (currentStep == null) return;

    final isCurrentExit = _isExitManeuver(currentStep.maneuver.type);
    final isNextExit = nextStep != null && _isExitManeuver(nextStep.maneuver.type);

    String? exitName;
    double distanceToExit = 0;

    if (isCurrentExit) {
      exitName = currentStep.name ?? 'la salida';
      distanceToExit = _distanceToNextManeuver;
    } else if (isNextExit) {
      exitName = nextStep.name ?? 'la salida';
      distanceToExit = _distanceToNextManeuver + nextStep.distance;
    }

    if (exitName == null) {
      if (_pendingExitName != null) {
        _exitAlerted1km = false;
        _exitAlerted500m = false;
        _exitAlerted300m = false;
        _pendingExitName = null;
      }
      return;
    }

    if (_pendingExitName != exitName) {
      _exitAlerted1km = false;
      _exitAlerted500m = false;
      _exitAlerted300m = false;
      _pendingExitName = exitName;
    }

    if (distanceToExit <= 1000 && distanceToExit > 500 && !_exitAlerted1km) {
      _exitAlerted1km = true;
      onExitApproaching?.call(exitName, distanceToExit);
      _speakIfNotRecent('En 1 kilómetro, toma $exitName');
    }

    if (distanceToExit <= 500 && distanceToExit > 300 && !_exitAlerted500m) {
      _exitAlerted500m = true;
      onExitApproaching?.call(exitName, distanceToExit);
      _speakIfNotRecent('En 500 metros, prepárate para tomar $exitName');
    }

    if (distanceToExit <= 300 && distanceToExit > 100 && !_exitAlerted300m) {
      _exitAlerted300m = true;
      onExitApproaching?.call(exitName, distanceToExit);
      _speakIfNotRecent('Mantente a la derecha para $exitName');
    }
  }

  bool _isExitManeuver(String type) {
    return type == 'off ramp' ||
           type == 'exit' ||
           type == 'exit roundabout' ||
           type == 'exit rotary';
  }

  void _checkParkingNearDestination(double lat, double lng) {
    if (_parkingAlertSent || _currentRoute == null) return;

    if (_distanceRemaining <= _parkingAlertDistance && _distanceRemaining > 100) {
      _parkingAlertSent = true;

      final dest = _currentRoute!.coordinates.last;
      onNearDestinationForParking?.call(dest[1], dest[0]);
    }
  }

  void _checkAirportAssistance() {
    if (!_isAirportDestination || _currentRoute == null) return;

    if (_distanceRemaining <= 2000 && _distanceRemaining > 1500 && !_airportAlert2km) {
      _airportAlert2km = true;
      final instruction = 'A 2 kilómetros del aeropuerto. Prepárate para seguir señales de Llegadas.';
      _speakIfNotRecent(instruction);
      onAirportInstruction?.call(instruction);
    }

    if (_distanceRemaining <= 500 && _distanceRemaining > 300 && !_airportAlert500m) {
      _airportAlert500m = true;
      final instruction = 'Mantente en el carril derecho para zona de Llegadas.';
      _speakIfNotRecent(instruction);
      onAirportInstruction?.call(instruction);
    }
  }

  String _buildInstruction(StepManeuver maneuver) {
    final type = maneuver.type;
    final modifier = maneuver.modifier;

    switch (type) {
      case 'turn':
        switch (modifier) {
          case 'left': return 'gira a la izquierda';
          case 'right': return 'gira a la derecha';
          case 'slight left': return 'gira ligeramente a la izquierda';
          case 'slight right': return 'gira ligeramente a la derecha';
          case 'sharp left': return 'gira bruscamente a la izquierda';
          case 'sharp right': return 'gira bruscamente a la derecha';
          case 'uturn': return 'da la vuelta';
          default: return 'continúa recto';
        }
      case 'depart':
        final bearing = maneuver.bearingAfter;
        if (bearing != null) {
          final direction = _bearingToDirection(bearing);
          return 'dirígete hacia el $direction';
        }
        return 'continúa recto';
      case 'arrive':
        return 'has llegado a tu destino';
      case 'merge':
        return 'incorpórate';
      case 'fork':
        return modifier == 'left' ? 'toma el desvío a la izquierda' : 'toma el desvío a la derecha';
      case 'roundabout':
        final exit = maneuver.exit;
        return exit != null ? 'en la rotonda, toma la salida $exit' : 'entra en la rotonda';
      case 'off ramp':
        return 'toma la salida';
      case 'on ramp':
        return 'toma la entrada';
      case 'new name':
      case 'continue':
        return 'continúa recto';
      default:
        return 'continúa recto';
    }
  }

  String _bearingToDirection(double bearing) {
    if (bearing >= 337.5 || bearing < 22.5) return 'norte';
    if (bearing >= 22.5 && bearing < 67.5) return 'noreste';
    if (bearing >= 67.5 && bearing < 112.5) return 'este';
    if (bearing >= 112.5 && bearing < 157.5) return 'sureste';
    if (bearing >= 157.5 && bearing < 202.5) return 'sur';
    if (bearing >= 202.5 && bearing < 247.5) return 'suroeste';
    if (bearing >= 247.5 && bearing < 292.5) return 'oeste';
    if (bearing >= 292.5 && bearing < 337.5) return 'noroeste';
    return 'norte';
  }

  void _notifyStateChanged() {
    onStateChanged?.call(currentState);
  }

  double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) *
        math.sin(dLng / 2) * math.sin(dLng / 2);
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double? _getRouteBearing(double lat, double lng) {
    if (_currentRoute == null) return null;

    final coords = _currentRoute!.coordinates;
    if (coords.length < 2) return null;

    double minDist = double.infinity;
    int closestIdx = 0;

    for (int i = 0; i < coords.length; i++) {
      final dist = _haversine(lat, lng, coords[i][1], coords[i][0]);
      if (dist < minDist) {
        minDist = dist;
        closestIdx = i;
      }
    }

    if (closestIdx >= coords.length - 1) {
      closestIdx = coords.length - 2;
    }

    final from = coords[closestIdx];
    final to = coords[closestIdx + 1];

    return _calculateBearing(from[1], from[0], to[1], to[0]);
  }

  double _calculateBearing(double lat1, double lng1, double lat2, double lng2) {
    final dLng = (lng2 - lng1) * math.pi / 180;
    final lat1Rad = lat1 * math.pi / 180;
    final lat2Rad = lat2 * math.pi / 180;

    final x = math.sin(dLng) * math.cos(lat2Rad);
    final y = math.cos(lat1Rad) * math.sin(lat2Rad) -
        math.sin(lat1Rad) * math.cos(lat2Rad) * math.cos(dLng);

    var bearing = math.atan2(x, y) * 180 / math.pi;
    return (bearing + 360) % 360;
  }

  double _getBearingDifference(double bearing1, double bearing2) {
    var diff = (bearing1 - bearing2).abs();
    if (diff > 180) diff = 360 - diff;
    return diff;
  }

  bool get isNavigating => _isNavigating;
  DirectionsRoute? get currentRoute => _currentRoute;
}

/// Estado de navegación
class NavigationState {
  final bool isNavigating;
  final DirectionsRoute? currentRoute;
  final int currentStepIndex;
  final RouteStep? currentStep;
  final RouteStep? nextStep;
  final double distanceToNextManeuver;
  final double distanceRemaining;
  final double durationRemaining;
  final String currentInstruction;
  final String? nextInstruction;
  final String maneuverType;
  final String? maneuverModifier;
  final String streetName;
  final List<LaneInfo>? lanes;
  final double? speedLimit;
  final String? congestionLevel;
  final List<BannerComponent>? shields;
  final bool isDeadReckoning;
  final bool hasTolls;
  final double? tollCost;
  final bool hasUpcomingExit;
  final String? upcomingExitName;
  final String? exitRef;  // Número de salida/ruta (ej: "51A", "AZ 202")

  NavigationState({
    required this.isNavigating,
    this.currentRoute,
    this.currentStepIndex = 0,
    this.currentStep,
    this.nextStep,
    this.distanceToNextManeuver = 0,
    this.distanceRemaining = 0,
    this.durationRemaining = 0,
    this.currentInstruction = '',
    this.nextInstruction,
    this.maneuverType = 'straight',
    this.maneuverModifier,
    this.streetName = '',
    this.lanes,
    this.speedLimit,
    this.congestionLevel,
    this.shields,
    this.isDeadReckoning = false,
    this.hasTolls = false,
    this.tollCost,
    this.hasUpcomingExit = false,
    this.upcomingExitName,
    this.exitRef,
  });

  factory NavigationState.idle() {
    return NavigationState(isNavigating: false);
  }

  bool get hasLanes => lanes != null && lanes!.isNotEmpty;
  bool get hasShields => shields != null && shields!.isNotEmpty;

  String get formattedDistanceToManeuver {
    if (distanceToNextManeuver < 1000) {
      return '${distanceToNextManeuver.round()} m';
    } else {
      return '${(distanceToNextManeuver / 1000).toStringAsFixed(1)} km';
    }
  }

  String get formattedDistanceRemaining {
    if (distanceRemaining < 1000) {
      return '${distanceRemaining.round()} m';
    } else {
      return '${(distanceRemaining / 1000).toStringAsFixed(1)} km';
    }
  }

  String get formattedDurationRemaining {
    final mins = (durationRemaining / 60).round();
    if (mins < 60) {
      return '$mins min';
    } else {
      final hours = mins ~/ 60;
      final remainMins = mins % 60;
      return remainMins > 0 ? '${hours}h ${remainMins}min' : '${hours}h';
    }
  }

  String get formattedETA {
    final eta = DateTime.now().add(Duration(seconds: durationRemaining.round()));
    final hour = eta.hour;
    final minute = eta.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$hour12:$minute $period';
  }
}
