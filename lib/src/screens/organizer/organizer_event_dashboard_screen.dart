import 'dart:async';
import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' as intl;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../services/organizer_service.dart';
import '../../services/tourism_event_service.dart';
import '../../services/tourism_invitation_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';
import '../../widgets/scrollable_time_picker.dart';
import '../tourism/tourism_chat_screen.dart';
import '../../widgets/tourism_chat_widget.dart';
import '../../services/tourism_messaging_service.dart';
import 'organizer_invite_screen.dart';
import 'organizer_edit_event_screen.dart';
import 'organizer_passengers_screen.dart';
import 'organizer_itinerary_screen.dart';
import 'organizer_photos_screen.dart';
import 'organizer_profile_screen.dart';
import 'organizer_vehicle_selection_screen.dart';
import 'organizer_bidding_screen.dart';

String _fmtPrice(double v) => intl.NumberFormat('#,##0', 'es_MX').format(v.round());

/// Main event management dashboard for organizers.
///
/// Displays event details, KPIs, financial breakdown, real-time map,
/// and check-in activity for a specific tourism event.
class OrganizerEventDashboardScreen extends StatefulWidget {
  final String eventId;

  const OrganizerEventDashboardScreen({
    super.key,
    required this.eventId,
  });

  @override
  State<OrganizerEventDashboardScreen> createState() =>
      _OrganizerEventDashboardScreenState();
}

