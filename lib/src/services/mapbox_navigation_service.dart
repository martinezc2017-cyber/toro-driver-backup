import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as geo;

/// Mapbox Navigation Service using official Mapbox Maps SDK
/// Provides turn-by-turn navigation using Mapbox Directions API
class MapboxNavigationService {
  static final MapboxNavigationService _instance = MapboxNavigationService._internal();
  factory MapboxNavigationService() => _instance;
  MapboxNavigationService._internal();

  // Mapbox Access Token (public token for API calls)
  static const String _accessToken = 'pk.eyJ1IjoibWFydGluZXpjMjAxNyIsImEiOiJjbWtocWtoZHIwbW1iM2dvdXZ3bmp0ZjBiIn0.MjYgv6DuvLTkrBVbrhtFbg';

  bool _isNavigating = false;
  List<NavigationStep> _currentSteps = [];
  int _currentStepIndex = 0;
  StreamController<NavigationUpdate>? _navigationController;
  Timer? _locationTimer;

  bool get isNavigating => _isNavigating;
  List<NavigationStep> get currentSteps => _currentSteps;
  int get currentStepIndex => _currentStepIndex;
  NavigationStep? get currentStep =>
      _currentStepIndex < _currentSteps.length ? _currentSteps[_currentStepIndex] : null;

  /// Stream of navigation updates
  Stream<NavigationUpdate>? get navigationUpdates => _navigationController?.stream;

  /// Initialize the Mapbox SDK
  Future<void> initialize() async {
    MapboxOptions.setAccessToken(_accessToken);
    // MapboxNavigationService: Initialized with access token');
  }

  /// Get route from Mapbox Directions API
  Future<MapboxRoute?> getRoute({
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
    String profile = 'driving-traffic', // driving, driving-traffic, walking, cycling
  }) async {
    try {
      final url = Uri.parse(
        'https://api.mapbox.com/directions/v5/mapbox/$profile/'
        '$originLng,$originLat;$destinationLng,$destinationLat'
        '?access_token=$_accessToken'
        '&geometries=geojson'
        '&overview=full'
        '&steps=true'
        '&voice_instructions=true'
        '&banner_instructions=true'
        '&annotations=congestion' // Request traffic congestion data
        '&language=es' // Spanish instructions
      );

      // MapboxNavigationService: Fetching route from $url');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];
          return MapboxRoute.fromJson(route);
        }
      }

