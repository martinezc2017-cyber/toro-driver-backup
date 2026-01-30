import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/ride_provider.dart';
import '../providers/driver_provider.dart';
import '../providers/location_provider.dart';
import '../models/ride_model.dart';
import '../utils/app_colors.dart';
import '../utils/haptic_service.dart';

/// Map Screen - Shows driver location and searching animation
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  LatLng? _driverLocation;
  bool _isLoading = true;
  double _currentZoom = 15.0;
  double _currentRotation = 0.0;

  // Animation controllers
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _searchController;

  @override
  void initState() {
    super.initState();

    // Pulse animation for driver marker
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Search animation
    _searchController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);

    // Try to get current position
    if (locationProvider.currentPosition != null) {
      _driverLocation = LatLng(
        locationProvider.currentPosition!.latitude,
        locationProvider.currentPosition!.longitude,
      );
    } else {
      // Initialize and get position
      await locationProvider.initialize();
      final position = await locationProvider.getCurrentPosition();
      if (position != null) {
        _driverLocation = LatLng(position.latitude, position.longitude);
      } else {
        // Default to Mexico City if no location
        _driverLocation = const LatLng(19.4326, -99.1332);
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Consumer2<RideProvider, DriverProvider>(
        builder: (context, rideProvider, driverProvider, child) {
          final activeRide = rideProvider.activeRide;
          final isOnline = driverProvider.isOnline;

          // If there's an active ride, show navigation option
          if (activeRide != null) {
            return _buildActiveRideView(activeRide);
          }

          // Show map with driver location
          return _buildMapView(
            isOnline,
            rideProvider.availableRides,
            driverProvider,
            rideProvider,
          );
        },
      ),
    );
  }

  Widget _buildMapView(
    bool isOnline,
    List<RideModel> availableRides,
    DriverProvider driverProvider,
    RideProvider rideProvider,
  ) {
    final availableRidesCount = availableRides.length;
    if (_isLoading || _driverLocation == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF9500)),
      );
    }

    return Stack(
      children: [
        // Map
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _driverLocation!,
            initialZoom: _currentZoom,
            minZoom: 4,
            maxZoom: 18,
            onPositionChanged: (position, hasGesture) {
              if (position.zoom != null) {
                _currentZoom = position.zoom!;
              }
            },
            onMapEvent: (event) {
              // Track rotation from map camera
              final camera = _mapController.camera;
              if (camera.rotation != _currentRotation) {
                setState(() {
                  _currentRotation = camera.rotation;
                });
              }
            },
          ),
          children: [
            // Dark map base (CartoDB Dark Matter - no labels)
            TileLayer(
              urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_nolabels/{z}/{x}/{y}{r}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'com.toro.driver',
              retinaMode: RetinaMode.isHighDensity(context),
            ),
            // Labels layer on top (CartoDB Dark Labels)
            TileLayer(
              urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_only_labels/{z}/{x}/{y}{r}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'com.toro.driver',
              retinaMode: RetinaMode.isHighDensity(context),
            ),

            // Driver location marker with pulse
            MarkerLayer(
              markers: [
                Marker(
                  point: _driverLocation!,
                  width: 80,
                  height: 80,
                  child: AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          // Outer pulse ring
                          Container(
                            width: 70 * _pulseAnimation.value,
                            height: 70 * _pulseAnimation.value,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFFF9500).withValues(alpha: 0.2 * (1 - _pulseAnimation.value)),
                            ),
                          ),
                          // Middle ring
                          Container(
                            width: 50 * _pulseAnimation.value,
                            height: 50 * _pulseAnimation.value,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFFF9500).withValues(alpha: 0.3 * (1 - _pulseAnimation.value)),
                            ),
                          ),
                          // Driver icon
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF9500),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFF9500).withValues(alpha: 0.5),
                                  blurRadius: 15,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.directions_car,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),

        // Top bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 10,
              left: 16,
              right: 16,
              bottom: 16,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.7),
                  Colors.transparent,
                ],
              ),
            ),
            child: Row(
              children: [
                // Back button
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                const Spacer(),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isOnline
                        ? const Color(0xFFFF9500).withValues(alpha: 0.2)
                        : AppColors.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isOnline
                          ? const Color(0xFFFF9500).withValues(alpha: 0.5)
                          : AppColors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isOnline)
                        AnimatedBuilder(
                          animation: _searchController,
                          builder: (context, child) {
                            return Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Color.lerp(
                                  const Color(0xFFFF9500),
                                  const Color(0xFFFFF5E6),
                                  (_searchController.value * 2).clamp(0.0, 1.0),
                                ),
                                shape: BoxShape.circle,
                              ),
                            );
                          },
                        )
                      else
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppColors.textTertiary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      const SizedBox(width: 8),
                      Text(
                        isOnline ? 'Buscando viajes...' : 'Offline',
                        style: TextStyle(
                          color: isOnline
                              ? const Color(0xFFFF9500)
                              : AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Center on location button
                GestureDetector(
                  onTap: () {
                    HapticService.lightImpact();
                    if (_driverLocation != null) {
                      _mapController.move(_driverLocation!, 15);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.my_location_rounded,
                      color: Color(0xFFFF9500),
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Right side controls (Compass + Zoom buttons)
        Positioned(
          right: 16,
          top: MediaQuery.of(context).padding.top + 80,
          child: Column(
            children: [
              // Compass (shows north, rotates with map)
              GestureDetector(
                onTap: () {
                  HapticService.lightImpact();
                  // Reset rotation to north
                  _mapController.rotate(0);
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Transform.rotate(
                    angle: -_currentRotation * (3.14159 / 180),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // North indicator (red)
                        Positioned(
                          top: 6,
                          child: Container(
                            width: 3,
                            height: 12,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF4444),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        // South indicator (white)
                        Positioned(
                          bottom: 6,
                          child: Container(
                            width: 3,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        // Center dot
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                        // N label
                        const Positioned(
                          top: 4,
                          child: Text(
                            'N',
                            style: TextStyle(
                              color: Color(0xFFFF4444),
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Zoom in button
              GestureDetector(
                onTap: () {
                  HapticService.lightImpact();
                  final newZoom = (_currentZoom + 1).clamp(4.0, 18.0);
                  _mapController.move(_mapController.camera.center, newZoom);
                  _currentZoom = newZoom;
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.add,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
              Container(
                width: 44,
                height: 1,
                color: AppColors.border,
              ),
              // Zoom out button
              GestureDetector(
                onTap: () {
                  HapticService.lightImpact();
                  final newZoom = (_currentZoom - 1).clamp(4.0, 18.0);
                  _mapController.move(_mapController.camera.center, newZoom);
                  _currentZoom = newZoom;
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                  ),
                  child: const Icon(
                    Icons.remove,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Bottom info card with Online/Offline toggle
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).padding.bottom + 20,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Status info row
                Row(
                  children: [
                    // Status icon with animation
                    if (isOnline) ...[
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: AnimatedBuilder(
                          animation: _searchController,
                          builder: (context, child) {
                            return Transform.rotate(
                              angle: _searchController.value * 6.28,
                              child: const Icon(
                                Icons.radar_rounded,
                                color: Color(0xFFFF9500),
                                size: 24,
                              ),
                            );
                          },
                        ),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.textTertiary.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.bedtime_outlined,
                          color: AppColors.textTertiary,
                          size: 16,
                        ),
                      ),
                    ],
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isOnline
                                ? (availableRidesCount > 0
                                    ? '$availableRidesCount viajes disponibles'
                                    : 'Buscando viajes cercanos')
                                : 'Estás desconectado',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isOnline
                                ? 'Te notificaremos cuando haya uno nuevo'
                                : 'Activa tu estado para recibir viajes',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // Show available rides if any
                if (isOnline && availableRides.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 120,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: availableRides.length > 5 ? 5 : availableRides.length,
                      itemBuilder: (context, index) {
                        final ride = availableRides[index];
                        return _buildCompactRideCard(
                          ride,
                          driverProvider,
                          rideProvider,
                        );
                      },
                    ),
                  ),
                ],
                // Toggle button removed - use header toggle on home screen instead
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveRideView(dynamic activeRide) {
    return Stack(
      children: [
        // Show map with route preview
        if (_driverLocation != null)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _driverLocation!,
              initialZoom: 14.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _driverLocation!,
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9500),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF9500).withValues(alpha: 0.5),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.directions_car,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

        // Overlay with ride info
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(context).padding.bottom + 24,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9500).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFFF9500).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.local_shipping_rounded,
                        color: Color(0xFFFF9500),
                        size: 32,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Viaje activo',
                              style: TextStyle(
                                color: Color(0xFFFF9500),
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              activeRide.pickupLocation.address ?? 'Punto de recogida',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () {
                    HapticService.mediumImpact();
                    // Close map screen - HomeScreen will detect active ride via RideProvider
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF9500), Color(0xFFFF6B00)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF9500).withValues(alpha: 0.4),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.navigation_rounded, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'ABRIR NAVEGACIÓN',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Back button
        Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          left: 16,
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Compact ride card for horizontal list
  Widget _buildCompactRideCard(
    RideModel ride,
    DriverProvider driverProvider,
    RideProvider rideProvider,
  ) {
    final isCarpool = ride.type == RideType.carpool;
    final typeIcon = ride.type == RideType.passenger ? '🚗'
        : ride.type == RideType.package ? '📦'
        : '👥';

    return GestureDetector(
      onTap: () async {
        HapticService.mediumImpact();
        final driverId = driverProvider.driver?.id;
        if (driverId != null) {
          final success = await rideProvider.acceptRide(ride.id, driverId);
          if (mounted && success) {
            // Close map screen - HomeScreen will detect active ride via RideProvider
            Navigator.pop(context);
          }
        }
      },
      child: Container(
        width: 200,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isCarpool
                ? Colors.blue.withValues(alpha: 0.5)
                : const Color(0xFFFF9500).withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type badge row
            Row(
              children: [
                Text(typeIcon, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 4),
                if (ride.isRoundTrip)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF00C853), Color(0xFF00897B)]),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('round_trip'.tr(), style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                  ),
                const Spacer(),
                Text(
                  '\$${ride.fare.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Color(0xFF4CAF50),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Destination
            Text(
              ride.dropoffLocation.address ?? 'destination'.tr(),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            // Carpool info
            if (isCarpool && ride.recurringDays.isNotEmpty) ...[
              Row(
                children: [
                  // Days
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _formatDays(ride.recurringDays),
                      style: const TextStyle(color: Colors.blue, fontSize: 9, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Seats
                  ...List.generate(3, (i) => Icon(
                    Icons.person,
                    color: i < ride.filledSeats ? const Color(0xFF4CAF50) : AppColors.textTertiary,
                    size: 12,
                  )),
                ],
              ),
            ] else ...[
              // Distance and time for regular rides
              Row(
                children: [
                  Icon(Icons.route, color: AppColors.textTertiary, size: 12),
                  const SizedBox(width: 2),
                  Text(
                    '${(ride.distanceKm * 0.621371).toStringAsFixed(1)} mi',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.schedule, color: AppColors.textTertiary, size: 12),
                  const SizedBox(width: 2),
                  Text(
                    '${ride.estimatedMinutes} min',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Format recurring days to short form
  String _formatDays(List<int> days) {
    const dayLetters = ['', 'L', 'M', 'X', 'J', 'V', 'S', 'D'];
    final sorted = List<int>.from(days)..sort();
    return sorted.map((d) => d >= 1 && d <= 7 ? dayLetters[d] : '').join('');
  }
}
