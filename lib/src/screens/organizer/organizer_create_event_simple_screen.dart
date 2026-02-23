import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import '../../providers/auth_provider.dart';
import '../../providers/driver_provider.dart';
import '../../config/supabase_config.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';
import '../../widgets/scrollable_time_picker.dart';
import '../../services/tourism_event_service.dart';
import '../../services/organizer_service.dart';
import '../../core/logging/app_logger.dart';
import 'organizer_bidding_screen.dart';

/// Event Stop Model - Represents a stop in the event itinerary
class EventStop {
  final String id;
  String name;
  double? lat;
  double? lng;
  DateTime? estimatedArrival; // Changed from TimeOfDay to DateTime
  int? durationMinutes;
  String? notes;
  int stopOrder;

  EventStop({
    String? id,
    required this.name,
    this.lat,
    this.lng,
    this.estimatedArrival,
    this.durationMinutes,
    this.notes,
    required this.stopOrder,
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lat': lat,
        'lng': lng,
        'estimatedArrival': estimatedArrival?.toIso8601String(),
        'durationMinutes': durationMinutes,
        'notes': notes,
        'stopOrder': stopOrder,
      };
}

/// Simplified event creation screen - all in one scrollable form
class OrganizerCreateEventSimpleScreen extends StatefulWidget {
  final String? preSelectedVehicleId;
  final String? serviceType; // fixed_route, tourism, special_event, shared_trip

  const OrganizerCreateEventSimpleScreen({
    super.key,
    this.preSelectedVehicleId,
    this.serviceType,
  });

  @override
  State<OrganizerCreateEventSimpleScreen> createState() =>
      _OrganizerCreateEventSimpleScreenState();
}

class _OrganizerCreateEventSimpleScreenState
    extends State<OrganizerCreateEventSimpleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _maxPassengersController = TextEditingController();
  // _pricePerPersonController removed - price set by driver via bidding

  // Services
  final _organizerService = OrganizerService();

  // Route/Area controllers
  final _areaCenterController = TextEditingController();
  final _areaRadiusController = TextEditingController();
  final _distanceKmController = TextEditingController();

  final TourismEventService _tourismService = TourismEventService();