      // MapboxNavigationService: Failed to get route - ${response.statusCode}');
      return null;
    } catch (e) {
      // MapboxNavigationService: Error getting route - $e');
      return null;
    }
  }

  /// Start navigation to a destination
  Future<bool> startNavigation({
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
    String? destinationName,
    void Function(NavigationUpdate)? onUpdate,
  }) async {
    try {
      // Get route
      final route = await getRoute(
        originLat: originLat,
        originLng: originLng,
        destinationLat: destinationLat,
        destinationLng: destinationLng,
      );

      if (route == null) {
        // MapboxNavigationService: Could not get route');
        return false;
      }

      _currentSteps = route.steps;
      _currentStepIndex = 0;
      _isNavigating = true;

      // Create stream controller for updates
      _navigationController?.close();
      _navigationController = StreamController<NavigationUpdate>.broadcast();

      if (onUpdate != null) {
        _navigationController!.stream.listen(onUpdate);
      }

      // Start location tracking
      _startLocationTracking(destinationLat, destinationLng);

      // Send initial update
      _emitUpdate(NavigationUpdate(
        currentStep: _currentSteps.isNotEmpty ? _currentSteps[0] : null,
        distanceRemaining: route.distance,
        durationRemaining: route.duration,
        isNavigating: true,
      ));

      // MapboxNavigationService: Navigation started with ${_currentSteps.length} steps');
      return true;
    } catch (e) {
      // MapboxNavigationService: Error starting navigation - $e');
      return false;
    }
  }

  /// Start tracking location and updating navigation
  void _startLocationTracking(double destLat, double destLng) {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!_isNavigating) {
        timer.cancel();
        return;
      }

      try {
        final position = await geo.Geolocator.getCurrentPosition();

        // Check if arrived at destination (within 30 meters)
        final distanceToDest = geo.Geolocator.distanceBetween(
          position.latitude, position.longitude,
          destLat, destLng,
        );

        if (distanceToDest < 30) {
          _emitUpdate(NavigationUpdate(
            currentStep: null,
            distanceRemaining: 0,
            durationRemaining: 0,
            isNavigating: false,
            hasArrived: true,
          ));
          stopNavigation();
          return;
        }

        // Update current step based on location
        _updateCurrentStep(position.latitude, position.longitude);

        // Emit update
        if (_currentStepIndex < _currentSteps.length) {
          _emitUpdate(NavigationUpdate(
            currentStep: _currentSteps[_currentStepIndex],
            distanceRemaining: distanceToDest,
            durationRemaining: (distanceToDest / 10).toDouble(), // Rough estimate
            isNavigating: true,
          ));
        }
      } catch (e) {
        // MapboxNavigationService: Location tracking error - $e');
      }
    });
  }

  /// Update current step based on driver location
  void _updateCurrentStep(double lat, double lng) {
    if (_currentStepIndex >= _currentSteps.length - 1) return;

    final nextStep = _currentSteps[_currentStepIndex + 1];
    if (nextStep.maneuverLocation != null) {
      final distanceToNextManeuver = geo.Geolocator.distanceBetween(
        lat, lng,
        nextStep.maneuverLocation!.latitude,
        nextStep.maneuverLocation!.longitude,
      );

      // If within 20 meters of next maneuver, advance step
      if (distanceToNextManeuver < 20) {
        _currentStepIndex++;
        // MapboxNavigationService: Advanced to step $_currentStepIndex');
      }
    }
  }

  void _emitUpdate(NavigationUpdate update) {
    if (_navigationController != null && !_navigationController!.isClosed) {
      _navigationController!.add(update);
    }
  }

  /// Stop the current navigation
  Future<void> stopNavigation() async {
    _isNavigating = false;
    _currentSteps = [];
    _currentStepIndex = 0;
    _locationTimer?.cancel();
    _navigationController?.close();
    // MapboxNavigationService: Navigation stopped');
  }

  /// Build a Mapbox map widget
  Widget buildMapWidget({
    required double initialLat,
    required double initialLng,
    double zoom = 15.0,
    void Function(MapboxMap)? onMapCreated,
    void Function(Point)? onTap,
  }) {
    return MapWidget(
      cameraOptions: CameraOptions(
        center: Point(coordinates: Position(initialLng, initialLat)),
        zoom: zoom,
        bearing: 0,
        pitch: 0,
      ),
      styleUri: MapboxStyles.STANDARD,
      onMapCreated: onMapCreated,
      onTapListener: onTap != null
          ? (context) => onTap(context.point)
          : null,
    );
  }

  /// Build a navigation map widget with 3D perspective
  Widget buildNavigationMapWidget({
    required double initialLat,
    required double initialLng,
    double bearing = 0,
    void Function(MapboxMap)? onMapCreated,
  }) {
    return MapWidget(
      cameraOptions: CameraOptions(
        center: Point(coordinates: Position(initialLng, initialLat)),
        zoom: 17.0,
        bearing: bearing,
        pitch: 60, // 3D perspective
      ),
      styleUri: MapboxStyles.DARK,
      onMapCreated: onMapCreated,
    );
  }

  /// Dispose the navigation service
  void dispose() {
    stopNavigation();
    // MapboxNavigationService: Disposed');
  }
}

/// Navigation update data
class NavigationUpdate {
  final NavigationStep? currentStep;
  final double distanceRemaining;
  final double durationRemaining;
  final bool isNavigating;
  final bool hasArrived;

  NavigationUpdate({
    this.currentStep,
    this.distanceRemaining = 0,
    this.durationRemaining = 0,
    this.isNavigating = false,
    this.hasArrived = false,
  });
}

/// Route from Mapbox Directions API
class MapboxRoute {
  final double distance; // meters
  final double duration; // seconds
  final List<NavigationStep> steps;
  final List<List<double>> geometry; // [lng, lat] pairs
  final List<String> congestion; // Traffic congestion per segment

  MapboxRoute({
    required this.distance,
    required this.duration,
    required this.steps,
    required this.geometry,
    this.congestion = const [],
  });