class _OrganizerEventDashboardScreenState
    extends State<OrganizerEventDashboardScreen>
    {
  final TourismEventService _eventService = TourismEventService();
  final TourismInvitationService _invitationService =
      TourismInvitationService();

  Map<String, dynamic>? _event;
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _checkIns = [];
  List<Map<String, dynamic>> _passengerLocations = [];
  List<Map<String, dynamic>> _pickupRequests = [];
  Map<String, dynamic>? _driverLocation;
  int _pendingPickupsCount = 0;
  List<Map<String, dynamic>> _joinRequests = [];
  List<Map<String, dynamic>> _allInvitations = [];
  bool _isLoading = true;
  String? _error;
  int _currentTabIndex = 0;
  bool _isFinanceExpanded = false;
  bool _isStopsExpanded = false;
  bool _isPickupsExpanded = true;

  // Pricing editor
  final TextEditingController _pricePerKmController = TextEditingController();
  bool _isPriceSaving = false;

  // Notification tools state
  bool _isSendingEmergency = false;
  bool _isSendingAnnouncement = false;

  // Chat unread badge
  final TourismMessagingService _chatService = TourismMessagingService();
  int _chatUnreadCount = 0;

  // Resend invitation cooldown (5 min per invitation)
  final Map<String, DateTime> _resendCooldowns = {};

  // Reviews
  List<Map<String, dynamic>> _reviews = [];

  RealtimeChannel? _eventChannel;
  RealtimeChannel? _locationChannel;
  RealtimeChannel? _driverLocationChannel;
  RealtimeChannel? _busEventsChannel;
  RealtimeChannel? _checkInChannel;
  RealtimeChannel? _joinRequestsChannel;
  RealtimeChannel? _invitationsChannel;
  RealtimeChannel? _reviewsChannel;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _subscribeToUpdates();
    _subscribeToChatUnread();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadStats();
      _loadPassengerLocations();
      _loadAllInvitations();
    });
  }

  /// Subscribe to real-time chat messages to update unread badge count.
  void _subscribeToChatUnread() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.driver?.id;
    if (userId == null) return;

    // Load initial unread count
    _chatService.getMessages(widget.eventId).then((messages) {
      if (!mounted) return;
      final unread = messages
          .where((m) => m.senderId != userId && !m.readBy.contains(userId))
          .length;
      setState(() => _chatUnreadCount = unread);
    }).catchError((_) {});

    // Real-time: use keyed subscription to avoid overwriting parent's channel
    _chatService.subscribeWithKey('dashboard', widget.eventId, (newMessage) {
      if (!mounted) return;
      if (newMessage.senderId != userId) {
        setState(() => _chatUnreadCount++);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _pricePerKmController.dispose();
    _chatService.unsubscribeKey('dashboard');
    final client = Supabase.instance.client;
    if (_eventChannel != null) {
      client.removeChannel(_eventChannel!);
      _eventChannel = null;
    }
    if (_locationChannel != null) {
      client.removeChannel(_locationChannel!);
      _locationChannel = null;
    }
    if (_driverLocationChannel != null) {
      client.removeChannel(_driverLocationChannel!);
      _driverLocationChannel = null;
    }
    if (_busEventsChannel != null) {
      client.removeChannel(_busEventsChannel!);
      _busEventsChannel = null;
    }
    if (_checkInChannel != null) {
      client.removeChannel(_checkInChannel!);
      _checkInChannel = null;
    }
    if (_joinRequestsChannel != null) {
      client.removeChannel(_joinRequestsChannel!);
      _joinRequestsChannel = null;
    }
    if (_invitationsChannel != null) {
      client.removeChannel(_invitationsChannel!);
      _invitationsChannel = null;
    }
    if (_reviewsChannel != null) {
      client.removeChannel(_reviewsChannel!);
      _reviewsChannel = null;
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await Future.wait([
        _loadEvent(),
        _loadStats(),
        _loadCheckIns(),
        _loadPassengerLocations(),
        _loadPickupRequests(),
        _loadJoinRequests(),
        _loadAllInvitations(),
        _loadReviews(),
      ]);

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Error al cargar datos: $e';
        });
      }
    }
  }

  Future<void> _loadPickupRequests() async {
    final requests = await _invitationService.getPickupRequests(widget.eventId);
    final pending = await _invitationService.countPendingPickups(widget.eventId);
    if (mounted) {
      setState(() {
        _pickupRequests = requests;
        _pendingPickupsCount = pending;
      });
    }
  }

  Future<void> _loadAllInvitations() async {
    final invitations = await _invitationService.getEventInvitations(widget.eventId);
    if (mounted) {
      setState(() => _allInvitations = invitations);
    }
  }

  Future<void> _loadEvent() async {
    final event = await _eventService.getEvent(widget.eventId);
    debugPrint('LOAD_EVENT -> event: $event');
    debugPrint('LOAD_EVENT -> drivers: ${event?['drivers']}');
    debugPrint('LOAD_EVENT -> driver_id: ${event?['driver_id']}');
    if (mounted && event != null) {
      final currentPricePerKm = (event['price_per_km'] as num?)?.toDouble() ?? 1.0;
      _pricePerKmController.text = currentPricePerKm.toStringAsFixed(2);
      setState(() => _event = event);
      _eventService.validateEventCompleteness(widget.eventId);
    }
  }

  Future<void> _loadStats() async {
    final stats = await _invitationService.getInvitationStats(widget.eventId);
    if (mounted) {
      setState(() => _stats = stats);
    }
  }

  Future<void> _loadCheckIns() async {
    final checkIns = await _invitationService.getEventCheckIns(widget.eventId);
    if (mounted) {
      setState(() => _checkIns = checkIns);
    }
  }

  Future<void> _loadPassengerLocations() async {
    debugPrint('DASH_GPS -> Loading passenger locations...');
    final locations =
        await _invitationService.getPassengerLocations(widget.eventId);
    debugPrint('DASH_GPS -> Got ${locations.length} locations');
    for (final loc in locations) {
      debugPrint('DASH_GPS -> ${loc['invitee_name']}: lat=${loc['lat']}, lng=${loc['lng']}');
    }
    if (mounted) {
      setState(() => _passengerLocations = locations);
    }
  }

  Future<void> _loadReviews() async {
    try {
      final reviews = await Supabase.instance.client
          .from('tourism_event_reviews')
          .select()
          .eq('event_id', widget.eventId)
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() => _reviews = List<Map<String, dynamic>>.from(reviews));
      }
    } catch (_) {
      // Table may not exist yet — ignore silently
    }
  }

  void _subscribeToUpdates() {
    _eventChannel = _eventService.subscribeToEvent(
      widget.eventId,
      (event) {
        if (!mounted) return;
        // Use addPostFrameCallback to avoid setState during build/layout phase
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          // Preserve joined data (drivers, organizers, vehicles) when merging realtime updates
          final currentDrivers = _event?['drivers'];
          final currentOrganizers = _event?['organizers'];
          final currentVehicles = _event?['bus_vehicles'];

          setState(() {
            _event = {...?_event, ...event};

            // Restore joined data if not present in realtime update
            if (_event?['drivers'] == null && currentDrivers != null) {
              _event!['drivers'] = currentDrivers;
            }
            if (_event?['organizers'] == null && currentOrganizers != null) {
              _event!['organizers'] = currentOrganizers;
            }
            if (_event?['bus_vehicles'] == null && currentVehicles != null) {
              _event!['bus_vehicles'] = currentVehicles;
            }
          });
        });
      },
    );

    _locationChannel = _invitationService.subscribeToPassengerLocations(
      eventId: widget.eventId,
      onLocationUpdate: (location) {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            final index = _passengerLocations.indexWhere(
              (l) => l['invitation_id'] == location['invitation_id'],
            );
            if (index != -1) {
              _passengerLocations[index] = location;
            } else {
              _passengerLocations.add(location);
            }
          });
        });
      },
    );

    // Subscribe to driver GPS location in real-time
    _driverLocationChannel = Supabase.instance.client
        .channel('driver_location_${widget.eventId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bus_driver_location',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'route_id',
            value: widget.eventId,
          ),
          callback: (payload) {
            if (!mounted || payload.newRecord.isEmpty) return;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                _driverLocation = payload.newRecord;
              });
            });
          },
        )
        .subscribe();

    // Subscribe to bus events (arrivals, departures) in real-time
    _busEventsChannel = Supabase.instance.client
        .channel('bus_events_${widget.eventId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'bus_events',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'route_id',
            value: widget.eventId,
          ),
          callback: (payload) {
            if (!mounted || payload.newRecord.isEmpty) return;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _loadData();
            });
          },
        )
        .subscribe();

    // Subscribe to check-ins in real-time
    _checkInChannel = Supabase.instance.client
        .channel('checkins_${widget.eventId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'tourism_check_ins',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'event_id',
            value: widget.eventId,
          ),
          callback: (payload) {
            if (!mounted) return;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _loadCheckIns();
              _loadAllInvitations();
              _loadStats();
            });
          },
        )
        .subscribe();

    // Subscribe to invitation changes in real-time (accept, decline, status changes)
    _invitationsChannel = Supabase.instance.client
        .channel('invitations_${widget.eventId}')
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
            if (!mounted) return;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _loadAllInvitations();
              _loadStats();
            });
          },
        )
        .subscribe();

    // Subscribe to join requests in real-time
    _joinRequestsChannel = _eventService.subscribeToJoinRequests(
      widget.eventId,
      (payload) {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _loadJoinRequests();
        });
      },
    );

    // Subscribe to reviews in real-time (new reviews appear live)
    _reviewsChannel = Supabase.instance.client
        .channel('reviews_${widget.eventId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'tourism_event_reviews',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'event_id',
            value: widget.eventId,
          ),
          callback: (payload) {
            if (!mounted || payload.newRecord.isEmpty) return;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _loadReviews();
            });
          },
        )
        .subscribe();
  }

  void _showMenu() {
    HapticService.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.75,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 24),
            _buildMenuItem(
              icon: Icons.qr_code_2,
              label: 'Mostrar QR del Evento',
              onTap: () {
                Navigator.pop(ctx);
                _showEventQR();
              },
            ),
            _buildMenuItem(
              icon: Icons.share_outlined,
              label: 'Compartir Evento',
              onTap: () {
                Navigator.pop(ctx);
                _shareEvent();
              },
            ),
            // Toggle chat for driver
            Builder(builder: (_) {
              final chatEnabled = _event?['chat_enabled_for_driver'] != false;
              return _buildMenuItem(
                icon: chatEnabled ? Icons.chat_bubble : Icons.chat_bubble_outline,
                label: chatEnabled ? 'Desactivar Chat al Chofer' : 'Activar Chat al Chofer',
                color: chatEnabled ? AppColors.warning : AppColors.success,
                onTap: () {
                  Navigator.pop(ctx);
                  _toggleChatForDriver();
                },
              );
            }),
            // Toggle fare visibility to riders
            Builder(builder: (_) {
              final fareVisible = _event?['show_fare_to_riders'] != false;
              return _buildMenuItem(
                icon: fareVisible ? Icons.attach_money : Icons.money_off,
                label: fareVisible ? 'Ocultar Tarifa al Pasajero' : 'Mostrar Tarifa al Pasajero',
                color: fareVisible ? AppColors.warning : AppColors.success,
                onTap: () {
                  Navigator.pop(ctx);
                  _toggleFareVisibility();
                },
              );
            }),
            const SizedBox(height: 8),
            Divider(color: AppColors.border.withValues(alpha: 0.5), height: 1),
            const SizedBox(height: 8),
            _buildMenuItem(
              icon: Icons.play_circle_outline,
              label: 'Iniciar Evento',
              color: AppColors.success,
              onTap: () async {
                Navigator.pop(ctx);
                await _startEvent();
              },
            ),
            _buildMenuItem(
              icon: Icons.stop_circle_outlined,
              label: 'Finalizar Evento',
              color: AppColors.primary,
              onTap: () async {
                Navigator.pop(ctx);
                await _completeEvent();
              },
            ),
            _buildMenuItem(
              icon: Icons.delete_forever,
              label: 'Eliminar Evento',
              color: AppColors.error,
              onTap: () async {
                Navigator.pop(ctx);
                await _cancelEvent();
              },
            ),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom + 8),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticService.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (color ?? AppColors.textSecondary).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: color ?? AppColors.textSecondary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color ?? AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: (color ?? AppColors.textTertiary).withValues(alpha: 0.5),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startEvent() async {
    final result = await _eventService.startEvent(widget.eventId);
    if (result.isNotEmpty) {
      HapticService.success();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('tourism_event_started'.tr()),
          backgroundColor: AppColors.success,
        ),
      );
      _loadEvent();
    }
  }

  Future<void> _completeEvent({bool skipConfirm = false}) async {
    if (!skipConfirm) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.flag, color: AppColors.success, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'tourism_finalize_event'.tr(),
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          content: Text(
            'tourism_finalize_event_confirm'.tr(),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('tourism_cancel'.tr(), style: const TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.check, size: 18),
              label: Text('tourism_finalize_event'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    if (!mounted) return;

    try {
      final result = await _eventService.completeEvent(widget.eventId);
      if (result.isNotEmpty) {
        HapticService.success();

        // Notify passengers so they can leave reviews
        await _eventService.notifyEventPassengers(
          eventId: widget.eventId,
          title: 'tourism_trip_completed'.tr(),
          body: 'tourism_trip_completed_notify'.tr(),
          type: 'tourism_trip_completed',
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('tourism_event_completed'.tr()),
            backgroundColor: AppColors.success,
          ),
        );
        _loadEvent();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _cancelEvent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Eliminar Evento',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'Se eliminara permanentemente este evento. Esta accion no se puede deshacer.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 15,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'No',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 16),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              backgroundColor: AppColors.error.withValues(alpha: 0.15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Si, Eliminar',
              style: TextStyle(
                color: AppColors.error,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _eventService.cancelEvent(widget.eventId);
        HapticService.warning();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('tourism_event_deleted'.tr()),
              backgroundColor: AppColors.error,
            ),
          );
          Navigator.pop(context);
        }
      } catch (e) {
        debugPrint('Error deleting event: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('tourism_error_delete'.tr(namedArgs: {'error': e.toString()})),
              backgroundColor: AppColors.error,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }

  void _onTabChanged(int index) {
    HapticService.lightImpact();
    setState(() => _currentTabIndex = index);

    switch (index) {
      case 0:
        _navigateToPassengers();
        break;
      case 1:
        _navigateToChat();
        break;
      case 2:
        _navigateToPhotos();
        break;
      case 3:
        _navigateToInvite();
        break;
    }
  }

  void _navigateToChat() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final driver = authProvider.driver;

    if (driver == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('tourism_error_profile'.tr()),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Reset unread badge when opening chat
    setState(() => _chatUnreadCount = 0);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TourismChatScreen(
          eventId: widget.eventId,
          userRole: 'organizer',
          userId: driver.id,
          userName: driver.name,
          userAvatarUrl: driver.profileImageUrl,
        ),
      ),
    );
  }

  void _navigateToInvite() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrganizerInviteScreen(
          eventId: widget.eventId,
        ),
      ),
    );
  }

  void _navigateToPassengers() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrganizerPassengersScreen(
          eventId: widget.eventId,
        ),
      ),
    );
  }

  void _navigateToPhotos() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final driver = authProvider.driver;

    if (driver == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrganizerPhotosScreen(
          eventId: widget.eventId,
          userId: driver.id,
          userName: driver.name,
        ),
      ),
    );
  }

  void _showEventQR() {
    final eventName = _event?['event_name'] ?? 'Evento';
    final inviteUrl = 'https://toro.app/event/${widget.eventId}';

    HapticService.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'QR del Evento',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              eventName,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: QrImageView(
                data: inviteUrl,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: inviteUrl));
                  HapticService.lightImpact();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('tourism_link_copied'.tr()),
                      backgroundColor: AppColors.success,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.copy, size: 20),
                label: const Text(
                  'Copiar Link',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Los invitados pueden escanear este codigo\npara unirse al evento',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  Future<void> _shareEvent() async {
    final eventName = _event?['event_name'] ?? 'Evento';
    final eventDate = _event?['event_date'] ?? '';
    final startTime = _event?['start_time'] ?? '';
    final inviteUrl = 'https://toro.app/event/${widget.eventId}';

    HapticService.lightImpact();

    final shareText = '''
$eventName

Fecha: $eventDate
Hora: $startTime

Unete al evento:
$inviteUrl

Enviado desde TORO
''';

    try {
      await Share.share(
        shareText,
        subject: eventName,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('tourism_error_sharing'.tr()),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _error != null
              ? _buildErrorState()
              : RefreshIndicator(
                  color: AppColors.primary,
                  backgroundColor: AppColors.surface,
                  onRefresh: _loadData,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      _buildSliverAppBar(),
                      SliverToBoxAdapter(child: _buildContent()),
                    ],
                  ),
                ),
      bottomNavigationBar: _buildBottomNavigation(),
    );
  }

  Widget _buildSliverAppBar() {
    final eventName = _event?['event_name'] ?? 'Evento';
    final status = _event?['status'] ?? 'draft';
    final visibility = _event?['passenger_visibility'] ?? 'private';
    final isPublic = visibility == 'public';
    final isBlackRose = _event?['is_black_rose'] == true || eventName.toUpperCase().contains('BLACK ROSE');

    return SliverAppBar(
      backgroundColor: AppColors.surface,
      pinned: true,
      expandedHeight: 130,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.arrow_back, color: AppColors.textPrimary, size: 22),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        // Toggle público/privado
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isPublic
                  ? AppColors.success.withValues(alpha: 0.15)
                  : AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: isPublic
                  ? Border.all(color: AppColors.success.withValues(alpha: 0.3))
                  : null,
            ),
            child: Icon(
              isPublic ? Icons.visibility : Icons.lock_outline,
              color: isPublic ? AppColors.success : AppColors.textSecondary,
              size: 20,
            ),
          ),
          onPressed: _toggleVisibility,
          tooltip: isPublic ? 'Evento público' : 'Solo invitados',
        ),
        // Menú
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.more_horiz, color: AppColors.textPrimary, size: 22),
          ),
          onPressed: _showMenu,
        ),
        const SizedBox(width: 8),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: isBlackRose
                ? AppColors.blackRoseBgGradient
                : const LinearGradient(
                    colors: [AppColors.surface, AppColors.background],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 48, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: GestureDetector(
                      onTap: _editEventName,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: isBlackRose
                                ? ShaderMask(
                                    shaderCallback: (bounds) => AppColors.blackRoseGradient.createShader(bounds),
                                    child: Text(
                                      eventName,
                                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )
                                : Text(
                                    eventName,
                                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.edit_rounded, color: isBlackRose ? AppColors.blackRose.withValues(alpha: 0.5) : AppColors.textTertiary, size: 16),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (isBlackRose)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            gradient: AppColors.blackRoseGradient,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.diamond, color: Colors.white, size: 12),
                              SizedBox(width: 4),
                              Text('BLACK ROSE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
                            ],
                          ),
                        ),
                      _buildStatusBadge(status),
                      const Spacer(),
                      _buildTopActionBtn(Icons.map, 'Mapa', AppColors.success, _openLiveMap),
                      const SizedBox(width: 8),
                      _buildTopActionBtn(Icons.person_add, 'Invitar', AppColors.primary, _navigateToInvite),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _editEventName() {
    final controller = TextEditingController(text: _event?['event_name'] ?? '');
    HapticService.lightImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Nombre del Evento',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
          maxLength: 80,
          decoration: InputDecoration(
            hintText: 'Ej: Frida Turismo Y Transporte',
            hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 14),
            filled: true,
            fillColor: AppColors.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            counterStyle: const TextStyle(color: AppColors.textTertiary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('tourism_cancel'.tr(), style: const TextStyle(color: AppColors.textTertiary)),
          ),
          TextButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await _eventService.updateEvent(widget.eventId, {'event_name': newName});
                if (mounted) {
                  setState(() {
                    _event?['event_name'] = newName;
                  });
                  HapticService.success();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('tourism_name_updated'.tr()), backgroundColor: AppColors.success),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('tourism_error_generic'.tr(namedArgs: {'error': '$e'})), backgroundColor: AppColors.error),
                  );
                }
              }
            },
            style: TextButton.styleFrom(
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('tourism_save'.tr(), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleVisibility() async {
    final current = _event?['passenger_visibility'] ?? 'private';
    final newValue = current == 'public' ? 'private' : 'public';
    final label = newValue == 'public' ? 'público' : 'privado (solo invitados)';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          newValue == 'public' ? 'Hacer Público' : 'Hacer Privado',
          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
        ),
        content: Text(
          newValue == 'public'
              ? 'Cualquier persona en la app rider podrá solicitar unirse a este evento.'
              : 'Solo personas con invitación podrán unirse a este evento.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('tourism_cancel'.tr(), style: const TextStyle(color: AppColors.textTertiary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('tourism_confirm'.tr(), style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _eventService.updateEvent(widget.eventId, {'passenger_visibility': newValue});
        if (mounted) {
          setState(() {
            _event?['passenger_visibility'] = newValue;
          });
          HapticService.success();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('tourism_event_now_is'.tr(namedArgs: {'status': label})),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('tourism_error_generic'.tr(namedArgs: {'error': '$e'})), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  Future<void> _toggleChatForDriver() async {
    final current = _event?['chat_enabled_for_driver'] != false;
    final newValue = !current;
    final label = newValue ? 'activado' : 'desactivado';

    try {
      await _eventService.updateEvent(widget.eventId, {'chat_enabled_for_driver': newValue});
      if (mounted) {
        setState(() {
          _event?['chat_enabled_for_driver'] = newValue;
        });
        HapticService.success();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('tourism_driver_chat'.tr(namedArgs: {'status': label})),
            backgroundColor: newValue ? AppColors.success : AppColors.warning,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('tourism_error_generic'.tr(namedArgs: {'error': '$e'})), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _toggleFareVisibility() async {
    final current = _event?['show_fare_to_riders'] != false;
    final newValue = !current;
    final label = newValue ? 'visible' : 'oculta';

    try {
      await _eventService.updateEvent(widget.eventId, {'show_fare_to_riders': newValue});
      if (mounted) {
        setState(() {
          _event?['show_fare_to_riders'] = newValue;
        });
        HapticService.success();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('tourism_fare_status'.tr(namedArgs: {'status': label})),
            backgroundColor: newValue ? AppColors.success : AppColors.warning,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('tourism_error_generic'.tr(namedArgs: {'error': '$e'})), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Widget _buildStatusBadge(String status) {
    final color = _getStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _getStatusLabel(status).toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline,
                size: 56,
                color: AppColors.error.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Error al cargar',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Error desconocido',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh, size: 20),
                label: const Text(
                  'Reintentar',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final isPublic = (_event?['passenger_visibility'] ?? 'private') == 'public';
    final hasDriver = _event?['driver_id'] != null;
    final hasVehicle = _event?['vehicle_id'] != null;
    final needsDriverWarning = !hasDriver || !hasVehicle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Warning: needs driver + vehicle to be visible
              if (needsDriverWarning) _buildNeedsDriverBanner(),

              // 1. Business Card + Organizer/Driver (TOP)
              _buildBusinessCardSection(),
              const SizedBox(height: 12),

              // 3. Route + Actions (compact card)
              _buildRouteInfoCard(),
              const SizedBox(height: 12),

              // 4. Panel de Check-in (pasajeros)
              _buildCheckInPanel(),
              const SizedBox(height: 12),

              // 4.1 Botón Finalizar Evento (visible solo cuando el evento está activo)
              if (_event?['status'] == 'in_progress' || _event?['status'] == 'active')
                _buildFinalizeEventButton(),
              if (_event?['status'] == 'in_progress' || _event?['status'] == 'active')
                const SizedBox(height: 12),

              // 4.5 Notificaciones: Emergencia + Anuncios
              _buildNotificationToolsSection(),
              const SizedBox(height: 12),

              // 5. Feed de Actividad en Tiempo Real
              _buildActivityFeed(),
              const SizedBox(height: 12),

              // 6. Pickup Requests (solo si hay)
              if (_pickupRequests.isNotEmpty || _pendingPickupsCount > 0) ...[
                _buildPickupRequestsSection(),
                const SizedBox(height: 12),
              ],

              // 6. Join Requests (solo si evento público)
              if (isPublic && _joinRequests.isNotEmpty) ...[
                _buildJoinRequestsSection(),
                const SizedBox(height: 12),
              ],

              // 7. Reviews (solo si hay o evento completado)
              if (_reviews.isNotEmpty || _event?['status'] == 'completed')
                _buildReviewsSection(),
              if (_reviews.isNotEmpty || _event?['status'] == 'completed')
                const SizedBox(height: 12),

              // 8. Finanzas (colapsable dropdown)
              _buildPricingCardCollapsible(),
            ],
          ),
        ),
      ],
    );
  }

  /// Warning banner when event has no driver or vehicle assigned.
  /// Disappears automatically when organizer assigns a driver with vehicle.
  Widget _buildNeedsDriverBanner() {
    final hasDriver = _event?['driver_id'] != null;
    final hasVehicle = _event?['vehicle_id'] != null;

    String message;
    IconData icon;
    if (!hasDriver && !hasVehicle) {
      message = 'Para publicar tu evento necesitas asignar un chofer con su unidad';
      icon = Icons.warning_amber_rounded;
    } else if (!hasDriver) {
      message = 'Falta asignar un chofer para que tu evento sea visible';
      icon = Icons.person_off_rounded;
    } else {
      message = 'Falta asignar una unidad/vehículo al evento';
      icon = Icons.directions_bus_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.warning, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Evento no visible para pasajeros',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      message,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      HapticService.mediumImpact();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OrganizerBiddingScreen(eventId: widget.eventId),
                        ),
                      ).then((_) => _loadData());
                    },
                    icon: const Icon(Icons.gavel, size: 16),
                    label: const Text(
                      'Buscar Chofer',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 40,
                child: OutlinedButton.icon(
                  onPressed: () {
                    HapticService.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OrganizerVehicleSelectionScreen(eventId: widget.eventId),
                      ),
                    ).then((_) => _loadData());
                  },
                  icon: const Icon(Icons.directions_bus, size: 16),
                  label: const Text(
                    'Directo',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Compact stat strip — single row, minimal space
  Widget _buildStatStrip() {
    final total = _stats['total'] ?? 0;
    final confirmed = _stats['confirmed'] ?? (_stats['accepted'] ?? 0);
    final boarded = _stats['boarded'] ?? 0;
    final checkedIn = _stats['checked_in'] ?? 0;
    final gpsActive = _stats['gps_active'] ?? 0;
    final maxPassengers = (_event?['max_passengers'] as num?)?.toInt() ?? 0;
    final pending = total - confirmed;

    return Row(
      children: [
        // Cupo: confirmed/max
        _buildStatChip(Icons.event_seat, '$confirmed${maxPassengers > 0 ? '/$maxPassengers' : ''}', AppColors.success),
        const SizedBox(width: 6),
        _buildStatChip(Icons.directions_bus, '${checkedIn + boarded}', Colors.orange),
        const SizedBox(width: 6),
        _buildStatChip(Icons.gps_fixed, '$gpsActive', AppColors.primary),
        if (pending > 0) ...[
          const SizedBox(width: 6),
          _buildStatChip(Icons.pending, '$pending', AppColors.textTertiary),
        ],
      ],
    );
  }

  Widget _buildStatChip(IconData icon, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  /// Compact route card with integrated itinerary, date/time, and actions
  Widget _buildRouteInfoCard() {
    final itinerary = _event?['itinerary'] as List<dynamic>? ?? [];
    final eventDate = _event?['event_date'] != null
        ? DateTime.tryParse(_event!['event_date'])
        : null;
    final startTime = _event?['start_time'] as String?;
    final endTime = _event?['end_time'] as String?;
    final distanceKm = (_event?['total_distance_km'] as num?)?.toDouble() ?? 0;

    String? origin;
    String? destination;
    int stopsCount = 0;
    if (itinerary.isNotEmpty) {
      origin = itinerary.first['name'] as String?;
      if (itinerary.length > 1) {
        destination = itinerary.last['name'] as String?;
        stopsCount = itinerary.length - 2;
      }
    }

    String durationStr = '-';
    if (startTime != null && endTime != null) {
      final startParts = startTime.split(':');
      final endParts = endTime.split(':');
      if (startParts.length >= 2 && endParts.length >= 2) {
        final startMinutes = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
        final endMinutes = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
        final durationMinutes = endMinutes - startMinutes;
        if (durationMinutes > 0) {
          final hours = durationMinutes ~/ 60;
          final mins = durationMinutes % 60;
          durationStr = '${hours}h${mins > 0 ? ' ${mins}m' : ''}';
        }
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top bar: date, time, distance, duration
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Icon(Icons.calendar_today, size: 13, color: AppColors.textTertiary),
                const SizedBox(width: 5),
                Text(
                  eventDate != null ? _formatDateShort(eventDate) : '-',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 12),
                Icon(Icons.access_time, size: 13, color: AppColors.textTertiary),
                const SizedBox(width: 5),
                Text(
                  startTime?.substring(0, 5) ?? '-',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.straighten, size: 12, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        '${_fmtPrice(distanceKm)} km',
                        style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.timer_outlined, size: 12, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        durationStr,
                        style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Route timeline: Origin → [expandable stops] → Destination
          if (origin != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  // Origin
                  Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.trip_origin, color: Colors.white, size: 14),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              origin,
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (itinerary.first['address'] != null && (itinerary.first['address'] as String).isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  itinerary.first['address'] as String,
                                  style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _showEditStopDialog(0),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.edit, color: AppColors.primary, size: 16),
                        ),
                      ),
                    ],
                  ),
                  // Expandable intermediate stops
                  if (stopsCount > 0) ...[
                    GestureDetector(
                      onTap: () => setState(() => _isStopsExpanded = !_isStopsExpanded),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: Row(
                          children: [
                            Container(width: 2, height: _isStopsExpanded ? 6 : 14, color: AppColors.border),
                            const SizedBox(width: 18),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '$stopsCount ${stopsCount == 1 ? 'siguiente parada' : 'paradas'}',
                                    style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    _isStopsExpanded ? Icons.expand_less : Icons.expand_more,
                                    size: 14,
                                    color: AppColors.primary,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_isStopsExpanded)
                      ...itinerary.sublist(1, itinerary.length - 1).asMap().entries.map((entry) {
                        final stop = entry.value;
                        final realIndex = entry.key + 1; // offset because we skipped origin
                        final stopName = stop['name'] as String? ?? 'Parada ${entry.key + 1}';
                        final stopAddress = stop['address'] as String? ?? '';
                        final dur = (stop['duration_minutes'] ?? stop['durationMinutes'] ?? 0) as int;
                        return Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Column(
                                children: [
                                  Container(width: 2, height: 6, color: AppColors.border),
                                  Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.8),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${entry.key + 2}',
                                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                  Container(width: 2, height: 6, color: AppColors.border),
                                ],
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        stopName,
                                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (stopAddress.isNotEmpty)
                                        Text(stopAddress, style: TextStyle(color: AppColors.textTertiary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      if (dur > 0)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text('$dur min parada', style: TextStyle(color: AppColors.primary.withValues(alpha: 0.7), fontSize: 11)),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GestureDetector(
                                    onTap: () => _showEditStopDialog(realIndex),
                                    child: Container(
                                      padding: const EdgeInsets.all(5),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Icon(Icons.edit, color: AppColors.primary, size: 14),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  GestureDetector(
                                    onTap: () => _removeStop(realIndex),
                                    child: Container(
                                      padding: const EdgeInsets.all(5),
                                      decoration: BoxDecoration(
                                        color: AppColors.error.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Icon(Icons.delete_outline, color: AppColors.error, size: 14),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                    if (!_isStopsExpanded)
                      Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: Container(width: 2, height: 6, color: AppColors.border),
                      ),
                  ] else ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: Container(width: 2, height: 14, color: AppColors.border),
                    ),
                  ],
                  // + Agregar parada button (inserts before destination)
                  if (itinerary.length >= 2)
                    Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: Row(
                        children: [
                          Container(width: 2, height: 6, color: AppColors.border),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () => _showAddStopDialog(itinerary.length - 1),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add_location_alt, color: AppColors.success, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Agregar parada',
                                    style: TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Destination - "Última parada"
                  if (destination != null)
                    Row(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: const BoxDecoration(
                            color: AppColors.error,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.flag, color: Colors.white, size: 14),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                destination,
                                style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (itinerary.last['address'] != null && (itinerary.last['address'] as String).isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    itinerary.last['address'] as String,
                                    style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              Text(
                                'Última parada',
                                style: TextStyle(color: AppColors.error.withValues(alpha: 0.7), fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _showEditStopDialog(itinerary.length - 1),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.edit, color: AppColors.primary, size: 16),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            )
          else
            // No itinerary yet
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextButton.icon(
                onPressed: _navigateToItinerary,
                icon: const Icon(Icons.add_location_alt, size: 18),
                label: Text('tourism_configure_itinerary'.tr()),
              ),
            ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildTopActionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        HapticService.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactActionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        HapticService.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToItinerary() {
    HapticService.lightImpact();
    final oldItinerary = (_event?['itinerary'] as List?)?.length ?? 0;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrganizerItineraryScreen(eventId: widget.eventId),
      ),
    ).then((_) async {
      await _loadEvent();
      // Notify passengers if itinerary changed
      final newItinerary = (_event?['itinerary'] as List?)?.length ?? 0;
      if (newItinerary != oldItinerary) {
        _eventService.notifyEventPassengers(
          eventId: widget.eventId,
          title: 'Ruta actualizada',
          body: 'El chofer modificó la ruta del viaje',
          type: 'tourism_event_updated',
          extraData: {'change': 'itinerary'},
        );
      }
    });
  }

  /// Shows a bottom sheet to edit a single stop's address, time, and duration.
  /// [stopIndex] is the 0-based index within the itinerary array.
  void _showEditStopDialog(int stopIndex) {
    final itinerary = List<Map<String, dynamic>>.from(
      (_event?['itinerary'] as List?)?.map((e) => Map<String, dynamic>.from(e)) ?? [],
    );
    if (stopIndex < 0 || stopIndex >= itinerary.length) return;

    final stop = Map<String, dynamic>.from(itinerary[stopIndex]);
    final nameController = TextEditingController(text: stop['name'] as String? ?? '');
    final addressController = TextEditingController(text: stop['address'] as String? ?? '');
    final durationController = TextEditingController(
      text: (stop['duration_minutes'] ?? stop['durationMinutes'] ?? 0).toString(),
    );
    double? selectedLat = (stop['lat'] as num?)?.toDouble();
    double? selectedLng = (stop['lng'] as num?)?.toDouble();
    List<Map<String, dynamic>> suggestions = [];
    Timer? debounce;
    bool isSaving = false;
    TimeOfDay? selectedTime;

    // Parse existing scheduled_time
    final scheduledStr = stop['scheduled_time'] as String?;
    if (scheduledStr != null) {
      final dt = DateTime.tryParse(scheduledStr);
      if (dt != null) {
        selectedTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
      }
    }

    final isOrigin = stopIndex == 0;
    final isDestination = itinerary.length > 1 && stopIndex == itinerary.length - 1;
    final label = isOrigin ? 'Origen' : isDestination ? 'Destino final' : 'Parada ${stopIndex + 1}';

    HapticService.lightImpact();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 20, right: 20, top: 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle bar
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Title
                    Row(
                      children: [
                        Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                            color: isOrigin ? AppColors.success : isDestination ? AppColors.error : AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isOrigin ? Icons.trip_origin : isDestination ? Icons.flag : Icons.location_on,
                            color: Colors.white, size: 14,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Editar $label',
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Name field
                    Text('tourism_stop_name'.tr(), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'ej. Terminal Mexicali',
                        hintStyle: TextStyle(color: AppColors.textTertiary),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        prefixIcon: const Icon(Icons.label_outline, color: AppColors.primary, size: 18),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Address search with Mapbox
                    Text('tourism_real_address'.tr(), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: addressController,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'Buscar dirección...',
                        hintStyle: TextStyle(color: AppColors.textTertiary),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        prefixIcon: const Icon(Icons.search, color: AppColors.primary, size: 18),
                        suffixIcon: selectedLat != null
                            ? const Icon(Icons.check_circle, color: AppColors.success, size: 18)
                            : null,
                      ),
                      onChanged: (query) {
                        debounce?.cancel();
                        debounce = Timer(const Duration(milliseconds: 400), () async {
                          if (query.trim().length < 3) {
                            setModalState(() => suggestions = []);
                            return;
                          }
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
                              });
                            }
                          } catch (_) {}
                        });
                      },
                    ),

                    // Suggestions list
                    if (suggestions.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: suggestions.length,
                          separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.border.withValues(alpha: 0.3)),
                          itemBuilder: (context, index) {
                            final s = suggestions[index];
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.location_on, color: AppColors.primary, size: 18),
                              title: Text(
                                s['text'] as String,
                                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                s['place_name'] as String,
                                style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                setModalState(() {
                                  addressController.text = s['place_name'] as String;
                                  selectedLat = s['lat'] as double;
                                  selectedLng = s['lng'] as double;
                                  if (nameController.text.isEmpty) {
                                    nameController.text = s['text'] as String;
                                  }
                                  suggestions = [];
                                });
                                HapticService.selectionClick();
                              },
                            );
                          },
                        ),
                      ),

                    const SizedBox(height: 16),

                    // Time + Duration row
                    Row(
                      children: [
                        // Time picker
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('tourism_estimated_time'.tr(), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              GestureDetector(
                                onTap: () async {
                                  final picked = await showScrollableTimePicker(
                                    context,
                                    selectedTime ?? TimeOfDay.now(),
                                    primaryColor: AppColors.primary,
                                  );
                                  if (picked != null) {
                                    setModalState(() => selectedTime = picked);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.schedule, color: AppColors.primary, size: 18),
                                      const SizedBox(width: 8),
                                      Text(
                                        selectedTime != null
                                            ? '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}'
                                            : 'Sin hora',
                                        style: TextStyle(
                                          color: selectedTime != null ? AppColors.textPrimary : AppColors.textTertiary,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Duration
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('tourism_duration_min'.tr(), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: durationController,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                                decoration: InputDecoration(
                                  hintText: '0',
                                  hintStyle: TextStyle(color: AppColors.textTertiary),
                                  filled: true,
                                  fillColor: AppColors.surface,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  prefixIcon: const Icon(Icons.timer_outlined, color: AppColors.primary, size: 18),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Save button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: isSaving ? null : () async {
                          if (nameController.text.trim().isEmpty) return;
                          setModalState(() => isSaving = true);
                          await _updateSingleStop(
                            stopIndex: stopIndex,
                            name: nameController.text.trim(),
                            address: addressController.text.trim(),
                            lat: selectedLat,
                            lng: selectedLng,
                            durationMinutes: int.tryParse(durationController.text) ?? 0,
                            scheduledTime: selectedTime,
                          );
                          if (mounted) Navigator.pop(context);
                        },
                        icon: isSaving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save, size: 18),
                        label: Text(isSaving ? 'Guardando...' : 'Guardar cambios'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Updates a single stop in the itinerary array and saves to Supabase.
  /// Then reloads the event and notifies all passengers of the change.
  Future<void> _updateSingleStop({
    required int stopIndex,
    required String name,
    String? address,
    double? lat,
    double? lng,
    int durationMinutes = 0,
    TimeOfDay? scheduledTime,
  }) async {
    final itinerary = List<Map<String, dynamic>>.from(
      (_event?['itinerary'] as List?)?.map((e) => Map<String, dynamic>.from(e)) ?? [],
    );
    if (stopIndex < 0 || stopIndex >= itinerary.length) return;

    // Update the stop
    itinerary[stopIndex]['name'] = name;
    if (address != null && address.isNotEmpty) {
      itinerary[stopIndex]['address'] = address;
    }
    if (lat != null && lng != null) {
      itinerary[stopIndex]['lat'] = lat;
      itinerary[stopIndex]['lng'] = lng;
    }
    itinerary[stopIndex]['duration_minutes'] = durationMinutes;
    itinerary[stopIndex]['durationMinutes'] = durationMinutes;

    if (scheduledTime != null) {
      // Build a scheduled_time from event date + time
      final eventDate = _event?['event_date'] != null
          ? DateTime.tryParse(_event!['event_date'])
          : DateTime.now();
      final scheduled = DateTime(
        eventDate?.year ?? DateTime.now().year,
        eventDate?.month ?? DateTime.now().month,
        eventDate?.day ?? DateTime.now().day,
        scheduledTime.hour,
        scheduledTime.minute,
      );
      itinerary[stopIndex]['scheduled_time'] = scheduled.toUtc().toIso8601String();
    }

    try {
      // Save full itinerary to Supabase
      await _eventService.updateItinerary(widget.eventId, itinerary);

      // Optimistic update: refresh local state immediately
      if (mounted) {
        setState(() {
          _event?['itinerary'] = itinerary;
        });
      }

      // Also reload full event data (for other fields that might depend on itinerary)
      await _loadEvent();

      // Notify all connected passengers
      _eventService.notifyEventPassengers(
        eventId: widget.eventId,
        title: 'Dirección actualizada',
        body: 'Se actualizó la parada: $name',
        type: 'tourism_event_updated',
        extraData: {'change': 'stop_address', 'stop_name': name, 'stop_index': stopIndex},
      );

      HapticService.success();

      // If coordinates changed, recalculate total distance + pricing
      if (lat != null && lng != null) {
        await _recalculateDistanceAndPricing(itinerary);
      }
    } catch (e) {
      debugPrint('ERROR updating stop: $e');
      HapticService.error();
    }
  }

  /// Shows a bottom sheet to add a new stop at [insertIndex] in the itinerary.
  void _showAddStopDialog(int insertIndex) {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final durationController = TextEditingController(text: '10');
    double? selectedLat;
    double? selectedLng;
    List<Map<String, dynamic>> suggestions = [];
    Timer? debounce;
    bool isSaving = false;
    TimeOfDay? selectedTime;

    HapticService.lightImpact();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 20, right: 20, top: 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          width: 28, height: 28,
                          decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
                          child: const Icon(Icons.add_location_alt, color: Colors.white, size: 14),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Agregar Parada',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Name field
                    Text('tourism_stop_name'.tr(), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'ej. Terminal Compostela',
                        hintStyle: TextStyle(color: AppColors.textTertiary),
                        filled: true, fillColor: AppColors.surface,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        prefixIcon: const Icon(Icons.label_outline, color: AppColors.primary, size: 18),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Address search
                    Text('tourism_real_address'.tr(), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: addressController,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'Buscar dirección...',
                        hintStyle: TextStyle(color: AppColors.textTertiary),
                        filled: true, fillColor: AppColors.surface,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        prefixIcon: const Icon(Icons.search, color: AppColors.primary, size: 18),
                        suffixIcon: selectedLat != null ? const Icon(Icons.check_circle, color: AppColors.success, size: 18) : null,
                      ),
                      onChanged: (query) {
                        debounce?.cancel();
                        debounce = Timer(const Duration(milliseconds: 400), () async {
                          if (query.trim().length < 3) {
                            setModalState(() => suggestions = []);
                            return;
                          }
                          try {
                            final url = Uri.parse(
                              'https://nominatim.openstreetmap.org/search'
                              '?q=${Uri.encodeComponent(query)}'
                              '&format=jsonv2&countrycodes=mx,us&limit=5&addressdetails=1&accept-language=es',
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
                              });
                            }
                          } catch (_) {}
                        });
                      },
                    ),
                    if (suggestions.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true, padding: EdgeInsets.zero,
                          itemCount: suggestions.length,
                          separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.border.withValues(alpha: 0.3)),
                          itemBuilder: (context, index) {
                            final s = suggestions[index];
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.location_on, color: AppColors.primary, size: 18),
                              title: Text(s['text'] as String, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                              subtitle: Text(s['place_name'] as String, style: TextStyle(color: AppColors.textTertiary, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                              onTap: () {
                                setModalState(() {
                                  addressController.text = s['place_name'] as String;
                                  selectedLat = s['lat'] as double;
                                  selectedLng = s['lng'] as double;
                                  if (nameController.text.isEmpty) nameController.text = s['text'] as String;
                                  suggestions = [];
                                });
                                HapticService.selectionClick();
                              },
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 16),
                    // Time + Duration row
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('tourism_estimated_time'.tr(), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              GestureDetector(
                                onTap: () async {
                                  final picked = await showScrollableTimePicker(context, selectedTime ?? TimeOfDay.now(), primaryColor: AppColors.primary);
                                  if (picked != null) setModalState(() => selectedTime = picked);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.schedule, color: AppColors.primary, size: 18),
                                      const SizedBox(width: 8),
                                      Text(
                                        selectedTime != null
                                            ? '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}'
                                            : 'Sin hora',
                                        style: TextStyle(color: selectedTime != null ? AppColors.textPrimary : AppColors.textTertiary, fontSize: 14),
                                      ),
                                    ],
                                  ),
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
                              Text('tourism_duration_min'.tr(), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: durationController,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                                decoration: InputDecoration(
                                  hintText: '0', hintStyle: TextStyle(color: AppColors.textTertiary),
                                  filled: true, fillColor: AppColors.surface,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  prefixIcon: const Icon(Icons.timer_outlined, color: AppColors.primary, size: 18),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Add button
                    SizedBox(
                      width: double.infinity, height: 48,
                      child: ElevatedButton.icon(
                        onPressed: isSaving ? null : () async {
                          if (nameController.text.trim().isEmpty) return;
                          setModalState(() => isSaving = true);
                          await _addNewStop(
                            insertIndex: insertIndex,
                            name: nameController.text.trim(),
                            address: addressController.text.trim(),
                            lat: selectedLat,
                            lng: selectedLng,
                            durationMinutes: int.tryParse(durationController.text) ?? 10,
                            scheduledTime: selectedTime,
                          );
                          if (mounted) Navigator.pop(context);
                        },
                        icon: isSaving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.add_location_alt, size: 18),
                        label: Text(isSaving ? 'Agregando...' : 'Agregar parada'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Adds a new stop to the itinerary at [insertIndex], saves, logs, notifies.
  Future<void> _addNewStop({
    required int insertIndex,
    required String name,
    String? address,
    double? lat,
    double? lng,
    int durationMinutes = 10,
    TimeOfDay? scheduledTime,
  }) async {
    final itinerary = List<Map<String, dynamic>>.from(
      (_event?['itinerary'] as List?)?.map((e) => Map<String, dynamic>.from(e)) ?? [],
    );

    final newStop = <String, dynamic>{
      'name': name,
      'address': address ?? '',
      'lat': lat,
      'lng': lng,
      'duration_minutes': durationMinutes,
      'durationMinutes': durationMinutes,
      'stop_order': insertIndex,
    };

    if (scheduledTime != null) {
      final eventDate = _event?['event_date'] != null
          ? DateTime.tryParse(_event!['event_date'])
          : DateTime.now();
      final scheduled = DateTime(
        eventDate?.year ?? DateTime.now().year,
        eventDate?.month ?? DateTime.now().month,
        eventDate?.day ?? DateTime.now().day,
        scheduledTime.hour,
        scheduledTime.minute,
      );
      newStop['scheduled_time'] = scheduled.toUtc().toIso8601String();
    }

    // Insert at position
    itinerary.insert(insertIndex, newStop);

    // Recalculate stop_order for all stops
    for (int i = 0; i < itinerary.length; i++) {
      itinerary[i]['stop_order'] = i;
    }

    try {
      await _eventService.updateItinerary(widget.eventId, itinerary);

      if (mounted) {
        setState(() {
          _event?['itinerary'] = itinerary;
        });
      }

      await _loadEvent();

      // Log the change for audit
      _eventService.logItineraryChange(
        eventId: widget.eventId,
        changeType: 'stop_added',
        summary: 'Agregó parada: $name',
        newValue: newStop,
      );

      // Notify passengers
      _eventService.notifyEventPassengers(
        eventId: widget.eventId,
        title: 'Ruta actualizada',
        body: 'Se agregó la parada: $name',
        type: 'tourism_event_updated',
        extraData: {'change': 'stop_added', 'stop_name': name},
      );

      HapticService.success();

      // Recalculate distance + pricing
      if (lat != null && lng != null) {
        await _recalculateDistanceAndPricing(itinerary);
      }
    } catch (e) {
      debugPrint('ERROR adding stop: $e');
      HapticService.error();
    }
  }

  /// Removes an intermediate stop from the itinerary after confirmation.
  void _removeStop(int stopIndex) {
    final itinerary = List<Map<String, dynamic>>.from(
      (_event?['itinerary'] as List?)?.map((e) => Map<String, dynamic>.from(e)) ?? [],
    );

    if (stopIndex <= 0 || stopIndex >= itinerary.length - 1) return; // Can't remove origin or destination
    if (itinerary.length <= 2) return; // Must keep at least origin + destination

    final stopName = itinerary[stopIndex]['name'] as String? ?? 'Parada ${stopIndex + 1}';
    final removedStop = Map<String, dynamic>.from(itinerary[stopIndex]);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.delete_outline, color: AppColors.error, size: 22),
            const SizedBox(width: 8),
            Text('tourism_delete_stop'.tr(), style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Text(
          '¿Eliminar la parada "$stopName"?\n\nSe notificará a los pasajeros del cambio.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('tourism_cancel'.tr(), style: const TextStyle(color: AppColors.textTertiary)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _executeRemoveStop(stopIndex, stopName, removedStop, itinerary);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('tourism_delete'.tr()),
          ),
        ],
      ),
    );
  }

  /// Executes the actual stop removal after confirmation.
  Future<void> _executeRemoveStop(
    int stopIndex,
    String stopName,
    Map<String, dynamic> removedStop,
    List<Map<String, dynamic>> itinerary,
  ) async {
    itinerary.removeAt(stopIndex);

    // Recalculate stop_order
    for (int i = 0; i < itinerary.length; i++) {
      itinerary[i]['stop_order'] = i;
    }

    try {
      await _eventService.updateItinerary(widget.eventId, itinerary);

      if (mounted) {
        setState(() {
          _event?['itinerary'] = itinerary;
        });
      }

      await _loadEvent();

      // Log the change for audit
      _eventService.logItineraryChange(
        eventId: widget.eventId,
        changeType: 'stop_removed',
        summary: 'Eliminó parada: $stopName',
        oldValue: removedStop,
      );

      // Notify passengers
      _eventService.notifyEventPassengers(
        eventId: widget.eventId,
        title: 'Ruta actualizada',
        body: 'Se eliminó la parada: $stopName',
        type: 'tourism_event_updated',
        extraData: {'change': 'stop_removed', 'stop_name': stopName},
      );

      HapticService.success();

      // Recalculate distance + pricing
      await _recalculateDistanceAndPricing(itinerary);
    } catch (e) {
      debugPrint('ERROR removing stop: $e');
      HapticService.error();
    }
  }

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
          final distanceMeters = data['routes'][0]['distance'] as num;
          return (distanceMeters / 1000).toDouble();
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error calculating road distance: $e');
      return null;
    }
  }

  /// Recalculate total distance from itinerary stops, update pricing & save to DB
  Future<void> _recalculateDistanceAndPricing(List<Map<String, dynamic>> itinerary) async {
    if (itinerary.length < 2) return;
    try {
      double totalDistance = 0;
      for (int i = 0; i < itinerary.length - 1; i++) {
        final from = itinerary[i];
        final to = itinerary[i + 1];
        final lat1 = (from['lat'] as num?)?.toDouble();
        final lng1 = (from['lng'] as num?)?.toDouble();
        final lat2 = (to['lat'] as num?)?.toDouble();
        final lng2 = (to['lng'] as num?)?.toDouble();
        if (lat1 != null && lng1 != null && lat2 != null && lng2 != null) {
          final d = await _calculateRoadDistance(lat1, lng1, lat2, lng2);
          if (d != null) totalDistance += d;
        }
      }

      // Recalculate pricing with new distance
      final pricePerKm = (_event?['price_per_km'] as num?)?.toDouble() ?? 1.0;
      final pricing = _eventService.calculatePricing(
        distanceKm: totalDistance,
        pricePerKm: pricePerKm,
        isDriverOwned: _event?['is_driver_owned'] == true,
      );

      // Save to Supabase
      await _eventService.updateEvent(widget.eventId, {
        'total_distance_km': totalDistance,
        'total_base_price': pricing['total_base_price'],
        'toro_fee': pricing['toro_fee'],
        'organizer_commission': pricing['organizer_commission'],
      });

      // Update local state
      if (mounted) {
        setState(() {
          _event?['total_distance_km'] = totalDistance;
          _event?['total_base_price'] = pricing['total_base_price'];
          _event?['toro_fee'] = pricing['toro_fee'];
          _event?['organizer_commission'] = pricing['organizer_commission'];
        });
      }
    } catch (e) {
      debugPrint('Error recalculating distance: $e');
    }
  }

  String _formatDateShort(DateTime date) {
    const months = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
    return '${date.day} ${months[date.month - 1]}';
  }

  /// Pricing card - set price per km, shows 18% fee and ticket example
  Widget _buildPricingCard() {
    final distanceKm = (_event?['total_distance_km'] as num?)?.toDouble() ?? 0;
    final maxPassengers = (_event?['max_passengers'] as num?)?.toInt() ?? 40;
    final pricePerKm = double.tryParse(_pricePerKmController.text) ?? 1.0;

    // Calculations: each passenger pays km × price_per_km
    final ticketPrice = pricePerKm * distanceKm;
    final toroFee = ticketPrice * 0.18;
    final receives = ticketPrice - toroFee;
    final accepted = (_stats['confirmed'] as num?)?.toInt() ?? (_stats['accepted'] as num?)?.toInt() ?? 0;
    final currentEarnings = receives * accepted;
    final totalBruto = ticketPrice * accepted;
    final receiverLabel = 'Tu recibes';
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.attach_money, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Finanzas',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Agreed price (tappable to edit)
            GestureDetector(
              onTap: () => _showEditPriceDialog(pricePerKm),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.handshake, color: AppColors.primary, size: 18),
                    const SizedBox(width: 10),
                    Text(
                      'tourism_agreed_price'.tr(),
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    Text(
                      '\$${pricePerKm.toStringAsFixed(2)}/km',
                      style: const TextStyle(color: AppColors.primary, fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.edit, color: AppColors.primary, size: 14),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Financial breakdown
            if (distanceKm > 0) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.cardSecondary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPricingRow('Distancia total', '${_fmtPrice(distanceKm)} km', icon: Icons.straighten),
                    const Divider(color: AppColors.border, height: 16),
                    _buildPricingRow('Precio boleto', '\$${_fmtPrice(ticketPrice)}', isBold: true, icon: Icons.receipt_long),
                    const SizedBox(height: 6),
                    _buildPricingRow('Servicio TORO (18%)', '-\$${_fmtPrice(toroFee)}', color: AppColors.textSecondary, icon: Icons.percent),
                    const SizedBox(height: 6),
                    _buildPricingRow(receiverLabel, '\$${_fmtPrice(receives)}', color: AppColors.success, isBold: true, icon: Icons.account_balance_wallet),
                    if (accepted > 0) ...[
                      const Divider(color: AppColors.border, height: 16),
                      _buildPricingRow('Pasajeros confirmados', '$accepted/$maxPassengers', icon: Icons.people),
                      const SizedBox(height: 6),
                      _buildPricingRow('Total recaudado', '\$${_fmtPrice(totalBruto)}', icon: Icons.monetization_on),
                      const SizedBox(height: 6),
                      _buildPricingRow('Servicio TORO', '-\$${_fmtPrice(toroFee * accepted)}', color: AppColors.textSecondary, icon: Icons.percent),
                      const SizedBox(height: 6),
                      _buildPricingRow(receiverLabel, '\$${_fmtPrice(currentEarnings)}', color: AppColors.primary, isBold: true, icon: Icons.account_balance_wallet),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Disclaimer
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange.shade600, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'tourism_payment_responsibility'.tr(),
                      style: TextStyle(color: Colors.orange.shade700, fontSize: 12, fontWeight: FontWeight.w500),
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

  Widget _buildReviewsSection() {
    final avgRating = _reviews.isEmpty
        ? 0.0
        : _reviews.fold<double>(0.0, (sum, r) => sum + ((r['overall_rating'] as num?) ?? 0)) / _reviews.length;
    final recommendCount = _reviews.where((r) => r['would_recommend'] == true).length;

    // Collect all improvement tags across reviews
    final tagCounts = <String, int>{};
    for (final review in _reviews) {
      final tags = review['improvement_tags'];
      if (tags is List) {
        for (final tag in tags) {
          tagCounts[tag.toString()] = (tagCounts[tag.toString()] ?? 0) + 1;
        }
      }
    }
    final sortedTags = tagCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star_rounded, color: Colors.amber, size: 22),
              const SizedBox(width: 8),
              Text(
                'tourism_ratings'.tr(),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (_reviews.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'tourism_review_count'.tr(namedArgs: {'count': '${_reviews.length}'}),
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (_reviews.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    Icon(Icons.rate_review_outlined, color: AppColors.textSecondary.withValues(alpha: 0.5), size: 40),
                    const SizedBox(height: 8),
                    Text(
                      'tourism_waiting_ratings'.tr(),
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            // Summary row
            Row(
              children: [
                // Average rating
                Column(
                  children: [
                    Text(
                      avgRating.toStringAsFixed(1),
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Row(
                      children: List.generate(5, (i) => Icon(
                        i < avgRating.round() ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: Colors.amber,
                        size: 16,
                      )),
                    ),
                  ],
                ),
                const SizedBox(width: 24),
                // Recommend %
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${((recommendCount / _reviews.length) * 100).round()}%',
                        style: TextStyle(
                          color: AppColors.success,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'tourism_recommend_it'.tr(),
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Top improvement tags
            if (sortedTags.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'tourism_top_improvements'.tr(),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: sortedTags.take(5).map((entry) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${entry.key} (${entry.value})',
                    style: TextStyle(
                      color: AppColors.warning,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )).toList(),
              ),
            ],

            // Individual reviews
            const SizedBox(height: 14),
            ...(_reviews.take(5).map((review) {
              final rating = (review['overall_rating'] as num?) ?? 0;
              final comment = review['comment'] as String?;
              final createdAt = DateTime.tryParse(review['created_at'] ?? '');
              final timeStr = createdAt != null
                  ? '${createdAt.toLocal().day}/${createdAt.toLocal().month} ${createdAt.toLocal().hour}:${createdAt.toLocal().minute.toString().padLeft(2, '0')}'
                  : '';

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ...List.generate(5, (i) => Icon(
                            i < rating.toInt() ? Icons.star_rounded : Icons.star_outline_rounded,
                            color: Colors.amber,
                            size: 14,
                          )),
                          const Spacer(),
                          Text(timeStr, style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                        ],
                      ),
                      if (comment != null && comment.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          comment,
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            })),
          ],
        ],
      ),
    );
  }

  /// Collapsible dropdown version of the pricing card for bottom placement
  Widget _buildPricingCardCollapsible() {
    final distanceKm = (_event?['total_distance_km'] as num?)?.toDouble() ?? 0;
    final maxPassengers = (_event?['max_passengers'] as num?)?.toInt() ?? 40;
    final pricePerKm = double.tryParse(_pricePerKmController.text) ?? 1.0;
    final ticketPrice = pricePerKm * distanceKm;
    final toroFee = ticketPrice * 0.18;
    final receives = ticketPrice - toroFee;
    final accepted = (_stats['confirmed'] as num?)?.toInt() ?? (_stats['accepted'] as num?)?.toInt() ?? 0;
    final currentEarnings = receives * accepted;
    final totalBruto = ticketPrice * accepted;
    final receiverLabel = 'Tu recibes';
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        children: [
          // Header - tap to expand/collapse
          InkWell(
            onTap: () {
              HapticService.lightImpact();
              setState(() => _isFinanceExpanded = !_isFinanceExpanded);
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.success.withValues(alpha: 0.2),
                          AppColors.success.withValues(alpha: 0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.account_balance_wallet_outlined, color: AppColors.success, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Finanzas',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Total: \$${_fmtPrice(ticketPrice * accepted)} MXN',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.cardSecondary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _isFinanceExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Expandable content
          if (_isFinanceExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  // Agreed price (tappable to edit)
                  GestureDetector(
                    onTap: () => _showEditPriceDialog(pricePerKm),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.handshake, color: AppColors.primary, size: 18),
                          const SizedBox(width: 10),
                          Text('tourism_agreed_price'.tr(),
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
                          const Spacer(),
                          Text('\$${pricePerKm.toStringAsFixed(2)}/km',
                            style: const TextStyle(color: AppColors.primary, fontSize: 16, fontWeight: FontWeight.w800)),
                          const SizedBox(width: 6),
                          const Icon(Icons.edit, color: AppColors.primary, size: 14),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Financial breakdown
                  if (distanceKm > 0) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.cardSecondary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPricingRow('Distancia total', '${_fmtPrice(distanceKm)} km', icon: Icons.straighten),
                          const Divider(color: AppColors.border, height: 16),
                          _buildPricingRow('Precio boleto', '\$${_fmtPrice(ticketPrice)}', isBold: true, icon: Icons.receipt_long),
                          const SizedBox(height: 6),
                          _buildPricingRow('Servicio TORO (18%)', '-\$${_fmtPrice(toroFee)}', color: AppColors.textSecondary, icon: Icons.percent),
                          const SizedBox(height: 6),
                          _buildPricingRow(receiverLabel, '\$${_fmtPrice(receives)}', color: AppColors.success, isBold: true, icon: Icons.account_balance_wallet),
                          if (accepted > 0) ...[
                            const Divider(color: AppColors.border, height: 16),
                            _buildPricingRow('Pasajeros confirmados', '$accepted/$maxPassengers', icon: Icons.people),
                            const SizedBox(height: 6),
                            _buildPricingRow('Total recaudado', '\$${_fmtPrice(totalBruto)}', icon: Icons.monetization_on),
                            const SizedBox(height: 6),
                            _buildPricingRow('Servicio TORO', '-\$${_fmtPrice(toroFee * accepted)}', color: AppColors.textSecondary, icon: Icons.percent),
                            const SizedBox(height: 6),
                            _buildPricingRow(receiverLabel, '\$${_fmtPrice(currentEarnings)}', color: AppColors.primary, isBold: true, icon: Icons.account_balance_wallet),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // Disclaimer
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange.shade600, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('tourism_payment_responsibility'.tr(),
                            style: TextStyle(color: Colors.orange.shade700, fontSize: 12, fontWeight: FontWeight.w500)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPricingRow(String label, String value, {bool isBold = false, Color? color, IconData? icon}) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        ),
        Text(
          value,
          style: TextStyle(
            color: color ?? AppColors.textPrimary,
            fontSize: isBold ? 16 : 14,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Future<void> _showEditPriceDialog(double currentPrice) async {
    final controller = TextEditingController(text: currentPrice.toStringAsFixed(2));
    final distanceKm = (_event?['total_distance_km'] as num?)?.toDouble() ?? 0;

    final result = await showDialog<double>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final newPrice = double.tryParse(controller.text) ?? 0;
            final newTicket = newPrice * distanceKm;
            final newFee = newTicket * 0.18;
            final newReceives = newTicket - newFee;

            return AlertDialog(
              backgroundColor: AppColors.card,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Cambiar precio/km', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    autofocus: true,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      prefixText: '\$ ',
                      suffixText: '/km',
                      prefixStyle: const TextStyle(color: AppColors.primary, fontSize: 20, fontWeight: FontWeight.w700),
                      suffixStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                      filled: true,
                      fillColor: AppColors.cardSecondary,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  if (distanceKm > 0 && newPrice > 0) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          _dialogRow('Distancia', '${_fmtPrice(distanceKm)} km'),
                          const SizedBox(height: 6),
                          _dialogRow('Precio boleto', '\$${_fmtPrice(newTicket)}', bold: true),
                          const SizedBox(height: 6),
                          _dialogRow('Servicio TORO (18%)', '-\$${_fmtPrice(newFee)}'),
                          const SizedBox(height: 6),
                          _dialogRow('Tu recibes', '\$${_fmtPrice(newReceives)}', bold: true, color: AppColors.success),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar', style: TextStyle(color: AppColors.textSecondary)),
                ),
                ElevatedButton(
                  onPressed: newPrice > 0 ? () => Navigator.pop(ctx, newPrice) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Guardar', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null && result != currentPrice) {
      _pricePerKmController.text = result.toStringAsFixed(2);
      await _savePricePerKm();
    }
  }

  Widget _dialogRow(String label, String value, {bool bold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        Text(value, style: TextStyle(
          color: color ?? AppColors.textPrimary,
          fontSize: bold ? 15 : 13,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        )),
      ],
    );
  }

  Future<void> _savePricePerKm() async {
    final value = double.tryParse(_pricePerKmController.text);
    if (value == null || value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('tourism_enter_valid_price'.tr()), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _isPriceSaving = true);
    try {
      final distanceKm = (_event?['total_distance_km'] as num?)?.toDouble() ?? 0;
      final pricing = _eventService.calculatePricing(
        distanceKm: distanceKm,
        pricePerKm: value,
        isDriverOwned: _event?['is_driver_owned'] == true,
      );

      await _eventService.updateEvent(widget.eventId, {
        'price_per_km': value,
        'total_base_price': pricing['total_base_price'],
        'toro_fee': pricing['toro_fee'],
        'organizer_commission': pricing['organizer_commission'],
      });

      if (mounted) {
        setState(() {
          _event?['price_per_km'] = value;
          _event?['total_base_price'] = pricing['total_base_price'];
          _event?['toro_fee'] = pricing['toro_fee'];
          _event?['organizer_commission'] = pricing['organizer_commission'];
        });
        HapticService.success();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('tourism_price_updated'.tr()), backgroundColor: AppColors.success),
        );
        // Notify passengers
        _eventService.notifyEventPassengers(
          eventId: widget.eventId,
          title: 'tourism_price_updated'.tr(),
          body: 'El precio del viaje cambió a \$${value.toStringAsFixed(2)}/km',
          type: 'tourism_event_updated',
          extraData: {'change': 'price_per_km', 'new_value': value},
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('tourism_error_generic'.tr(namedArgs: {'error': '$e'})), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isPriceSaving = false);
    }
  }

  Future<void> _showSeatAdjustDialog() async {
    final currentMax = (_event?['max_passengers'] as num?)?.toInt() ?? 40;
    final vehicle = _event?['bus_vehicles'] as Map<String, dynamic>?;
    final vehicleSeats = (vehicle?['total_seats'] as num?)?.toInt() ?? currentMax;
    final accepted = (_stats['confirmed'] as num?)?.toInt() ?? (_stats['accepted'] as num?)?.toInt() ?? 0;
    // Min = passengers already confirmed (accepted + checked_in + boarded), Max = vehicle total_seats
    final minSeats = accepted > 0 ? accepted : 1;

    int selected = currentMax;

    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Ajustar Asientos',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Máximo del vehículo: $vehicleSeats',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              if (accepted > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Pasajeros confirmados: $accepted (mínimo)',
                    style: TextStyle(color: Colors.orange.shade600, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: selected > minSeats
                        ? () => setDialogState(() => selected--)
                        : null,
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: selected > minSeats
                            ? AppColors.error.withValues(alpha: 0.15)
                            : AppColors.cardSecondary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.remove,
                        color: selected > minSeats ? AppColors.error : AppColors.textTertiary,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    '$selected',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    onPressed: selected < vehicleSeats
                        ? () => setDialogState(() => selected++)
                        : null,
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: selected < vehicleSeats
                            ? AppColors.success.withValues(alpha: 0.15)
                            : AppColors.cardSecondary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.add,
                        color: selected < vehicleSeats ? AppColors.success : AppColors.textTertiary,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('tourism_cancel'.tr(), style: const TextStyle(color: AppColors.textTertiary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, selected),
              style: TextButton.styleFrom(
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('tourism_save'.tr(), style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );

    if (result != null && result != currentMax) {
      try {
        await _eventService.updateEvent(widget.eventId, {'max_passengers': result});
        if (mounted) {
          setState(() => _event?['max_passengers'] = result);
          HapticService.success();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('tourism_seats_adjusted'.tr(namedArgs: {'count': '$result'})), backgroundColor: AppColors.success),
          );
          // Notify passengers
          _eventService.notifyEventPassengers(
            eventId: widget.eventId,
            title: 'Asientos actualizados',
            body: 'La capacidad del viaje cambió a $result asientos',
            type: 'tourism_event_updated',
            extraData: {'change': 'max_passengers', 'new_value': result},
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('tourism_error_generic'.tr(namedArgs: {'error': '$e'})), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  /// Business card + organizer (editable) + driver (read-only) section
  Widget _buildBusinessCardSection() {
    final organizer = _event?['organizers'] as Map<String, dynamic>?;
    final driver = _event?['drivers'] as Map<String, dynamic>?;
    final maxPassengers = _event?['max_passengers'] ?? 0;
    final acceptedCount = _stats['confirmed'] ?? _stats['accepted'] ?? 0;

    final organizerName = organizer?['company_name'] ?? organizer?['name'] ?? 'Mi Negocio';
    final organizerPhone = organizer?['phone'] as String?;
    final organizerEmail = organizer?['contact_email'] ?? organizer?['email'] as String?;
    final organizerWebsite = organizer?['website'] as String?;
    final organizerDesc = organizer?['description'] as String?;
    final organizerLogo = organizer?['company_logo_url'] as String?;
    final businessCardUrl = organizer?['business_card_url'] as String?;
    final organizerId = organizer?['id'] as String?;

    final driverName = driver?['name'] ?? driver?['full_name'] ?? 'Sin asignar';
    final driverAvatar = driver?['profile_image_url'] as String?;
    final driverPhone = driver?['phone'] as String?;
    final driverContactEmail = driver?['contact_email'] as String?;
    final driverContactPhone = driver?['contact_phone'] as String?;
    final driverContactFacebook = driver?['contact_facebook'] as String?;
    final driverBusinessCard = driver?['business_card_url'] as String?;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Business card image banner (tappable to upload)
          GestureDetector(
            onTap: () => _pickBusinessCard(organizerId),
            child: Stack(
              children: [
                if (businessCardUrl != null)
                  Image.network(
                    businessCardUrl,
                    width: double.infinity,
                    height: 160,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _buildCardPlaceholder(),
                  )
                else
                  _buildCardPlaceholder(),
                // Edit overlay
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                  ),
                ),
                // Organizer name + logo overlay at bottom
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
                      ),
                    ),
                    child: Row(
                      children: [
                        if (organizerLogo != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              organizerLogo,
                              width: 28,
                              height: 28,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const SizedBox.shrink(),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            organizerName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Organizer info (editable) — tap row to edit profile
          GestureDetector(
            onTap: () {
              HapticService.lightImpact();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OrganizerProfileScreen()),
              ).then((_) => _loadData());
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info row: phone, email, website
                  Row(
                    children: [
                      const Icon(Icons.business, color: AppColors.primary, size: 14),
                      const SizedBox(width: 6),
                      const Text(
                        'Chofer',
                        style: TextStyle(color: AppColors.textTertiary, fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                      const Spacer(),
                      const Icon(Icons.edit, color: AppColors.primary, size: 13),
                      const SizedBox(width: 4),
                      const Text(
                        'Editar Perfil',
                        style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (organizerDesc != null && organizerDesc.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      organizerDesc,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  // Contact details - clickable chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (organizerPhone != null && organizerPhone.isNotEmpty)
                        _buildContactChip(Icons.phone, organizerPhone),
                      if (organizerEmail != null && organizerEmail.isNotEmpty)
                        _buildContactChip(Icons.email_outlined, organizerEmail),
                      if (organizerWebsite != null && organizerWebsite.isNotEmpty)
                        _buildContactChip(Icons.language, organizerWebsite),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Divider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Divider(color: AppColors.border.withValues(alpha: 0.5), height: 1),
          ),

          // Driver row (read-only) — tap to assign via bidding if none
          GestureDetector(
            onTap: driver == null
                ? () {
                    HapticService.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OrganizerBiddingScreen(eventId: widget.eventId),
                      ),
                    ).then((_) => _loadData());
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: driver != null
                          ? AppColors.warning.withValues(alpha: 0.15)
                          : AppColors.textTertiary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: driverAvatar != null
                        ? ClipOval(
                            child: Image.network(
                              driverAvatar,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Icon(Icons.directions_bus, color: AppColors.warning, size: 20),
                            ),
                          )
                        : Icon(
                            driver == null ? Icons.add_circle_outline : Icons.directions_bus,
                            color: driver != null ? AppColors.warning : AppColors.primary,
                            size: 20,
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Driver',
                          style: TextStyle(color: AppColors.textTertiary, fontSize: 10, fontWeight: FontWeight.w500),
                        ),
                        Text(
                          driver == null ? 'Toca para agregar' : driverName,
                          style: TextStyle(
                            color: driver != null ? AppColors.textPrimary : AppColors.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
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
          ),
          // ── Driver credential chips ──
          if (driver != null && (driverContactEmail != null || driverContactPhone != null || driverContactFacebook != null || driverBusinessCard != null))
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (driverContactPhone != null && driverContactPhone.isNotEmpty)
                    _buildDriverCredChip(Icons.phone, driverContactPhone),
                  if (driverContactEmail != null && driverContactEmail.isNotEmpty)
                    _buildDriverCredChip(Icons.email, driverContactEmail),
                  if (driverContactFacebook != null && driverContactFacebook.isNotEmpty)
                    _buildDriverCredChip(Icons.facebook, 'Facebook'),
                  if (driverBusinessCard != null)
                    _buildDriverCredChip(Icons.badge, 'Tarjeta'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDriverCredChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppColors.warning),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildCardPlaceholder() {
    return Container(
      width: double.infinity,
      height: 160,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.15),
            AppColors.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_photo_alternate_outlined, color: AppColors.primary, size: 40),
          SizedBox(height: 8),
          Text(
            'Agregar Tarjeta de Presentacion',
            style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          Text(
            'Los pasajeros veran esta imagen',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildContactChip(IconData icon, String text) {
    return GestureDetector(
      onTap: () async {
        HapticService.lightImpact();
        Uri? uri;
        if (icon == Icons.phone) {
          uri = Uri.parse('tel:$text');
        } else if (icon == Icons.email_outlined) {
          uri = Uri.parse('mailto:$text');
        } else if (icon == Icons.language) {
          final url = text.startsWith('http') ? text : 'https://$text';
          uri = Uri.parse(url);
        }
        if (uri != null) {
          try {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } catch (_) {}
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.primary, size: 13),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.open_in_new, color: AppColors.primary.withValues(alpha: 0.5), size: 10),
          ],
        ),
      ),
    );
  }

  Future<void> _pickBusinessCard(String? organizerId, {ImageSource? source}) async {
    if (organizerId == null) return;

    // Show picker dialog if no source specified
    ImageSource selectedSource;
    if (source != null) {
      selectedSource = source;
    } else {
      final result = await showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: AppColors.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('tourism_upload_image'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.photo_library, color: AppColors.primary),
                  title: Text('tourism_gallery'.tr(), style: const TextStyle(color: Colors.white)),
                  onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                ),
                if (!kIsWeb)
                  ListTile(
                    leading: const Icon(Icons.camera_alt, color: AppColors.primary),
                    title: Text('tourism_camera'.tr(), style: const TextStyle(color: Colors.white)),
                    onTap: () => Navigator.pop(ctx, ImageSource.camera),
                  ),
              ],
            ),
          ),
        ),
      );
      if (result == null) return;
      selectedSource = result;
    }

    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: selectedSource,
      maxWidth: 1200,
      maxHeight: 800,
      imageQuality: 90,
    );
    if (image == null) return;

    try {
      HapticService.lightImpact();
      final organizerService = OrganizerService();
      final imageBytes = await image.readAsBytes();
      final url = await organizerService.uploadBusinessCard(organizerId, image.name, bytes: imageBytes);

      if (url != null && mounted) {
        setState(() {
          final org = _event?['organizers'] as Map<String, dynamic>?;
          if (org != null) {
            org['business_card_url'] = url;
          }
        });
        HapticService.success();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('tourism_card_updated'.tr()),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('tourism_error_generic'.tr(namedArgs: {'error': '$e'})),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _openLiveMap() {
    // Navigate to the real-time map showing passengers
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _EventLiveMapScreen(
          eventId: widget.eventId,
          event: _event,
          passengerLocations: _passengerLocations,
        ),
      ),
    );
  }

  /// Pickup requests section - shows passengers who requested custom pickup locations
  Widget _buildPickupRequestsSection() {
    final pendingRequests = _pickupRequests.where((r) => r['pickup_approved'] == null).toList();
    final approvedRequests = _pickupRequests.where((r) => r['pickup_approved'] == true).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: pendingRequests.isNotEmpty ? AppColors.warning : AppColors.border,
          width: pendingRequests.isNotEmpty ? 1.5 : 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with collapse toggle
          GestureDetector(
            onTap: () => setState(() => _isPickupsExpanded = !_isPickupsExpanded),
            child: Row(
              children: [
                Icon(
                  Icons.location_on,
                  color: pendingRequests.isNotEmpty ? AppColors.warning : AppColors.primary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Solicitudes de Pickup',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (pendingRequests.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${pendingRequests.length} pendientes',
                      style: const TextStyle(
                        color: AppColors.warning,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (approvedRequests.isNotEmpty && pendingRequests.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${approvedRequests.length} aprobados',
                      style: const TextStyle(
                        color: AppColors.success,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Icon(
                  _isPickupsExpanded ? Icons.expand_less : Icons.expand_more,
                  color: AppColors.textTertiary,
                  size: 20,
                ),
              ],
            ),
          ),
          // Collapsible content
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                if (pendingRequests.isNotEmpty) ...[
                  ...pendingRequests.map((request) => _buildPickupRequestItem(request, isPending: true)),
                  if (approvedRequests.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Divider(color: AppColors.border.withValues(alpha: 0.5)),
                    ),
                ],
                if (approvedRequests.isNotEmpty)
                  ...approvedRequests.map((request) => _buildPickupRequestItem(request, isPending: false)),
                if (_pickupRequests.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.location_off_outlined,
                            size: 28,
                            color: AppColors.textTertiary.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Sin solicitudes de pickup',
                            style: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            crossFadeState: _isPickupsExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildPickupRequestItem(Map<String, dynamic> request, {required bool isPending}) {
    final name = request['passenger_name'] ?? 'Pasajero';
    final address = request['pickup_address'] ?? 'Ubicación personalizada';
    final lat = request['pickup_lat'] as double?;
    final lng = request['pickup_lng'] as double?;
    final order = request['pickup_order'] as int?;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isPending
            ? AppColors.warning.withValues(alpha: 0.08)
            : AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPending
              ? AppColors.warning.withValues(alpha: 0.3)
              : AppColors.success.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          // Avatar / Icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isPending ? AppColors.warning : AppColors.success,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'P',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (!isPending && order != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '#$order',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.location_on, size: 12, color: AppColors.textTertiary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        address,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Actions
          if (isPending) ...[
            const SizedBox(width: 8),
            // Approve button
            GestureDetector(
              onTap: () => _approvePickup(request['invitation_id']),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: AppColors.success, size: 18),
              ),
            ),
            const SizedBox(width: 4),
            // Deny button
            GestureDetector(
              onTap: () => _denyPickup(request['invitation_id']),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: AppColors.error, size: 18),
              ),
            ),
          ] else if (lat != null && lng != null) ...[
            // View on map button for approved pickups
            GestureDetector(
              onTap: () => _openMapLocation(lat, lng, name),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.map, color: AppColors.primary, size: 18),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _approvePickup(String invitationId) async {
    HapticService.lightImpact();
    final success = await _invitationService.respondToPickupRequest(
      invitationId,
      approved: true,
    );
    if (success) {
      _loadPickupRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('tourism_pickup_approved'.tr()),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  Future<void> _denyPickup(String invitationId) async {
    HapticService.lightImpact();
    final success = await _invitationService.respondToPickupRequest(
      invitationId,
      approved: false,
    );
    if (success) {
      _loadPickupRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('tourism_pickup_rejected'.tr()),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    }
  }

  Future<void> _openMapLocation(double lat, double lng, String label) async {
    final url = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    final uri = Uri.parse(url);
    // Use url_launcher - but for now just show in embedded map
    // This should integrate with your existing map view
    HapticService.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('tourism_location_of'.tr(namedArgs: {'label': label, 'lat': '$lat', 'lng': '$lng'})),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  // ===========================================================================
  // NOTIFICATION TOOLS: Emergency Broadcast + Custom Announcements
  // ===========================================================================

  /// Builds the notification tools section with emergency broadcast and
  /// custom announcement creator for the organizer dashboard.
  Widget _buildNotificationToolsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(
            children: [
              const Icon(Icons.campaign_rounded, color: AppColors.warning, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Centro de Notificaciones',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_allInvitations.length} pasajeros',
                  style: TextStyle(
                    color: AppColors.warning,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // --- Level 4 Emergency Broadcast Button ---
          _buildEmergencyBroadcastButton(),
          const SizedBox(height: 12),

          // --- Custom Notification Creator ---
          _buildCustomAnnouncementCard(),
        ],
      ),
    );
  }

  /// Red/orange emergency broadcast button with pulsing icon.
  Widget _buildEmergencyBroadcastButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isSendingEmergency ? null : _showEmergencyBroadcastDialog,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFFDC2626).withOpacity(0.20),
                const Color(0xFFFF6B00).withOpacity(0.12),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFDC2626).withOpacity(0.5),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626).withOpacity(0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _isSendingEmergency
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Color(0xFFFF6B6B),
                        ),
                      )
                    : const Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFFF6B6B),
                        size: 26,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Alerta de Emergencia',
                          style: TextStyle(
                            color: Color(0xFFFF6B6B),
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC2626),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'NIVEL 4',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Enviar alerta urgente a TODOS los pasajeros',
                      style: TextStyle(
                        color: AppColors.textSecondary.withOpacity(0.8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Color(0xFFFF6B6B),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shows a confirmation dialog for emergency broadcast with custom message input.
  void _showEmergencyBroadcastDialog() {
    final messageController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFFF6B6B),
                  size: 24,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Alerta de Emergencia',
                  style: TextStyle(
                    color: Color(0xFFFF6B6B),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFDC2626).withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFFFF6B6B), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Esta alerta se enviara a TODOS los pasajeros del evento, incluyendo los pendientes.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Mensaje de emergencia:',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: messageController,
                maxLines: 3,
                maxLength: 300,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Ej: Cambio de ruta por clima, punto de encuentro actualizado...',
                  hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
                  ),
                  counterStyle: TextStyle(color: AppColors.textTertiary, fontSize: 11),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                messageController.dispose();
                Navigator.of(ctx).pop();
              },
              child: Text(
                'tourism_cancel'.tr(),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () {
                final msg = messageController.text.trim();
                if (msg.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('tourism_emergency_message'.tr()),
                      backgroundColor: AppColors.error,
                    ),
                  );
                  return;
                }
                messageController.dispose();
                Navigator.of(ctx).pop();
                _sendEmergencyBroadcast(msg);
              },
              icon: const Icon(Icons.send_rounded, size: 18),
              label: Text('tourism_send_alert'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Actually sends the emergency broadcast via the service.
  Future<void> _sendEmergencyBroadcast(String message) async {
    if (!mounted) return;
    setState(() => _isSendingEmergency = true);

    try {
      final eventName = _event?['title'] ?? _event?['event_name'] ?? 'Evento';
      final count = await _eventService.broadcastToAllPassengers(
        eventId: widget.eventId,
        title: 'ALERTA: $eventName',
        body: message,
      );

      if (mounted) {
        setState(() => _isSendingEmergency = false);
        HapticService.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Alerta enviada a $count pasajero${count == 1 ? '' : 's'}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSendingEmergency = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('tourism_error_sending_alert'.tr(namedArgs: {'error': '$e'})),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Custom announcement card — lets organizer compose a notification with
  /// title, body, and audience filter.
  Widget _buildCustomAnnouncementCard() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isSendingAnnouncement ? null : _showCustomAnnouncementDialog,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.primary.withOpacity(0.25),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _isSendingAnnouncement
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.primary,
                        ),
                      )
                    : const Icon(
                        Icons.edit_notifications_rounded,
                        color: AppColors.primaryLight,
                        size: 24,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Crear Anuncio',
                      style: TextStyle(
                        color: AppColors.primaryLight,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Enviar notificacion personalizada a pasajeros',
                      style: TextStyle(
                        color: AppColors.textSecondary.withOpacity(0.8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppColors.primaryLight,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shows the full custom announcement dialog with title, body, and audience picker.
  void _showCustomAnnouncementDialog() {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    String selectedAudience = 'todos';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.card,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.edit_notifications_rounded,
                      color: AppColors.primaryLight,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Crear Anuncio',
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
                    // Audience selector
                    const Text(
                      'Audiencia:',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildAudienceChip(
                          label: 'Todos',
                          value: 'todos',
                          icon: Icons.groups_rounded,
                          selected: selectedAudience,
                          onTap: () => setDialogState(() => selectedAudience = 'todos'),
                        ),
                        _buildAudienceChip(
                          label: 'Abordados',
                          value: 'abordados',
                          icon: Icons.directions_bus_rounded,
                          selected: selectedAudience,
                          onTap: () => setDialogState(() => selectedAudience = 'abordados'),
                        ),
                        _buildAudienceChip(
                          label: 'Aceptados',
                          value: 'aceptados',
                          icon: Icons.check_circle_outline_rounded,
                          selected: selectedAudience,
                          onTap: () => setDialogState(() => selectedAudience = 'aceptados'),
                        ),
                        _buildAudienceChip(
                          label: 'Pendientes',
                          value: 'pendientes',
                          icon: Icons.hourglass_top_rounded,
                          selected: selectedAudience,
                          onTap: () => setDialogState(() => selectedAudience = 'pendientes'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Title field
                    const Text(
                      'Titulo:',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: titleController,
                      maxLength: 80,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Ej: Recordatorio de salida',
                        hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                        counterStyle: TextStyle(color: AppColors.textTertiary, fontSize: 11),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Body field
                    const Text(
                      'Mensaje:',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: bodyController,
                      maxLines: 3,
                      maxLength: 300,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Escribe el mensaje para los pasajeros...',
                        hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                        counterStyle: TextStyle(color: AppColors.textTertiary, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    titleController.dispose();
                    bodyController.dispose();
                    Navigator.of(ctx).pop();
                  },
                  child: Text(
                    'tourism_cancel'.tr(),
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    final title = titleController.text.trim();
                    final body = bodyController.text.trim();
                    if (title.isEmpty || body.isEmpty) {
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(
                          content: Text('tourism_complete_title_message'.tr()),
                          backgroundColor: AppColors.warning,
                        ),
                      );
                      return;
                    }
                    final audience = selectedAudience;
                    titleController.dispose();
                    bodyController.dispose();
                    Navigator.of(ctx).pop();
                    _sendCustomAnnouncement(title, body, audience);
                  },
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: Text('tourism_send'.tr()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Helper to build a selectable audience chip in the announcement dialog.
  Widget _buildAudienceChip({
    required String label,
    required String value,
    required IconData icon,
    required String selected,
    required VoidCallback onTap,
  }) {
    final isSelected = selected == value;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.2) : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? AppColors.primaryLight : AppColors.textTertiary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppColors.primaryLight : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Sends the custom announcement through the service, mapping audience to status filter.
  Future<void> _sendCustomAnnouncement(
    String title,
    String body,
    String audience,
  ) async {
    if (!mounted) return;
    setState(() => _isSendingAnnouncement = true);

    try {
      // Map audience selection to Supabase status filter values
      List<String>? statusFilter;
      switch (audience) {
        case 'todos':
          statusFilter = ['accepted', 'checked_in', 'boarded', 'pending', 'invited'];
          break;
        case 'abordados':
          statusFilter = ['checked_in', 'boarded'];
          break;
        case 'aceptados':
          statusFilter = ['accepted'];
          break;
        case 'pendientes':
          statusFilter = ['pending', 'invited'];
          break;
      }

      final count = await _eventService.sendOrganizerAnnouncement(
        eventId: widget.eventId,
        title: title,
        body: body,
        statusFilter: statusFilter,
      );

      if (mounted) {
        setState(() => _isSendingAnnouncement = false);
        HapticService.mediumImpact();

        final audienceLabel = {
          'todos': 'todos los pasajeros',
          'abordados': 'pasajeros abordados',
          'aceptados': 'pasajeros aceptados',
          'pendientes': 'pasajeros pendientes',
        }[audience] ?? 'pasajeros';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Anuncio enviado a $count de $audienceLabel',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSendingAnnouncement = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('tourism_error_sending_announcement'.tr(namedArgs: {'error': '$e'})),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Feed de actividad en tiempo real — muestra estado de cada pasajero
  Widget _buildCheckInKpi(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color.withValues(alpha: 0.7),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Panel de check-in: muestra pasajeros organizados por estatus
  Widget _buildCheckInPanel() {
    // Classify passengers
    final boarded = <Map<String, dynamic>>[];
    final accepted = <Map<String, dynamic>>[];
    final exited = <Map<String, dynamic>>[];
    final pending = <Map<String, dynamic>>[];

    for (final inv in _allInvitations) {
      final status = inv['status'] as String? ?? 'pending';
      final checkStatus = inv['current_check_in_status'] as String?;

      if (checkStatus == 'off_boarded' || inv['exited_at'] != null) {
        exited.add(inv);
      } else if (status == 'boarded' || status == 'checked_in' || checkStatus == 'boarded') {
        boarded.add(inv);
      } else if (status == 'accepted') {
        accepted.add(inv);
      } else if (status == 'pending' || status == 'invited') {
        pending.add(inv);
      }
    }

    final totalOnBoard = boarded.length;
    final totalAccepted = accepted.length;
    final maxP = (_event?['max_passengers'] as num?)?.toInt() ?? 40;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.how_to_reg, color: AppColors.success, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'tourism_checkin_passengers'.tr(),
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                // Counters
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$totalOnBoard abordo',
                    style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$totalAccepted esperando',
                    style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => _showFullScreenCheckIn(boarded, accepted, exited, pending),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.cardSecondary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.fullscreen, color: AppColors.textSecondary, size: 18),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Capacity KPIs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _buildCheckInKpi(
                    '${totalOnBoard + totalAccepted}',
                    '/ $maxP asientos',
                    (totalOnBoard + totalAccepted) >= maxP ? AppColors.error : AppColors.success,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildCheckInKpi(
                    '${pending.length}',
                    'pendientes',
                    Colors.orange,
                  ),
                ),
                if (exited.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildCheckInKpi(
                      '${exited.length}',
                      'bajaron',
                      AppColors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),

          if (_allInvitations.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text('tourism_no_passengers_yet'.tr(), style: TextStyle(color: AppColors.textTertiary, fontSize: 14)),
              ),
            )
          else ...[
            // Boarded section (green, on top)
            if (boarded.isNotEmpty) ...[
              _buildCheckInSectionHeader('A bordo', Icons.directions_bus, AppColors.success, boarded.length),
              for (final p in boarded.take(4))
                _buildCheckInRow(p, 'boarded'),
            ],
            // Accepted / waiting section (orange)
            if (accepted.isNotEmpty) ...[
              _buildCheckInSectionHeader('Esperando abordaje', Icons.access_time, Colors.orange, accepted.length),
              for (final p in accepted.take(4))
                _buildCheckInRow(p, 'accepted'),
            ],
            // Exited section (gray)
            if (exited.isNotEmpty) ...[
              _buildCheckInSectionHeader('Bajaron', Icons.exit_to_app, AppColors.textTertiary, exited.length),
              for (final p in exited.take(2))
                _buildCheckInRow(p, 'exited'),
            ],
            // Pending invitations
            if (pending.isNotEmpty) ...[
              _buildCheckInSectionHeader('Invitación pendiente', Icons.mail_outline, AppColors.textTertiary, pending.length),
              for (final p in pending.take(4))
                _buildCheckInRow(p, 'pending'),
            ],

            if (_allInvitations.length > 6) ...[
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: () => _showFullScreenCheckIn(boarded, accepted, exited, pending),
                  child: Text('tourism_see_all'.tr(namedArgs: {'count': '${_allInvitations.length}'}), style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildFinalizeEventButton() {
    final boarded = _allInvitations.where((inv) {
      final status = inv['status'] as String? ?? '';
      final checkStatus = inv['current_check_in_status'] as String?;
      return status == 'boarded' || status == 'checked_in' || checkStatus == 'boarded';
    }).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.success.withValues(alpha: 0.15),
            AppColors.success.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.flag, color: AppColors.success, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'tourism_finalize_event'.tr(),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'tourism_finalize_event_desc'.tr(namedArgs: {'count': '$boarded'}),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _completeEvent,
              icon: const Icon(Icons.check_circle, size: 20),
              label: Text(
                'tourism_finalize_event'.tr(),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckInSectionHeader(String label, IconData icon, Color color, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('$count', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildCheckInRow(Map<String, dynamic> inv, String group) {
    final name = inv['invitee_name'] ?? inv['invited_name'] ?? 'Pasajero';
    final phone = inv['invitee_phone'] ?? inv['invited_phone'] as String?;
    final hasGps = inv['last_known_lat'] != null;
    final kmTraveled = (inv['km_traveled'] as num?)?.toDouble();
    final totalPrice = (inv['total_price'] as num?)?.toDouble();

    // Timestamps
    final acceptedAt = inv['accepted_at'] as String?;
    final boardedAt = inv['boarded_at'] as String?;
    final exitedAt = inv['exited_at'] as String?;
    final lastCheckInAt = inv['last_check_in_at'] as String?;
    final createdAt = inv['created_at'] as String?;

    Color dotColor;
    String statusText;
    switch (group) {
      case 'boarded':
        dotColor = AppColors.success;
        statusText = hasGps ? 'GPS activo' : 'A bordo';
        break;
      case 'accepted':
        dotColor = Colors.orange;
        statusText = hasGps ? 'Cerca' : 'Esperando';
        break;
      case 'exited':
        dotColor = AppColors.textTertiary;
        statusText = 'Bajó';
        break;
      default:
        dotColor = AppColors.border;
        statusText = 'Pendiente';
    }

    // Build timeline chips
    final timelineChips = <Widget>[];
    if (createdAt != null && group != 'pending') {
      timelineChips.add(_buildTimeChip('Invitado', _formatTimeShort(createdAt), AppColors.textTertiary));
    }
    if (acceptedAt != null) {
      timelineChips.add(_buildTimeChip('Aceptó', _formatTimeShort(acceptedAt), AppColors.primary));
    }
    if (boardedAt != null) {
      timelineChips.add(_buildTimeChip('Abordó', _formatTimeShort(boardedAt), AppColors.success));
    }
    if (lastCheckInAt != null && lastCheckInAt != boardedAt) {
      timelineChips.add(_buildTimeChip('Check-in', _formatTimeShort(lastCheckInAt), Colors.cyan));
    }
    if (exitedAt != null) {
      timelineChips.add(_buildTimeChip('Bajó', _formatTimeShort(exitedAt), Colors.orange));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: dotColor.withValues(alpha: 0.2), width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Name + status
            Row(
              children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    boxShadow: group == 'boarded' ? [BoxShadow(color: dotColor.withValues(alpha: 0.4), blurRadius: 6)] : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (group == 'exited' && totalPrice != null) ...[
                  Text('\$${_fmtPrice(totalPrice)}', style: const TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 6),
                ],
                Text(statusText, style: TextStyle(color: dotColor, fontSize: 11, fontWeight: FontWeight.w600)),
                if (hasGps && group != 'exited')
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(Icons.gps_fixed, size: 11, color: AppColors.success),
                  ),
                // Resend invitation button
                if (group != 'exited')
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: GestureDetector(
                      onTap: () => _resendInvitation(inv),
                      child: Icon(
                        Icons.send,
                        size: 13,
                        color: _canResend(inv['id'] as String?)
                            ? AppColors.primary
                            : AppColors.textTertiary.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
              ],
            ),
            // Row 2: Phone + km
            if (phone != null || (kmTraveled != null && group == 'exited'))
              Padding(
                padding: const EdgeInsets.only(left: 18, top: 2),
                child: Row(
                  children: [
                    if (phone != null) ...[
                      Icon(Icons.phone, size: 10, color: AppColors.textTertiary),
                      const SizedBox(width: 3),
                      Text(phone, style: const TextStyle(color: AppColors.textTertiary, fontSize: 10)),
                    ],
                    if (phone != null && kmTraveled != null && group == 'exited')
                      const SizedBox(width: 10),
                    if (kmTraveled != null && group == 'exited') ...[
                      Icon(Icons.straighten, size: 10, color: AppColors.textTertiary),
                      const SizedBox(width: 3),
                      Text('${kmTraveled.toStringAsFixed(1)} km', style: const TextStyle(color: AppColors.textTertiary, fontSize: 10)),
                    ],
                  ],
                ),
              ),
            // Row 3: Timeline chips
            if (timelineChips.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 18, top: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: timelineChips,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Resend invitation notification to a passenger (5 min cooldown)
  Future<void> _resendInvitation(Map<String, dynamic> inv) async {
    final invId = inv['id'] as String?;
    final userId = inv['user_id'] as String?;
    final name = inv['invitee_name'] ?? inv['invited_name'] ?? 'Pasajero';
    if (invId == null || userId == null) return;

    // Check cooldown
    final lastSent = _resendCooldowns[invId];
    if (lastSent != null && DateTime.now().difference(lastSent).inMinutes < 5) {
      final remaining = 5 - DateTime.now().difference(lastSent).inMinutes;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('tourism_wait_resend'.tr(namedArgs: {'remaining': '$remaining', 'name': name})),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    try {
      final eventName = _event?['event_name'] ?? 'Evento';
      final invCode = _event?['invitation_code'] ?? '';
      final eventId = widget.eventId;

      await Supabase.instance.client.from('notifications').insert({
        'user_id': userId,
        'title': 'Recordatorio: $eventName',
        'body': 'Tu viaje $eventName te espera. Codigo: $invCode',
        'type': 'tourism_invitation',
        'data': {
          'event_id': eventId,
          'invitation_id': invId,
          'invitation_code': invCode,
        },
        'read': false,
      });

      _resendCooldowns[invId] = DateTime.now();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('tourism_reminder_sent'.tr(namedArgs: {'name': name})),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('tourism_error_resending'.tr(namedArgs: {'error': '$e'})),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  bool _canResend(String? invId) {
    if (invId == null) return true;
    final lastSent = _resendCooldowns[invId];
    if (lastSent == null) return true;
    return DateTime.now().difference(lastSent).inMinutes >= 5;
  }

  Widget _buildTimeChip(String label, String time, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600)),
          const SizedBox(width: 3),
          Text(time, style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 9)),
        ],
      ),
    );
  }

  String _formatTimeShort(String isoDate) {
    final dt = DateTime.tryParse(isoDate);
    if (dt == null) return '';
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  void _showFullScreenCheckIn(
    List<Map<String, dynamic>> boarded,
    List<Map<String, dynamic>> accepted,
    List<Map<String, dynamic>> exited,
    List<Map<String, dynamic>> pending,
  ) {
    HapticService.lightImpact();
    final maxP = (_event?['max_passengers'] as num?)?.toInt() ?? 40;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.95,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, scrollController) => Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    const Icon(Icons.how_to_reg, color: AppColors.success, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('tourism_checkin_passengers'.tr(), style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w800)),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              // Stats
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _buildFullScreenStat('A bordo', '${boarded.length}', AppColors.success),
                    const SizedBox(width: 8),
                    _buildFullScreenStat('Esperando', '${accepted.length}', Colors.orange),
                    const SizedBox(width: 8),
                    _buildFullScreenStat('Bajaron', '${exited.length}', AppColors.textTertiary),
                    const SizedBox(width: 8),
                    _buildFullScreenStat('Capacidad', '$maxP', AppColors.primary),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Divider(color: AppColors.border.withValues(alpha: 0.5), height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  children: [
                    if (boarded.isNotEmpty) ...[
                      _buildCheckInSectionHeader('A bordo', Icons.directions_bus, AppColors.success, boarded.length),
                      for (final p in boarded) _buildCheckInRow(p, 'boarded'),
                    ],
                    if (accepted.isNotEmpty) ...[
                      _buildCheckInSectionHeader('Esperando abordaje', Icons.access_time, Colors.orange, accepted.length),
                      for (final p in accepted) _buildCheckInRow(p, 'accepted'),
                    ],
                    if (exited.isNotEmpty) ...[
                      _buildCheckInSectionHeader('Bajaron', Icons.exit_to_app, AppColors.textTertiary, exited.length),
                      for (final p in exited) _buildCheckInRow(p, 'exited'),
                    ],
                    if (pending.isNotEmpty) ...[
                      _buildCheckInSectionHeader('Invitación pendiente', Icons.mail_outline, AppColors.textTertiary, pending.length),
                      for (final p in pending) _buildCheckInRow(p, 'pending'),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _buildActivityItems() {
    final items = <Map<String, dynamic>>[];
    final itinerary = _event?['itinerary'] as List<dynamic>? ?? [];

    // Driver status
    final eventStatus = _event?['status'] as String? ?? 'draft';
    if (eventStatus == 'active') {
      items.add({'type': 'driver_status', 'label': 'Chofer asignado - Esperando inicio', 'icon': 'hourglass', 'color': 'orange', 'time': _event?['updated_at']});
    } else if (eventStatus == 'in_progress') {
      items.add({'type': 'driver_status', 'label': 'Viaje en curso', 'icon': 'bus', 'color': 'success', 'time': _event?['started_at'] ?? _event?['updated_at']});
      final currentStop = (_event?['current_stop_index'] as num?)?.toInt() ?? 0;
      if (currentStop > 0 && currentStop < itinerary.length) {
        final stopName = itinerary[currentStop]['name'] ?? 'Parada $currentStop';
        items.add({'type': 'stop', 'label': 'En parada: $stopName', 'icon': 'location', 'color': 'primary', 'time': _event?['updated_at']});
      }
    } else if (eventStatus == 'completed') {
      items.add({'type': 'driver_status', 'label': 'Viaje completado', 'icon': 'check', 'color': 'success', 'time': _event?['completed_at']});
    }

    // Check-ins & passenger events
    for (final ci in _checkIns) {
      final name = ci['invited_name'] ?? ci['invitee_name'] ?? 'Pasajero';
      final checkType = ci['check_in_type'] as String?;
      final time = ci['checked_in_at'] ?? ci['created_at'];

      if (checkType == 'boarding') {
        items.add({'type': 'boarding', 'label': '$name abordó', 'icon': 'person_check', 'color': 'success', 'time': time});
      } else if (checkType == 'stop') {
        final stopIdx = ci['stop_index'] as int?;
        final stopName = (stopIdx != null && stopIdx < itinerary.length) ? itinerary[stopIdx]['name'] : 'parada';
        items.add({'type': 'stop_exit', 'label': '$name bajó en $stopName', 'icon': 'person_off', 'color': 'orange', 'time': time});
      } else if (checkType == 'final') {
        items.add({'type': 'completed', 'label': '$name completó el viaje', 'icon': 'flag', 'color': 'primary', 'time': time});
      } else {
        items.add({'type': 'checkin', 'label': '$name hizo check-in', 'icon': 'check_circle', 'color': 'success', 'time': time});
      }
    }

    // Pickup requests (passenger alerts)
    for (final req in _pickupRequests) {
      final name = req['invitee_name'] ?? 'Pasajero';
      final reqStatus = req['pickup_status'] ?? req['status'] ?? 'pending';
      if (reqStatus == 'pending') {
        items.add({'type': 'alert', 'label': '$name solicita parada', 'icon': 'warning', 'color': 'error', 'time': req['created_at'], 'data': req});
      }
    }

    // GPS arrivals
    for (final loc in _passengerLocations) {
      final name = loc['invitee_name'] ?? 'Pasajero';
      final status = loc['status'] as String?;
      if (status == 'accepted') {
        items.add({'type': 'gps', 'label': '$name cerca del punto de abordaje', 'icon': 'gps', 'color': 'primary', 'time': loc['updated_at']});
      }
    }

    // Sort by time descending (newest first)
    items.sort((a, b) {
      final aTime = a['time']?.toString() ?? '';
      final bTime = b['time']?.toString() ?? '';
      return bTime.compareTo(aTime);
    });

    return items;
  }

  Widget _buildActivityFeed() {
    final total = _stats['total'] ?? 0;
    final accepted = _stats['confirmed'] ?? _stats['accepted'] ?? 0;
    final items = _buildActivityItems();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with expand button
          Row(
            children: [
              const Icon(Icons.timeline, color: AppColors.primary, size: 22),
              const SizedBox(width: 10),
              const Text(
                'Actividad en Vivo',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$accepted/$total',
                  style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _showFullScreenActivity(items),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.cardSecondary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.fullscreen, color: AppColors.textSecondary, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'tourism_no_activity_yet'.tr(),
                  style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
                ),
              ),
            )
          else ...[
            for (final item in items.take(6))
              _buildActivityItem(item),

            if (items.length > 6) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () => _showFullScreenActivity(items),
                  child: Text(
                    'Ver todo (${items.length})',
                    style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildActivityItem(Map<String, dynamic> item) {
    final label = item['label'] as String;
    final colorKey = item['color'] as String? ?? 'primary';
    final iconKey = item['icon'] as String? ?? 'info';
    final isAlert = item['type'] == 'alert';

    final color = switch (colorKey) {
      'success' => AppColors.success,
      'error' => AppColors.error,
      'orange' => Colors.orange,
      _ => AppColors.primary,
    };

    final icon = switch (iconKey) {
      'hourglass' => Icons.hourglass_empty,
      'bus' => Icons.directions_bus,
      'check' => Icons.check_circle,
      'person_check' => Icons.person_add_alt_1,
      'person_off' => Icons.person_off,
      'flag' => Icons.flag,
      'check_circle' => Icons.check_circle_outline,
      'warning' => Icons.warning_amber_rounded,
      'gps' => Icons.gps_fixed,
      'location' => Icons.location_on,
      _ => Icons.info_outline,
    };

    // Format time
    String timeStr = '';
    final time = item['time']?.toString();
    if (time != null) {
      final dt = DateTime.tryParse(time);
      if (dt != null) {
        final local = dt.toLocal();
        timeStr = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isAlert ? color.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: isAlert ? Border.all(color: color.withValues(alpha: 0.2)) : null,
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 14),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isAlert ? color : AppColors.textPrimary,
                fontSize: 13,
                fontWeight: isAlert ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
          if (timeStr.isNotEmpty)
            Text(
              timeStr,
              style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
            ),
        ],
      ),
    );
  }

  void _showFullScreenActivity(List<Map<String, dynamic>> items) {
    HapticService.lightImpact();
    final total = _stats['total'] ?? 0;
    final accepted = _stats['confirmed'] ?? _stats['accepted'] ?? 0;
    final checkedIn = (_stats['checked_in'] ?? 0) + (_stats['boarded'] ?? 0);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.95,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, scrollController) => Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    const Icon(Icons.timeline, color: AppColors.primary, size: 24),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Actividad en Vivo',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w800),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              // Stats bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _buildFullScreenStat('Invitados', '$total', AppColors.textTertiary),
                    const SizedBox(width: 12),
                    _buildFullScreenStat('Aceptaron', '$accepted', AppColors.success),
                    const SizedBox(width: 12),
                    _buildFullScreenStat('Abordaron', '$checkedIn', Colors.orange),
                    const SizedBox(width: 12),
                    _buildFullScreenStat('Con GPS', '${_passengerLocations.length}', AppColors.primary),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Divider(color: AppColors.border.withValues(alpha: 0.5), height: 1),
              // Activity list
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text('tourism_no_activity_yet'.tr(), style: const TextStyle(color: AppColors.textTertiary, fontSize: 16)),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: items.length,
                        itemBuilder: (_, i) => _buildActivityItem(items[i]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFullScreenStat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 10, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }


  /// Sección de solicitudes de unión (solo eventos públicos)
  Widget _buildJoinRequestsSection() {
    final pending = _joinRequests.where((r) => r['status'] == 'pending').toList();
    if (pending.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_add, color: Colors.amber, size: 22),
              const SizedBox(width: 10),
              const Text(
                'Solicitudes de Unión',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${pending.length} pendientes',
                  style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final req in pending.take(3))
            _buildJoinRequestItem(req),
          if (pending.length > 3)
            Center(
              child: TextButton(
                onPressed: () {
                  // Navigate to full join requests list
                },
                child: Text('tourism_see_all'.tr(namedArgs: {'count': '${pending.length}'}), style: TextStyle(color: AppColors.primary)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildJoinRequestItem(Map<String, dynamic> request) {
    final name = request['passenger_name'] as String? ?? 'Pasajero';
    final pickup = request['pickup_address'] as String?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.amber.withValues(alpha: 0.15),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                if (pickup != null)
                  Text(pickup, style: TextStyle(color: AppColors.textTertiary, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          // Approve
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.check, color: AppColors.success, size: 18),
            ),
            onPressed: () async {
              final reqId = request['id']?.toString();
              if (reqId == null) return;
              try {
                await _eventService.acceptJoinRequest(reqId, widget.eventId);
                HapticService.success();
                _loadJoinRequests();
                _loadStats();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('tourism_error_generic'.tr(namedArgs: {'error': '$e'})), backgroundColor: AppColors.error),
                  );
                }
              }
            },
          ),
          // Deny
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.close, color: AppColors.error, size: 18),
            ),
            onPressed: () async {
              final reqId = request['id']?.toString();
              if (reqId == null) return;
              try {
                await _eventService.rejectJoinRequest(reqId);
                HapticService.warning();
                _loadJoinRequests();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('tourism_error_generic'.tr(namedArgs: {'error': '$e'})), backgroundColor: AppColors.error),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _loadJoinRequests() async {
    try {
      final requests = await _eventService.getJoinRequestsForEvent(widget.eventId);
      if (mounted) {
        setState(() => _joinRequests = requests);
      }
    } catch (e) {
      debugPrint('Error loading join requests: $e');
    }
  }

  Widget _buildFinancialSection() {
    final totalBasePrice =
        (_event?['total_base_price'] as num?)?.toDouble() ?? 0;
    final distanceKm =
        (_event?['total_distance_km'] as num?)?.toDouble() ?? 0;
    final pricePerKm = (_event?['price_per_km'] as num?)?.toDouble() ?? 0;
    final toroFee = (_event?['toro_fee'] as num?)?.toDouble() ?? 0;
    final organizerCommission =
        (_event?['organizer_commission'] as num?)?.toDouble() ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        children: [
          // Header - always visible
          InkWell(
            onTap: () {
              HapticService.lightImpact();
              setState(() => _isFinanceExpanded = !_isFinanceExpanded);
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.success.withValues(alpha: 0.2),
                          AppColors.success.withValues(alpha: 0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_outlined,
                      color: AppColors.success,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Finanzas',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Total: \$${_fmtPrice(totalBasePrice)} MXN',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.cardSecondary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _isFinanceExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: AppColors.textSecondary,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Expanded content
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _isFinanceExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: [
                Divider(
                  color: AppColors.border.withValues(alpha: 0.5),
                  height: 1,
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _buildFinancialRow(
                        'Total Bus',
                        '\$${_fmtPrice(totalBasePrice)} MXN',
                        icon: Icons.directions_bus,
                        iconColor: AppColors.primary,
                        isBold: true,
                      ),
                      const SizedBox(height: 14),
                      _buildFinancialRow(
                        'Distancia',
                        '${_fmtPrice(distanceKm)} km',
                        icon: Icons.straighten,
                        iconColor: AppColors.textTertiary,
                      ),
                      const SizedBox(height: 14),
                      _buildFinancialRow(
                        'Precio por km',
                        '\$${pricePerKm.toStringAsFixed(2)} MXN',
                        icon: Icons.price_change_outlined,
                        iconColor: AppColors.textTertiary,
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.cardSecondary,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            _buildFinancialRow(
                              'Comision TORO (18%)',
                              '-\$${_fmtPrice(toroFee)}',
                              color: AppColors.error,
                            ),
                            // Only show organizer commission when there's no driver assigned
                            // (organizer acts as driver and earns commission)
                            if (_event?['driver_id'] == null) ...[
                              const SizedBox(height: 12),
                              _buildFinancialRow(
                                'Tu Comision (3%)',
                                '+\$${_fmtPrice(organizerCommission)}',
                                color: AppColors.success,
                                isBold: true,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                HapticService.lightImpact();
                                // TODO: Generate PDF
                              },
                              icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                              label: const Text(
                                'Descargar PDF',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.textSecondary,
                                side: const BorderSide(color: AppColors.border),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                HapticService.lightImpact();
                                // TODO: Send email
                              },
                              icon: const Icon(Icons.email_outlined, size: 20),
                              label: const Text(
                                'Enviar Email',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.textSecondary,
                                side: const BorderSide(color: AppColors.border),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialRow(
    String label,
    String value, {
    bool isBold = false,
    Color? color,
    IconData? icon,
    Color? iconColor,
  }) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, color: iconColor ?? AppColors.textTertiary, size: 20),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
              fontWeight: isBold ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color ?? AppColors.textPrimary,
            fontSize: 16,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNavigation() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.border.withValues(alpha: 0.5), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.people_alt_outlined, 'Pasajeros'),
              _buildNavItem(1, Icons.chat_bubble_outline, 'Chat', badgeCount: _chatUnreadCount),
              _buildNavItem(2, Icons.photo_library_outlined, 'Fotos'),
              _buildNavItem(3, Icons.person_add_outlined, 'Invitar'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label, {int badgeCount = 0}) {
    final isSelected = _currentTabIndex == index;

    return GestureDetector(
      onTap: () => _onTabChanged(index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  size: 26,
                  color: isSelected ? AppColors.primary : AppColors.textTertiary,
                ),
                if (badgeCount > 0)
                  Positioned(
                    right: -8,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.surface, width: 1.5),
                      ),
                      child: Text(
                        badgeCount > 99 ? '99+' : '$badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppColors.primary : AppColors.textTertiary,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════════════════════

  String _formatDate(DateTime date) {
    const months = [
      'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
      'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'draft':
        return 'Esperando Puja';
      case 'pending_vehicle':
        return 'Esperando Vehiculo';
      case 'vehicle_accepted':
        return 'Vehiculo Confirmado';
      case 'vehicle_rejected':
        return 'Vehiculo Rechazado';
      case 'active':
        return 'Activo';
      case 'in_progress':
        return 'En Progreso';
      case 'completed':
        return 'Completado';
      case 'cancelled':
        return 'Cancelado';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'draft':
        return AppColors.textTertiary;
      case 'pending_vehicle':
        return AppColors.warning;
      case 'vehicle_accepted':
        return AppColors.primary;
      case 'vehicle_rejected':
        return AppColors.error;
      case 'active':
        return AppColors.success;
      case 'in_progress':
        return AppColors.primary;
      case 'completed':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      default:
        return AppColors.textTertiary;
    }
  }
}

// =============================================================================
// Live Map Screen - Real-time passenger tracking with invitee list
// =============================================================================

class _EventLiveMapScreen extends StatefulWidget {
  final String eventId;
  final Map<String, dynamic>? event;
  final List<Map<String, dynamic>> passengerLocations;

  const _EventLiveMapScreen({
    required this.eventId,
    required this.event,
    required this.passengerLocations,
  });

  @override
  State<_EventLiveMapScreen> createState() => _EventLiveMapScreenState();
}

class _EventLiveMapScreenState extends State<_EventLiveMapScreen> {
  final MapController _mapController = MapController();
  final TourismInvitationService _invitationService = TourismInvitationService();

  late List<Map<String, dynamic>> _locations;
  List<Map<String, dynamic>> _allInvitations = [];
  Map<String, dynamic>? _selectedPassenger;
  bool _isLoadingInvitations = true;
  final bool _isPanelExpanded = true;

  @override
  void initState() {
    super.initState();
    _locations = List.from(widget.passengerLocations);
    _loadAllInvitations();
  }

  @override
  void didUpdateWidget(covariant _EventLiveMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update locations when parent passes new data
    if (widget.passengerLocations != oldWidget.passengerLocations) {
      setState(() {
        _locations = List.from(widget.passengerLocations);
      });
    }
  }

  Future<void> _loadAllInvitations() async {
    try {
      final invitations = await _invitationService.getEventInvitations(widget.eventId);
      if (mounted) {
        setState(() {
          _allInvitations = invitations;
          _isLoadingInvitations = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingInvitations = false);
      }
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  LatLng _getMapCenter() {
    // Try to get driver/bus location first
    final driver = widget.event?['drivers'] as Map<String, dynamic>?;
    final busLat = (driver?['current_lat'] as num?)?.toDouble();
    final busLng = (driver?['current_lng'] as num?)?.toDouble();

    if (busLat != null && busLng != null) {
      return LatLng(busLat, busLng);
    }

    // Try to get first passenger location
    if (_locations.isNotEmpty) {
      final first = _locations.first;
      final lat = (first['lat'] as num?)?.toDouble();
      final lng = (first['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        return LatLng(lat, lng);
      }
    }

    // Try to get first itinerary point
    final itinerary = widget.event?['itinerary'] as List<dynamic>? ?? [];
    if (itinerary.isNotEmpty) {
      final first = itinerary.first as Map<String, dynamic>;
      final lat = (first['lat'] as num?)?.toDouble();
      final lng = (first['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        return LatLng(lat, lng);
      }
    }

    // Default to Mexico
    return const LatLng(19.4326, -99.1332);
  }

  void _focusOnPassenger(Map<String, dynamic> invitation) {
    HapticService.lightImpact();

    // Find this passenger's location data
    final invitationId = invitation['id'];
    final locData = _locations.firstWhere(
      (l) => l['invitation_id'] == invitationId,
      orElse: () => {},
    );

    // locData uses 'lat'/'lng' from service, invitation might have 'last_known_lat'
    final lat = (locData['lat'] as num?)?.toDouble() ??
                (invitation['last_known_lat'] as num?)?.toDouble();
    final lng = (locData['lng'] as num?)?.toDouble() ??
                (invitation['last_known_lng'] as num?)?.toDouble();

    if (lat != null && lng != null) {
      _mapController.move(LatLng(lat, lng), 16);
      setState(() {
        _selectedPassenger = {
          ...invitation,
          'last_known_lat': lat,
          'last_known_lng': lng,
        };
      });
    } else {
      // No GPS, just select them
      setState(() {
        _selectedPassenger = invitation;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('tourism_passenger_no_gps'.tr()),
          backgroundColor: AppColors.warning,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // Add itinerary stops
    final itinerary = widget.event?['itinerary'] as List<dynamic>? ?? [];
    for (var i = 0; i < itinerary.length; i++) {
      final stop = itinerary[i] as Map<String, dynamic>;
      final lat = (stop['lat'] as num?)?.toDouble();
      final lng = (stop['lng'] as num?)?.toDouble();
      final name = stop['name'] ?? 'Parada ${i + 1}';
      final isFirst = i == 0;
      final isLast = i == itinerary.length - 1;

      if (lat != null && lng != null) {
        markers.add(
          Marker(
            point: LatLng(lat, lng),
            width: 36,
            height: 36,
            child: Tooltip(
              message: name,
              child: Container(
                decoration: BoxDecoration(
                  color: isFirst ? AppColors.success : isLast ? AppColors.error : AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6)],
                ),
                child: Center(
                  child: Icon(
                    isFirst ? Icons.trip_origin : isLast ? Icons.flag : Icons.location_on,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }

    // Add bus/driver location
    final driver = widget.event?['drivers'] as Map<String, dynamic>?;
    final busLat = (driver?['current_lat'] as num?)?.toDouble();
    final busLng = (driver?['current_lng'] as num?)?.toDouble();

    if (busLat != null && busLng != null) {
      markers.add(
        Marker(
          point: LatLng(busLat, busLng),
          width: 52,
          height: 52,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.warning,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [BoxShadow(color: AppColors.warning.withValues(alpha: 0.5), blurRadius: 12, spreadRadius: 2)],
            ),
            child: const Icon(Icons.directions_bus, color: Colors.white, size: 26),
          ),
        ),
      );
    }

    // Add passenger locations from _locations (GPS active)
    for (final loc in _locations) {
      final lat = (loc['lat'] as num?)?.toDouble();
      final lng = (loc['lng'] as num?)?.toDouble();
      final name = loc['invited_name'] ?? 'Pasajero';
      final isCheckedIn = loc['status'] == 'checked_in';
      final isSelected = _selectedPassenger?['id'] == loc['invitation_id'] ||
                         _selectedPassenger?['invitation_id'] == loc['invitation_id'];

      if (lat != null && lng != null) {
        markers.add(
          Marker(
            point: LatLng(lat, lng),
            width: isSelected ? 48 : 40,
            height: isSelected ? 48 : 40,
            child: GestureDetector(
              onTap: () {
                HapticService.lightImpact();
                setState(() {
                  _selectedPassenger = loc;
                });
              },
              child: Tooltip(
                message: name,
                child: Container(
                  decoration: BoxDecoration(
                    color: isCheckedIn ? AppColors.success : AppColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: isSelected ? AppColors.warning : Colors.white, width: isSelected ? 3 : 2),
                    boxShadow: [BoxShadow(color: (isCheckedIn ? AppColors.success : AppColors.primary).withValues(alpha: 0.4), blurRadius: 8)],
                  ),
                  child: Icon(isCheckedIn ? Icons.check : Icons.person, color: Colors.white, size: isSelected ? 24 : 20),
                ),
              ),
            ),
          ),
        );
      }
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final eventName = widget.event?['event_name'] ?? 'Evento';
    final gpsCount = _locations.where((l) => l['lat'] != null).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Map - takes full screen
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _getMapCenter(),
              initialZoom: 14,
              onTap: (_, _) {
                setState(() => _selectedPassenger = null);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.toro.driver',
              ),
              MarkerLayer(markers: _buildMarkers()),
            ],
          ),

          // Top bar with back button and title
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(8, MediaQuery.of(context).padding.top + 8, 8, 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.background,
                    AppColors.background.withValues(alpha: 0.8),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Icon(Icons.arrow_back, color: AppColors.textPrimary, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      eventName,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // GPS count badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: gpsCount > 0 ? AppColors.success : AppColors.textTertiary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.gps_fixed, color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                        Text('$gpsCount', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      HapticService.lightImpact();
                      _mapController.move(_getMapCenter(), 14);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Icon(Icons.my_location, color: AppColors.primary, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom panel with invitee list
          DraggableScrollableSheet(
            initialChildSize: 0.35,
            minChildSize: 0.12,
            maxChildSize: 0.7,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, -4)),
                  ],
                ),
                child: Column(
                  children: [
                    // Handle bar
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.textTertiary.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    // Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          const Icon(Icons.people, color: AppColors.primary, size: 20),
                          const SizedBox(width: 10),
                          const Text(
                            'Invitados',
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${_allInvitations.length}',
                              style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const Spacer(),
                          // Legend
                          Row(
                            children: [
                              Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                              const SizedBox(width: 4),
                              const Text('GPS', style: TextStyle(color: AppColors.textTertiary, fontSize: 10)),
                              const SizedBox(width: 8),
                              Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.textTertiary, shape: BoxShape.circle)),
                              const SizedBox(width: 4),
                              Text('tourism_no_gps'.tr(), style: const TextStyle(color: AppColors.textTertiary, fontSize: 10)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Divider(height: 1, color: AppColors.border.withValues(alpha: 0.5)),
                    // List
                    Expanded(
                      child: _isLoadingInvitations
                          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                          : _allInvitations.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.people_outline, size: 40, color: AppColors.textTertiary.withValues(alpha: 0.5)),
                                      const SizedBox(height: 12),
                                      Text('tourism_no_guests'.tr(), style: const TextStyle(color: AppColors.textTertiary, fontSize: 14)),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  controller: scrollController,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  itemCount: _allInvitations.length + 1, // +1 for driver
                                  itemBuilder: (context, index) {
                                    // First item is the driver
                                    if (index == 0) {
                                      return _buildDriverRow();
                                    }
                                    final invitation = _allInvitations[index - 1];
                                    return _buildInviteeRow(invitation);
                                  },
                                ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInviteeRow(Map<String, dynamic> invitation) {
    final name = invitation['invited_name'] ?? 'Invitado';
    final status = invitation['status'] ?? 'pending';
    final invitationId = invitation['id'];

    // Check if this person has GPS active
    // Service returns 'lat'/'lng', not 'last_known_lat'/'last_known_lng'
    final hasGps = _locations.any((l) =>
      l['invitation_id'] == invitationId && l['lat'] != null
    );
    final isCheckedIn = status == 'checked_in';
    final isAccepted = status == 'accepted';
    final isSelected = _selectedPassenger?['id'] == invitationId ||
                       _selectedPassenger?['invitation_id'] == invitationId;

    return GestureDetector(
      onTap: () => _focusOnPassenger(invitation),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          children: [
            // Avatar with status
            Stack(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isCheckedIn
                        ? AppColors.success.withValues(alpha: 0.15)
                        : isAccepted
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : AppColors.textTertiary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isCheckedIn ? Icons.check : Icons.person,
                    color: isCheckedIn ? AppColors.success : isAccepted ? AppColors.primary : AppColors.textTertiary,
                    size: 20,
                  ),
                ),
                // GPS indicator
                if (hasGps)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.card, width: 2),
                      ),
                      child: const Icon(Icons.gps_fixed, color: Colors.white, size: 8),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            // Name and status
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _getStatusLabel(status),
                    style: TextStyle(
                      color: _getStatusColor(status),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            // Cupo / status chip (always visible)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _getStatusColor(status).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _getStatusLabel(status),
                style: TextStyle(
                  color: _getStatusColor(status),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            // GPS indicator
            if (hasGps)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.location_on, color: AppColors.success, size: 16),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.textTertiary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'tourism_no_gps'.tr(),
                  style: const TextStyle(color: AppColors.textTertiary, fontSize: 10),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Builds the driver row for the list - allows focusing on driver location
  Widget _buildDriverRow() {
    final driver = widget.event?['drivers'] as Map<String, dynamic>?;
    debugPrint('DRIVER_ROW -> driver object: $driver');
    debugPrint('DRIVER_ROW -> current_lat: ${driver?['current_lat']}, current_lng: ${driver?['current_lng']}');
    final driverName = driver?['full_name'] ?? driver?['name'] ?? 'Conductor';
    final driverLat = (driver?['current_lat'] as num?)?.toDouble();
    final driverLng = (driver?['current_lng'] as num?)?.toDouble();
    final hasGps = driverLat != null && driverLng != null;
    debugPrint('DRIVER_ROW -> hasGps: $hasGps');
    final isSelected = _selectedPassenger?['is_driver'] == true;

    return GestureDetector(
      onTap: () => _focusOnDriver(),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.warning.withValues(alpha: 0.15) : AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.warning : AppColors.border,
            width: isSelected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          children: [
            // Bus icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.directions_bus, color: AppColors.warning, size: 20),
            ),
            const SizedBox(width: 12),
            // Name and role
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    driverName,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Conductor',
                    style: TextStyle(color: AppColors.warning, fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            // GPS indicator
            if (hasGps)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.location_on, color: AppColors.warning, size: 16),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.textTertiary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'tourism_no_gps'.tr(),
                  style: const TextStyle(color: AppColors.textTertiary, fontSize: 10),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Focus on driver location when tapped
  void _focusOnDriver() {
    HapticService.lightImpact();

    final driver = widget.event?['drivers'] as Map<String, dynamic>?;
    final lat = (driver?['current_lat'] as num?)?.toDouble();
    final lng = (driver?['current_lng'] as num?)?.toDouble();

    if (lat != null && lng != null) {
      _mapController.move(LatLng(lat, lng), 16);
      setState(() {
        _selectedPassenger = {'is_driver': true, 'name': driver?['full_name'] ?? 'Conductor'};
      });
    } else {
      setState(() {
        _selectedPassenger = {'is_driver': true, 'name': driver?['full_name'] ?? 'Conductor'};
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('tourism_driver_no_gps'.tr()),
          backgroundColor: AppColors.warning,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'accepted': return 'Aceptado';
      case 'checked_in': return 'A bordo';
      case 'pending': return 'Pendiente';
      case 'declined': return 'Rechazado';
      default: return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'accepted': return AppColors.primary;
      case 'checked_in': return AppColors.success;
      case 'pending': return AppColors.warning;
      case 'declined': return AppColors.error;
      default: return AppColors.textTertiary;
    }
  }
}