  // Basic info
  String _eventType = 'tour';
  DateTime _eventDate = DateTime.now().add(const Duration(days: 7));
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);

  // Service type
  String _serviceType = 'route'; // 'route' or 'area'

  // Vehicle selection
  List<Map<String, dynamic>> _vehicles = [];
  Map<String, dynamic>? _selectedVehicle;
  bool _loadingVehicles = true;
  String? _organizerId;

  // Vehicle wizard: null = not answered, true = has own vehicle, false = dispatcher/organizer
  bool? _hasOwnVehicle;

  // Itinerary - Multiple stops system
  List<EventStop> _stops = [];
  bool _isRoundTrip = false;

  // Saved defaults (SharedPreferences keys) - Template System
  static const String _savedVehicleIdKey = 'organizer_last_vehicle_id';
  static const String _savedEventTypeKey = 'organizer_last_event_type';
  static const String _savedServiceTypeKey = 'organizer_last_service_type';

  // Itinerary section
  static const String _savedStopsKey = 'organizer_last_stops';
  static const String _savedIsRoundTripKey = 'organizer_last_is_round_trip';
  static const String _savedStartTimeKey = 'organizer_last_start_time';
  static const String _savedDistanceKmKey = 'organizer_last_distance_km';

  static const String _savedMaxPassengersKey = 'organizer_last_max_passengers';
  static const String _savedHasOwnVehicleKey = 'organizer_has_own_vehicle';

  // Description section
  static const String _savedDescriptionKey = 'organizer_last_description';

  // Road distance calculation
  bool _calculatingDistance = false;
  double? _realDistanceKm;
  String? _distanceSource; // 'osrm', 'manual', or null

  // Pricing removed - driver sets price via bidding

  // Organizer contact info (business card / credencial)
  final _contactEmailController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _contactFacebookController = TextEditingController();
  String? _companyLogoUrl;
  Map<String, dynamic>? _organizerProfile; // Full organizer data
  bool _loadingOrganizerProfile = true;
  bool _contactInfoExpanded = true; // true if no data saved yet, false = compact card
  bool _savingCredential = false;

  // Help tooltip expansion state per section
  final Set<String> _expandedHelp = {};
  // Commission legal disclaimer expanded
  bool _feeDisclaimerExpanded = false;

  // Editable seat count per event
  final _eventSeatsController = TextEditingController();

  // Visibility toggle for "Otro" type
  bool _isOtherTypePublic = false;
  // Bid visibility: public (any driver can bid) or private (only invited)
  bool _isBidPublic = true;
  // Search radius configurable by creator (1-5km, only for public events)
  double _searchRadiusKm = 3.0;

  // Event types with visibility rules and descriptions
  static const _eventTypes = [
    {
      'value': 'tour',
      'label': 'Tour',
      'icon': Icons.tour,
      'visibility': 'private',
      'desc': 'Evento privado. Pasajeros se unen solo por invitacion. Puedes invitar de otros estados.',
    },
    {
      'value': 'charter',
      'label': 'Transporte Publico',
      'icon': Icons.directions_bus,
      'visibility': 'public',
      'desc': 'Evento publico tipo autobus. Los pasajeros cercanos al chofer en ruta pueden solicitar abordaje dentro del radio que configures (max 5km).',
    },
    {
      'value': 'excursion',
      'label': 'Excursion',
      'icon': Icons.hiking,
      'visibility': 'private',
      'desc': 'Evento privado. Solo pasajeros invitados.',
    },
    {
      'value': 'corporate',
      'label': 'Corporativo',
      'icon': Icons.business,
      'visibility': 'private',
      'desc': 'Evento privado empresarial. Solo invitaciones de la organizacion.',
    },
    {
      'value': 'wedding',
      'label': 'Boda',
      'icon': Icons.favorite,
      'visibility': 'private',
      'desc': 'Evento privado. El organizador selecciona a los invitados.',
    },
    {
      'value': 'other',
      'label': 'Otro',
      'icon': Icons.category,
      'visibility': null, // toggle
      'desc': 'Personalizable. Puedes elegir si el evento es publico o privado.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _applyServiceTypePreset();
    _loadSavedDefaults();
    _loadOrganizerAndVehicles();
  }

  String get _appBarTitle {
    switch (widget.serviceType) {
      case 'fixed_route': return 'Nueva Ruta';
      case 'tourism': return 'Nuevo Tour';
      case 'special_event': return 'Nuevo Evento';
      case 'shared_trip': return 'Nuevo Viaje';
      default: return 'Crear Evento';
    }
  }

  /// Pre-configure event type based on the service card the user tapped
  void _applyServiceTypePreset() {
    final st = widget.serviceType;
    if (st == null) return;
    switch (st) {
      case 'fixed_route':
        _eventType = 'charter';
        _serviceType = 'route';
        break;
      case 'tourism':
        _eventType = 'tour';
        _serviceType = 'route';
        break;
      case 'special_event':
        _eventType = 'other';
        _serviceType = 'route';
        break;
      case 'shared_trip':
        _eventType = 'charter';
        _serviceType = 'route';
        _isBidPublic = true;
        break;
    }
  }

  /// Load saved defaults from SharedPreferences (Template System)
  Future<void> _loadSavedDefaults() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      setState(() {
        // Event type and service type
        _eventType = prefs.getString(_savedEventTypeKey) ?? 'tour';
        _serviceType = prefs.getString(_savedServiceTypeKey) ?? 'route';

        // Itinerary section
        final stopsJson = prefs.getString(_savedStopsKey);
        if (stopsJson != null && stopsJson.isNotEmpty) {
          try {
            final List<dynamic> stopsList = jsonDecode(stopsJson);
            _stops = stopsList
                .map((s) => EventStop(
                      id: s['id'],
                      name: s['name'] ?? '',
                      lat: s['lat'],
                      lng: s['lng'],
                      estimatedArrival: s['estimatedArrival'] != null
                          ? DateTime.tryParse(s['estimatedArrival'])
                          : null,
                      durationMinutes: s['durationMinutes'],
                      notes: s['notes'],
                      stopOrder: s['stopOrder'] ?? 0,
                    ))
                .toList();
          } catch (e) {
            AppLogger.log('Error parsing saved stops: $e');
          }
        }

        _isRoundTrip = prefs.getBool(_savedIsRoundTripKey) ?? false;

        // Start time
        final savedStartTime = prefs.getString(_savedStartTimeKey);
        if (savedStartTime != null) {
          try {
            final timeParts = savedStartTime.split(':');
            if (timeParts.length == 2) {
              _startTime = TimeOfDay(
                hour: int.parse(timeParts[0]),
                minute: int.parse(timeParts[1]),
              );
            }
          } catch (e) {
            AppLogger.log('Error parsing saved start time: $e');
          }
        }

        // Distance
        final savedDistance = prefs.getDouble(_savedDistanceKmKey);
        if (savedDistance != null) {
          _distanceKmController.text = savedDistance.toStringAsFixed(1);
          _realDistanceKm = savedDistance;
        }

        final savedPassengers = prefs.getInt(_savedMaxPassengersKey);
        if (savedPassengers != null) {
          _maxPassengersController.text = savedPassengers.toString();
        }

        // Description
        final savedDescription = prefs.getString(_savedDescriptionKey);
        if (savedDescription != null && savedDescription.isNotEmpty) {
          _descriptionController.text = savedDescription;
        }

        // Vehicle wizard preference
        if (prefs.containsKey(_savedHasOwnVehicleKey)) {
          _hasOwnVehicle = prefs.getBool(_savedHasOwnVehicleKey);
        }
      });

      AppLogger.log('Template loaded: ${_stops.length} stops, passengers: ${_maxPassengersController.text}');
    } catch (e) {
      AppLogger.log('Error loading saved defaults: $e');
    }
  }

  /// Save all sections as template for next event (Template System)
  Future<void> _saveDefaults() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Vehicle and event type (already working)
      if (_selectedVehicle != null) {
        await prefs.setString(_savedVehicleIdKey, _selectedVehicle!['id'] as String);
      }
      await prefs.setString(_savedEventTypeKey, _eventType);
      await prefs.setString(_savedServiceTypeKey, _serviceType);

      // Itinerary section - Save all stops as JSON
      if (_stops.isNotEmpty) {
        final stopsJson = jsonEncode(_stops.map((s) => s.toJson()).toList());
        await prefs.setString(_savedStopsKey, stopsJson);
      } else {
        await prefs.remove(_savedStopsKey); // Clear if no stops
      }

      await prefs.setBool(_savedIsRoundTripKey, _isRoundTrip);

      // Start time
      final timeString = '${_startTime.hour}:${_startTime.minute}';
      await prefs.setString(_savedStartTimeKey, timeString);

      // Distance
      if (_realDistanceKm != null) {
        await prefs.setDouble(_savedDistanceKmKey, _realDistanceKm!);
      } else if (_distanceKmController.text.isNotEmpty) {
        final distance = double.tryParse(_distanceKmController.text.trim());
        if (distance != null) {
          await prefs.setDouble(_savedDistanceKmKey, distance);
        }
      }

      if (_maxPassengersController.text.isNotEmpty) {
        final passengers = int.tryParse(_maxPassengersController.text.trim());
        if (passengers != null) {
          await prefs.setInt(_savedMaxPassengersKey, passengers);
        }
      }

      // Description section
      if (_descriptionController.text.trim().isNotEmpty) {
        await prefs.setString(_savedDescriptionKey, _descriptionController.text.trim());
      }

      AppLogger.log('Template saved: ${_stops.length} stops, ${_maxPassengersController.text} passengers');
    } catch (e) {
      AppLogger.log('Error saving defaults: $e');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _maxPassengersController.dispose();
    _areaCenterController.dispose();
    _areaRadiusController.dispose();
    _distanceKmController.dispose();
    _contactEmailController.dispose();
    _contactPhoneController.dispose();
    _contactFacebookController.dispose();
    _eventSeatsController.dispose();
    super.dispose();
  }

  Future<void> _loadOrganizerAndVehicles() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.driver?.id;

    if (userId == null) return;

    setState(() {
      _loadingVehicles = true;
      _loadingOrganizerProfile = true;
    });

    try {
      // Get or create organizer with full profile
      var organizerData = await SupabaseConfig.client
          .from('organizers')
          .select('*, profiles:user_id(*)')
          .eq('user_id', userId)
          .maybeSingle();

      // Auto-create organizer if needed
      organizerData ??= await SupabaseConfig.client
          .from('organizers')
          .insert({
            'user_id': userId,
            'created_at': DateTime.now().toIso8601String(),
          })
          .select('*, profiles:user_id(*)')
          .single();

      _organizerId = organizerData['id'] as String;

      // Load organizer profile data
      final hasEmail = (organizerData['contact_email'] as String?)?.isNotEmpty == true;
      final hasPhone = (organizerData['contact_phone'] as String?)?.isNotEmpty == true;
      final hasFacebook = (organizerData['contact_facebook'] as String?)?.isNotEmpty == true;
      final hasLogo = (organizerData['company_logo_url'] as String?)?.isNotEmpty == true;
      final hasAnyContactData = hasEmail || hasPhone || hasFacebook || hasLogo;

      setState(() {
        _organizerProfile = organizerData;
        _contactEmailController.text = (organizerData?['contact_email'] as String?) ?? '';
        _contactPhoneController.text = (organizerData?['contact_phone'] as String?) ?? '';
        _contactFacebookController.text = (organizerData?['contact_facebook'] as String?) ?? '';
        _companyLogoUrl = organizerData?['company_logo_url'] as String?;
        _loadingOrganizerProfile = false;
        // If organizer already has contact data saved, show compact card
        _contactInfoExpanded = !hasAnyContactData;
      });

      // Load vehicles from bus_vehicles
      // Organizador puede ver TODOS los vehículos disponibles
      final vehicles = await SupabaseConfig.client
          .from('bus_vehicles')
          .select('*')
          .eq('is_active', true)
          .eq('available_for_tourism', true);

      setState(() {
        _vehicles = List<Map<String, dynamic>>.from(vehicles);
        _loadingVehicles = false;

        // Pre-select vehicle priority:
        // 1. If preSelectedVehicleId provided
        if (widget.preSelectedVehicleId != null) {
          final match = _vehicles.where(
            (v) => v['id'] == widget.preSelectedVehicleId,
          );
          _selectedVehicle = match.isNotEmpty ? match.first : null;
        }
        // 2. If user has own vehicles, auto-select first one
        else {
          final ownVehicles = _vehicles.where((v) => v['owner_id'] == userId).toList();
          if (ownVehicles.isNotEmpty) {
            _selectedVehicle = ownVehicles.first;
            // Auto-detect: driver has own vehicles → set wizard to true
            if (_hasOwnVehicle == null) {
              _hasOwnVehicle = true;
            }
          } else {
            // 3. Try to load saved vehicle from SharedPreferences
            _loadSavedVehicle();
          }
        }
      });
    } catch (e) {
      AppLogger.log('Error loading vehicles: $e');
      setState(() => _loadingVehicles = false);
    }
  }

  /// Save organizer contact info to database
  Future<void> _saveOrganizerContactInfo() async {
    if (_organizerId == null) return;

    try {
      await SupabaseConfig.client.from('organizers').update({
        'contact_email': _contactEmailController.text.trim().isEmpty
            ? null
            : _contactEmailController.text.trim(),
        'contact_phone': _contactPhoneController.text.trim().isEmpty
            ? null
            : _contactPhoneController.text.trim(),
        'contact_facebook': _contactFacebookController.text.trim().isEmpty
            ? null
            : _contactFacebookController.text.trim(),
        'company_logo_url': _companyLogoUrl,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', _organizerId!);

      AppLogger.log('Organizer contact info saved successfully');
    } catch (e) {
      AppLogger.log('Error saving organizer contact info: $e');
    }
  }

  /// Upload company logo (business card image)
  Future<void> _uploadCompanyLogo() async {
    if (_organizerId == null) {
      _showError('Error: No se encontró el organizador');
      return;
    }

    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image == null) return;

      // Show loading
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );

      // Read bytes from XFile (works on web & mobile)
      final imageBytes = await image.readAsBytes();

      // Upload using service
      final newUrl = await _organizerService.uploadCompanyLogo(
        _organizerId!,
        image.path,
        bytes: imageBytes,
      );

      if (mounted) Navigator.pop(context); // Close loading

      if (newUrl != null) {
        setState(() => _companyLogoUrl = newUrl);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Logo subido exitosamente'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) _showError('Error al subir el logo');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context); // Close loading if still open
      AppLogger.log('Error uploading company logo: $e');
      if (mounted) _showError('Error al subir el logo: $e');
    }
  }

  Future<void> _createEvent() async {
    if (!_formKey.currentState!.validate()) return;
    if (_organizerId == null) {
      _showError('Error: No se pudo obtener el ID de organizador');
      return;
    }

    // Validate itinerary for route service type
    if (_serviceType == 'route' && _stops.length < 2) {
      _showError('Agrega al menos 2 paradas (origen y destino)');
      return;
    }

    // Validate seats
    final eventSeats = int.tryParse(_eventSeatsController.text);
    if (eventSeats == null || eventSeats <= 0) {
      _showError('Indica cuántos asientos necesitas');
      return;
    }

    HapticService.lightImpact();

    try {
      // Save organizer contact info first
      await _saveOrganizerContactInfo();

      // Convert stops to JSON for itinerary field
      final itineraryJson = _stops.map((stop) => stop.toJson()).toList();

      // Auto-set visibility based on event type
      String passengerVisibility;
      if (_eventType == 'charter') {
        passengerVisibility = 'public';
      } else if (_eventType == 'other') {
        passengerVisibility = _isOtherTypePublic ? 'public' : 'private';
      } else {
        passengerVisibility = 'private';
      }

      // Determine if driver is posting with own vehicle
      final bool postingWithOwnVehicle = _hasOwnVehicle == true && _selectedVehicle != null;
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentDriverId = authProvider.driver?.id;

      final eventData = {
        'organizer_id': _organizerId,
        'event_name': _nameController.text.trim(),
        'event_type': _eventType,
        'event_description': _descriptionController.text.trim(),
        'event_date': _eventDate.toIso8601String().split('T')[0],
        'start_time': '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}:00',
        'max_passengers': eventSeats,
        'price_per_km': 0,
        'total_distance_km': _realDistanceKm,
        'itinerary': itineraryJson,
        'passenger_visibility': passengerVisibility,
        'bid_visibility': _isBidPublic ? 'public' : 'private',
        // If posting with own vehicle: active + assigned; otherwise: draft waiting for bids
        'status': postingWithOwnVehicle ? 'active' : 'draft',
        if (postingWithOwnVehicle) 'vehicle_id': _selectedVehicle!['id'],
        if (postingWithOwnVehicle && currentDriverId != null) 'driver_id': currentDriverId,
        if (postingWithOwnVehicle) 'vehicle_request_status': 'accepted',
        'country_code': authProvider.driver?.countryCode ?? 'US',
        'created_at': DateTime.now().toIso8601String(),
      };

      final result = await SupabaseConfig.client
          .from('tourism_events')
          .insert(eventData)
          .select()
          .single();

      if (mounted) {
        // Save defaults for next time
        await _saveDefaults();
        if (!mounted) return;

        final eventId = result['id'] as String?;

        // Show success dialog based on mode
        if (postingWithOwnVehicle) {
          // Own vehicle: event is active immediately
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: AppColors.success, size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Evento Publicado',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              content: const Text(
                'Tu evento está activo con tu vehículo. Los pasajeros ya pueden verlo y reservar.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: const Text('Listo', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          );

          if (!mounted) return;
          Navigator.pop(context, result);
        } else {
          // Dispatcher mode: waiting for driver bids
          final inviteDrivers = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: AppColors.success, size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Esperando Puja',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tu evento ya es visible para todos los choferes. Ellos pueden enviarte pujas con su precio.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.gold.withValues(alpha: 0.2)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.person_add, color: AppColors.gold, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Tambien puedes invitar choferes directamente si no recibes pujas.',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Listo', style: TextStyle(color: AppColors.textTertiary)),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.person_add, size: 16),
                  label: const Text('Invitar Choferes', style: TextStyle(fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          );

          if (!mounted) return;

          if (inviteDrivers == true && eventId != null) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => OrganizerBiddingScreen(eventId: eventId)),
            );
          } else {
            Navigator.pop(context, result);
          }
        }
      }
    } catch (e) {
      if (mounted) _showError('Error al crear evento: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  /// Load saved vehicle selection from SharedPreferences
  Future<void> _loadSavedVehicle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedVehicleId = prefs.getString(_savedVehicleIdKey);

      if (savedVehicleId != null && _vehicles.isNotEmpty) {
        final savedVehicle = _vehicles.where((v) => v['id'] == savedVehicleId).firstOrNull;
        if (savedVehicle != null) {
          setState(() {
            _selectedVehicle = savedVehicle;
          });
        }
      }
    } catch (e) {
      AppLogger.log('Error loading saved vehicle: $e');
    }
  }

  /// Calculate real road distance using OSRM API (Open Source Routing Machine)
  /// This is called automatically when both origin and destination are selected
  /// Calculate road distance between two points using OSRM API
  Future<double?> _calculateRoadDistance(double lat1, double lng1, double lat2, double lng2) async {
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '$lng1,$lat1;$lng2,$lat2'
        '?overview=false&alternatives=false&steps=false',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['code'] == 'Ok' && data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];
          final distanceMeters = route['distance'] as num;
          final distanceKm = (distanceMeters / 1000).toDouble();
          return distanceKm;
        }
      }
      return null;
    } catch (e) {
      AppLogger.log('Error calculating road distance: $e');
      return null;
    }
  }

  /// Get coordinates for known Mexican cities
  /// Extracts city name from addresses like "walmart mexicali" or "plaza tijuana"
  Map<String, double>? _getKnownCityCoordinates(String address) {
    final text = address.toLowerCase().trim();

    // Major Mexican cities coordinates
    const cities = {
      'mexicali': {'lat': 32.6519, 'lng': -115.4683},
      'tijuana': {'lat': 32.5027, 'lng': -117.0038},
      'ensenada': {'lat': 31.8667, 'lng': -116.6167},
      'san felipe': {'lat': 31.0244, 'lng': -114.8377},
      'tecate': {'lat': 32.5773, 'lng': -116.6283},
      'rosarito': {'lat': 32.3333, 'lng': -117.0333},
      'cdmx': {'lat': 19.4326, 'lng': -99.1332},
      'ciudad de mexico': {'lat': 19.4326, 'lng': -99.1332},
      'guadalajara': {'lat': 20.6597, 'lng': -103.3496},
      'monterrey': {'lat': 25.6866, 'lng': -100.3161},
      'cancun': {'lat': 21.1619, 'lng': -86.8515},
      'playa del carmen': {'lat': 20.6296, 'lng': -87.0739},
      'los cabos': {'lat': 22.8905, 'lng': -109.9167},
      'cabo san lucas': {'lat': 22.8905, 'lng': -109.9167},
      'la paz': {'lat': 24.1426, 'lng': -110.3128},
      'hermosillo': {'lat': 29.0729, 'lng': -110.9559},
      'ciudad juarez': {'lat': 31.6904, 'lng': -106.4245},
      'chihuahua': {'lat': 28.6353, 'lng': -106.0889},
      'queretaro': {'lat': 20.5888, 'lng': -100.3899},
      'puebla': {'lat': 19.0414, 'lng': -98.2063},
      'merida': {'lat': 20.9674, 'lng': -89.5926},
      'acapulco': {'lat': 16.8531, 'lng': -99.8237},
      'mazatlan': {'lat': 23.2494, 'lng': -106.4111},
      'puerto vallarta': {'lat': 20.6534, 'lng': -105.2253},
      'tepic': {'lat': 21.5069, 'lng': -104.8946},
      'compostela': {'lat': 21.2366, 'lng': -104.9000},
      'san blas': {'lat': 21.5403, 'lng': -105.2842},
      'sayulita': {'lat': 20.8690, 'lng': -105.4414},
      'rincon de guayabitos': {'lat': 21.0283, 'lng': -105.2578},
      'leon': {'lat': 21.1221, 'lng': -101.6822},
      'irapuato': {'lat': 20.6740, 'lng': -101.3566},
      'celaya': {'lat': 20.5236, 'lng': -100.8159},
      'san luis potosi': {'lat': 22.1565, 'lng': -100.9855},
      'aguascalientes': {'lat': 21.8818, 'lng': -102.2916},
      'morelia': {'lat': 19.7060, 'lng': -101.1950},
      'oaxaca': {'lat': 17.0732, 'lng': -96.7266},
      'villahermosa': {'lat': 17.9894, 'lng': -92.9475},
      'tuxtla gutierrez': {'lat': 16.7528, 'lng': -93.1152},
      'colima': {'lat': 19.2453, 'lng': -103.7246},
      'manzanillo': {'lat': 19.1104, 'lng': -104.3231},
      'durango': {'lat': 24.0277, 'lng': -104.6532},
      'zacatecas': {'lat': 22.7709, 'lng': -102.5832},
      'torreon': {'lat': 25.5428, 'lng': -103.4068},
      'saltillo': {'lat': 25.4232, 'lng': -100.9932},
      'tampico': {'lat': 22.2331, 'lng': -97.8614},
      'veracruz': {'lat': 19.1738, 'lng': -96.1342},
      'xalapa': {'lat': 19.5438, 'lng': -96.9102},
      'pachuca': {'lat': 20.1011, 'lng': -98.7591},
      'toluca': {'lat': 19.2826, 'lng': -99.6557},
      'cuernavaca': {'lat': 18.9242, 'lng': -99.2216},
      'taxco': {'lat': 18.5565, 'lng': -99.6051},
    };

    // Try to extract city name from address
    // Works for: "walmart mexicali", "plaza sendero tijuana", "aeropuerto ensenada"
    for (final entry in cities.entries) {
      if (text.contains(entry.key)) {
        return entry.value;
      }
    }

    // Also try if the whole text is a city name (backwards compatibility)
    for (final entry in cities.entries) {
      if (entry.key.contains(text) || text.contains(entry.key)) {
        return entry.value;
      }
    }

    return null;
  }

  /// Geocode a stop name to get coordinates.
  /// First tries known cities, then Nominatim API.
  Future<Map<String, double>?> _geocodeStopName(String name) async {
    if (name.trim().isEmpty) return null;

    // 1) Try known cities first (instant)
    final known = _getKnownCityCoordinates(name);
    if (known != null) return known;

    // 2) Try Nominatim geocoding API
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(name)}'
        '&format=jsonv2'
        '&countrycodes=mx,us'
        '&limit=1'
        '&accept-language=es',
      );
      final response = await http.get(url, headers: {'User-Agent': 'TORORide/1.0'})
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final results = json.decode(response.body) as List;
        if (results.isNotEmpty) {
          return {
            'lat': double.parse(results[0]['lat'].toString()),
            'lng': double.parse(results[0]['lon'].toString()),
          };
        }
      }
    } catch (e) {
      debugPrint('Geocode stop name error: $e');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _appBarTitle,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Section 1: Credencial del Organizador (TOP - persists independently)
              _buildSectionHeader(
                icon: Icons.badge,
                title: 'org_section_credencial'.tr(),
                helpKey: 'credencial',
                helpText: 'org_help_credencial'.tr(),
              ),
              const SizedBox(height: 16),
              _buildContactInfoSection(),
              const SizedBox(height: 32),

              // Section 2: Basic Info
              _buildSectionHeader(
                icon: Icons.event,
                title: 'org_section_info_basica'.tr(),
                helpKey: 'info_basica',
                helpText: 'org_help_info_basica'.tr(),
              ),
              const SizedBox(height: 16),
              _buildBasicInfoSection(),
              const SizedBox(height: 32),

              // Section 3: Capacity
              _buildSectionHeader(
                icon: Icons.event_seat,
                title: 'org_section_capacidad'.tr(),
                helpKey: 'capacidad',
                helpText: 'org_help_capacidad'.tr(),
              ),
              const SizedBox(height: 16),
              _buildCapacitySection(),
              const SizedBox(height: 32),

              // Section 4: Bid Visibility (public/private)
              _buildSectionHeader(
                icon: Icons.gavel_rounded,
                title: 'org_section_tipo_puja'.tr(),
                helpKey: 'tipo_puja',
                helpText: 'org_help_tipo_puja'.tr(),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _isBidPublic = true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _isBidPublic
                                    ? AppColors.success.withValues(alpha: 0.15)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _isBidPublic
                                      ? AppColors.success
                                      : AppColors.border,
                                  width: _isBidPublic ? 1.5 : 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.public,
                                    color: _isBidPublic
                                        ? AppColors.success
                                        : AppColors.textTertiary,
                                    size: 24,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'org_bid_public'.tr(),
                                    style: TextStyle(
                                      color: _isBidPublic
                                          ? AppColors.success
                                          : AppColors.textTertiary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _isBidPublic = false),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: !_isBidPublic
                                    ? Colors.orange.withValues(alpha: 0.15)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: !_isBidPublic
                                      ? Colors.orange
                                      : AppColors.border,
                                  width: !_isBidPublic ? 1.5 : 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.lock_outline,
                                    color: !_isBidPublic
                                        ? Colors.orange
                                        : AppColors.textTertiary,
                                    size: 24,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'org_bid_private'.tr(),
                                    style: TextStyle(
                                      color: !_isBidPublic
                                          ? Colors.orange
                                          : AppColors.textTertiary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isBidPublic
                          ? 'org_bid_public_desc'.tr()
                          : 'org_bid_private_desc'.tr(),
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Create Button
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _createEvent,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'org_create_event'.tr(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    String? helpKey,
    String? helpText,
  }) {
    final isHelpOpen = helpKey != null && _expandedHelp.contains(helpKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: AppColors.primary, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (helpKey != null && helpText != null)
              GestureDetector(
                onTap: () {
                  HapticService.lightImpact();
                  setState(() {
                    if (_expandedHelp.contains(helpKey)) {
                      _expandedHelp.remove(helpKey);
                    } else {
                      _expandedHelp.add(helpKey);
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isHelpOpen
                        ? AppColors.primary.withValues(alpha: 0.15)
                        : AppColors.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isHelpOpen ? AppColors.primary : AppColors.border,
                    ),
                  ),
                  child: Icon(
                    isHelpOpen ? Icons.close : Icons.help_outline,
                    color: isHelpOpen ? AppColors.primary : AppColors.textTertiary,
                    size: 18,
                  ),
                ),
              ),
          ],
        ),
        if (isHelpOpen && helpText != null)
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline, color: AppColors.gold, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      helpText,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBasicInfoSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Event Name
          TextFormField(
            controller: _nameController,
            style: TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              labelText: 'org_event_name'.tr(),
              labelStyle: TextStyle(color: AppColors.textSecondary),
              prefixIcon: Icon(Icons.title, color: AppColors.textSecondary),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.border),
              ),
            ),
            validator: (value) =>
                value?.isEmpty ?? true ? 'org_event_name_required'.tr() : null,
          ),
          const SizedBox(height: 16),

          // Event Type
          Text(
            'org_event_type'.tr(),
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _eventTypes.map((type) {
              final isSelected = _eventType == type['value'];
              return ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      type['icon'] as IconData,
                      size: 16,
                      color: isSelected ? Colors.white : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(type['label'] as String),
                  ],
                ),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _eventType = type['value'] as String;
                      _isOtherTypePublic = false;
                      _searchRadiusKm = 3.0;
                    });
                  }
                },
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.card,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          // Event type description box
          Builder(builder: (_) {
            final selectedType = _eventTypes.firstWhere(
              (t) => t['value'] == _eventType,
              orElse: () => _eventTypes.first,
            );
            final desc = selectedType['desc'] as String? ?? '';
            final visibility = selectedType['visibility'] as String?;
            final isPublic = _eventType == 'charter' ||
                (_eventType == 'other' && _isOtherTypePublic);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Info box with description
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          desc,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Toggle for "Otro" type
                if (visibility == null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isOtherTypePublic
                              ? Icons.public
                              : Icons.lock_outline,
                          size: 18,
                          color: _isOtherTypePublic
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _isOtherTypePublic
                                ? 'org_visibility_public'.tr()
                                : 'org_visibility_private'.tr(),
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Switch(
                          value: _isOtherTypePublic,
                          onChanged: (v) =>
                              setState(() => _isOtherTypePublic = v),
                          activeColor: AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                ],

                // Search radius slider (only for public events)
                if (isPublic) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.radar, size: 16,
                                color: AppColors.primary),
                            const SizedBox(width: 6),
                            Text(
                              'org_search_radius'.tr(namedArgs: {'radius': _searchRadiusKm.toStringAsFixed(1)}),
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'org_search_radius_desc'.tr(),
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                        Slider(
                          value: _searchRadiusKm,
                          min: 1.0,
                          max: 5.0,
                          divisions: 8,
                          activeColor: AppColors.primary,
                          inactiveColor:
                              AppColors.primary.withValues(alpha: 0.2),
                          label: '${_searchRadiusKm.toStringAsFixed(1)} km',
                          onChanged: (v) =>
                              setState(() => _searchRadiusKm = v),
                        ),
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Text('1 km',
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 10)),
                            Text('5 km',
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 10)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          }),
          const SizedBox(height: 16),

          // Service Type
          Text(
            'org_service_type'.tr(),
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.route, size: 16, color: Colors.white),
                      const SizedBox(width: 4),
                      Text('org_route_fixed'.tr()),
                    ],
                  ),
                  selected: _serviceType == 'route',
                  onSelected: (selected) {
                    if (selected) setState(() => _serviceType = 'route');
                  },
                  selectedColor: AppColors.primary,
                  backgroundColor: AppColors.card,
                  labelStyle: TextStyle(
                    color: _serviceType == 'route' ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ChoiceChip(
                  label: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.location_on, size: 16, color: Colors.white),
                      const SizedBox(width: 4),
                      Text('org_area_free'.tr()),
                    ],
                  ),
                  selected: _serviceType == 'area',
                  onSelected: (selected) {
                    if (selected) setState(() => _serviceType = 'area');
                  },
                  selectedColor: AppColors.primary,
                  backgroundColor: AppColors.card,
                  labelStyle: TextStyle(
                    color: _serviceType == 'area' ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Route fields (if service type is route)
          if (_serviceType == 'route') ...[
            // Itinerary Section Header
            Row(
              children: [
                Icon(Icons.route, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'org_itinerary'.tr(),
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (_stops.length >= 2)
                  Text(
                    '${_stops.length} paradas',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Stops List
            if (_stops.isEmpty)
              _buildEmptyStopsPlaceholder()
            else
              _buildStopsList(),

            const SizedBox(height: 12),

            // Add Stop Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: _addNewStop,
                icon: Icon(Icons.add_location_alt, size: 20),
                label: Text(_stops.isEmpty
                    ? 'org_add_origin'.tr()
                    : _stops.length == 1
                        ? 'org_add_destination'.tr()
                        : 'org_next_stop'.tr()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(color: AppColors.primary, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),

            // Round Trip Toggle
            if (_stops.length >= 2) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.swap_horiz, color: AppColors.textSecondary, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'org_round_trip'.tr(),
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'org_round_trip_desc'.tr(),
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isRoundTrip,
                      onChanged: (value) {
                        setState(() => _isRoundTrip = value);
                        if (value) _addReturnTrip();
                        HapticService.lightImpact();
                      },
                      activeColor: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ],

            // Total Distance Display
            if (_stops.length >= 2) ...[
              const SizedBox(height: 12),
              if (_calculatingDistance)
                _buildCalculatingDistanceIndicator()
              else if (_realDistanceKm != null)
                _buildDistanceDisplay(),
            ],

            const SizedBox(height: 16),
          ],

          // Area fields (if service type is area)
          if (_serviceType == 'area') ...[
            TextFormField(
              controller: _areaCenterController,
              style: TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'org_area_center'.tr(),
                labelStyle: TextStyle(color: AppColors.textSecondary),
                hintText: 'org_area_center_hint'.tr(),
                hintStyle: TextStyle(color: AppColors.textTertiary),
                prefixIcon: Icon(Icons.my_location, color: AppColors.textSecondary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.border),
                ),
              ),
              validator: (value) =>
                  value?.isEmpty ?? true ? 'org_area_center_required'.tr() : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _areaRadiusController,
              style: TextStyle(color: AppColors.textPrimary),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'org_area_radius'.tr(),
                labelStyle: TextStyle(color: AppColors.textSecondary),
                hintText: 'org_area_radius_hint'.tr(),
                hintStyle: TextStyle(color: AppColors.textTertiary),
                prefixIcon: Icon(Icons.radar, color: AppColors.textSecondary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.border),
                ),
              ),
              validator: (value) =>
                  value?.isEmpty ?? true ? 'org_area_radius_required'.tr() : null,
            ),
            const SizedBox(height: 16),
          ],


          // Event Date
          InkWell(
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _eventDate,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (date != null) {
                setState(() => _eventDate = date);
              }
            },
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'org_event_date'.tr(),
                labelStyle: TextStyle(color: AppColors.textSecondary),
                prefixIcon: Icon(Icons.calendar_today, color: AppColors.textSecondary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.border),
                ),
              ),
              child: Text(
                '${_eventDate.day}/${_eventDate.month}/${_eventDate.year}',
                style: TextStyle(color: AppColors.textPrimary),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Start Time
          InkWell(
            onTap: () async {
              final time = await showScrollableTimePicker(context, _startTime, primaryColor: AppColors.primary);
              if (time != null) {
                setState(() => _startTime = time);
              }
            },
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'org_start_time'.tr(),
                labelStyle: TextStyle(color: AppColors.textSecondary),
                prefixIcon: Icon(Icons.access_time, color: AppColors.textSecondary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.border),
                ),
              ),
              child: Text(
                _startTime.format(context),
                style: TextStyle(color: AppColors.textPrimary),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Description
          TextFormField(
            controller: _descriptionController,
            style: TextStyle(color: AppColors.textPrimary),
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'org_description'.tr(),
              labelStyle: TextStyle(color: AppColors.textSecondary),
              hintText: 'org_description_hint'.tr(),
              hintStyle: TextStyle(color: AppColors.textTertiary),
              alignLabelWithHint: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.border),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Upload profile photo from credential section
  Future<void> _uploadCredentialPhoto() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.driver?.id;
    if (userId == null) return;

    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (pickedFile == null || !mounted) return;

      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );

      // Read bytes from XFile (works on web & mobile)
      final imageBytes = await pickedFile.readAsBytes();
      final ext = pickedFile.path.split('.').last.toLowerCase();
      final fileName = '$userId/profile_${DateTime.now().millisecondsSinceEpoch}.$ext';

      String contentType = 'image/jpeg';
      if (ext == 'png') contentType = 'image/png';
      if (ext == 'webp') contentType = 'image/webp';

      // Upload to organizer-logos bucket (known to exist)
      await SupabaseConfig.client.storage
          .from('organizer-logos')
          .uploadBinary(
            fileName,
            imageBytes,
            fileOptions: FileOptions(contentType: contentType, upsert: true),
          );

      final imageUrl = SupabaseConfig.client.storage
          .from('organizer-logos')
          .getPublicUrl(fileName);

      // Update profiles table
      await SupabaseConfig.client
          .from('profiles')
          .update({'avatar_url': imageUrl})
          .eq('id', userId);

      // Also update drivers table so profile_screen shows it too
      await SupabaseConfig.client
          .from('drivers')
          .update({'profile_image_url': imageUrl})
          .eq('id', userId);

      if (mounted) Navigator.pop(context); // Close loading

      if (mounted) {
        // Update local organizer profile data so UI refreshes
        final profiles = Map<String, dynamic>.from(_organizerProfile?['profiles'] ?? {});
        profiles['avatar_url'] = imageUrl;
        _organizerProfile?['profiles'] = profiles;
        // Update driver provider too
        final driver = authProvider.driver;
        if (driver != null) {
          authProvider.updateDriver(driver.copyWith(profileImageUrl: imageUrl));
        }
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto actualizada'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading if open
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al subir foto: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Handle independent credential save
  Future<void> _handleSaveCredential() async {
    setState(() => _savingCredential = true);
    await _saveOrganizerContactInfo();
    if (mounted) {
      setState(() {
        _savingCredential = false;
        _contactInfoExpanded = false; // Collapse after saving
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Credencial guardada'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildContactInfoSection() {
    if (_loadingOrganizerProfile) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    // Use driver name (manually set by user) instead of profiles.full_name (Google OAuth)
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final driver = authProvider.driver;
    final profile = _organizerProfile?['profiles'];
    final fullName = driver?.name ?? driver?.fullName ?? profile?['full_name'] ?? 'cred_no_name'.tr();
    final phone = driver?.phone ?? profile?['phone'] ?? '';
    final photoUrl = driver?.profileImageUrl ?? profile?['avatar_url'];
    final createdAt = _organizerProfile?['created_at'];

    // Calculate time with Toro
    String timeWithToro = 'org_time_new'.tr();
    if (createdAt != null) {
      try {
        final joinDate = DateTime.parse(createdAt);
        final now = DateTime.now();
        final difference = now.difference(joinDate);

        if (difference.inDays >= 365) {
          final years = (difference.inDays / 365).floor();
          timeWithToro = 'org_time_years'.tr(namedArgs: {'count': '$years'});
        } else if (difference.inDays >= 30) {
          final months = (difference.inDays / 30).floor();
          timeWithToro = 'org_time_months'.tr(namedArgs: {'count': '$months'});
        } else if (difference.inDays > 0) {
          timeWithToro = 'org_time_days'.tr(namedArgs: {'count': '${difference.inDays}'});
        } else {
          timeWithToro = 'org_time_new'.tr();
        }
      } catch (e) {
        AppLogger.log('Error calculating time with Toro: $e');
      }
    }

    // ── COLLAPSED COMPACT CARD (credential already saved) ──
    if (!_contactInfoExpanded) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                // Profile Photo (tappable)
                GestureDetector(
                  onTap: _uploadCredentialPhoto,
                  child: Stack(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.success, width: 2),
                          image: photoUrl != null
                              ? DecorationImage(
                                  image: NetworkImage(photoUrl),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: photoUrl == null
                            ? Icon(Icons.person, color: AppColors.textTertiary, size: 28)
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.surface, width: 1.5),
                          ),
                          child: const Icon(Icons.camera_alt, size: 10, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              fullName,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.check_circle, color: AppColors.success, size: 16),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Chips for saved contact data
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (_contactEmailController.text.isNotEmpty)
                            _buildContactChip(Icons.email, _contactEmailController.text),
                          if (_contactPhoneController.text.isNotEmpty)
                            _buildContactChip(Icons.phone, _contactPhoneController.text),
                          if (_contactFacebookController.text.isNotEmpty)
                            _buildContactChip(Icons.facebook, 'Facebook'),
                          if (_companyLogoUrl != null)
                            _buildContactChip(Icons.image, 'Logo'),
                        ],
                      ),
                    ],
                  ),
                ),
                // Edit button
                IconButton(
                  onPressed: () => setState(() => _contactInfoExpanded = true),
                  icon: Icon(Icons.edit, color: AppColors.primary, size: 20),
                  tooltip: 'org_edit_credencial'.tr(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.access_time, size: 13, color: AppColors.primary),
                const SizedBox(width: 4),
                Text(
                  timeWithToro,
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // ── EXPANDED FORM (editable) ──
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Profile Header (auto-filled)
          Row(
            children: [
              // Profile Photo (tappable)
              GestureDetector(
                onTap: _uploadCredentialPhoto,
                child: Stack(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.primary, width: 2),
                        image: photoUrl != null
                            ? DecorationImage(
                                image: NetworkImage(photoUrl),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: photoUrl == null
                          ? Icon(
                              Icons.person,
                              color: AppColors.textTertiary,
                              size: 32,
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.surface, width: 2),
                        ),
                        child: const Icon(Icons.camera_alt, size: 12, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (phone.isNotEmpty)
                      Row(
                        children: [
                          Icon(Icons.phone, size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            phone,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 14, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          timeWithToro,
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Divider
          Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 16),

          // Contact Fields Label
          Text(
            'org_contact_info'.tr(),
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),

          // Business Email
          TextFormField(
            controller: _contactEmailController,
            style: const TextStyle(color: AppColors.textPrimary),
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'org_business_email'.tr(),
              labelStyle: TextStyle(color: AppColors.textSecondary),
              prefixIcon: Icon(Icons.email, color: AppColors.textSecondary),
              hintText: 'contacto@empresa.com',
              hintStyle: TextStyle(color: AppColors.textTertiary),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.border),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Business Phone
          TextFormField(
            controller: _contactPhoneController,
            style: const TextStyle(color: AppColors.textPrimary),
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'org_business_phone'.tr(),
              labelStyle: TextStyle(color: AppColors.textSecondary),
              prefixIcon: Icon(Icons.business, color: AppColors.textSecondary),
              hintText: '664-123-4567',
              hintStyle: TextStyle(color: AppColors.textTertiary),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.border),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Facebook
          TextFormField(
            controller: _contactFacebookController,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              labelText: 'org_business_facebook'.tr(),
              labelStyle: TextStyle(color: AppColors.textSecondary),
              prefixIcon: Icon(Icons.facebook, color: AppColors.textSecondary),
              hintText: 'facebook.com/tupagina',
              hintStyle: TextStyle(color: AppColors.textTertiary),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.border),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Company Logo Upload
          InkWell(
            onTap: _uploadCompanyLogo,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _companyLogoUrl != null ? AppColors.primary : AppColors.border,
                  width: _companyLogoUrl != null ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: AppColors.surface,
                      image: _companyLogoUrl != null
                          ? DecorationImage(
                              image: NetworkImage(_companyLogoUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: _companyLogoUrl == null
                        ? Icon(
                            Icons.business_center,
                            color: AppColors.textTertiary,
                            size: 24,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _companyLogoUrl != null ? 'org_logo_loaded'.tr() : 'org_add_logo'.tr(),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'org_logo_subtitle'.tr(),
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _companyLogoUrl != null ? Icons.check_circle : Icons.upload,
                    color: _companyLogoUrl != null ? AppColors.primary : AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── GUARDAR CREDENCIAL button (independent save) ──
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _savingCredential ? null : _handleSaveCredential,
              icon: _savingCredential
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save, size: 20),
              label: Text(
                _savingCredential ? 'org_saving'.tr() : 'org_save_credencial'.tr(),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Info message
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'org_credencial_saved_note'.tr(),
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.primary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleSection() {
    if (_loadingVehicles) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (_vehicles.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Icon(
              Icons.directions_bus_outlined,
              size: 64,
              color: AppColors.textTertiary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No tienes vehículos registrados',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Agrega un vehículo de turismo en "Publicar Vehículo"',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: _vehicles.map((vehicle) {
        final isSelected = _selectedVehicle?['id'] == vehicle['id'];
        final vehicleName = vehicle['vehicle_name'] as String? ?? 'Sin nombre';
        final totalSeats = vehicle['total_seats'] as int? ?? 0;
        final imageUrls = vehicle['image_urls'] as List<dynamic>? ?? [];

        // Get pricing from rental_listing
        final rentalListing = vehicle['rental_listing'] as Map<String, dynamic>?;
        final weeklyPrice = rentalListing?['weekly_price'] as num?;
        final pricePerKm = rentalListing?['price_per_km'] as num?;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isSelected ? AppColors.primary : AppColors.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: InkWell(
            onTap: () {
              HapticService.lightImpact();
              setState(() {
                _selectedVehicle = vehicle;
                // Auto-populate event seats with vehicle's total seats
                final seats = vehicle['total_seats'] as int?;
                if (seats != null && seats > 0) {
                  _eventSeatsController.text = seats.toString();
                }
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // Vehicle image
                      ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: imageUrls.isNotEmpty
                        ? Image.network(
                            imageUrls.first as String,
                            width: 80,
                            height: 60,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _buildPlaceholderImage(),
                          )
                        : _buildPlaceholderImage(),
                  ),
                  const SizedBox(width: 16),
                  // Vehicle info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vehicleName,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.event_seat,
                              size: 16,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$totalSeats asientos',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        if (weeklyPrice != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.attach_money,
                                size: 16,
                                color: Colors.green,
                              ),
                              Text(
                                '\$${weeklyPrice.toStringAsFixed(0)}/semana',
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (pricePerKm != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  '+ \$${pricePerKm.toStringAsFixed(0)}/km',
                                  style: TextStyle(
                                    color: AppColors.textTertiary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                      if (isSelected)
                        Icon(
                          Icons.check_circle,
                          color: AppColors.primary,
                          size: 28,
                        ),
                    ],
                  ),
                ),
                // "Default" badge for saved vehicle
                if (_isSavedDefault(vehicle['id']))
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.bookmark, color: Colors.white, size: 12),
                          SizedBox(width: 4),
                          Text(
                            'Predeterminado',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Check if a vehicle is the saved default
  bool _isSavedDefault(String vehicleId) {
    // This is a synchronous check - we'll need to load this from SharedPreferences
    // For now, we'll just check if it matches the currently selected vehicle on load
    return _selectedVehicle?['id'] == vehicleId && widget.preSelectedVehicleId == null;
  }

  Widget _buildCapacitySection() {
    // Wizard: ask if driver has own vehicle or needs to find one
    if (_hasOwnVehicle == null) {
      return _buildVehicleWizardChoice();
    }
    if (_hasOwnVehicle == true) {
      return _buildOwnVehicleCapacity();
    }
    return _buildDispatcherCapacity();
  }

  /// Wizard step: two clear choices
  Widget _buildVehicleWizardChoice() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '¿Cómo quieres operar?',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Esto define cómo se publica tu evento',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 16),

          // Option 1: I have a vehicle
          _buildWizardOption(
            icon: Icons.directions_bus_filled,
            title: 'Tengo vehículo',
            subtitle: 'Publicaré con mi propio carro o autobús',
            color: Colors.green,
            onTap: () async {
              HapticService.lightImpact();
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool(_savedHasOwnVehicleKey, true);
              setState(() => _hasOwnVehicle = true);

              // Auto-select own vehicle if available
              final userId = Provider.of<AuthProvider>(context, listen: false).driver?.id;
              if (userId != null) {
                final ownVehicles = _vehicles.where((v) => v['owner_id'] == userId).toList();
                if (ownVehicles.isNotEmpty && _selectedVehicle == null) {
                  setState(() {
                    _selectedVehicle = ownVehicles.first;
                    final seats = ownVehicles.first['total_seats'] as int?;
                    if (seats != null && _eventSeatsController.text.isEmpty) {
                      _eventSeatsController.text = seats.toString();
                    }
                  });
                }
              }
            },
          ),
          const SizedBox(height: 12),

          // Option 2: I need a driver
          _buildWizardOption(
            icon: Icons.groups_rounded,
            title: 'Necesito conductor',
            subtitle: 'Soy organizador / dispatcher — busco chofer con vehículo',
            color: AppColors.gold,
            onTap: () async {
              HapticService.lightImpact();
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool(_savedHasOwnVehicleKey, false);
              setState(() => _hasOwnVehicle = false);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWizardOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  /// Driver has own vehicle — show selected vehicle + seats
  Widget _buildOwnVehicleCapacity() {
    final userId = Provider.of<AuthProvider>(context, listen: false).driver?.id;
    final ownVehicles = _vehicles.where((v) => v['owner_id'] == userId).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with change link
          Row(
            children: [
              Icon(Icons.directions_bus_filled, color: Colors.green, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Mi vehículo',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () async {
                  HapticService.lightImpact();
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove(_savedHasOwnVehicleKey);
                  setState(() {
                    _hasOwnVehicle = null;
                    _selectedVehicle = null;
                  });
                },
                child: Text(
                  'Cambiar',
                  style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (_loadingVehicles)
            const Center(child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(strokeWidth: 2),
            ))
          else if (ownVehicles.isEmpty)
            // No vehicles registered — prompt to add
            _buildAddVehiclePrompt()
          else ...[
            // Show selected vehicle card
            if (_selectedVehicle != null) _buildSelectedVehicleCard(),

            // Show other vehicles if multiple
            if (ownVehicles.length > 1) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => _showOwnVehiclePicker(ownVehicles),
                child: Text(
                  'Ver mis ${ownVehicles.length} vehículos',
                  style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Seat count (editable, pre-filled from vehicle)
            TextFormField(
              controller: _eventSeatsController,
              style: const TextStyle(color: AppColors.textPrimary),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Asientos disponibles',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                prefixIcon: Icon(Icons.event_seat, color: AppColors.textSecondary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'org_seats_required'.tr();
                final seats = int.tryParse(value);
                if (seats == null || seats <= 0) return 'org_seats_invalid'.tr();
                return null;
              },
              onChanged: (_) => setState(() {}),
            ),

            const SizedBox(height: 12),

            // Info: publishing with own vehicle
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Publicarás este evento con tu vehículo',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
          _buildFeeDisclaimer(),
        ],
      ),
    );
  }

  Widget _buildAddVehiclePrompt() {
    return GestureDetector(
      onTap: () {
        HapticService.lightImpact();
        Navigator.pushNamed(context, '/add-vehicle').then((_) {
          // Reload vehicles when returning from add vehicle screen
          final authProvider = Provider.of<AuthProvider>(context, listen: false);
          final userId = authProvider.driver?.id;
          if (userId != null) {
            SupabaseConfig.client
                .from('bus_vehicles')
                .select('*')
                .eq('is_active', true)
                .eq('available_for_tourism', true)
                .then((vehicles) {
              if (mounted) {
                setState(() {
                  _vehicles = List<Map<String, dynamic>>.from(vehicles);
                  final ownVehicles = _vehicles.where((v) => v['owner_id'] == userId).toList();
                  if (ownVehicles.isNotEmpty) {
                    _selectedVehicle = ownVehicles.first;
                    final seats = ownVehicles.first['total_seats'] as int?;
                    if (seats != null) {
                      _eventSeatsController.text = seats.toString();
                    }
                  }
                });
              }
            });
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), style: BorderStyle.solid),
        ),
        child: Column(
          children: [
            Icon(Icons.add_circle_outline, color: AppColors.primary, size: 40),
            const SizedBox(height: 10),
            Text(
              'Agregar Vehículo',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Registra tu carro o autobús para poder publicar',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedVehicleCard() {
    if (_selectedVehicle == null) return const SizedBox.shrink();
    final name = _selectedVehicle!['vehicle_name'] as String? ?? 'Sin nombre';
    final seats = _selectedVehicle!['total_seats'] as int? ?? 0;
    final plate = _selectedVehicle!['plate'] as String? ?? '';
    final imageUrls = _selectedVehicle!['image_urls'] as List<dynamic>? ?? [];
    final imageUrl = imageUrls.isNotEmpty ? imageUrls.first as String : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          // Vehicle image
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: imageUrl != null
                ? Image.network(imageUrl, width: 56, height: 56, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 56, height: 56,
                      color: AppColors.card,
                      child: Icon(Icons.directions_bus, color: AppColors.textTertiary, size: 28),
                    ),
                  )
                : Container(
                    width: 56, height: 56,
                    color: AppColors.card,
                    child: Icon(Icons.directions_bus, color: AppColors.textTertiary, size: 28),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(
                  '$seats asientos${plate.isNotEmpty ? ' · $plate' : ''}',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          Icon(Icons.check_circle, color: Colors.green, size: 22),
        ],
      ),
    );
  }

  void _showOwnVehiclePicker(List<Map<String, dynamic>> ownVehicles) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mis Vehículos', style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            ...ownVehicles.map((v) {
              final isSelected = _selectedVehicle?['id'] == v['id'];
              final vName = v['vehicle_name'] as String? ?? 'Sin nombre';
              final vSeats = v['total_seats'] as int? ?? 0;
              return ListTile(
                leading: Icon(Icons.directions_bus, color: isSelected ? Colors.green : AppColors.textSecondary),
                title: Text(vName, style: TextStyle(color: AppColors.textPrimary)),
                subtitle: Text('$vSeats asientos', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                trailing: isSelected ? Icon(Icons.check_circle, color: Colors.green) : null,
                onTap: () {
                  setState(() {
                    _selectedVehicle = v;
                    final seats = v['total_seats'] as int?;
                    if (seats != null) {
                      _eventSeatsController.text = seats.toString();
                    }
                  });
                  Navigator.pop(ctx);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  /// Dispatcher/organizer mode — original capacity section
  Widget _buildDispatcherCapacity() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with change link
          Row(
            children: [
              Icon(Icons.groups_rounded, color: AppColors.gold, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Buscar conductor',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () async {
                  HapticService.lightImpact();
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove(_savedHasOwnVehicleKey);
                  setState(() {
                    _hasOwnVehicle = null;
                  });
                },
                child: Text(
                  'Cambiar',
                  style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Editable seat count
          TextFormField(
            controller: _eventSeatsController,
            style: const TextStyle(color: AppColors.textPrimary),
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'org_seats_needed'.tr(),
              labelStyle: TextStyle(color: AppColors.textSecondary),
              prefixIcon: Icon(Icons.event_seat, color: AppColors.textSecondary),
              hintText: 'org_seats_hint'.tr(),
              hintStyle: TextStyle(color: AppColors.textTertiary),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'org_seats_required'.tr();
              final seats = int.tryParse(value);
              if (seats == null || seats <= 0) return 'org_seats_invalid'.tr();
              return null;
            },
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),

          // Info: drivers will bid on this event
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.gavel_rounded, color: AppColors.gold, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'org_bid_info'.tr(),
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          _buildFeeDisclaimer(),
        ],
      ),
    );
  }

  /// TORO 18% commission disclaimer (shared between both modes)
  Widget _buildFeeDisclaimer() {
    return GestureDetector(
      onTap: () {
        HapticService.lightImpact();
        setState(() => _feeDisclaimerExpanded = !_feeDisclaimerExpanded);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'org_fee_title'.tr(),
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  _feeDisclaimerExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: AppColors.textTertiary,
                  size: 20,
                ),
              ],
            ),
            if (_feeDisclaimerExpanded) ...[
              const SizedBox(height: 10),
              Divider(color: AppColors.border, height: 1),
              const SizedBox(height: 10),
              Text(
                'org_fee_detail'.tr(),
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.gavel, color: Colors.orange, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'org_fee_legal'.tr(),
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showVehicleSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.textTertiary.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text('Selecciona Vehículo', style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Expanded(child: SingleChildScrollView(child: _buildVehicleSection())),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      width: 80,
      height: 60,
      color: AppColors.border,
      child: Icon(
        Icons.directions_bus,
        color: AppColors.textTertiary,
        size: 32,
      ),
    );
  }

  // ============================================================================
  // ITINERARY FUNCTIONS (must be inside main class)
  // ============================================================================

  String _formatTimeAMPM(DateTime dateTime) {
    int hour = dateTime.hour;
    String period = hour >= 12 ? 'PM' : 'AM';
    hour = hour % 12;
    if (hour == 0) hour = 12;
    String minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  void _addNewStop() async {
    final result = await _showAddStopDialog();
    if (result != null) {
      // If no coordinates from selection, try geocoding the name
      double? resultLat = result['lat'] as double?;
      double? resultLng = result['lng'] as double?;
      if (resultLat == null || resultLng == null) {
        final coords = await _geocodeStopName(result['name'] as String);
        resultLat = coords?['lat'];
        resultLng = coords?['lng'];
      }

      setState(() {
        _stops.add(EventStop(
          name: result['name'],
          lat: resultLat,
          lng: resultLng,
          estimatedArrival: result['datetime'],
          durationMinutes: result['duration'],
          notes: result['notes'],
          stopOrder: _stops.length,
        ));

        // Auto-sort stops by datetime (chronological order)
        _stops.sort((a, b) {
          if (a.estimatedArrival == null && b.estimatedArrival == null) return 0;
          if (a.estimatedArrival == null) return 1;
          if (b.estimatedArrival == null) return -1;
          return a.estimatedArrival!.compareTo(b.estimatedArrival!);
        });

        // Update stopOrder based on sorted position
        for (int i = 0; i < _stops.length; i++) {
          _stops[i].stopOrder = i;
        }
      });
      HapticService.lightImpact();

      // Recalculate distance if we have at least 2 stops
      if (_stops.length >= 2) {
        _calculateTotalDistance();
      }
    }
  }

  /// Extract state code from address string
  /// Example: "Mexicali, Baja California" -> "BC"
  String? _extractStateCodeFromAddress(String address) {
    final stateMap = {
      'baja california': 'BC',
      'baja california sur': 'BCS',
      'sonora': 'SON',
      'chihuahua': 'CHH',
      'coahuila': 'COA',
      'nuevo león': 'NLE',
      'tamaulipas': 'TAM',
      'ciudad de méxico': 'CDMX',
      'cdmx': 'CDMX',
      'estado de méxico': 'MEX',
      'querétaro': 'QRO',
      'aguascalientes': 'AGS',
      'quintana roo': 'QROO',
      'guerrero': 'GRO',
      'jalisco': 'JAL',
      'sinaloa': 'SIN',
      'puebla': 'PUE',
      'guanajuato': 'GUA',
      'morelos': 'MOR',
      'yucatán': 'YUC',
      'veracruz': 'VER',
    };

    final lowerAddress = address.toLowerCase();
    for (final entry in stateMap.entries) {
      if (lowerAddress.contains(entry.key)) {
        return entry.value;
      }
    }
    return null; // Keep current default
  }

  void _editStop(int index) async {
    final stop = _stops[index];
    final result = await _showAddStopDialog(existingStop: stop);
    if (result != null) {
      // If no coordinates, try geocoding the name
      double? resultLat = result['lat'] as double?;
      double? resultLng = result['lng'] as double?;
      if (resultLat == null || resultLng == null) {
        final coords = await _geocodeStopName(result['name'] as String);
        resultLat = coords?['lat'];
        resultLng = coords?['lng'];
      }
      setState(() {
        stop.name = result['name'];
        stop.lat = resultLat;
        stop.lng = resultLng;
        stop.estimatedArrival = result['datetime'];
        stop.durationMinutes = result['duration'];
        stop.notes = result['notes'];
      });
      HapticService.lightImpact();
      _calculateTotalDistance();
    }
  }

  void _deleteStop(int index) {
    setState(() {
      _stops.removeAt(index);
      // Reorder remaining stops
      for (int i = 0; i < _stops.length; i++) {
        _stops[i].stopOrder = i;
      }
    });
    HapticService.lightImpact();
    if (_stops.length >= 2) {
      _calculateTotalDistance();
    }
  }

  void _moveStopUp(int index) {
    if (index > 0) {
      setState(() {
        final stop = _stops.removeAt(index);
        _stops.insert(index - 1, stop);
        // Update stop orders
        for (int i = 0; i < _stops.length; i++) {
          _stops[i].stopOrder = i;
        }
      });
      HapticService.lightImpact();
      _calculateTotalDistance();
    }
  }

  void _moveStopDown(int index) {
    if (index < _stops.length - 1) {
      setState(() {
        final stop = _stops.removeAt(index);
        _stops.insert(index + 1, stop);
        // Update stop orders
        for (int i = 0; i < _stops.length; i++) {
          _stops[i].stopOrder = i;
        }
      });
      HapticService.lightImpact();
      _calculateTotalDistance();
    }
  }

  void _addReturnTrip() {
    if (_stops.length < 2) return;
    final originalStops = List<EventStop>.from(_stops);
    for (int i = originalStops.length - 2; i >= 0; i--) {
      final originalStop = originalStops[i];
      _stops.add(EventStop(
        name: originalStop.name,
        lat: originalStop.lat,
        lng: originalStop.lng,
        estimatedArrival: null,
        durationMinutes: originalStop.durationMinutes,
        notes: originalStop.notes,
        stopOrder: _stops.length,
      ));
    }
    setState(() {});
    HapticService.lightImpact();
    _calculateTotalDistance();
  }

  Future<void> _calculateTotalDistance() async {
    if (_stops.length < 2) return;
    setState(() {
      _calculatingDistance = true;
      _realDistanceKm = null;
    });
    try {
      double totalDistance = 0;
      for (int i = 0; i < _stops.length - 1; i++) {
        final from = _stops[i];
        final to = _stops[i + 1];
        if (from.lat != null && from.lng != null && to.lat != null && to.lng != null) {
          final distance = await _calculateRoadDistance(
            from.lat!,
            from.lng!,
            to.lat!,
            to.lng!,
          );
          if (distance != null) {
            totalDistance += distance;
          }
        }
      }
      if (mounted) {
        setState(() {
          _realDistanceKm = totalDistance;
          _distanceKmController.text = totalDistance.toStringAsFixed(1);
          _calculatingDistance = false;
        });
      }
    } catch (e) {
      AppLogger.log('Error calculating total distance: $e');
      if (mounted) {
        setState(() {
          _calculatingDistance = false;
        });
      }
    }
  }

  Future<Map<String, dynamic>?> _showAddStopDialog({EventStop? existingStop}) async {
    final nameController = TextEditingController(text: existingStop?.name ?? '');
    final notesController = TextEditingController(text: existingStop?.notes ?? '');
    final durationController = TextEditingController(
      text: existingStop?.durationMinutes?.toString() ?? '',
    );

    double? lat = existingStop?.lat;
    double? lng = existingStop?.lng;
    String? address = existingStop?.name;
    DateTime? selectedDateTime = existingStop?.estimatedArrival; // Changed from TimeOfDay to DateTime

    // Autocomplete variables
    List<Map<String, dynamic>> suggestions = [];
    bool showSuggestions = false;
    Timer? debounceTimer;

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Autocomplete fetch function
            void fetchSuggestions(String query) {
              if (query.trim().isEmpty) {
                setModalState(() {
                  suggestions = [];
                  showSuggestions = false;
                });
                return;
              }

              debounceTimer?.cancel();
              debounceTimer = Timer(const Duration(milliseconds: 500), () async {
                try {
                  // Nominatim (OpenStreetMap) - better at understanding state/city context
                  final url = Uri.parse(
                    'https://nominatim.openstreetmap.org/search'
                    '?q=${Uri.encodeComponent(query)}'
                    '&format=jsonv2'
                    '&countrycodes=mx,us'
                    '&limit=5'
                    '&addressdetails=1'
                    '&accept-language=es',
                  );

                  final response = await http.get(url, headers: {'User-Agent': 'TORORide/1.0'});

                  if (response.statusCode == 200) {
                    final results = json.decode(response.body) as List;

                    setModalState(() {
                      suggestions = results.map((r) {
                        final name = (r['name'] as String?) ?? '';
                        final displayName = r['display_name'] as String;
                        return {
                          'place_name': displayName,
                          'text': name.isNotEmpty ? name : displayName.split(',').first.trim(),
                          'lat': double.parse(r['lat'].toString()),
                          'lng': double.parse(r['lon'].toString()),
                        };
                      }).toList();
                      showSuggestions = suggestions.isNotEmpty;
                    });
                  }
                } catch (e) {
                  AppLogger.log('Error fetching suggestions: $e');
                }
              });
            }
            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.add_location_alt, color: AppColors.primary, size: 24),
                          const SizedBox(width: 12),
                          Text(
                            existingStop != null ? 'Editar Parada' : 'Nueva Parada',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: Icon(Icons.close, color: AppColors.textSecondary),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: nameController,
                                  style: TextStyle(color: AppColors.textPrimary),
                                  decoration: InputDecoration(
                                    labelText: 'Dirección',
                                    hintText: 'Escribe o selecciona en mapa',
                                    prefixIcon: Icon(Icons.place, color: AppColors.textSecondary),
                                    suffixIcon: lat != null && lng != null
                                        ? Icon(Icons.check_circle, color: Colors.green, size: 20)
                                        : nameController.text.isNotEmpty
                                            ? IconButton(
                                                icon: Icon(Icons.clear, color: AppColors.textSecondary, size: 20),
                                                onPressed: () {
                                                  nameController.clear();
                                                  setModalState(() {
                                                    suggestions = [];
                                                    showSuggestions = false;
                                                    lat = null;
                                                    lng = null;
                                                  });
                                                },
                                              )
                                            : null,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onChanged: (value) {
                                    fetchSuggestions(value);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                height: 56,
                                child: ElevatedButton(
                                  onPressed: () async {
                                    final result = await showDialog<Map<String, dynamic>>(
                                      context: context,
                                      builder: (context) => _SimpleMapPicker(
                                        title: 'Seleccionar Ubicación',
                                        initialLocation: lat != null && lng != null
                                            ? LatLng(lat!, lng!)
                                            : null,
                                      ),
                                    );
                                    if (result != null) {
                                      setModalState(() {
                                        lat = result['coords']['lat'];
                                        lng = result['coords']['lng'];
                                        address = result['address'];
                                        nameController.text = address ?? '';
                                        showSuggestions = false;
                                      });
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                  ),
                                  child: Icon(Icons.map, color: Colors.white, size: 20),
                                ),
                              ),
                            ],
                          ),
                          // Suggestions dropdown
                          if (showSuggestions && suggestions.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.textTertiary.withOpacity(0.2)),
                              ),
                              constraints: const BoxConstraints(maxHeight: 200),
                              child: ListView.separated(
                                shrinkWrap: true,
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                itemCount: suggestions.length,
                                separatorBuilder: (_, _) => Divider(
                                  height: 1,
                                  color: AppColors.textTertiary.withOpacity(0.1),
                                ),
                                itemBuilder: (context, index) {
                                  final suggestion = suggestions[index];
                                  return InkWell(
                                    onTap: () {
                                      setModalState(() {
                                        lat = suggestion['lat'] as double;
                                        lng = suggestion['lng'] as double;
                                        address = suggestion['place_name'] as String;
                                        nameController.text = suggestion['text'] as String;
                                        showSuggestions = false;
                                      });
                                      FocusScope.of(context).unfocus();
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      child: Row(
                                        children: [
                                          Icon(Icons.location_on, color: AppColors.primary, size: 18),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  suggestion['text'] as String,
                                                  style: TextStyle(
                                                    color: AppColors.textPrimary,
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  suggestion['place_name'] as String,
                                                  style: TextStyle(
                                                    color: AppColors.textSecondary,
                                                    fontSize: 12,
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
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: () async {
                          DateTime initialDateTime = selectedDateTime ?? DateTime.now();

                          await showDialog(
                            context: context,
                            builder: (BuildContext builder) {
                              DateTime tempDateTime = initialDateTime;
                              return Dialog(
                                backgroundColor: Colors.transparent,
                                child: Container(
                                  height: 380,
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Column(
                                    children: [
                                      // Header
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: AppColors.background,
                                          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(context),
                                              child: Text('Cancelar', style: TextStyle(color: AppColors.textSecondary)),
                                            ),
                                            Text(
                                              'Fecha y Hora',
                                              style: TextStyle(
                                                color: AppColors.textPrimary,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 16,
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: () {
                                                setModalState(() {
                                                  selectedDateTime = tempDateTime;
                                                });
                                                Navigator.pop(context);
                                              },
                                              child: Text('Listo', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Cupertino Date/Time Picker
                                      Expanded(
                                        child: CupertinoDatePicker(
                                          mode: CupertinoDatePickerMode.dateAndTime,
                                          initialDateTime: initialDateTime,
                                          minimumDate: DateTime.now().subtract(const Duration(hours: 1)),
                                          maximumDate: DateTime.now().add(const Duration(days: 365)),
                                          use24hFormat: false,
                                          onDateTimeChanged: (DateTime newDateTime) {
                                            tempDateTime = newDateTime;
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Fecha y hora estimada (opcional)',
                            prefixIcon: Icon(Icons.event, color: AppColors.textSecondary),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            selectedDateTime != null
                                ? '${selectedDateTime!.day}/${selectedDateTime!.month}/${selectedDateTime!.year} ${_formatTimeAMPM(selectedDateTime!)}'
                                : 'Seleccionar fecha y hora',
                            style: TextStyle(
                              color: selectedDateTime != null ? AppColors.textPrimary : AppColors.textTertiary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: durationController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          labelText: 'Duración de parada (minutos, opcional)',
                          hintText: 'Ej: 15',
                          prefixIcon: Icon(Icons.timer, color: AppColors.textSecondary),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: notesController,
                        maxLines: 3,
                        style: TextStyle(color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          labelText: 'Notas (opcional)',
                          hintText: 'Información adicional sobre esta parada',
                          prefixIcon: Icon(Icons.notes, color: AppColors.textSecondary),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (nameController.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Ingresa la dirección de la parada')),
                              );
                              return;
                            }
                            Navigator.pop(context, {
                              'name': nameController.text.trim(),
                              'lat': lat,
                              'lng': lng,
                              'datetime': selectedDateTime, // Changed from 'time' to 'datetime'
                              'duration': durationController.text.isNotEmpty
                                  ? int.tryParse(durationController.text)
                                  : null,
                              'notes': notesController.text.trim().isNotEmpty
                                  ? notesController.text.trim()
                                  : null,
                            });
                          },
                          icon: Icon(Icons.check, color: Colors.white),
                          label: Text(
                            existingStop != null
                                ? 'Guardar Cambios'
                                : _stops.isEmpty
                                    ? 'Agregar Origen'
                                    : _stops.length == 1
                                        ? 'Agregar Destino'
                                        : 'Agregar Parada',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyStopsPlaceholder() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, style: BorderStyle.solid, width: 1.5),
      ),
      child: Column(
        children: [
          Icon(Icons.explore_outlined, size: 48, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          Text(
            'Sin paradas todavía',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Agrega al menos 2 paradas (origen y destino)',
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStopsList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _stops.length,
      itemBuilder: (context, index) {
        final stop = _stops[index];
        final isFirst = index == 0;
        final isLast = index == _stops.length - 1;
        return _buildStopCard(stop, index, isFirst, isLast);
      },
    );
  }

  Widget _buildStopCard(EventStop stop, int index, bool isFirst, bool isLast) {
    IconData icon;
    Color iconColor;
    String label;

    if (isFirst) {
      icon = Icons.trip_origin;
      iconColor = Colors.green;
      label = 'Origen';
    } else if (isLast) {
      icon = Icons.location_on;
      iconColor = Colors.red;
      label = 'Destino';
    } else {
      icon = Icons.place;
      iconColor = Colors.blue;
      label = 'Parada $index';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            title: Text(
              stop.name,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
                if (stop.estimatedArrival != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.event, size: 12, color: AppColors.textTertiary),
                      const SizedBox(width: 4),
                      Text(
                        '${stop.estimatedArrival!.day}/${stop.estimatedArrival!.month}/${stop.estimatedArrival!.year} ${_formatTimeAMPM(stop.estimatedArrival!)}',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Edit button
                IconButton(
                  icon: Icon(Icons.edit, size: 18, color: AppColors.primary),
                  onPressed: () => _editStop(index),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                // Delete button (only if more than 2 stops)
                if (_stops.length > 2)
                  IconButton(
                    icon: Icon(Icons.delete_outline, size: 18, color: Colors.red),
                    onPressed: () => _deleteStop(index),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
              ],
            ),
          ),
          if (!isLast)
            Container(
              margin: const EdgeInsets.only(left: 24),
              height: 16,
              width: 2,
              color: AppColors.border,
            ),
        ],
      ),
    );
  }

  Widget _buildCalculatingDistanceIndicator() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.blue,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Calculando distancia total...',
            style: TextStyle(
              color: Colors.blue,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDistanceDisplay() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green),
      ),
      child: Row(
        children: [
          Icon(Icons.route, color: Colors.green, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '✅ Distancia Total',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${_realDistanceKm!.toStringAsFixed(1)} km',
                  style: const TextStyle(
                    color: Colors.green,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (_isRoundTrip)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'IDA Y VUELTA',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// Simple Map Picker Dialog
// =============================================================================

class _SimpleMapPicker extends StatefulWidget {
  final String title;
  final LatLng? initialLocation;

  const _SimpleMapPicker({
    required this.title,
    this.initialLocation,
  });

  @override
  State<_SimpleMapPicker> createState() => _SimpleMapPickerState();
}

class _SimpleMapPickerState extends State<_SimpleMapPicker> {
  late MapController _mapController;
  late LatLng _currentCenter;
  late TextEditingController _searchController;
  String _addressText = 'Mueve el mapa para seleccionar';
  bool _isLoadingAddress = false;
  bool _isLoadingGPS = false;
  bool _isDragging = false;
  bool _isSearching = false;
  List<Map<String, dynamic>> _suggestions = [];
  bool _showSuggestions = false;
  Timer? _debounceTimer;

  // Default center: Phoenix, AZ (US)
  static const _defaultCenter = LatLng(33.4484, -112.0740);

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _searchController = TextEditingController();
    _currentCenter = widget.initialLocation ?? _defaultCenter;

    // Auto-detect GPS on open (skip if initialLocation was provided)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialLocation != null) {
        _reverseGeocode(_currentCenter);
      } else {
        _goToCurrentLocation();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchSuggestions(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        // Nominatim (OpenStreetMap) - better at understanding state/city context
        final url = Uri.parse(
          'https://nominatim.openstreetmap.org/search'
          '?q=${Uri.encodeComponent(query)}'
          '&format=jsonv2'
          '&countrycodes=mx,us'
          '&limit=5'
          '&addressdetails=1'
          '&accept-language=es',
        );

        final response = await http.get(url, headers: {'User-Agent': 'TORORide/1.0'});

        if (response.statusCode == 200) {
          final results = json.decode(response.body) as List;

          if (mounted) {
            setState(() {
              _suggestions = results.map((r) {
                final name = (r['name'] as String?) ?? '';
                final displayName = r['display_name'] as String;
                return {
                  'place_name': displayName,
                  'text': name.isNotEmpty ? name : displayName.split(',').first.trim(),
                  'lat': double.parse(r['lat'].toString()),
                  'lng': double.parse(r['lon'].toString()),
                };
              }).toList();
              _showSuggestions = _suggestions.isNotEmpty;
            });
          }
        }
      } catch (e) {
        AppLogger.log('Error fetching suggestions: $e');
      }
    });
  }

  Future<void> _reverseGeocode(LatLng location) async {
    setState(() => _isLoadingAddress = true);

    try {
      final placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;

        // Build complete address without duplicates
        List<String> addressParts = [];

        // Add business/place name if available and it's not just a number
        if (place.name != null &&
            place.name!.isNotEmpty &&
            place.name != place.street &&
            place.name != place.subThoroughfare &&
            !RegExp(r'^\d+$').hasMatch(place.name!)) {
          addressParts.add('📍 ${place.name}');
        }

        // Add street (already includes number in most cases)
        if (place.street != null && place.street!.isNotEmpty) {
          // Only add subThoroughfare if street doesn't already start with it
          String streetInfo = place.street!;
          if (place.subThoroughfare != null &&
              place.subThoroughfare!.isNotEmpty &&
              !streetInfo.startsWith(place.subThoroughfare!)) {
            streetInfo = '${place.subThoroughfare} $streetInfo';
          }
          addressParts.add(streetInfo);
        }

        // Add neighborhood/sub-locality (avoid duplicates with locality)
        if (place.subLocality != null &&
            place.subLocality!.isNotEmpty &&
            place.subLocality != place.locality) {
          addressParts.add(place.subLocality!);
        }

        // Add city
        if (place.locality != null && place.locality!.isNotEmpty) {
          addressParts.add(place.locality!);
        }

        // Add state
        if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) {
          addressParts.add(place.administrativeArea!);
        }

        // Add postal code
        if (place.postalCode != null && place.postalCode!.isNotEmpty) {
          addressParts.add('CP ${place.postalCode}');
        }

        final address = addressParts.join(', ');

        if (mounted) {
          setState(() {
            _addressText = address.isNotEmpty
                ? address
                : '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}';
            _isLoadingAddress = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _addressText =
              '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}';
          _isLoadingAddress = false;
        });
      }
    }
  }

  Future<void> _goToCurrentLocation() async {
    setState(() => _isLoadingGPS = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('GPS desactivado. Activa la ubicación.')),
          );
        }
        setState(() => _isLoadingGPS = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Permiso de ubicación denegado')),
            );
          }
          setState(() => _isLoadingGPS = false);
          return;
        }
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      final newLocation = LatLng(position.latitude, position.longitude);

      if (!mounted) return;

      _mapController.move(newLocation, 16);
      setState(() {
        _currentCenter = newLocation;
        _isLoadingGPS = false;
      });

      _reverseGeocode(newLocation);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al obtener ubicación: $e')),
        );
        setState(() => _isLoadingGPS = false);
      }
    }
  }

  Future<void> _searchAddress() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa una dirección para buscar')),
      );
      return;
    }

    setState(() => _isSearching = true);

    try {
      // Geocode the address
      final locations = await locationFromAddress(query);

      if (locations.isNotEmpty) {
        final location = locations.first;
        final newLocation = LatLng(location.latitude, location.longitude);

        // Move map to the found location
        _mapController.move(newLocation, 16);

        setState(() {
          _currentCenter = newLocation;
          _isSearching = false;
        });

        // Get the reverse geocoded address
        _reverseGeocode(newLocation);

        // Hide keyboard
        if (!mounted) return;
        FocusScope.of(context).unfocus();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se encontró la dirección')),
          );
        }
        setState(() => _isSearching = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al buscar: ${e.toString()}')),
        );
        setState(() => _isSearching = false);
      }
    }
  }

  void _onMapMove(MapPosition position, bool hasGesture) {
    if (hasGesture && !_isDragging) {
      setState(() => _isDragging = true);
    }
  }

  void _onMapMoveEnd() {
    if (_isDragging) {
      setState(() {
        _isDragging = false;
        _currentCenter = _mapController.camera.center;
      });
      _reverseGeocode(_mapController.camera.center);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        backgroundColor: const Color(0xFF1E1E1E),
        appBar: AppBar(
          backgroundColor: const Color(0xFF2A2A2A),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            widget.title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          centerTitle: true,
        ),
        body: Stack(
          children: [
            // Map
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentCenter,
                initialZoom: 15,
                onPositionChanged: (position, hasGesture) {
                  _onMapMove(position, hasGesture);
                  if (!hasGesture) {
                    _onMapMoveEnd();
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.toro.driver',
                ),
              ],
            ),

            // Search bar - top
            Positioned(
              top: 16,
              left: 16,
              right: 80,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(fontSize: 14, color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Buscar dirección...',
                        hintStyle: const TextStyle(color: Color(0xFF888888)),
                        prefixIcon: const Icon(Icons.search, color: Color(0xFFAAAAAA), size: 20),
                        suffixIcon: _isSearching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
                                ),
                              )
                            : _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, color: Color(0xFFAAAAAA), size: 20),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {
                                        _suggestions = [];
                                        _showSuggestions = false;
                                      });
                                    },
                                  )
                                : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _searchAddress(),
                      onChanged: (value) {
                        _fetchSuggestions(value);
                      },
                    ),
                  ),
                  // Suggestions dropdown
                  if (_showSuggestions && _suggestions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      constraints: const BoxConstraints(maxHeight: 250),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _suggestions.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          color: Colors.white.withOpacity(0.1),
                          indent: 16,
                          endIndent: 16,
                        ),
                        itemBuilder: (context, index) {
                          final suggestion = _suggestions[index];
                          return InkWell(
                            onTap: () {
                              final lat = suggestion['lat'] as double;
                              final lng = suggestion['lng'] as double;
                              final newLocation = LatLng(lat, lng);

                              _mapController.move(newLocation, 16);
                              setState(() {
                                _currentCenter = newLocation;
                                _showSuggestions = false;
                                _searchController.text = suggestion['text'] as String;
                              });

                              _reverseGeocode(newLocation);
                              FocusScope.of(context).unfocus();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  const Icon(Icons.location_on, color: Colors.orange, size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          suggestion['text'] as String,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          suggestion['place_name'] as String,
                                          style: const TextStyle(
                                            color: Color(0xFF888888),
                                            fontSize: 12,
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
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),

            // Centered Pin - Fixed position
            Center(
              child: Transform.translate(
                offset: const Offset(0, -20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    Container(
                      width: 12,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // GPS Button - top right
            Positioned(
              top: 16,
              right: 16,
              child: GestureDetector(
                onTap: _isLoadingGPS ? null : _goToCurrentLocation,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: _isLoadingGPS
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
                        )
                      : const Icon(Icons.my_location, color: Colors.orange, size: 24),
                ),
              ),
            ),

            // Zoom controls
            Positioned(
              right: 16,
              bottom: 220,
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () {
                      _mapController.move(
                        _mapController.camera.center,
                        _mapController.camera.zoom + 1,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.add, size: 22, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      _mapController.move(
                        _mapController.camera.center,
                        _mapController.camera.zoom - 1,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.remove, size: 22, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom panel
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                      // Address display
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.25),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.location_on, color: Colors.red, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _isLoadingAddress
                                  ? const Row(
                                      children: [
                                        SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
                                        ),
                                        SizedBox(width: 10),
                                        Text(
                                          'Obteniendo dirección...',
                                          style: TextStyle(color: Color(0xFF999999), fontSize: 14),
                                        ),
                                      ],
                                    )
                                  : Text(
                                      _addressText,
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Confirm button
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context, {
                            'coords': {
                              'lat': _currentCenter.latitude,
                              'lng': _currentCenter.longitude,
                            },
                            'address': _addressText,
                          });
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Colors.orange, Color(0xFFFF8C00)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.orange.withOpacity(0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle, color: Colors.white, size: 22),
                              SizedBox(width: 10),
                              Text(
                                'Confirmar Ubicación',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
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
            ),
          ],
        ),
      ),
    );
  }

}