  factory MapboxRoute.fromJson(Map<String, dynamic> json) {
    final legs = json['legs'] as List? ?? [];
    final steps = <NavigationStep>[];
    final congestionList = <String>[];

    for (final leg in legs) {
      final legSteps = leg['steps'] as List? ?? [];
      for (final step in legSteps) {
        steps.add(NavigationStep.fromJson(step));
      }

      // Extract congestion data from annotations
      final annotations = leg['annotation'] as Map<String, dynamic>?;
      if (annotations != null && annotations['congestion'] != null) {
        final legCongestion = annotations['congestion'] as List? ?? [];
        for (final item in legCongestion) {
          congestionList.add(item.toString());
        }
      }
    }

    final geometryCoords = json['geometry']?['coordinates'] as List? ?? [];

    return MapboxRoute(
      distance: (json['distance'] as num?)?.toDouble() ?? 0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0,
      steps: steps,
      geometry: geometryCoords.map<List<double>>((c) =>
        [(c[0] as num).toDouble(), (c[1] as num).toDouble()]
      ).toList(),
      congestion: congestionList,
    );
  }
}

/// Navigation step (turn instruction)
class NavigationStep {
  final String instruction;
  final String? maneuverType; // turn, depart, arrive, etc.
  final String? maneuverModifier; // left, right, straight, etc.
  final double distance;
  final double duration;
  final NavCoordinate? maneuverLocation;
  final String? voiceInstruction;
  final String? bannerInstruction;

  NavigationStep({
    required this.instruction,
    this.maneuverType,
    this.maneuverModifier,
    this.distance = 0,
    this.duration = 0,
    this.maneuverLocation,
    this.voiceInstruction,
    this.bannerInstruction,
  });

  factory NavigationStep.fromJson(Map<String, dynamic> json) {
    final maneuver = json['maneuver'] as Map<String, dynamic>? ?? {};
    final location = maneuver['location'] as List?;

    // Get voice instruction if available
    String? voiceInstruction;
    final voiceInstructions = json['voiceInstructions'] as List?;
    if (voiceInstructions != null && voiceInstructions.isNotEmpty) {
      voiceInstruction = voiceInstructions[0]['announcement'] as String?;
    }

    // Get banner instruction if available
    String? bannerInstruction;
    final bannerInstructions = json['bannerInstructions'] as List?;
    if (bannerInstructions != null && bannerInstructions.isNotEmpty) {
      final primary = bannerInstructions[0]['primary'] as Map<String, dynamic>?;
      bannerInstruction = primary?['text'] as String?;
    }

    return NavigationStep(
      instruction: maneuver['instruction'] as String? ?? json['name'] as String? ?? '',
      maneuverType: maneuver['type'] as String?,
      maneuverModifier: maneuver['modifier'] as String?,
      distance: (json['distance'] as num?)?.toDouble() ?? 0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0,
      maneuverLocation: location != null && location.length >= 2
          ? NavCoordinate((location[1] as num).toDouble(), (location[0] as num).toDouble())
          : null,
      voiceInstruction: voiceInstruction,
      bannerInstruction: bannerInstruction,
    );
  }

  /// Get icon for this maneuver type
  IconData get maneuverIcon {
    switch (maneuverType) {
      case 'turn':
        if (maneuverModifier == 'left') return Icons.turn_left;
        if (maneuverModifier == 'right') return Icons.turn_right;
        if (maneuverModifier == 'slight left') return Icons.turn_slight_left;
        if (maneuverModifier == 'slight right') return Icons.turn_slight_right;
        if (maneuverModifier == 'sharp left') return Icons.turn_sharp_left;
        if (maneuverModifier == 'sharp right') return Icons.turn_sharp_right;
        return Icons.straight;
      case 'depart':
        return Icons.trip_origin;
      case 'arrive':
        return Icons.flag;
      case 'merge':
        return Icons.merge;
      case 'fork':
        return Icons.fork_right;
      case 'roundabout':
        return Icons.roundabout_left;
      case 'rotary':
        return Icons.roundabout_right;
      default:
        return Icons.straight;
    }
  }
}

/// Simple coordinate class for navigation
class NavCoordinate {
  final double latitude;
  final double longitude;

  NavCoordinate(this.latitude, this.longitude);
}
