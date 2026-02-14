// ============================================================================
// TORO DRIVER - NAVIGATION MAP SCREEN
// Mapa de navegación completo conectado con RideProvider
// ============================================================================

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/ride_provider.dart';
import '../providers/driver_provider.dart';
import '../models/ride_model.dart';
import '../services/geocoding_service.dart';
import '../services/directions_service.dart';
import '../services/navigation_service.dart';
import '../services/poi_service.dart';
// Map matching removido - usamos los steps de la ruta para nombre de calle (gratis)
import '../widgets/navigation_ui.dart';
import '../widgets/ride_chat_popup.dart';
import 'report_ride_screen.dart';

const String _mapboxToken = 'pk.eyJ1IjoibWFydGluZXpjMjAxNyIsImEiOiJjbWtocWtoZHIwbW1iM2dvdXZ3bmp0ZjBiIn0.MjYgv6DuvLTkrBVbrhtFbg';

class NavigationMapScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const NavigationMapScreen({super.key, this.onBack});

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
  PointAnnotationManager? _destinationMarkerManager;
  PointAnnotationManager? _riderMarkerManager;
  String? _lastMarkerRideId; // Track which ride's marker is shown
  String? _lastRiderMarkerId; // Track rider marker state

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
  double _currentPitch = 0.0;  // 0 = 2D plano, 45 = 3D navegación
  DateTime? _lastZoomUpdate;  // Throttle para adaptive zoom

  // Speed-based pitch: < 10 km/h = flat (0°), >= 10 km/h = navigation (45°)
  static const double _speedThresholdForPitch = 2.78; // 10 km/h in m/s

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

  // Wait timer at pickup
  Timer? _waitTimer;
  int _waitSeconds = 0;

  // Route loading state (prevents panel flash during route fetch)
  bool _isLoadingRoute = false;

  // GPS update timer to Supabase (every 10s during active ride)
  Timer? _gpsUpdateTimer;
  DateTime? _lastGpsSent;

  // Periodic arrival check timer (covers case when GPS stream stops due to distanceFilter)
  Timer? _arrivalCheckTimer;

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
    _destinationMarkerManager = await map.annotations.createPointAnnotationManager();
    _riderMarkerManager = await map.annotations.createPointAnnotationManager();

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
      // CRITICAL: Still check arrival even during deadband filtering
      // When driver is parking at pickup, small movements get filtered out
      // but we must still detect arrival within 30m threshold
      if (_navigationService.isNavigating) {
        _navigationService.updateLocation(
          pos.latitude, pos.longitude, pos.speed, pos.heading,
        );
      }
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

    // Speed-based pitch: < 10 km/h = flat (0°), >= 10 km/h = navigation (45°)
    final newPitch = speed >= _speedThresholdForPitch ? 45.0 : 0.0;
    if (newPitch != _currentPitch) {
      debugPrint('🎥 PITCH: ${_currentPitch.toStringAsFixed(0)}° → ${newPitch.toStringAsFixed(0)}° (${(speed*3.6).toStringAsFixed(1)} km/h)');
      _currentPitch = newPitch;
      // Trigger rebuild to update FollowPuckViewportState pitch
      if (mounted) setState(() {});
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
        _stopGpsUpdatesToSupabase();
        _waitTimer?.cancel();
        _waitSeconds = 0;
      }
      return;
    }

    // Start GPS updates to Supabase when we have an active ride
    if (_gpsUpdateTimer == null) {
      _startGpsUpdatesToSupabase();
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
    _updateDestinationMarker(ride);
    _startNavigationTo(targetLat, targetLng, targetName, targetType);
  }

  Future<void> _startNavigationTo(double lat, double lng, String name, String targetType) async {
    // Reset street tracking for new navigation
    _lastStepIndex = -1;

    setState(() => _isLoadingRoute = true);

    final success = await _navigationService.startNavigation(
      originLat: _currentLat,
      originLng: _currentLng,
      destLat: lat,
      destLng: lng,
      bearing: _currentBearing > 0 ? _currentBearing : null,
    );

    if (mounted) setState(() => _isLoadingRoute = false);

    if (success && _navigationService.currentRoute != null) {
      _drawRoute(_navigationService.currentRoute!);

      // Start periodic arrival check for pickup (covers stationary GPS gaps)
      _arrivalCheckTimer?.cancel();
      if (targetType == 'pickup') {
        final pickupLat = lat;
        final pickupLng = lng;
        _arrivalCheckTimer = Timer.periodic(const Duration(seconds: 3), (_) {
          if (!mounted || _currentTargetType != 'pickup') {
            _arrivalCheckTimer?.cancel();
            _arrivalCheckTimer = null;
            return;
          }
          final dist = _quickDistance(_currentLat, _currentLng, pickupLat, pickupLng);
          if (dist < 50) {
            // Within 50m - force NavigationService check with current position
            if (_navigationService.isNavigating) {
              _navigationService.updateLocation(
                _currentLat, _currentLng, _currentSpeed, _currentBearing,
              );
            }
          }
        });
      }

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
    if (!mounted) return;

    // Stop periodic arrival check
    _arrivalCheckTimer?.cancel();
    _arrivalCheckTimer = null;

    if (_currentTargetType == 'pickup') {
      // Auto-trigger arrived at pickup
      _handleArriveAtPickup();
    } else {
      // At dropoff - show snackbar, driver manually finalizes
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Has llegado al destino')),
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
  // RIDE LIFECYCLE HANDLERS
  // ============================================================================

  Future<void> _handleArriveAtPickup() async {
    final rideProvider = context.read<RideProvider>();
    final success = await rideProvider.arriveAtPickup();
    if (success) {
      // Start wait timer
      _waitSeconds = 0;
      _waitTimer?.cancel();
      _waitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() => _waitSeconds++);
        } else {
          timer.cancel();
        }
      });
      if (!_isMuted) {
        _tts.speak('Has llegado al punto de recogida. Esperando al pasajero.');
      }
    }
  }

  Future<void> _handleStartRide() async {
    final rideProvider = context.read<RideProvider>();
    final success = await rideProvider.startRide();
    if (success) {
      _waitTimer?.cancel();
      _waitSeconds = 0;
      if (!_isMuted) {
        _tts.speak('Viaje iniciado. Navegando al destino.');
      }
    }
  }

  Future<void> _handleCompleteRide() async {
    final rideProvider = context.read<RideProvider>();
    final driverProvider = context.read<DriverProvider>();
    final driverId = driverProvider.driver?.id;
    if (driverId == null) return;

    // Cash payment confirmation
    if (rideProvider.isCashPayment) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('Confirmar pago en efectivo',
              style: TextStyle(color: Colors.white)),
          content: Text(
            '¿Recibiste \$${rideProvider.cashAmountToCollect.toStringAsFixed(2)} en efectivo?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('NO'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('SÍ, RECIBIDO'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      final success = await rideProvider.completeRideWithCashConfirmation(driverId: driverId);
      if (!success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(rideProvider.error ?? 'Error al completar viaje'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return; // Don't navigate back if completion failed
      }
    } else {
      final success = await rideProvider.completeRide(driverId: driverId);
      if (!success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(rideProvider.error ?? 'Error al completar viaje'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return; // Don't navigate back if completion failed
      }
    }

    _waitTimer?.cancel();
    _waitSeconds = 0;
    _clearRoute();

    // Show earnings popup before navigating back
    if (mounted) {
      final completedRide = rideProvider.lastCompletedRide;
      if (completedRide != null) {
        await _showEarningsPopup(completedRide);
        rideProvider.clearLastCompletedRide();
      }
    }

    if (widget.onBack != null) widget.onBack!();
  }

  /// Show earnings breakdown popup after ride completion
  Future<void> _showEarningsPopup(RideModel ride) async {
    final baseEarnings = ride.driverEarnings - ride.tip;
    final hasTip = ride.tip > 0;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.green.shade700, Colors.green.shade500],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 16),
              const Text(
                'Viaje completado',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),

              // Total earnings (big number)
              Text(
                '\$${ride.driverEarnings.toStringAsFixed(2)}',
                style: TextStyle(
                  color: Colors.green.shade400,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                'Tus ganancias',
                style: TextStyle(color: Colors.white60, fontSize: 14),
              ),
              const SizedBox(height: 20),

              // Breakdown
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(13),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _earningsRow(
                      'Tarifa base',
                      '\$${ride.fare.toStringAsFixed(2)}',
                      Icons.directions_car,
                    ),
                    const Divider(color: Colors.white24, height: 16),
                    _earningsRow(
                      'Tu parte',
                      '\$${baseEarnings.toStringAsFixed(2)}',
                      Icons.account_balance_wallet,
                      highlight: true,
                    ),
                    if (hasTip) ...[
                      const Divider(color: Colors.white24, height: 16),
                      _earningsRow(
                        'Propina',
                        '+\$${ride.tip.toStringAsFixed(2)}',
                        Icons.star,
                        color: Colors.amber,
                      ),
                    ],
                    const Divider(color: Colors.white24, height: 16),
                    _earningsRow(
                      'Comisión Toro',
                      '-\$${ride.platformFee.toStringAsFixed(2)}',
                      Icons.business,
                      color: Colors.white38,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Payment method
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    ride.paymentMethod == PaymentMethod.cash
                        ? Icons.money
                        : Icons.credit_card,
                    color: Colors.white54,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    paymentMethodDisplayText(ride.paymentMethod, spanish: true),
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Close button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Siguiente viaje',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build a row for the earnings breakdown
  Widget _earningsRow(String label, String amount, IconData icon, {
    bool highlight = false,
    Color? color,
  }) {
    return Row(
      children: [
        Icon(icon, color: color ?? Colors.white60, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: highlight ? Colors.white : Colors.white70,
              fontSize: 14,
              fontWeight: highlight ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
        Text(
          amount,
          style: TextStyle(
            color: color ?? (highlight ? Colors.green.shade400 : Colors.white),
            fontSize: 15,
            fontWeight: highlight ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Future<void> _handleCancelRide() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('¿Cancelar viaje?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'El viaje será liberado para que otro conductor lo tome.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('NO'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('SÍ, CANCELAR'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final rideProvider = context.read<RideProvider>();
      await rideProvider.cancelRide('driver_cancelled');
      _waitTimer?.cancel();
      _waitSeconds = 0;
      _clearRoute();
      if (widget.onBack != null) widget.onBack!();
    }
  }

  Future<void> _launchExternalNav() async {
    final rideProvider = context.read<RideProvider>();
    final ride = rideProvider.activeRide;
    if (ride == null) return;

    double targetLat, targetLng;
    if (ride.status == RideStatus.accepted || ride.status == RideStatus.pending) {
      targetLat = ride.pickupLocation.latitude;
      targetLng = ride.pickupLocation.longitude;
    } else {
      targetLat = ride.dropoffLocation.latitude;
      targetLng = ride.dropoffLocation.longitude;
    }

    // Try Google Maps first, then Waze, then generic geo
    final googleMapsUrl = Uri.parse(
        'google.navigation:q=$targetLat,$targetLng&mode=d');
    final wazeUrl = Uri.parse(
        'https://waze.com/ul?ll=$targetLat,$targetLng&navigate=yes');
    final genericUrl = Uri.parse(
        'geo:$targetLat,$targetLng?q=$targetLat,$targetLng');

    try {
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl);
      } else if (await canLaunchUrl(wazeUrl)) {
        await launchUrl(wazeUrl, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(genericUrl);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir navegación externa')),
        );
      }
    }
  }

  // ============================================================================
  // GPS TO SUPABASE
  // ============================================================================

  void _startGpsUpdatesToSupabase() {
    _gpsUpdateTimer?.cancel();
    _gpsUpdateTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _sendGpsToSupabase();
    });
  }

  void _stopGpsUpdatesToSupabase() {
    _gpsUpdateTimer?.cancel();
    _gpsUpdateTimer = null;
  }

  Future<void> _sendGpsToSupabase() async {
    if (!mounted) return;
    final rideProvider = context.read<RideProvider>();
    final ride = rideProvider.activeRide;
    if (ride == null) return;

    // Throttle: only send every 10 seconds
    final now = DateTime.now();
    if (_lastGpsSent != null && now.difference(_lastGpsSent!).inSeconds < 10) {
      return;
    }
    _lastGpsSent = now;

    try {
      // Update driver location in the delivery record
      final driverProvider = context.read<DriverProvider>();
      final driverId = driverProvider.driver?.id;
      if (driverId == null) return;

      await Supabase.instance.client
          .from('deliveries')
          .update({
            'driver_lat': _currentLat,
            'driver_lng': _currentLng,
            'driver_bearing': _currentBearing,
            'driver_speed': _currentSpeed,
            'driver_location_updated_at': now.toIso8601String(),
          })
          .eq('id', ride.id)
          .eq('driver_id', driverId);

      debugPrint('📡 GPS sent to Supabase: $_currentLat, $_currentLng');
    } catch (e) {
      debugPrint('📡 GPS send error: $e');
    }
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
    await _destinationMarkerManager?.deleteAll();
    await _riderMarkerManager?.deleteAll();
    _lastMarkerRideId = null;
    _lastRiderMarkerId = null;
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

  /// Muestra pin de destino (pickup o dropoff) en el mapa del driver
  Future<void> _updateDestinationMarker(RideModel ride) async {
    if (_destinationMarkerManager == null) return;

    final isPickup = ride.status == RideStatus.accepted ||
        ride.status == RideStatus.pending;
    final isDropoff = ride.status == RideStatus.inProgress ||
        ride.status == RideStatus.arrivedAtPickup;

    if (!isPickup && !isDropoff) {
      await _destinationMarkerManager!.deleteAll();
      _lastMarkerRideId = null;
      return;
    }

    final targetType = isPickup ? 'pickup' : 'dropoff';
    final markerId = '${ride.id}_$targetType';

    // No recrear si ya es el mismo marker
    if (_lastMarkerRideId == markerId) return;
    _lastMarkerRideId = markerId;

    await _destinationMarkerManager!.deleteAll();

    final lat = isPickup
        ? ride.pickupLocation.latitude
        : ride.dropoffLocation.latitude;
    final lng = isPickup
        ? ride.pickupLocation.longitude
        : ride.dropoffLocation.longitude;
    // Pin icon: 📍 for pickup (cyan), 🏁 for destination (red)
    final icon = isPickup ? '📍' : '🏁';
    final color = isPickup ? 0xFF00BCD4 : 0xFFFF1744; // cyan / rojo

    await _destinationMarkerManager!.create(PointAnnotationOptions(
      geometry: Point(coordinates: Position(lng, lat)),
      textField: icon,
      textSize: 32,
      textColor: color,
      textHaloColor: 0xFFFFFFFF,
      textHaloWidth: 3,
      textOffset: [0.0, 0.0],
    ));
  }

  /// Muestra el marcador del rider en tiempo real (solo durante pickup)
  /// El rider envía su ubicación GPS y se muestra con un pin morado
  Future<void> _updateRiderMarker(RideModel? ride) async {
    if (_riderMarkerManager == null) return;

    // Solo mostrar durante pickup (accepted o pending)
    // NO mostrar cuando:
    // - No hay ride
    // - Ya pasó pickup (inProgress, arrivedAtPickup, completed, cancelled)
    // - No hay ubicación del rider
    // - Es booking para otra persona (isBookingForSomeoneElse)
    final isGoingToPickup = ride != null &&
        (ride.status == RideStatus.accepted || ride.status == RideStatus.pending);

    if (!isGoingToPickup || !ride.hasRiderGps) {
      // Limpiar marcador si no aplica
      if (_lastRiderMarkerId != null) {
        await _riderMarkerManager!.deleteAll();
        _lastRiderMarkerId = null;
        debugPrint('🧑 RIDER_MARKER: Cleared (status=${ride?.status}, hasGps=${ride?.hasRiderGps})');
      }
      return;
    }

    // Crear ID único basado en ubicación para evitar recrear innecesariamente
    final markerId = '${ride.id}_rider_${ride.riderGpsLat!.toStringAsFixed(5)}_${ride.riderGpsLng!.toStringAsFixed(5)}';

    // No recrear si es la misma ubicación
    if (_lastRiderMarkerId == markerId) return;
    _lastRiderMarkerId = markerId;

    await _riderMarkerManager!.deleteAll();

    // Marcador VERDE brillante con persona - muy visible
    // Distinct from driver (blue car) and pickup pin (red/cyan)
    await _riderMarkerManager!.create(PointAnnotationOptions(
      geometry: Point(coordinates: Position(ride.riderGpsLng!, ride.riderGpsLat!)),
      textField: '●',  // Large solid circle
      textSize: 36,
      textColor: 0xFF4CAF50,  // Green (same as rider app)
      textHaloColor: 0xFFFFFFFF,
      textHaloWidth: 4,
      textOffset: [0.0, 0.0],
    ));

    // Add person label above the circle
    await _riderMarkerManager!.create(PointAnnotationOptions(
      geometry: Point(coordinates: Position(ride.riderGpsLng!, ride.riderGpsLat!)),
      textField: '🧑',  // Person emoji
      textSize: 18,
      textOffset: [0.0, 0.0],
    ));

    debugPrint('🧑 RIDER_MARKER: Updated at ${ride.riderGpsLat!.toStringAsFixed(5)}, ${ride.riderGpsLng!.toStringAsFixed(5)}');
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
    _waitTimer?.cancel();
    _gpsUpdateTimer?.cancel();
    _arrivalCheckTimer?.cancel();
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
        // Defer to avoid setState during build
        if (_isMapReady) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _checkAndStartNavigation(ride);
              // Update rider marker on every rebuild (rider location may change)
              _updateRiderMarker(ride);
            }
          });
        }

        return Scaffold(
          backgroundColor: const Color(0xFF1E1E1E), // Dark background to match map
          body: Stack(
            children: [
              // Mapa de navegación - ocupa toda la pantalla
              Positioned.fill(
                child: MapWidget(
                  key: const ValueKey('nav_map'),
                  viewport: FollowPuckViewportState(
                    zoom: 17.0,
                    bearing: ride != null
                        ? FollowPuckViewportStateBearingCourse()
                        : FollowPuckViewportStateBearingConstant(0),
                    // Speed-based pitch: < 10 km/h = flat (0°), >= 10 km/h = navigation (45°)
                    pitch: ride != null ? _currentPitch : 0.0,
                  ),
                  styleUri: 'mapbox://styles/mapbox/navigation-night-v1',
                  onMapCreated: _onMapCreated,
                  androidHostingMode: AndroidPlatformViewHostingMode.VD,
                ),
              ),

              // NavigationUI - solo top maneuver banner + nav controls (sin ride panel)
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
                    ride: null,
                    waitSeconds: 0,
                    hideBottomPanel: true, // Uber panel handles bottom controls
                    onMute: () => setState(() => _isMuted = !_isMuted),
                    onOverview: _toggleOverviewMode,
                    onShowSteps: _showAllSteps,
                    onClose: _clearRoute,
                    onLaunchExternalNav: _launchExternalNav,
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

              // Panel Uber-style - siempre visible cuando hay ride activa (navegando o no)
              if (!_isLoadingRoute && rideProvider.activeRide != null && _isMapReady)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _buildUberStylePanel(rideProvider.activeRide!),
                ),

              // Loading route indicator
              if (_isLoadingRoute)
                Positioned(
                  bottom: 30,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E).withOpacity(0.92),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white54,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Calculando ruta...',
                            style: TextStyle(color: Colors.white54, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Available rides panel (cuando no hay ride activo ni navegación)
              if (!_navState.isNavigating && !_isLoadingRoute && rideProvider.activeRide == null)
                Positioned(
                  bottom: 20,
                  left: 12,
                  right: 12,
                  child: _buildAvailableRidesPanel(rideProvider),
                ),

              // Back button - always visible, on top of everything
              if (widget.onBack != null)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  left: 16,
                  child: GestureDetector(
                    onTap: widget.onBack,
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E).withOpacity(0.9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.15),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 24,
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

  // ============================================================================
  // AVAILABLE RIDES PANEL (waiting room)
  // ============================================================================

  Widget _buildAvailableRidesPanel(RideProvider rideProvider) {
    final rides = rideProvider.availableRides;

    if (rides.isEmpty) {
      // No rides - show minimal status
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E).withOpacity(0.92),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _isMapReady ? Colors.green : Colors.red,
                shape: BoxShape.circle,
                boxShadow: [
                  if (_isMapReady)
                    BoxShadow(
                      color: Colors.green.withAlpha(120),
                      blurRadius: 6,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Esperando viajes...',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ),
      );
    }

    // Has available rides - show ride cards
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.45,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E).withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9500),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF9500).withAlpha(130),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${rides.length} ${rides.length == 1 ? 'viaje disponible' : 'viajes disponibles'}',
                  style: const TextStyle(
                    color: Color(0xFFFF9500),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // Ride cards list (scrollable)
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              itemCount: rides.length > 5 ? 5 : rides.length,
              itemBuilder: (context, index) {
                final ride = rides[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildMapRideCard(ride, rideProvider),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapRideCard(RideModel ride, RideProvider rideProvider) {
    // Type icon & color - Minimalist: blue, light-blue, gray
    IconData typeIcon;
    Color typeColor;
    String typeLabel;
    switch (ride.type) {
      case RideType.passenger:
        typeIcon = Icons.person;
        typeColor = const Color(0xFF1E88E5);  // Blue
        typeLabel = 'RIDE';
        break;
      case RideType.package:
        typeIcon = Icons.inventory_2;
        typeColor = const Color(0xFF78909C);  // Blue-gray
        typeLabel = 'PKG';
        break;
      case RideType.carpool:
        typeIcon = Icons.groups;
        typeColor = const Color(0xFF42A5F5);  // Light blue
        typeLabel = 'POOL';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Type + Name + Rating + Earnings
          Row(
            children: [
              // Type badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: typeColor.withAlpha(40),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(typeIcon, color: typeColor, size: 12),
                    const SizedBox(width: 3),
                    Text(typeLabel,
                        style: TextStyle(
                            color: typeColor,
                            fontSize: 9,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              if (ride.isGoodTipper) ...[
                const SizedBox(width: 4),
                const Icon(Icons.star, color: Colors.white70, size: 12),
              ],
              const SizedBox(width: 8),
              // Name
              Expanded(
                child: Text(
                  ride.displayName,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (ride.passengerRating > 0) ...[
                const Icon(Icons.star, color: Colors.white54, size: 12),
                Text(ride.passengerRating.toStringAsFixed(1),
                    style: const TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(width: 6),
              ],
              // Amount display - CASH: show total to collect, CARD: show driver earnings
              if (ride.paymentMethod == PaymentMethod.cash) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.green.withOpacity(0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.payments, color: Colors.green, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        'Cobrar: \$${ride.fare.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.green,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, color: Colors.blue, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        '\$${ride.driverEarnings.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.blue,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          // Row 2: Pickup → Dropoff
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E88E5),  // Blue
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  ride.pickupLocation.address ?? 'Pickup',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.arrow_forward, color: Colors.white30, size: 12),
              ),
              Expanded(
                child: Text(
                  ride.dropoffLocation.address ?? 'Destino',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Row 3: Distance + Time + Payment + Buttons
          Row(
            children: [
              // Distance
              const Icon(Icons.route, color: Colors.white38, size: 12),
              const SizedBox(width: 2),
              Text(
                '${(ride.distanceKm * 0.621371).toStringAsFixed(1)} mi',
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
              const SizedBox(width: 8),
              // Time
              const Icon(Icons.schedule, color: Colors.white38, size: 12),
              const SizedBox(width: 2),
              Text(
                '~${ride.estimatedMinutes} min',
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
              const SizedBox(width: 8),
              // Payment
              Icon(
                ride.paymentMethod == PaymentMethod.cash
                    ? Icons.payments_outlined
                    : Icons.credit_card,
                color: Colors.white54,
                size: 12,
              ),
              const Spacer(),
              // Reject
              GestureDetector(
                onTap: () async {
                  final driverProvider = context.read<DriverProvider>();
                  final driverId = driverProvider.driver?.id;
                  if (driverId != null) {
                    await rideProvider.dismissRide(ride.id, driverId);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(Icons.close, color: Colors.white54, size: 16),
                ),
              ),
              const SizedBox(width: 8),
              // Accept
              GestureDetector(
                onTap: () async {
                  final driverProvider = context.read<DriverProvider>();
                  final driverId = driverProvider.driver?.id;
                  if (driverId == null) return;
                  final success = await rideProvider.acceptRide(ride.id, driverId);
                  if (!success && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(rideProvider.error ?? 'Error'),
                        backgroundColor: const Color(0xFF424242),
                      ),
                    );
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1E88E5), Color(0xFF1565C0)],  // Blue gradient
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Text('ACEPTAR',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // UBER-STYLE PANEL - Bottom panel during active ride
  // ============================================================================

  Widget _buildUberStylePanel(RideModel ride) {
    final isGoingToPickup = ride.status == RideStatus.accepted ||
        ride.status == RideStatus.pending;
    final isWaiting = ride.status == RideStatus.arrivedAtPickup;
    final isInProgress = ride.status == RideStatus.inProgress;

    // Status config
    String statusLabel;
    Color statusColor;
    IconData statusIcon;
    String? statusSubtitle;
    if (isGoingToPickup) {
      statusLabel = 'En camino al pickup';
      statusColor = const Color(0xFF2196F3);
      statusIcon = Icons.directions_car;
      if (_navState.isNavigating) {
        statusSubtitle = 'ETA: ${_navState.formattedETA}';
      }
    } else if (isWaiting) {
      statusLabel = 'Esperando pasajero';
      statusColor = const Color(0xFF78909C);  // Blue-gray
      statusIcon = Icons.place;
      statusSubtitle = 'En el punto de recogida';
    } else if (isInProgress) {
      statusLabel = 'Viaje en curso';
      statusColor = const Color(0xFF42A5F5);  // Light blue
      statusIcon = Icons.navigation;
    } else {
      statusLabel = '';
      statusColor = Colors.white;
      statusIcon = Icons.info;
    }

    final hasPhone = ride.passengerPhone != null && ride.passengerPhone!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Status banner (rider style: icon + text + border)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: statusColor.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          statusLabel,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (statusSubtitle != null)
                          Text(
                            statusSubtitle,
                            style: TextStyle(
                              color: statusColor.withOpacity(0.8),
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Wait timer inline (when waiting)
                  if (isWaiting && _waitSeconds > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text(
                        '${(_waitSeconds ~/ 60).toString().padLeft(2, '0')}:${(_waitSeconds % 60).toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _waitSeconds <= 120 ? Colors.white : Colors.white70,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Rider info row
            Row(
              children: [
                // Avatar circle with status tint
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.2),
                    shape: BoxShape.circle,
                    image: ride.displayImageUrl != null
                        ? DecorationImage(
                            image: NetworkImage(ride.displayImageUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: ride.displayImageUrl == null
                      ? Icon(Icons.person, color: statusColor, size: 24)
                      : null,
                ),
                const SizedBox(width: 12),
                // Name + vehicle info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              ride.displayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (ride.passengerRating > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star, size: 14, color: Colors.white70),
                                  const SizedBox(width: 2),
                                  Text(
                                    ride.passengerRating.toStringAsFixed(1),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          // CONTACT BUTTONS - MÁS GRANDES Y VISIBLES
                          const SizedBox(width: 12),
                          // Call button (solo si hay phone)
                          if (hasPhone)
                            GestureDetector(
                              onTap: () => _callPassenger(ride),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF424242),  // Dark gray
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: const Icon(Icons.phone, size: 20, color: Colors.white),
                              ),
                            ),
                          if (hasPhone) const SizedBox(width: 8),
                          // Chat button - SIEMPRE VISIBLE
                          GestureDetector(
                            onTap: () => _openChatWithPassenger(ride),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1565C0),  // Darker blue
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white24),
                              ),
                              child: const Icon(Icons.chat_bubble, size: 20, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isGoingToPickup
                            ? (ride.pickupLocation.address ?? 'Pickup')
                            : (ride.dropoffLocation.address ?? 'Destino'),
                        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Trip details card (rider style: inner card with primary tint)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: statusColor.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  // Trip info chips
                  Expanded(
                    child: Row(
                      children: [
                        if (_navState.isNavigating) ...[
                          _buildTripDetailChip(Icons.access_time_filled, _navState.formattedETA),
                          const SizedBox(width: 6),
                          _buildTripDetailChip(Icons.route, _navState.formattedDistanceRemaining),
                          const SizedBox(width: 6),
                          _buildTripDetailChip(Icons.schedule, _navState.formattedDurationRemaining),
                        ] else ...[
                          _buildTripDetailChip(Icons.route, '${(ride.distanceKm * 0.621371).toStringAsFixed(1)} mi'),
                          const SizedBox(width: 6),
                          _buildTripDetailChip(Icons.schedule, '~${ride.estimatedMinutes} min'),
                        ],
                      ],
                    ),
                  ),
                  // Payment pill - CASH: show amount to collect, CARD: show "Ya pagado"
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: ride.paymentMethod == PaymentMethod.cash
                          ? Colors.green.withOpacity(0.15)
                          : Colors.blue.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: ride.paymentMethod == PaymentMethod.cash
                            ? Colors.green.withOpacity(0.5)
                            : Colors.blue.withOpacity(0.5),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          // CASH: show fare (what to collect), CARD: show driver earnings
                          ride.paymentMethod == PaymentMethod.cash
                              ? '\$${ride.fare.toStringAsFixed(2)}'
                              : '\$${ride.driverEarnings.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: ride.paymentMethod == PaymentMethod.cash
                                ? Colors.green
                                : Colors.blue,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              ride.paymentMethod == PaymentMethod.cash
                                  ? Icons.payments_outlined
                                  : Icons.check_circle,
                              color: ride.paymentMethod == PaymentMethod.cash
                                  ? Colors.green.withOpacity(0.8)
                                  : Colors.blue.withOpacity(0.8),
                              size: 12,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              ride.paymentMethod == PaymentMethod.cash
                                  ? 'COBRAR EN EFECTIVO'
                                  : 'YA PAGADO',
                              style: TextStyle(
                                color: ride.paymentMethod == PaymentMethod.cash
                                    ? Colors.green.withOpacity(0.8)
                                    : Colors.blue.withOpacity(0.8),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Mute button when navigating
                  if (_navState.isNavigating) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() => _isMuted = !_isMuted),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _isMuted ? Icons.volume_off : Icons.volume_up,
                          color: Colors.white54,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Slide to confirm action
            _buildSlideToConfirm(ride),
            const SizedBox(height: 10),

            // Bottom action bar: Navigate + Report + Cancel
            Row(
              children: [
                // Navigate
                _buildBottomAction(
                  icon: Icons.navigation,
                  label: 'Navegar',
                  color: const Color(0xFF1E88E5),  // Blue
                  onTap: _launchExternalNav,
                ),
                const SizedBox(width: 8),
                // Report
                _buildBottomAction(
                  icon: Icons.flag_rounded,
                  label: 'Reportar',
                  color: const Color(0xFFFF9800),  // Orange
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReportRideScreen(
                          rideId: ride.id,
                          rideType: ride.type == RideType.carpool
                              ? 'carpool'
                              : ride.type == RideType.package
                                  ? 'delivery'
                                  : 'ride',
                          reportedUserId: ride.passengerId,
                          reportedUserName: ride.displayName,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
                // Cancel
                _buildBottomAction(
                  icon: Icons.close,
                  label: 'Cancelar',
                  color: const Color(0xFF757575),  // Gray
                  onTap: _handleCancelRide,
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildTripDetailChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white54, size: 14),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildBottomAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.35)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 3),
              Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  // Slide-to-confirm widget
  Widget _buildSlideToConfirm(RideModel ride) {
    String label;
    Color color;
    VoidCallback? onConfirm;

    switch (ride.status) {
      case RideStatus.accepted:
      case RideStatus.pending:
        label = '📍  DESLIZA → LLEGUÉ';
        color = const Color(0xFF1E88E5);  // Blue
        onConfirm = _handleArriveAtPickup;
        break;
      case RideStatus.arrivedAtPickup:
        label = '▶  DESLIZA → INICIAR VIAJE';
        color = const Color(0xFF42A5F5);  // Light blue
        onConfirm = _handleStartRide;
        break;
      case RideStatus.inProgress:
        label = '🏁  DESLIZA → FINALIZAR';
        color = const Color(0xFF1565C0);  // Darker blue
        onConfirm = _handleCompleteRide;
        break;
      default:
        return const SizedBox.shrink();
    }

    return _SlideToConfirmButton(
      label: label,
      color: color,
      onConfirm: onConfirm,
    );
  }

  Future<void> _sendSmsToPassenger(RideModel ride) async {
    if (ride.passengerPhone == null) return;
    final phone = ride.passengerPhone!.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('sms:$phone');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  /// Open in-app chat with passenger
  void _openChatWithPassenger(RideModel ride) {
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    final driverId = driverProvider.driver?.id;
    if (driverId == null) return;

    RideChatPopup.show(
      context,
      deliveryId: ride.id,
      myId: driverId,
      myType: 'driver',
      otherName: ride.passengerName,
      otherImageUrl: ride.passengerImageUrl,
    );
  }

  /// Wait timer for pre-navigation panel
  Widget _buildWaitTimerCompact() {
    final minutes = _waitSeconds ~/ 60;
    final seconds = _waitSeconds % 60;
    final isFreeTime = _waitSeconds <= 120;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isFreeTime ? Colors.blue.withAlpha(30) : Colors.red.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isFreeTime ? Colors.blue.withAlpha(80) : Colors.red.withAlpha(80),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.timer,
            color: isFreeTime ? Colors.blue : Colors.red,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            'Esperando: ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
            style: TextStyle(
              color: isFreeTime ? Colors.blue : Colors.red,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            isFreeTime ? 'Gratis' : 'Cobro activo',
            style: TextStyle(
              color: isFreeTime ? Colors.blue.withAlpha(180) : Colors.red,
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

// ============================================================================
// SLIDE TO CONFIRM BUTTON - Uber-style swipe action
// ============================================================================

class _SlideToConfirmButton extends StatefulWidget {
  final String label;
  final Color color;
  final VoidCallback? onConfirm;

  const _SlideToConfirmButton({
    required this.label,
    required this.color,
    required this.onConfirm,
  });

  @override
  State<_SlideToConfirmButton> createState() => _SlideToConfirmButtonState();
}

class _SlideToConfirmButtonState extends State<_SlideToConfirmButton>
    with SingleTickerProviderStateMixin {
  double _dragPosition = 0;
  bool _confirmed = false;
  late AnimationController _resetController;
  late Animation<double> _resetAnimation;

  static const double _thumbSize = 56;
  static const double _horizontalPadding = 4;

  @override
  void initState() {
    super.initState();
    _resetController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _resetAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _resetController, curve: Curves.easeOut),
    );
    _resetController.addListener(() {
      setState(() => _dragPosition = _resetAnimation.value);
    });
  }

  @override
  void dispose() {
    _resetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxDrag = constraints.maxWidth - _thumbSize - (_horizontalPadding * 2);
        final progress = maxDrag > 0 ? (_dragPosition / maxDrag).clamp(0.0, 1.0) : 0.0;

        return Container(
          height: 60,
          decoration: BoxDecoration(
            color: widget.color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: widget.color.withOpacity(0.5), width: 1.5),
          ),
          child: Stack(
            children: [
              // Progress fill
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress * 0.9 + 0.1,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          widget.color.withOpacity(0.4),
                          widget.color.withOpacity(0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              ),
              // Label text (fades as you slide)
              Center(
                child: Opacity(
                  opacity: (1 - progress * 1.5).clamp(0.0, 1.0),
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      color: widget.color,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              // Draggable thumb
              Positioned(
                left: _horizontalPadding + _dragPosition,
                top: 2,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    if (_confirmed) return;
                    setState(() {
                      _dragPosition = (_dragPosition + details.delta.dx).clamp(0.0, maxDrag);
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    if (_confirmed) return;
                    if (_dragPosition >= maxDrag * 0.85) {
                      // Confirmed!
                      setState(() {
                        _confirmed = true;
                        _dragPosition = maxDrag;
                      });
                      HapticFeedback.heavyImpact();
                      widget.onConfirm?.call();
                      // Reset after action
                      Future.delayed(const Duration(milliseconds: 500), () {
                        if (mounted) {
                          setState(() {
                            _confirmed = false;
                            _dragPosition = 0;
                          });
                        }
                      });
                    } else {
                      // Snap back
                      _resetAnimation = Tween<double>(
                        begin: _dragPosition,
                        end: 0,
                      ).animate(CurvedAnimation(
                        parent: _resetController,
                        curve: Curves.easeOut,
                      ));
                      _resetController.forward(from: 0);
                    }
                  },
                  child: Container(
                    width: _thumbSize,
                    height: _thumbSize,
                    decoration: BoxDecoration(
                      color: _confirmed ? Colors.white : widget.color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: widget.color.withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(2, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      _confirmed ? Icons.check : Icons.arrow_forward_rounded,
                      color: _confirmed ? widget.color : Colors.white,
                      size: 28,
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
}
