import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';
import '../../services/tourism_event_service.dart';
import '../../services/organizer_service.dart';
import '../../config/supabase_config.dart';

import 'organizer_agreement_screen.dart';
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

  // Organizer identity & agreement
  String? _organizerId;
  bool _agreementSigned = false;

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
          .select('id, agreement_signed')
          .eq('user_id', userId)
          .maybeSingle();

      if (organizerData == null) {
        final newOrganizerData = await SupabaseConfig.client
            .from('organizers')
            .insert({
              'user_id': userId,
              'created_at': DateTime.now().toIso8601String(),
            })
            .select('id, agreement_signed')
            .single();
        organizerData = newOrganizerData;
      }

      final organizerId = organizerData['id'] as String;
      _organizerId = organizerId;
      _agreementSigned = organizerData['agreement_signed'] == true;

      // Parallel fetch: organizer events + driver events
      final results = await Future.wait([
        _eventService.getMyEvents(organizerId),
        _eventService.getEventsByDriver(userId),
      ]);
      final orgEvents = results[0];
      final driverEvents = results[1];

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
    final hasEvents = _events.where((e) {
      final s = e['status'] ?? 'draft';
      return s != 'cancelled' && s != 'deleted';
    }).isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header compacto
            _buildHeader(),
            // Tab bar only when there are events
            if (hasEvents) _buildTabBar(),
            // Content
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : _error != null
                      ? _buildError()
                      : hasEvents
                          ? TabBarView(
                              controller: _tabController,
                              children: [
                                _buildEventsList(0),
                                _buildEventsList(1),
                                _buildEventsList(2),
                                _buildEventsList(3),
                              ],
                            )
                          : _buildWelcomeEmpty(),
            ),
          ],
        ),
      ),
      floatingActionButton: hasEvents ? _buildFAB() : null,
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 8, 0),
      child: Row(
        children: [
          const Expanded(
            child: Text('Mis Eventos',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          GestureDetector(
            onTap: _loadEvents,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.refresh_rounded, color: AppColors.textSecondary, size: 16),
            ),
          ),
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
    final labels = ['No tienes eventos', 'No tienes eventos activos',
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
        ],
      ),
    );
  }

  Widget _buildExampleRow(String emoji, String text) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  /// Welcome screen when organizer has zero events - EPIC VERSION
  Widget _buildWelcomeEmpty() {
    return _AnimatedEmptyState(
      onCreateEvent: _createEvent,
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
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: urgentDate ? AppColors.primary.withOpacity(0.5) : AppColors.border,
            width: urgentDate ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail (cover or vehicle photo)
            if (imageUrl != null || vehiclePhoto != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  imageUrl ?? vehiclePhoto!,
                  width: 60, height: 60, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _vehicleIcon(),
                ),
              )
            else
              _vehicleIcon(),
            const SizedBox(width: 10),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Title + Status
                  Row(
                    children: [
                      Expanded(
                        child: Text(eventName,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
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
                        if (hasWinner) return _buildStatusChip('Asignado', AppColors.success);
                        if (receivedBids > 0 && (status == 'draft' || status == 'pending_vehicle')) {
                          return _buildStatusChip('$receivedBids Puja${receivedBids > 1 ? 's' : ''}', AppColors.primary);
                        }
                        return _buildStatusChip(_statusLabel(status), _statusColor(status));
                      }),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Row 2: Date + Time + Km + Passengers inline
                  Row(
                    children: [
                      if (formattedDate.isNotEmpty) ...[
                        Icon(Icons.calendar_today, size: 10, color: urgentDate ? AppColors.error : AppColors.textTertiary),
                        const SizedBox(width: 2),
                        Text(formattedDate, style: TextStyle(color: urgentDate ? AppColors.error : AppColors.textSecondary, fontSize: 10)),
                        const SizedBox(width: 6),
                      ],
                      if (formattedTime.isNotEmpty) ...[
                        Icon(Icons.access_time, size: 10, color: urgentDate ? AppColors.error : AppColors.textTertiary),
                        const SizedBox(width: 2),
                        Text(formattedTime, style: TextStyle(color: urgentDate ? AppColors.error : AppColors.textSecondary, fontSize: 10)),
                        const SizedBox(width: 6),
                      ],
                      if (distKm > 0) ...[
                        const Icon(Icons.straighten, size: 10, color: AppColors.textTertiary),
                        const SizedBox(width: 2),
                        Text('${distKm.toStringAsFixed(0)} km', style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                        const SizedBox(width: 6),
                      ],
                      Icon(Icons.event_seat, size: 10, color: AppColors.success),
                      const SizedBox(width: 2),
                      Text('$confirmedPassengers/${maxPassengers > 0 ? maxPassengers : totalSeats ?? 0}',
                        style: const TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Row 3: Route
                  if (originName != null)
                    Row(
                      children: [
                        Container(width: 5, height: 5, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                        const SizedBox(width: 4),
                        Flexible(child: Text(originName, style: const TextStyle(color: AppColors.textTertiary, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        if (destinationName != null) ...[
                          const Padding(padding: EdgeInsets.symmetric(horizontal: 3), child: Icon(Icons.arrow_forward, size: 10, color: AppColors.textTertiary)),
                          Container(width: 5, height: 5, decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle)),
                          const SizedBox(width: 4),
                          Flexible(child: Text(destinationName, style: const TextStyle(color: AppColors.textTertiary, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        ],
                      ],
                    ),
                  // Vehicle/driver compact
                  if (vehicle != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.directions_bus, size: 10, color: AppColors.textTertiary),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            '${make ?? ''} ${model ?? ''} ${year != null ? '($year)' : ''} · $driverName'.trim(),
                            style: const TextStyle(color: AppColors.textTertiary, fontSize: 10),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  // Driver-assigned badge
                  if (event['_is_driver_event'] == true) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.emoji_events, size: 10, color: AppColors.success),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text('Puja ganada — ${event['organizers']?['company_name'] ?? 'Organizador'}',
                            style: TextStyle(fontSize: 10, color: AppColors.success, fontWeight: FontWeight.w600),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ],
                  // Warning
                  if (event['_is_driver_event'] != true && (event['driver_id'] == null || vehicle == null)) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 10, color: Colors.orange),
                        const SizedBox(width: 3),
                        Text(event['driver_id'] == null ? 'Falta chofer' : 'Falta unidad',
                          style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ],
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
      label: const Text('Nuevo',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
    );
  }

  void _showServiceTypeSheet() {
    HapticService.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              '¿Qué quieres organizar?',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildSheetOption(
              emoji: '\u{1F68C}', title: 'Ruta Fija',
              subtitle: 'Microbús, camión, escolar',
              color: const Color(0xFF2196F3),
              onTap: () { Navigator.pop(ctx); _createEventWithType('fixed_route'); },
            ),
            _buildSheetOption(
              emoji: '\u{1F3D6}', title: 'Tour / Paseo',
              subtitle: 'Excursión, turismo, playa',
              color: const Color(0xFFFF9800),
              onTap: () { Navigator.pop(ctx); _createEventWithType('tourism'); },
            ),
            _buildSheetOption(
              emoji: '\u{1F3C8}', title: 'Evento Especial',
              subtitle: 'Boda, fiesta, concierto',
              color: const Color(0xFF9C27B0),
              onTap: () { Navigator.pop(ctx); _createEventWithType('special_event'); },
            ),
            _buildSheetOption(
              emoji: '\u{270B}', title: '¿Quién más va?',
              subtitle: 'Junta gente al mismo destino',
              color: const Color(0xFF4CAF50),
              onTap: () { Navigator.pop(ctx); _createEventWithType('shared_trip'); },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSheetOption({
    required String emoji,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticService.buttonPress();
        onTap();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700)),
                  Text(subtitle, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color.withOpacity(0.4), size: 16),
          ],
        ),
      ),
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

  /// Gate: check agreement before allowing event creation.
  Future<void> _ensureAgreementThen(VoidCallback onAgreementOk) async {
    if (_agreementSigned) {
      onAgreementOk();
      return;
    }
    if (_organizerId == null) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => OrganizerAgreementScreen(organizerId: _organizerId!),
      ),
    );

    if (result == true && mounted) {
      setState(() => _agreementSigned = true);
      onAgreementOk();
    }
  }

  void _createEvent() {
    HapticService.lightImpact();
    _ensureAgreementThen(() {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const OrganizerCreateEventSimpleScreen()),
      ).then((_) => _loadEvents());
    });
  }

  void _createEventWithType(String serviceType) {
    HapticService.lightImpact();
    _ensureAgreementThen(() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OrganizerCreateEventSimpleScreen(serviceType: serviceType),
        ),
      ).then((_) => _loadEvents());
    });
  }
}


// ============================================================
// EPIC EMPTY STATE WIDGET - Matching Splash Screen Quality
// ============================================================

/// Animated empty state with particle background and glassmorphism
class _AnimatedEmptyState extends StatefulWidget {
  final VoidCallback onCreateEvent;

  const _AnimatedEmptyState({required this.onCreateEvent});

  @override
  State<_AnimatedEmptyState> createState() => _AnimatedEmptyStateState();
}

class _AnimatedEmptyStateState extends State<_AnimatedEmptyState>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _floatController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _floatAnimation;
  late Animation<double> _pulseAnimation;

  final List<_Particle> _particles = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _initParticles();
    _initAnimations();
    _startAnimations();
  }

  void _initParticles() {
    for (int i = 0; i < 40; i++) {
      _particles.add(_Particle(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        size: _random.nextDouble() * 2 + 0.5,
        speedX: (_random.nextDouble() - 0.5) * 0.001,
        speedY: (_random.nextDouble() - 0.5) * 0.001,
        opacity: _random.nextDouble() * 0.5 + 0.3,
      ));
    }
  }

  void _initAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _floatController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);

    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutQuart,
    );

    _floatAnimation = Tween<double>(begin: 0, end: 10).animate(
      CurvedAnimation(
        parent: _floatController,
        curve: Curves.easeInOutSine,
      ),
    );

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );
  }

  void _startAnimations() {
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _floatController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Animated particle background
        _ParticleBackground(particles: _particles),

        // Main content
        FadeTransition(
          opacity: _fadeAnimation,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 40),

                  // Title with i18n
                  Text(
                    'organizer.first_trip_title'.tr(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 12),

                  // Subtitle
                  Text(
                    'organizer.first_trip_subtitle'.tr(),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 16,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 40),

                  // Glassmorphism examples card
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withOpacity(0.1),
                          Colors.white.withOpacity(0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.lightbulb_outline,
                                    color: AppColors.primary,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'organizer.examples'.tr(),
                                    style: TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _buildGlassExampleRow(Icons.directions_bus, 'organizer.example_bus'.tr()),
                              _buildGlassExampleRow(Icons.beach_access, 'organizer.example_beach'.tr()),
                              _buildGlassExampleRow(Icons.sports_football, 'organizer.example_sports'.tr()),
                              _buildGlassExampleRow(Icons.school, 'organizer.example_school'.tr()),
                              _buildGlassExampleRow(Icons.route, 'organizer.example_city'.tr()),
                              _buildGlassExampleRow(Icons.people, 'organizer.example_friends'.tr()),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Epic CTA Button
                  GestureDetector(
                    onTap: widget.onCreateEvent,
                    child: AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary,
                                AppColors.primary.withOpacity(0.8),
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.4 * _pulseAnimation.value),
                                blurRadius: 20,
                                spreadRadius: 4,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.add_circle_outline,
                                color: Colors.white,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'organizer.create_trip'.tr(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGlassExampleRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: Colors.white.withOpacity(0.9),
              size: 18,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Particle background similar to splash screen
class _ParticleBackground extends StatefulWidget {
  final List<_Particle> particles;

  const _ParticleBackground({required this.particles});

  @override
  State<_ParticleBackground> createState() => _ParticleBackgroundState();
}

class _ParticleBackgroundState extends State<_ParticleBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size.infinite,
          painter: _ParticlePainter(
            particles: widget.particles,
            progress: _controller.value,
          ),
        );
      },
    );
  }
}

