import 'dart:async';
import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../services/tourism_event_service.dart';
import '../../services/tourism_messaging_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';
import '../../core/logging/app_logger.dart';

/// Live itinerary screen for organizers.
///
/// Features:
/// - Fast loading (direct query to tourism_event_itinerary)
/// - Mini map with numbered pins and OSRM polyline
/// - Edit mode: add/edit/delete stops with Nominatim search + map picker
/// - OSRM road distance/duration between consecutive stops
/// - Mark arrived/departed buttons
/// - Real-time updates via Supabase subscriptions
class OrganizerItineraryScreen extends StatefulWidget {
  final String eventId;

  const OrganizerItineraryScreen({
    super.key,
    required this.eventId,
  });

  @override
  State<OrganizerItineraryScreen> createState() =>
      _OrganizerItineraryScreenState();
}

class _OrganizerItineraryScreenState extends State<OrganizerItineraryScreen>
    with SingleTickerProviderStateMixin {
  final TourismEventService _eventService = TourismEventService();
  final TourismMessagingService _messagingService = TourismMessagingService();
  final _client = Supabase.instance.client;

  // Data
  Map<String, dynamic>? _event;
  List<Map<String, dynamic>> _itinerary = [];

  // OSRM route data between stops
  // Key: "stopIndex" -> {km, min, polyline}
  Map<int, Map<String, dynamic>> _routeSegments = {};

  // UI State
  bool _isLoading = true;
  bool _isEditMode = false;
  String? _error;
  int _currentStopIndex = 0;

  // Passenger KPIs
  int _totalPassengers = 0;
  int _aboardPassengers = 0;
  int _missingPassengers = 0;

  // Real-time subscriptions
  RealtimeChannel? _itineraryChannel;
  RealtimeChannel? _invitationsChannel;

  // Animation for current stop pulse
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initPulseAnimation();
    _loadData();
    _subscribeToUpdates();
  }

  void _initPulseAnimation() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    if (_itineraryChannel != null) {
      _client.removeChannel(_itineraryChannel!);
      _itineraryChannel = null;
    }
    if (_invitationsChannel != null) {
      _client.removeChannel(_invitationsChannel!);
      _invitationsChannel = null;
    }
    super.dispose();
  }

  // ─── DATA LOADING ────────────────────────────────────────────

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 3 parallel queries
      final results = await Future.wait([
        _client
            .from('tourism_event_itinerary')
            .select('*')
            .eq('event_id', widget.eventId)
            .order('stop_order', ascending: true),
        _client
            .from('tourism_events')
            .select('id, event_name, status')
            .eq('id', widget.eventId)
            .maybeSingle(),
        _client
            .from('tourism_invitations')
            .select('id, status, current_check_in_status')
            .eq('event_id', widget.eventId),
      ]);

      final itineraryData = results[0] as List;
      _itinerary = List<Map<String, dynamic>>.from(
        itineraryData.map((e) => Map<String, dynamic>.from(e as Map)),
      );
      _event = results[1] as Map<String, dynamic>?;

      // Calculate passenger KPIs
      final passengers = List<Map<String, dynamic>>.from(
        (results[2] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      _calculatePassengerStats(passengers);

      _currentStopIndex = _findCurrentStopIndex();

      // Calculate OSRM routes between stops
      await _calculateAllRouteSegments();

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Error cargando itinerario: $e';
        });
      }
    }
  }

  int _findCurrentStopIndex() {
    for (int i = 0; i < _itinerary.length; i++) {
      final stop = _itinerary[i];
      if (stop['arrived_at'] == null) return i;
      if (stop['departed_at'] == null) return i;
    }
    return _itinerary.isEmpty ? 0 : _itinerary.length - 1;
  }

  void _subscribeToUpdates() {
    _itineraryChannel =
        _client.channel('itinerary_${widget.eventId}');
    _itineraryChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tourism_event_itinerary',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'event_id',
            value: widget.eventId,
          ),
          callback: (payload) {
            _loadData();
          },
        )
        .subscribe();

    // Subscribe to invitation changes (passenger KPIs)
    _invitationsChannel =
        _client.channel('inv_${widget.eventId}');
    _invitationsChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tourism_invitations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'event_id',
            value: widget.eventId,
          ),
          callback: (payload) {
            _loadData();
          },
        )
        .subscribe();
  }

  void _calculatePassengerStats(List<Map<String, dynamic>> passengers) {
    int total = 0;
    int aboard = 0;
    for (final p in passengers) {
      final status = p['status'] as String? ?? 'pending';
      final checkIn = p['current_check_in_status'] as String?;
      if (status == 'accepted' || status == 'checked_in') total++;
      if (status == 'checked_in' || checkIn == 'boarded') aboard++;
    }
    _totalPassengers = total;
    _aboardPassengers = aboard;
    _missingPassengers = total - aboard;
  }

  // ─── OSRM ROUTING ───────────────────────────────────────────

  Future<void> _calculateAllRouteSegments() async {
    _routeSegments = {};

    if (_itinerary.length < 2) return;

    for (int i = 0; i < _itinerary.length - 1; i++) {
      final stop1 = _itinerary[i];
      final stop2 = _itinerary[i + 1];
      final lat1 = (stop1['lat'] as num?)?.toDouble();
      final lng1 = (stop1['lng'] as num?)?.toDouble();
      final lat2 = (stop2['lat'] as num?)?.toDouble();
      final lng2 = (stop2['lng'] as num?)?.toDouble();

      if (lat1 != null && lng1 != null && lat2 != null && lng2 != null) {
        try {
          final result = await _fetchOsrmRoute(lat1, lng1, lat2, lng2);
          if (result != null) {
            _routeSegments[i] = result;
          }
        } catch (e) {
          AppLogger.log('OSRM segment $i error: $e');
        }
      }
    }
  }

  Future<Map<String, dynamic>?> _fetchOsrmRoute(
      double lat1, double lng1, double lat2, double lng2) async {
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '$lng1,$lat1;$lng2,$lat2'
        '?overview=full&geometries=polyline&alternatives=false&steps=false',
      );

      final response =
          await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 'Ok' &&
            data['routes'] != null &&
            (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];
          final distanceM = (route['distance'] as num).toDouble();
          final durationS = (route['duration'] as num).toDouble();
          final geometry = route['geometry'] as String;
          final polyline = _decodePolyline(geometry);

          return {
            'km': distanceM / 1000,
            'mi': distanceM / 1609.344,
            'min': durationS / 60,
            'polyline': polyline,
          };
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      int shift = 0;
      int result = 0;
      int byte;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1F) << shift;
        shift += 5;
      } while (byte >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      shift = 0;
      result = 0;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1F) << shift;
        shift += 5;
      } while (byte >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  // ─── STOP ACTIONS ───────────────────────────────────────────

  Future<void> _markStopArrived(int stopIndex) async {
    HapticService.mediumImpact();
    try {
      final result =
          await _eventService.markStopArrived(widget.eventId, stopIndex);
      if (result.isNotEmpty) {
        HapticService.success();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        'Llegada registrada: ${_itinerary[stopIndex]['name'] ?? 'Parada ${stopIndex + 1}'}'),
                  ),
                ],
              ),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al registrar llegada: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _markStopDeparted(int stopIndex) async {
    HapticService.mediumImpact();
    try {
      await _client
          .from('tourism_event_itinerary')
          .update({
            'departed_at': DateTime.now().toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('event_id', widget.eventId)
          .eq('stop_order', stopIndex);

      HapticService.success();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.departure_board,
                    color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      'Salida registrada: ${_itinerary[stopIndex]['name'] ?? 'Parada ${stopIndex + 1}'}'),
                ),
              ],
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al registrar salida: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ─── EDIT MODE: CRUD ────────────────────────────────────────

  Future<void> _addStop() async {
    final result = await _showStopDialog();
    if (result == null) return;

    try {
      final newOrder = _itinerary.length;
      await _client.from('tourism_event_itinerary').insert({
        'event_id': widget.eventId,
        'stop_order': newOrder,
        'name': result['name'],
        'lat': result['lat'],
        'lng': result['lng'],
        'scheduled_time': result['scheduled_time'],
        'duration_minutes': result['duration'] ?? 30,
        'notes': result['notes'],
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

      HapticService.success();
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al agregar parada: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _editStop(int index) async {
    final stop = _itinerary[index];
    final result = await _showStopDialog(existingStop: stop);
    if (result == null) return;

    try {
      await _client.from('tourism_event_itinerary').update({
        'name': result['name'],
        'lat': result['lat'],
        'lng': result['lng'],
        'scheduled_time': result['scheduled_time'],
        'duration_minutes': result['duration'] ?? 30,
        'notes': result['notes'],
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', stop['id']);

      HapticService.success();
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al editar parada: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _deleteStop(int index) async {
    final stop = _itinerary[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Eliminar Parada',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Eliminar "${stop['name'] ?? 'Parada ${index + 1}'}"?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar',
                style: TextStyle(color: AppColors.textTertiary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child:
                const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _client
          .from('tourism_event_itinerary')
          .delete()
          .eq('id', stop['id']);

      // Reorder remaining stops
      for (int i = index + 1; i < _itinerary.length; i++) {
        await _client.from('tourism_event_itinerary').update({
          'stop_order': i - 1,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', _itinerary[i]['id']);
      }

      HapticService.success();
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al eliminar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // ─── STOP DIALOG (Nominatim + Map Picker) ──────────────────

  Future<Map<String, dynamic>?> _showStopDialog(
      {Map<String, dynamic>? existingStop}) async {
    final nameController =
        TextEditingController(text: existingStop?['name'] ?? '');
    final notesController =
        TextEditingController(text: existingStop?['notes'] ?? '');
    final durationController = TextEditingController(
      text: (existingStop?['duration_minutes'] ?? '').toString(),
    );
    if (durationController.text == 'null' ||
        durationController.text == '0') {
      durationController.text = '';
    }

    double? lat = (existingStop?['lat'] as num?)?.toDouble();
    double? lng = (existingStop?['lng'] as num?)?.toDouble();
    String? scheduledTime = existingStop?['scheduled_time'] as String?;

    // Parse scheduled_time to DateTime for picker
    DateTime? selectedDateTime;
    if (scheduledTime != null && scheduledTime.contains(':')) {
      final parts = scheduledTime.split(':');
      selectedDateTime = DateTime.now().copyWith(
        hour: int.tryParse(parts[0]) ?? 0,
        minute: int.tryParse(parts[1]) ?? 0,
      );
    }

    // Autocomplete
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
            void fetchSuggestions(String query) {
              if (query.trim().isEmpty) {
                setModalState(() {
                  suggestions = [];
                  showSuggestions = false;
                });
                return;
              }

              debounceTimer?.cancel();
              debounceTimer =
                  Timer(const Duration(milliseconds: 500), () async {
                try {
                  final url = Uri.parse(
                    'https://nominatim.openstreetmap.org/search'
                    '?q=${Uri.encodeComponent(query)}'
                    '&format=jsonv2'
                    '&countrycodes=mx,us'
                    '&limit=5'
                    '&addressdetails=1'
                    '&accept-language=es',
                  );

                  final response = await http.get(url,
                      headers: {'User-Agent': 'TORORide/1.0'});

                  if (response.statusCode == 200) {
                    final results = json.decode(response.body) as List;
                    setModalState(() {
                      suggestions = results.map((r) {
                        final name = (r['name'] as String?) ?? '';
                        final displayName = r['display_name'] as String;
                        return {
                          'place_name': displayName,
                          'text': name.isNotEmpty
                              ? name
                              : displayName.split(',').first.trim(),
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
                  bottom: MediaQuery.of(context).viewInsets.bottom),
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          const Icon(Icons.add_location_alt,
                              color: AppColors.primary, size: 24),
                          const SizedBox(width: 12),
                          Text(
                            existingStop != null
                                ? 'Editar Parada'
                                : 'Nueva Parada',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close,
                                color: AppColors.textSecondary),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Address field + Map button
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: nameController,
                                  style: const TextStyle(
                                      color: AppColors.textPrimary),
                                  decoration: InputDecoration(
                                    labelText: 'Dirección',
                                    hintText:
                                        'Escribe o selecciona en mapa',
                                    prefixIcon: const Icon(Icons.place,
                                        color: AppColors.textSecondary),
                                    suffixIcon: lat != null && lng != null
                                        ? const Icon(Icons.check_circle,
                                            color: Colors.green, size: 20)
                                        : null,
                                    border: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(8),
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
                                    final result = await showDialog<
                                        Map<String, dynamic>>(
                                      context: context,
                                      builder: (context) =>
                                          _ItineraryMapPicker(
                                        title: 'Seleccionar Ubicación',
                                        initialLocation:
                                            lat != null && lng != null
                                                ? LatLng(lat!, lng!)
                                                : null,
                                      ),
                                    );
                                    if (result != null) {
                                      setModalState(() {
                                        lat = result['coords']['lat'];
                                        lng = result['coords']['lng'];
                                        nameController.text =
                                            result['address'] ?? '';
                                        showSuggestions = false;
                                      });
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                  ),
                                  child: const Icon(Icons.map,
                                      color: Colors.white, size: 20),
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
                                border: Border.all(
                                    color: AppColors.textTertiary
                                        .withOpacity(0.2)),
                              ),
                              constraints:
                                  const BoxConstraints(maxHeight: 200),
                              child: ListView.separated(
                                shrinkWrap: true,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                itemCount: suggestions.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: 1,
                                  color: AppColors.textTertiary
                                      .withOpacity(0.1),
                                ),
                                itemBuilder: (context, index) {
                                  final suggestion = suggestions[index];
                                  return InkWell(
                                    onTap: () {
                                      setModalState(() {
                                        lat =
                                            suggestion['lat'] as double;
                                        lng =
                                            suggestion['lng'] as double;
                                        nameController.text =
                                            suggestion['text'] as String;
                                        showSuggestions = false;
                                      });
                                      FocusScope.of(context).unfocus();
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 10),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.location_on,
                                              color: AppColors.primary,
                                              size: 18),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  suggestion['text']
                                                      as String,
                                                  style: const TextStyle(
                                                    color: AppColors
                                                        .textPrimary,
                                                    fontSize: 14,
                                                    fontWeight:
                                                        FontWeight.w500,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  suggestion['place_name']
                                                      as String,
                                                  style: const TextStyle(
                                                    color: AppColors
                                                        .textSecondary,
                                                    fontSize: 12,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
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

                      // Date/time picker
                      InkWell(
                        onTap: () async {
                          DateTime initial =
                              selectedDateTime ?? DateTime.now();
                          await showDialog(
                            context: context,
                            builder: (BuildContext builder) {
                              DateTime temp = initial;
                              return Dialog(
                                backgroundColor: Colors.transparent,
                                child: Container(
                                  height: 380,
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius:
                                        BorderRadius.circular(20),
                                  ),
                                  child: Column(
                                    children: [
                                      Container(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 12),
                                        decoration: const BoxDecoration(
                                          color: AppColors.background,
                                          borderRadius:
                                              BorderRadius.vertical(
                                                  top: Radius.circular(
                                                      20)),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment
                                                  .spaceBetween,
                                          children: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context),
                                              child: const Text(
                                                  'Cancelar',
                                                  style: TextStyle(
                                                      color: AppColors
                                                          .textSecondary)),
                                            ),
                                            const Text(
                                              'Fecha y Hora',
                                              style: TextStyle(
                                                color:
                                                    AppColors.textPrimary,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 16,
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: () {
                                                setModalState(() {
                                                  selectedDateTime = temp;
                                                });
                                                Navigator.pop(context);
                                              },
                                              child: const Text('Listo',
                                                  style: TextStyle(
                                                      color:
                                                          AppColors.primary,
                                                      fontWeight:
                                                          FontWeight.w600)),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        child: CupertinoDatePicker(
                                          mode: CupertinoDatePickerMode
                                              .dateAndTime,
                                          initialDateTime: initial,
                                          minimumDate: DateTime.now()
                                              .subtract(const Duration(
                                                  hours: 1)),
                                          maximumDate: DateTime.now()
                                              .add(const Duration(
                                                  days: 365)),
                                          use24hFormat: false,
                                          onDateTimeChanged:
                                              (DateTime newDT) {
                                            temp = newDT;
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
                            prefixIcon: const Icon(Icons.event,
                                color: AppColors.textSecondary),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            selectedDateTime != null
                                ? '${selectedDateTime!.day}/${selectedDateTime!.month}/${selectedDateTime!.year} ${selectedDateTime!.hour.toString().padLeft(2, '0')}:${selectedDateTime!.minute.toString().padLeft(2, '0')}'
                                : 'Seleccionar fecha y hora',
                            style: TextStyle(
                              color: selectedDateTime != null
                                  ? AppColors.textPrimary
                                  : AppColors.textTertiary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Duration
                      TextFormField(
                        controller: durationController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                            color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          labelText: 'Duración de parada (minutos)',
                          hintText: 'Ej: 15',
                          prefixIcon: const Icon(Icons.timer,
                              color: AppColors.textSecondary),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Notes
                      TextFormField(
                        controller: notesController,
                        maxLines: 3,
                        style: const TextStyle(
                            color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          labelText: 'Notas (opcional)',
                          hintText: 'Información adicional',
                          prefixIcon: const Icon(Icons.notes,
                              color: AppColors.textSecondary),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Save button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (nameController.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Ingresa la dirección de la parada')),
                              );
                              return;
                            }

                            String? timeStr;
                            if (selectedDateTime != null) {
                              timeStr =
                                  '${selectedDateTime!.hour.toString().padLeft(2, '0')}:${selectedDateTime!.minute.toString().padLeft(2, '0')}';
                            }

                            Navigator.pop(context, {
                              'name': nameController.text.trim(),
                              'lat': lat,
                              'lng': lng,
                              'scheduled_time': timeStr,
                              'duration': durationController.text.isNotEmpty
                                  ? int.tryParse(durationController.text)
                                  : null,
                              'notes':
                                  notesController.text.trim().isNotEmpty
                                      ? notesController.text.trim()
                                      : null,
                            });
                          },
                          icon:
                              const Icon(Icons.check, color: Colors.white),
                          label: Text(
                            existingStop != null
                                ? 'Guardar Cambios'
                                : 'Agregar Parada',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
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

  // ─── NOTIFICATIONS ─────────────────────────────────────────

  Future<void> _notifyPassengers() async {
    HapticService.lightImpact();

    final currentStop = _currentStopIndex < _itinerary.length
        ? _itinerary[_currentStopIndex]
        : null;
    final stopName =
        currentStop?['name'] ?? 'Parada ${_currentStopIndex + 1}';

    final message = await showDialog<String>(
      context: context,
      builder: (ctx) => _NotifyPassengersDialog(
        defaultMessage: 'Hemos llegado a $stopName',
        stopName: stopName,
      ),
    );

    if (message == null || message.isEmpty) return;
    if (!mounted) return;

    final authProvider =
        Provider.of<AuthProvider>(context, listen: false);
    final driver = authProvider.driver;
    if (driver == null) return;

    try {
      final success = await _messagingService.sendAnnouncement(
        eventId: widget.eventId,
        senderId: driver.id,
        senderType: 'organizer',
        senderName: driver.name,
        message: message,
        pin: true,
        senderAvatarUrl: driver.profileImageUrl,
      );

      if (success && mounted) {
        HapticService.success();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.campaign, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Anuncio enviado'),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // ─── BUILD ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? _buildErrorState()
              : RefreshIndicator(
                  color: AppColors.primary,
                  backgroundColor: AppColors.surface,
                  onRefresh: _loadData,
                  child: _buildContent(),
                ),
      floatingActionButton: _buildFAB(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final eventName = _event?['event_name'] ?? 'Itinerario';
    final completedStops =
        _itinerary.where((s) => s['departed_at'] != null).length;
    final totalStops = _itinerary.length;

    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
        onPressed: () {
          HapticService.lightImpact();
          Navigator.pop(context);
        },
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eventName,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (totalStops > 0)
            Text(
              'Parada ${_currentStopIndex + 1} de $totalStops',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
      actions: [
        // Edit toggle
        IconButton(
          icon: Icon(
            _isEditMode ? Icons.check : Icons.edit,
            color: _isEditMode ? AppColors.success : AppColors.textSecondary,
          ),
          onPressed: () {
            HapticService.lightImpact();
            setState(() => _isEditMode = !_isEditMode);
          },
        ),
        // Progress indicator
        if (totalStops > 0)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: SizedBox(
                width: 36,
                height: 36,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: totalStops > 0
                          ? completedStops / totalStops
                          : 0,
                      backgroundColor: AppColors.border,
                      color: AppColors.success,
                      strokeWidth: 3,
                    ),
                    Text(
                      '${((completedStops / totalStops) * 100).round()}%',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: AppColors.error.withOpacity(0.7)),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Error desconocido',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadData,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_itinerary.isEmpty) {
      return _buildEmptyState();
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        // Total route summary
        _buildRouteSummary(),
        const SizedBox(height: 12),
        // Timeline
        _buildTimeline(),
        const SizedBox(height: 100), // Space for FAB
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.route_outlined,
                size: 64,
                color: AppColors.textTertiary.withOpacity(0.5)),
            const SizedBox(height: 16),
            const Text(
              'Sin itinerario',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Agrega paradas para crear el recorrido',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _addStop,
              icon: const Icon(Icons.add_location_alt),
              label: const Text('Agregar Primera Parada'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── ROUTE SUMMARY ─────────────────────────────────────────

  Widget _buildRouteSummary() {
    double totalKm = 0;
    double totalMin = 0;
    for (final seg in _routeSegments.values) {
      totalKm += (seg['km'] as num?)?.toDouble() ?? 0;
      totalMin += (seg['min'] as num?)?.toDouble() ?? 0;
    }

    if (totalKm == 0) return const SizedBox.shrink();

    final totalMi = totalKm * 0.621371;
    final hours = (totalMin / 60).floor();
    final mins = (totalMin % 60).round();
    final timeStr =
        hours > 0 ? '${hours}h ${mins}m' : '${mins} min';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.route, color: AppColors.primary, size: 18),
          const SizedBox(width: 8),
          Text(
            '${totalMi.toStringAsFixed(1)} mi',
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withOpacity(0.5),
            ),
          ),
          Text(
            timeStr,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withOpacity(0.5),
            ),
          ),
          Text(
            '${_itinerary.length} paradas',
            style: TextStyle(
              color: AppColors.primary.withOpacity(0.8),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ─── TIMELINE ──────────────────────────────────────────────

  Widget _buildTimeline() {
    return Column(
      children: List.generate(_itinerary.length, (index) {
        final stop = _itinerary[index];
        final isCurrentStop = index == _currentStopIndex;
        final hasArrived = stop['arrived_at'] != null;
        final hasDeparted = stop['departed_at'] != null;
        final isLastStop = index == _itinerary.length - 1;

        return Column(
          children: [
            _buildTimelineItem(
              index: index,
              stop: stop,
              isCurrentStop: isCurrentStop,
              hasArrived: hasArrived,
              hasDeparted: hasDeparted,
              isLastStop: isLastStop,
            ),
            // OSRM distance between this and next stop
            if (!isLastStop && _routeSegments.containsKey(index))
              _buildDistanceIndicator(index),
          ],
        );
      }),
    );
  }

  Widget _buildDistanceIndicator(int segmentIndex) {
    final seg = _routeSegments[segmentIndex]!;
    final mi = (seg['mi'] as num?)?.toDouble() ?? 0;
    final min = (seg['min'] as num?)?.toDouble() ?? 0;

    return Container(
      margin: const EdgeInsets.only(left: 16, bottom: 4, top: 4),
      child: Row(
        children: [
          Container(
            width: 2,
            height: 30,
            margin: const EdgeInsets.only(left: 18),
            color: AppColors.border,
          ),
          const SizedBox(width: 16),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.info.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: AppColors.info.withOpacity(0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.directions_car,
                    size: 12, color: AppColors.info),
                const SizedBox(width: 6),
                Text(
                  '${mi.toStringAsFixed(1)} mi',
                  style: TextStyle(
                    color: AppColors.info,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 3,
                  height: 3,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.info.withOpacity(0.5),
                  ),
                ),
                Text(
                  '${min.round()} min',
                  style: TextStyle(
                    color: AppColors.info,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem({
    required int index,
    required Map<String, dynamic> stop,
    required bool isCurrentStop,
    required bool hasArrived,
    required bool hasDeparted,
    required bool isLastStop,
  }) {
    final stopName = stop['name'] ?? 'Parada ${index + 1}';
    final address = stop['address'] as String?;
    final scheduledTime = stop['scheduled_time'] as String?;
    final durationMinutes =
        (stop['duration_minutes'] as num?)?.toInt() ?? 30;
    final notes = stop['notes'] as String?;

    DateTime? arrivedAt;
    DateTime? departedAt;
    if (stop['arrived_at'] != null) {
      arrivedAt = DateTime.tryParse(stop['arrived_at']);
    }
    if (stop['departed_at'] != null) {
      departedAt = DateTime.tryParse(stop['departed_at']);
    }

    Color statusColor;
    String statusLabel;
    if (hasDeparted) {
      statusColor = AppColors.success;
      statusLabel = 'Completada';
    } else if (hasArrived) {
      statusColor = AppColors.warning;
      statusLabel = 'En parada';
    } else if (isCurrentStop) {
      statusColor = AppColors.primary;
      statusLabel = 'Siguiente';
    } else {
      statusColor = AppColors.textTertiary;
      statusLabel = 'Pendiente';
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timeline dot
        SizedBox(
          width: 40,
          child: Column(
            children: [
              if (index > 0)
                Container(
                    width: 3,
                    height: 8,
                    color: hasDeparted || hasArrived
                        ? AppColors.success
                        : AppColors.border),
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Container(
                    width: isCurrentStop ? 32 : 24,
                    height: isCurrentStop ? 32 : 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hasDeparted
                          ? AppColors.success
                          : (hasArrived
                              ? AppColors.warning
                              : (isCurrentStop
                                  ? AppColors.primary
                                  : AppColors.card)),
                      border: Border.all(
                        color: statusColor,
                        width: isCurrentStop ? 3 : 2,
                      ),
                      boxShadow: isCurrentStop
                          ? [
                              BoxShadow(
                                color: statusColor.withOpacity(
                                    _pulseAnimation.value * 0.5),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: hasDeparted
                          ? const Icon(Icons.check,
                              color: Colors.white, size: 14)
                          : hasArrived
                              ? const Icon(Icons.location_on,
                                  color: Colors.white, size: 14)
                              : Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    color: isCurrentStop
                                        ? Colors.white
                                        : AppColors.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        // Content card
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isCurrentStop
                  ? AppColors.primary.withOpacity(0.1)
                  : AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isCurrentStop
                    ? AppColors.primary.withOpacity(0.5)
                    : AppColors.border,
                width: isCurrentStop ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        stopName,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: isCurrentStop
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                    // Edit/delete buttons
                    if (_isEditMode) ...[
                      GestureDetector(
                        onTap: () => _editStop(index),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          child: const Icon(Icons.edit,
                              size: 16, color: AppColors.primary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _deleteStop(index),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          child: const Icon(Icons.delete,
                              size: 16, color: AppColors.error),
                        ),
                      ),
                    ] else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                // Compact passenger KPIs — only on current stop
                if (isCurrentStop && _totalPassengers > 0) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.people, size: 13, color: AppColors.textTertiary),
                      const SizedBox(width: 3),
                      Text('$_totalPassengers', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 10),
                      Icon(Icons.how_to_reg, size: 13, color: AppColors.success),
                      const SizedBox(width: 3),
                      Text('$_aboardPassengers', style: const TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 10),
                      Icon(Icons.person_off, size: 13, color: _missingPassengers > 0 ? AppColors.warning : AppColors.success),
                      const SizedBox(width: 3),
                      Text('$_missingPassengers', style: TextStyle(color: _missingPassengers > 0 ? AppColors.warning : AppColors.success, fontSize: 12, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                // Info chips
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (scheduledTime != null)
                      _buildChip(Icons.schedule, scheduledTime,
                          AppColors.textTertiary),
                    _buildChip(Icons.timer, '$durationMinutes min',
                        AppColors.info),
                    if (notes != null && notes.isNotEmpty)
                      _buildChip(Icons.notes, notes,
                          AppColors.textTertiary),
                  ],
                ),
                // Actual times
                if (arrivedAt != null || departedAt != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (arrivedAt != null)
                        _buildChip(
                            Icons.check_circle,
                            'Llegó: ${_formatTime(arrivedAt)}',
                            AppColors.success),
                      if (departedAt != null) ...[
                        const SizedBox(width: 8),
                        _buildChip(
                            Icons.check_circle,
                            'Salió: ${_formatTime(departedAt)}',
                            AppColors.success),
                      ],
                    ],
                  ),
                ],
                // Action buttons
                if (!hasDeparted && !_isEditMode) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (!hasArrived)
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _markStopArrived(index),
                            icon: const Icon(Icons.check_circle_outline,
                                size: 16),
                            label: const Text('Llegué',
                                style: TextStyle(fontSize: 13)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      if (hasArrived)
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _markStopDeparted(index),
                            icon: const Icon(Icons.departure_board,
                                size: 16),
                            label: const Text('Salir',
                                style: TextStyle(fontSize: 13)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiBox({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: color.withOpacity(0.7),
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _buildFAB() {
    if (_isEditMode) {
      return FloatingActionButton.extended(
        heroTag: 'addStop',
        onPressed: _addStop,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_location_alt),
        label: const Text('Agregar Parada'),
      );
    }

    if (_itinerary.isEmpty) return null;

    return FloatingActionButton.extended(
      heroTag: 'notify',
      onPressed: _notifyPassengers,
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.campaign),
      label: const Text('Notificar'),
    );
  }

  String _formatTime(DateTime time) {
    final localTime = time.toLocal();
    return '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
  }
}

// ─── NOTIFY PASSENGERS DIALOG ──────────────────────────────

class _NotifyPassengersDialog extends StatefulWidget {
  final String defaultMessage;
  final String stopName;

  const _NotifyPassengersDialog({
    required this.defaultMessage,
    required this.stopName,
  });

  @override
  State<_NotifyPassengersDialog> createState() =>
      _NotifyPassengersDialogState();
}

class _NotifyPassengersDialogState extends State<_NotifyPassengersDialog> {
  late TextEditingController _controller;
  final List<String> _quickMessages = [
    'Hemos llegado',
    'Salimos en 5 min',
    'Salimos en 10 min',
    'Regresen al bus',
    'Tiempo libre',
    'Hora de comer',
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.defaultMessage);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                const Icon(Icons.campaign, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Notificar Pasajeros',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on,
                      color: AppColors.warning, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.stopName,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Mensajes rápidos',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _quickMessages.map((msg) {
                return GestureDetector(
                  onTap: () {
                    HapticService.lightImpact();
                    _controller.text = msg;
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      msg,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              maxLines: 3,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Escribe un mensaje...',
                hintStyle: const TextStyle(color: AppColors.textTertiary),
                filled: true,
                fillColor: AppColors.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 2),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar',
              style: TextStyle(color: AppColors.textTertiary)),
        ),
        ElevatedButton.icon(
          onPressed: () {
            HapticService.mediumImpact();
            Navigator.pop(context, _controller.text);
          },
          icon: const Icon(Icons.send, size: 16),
          label: const Text('Enviar'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── MAP PICKER DIALOG ─────────────────────────────────────

class _ItineraryMapPicker extends StatefulWidget {
  final String title;
  final LatLng? initialLocation;

  const _ItineraryMapPicker({
    required this.title,
    this.initialLocation,
  });

  @override
  State<_ItineraryMapPicker> createState() => _ItineraryMapPickerState();
}

class _ItineraryMapPickerState extends State<_ItineraryMapPicker> {
  late MapController _mapController;
  late LatLng _currentCenter;
  late TextEditingController _searchController;
  String _addressText = 'Mueve el mapa para seleccionar';
  bool _isLoadingAddress = false;
  bool _isLoadingGPS = false;
  bool _isDragging = false;
  List<Map<String, dynamic>> _suggestions = [];
  bool _showSuggestions = false;
  Timer? _debounceTimer;

  static const _defaultCenter = LatLng(33.4484, -112.0740);

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _searchController = TextEditingController();
    _currentCenter = widget.initialLocation ?? _defaultCenter;

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
        final url = Uri.parse(
          'https://nominatim.openstreetmap.org/search'
          '?q=${Uri.encodeComponent(query)}'
          '&format=jsonv2'
          '&countrycodes=mx,us'
          '&limit=5'
          '&addressdetails=1'
          '&accept-language=es',
        );

        final response =
            await http.get(url, headers: {'User-Agent': 'TORORide/1.0'});

        if (response.statusCode == 200) {
          final results = json.decode(response.body) as List;
          if (mounted) {
            setState(() {
              _suggestions = results.map((r) {
                final name = (r['name'] as String?) ?? '';
                final displayName = r['display_name'] as String;
                return {
                  'place_name': displayName,
                  'text': name.isNotEmpty
                      ? name
                      : displayName.split(',').first.trim(),
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
          location.latitude, location.longitude);

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        List<String> parts = [];
        if (place.name != null &&
            place.name!.isNotEmpty &&
            place.name != place.street &&
            !RegExp(r'^\d+$').hasMatch(place.name!)) {
          parts.add(place.name!);
        }
        if (place.street != null && place.street!.isNotEmpty) {
          parts.add(place.street!);
        }
        if (place.locality != null && place.locality!.isNotEmpty) {
          parts.add(place.locality!);
        }
        if (place.administrativeArea != null &&
            place.administrativeArea!.isNotEmpty) {
          parts.add(place.administrativeArea!);
        }

        if (mounted) {
          setState(() {
            _addressText = parts.isNotEmpty
                ? parts.join(', ')
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
        setState(() => _isLoadingGPS = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
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
      if (mounted) setState(() => _isLoadingGPS = false);
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
                  if (hasGesture && !_isDragging) {
                    setState(() => _isDragging = true);
                  }
                  if (!hasGesture && _isDragging) {
                    setState(() {
                      _isDragging = false;
                      _currentCenter = _mapController.camera.center;
                    });
                    _reverseGeocode(_mapController.camera.center);
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

            // Search bar
            Positioned(
              top: 16,
              left: 16,
              right: 80,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4)),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(
                          fontSize: 14, color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Buscar dirección...',
                        hintStyle: TextStyle(color: Color(0xFF888888)),
                        prefixIcon: Icon(Icons.search,
                            color: Color(0xFFAAAAAA), size: 20),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                      onChanged: _fetchSuggestions,
                    ),
                  ),
                  if (_showSuggestions && _suggestions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 12),
                        ],
                      ),
                      constraints: const BoxConstraints(maxHeight: 250),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding:
                            const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _suggestions.length,
                        separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: Colors.white.withOpacity(0.1),
                            indent: 16,
                            endIndent: 16),
                        itemBuilder: (context, index) {
                          final s = _suggestions[index];
                          return InkWell(
                            onTap: () {
                              final loc = LatLng(s['lat'] as double,
                                  s['lng'] as double);
                              _mapController.move(loc, 16);
                              setState(() {
                                _currentCenter = loc;
                                _showSuggestions = false;
                                _searchController.text =
                                    s['text'] as String;
                              });
                              _reverseGeocode(loc);
                              FocusScope.of(context).unfocus();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  const Icon(Icons.location_on,
                                      color: Colors.orange, size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(s['text'] as String,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight:
                                                    FontWeight.w500)),
                                        const SizedBox(height: 2),
                                        Text(
                                            s['place_name'] as String,
                                            style: const TextStyle(
                                                color:
                                                    Color(0xFF888888),
                                                fontSize: 12),
                                            maxLines: 1,
                                            overflow: TextOverflow
                                                .ellipsis),
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

            // Center pin
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
                              offset: const Offset(0, 4)),
                        ],
                      ),
                      child: const Icon(Icons.location_on,
                          color: Colors.white, size: 28),
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

            // GPS button
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
                          blurRadius: 8),
                    ],
                  ),
                  child: _isLoadingGPS
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.orange))
                      : const Icon(Icons.my_location,
                          color: Colors.orange, size: 24),
                ),
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
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, -5)),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                              child: const Icon(Icons.location_on,
                                  color: Colors.red, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _isLoadingAddress
                                  ? const Row(
                                      children: [
                                        SizedBox(
                                            width: 16,
                                            height: 16,
                                            child:
                                                CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color:
                                                        Colors.orange)),
                                        SizedBox(width: 10),
                                        Text('Obteniendo dirección...',
                                            style: TextStyle(
                                                color: Color(0xFF999999),
                                                fontSize: 14)),
                                      ],
                                    )
                                  : Text(
                                      _addressText,
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
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
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Colors.orange,
                                Color(0xFFFF8C00)
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.orange.withOpacity(0.4),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4)),
                            ],
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle,
                                  color: Colors.white, size: 22),
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
