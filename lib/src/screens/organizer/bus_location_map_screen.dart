import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/organizer_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';

/// Real-time map for tourism events showing:
/// - Events from the organizer
/// - Accepted invitees with GPS locations
/// - Driver/bus location
class BusLocationMapScreen extends StatefulWidget {
  final String? routeId;
  final String? routeName;

  const BusLocationMapScreen({
    super.key,
    this.routeId,
    this.routeName,
  });

  @override
  State<BusLocationMapScreen> createState() => _BusLocationMapScreenState();
}

class _BusLocationMapScreenState extends State<BusLocationMapScreen> {
  final OrganizerService _organizerService = OrganizerService();
  final MapController _mapController = MapController();
  final _client = Supabase.instance.client;

  List<Map<String, dynamic>> _tourismEvents = [];
  List<Map<String, dynamic>> _invitees = [];
  Map<String, dynamic>? _selectedEvent;
  Map<String, dynamic>? _selectedInvitee;
  Map<String, dynamic>? _driverLocation;
  bool _isLoading = true;
  bool _isLoadingInvitees = false;
  RealtimeChannel? _inviteesChannel;
  RealtimeChannel? _driverChannel;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadTourismEvents();
    // Refresh locations every 10 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_selectedEvent != null) {
        _refreshInviteeLocations();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    if (_inviteesChannel != null) {
      _client.removeChannel(_inviteesChannel!);
      _inviteesChannel = null;
    }
    if (_driverChannel != null) {
      _client.removeChannel(_driverChannel!);
      _driverChannel = null;
    }
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadTourismEvents() async {
    setState(() => _isLoading = true);
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;

      // Get organizer ID
      final organizerResponse = await _client
          .from('organizers')
          .select('id')
          .eq('user_id', userId)
          .maybeSingle();

      if (organizerResponse == null) {
        setState(() => _isLoading = false);
        return;
      }

      final organizerId = organizerResponse['id'];

      // Get events for this organizer
      final eventsResponse = await _client
          .from('tourism_events')
          .select('''
            id,
            name,
            event_date,
            start_time,
            status,
            destination_lat,
            destination_lng,
            destination_name,
            driver_id,
            vehicle_id
          ''')
          .eq('organizer_id', organizerId)
          .inFilter('status', ['active', 'in_progress', 'vehicle_accepted'])
          .order('event_date', ascending: true);

      if (mounted) {
        setState(() {
          _tourismEvents = List<Map<String, dynamic>>.from(eventsResponse);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading tourism events: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadInviteesForEvent(String eventId) async {
    setState(() => _isLoadingInvitees = true);
    try {
      // Load accepted invitees with GPS locations
      final response = await _client
          .from('tourism_invitations')
          .select('''
            id,
            invited_name,
            invited_email,
            invited_phone,
            status,
            current_check_in_status,
            last_known_lat,
            last_known_lng,
            last_gps_update,
            gps_tracking_enabled,
            seat_number,
            boarding_stop,
            dropoff_stop,
            checked_in,
            updated_at
          ''')
          .eq('event_id', eventId)
          .inFilter('status', ['accepted', 'boarded', 'checked_in']);

      if (mounted) {
        setState(() {
          _invitees = List<Map<String, dynamic>>.from(response);
          _isLoadingInvitees = false;
        });
        _subscribeToInviteeUpdates(eventId);
      }
    } catch (e) {
      debugPrint('Error loading invitees: $e');
      if (mounted) {
        setState(() => _isLoadingInvitees = false);
      }
    }
  }

  Future<void> _loadDriverLocation(String? driverId) async {
    if (driverId == null) return;
    try {
      final response = await _client
          .from('drivers')
          .select('id, current_lat, current_lng, full_name')
          .eq('id', driverId)
          .maybeSingle();

      if (mounted && response != null) {
        setState(() => _driverLocation = response);
      }
    } catch (e) {
      debugPrint('Error loading driver location: $e');
    }
  }

  Future<void> _refreshInviteeLocations() async {
    if (_selectedEvent == null) return;
    final eventId = _selectedEvent!['id'];
    try {
      final response = await _client
          .from('tourism_invitations')
          .select('id, last_known_lat, last_known_lng, last_gps_update, gps_tracking_enabled, checked_in, updated_at')
          .eq('event_id', eventId)
          .inFilter('status', ['accepted', 'boarded', 'checked_in']);

      if (mounted) {
        setState(() {
          for (final updated in response) {
            final index = _invitees.indexWhere((i) => i['id'] == updated['id']);
            if (index != -1) {
              _invitees[index]['last_known_lat'] = updated['last_known_lat'];
              _invitees[index]['last_known_lng'] = updated['last_known_lng'];
              _invitees[index]['checked_in'] = updated['checked_in'];
              _invitees[index]['updated_at'] = updated['updated_at'];
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error refreshing invitee locations: $e');
    }
  }

  void _subscribeToInviteeUpdates(String eventId) {
    if (_inviteesChannel != null) {
      _client.removeChannel(_inviteesChannel!);
      _inviteesChannel = null;
    }
    _inviteesChannel = _client
        .channel('invitees_$eventId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'tourism_invitations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'event_id',
            value: eventId,
          ),
          callback: (payload) {
            final updated = payload.newRecord;
            if (updated.isNotEmpty && mounted) {
              setState(() {
                final index = _invitees.indexWhere((i) => i['id'] == updated['id']);
                if (index != -1) {
                  _invitees[index] = {..._invitees[index], ...updated};
                }
              });
            }
          },
        )
        .subscribe();
  }

  void _selectEvent(Map<String, dynamic> event) {
    HapticService.lightImpact();
    setState(() {
      _selectedEvent = event;
      _selectedInvitee = null;
      _invitees = [];
    });
    _loadInviteesForEvent(event['id']);
    _loadDriverLocation(event['driver_id']);

    // Center on destination if available
    final lat = (event['destination_lat'] as num?)?.toDouble();
    final lng = (event['destination_lng'] as num?)?.toDouble();
    if (lat != null && lng != null) {
      _mapController.move(LatLng(lat, lng), 12);
    }
  }

  void _selectInvitee(Map<String, dynamic> invitee) {
    HapticService.lightImpact();
    setState(() => _selectedInvitee = invitee);

    // Center on invitee location
    final lat = (invitee['last_known_lat'] as num?)?.toDouble();
    final lng = (invitee['last_known_lng'] as num?)?.toDouble();
    if (lat != null && lng != null) {
      _mapController.move(LatLng(lat, lng), 15);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este pasajero no tiene ubicación GPS disponible'),
          backgroundColor: AppColors.warning,
        ),
      );
    }
  }

  void _goBackToEvents() {
    setState(() {
      _selectedEvent = null;
      _selectedInvitee = null;
      _invitees = [];
      _driverLocation = null;
    });
    if (_inviteesChannel != null) {
      _client.removeChannel(_inviteesChannel!);
      _inviteesChannel = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () {
            if (_selectedEvent != null) {
              _goBackToEvents();
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Text(
          _selectedEvent != null
              ? _selectedEvent!['name'] ?? 'Evento'
              : 'Mapa en Tiempo Real',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
            onPressed: () {
              HapticService.lightImpact();
              if (_selectedEvent != null) {
                _refreshInviteeLocations();
              } else {
                _loadTourismEvents();
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : Column(
              children: [
                // Map - flex 3
                Expanded(
                  flex: 3,
                  child: Stack(
                    children: [
                      _buildMap(),
                      // Badge showing counts
                      Positioned(
                        top: 16,
                        left: 16,
                        child: _buildCountBadge(),
                      ),
                      // Selected invitee card
                      if (_selectedInvitee != null)
                        Positioned(
                          bottom: 16,
                          left: 16,
                          right: 16,
                          child: _buildSelectedInviteeCard(),
                        ),
                    ],
                  ),
                ),
                // Bottom panel - flex 2
                Expanded(
                  flex: 2,
                  child: _selectedEvent != null
                      ? _buildInviteesList()
                      : _buildEventsList(),
                ),
              ],
            ),
    );
  }

  Widget _buildMap() {
    // Default center (Arizona)
    LatLng center = const LatLng(33.4484, -112.0740);
    double zoom = 10;

    // Center on selected event destination
    if (_selectedEvent != null) {
      final lat = (_selectedEvent!['destination_lat'] as num?)?.toDouble();
      final lng = (_selectedEvent!['destination_lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        center = LatLng(lat, lng);
        zoom = 12;
      }
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        onTap: (_, _) {
          setState(() => _selectedInvitee = null);
        },
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.toro.driver',
        ),
        MarkerLayer(
          markers: _buildMarkers(),
        ),
      ],
    );
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // Add event destination marker
    if (_selectedEvent != null) {
      final lat = (_selectedEvent!['destination_lat'] as num?)?.toDouble();
      final lng = (_selectedEvent!['destination_lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        markers.add(
          Marker(
            point: LatLng(lat, lng),
            width: 50,
            height: 50,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.5),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(Icons.flag, color: Colors.white, size: 24),
            ),
          ),
        );
      }
    }

    // Add driver/bus marker
    if (_driverLocation != null) {
      final lat = (_driverLocation!['current_lat'] as num?)?.toDouble();
      final lng = (_driverLocation!['current_lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        markers.add(
          Marker(
            point: LatLng(lat, lng),
            width: 50,
            height: 50,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.success,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.success.withValues(alpha: 0.5),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: const Icon(Icons.directions_bus, color: Colors.white, size: 24),
            ),
          ),
        );
      }
    }

    // Add invitee markers
    for (final invitee in _invitees) {
      final lat = (invitee['last_known_lat'] as num?)?.toDouble();
      final lng = (invitee['last_known_lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      final isSelected = _selectedInvitee?['id'] == invitee['id'];
      final isCheckedIn = invitee['checked_in'] == true;

      markers.add(
        Marker(
          point: LatLng(lat, lng),
          width: isSelected ? 50 : 40,
          height: isSelected ? 50 : 40,
          child: GestureDetector(
            onTap: () => _selectInvitee(invitee),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? AppColors.primary
                    : (isCheckedIn ? AppColors.purple : AppColors.warning),
                border: Border.all(
                  color: Colors.white,
                  width: isSelected ? 3 : 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isSelected
                            ? AppColors.primary
                            : (isCheckedIn ? AppColors.purple : AppColors.warning))
                        .withValues(alpha: 0.5),
                    blurRadius: isSelected ? 12 : 8,
                  ),
                ],
              ),
              child: Icon(
                isCheckedIn ? Icons.check_circle : Icons.person,
                color: Colors.white,
                size: isSelected ? 24 : 18,
              ),
            ),
          ),
        ),
      );
    }

    return markers;
  }

  Widget _buildCountBadge() {
    if (_selectedEvent == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event, color: AppColors.primary, size: 18),
            const SizedBox(width: 8),
            Text(
              '${_tourismEvents.length} eventos',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    final withGps = _invitees.where((i) =>
        i['last_known_lat'] != null && i['last_known_lng'] != null).length;
    final checkedIn = _invitees.where((i) => i['checked_in'] == true).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.people, color: AppColors.primary, size: 18),
          const SizedBox(width: 8),
          Text(
            '$withGps/${_invitees.length} con GPS',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.purple.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, size: 12, color: AppColors.purple),
                const SizedBox(width: 3),
                Text(
                  '$checkedIn',
                  style: const TextStyle(
                    color: AppColors.purple,
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

  Widget _buildSelectedInviteeCard() {
    final invitee = _selectedInvitee!;
    final name = invitee['invited_name'] ?? 'Pasajero';
    final isCheckedIn = invitee['checked_in'] == true;
    final hasGps = invitee['last_known_lat'] != null;
    final updatedAt = invitee['updated_at'] != null
        ? DateTime.tryParse(invitee['updated_at'])
        : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isCheckedIn
                      ? AppColors.purple.withValues(alpha: 0.2)
                      : AppColors.warning.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isCheckedIn ? Icons.check_circle : Icons.person,
                  color: isCheckedIn ? AppColors.purple : AppColors.warning,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isCheckedIn
                                ? AppColors.purple.withValues(alpha: 0.15)
                                : AppColors.warning.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isCheckedIn ? 'Check-in ✓' : 'Pendiente',
                            style: TextStyle(
                              color: isCheckedIn
                                  ? AppColors.purple
                                  : AppColors.warning,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (hasGps) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.gps_fixed,
                              size: 12, color: AppColors.success),
                          const SizedBox(width: 4),
                          Text(
                            updatedAt != null
                                ? _formatTimeAgo(updatedAt)
                                : 'GPS activo',
                            style: const TextStyle(
                              color: AppColors.success,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.textTertiary),
                onPressed: () => setState(() => _selectedInvitee = null),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEventsList() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.event, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Mis Eventos',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_tourismEvents.length} activos',
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: AppColors.border, height: 1),
          Expanded(
            child: _tourismEvents.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event_busy,
                            size: 32,
                            color: AppColors.textTertiary.withValues(alpha: 0.5)),
                        const SizedBox(height: 8),
                        const Text(
                          'Sin eventos activos',
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _tourismEvents.length,
                    separatorBuilder: (_, _) =>
                        const Divider(color: AppColors.border, height: 1),
                    itemBuilder: (context, index) =>
                        _buildEventRow(_tourismEvents[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventRow(Map<String, dynamic> event) {
    final name = event['name'] ?? 'Evento';
    final destination = event['destination_name'] ?? '';
    final status = event['status'] ?? 'active';
    final eventDate = event['event_date'] != null
        ? DateTime.tryParse(event['event_date'])
        : null;
    final startTime = event['start_time'] as String?;

    return InkWell(
      onTap: () => _selectEvent(event),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _getStatusColor(status).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _getStatusIcon(status),
                color: _getStatusColor(status),
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (eventDate != null) ...[
                        Text(
                          _formatDate(eventDate),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                        if (startTime != null) ...[
                          const Text(
                            '  •  ',
                            style: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            startTime,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                  if (destination.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.location_on,
                            size: 10, color: AppColors.textTertiary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            destination,
                            style: const TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 10,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getStatusColor(status).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _getStatusLabel(status),
                style: TextStyle(
                  color: _getStatusColor(status),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: AppColors.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteesList() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _goBackToEvents,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.arrow_back,
                        size: 16, color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.people, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Pasajeros',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_invitees.length} aceptados',
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: AppColors.border, height: 1),
          Expanded(
            child: _isLoadingInvitees
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : _invitees.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people_outline,
                                size: 32,
                                color: AppColors.textTertiary.withValues(alpha: 0.5)),
                            const SizedBox(height: 8),
                            const Text(
                              'Sin pasajeros aceptados',
                              style: TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _invitees.length,
                        separatorBuilder: (_, _) =>
                            const Divider(color: AppColors.border, height: 1),
                        itemBuilder: (context, index) =>
                            _buildInviteeRow(_invitees[index]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildInviteeRow(Map<String, dynamic> invitee) {
    final name = invitee['invited_name'] ?? 'Pasajero';
    final phone = invitee['invited_phone'] as String?;
    final isCheckedIn = invitee['checked_in'] == true;
    final hasGps =
        invitee['last_known_lat'] != null && invitee['last_known_lng'] != null;
    final isSelected = _selectedInvitee?['id'] == invitee['id'];

    return InkWell(
      onTap: () => _selectInvitee(invitee),
      child: Container(
        color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isCheckedIn
                    ? AppColors.purple.withValues(alpha: 0.15)
                    : AppColors.warning.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isCheckedIn ? Icons.check_circle : Icons.person,
                color: isCheckedIn ? AppColors.purple : AppColors.warning,
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (phone != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      phone,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Status badges
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Check-in status
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: isCheckedIn
                        ? AppColors.purple.withValues(alpha: 0.1)
                        : AppColors.card,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isCheckedIn ? 'Check-in ✓' : 'Pendiente',
                    style: TextStyle(
                      color: isCheckedIn
                          ? AppColors.purple
                          : AppColors.textTertiary,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // GPS indicator
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: hasGps
                        ? AppColors.success.withValues(alpha: 0.1)
                        : AppColors.card,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    hasGps ? Icons.gps_fixed : Icons.gps_off,
                    size: 12,
                    color: hasGps ? AppColors.success : AppColors.textTertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.my_location,
              size: 18,
              color: hasGps ? AppColors.primary : AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'in_progress':
        return AppColors.success;
      case 'active':
      case 'vehicle_accepted':
        return AppColors.primary;
      case 'completed':
        return AppColors.purple;
      default:
        return AppColors.textTertiary;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'in_progress':
        return Icons.play_arrow;
      case 'active':
      case 'vehicle_accepted':
        return Icons.event_available;
      case 'completed':
        return Icons.check_circle;
      default:
        return Icons.event;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'in_progress':
        return 'En curso';
      case 'active':
        return 'Activo';
      case 'vehicle_accepted':
        return 'Vehículo OK';
      case 'completed':
        return 'Completado';
      default:
        return status;
    }
  }

  String _formatDate(DateTime date) {
    final months = [
      'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
      'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'
    ];
    return '${date.day} ${months[date.month - 1]}';
  }

  String _formatTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);

    if (diff.inSeconds < 60) {
      return 'Ahora';
    } else if (diff.inMinutes < 60) {
      return 'Hace ${diff.inMinutes}m';
    } else if (diff.inHours < 24) {
      return 'Hace ${diff.inHours}h';
    } else {
      return 'Hace ${diff.inDays}d';
    }
  }
}