class _Particle {
  double x, y;
  double size;
  double speedX, speedY;
  double opacity;

  _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speedX,
    required this.speedY,
    required this.opacity,
  });
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;

  _ParticlePainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    // Dark gradient background
    final bgPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF0A1628),
          const Color(0xFF050A10),
        ],
        stops: const [0.0, 1.0],
      ).createShader(
        Rect.fromCenter(
          center: Offset(size.width / 2, size.height / 2),
          width: size.width,
          height: size.height,
        ),
      );
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Draw particles
    for (var particle in particles) {
      particle.x += particle.speedX;
      particle.y += particle.speedY;

      // Wrap around
      if (particle.x < 0) particle.x = 1;
      if (particle.x > 1) particle.x = 0;
      if (particle.y < 0) particle.y = 1;
      if (particle.y > 1) particle.y = 0;

      final paint = Paint()
        ..color = AppColors.primary.withOpacity(particle.opacity * 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

      canvas.drawCircle(
        Offset(particle.x * size.width, particle.y * size.height),
        particle.size,
        paint,
      );
    }

    // Draw connections
    final linePaint = Paint()
      ..strokeWidth = 0.5
      ..color = AppColors.primary.withOpacity(0.1);

    for (int i = 0; i < particles.length; i++) {
      for (int j = i + 1; j < particles.length; j++) {
        final dx = (particles[i].x - particles[j].x) * size.width;
        final dy = (particles[i].y - particles[j].y) * size.height;
        final dist = sqrt(dx * dx + dy * dy);

        if (dist < 100) {
          linePaint.color = AppColors.primary.withOpacity(0.1 * (1 - dist / 100));
          canvas.drawLine(
            Offset(particles[i].x * size.width, particles[i].y * size.height),
            Offset(particles[j].x * size.width, particles[j].y * size.height),
            linePaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
