import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart' as geo;
import '../models/ride_model.dart';
import '../providers/location_provider.dart';
import '../providers/ride_provider.dart';
import '../providers/driver_provider.dart';
import '../services/mapbox_navigation_service.dart';
import '../utils/app_colors.dart';
import '../utils/haptic_service.dart';

/// Navigation Map Screen - 3D Uber-Style with Mapbox
/// Professional turn-by-turn navigation with 3D perspective
class NavigationMapScreen extends StatefulWidget {
  final RideModel ride;

  const NavigationMapScreen({super.key, required this.ride});

  @override
  State<NavigationMapScreen> createState() => _NavigationMapScreenState();
}

class _NavigationMapScreenState extends State<NavigationMapScreen>
    with TickerProviderStateMixin {

  // Mapbox controller
  MapboxMap? _mapboxMap;

  // Navigation service
  final MapboxNavigationService _navService = MapboxNavigationService();

  // State
  bool _isLoading = true;
  bool _isNavigating = false;
  double _currentBearing = 0;
  Position? _driverPosition;
  MapboxRoute? _currentRoute;
  NavigationStep? _currentStep;
  double _distanceRemaining = 0;
  double _durationRemaining = 0;

  // Route line
  PolylineAnnotation? _routeLine;
  PolylineAnnotationManager? _polylineManager;
  PointAnnotationManager? _pointManager;

  // Location tracking
  StreamSubscription<geo.Position>? _locationSubscription;

  // Determine target based on ride status
  bool get _isGoingToPickup =>
      widget.ride.status == RideStatus.accepted ||
      widget.ride.status == RideStatus.pending;

  Position get _targetPosition => _isGoingToPickup
      ? Position(
          widget.ride.pickupLocation.longitude,
          widget.ride.pickupLocation.latitude,
        )
      : Position(
          widget.ride.dropoffLocation.longitude,
          widget.ride.dropoffLocation.latitude,
        );

  String get _targetAddress => _isGoingToPickup
      ? widget.ride.pickupLocation.address ?? 'Punto de recogida'
      : widget.ride.dropoffLocation.address ?? 'Destino';

  @override
  void initState() {
    super.initState();
    _initializeNavigation();
  }

  Future<void> _initializeNavigation() async {
    try {
      // Initialize Mapbox
      await _navService.initialize();

      // Get current location
      final locationProvider = Provider.of<LocationProvider>(context, listen: false);
      if (locationProvider.currentPosition != null) {
        _driverPosition = Position(
          locationProvider.currentPosition!.longitude,
          locationProvider.currentPosition!.latitude,
        );
      } else {
        final position = await locationProvider.getCurrentPosition();
        if (position != null) {
          _driverPosition = Position(position.longitude, position.latitude);
        }
      }

      // Get route
      if (_driverPosition != null) {
        _currentRoute = await _navService.getRoute(
          originLat: _driverPosition!.lat.toDouble(),
          originLng: _driverPosition!.lng.toDouble(),
          destinationLat: _targetPosition.lat.toDouble(),
          destinationLng: _targetPosition.lng.toDouble(),
        );

        if (_currentRoute != null) {
          _distanceRemaining = _currentRoute!.distance;
          _durationRemaining = _currentRoute!.duration;
          if (_currentRoute!.steps.isNotEmpty) {
            _currentStep = _currentRoute!.steps.first;
          }
        }
      }

      setState(() {
        _isLoading = false;
      });

      // Start location tracking
      _startLocationTracking();
    } catch (e) {
      debugPrint('Navigation init error: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _startLocationTracking() {
    _locationSubscription = geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.high,
        distanceFilter: 5, // Update every 5 meters
      ),
    ).listen((position) {
      _updateDriverLocation(position);
    });
  }

  void _updateDriverLocation(geo.Position position) async {
    final newPosition = Position(position.longitude, position.latitude);

    // Calculate bearing based on movement
    if (_driverPosition != null) {
      final bearing = geo.Geolocator.bearingBetween(
        _driverPosition!.lat.toDouble(),
        _driverPosition!.lng.toDouble(),
        position.latitude,
        position.longitude,
      );
      _currentBearing = bearing;
    }

    _driverPosition = newPosition;

    // Update camera to follow driver
    if (_mapboxMap != null && _isNavigating) {
      await _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(coordinates: newPosition),
          zoom: 17.5,
          bearing: _currentBearing,
          pitch: 60, // 3D tilt
        ),
        MapAnimationOptions(duration: 1000),
      );
    }

    // Check distance to target
    final distanceToTarget = geo.Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      _targetPosition.lat.toDouble(),
      _targetPosition.lng.toDouble(),
    );

    setState(() {
      _distanceRemaining = distanceToTarget;
      _durationRemaining = distanceToTarget / 8; // ~30 km/h average
    });

    // Update driver marker on map
    _updateDriverMarker();
  }

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;

    // Setup annotation managers
    _polylineManager = await mapboxMap.annotations.createPolylineAnnotationManager();
    _pointManager = await mapboxMap.annotations.createPointAnnotationManager();

    // Draw route
    await _drawRoute();

    // Add markers
    await _addMarkers();

    // Start in navigation mode
    _startNavigationMode();
  }

  Future<void> _drawRoute() async {
    if (_currentRoute == null || _polylineManager == null) return;

    // Convert route geometry to points
    final points = _currentRoute!.geometry.map((coord) {
      return Point(coordinates: Position(coord[0], coord[1]));
    }).toList();

    if (points.isEmpty) return;

    // Create route line
    final options = PolylineAnnotationOptions(
      geometry: LineString(coordinates: points.map((p) => p.coordinates).toList()),
      lineColor: Colors.orange.value,
      lineWidth: 6.0,
      lineOpacity: 1.0,
    );

    _routeLine = await _polylineManager!.create(options);
  }

  Future<void> _addMarkers() async {
    if (_pointManager == null) return;

    // Add destination marker
    await _pointManager!.create(
      PointAnnotationOptions(
        geometry: Point(coordinates: _targetPosition),
        iconSize: 1.5,
        iconColor: _isGoingToPickup ? Colors.orange.value : Colors.green.value,
        textField: _isGoingToPickup ? "PICKUP" : "DESTINO",
        textColor: Colors.white.value,
        textSize: 12,
      ),
    );
  }

  Future<void> _updateDriverMarker() async {
    // Driver marker is handled by Mapbox location puck
    // This could be enhanced with custom marker if needed
  }

  void _startNavigationMode() {
    setState(() {
      _isNavigating = true;
    });

    // Move camera to navigation view
    if (_mapboxMap != null && _driverPosition != null) {
      _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(coordinates: _driverPosition!),
          zoom: 17.5,
          bearing: _currentBearing,
          pitch: 60, // 3D perspective
        ),
        MapAnimationOptions(duration: 1500),
      );
    }
  }

  void _showOverview() {
    setState(() {
      _isNavigating = false;
    });

    _fitBounds();
  }

  void _fitBounds() {
    if (_mapboxMap == null || _driverPosition == null) return;

    // Calculate bounds
    final minLat = _driverPosition!.lat < _targetPosition.lat
        ? _driverPosition!.lat : _targetPosition.lat;
    final maxLat = _driverPosition!.lat > _targetPosition.lat
        ? _driverPosition!.lat : _targetPosition.lat;
    final minLng = _driverPosition!.lng < _targetPosition.lng
        ? _driverPosition!.lng : _targetPosition.lng;
    final maxLng = _driverPosition!.lng > _targetPosition.lng
        ? _driverPosition!.lng : _targetPosition.lng;

    _mapboxMap!.flyTo(
      CameraOptions(
        center: Point(
          coordinates: Position(
            (minLng.toDouble() + maxLng.toDouble()) / 2,
            (minLat.toDouble() + maxLat.toDouble()) / 2,
          ),
        ),
        zoom: 13,
        bearing: 0,
        pitch: 0,
      ),
      MapAnimationOptions(duration: 1000),
    );
  }

  void _recenterOnDriver() {
    if (_mapboxMap == null || _driverPosition == null) return;

    _mapboxMap!.flyTo(
      CameraOptions(
        center: Point(coordinates: _driverPosition!),
        zoom: 17.5,
        bearing: _currentBearing,
        pitch: 60,
      ),
      MapAnimationOptions(duration: 1000),
    );

    setState(() {
      _isNavigating = true;
    });
  }

  String _formatDistance(double meters) {
    if (meters >= 1609) {
      return '${(meters / 1609.34).toStringAsFixed(1)} mi';
    }
    return '${(meters * 3.28084).toInt()} ft';
  }

  String _formatDuration(double seconds) {
    final minutes = (seconds / 60).round();
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      return '${hours}h ${mins}min';
    }
    return '$minutes min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Mapbox Map
          if (_isLoading)
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFFFF9500)),
                  SizedBox(height: 16),
                  Text(
                    'Cargando navegacion...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            )
          else
            MapWidget(
              cameraOptions: CameraOptions(
                center: Point(
                  coordinates: _driverPosition ?? _targetPosition,
                ),
                zoom: 15,
                bearing: _currentBearing,
                pitch: _isNavigating ? 60 : 0,
              ),
              styleUri: MapboxStyles.DARK,
              onMapCreated: _onMapCreated,
            ),

          // Navigation instruction panel (top)
          if (!_isLoading && _currentStep != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildInstructionPanel(),
            ),

          // Control buttons (right side)
          if (!_isLoading)
            Positioned(
              right: 16,
              top: MediaQuery.of(context).padding.top + 140,
              child: Column(
                children: [
                  _buildControlButton(
                    icon: _isNavigating ? Icons.map_outlined : Icons.navigation,
                    onTap: _isNavigating ? _showOverview : _startNavigationMode,
                    tooltip: _isNavigating ? 'Vista general' : 'Modo navegacion',
                  ),
                  const SizedBox(height: 12),
                  _buildControlButton(
                    icon: Icons.my_location,
                    onTap: _recenterOnDriver,
                    color: const Color(0xFFFF9500),
                    tooltip: 'Centrar en mi',
                  ),
                ],
              ),
            ),

          // Bottom panel with ride controls
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: _buildBottomPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionPanel() {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Back button and distance/time
            Row(
              children: [
                GestureDetector(
                  onTap: () {
                    HapticService.lightImpact();
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                  ),
                ),
                const Spacer(),
                // Distance badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9500).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.directions_car, color: Color(0xFFFF9500), size: 16),
                      const SizedBox(width: 6),
                      Text(
                        '${_formatDistance(_distanceRemaining)} - ${_formatDuration(_durationRemaining)}',
                        style: const TextStyle(
                          color: Color(0xFFFF9500),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Turn instruction
            Row(
              children: [
                // Direction icon
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9500),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _currentStep?.maneuverIcon ?? Icons.straight,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                // Instruction text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentStep?.bannerInstruction ??
                        _currentStep?.instruction ??
                        'Continua recto',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_currentStep != null)
                        Text(
                          'en ${_formatDistance(_currentStep!.distance)}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 14,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
    String? tooltip,
  }) {
    return GestureDetector(
      onTap: () {
        HapticService.lightImpact();
        onTap();
      },
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
            ),
          ],
        ),
        child: Icon(
          icon,
          color: color ?? Colors.white,
          size: 22,
        ),
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Consumer2<RideProvider, DriverProvider>(
      builder: (context, rideProvider, driverProvider, child) {
        final currentRide = rideProvider.activeRide ?? widget.ride;
        final rideStatus = currentRide.status;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFFF9500).withValues(alpha: 0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _getStatusColor(rideStatus).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _getStatusLabel(rideStatus),
                  style: TextStyle(
                    color: _getStatusColor(rideStatus),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Address
              Text(
                _targetAddress,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              // Action button
              _buildActionButton(context, rideProvider, driverProvider, rideStatus),
            ],
          ),
        );
      },
    );
  }

  Color _getStatusColor(RideStatus status) {
    switch (status) {
      case RideStatus.pending:
      case RideStatus.accepted:
        return const Color(0xFFFF9500);
      case RideStatus.arrivedAtPickup:
        return const Color(0xFF4285F4);
      case RideStatus.inProgress:
        return Colors.green;
      case RideStatus.completed:
        return Colors.green;
      case RideStatus.cancelled:
        return Colors.red;
    }
  }

  String _getStatusLabel(RideStatus status) {
    switch (status) {
      case RideStatus.pending:
      case RideStatus.accepted:
        return 'IR A RECOGER';
      case RideStatus.arrivedAtPickup:
        return 'ESPERANDO PASAJERO';
      case RideStatus.inProgress:
        return 'EN CAMINO AL DESTINO';
      case RideStatus.completed:
        return 'COMPLETADO';
      case RideStatus.cancelled:
        return 'CANCELADO';
    }
  }

  Widget _buildActionButton(
    BuildContext context,
    RideProvider rideProvider,
    DriverProvider driverProvider,
    RideStatus status,
  ) {
    String buttonText;
    IconData buttonIcon;
    Color buttonColor;
    VoidCallback? onTap;
    bool isLoading = rideProvider.isLoading;

    switch (status) {
      case RideStatus.pending:
      case RideStatus.accepted:
        buttonText = 'LLEGUE AL PUNTO';
        buttonIcon = Icons.location_on;
        buttonColor = const Color(0xFFFF9500);
        onTap = () async {
          HapticService.mediumImpact();
          final success = await rideProvider.arriveAtPickup();
          if (success && context.mounted) {
            // Refresh route to destination
            await _refreshRoute();
          }
        };
        break;

      case RideStatus.arrivedAtPickup:
        buttonText = 'INICIAR VIAJE';
        buttonIcon = Icons.play_arrow_rounded;
        buttonColor = const Color(0xFF4285F4);
        onTap = () async {
          HapticService.mediumImpact();
          final success = await rideProvider.startRide();
          if (success && context.mounted) {
            await _refreshRoute();
          }
        };
        break;

      case RideStatus.inProgress:
        buttonText = 'COMPLETAR VIAJE';
        buttonIcon = Icons.check_circle;
        buttonColor = Colors.green;
        onTap = () async {
          HapticService.heavyImpact();
          final driverId = driverProvider.driver?.id;
          if (driverId != null) {
            final success = await rideProvider.completeRide(driverId: driverId);
            if (success && context.mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Viaje completado! Ganancias agregadas.'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          }
        };
        break;

      case RideStatus.completed:
      case RideStatus.cancelled:
        buttonText = 'VOLVER AL INICIO';
        buttonIcon = Icons.home_rounded;
        buttonColor = Colors.grey;
        onTap = () => Navigator.pop(context);
        break;
    }

    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isLoading
                ? [Colors.grey, Colors.grey.shade700]
                : [buttonColor, buttonColor.withValues(alpha: 0.8)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: buttonColor.withValues(alpha: 0.4),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            else
              Icon(buttonIcon, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              buttonText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshRoute() async {
    if (_driverPosition == null) return;

    // Get new route
    _currentRoute = await _navService.getRoute(
      originLat: _driverPosition!.lat.toDouble(),
      originLng: _driverPosition!.lng.toDouble(),
      destinationLat: _targetPosition.lat.toDouble(),
      destinationLng: _targetPosition.lng.toDouble(),
    );

    if (_currentRoute != null) {
      _distanceRemaining = _currentRoute!.distance;
      _durationRemaining = _currentRoute!.duration;
      if (_currentRoute!.steps.isNotEmpty) {
        _currentStep = _currentRoute!.steps.first;
      }

      // Redraw route
      if (_polylineManager != null && _routeLine != null) {
        await _polylineManager!.delete(_routeLine!);
      }
      await _drawRoute();
    }

    setState(() {});
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _navService.stopNavigation();
    super.dispose();
  }
}
