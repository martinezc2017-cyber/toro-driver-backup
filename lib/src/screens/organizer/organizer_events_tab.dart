import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';
import '../../services/tourism_event_service.dart';
import '../../services/organizer_service.dart';
import '../../config/supabase_config.dart';
import 'organizer_event_dashboard_screen.dart';
import 'organizer_create_event_simple_screen.dart';
import 'package:toro_driver/src/screens/organizer/organizer_bidding_screen.dart';
import '../tourism/tourism_driver_home_screen.dart';

/// Professional Events Management Tab for Organizers
class OrganizerEventsTab extends StatefulWidget {
  const OrganizerEventsTab({super.key});

  @override
  State<OrganizerEventsTab> createState() => _OrganizerEventsTabState();
}

class _OrganizerEventsTabState extends State<OrganizerEventsTab>
    with SingleTickerProviderStateMixin {
  final TourismEventService _eventService = TourismEventService();
  final OrganizerService _organizerService = OrganizerService();
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;
  String? _error;
  late TabController _tabController;

  // Stats
  int _totalEvents = 0;
  int _activeEvents = 0;
  int _totalPassengers = 0;
  double _totalRevenue = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadEvents();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadEvents() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) {
        setState(() {
          _error = 'No autenticado';
          _loading = false;
        });
        return;
      }

      var organizerData = await SupabaseConfig.client
          .from('organizers')
          .select('id')
          .eq('user_id', userId)
          .maybeSingle();

      if (organizerData == null) {
        final newOrganizerData = await SupabaseConfig.client
            .from('organizers')
            .insert({
              'user_id': userId,
              'created_at': DateTime.now().toIso8601String(),
            })
            .select('id')
            .single();
        organizerData = newOrganizerData;
      }

      final organizerId = organizerData['id'] as String;

      final orgEvents = await _eventService.getMyEvents(organizerId);
      final driverEvents = await _eventService.getEventsByDriver(userId);

      final existingIds = orgEvents.map((e) => e['id']).toSet();
      for (final de in driverEvents) {
        if (!existingIds.contains(de['id'])) {
          de['_is_driver_event'] = true;
          orgEvents.add(de);
        }
      }

      final events = orgEvents;

      int active = 0;
      int passengers = 0;
      double revenue = 0;
      int nonCancelledEvents = 0;

      for (final event in events) {
        final status = event['status'] ?? 'draft';
        if (status == 'cancelled' || status == 'deleted') continue;
        nonCancelledEvents++;
        if (status == 'active' || status == 'in_progress' || status == 'vehicle_accepted') {
          active++;
        }
        passengers += (event['confirmed_passengers'] as int?) ?? 0;
        revenue += (event['total_revenue'] as num?)?.toDouble() ?? 0;
      }

      setState(() {
        _events = events;
        _totalEvents = nonCancelledEvents;
        _activeEvents = active;
        _totalPassengers = passengers;
        _totalRevenue = revenue;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _getFilteredEvents(int tabIndex) {
    final now = DateTime.now();
    return _events.where((event) {
      final status = event['status'] ?? 'draft';
      if (status == 'cancelled' || status == 'deleted') return false;

      final eventDateStr = event['event_date'] as String?;
      DateTime? eventDate;
      if (eventDateStr != null) {
        try { eventDate = DateTime.parse(eventDateStr); } catch (_) {}
      }

      switch (tabIndex) {
        case 0: return true;
        case 1: return status == 'active' || status == 'in_progress' || status == 'vehicle_accepted';
        case 2: return eventDate != null && eventDate.isAfter(now) && status != 'completed';
        case 3: return status == 'completed';
        default: return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header compacto
            _buildHeader(),
            // Tab bar
            _buildTabBar(),
            // Content
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : _error != null
                      ? _buildError()
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildEventsList(0),
                            _buildEventsList(1),
                            _buildEventsList(2),
                            _buildEventsList(3),
                          ],
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
      child: Column(
        children: [
          // Title + refresh
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Mis Eventos',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: _loadEvents,
                icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // KPI row
          Row(
            children: [
              _buildKPI('$_totalEvents', 'Eventos', Icons.event, Colors.blue),
              const SizedBox(width: 10),
              _buildKPI('$_activeEvents', 'Activos', Icons.play_circle_fill, AppColors.success),
              const SizedBox(width: 10),
              _buildKPI('$_totalPassengers', 'Pasajeros', Icons.people, Colors.orange),
              const SizedBox(width: 10),
              _buildKPI('\$${_totalRevenue.toStringAsFixed(0)}', 'Ingresos', Icons.attach_money, AppColors.primary),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildKPI(String value, String label, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textTertiary,
        indicatorColor: AppColors.primary,
        indicatorWeight: 3,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 13),
        isScrollable: false,
        labelPadding: EdgeInsets.zero,
        tabs: const [
          Tab(text: 'Todos'),
          Tab(text: 'Activos'),
          Tab(text: 'Próximos'),
          Tab(text: 'Completos'),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: AppColors.error, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Error al cargar eventos',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadEvents,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventsList(int tabIndex) {
    final filteredEvents = _getFilteredEvents(tabIndex);

    if (filteredEvents.isEmpty) {
      return _buildEmptyState(tabIndex);
    }

    return RefreshIndicator(
      onRefresh: _loadEvents,
      color: AppColors.primary,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          // Phone: full width with 16px padding
          // Tablet: use 92% of width, max 800px
          final double hPad = w > 600
              ? ((w - (w * 0.92).clamp(0, 800)) / 2).clamp(16, double.infinity)
              : 16;
          return ListView.builder(
            padding: EdgeInsets.symmetric(
              horizontal: hPad,
              vertical: 12,
            ),
            itemCount: filteredEvents.length,
            itemBuilder: (context, index) => _buildEventCard(filteredEvents[index]),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(int tabIndex) {
    final labels = ['No tienes eventos creados', 'No tienes eventos activos',
                    'No tienes eventos próximos', 'No tienes eventos completados'];
    final icons = [Icons.event_busy, Icons.play_circle_outline,
                   Icons.upcoming, Icons.check_circle_outline];

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icons[tabIndex], color: AppColors.textTertiary, size: 48),
          const SizedBox(height: 16),
          Text(labels[tabIndex],
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 16)),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _createEvent,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Crear Evento'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventCard(Map<String, dynamic> event) {
    final eventName = event['event_name'] ?? 'Evento sin nombre';
    final eventDate = event['event_date'] as String?;
    final startTime = event['start_time'] as String?;
    final status = event['status'] ?? 'draft';
    final maxPassengers = event['max_passengers'] ?? 0;
    final confirmedPassengers = event['confirmed_passengers'] ?? 0;
    final itinerary = event['itinerary'] as List<dynamic>? ?? [];
    final distKm = (event['total_distance_km'] as num?)?.toDouble() ?? 0;
    final imageUrl = event['cover_image_url'] as String?;

    // Vehicle info (assigned vehicle on the event)
    final vehicle = event['bus_vehicles'] as Map<String, dynamic>?;
    final make = vehicle?['make'] as String?;
    final model = vehicle?['model'] as String?;
    final year = vehicle?['year'];
    final totalSeats = vehicle?['total_seats'] as int?;
    final ownerName = vehicle?['owner_name'] as String? ?? 'Sin chofer';
    final imageUrls = vehicle?['image_urls'] as List<dynamic>?;
    final vehiclePhoto = (imageUrls != null && imageUrls.isNotEmpty) ? imageUrls[0].toString() : null;

    // Find winning driver from bids
    final bids = event['tourism_vehicle_bids'] as List<dynamic>? ?? [];
    Map<String, dynamic>? winningBid;
    for (final b in bids) {
      final m = b as Map<String, dynamic>;
      if (m['organizer_status'] == 'selected' && m['is_winning_bid'] == true) {
        winningBid = m;
        break;
      }
    }
    final winningDriver = winningBid?['bid_driver'] as Map<String, dynamic>?;
    final driverName = winningDriver?['full_name'] as String? ?? winningDriver?['name'] as String? ?? ownerName;
    final driverPhone = winningDriver?['phone'] as String?;
    final driverPhoto = winningDriver?['profile_image_url'] as String?;

    // Date formatting
    String formattedDate = '';
    bool isToday = false;
    bool isTomorrow = false;
    if (eventDate != null) {
      try {
        final date = DateTime.parse(eventDate);
        final now = DateTime.now();
        isToday = date.year == now.year && date.month == now.month && date.day == now.day;
        isTomorrow = date.year == now.year && date.month == now.month && date.day == now.day + 1;
        if (isToday) {
          formattedDate = 'Hoy';
        } else if (isTomorrow) {
          formattedDate = 'Mañana';
        } else {
          formattedDate = DateFormat('d MMM').format(date);
        }
      } catch (_) {
        formattedDate = eventDate;
      }
    }

    String formattedTime = '';
    if (startTime != null && startTime.length >= 5) {
      formattedTime = startTime.substring(0, 5);
    }

    // Route
    String? originName;
    String? destinationName;
    if (itinerary.isNotEmpty) {
      originName = itinerary.first['name'] as String?;
      if (itinerary.length > 1) destinationName = itinerary.last['name'] as String?;
    }

    final urgentDate = isToday || status == 'in_progress';

    return GestureDetector(
      onTap: () => _openEventDashboard(event),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: urgentDate ? AppColors.primary.withOpacity(0.5) : AppColors.border,
            width: urgentDate ? 1.5 : 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover image
            if (imageUrl != null || vehiclePhoto != null)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                child: Image.network(
                  imageUrl ?? vehiclePhoto!,
                  height: 100,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Title + Status badge
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          eventName,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Builder(builder: (_) {
                        final bids = event['tourism_vehicle_bids'] as List<dynamic>? ?? [];
                        final currentUid = SupabaseConfig.client.auth.currentUser?.id;
                        final receivedBids = bids.where((b) {
                          final m = b as Map<String, dynamic>;
                          return m['driver_status'] == 'accepted'
                              && m['organizer_status'] == 'pending'
                              && m['driver_id'] != currentUid;
                        }).length;
                        final hasWinner = bids.any((b) {
                          final m = b as Map<String, dynamic>;
                          return m['organizer_status'] == 'selected' && m['is_winning_bid'] == true;
                        });
                        if (hasWinner) return _buildStatusChip('Chofer Asignado', AppColors.success);
                        if (receivedBids > 0 && (status == 'draft' || status == 'pending_vehicle')) {
                          return _buildStatusChip('$receivedBids Puja${receivedBids > 1 ? 's' : ''}', AppColors.primary);
                        }
                        return _buildStatusChip(_statusLabel(status), _statusColor(status));
                      }),
                    ],
                  ),

                  // Driver-assigned event badge
                  if (event['_is_driver_event'] == true) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.emoji_events, size: 14, color: AppColors.success),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Puja ganada — ${event['organizers']?['company_name'] ?? 'Organizador'}',
                              style: TextStyle(fontSize: 11, color: AppColors.success, fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 10),

                  // Row 2: Date + Time + Distance + Seats (unified info strip)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        if (formattedDate.isNotEmpty)
                          Expanded(
                            child: _infoChipCenter(Icons.calendar_today, formattedDate,
                                color: urgentDate ? AppColors.error : null),
                          ),
                        if (formattedTime.isNotEmpty)
                          Expanded(
                            child: _infoChipCenter(Icons.access_time, formattedTime,
                                color: urgentDate ? AppColors.error : null),
                          ),
                        if (distKm > 0)
                          Expanded(
                            child: _infoChipCenter(Icons.straighten, '${distKm.toStringAsFixed(0)} km'),
                          ),
                        Expanded(
                          child: _infoChipCenter(Icons.event_seat, '$confirmedPassengers/${totalSeats ?? maxPassengers}',
                              color: AppColors.success),
                        ),
                      ],
                    ),
                  ),

                  // Row 3: Route
                  if (originName != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(width: 7, height: 7,
                          decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(originName,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        if (destinationName != null) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(Icons.arrow_forward, size: 14, color: AppColors.textTertiary),
                          ),
                          Container(width: 7, height: 7,
                            decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(destinationName,
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ],
                    ),
                  ],

                  // Vehicle info (compact row)
                  if (vehicle != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        // Small vehicle photo
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: vehiclePhoto != null
                              ? Image.network(vehiclePhoto, width: 44, height: 44, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _vehicleIcon())
                              : _vehicleIcon(),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (make != null || model != null)
                                Text(
                                  '${make ?? ''} ${model ?? ''} ${year != null ? '($year)' : ''}'.trim(),
                                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                ),
                              Row(
                                children: [
                                  if (driverPhoto != null)
                                    CircleAvatar(
                                      radius: 8,
                                      backgroundImage: NetworkImage(driverPhoto),
                                    )
                                  else
                                    const Icon(Icons.person_outline, size: 13, color: AppColors.textTertiary),
                                  const SizedBox(width: 3),
                                  Expanded(
                                    child: Text(driverName,
                                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ),
                                  if (driverPhone != null) ...[
                                    const SizedBox(width: 4),
                                    Icon(Icons.phone, size: 11, color: AppColors.textTertiary),
                                    const SizedBox(width: 2),
                                    Text(driverPhone,
                                      style: const TextStyle(color: AppColors.textTertiary, fontSize: 10)),
                                  ],
                                  // Seats shown in unified info strip above
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Warning: no driver/vehicle
                  if (event['_is_driver_event'] != true && (event['driver_id'] == null || vehicle == null)) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              event['driver_id'] == null ? 'Falta chofer con unidad' : 'Falta asignar unidad',
                              style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Bid section
                  ..._buildBidSection(event),

                  // Bottom: "Administrar" button
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.primary, AppColors.primary.withOpacity(0.85)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.settings, size: 16, color: Colors.white),
                          SizedBox(width: 6),
                          Text('Administrar',
                            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vehicleIcon() {
    return Container(
      width: 44, height: 44,
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.directions_bus, color: AppColors.primary, size: 20),
    );
  }

  Widget _infoChip(IconData icon, String text, {Color? color}) {
    final c = color ?? AppColors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: c),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _infoChipCenter(IconData icon, String text, {Color? color}) {
    final c = color ?? AppColors.textSecondary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: c),
        const SizedBox(height: 3),
        Text(text,
          style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600),
          textAlign: TextAlign.center),
      ],
    );
  }

  List<Widget> _buildBidSection(Map<String, dynamic> event) {
    final bids = event['tourism_vehicle_bids'] as List<dynamic>?;
    if (bids == null || bids.isEmpty) return [];

    // Current user ID to filter out organizer's own bid
    final currentUserId = SupabaseConfig.client.auth.currentUser?.id;

    final pendingBids = bids.where((b) {
      final m = b as Map<String, dynamic>;
      if (m['driver_status'] != 'accepted' || m['organizer_status'] != 'pending') return false;
      // Filter out the organizer's own bid (same user bidding on their own event)
      if (m['driver_id'] == currentUserId) return false;
      return true;
    }).toList();

    if (pendingBids.isEmpty) return [];

    final eventId = event['id'] as String?;
    final totalDist = (event['total_distance_km'] as num?)?.toDouble() ?? 0;

    return [
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header - taps navigate to full bidding screen
            GestureDetector(
              onTap: eventId != null
                  ? () {
                      HapticService.lightImpact();
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => OrganizerBiddingScreen(eventId: eventId)),
                      ).then((_) => _loadEvents());
                    }
                  : null,
              child: Row(
                children: [
                  const Icon(Icons.gavel_rounded, size: 15, color: Colors.orange),
                  const SizedBox(width: 6),
                  Text(
                    '${pendingBids.length} Puja${pendingBids.length > 1 ? 's' : ''} Recibida${pendingBids.length > 1 ? 's' : ''}',
                    style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  const Text('Ver todas', style: TextStyle(color: Colors.orange, fontSize: 11)),
                  const SizedBox(width: 2),
                  const Icon(Icons.arrow_forward_ios, size: 10, color: Colors.orange),
                ],
              ),
            ),
            // Bid rows with real driver info + accept button
            ...pendingBids.take(3).map((b) {
              final bid = b as Map<String, dynamic>;
              final bidId = bid['id'] as String?;
              final price = (bid['proposed_price_per_km'] as num?)?.toDouble();
              final bidDriver = bid['bid_driver'] as Map<String, dynamic>?;
              final name = bidDriver?['full_name'] as String? ?? bidDriver?['name'] as String? ?? 'Chofer';
              final phone = bidDriver?['phone'] as String?;
              final totalPrice = price != null ? price * totalDist : null;

              // Vehicle info from the bid
              final bidVehicle = bid['bid_vehicle'] as Map<String, dynamic>?;
              final vMake = bidVehicle?['make'] as String?;
              final vModel = bidVehicle?['model'] as String?;
              final vYear = bidVehicle?['year'];
              final vSeats = bidVehicle?['total_seats'];
              final vPlate = bidVehicle?['plate'] as String?;
              final vehicleDesc = [
                if (vMake != null || vModel != null) '${vMake ?? ''} ${vModel ?? ''}'.trim(),
                if (vYear != null) '($vYear)',
                if (vSeats != null) '$vSeats asientos',
                if (vPlate != null) '• $vPlate',
              ].join(' ');

              return Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Driver avatar
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: AppColors.primary.withOpacity(0.15),
                          backgroundImage: bidDriver?['profile_image_url'] != null
                              ? NetworkImage(bidDriver!['profile_image_url'] as String)
                              : null,
                          child: bidDriver?['profile_image_url'] == null
                              ? Text(name[0].toUpperCase(),
                                  style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w700))
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                              if (phone != null)
                                Text(phone,
                                  style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
                            ],
                          ),
                        ),
                        // Price
                        if (price != null)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('\$${price.toStringAsFixed(1)}/km',
                                style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w700)),
                              if (totalPrice != null)
                                Text('Total \$${totalPrice.toStringAsFixed(0)}',
                                  style: const TextStyle(color: AppColors.textTertiary, fontSize: 10)),
                            ],
                          ),
                      ],
                    ),
                    // Vehicle info
                    if (vehicleDesc.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const SizedBox(width: 40), // align with name
                          const Icon(Icons.directions_bus, size: 12, color: AppColors.textTertiary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(vehicleDesc,
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ],
                    // Accept button
                    if (bidId != null && eventId != null) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: GestureDetector(
                          onTap: () => _acceptBidFromCard(bidId, eventId, name, price),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.success,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: Text('Aceptar Puja',
                                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    ];
  }

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'active': return 'Activo';
      case 'in_progress': return 'En Curso';
      case 'completed': return 'Completado';
      case 'cancelled': return 'Cancelado';
      case 'vehicle_accepted': return 'Chofer Asignado';
      case 'draft':
      case 'pending_vehicle': return 'Esperando Puja';
      default: return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active': return AppColors.success;
      case 'in_progress': return AppColors.primary;
      case 'completed': return Colors.blue;
      case 'cancelled': return AppColors.error;
      case 'vehicle_accepted': return AppColors.success;
      case 'draft':
      case 'pending_vehicle': return Colors.orange;
      default: return AppColors.textTertiary;
    }
  }

  Widget _buildFAB() {
    return FloatingActionButton.extended(
      onPressed: _createEvent,
      backgroundColor: AppColors.primary,
      elevation: 4,
      icon: const Icon(Icons.add, color: Colors.white),
      label: const Text('Nuevo Evento',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
    );
  }

  Future<void> _acceptBidFromCard(String bidId, String eventId, String driverName, double? price) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Aceptar Puja', style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Chofer: $driverName',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
            if (price != null) ...[
              const SizedBox(height: 4),
              Text('Precio: \$${price.toStringAsFixed(2)}/km',
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Las demás pujas serán rechazadas automáticamente',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.success),
            child: const Text('Confirmar', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    HapticService.mediumImpact();

    try {
      await _organizerService.selectWinningBid(bidId, eventId);

      if (mounted) {
        HapticService.success();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Puja de $driverName aceptada'), backgroundColor: AppColors.success),
        );
        _loadEvents();
      }
    } catch (e) {
      if (mounted) {
        HapticService.error();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _openEventDashboard(Map<String, dynamic> event) {
    HapticService.lightImpact();
    final eventId = event['id'] as String?;
    if (eventId == null) return;

    final isDriverEvent = event['_is_driver_event'] == true;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => isDriverEvent
            ? TourismDriverHomeScreen(eventId: eventId)
            : OrganizerEventDashboardScreen(eventId: eventId),
      ),
    ).then((_) => _loadEvents());
  }

  void _createEvent() {
    HapticService.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OrganizerCreateEventSimpleScreen()),
    ).then((_) => _loadEvents());
  }
}
