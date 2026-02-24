import 'dart:async';
import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../providers/driver_provider.dart';
import '../../services/location_service.dart';
import '../../services/tourism_event_service.dart';
import '../../services/tourism_invitation_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';
import '../../widgets/scrollable_time_picker.dart';
import '../../services/tourism_messaging_service.dart';
import '../../widgets/tourism_chat_widget.dart';
import 'join_requests_screen.dart';
import 'live_trip_panel_screen.dart';
import 'tourism_chat_screen.dart';
import 'tourism_passenger_list_screen.dart';
import '../organizer/organizer_itinerary_screen.dart';

/// Tourism mode home screen for drivers with an assigned event.
///
/// This screen replaces the normal home_screen when driver.vehicle_mode == 'tourism'.
/// Shows event info, KPIs, route map, current stop progress, and navigation.
class TourismDriverHomeScreen extends StatefulWidget {
  final String eventId;

  const TourismDriverHomeScreen({
    super.key,
    required this.eventId,
  });

  @override
  State<TourismDriverHomeScreen> createState() => _TourismDriverHomeScreenState();
}

class _TourismDriverHomeScreenState extends State<TourismDriverHomeScreen>
    with SingleTickerProviderStateMixin {
  final TourismEventService _eventService = TourismEventService();
  final TourismInvitationService _invitationService = TourismInvitationService();
  final LocationService _locationService = LocationService();
  final MapController _mapController = MapController();

  // Event data
  Map<String, dynamic>? _event;
  List<Map<String, dynamic>> _itinerary = [];
  Map<String, dynamic> _stats = {
    'total': 0,
    'accepted': 0,
    'checked_in': 0,
  };

  // Location tracking
  Position? _currentPosition;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _locationUpdateTimer;
  bool _isGpsActive = false;

  // UI State
  bool _isLoading = true;
  final int _selectedNavIndex = 0;
  int _currentStopIndex = 0;
  int _pendingJoinCount = 0;

  // Chat unread badge
  final TourismMessagingService _chatMessagingService = TourismMessagingService();
  int _chatUnreadCount = 0;

  // Realtime subscription for event updates
  RealtimeChannel? _eventChannel;

  // Animation for live indicator
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initPulseAnimation();
    _loadEventData(showLoader: true);
    _startGpsTracking();
    _subscribeToChatUnread();
    _subscribeToEventUpdates();
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

  /// Subscribe to real-time chat messages to update unread badge count.
  void _subscribeToChatUnread() {
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    final userId = driverProvider.driver?.id;
    if (userId == null) return;

    // Load initial unread count
    _chatMessagingService.getMessages(widget.eventId).then((messages) {
      if (!mounted) return;
      final unread = messages
          .where((m) => m.senderId != userId && !m.readBy.contains(userId))
          .length;
      setState(() => _chatUnreadCount = unread);
    }).catchError((_) {});

    // Real-time: use keyed subscription to avoid conflicts with dashboard
    _chatMessagingService.subscribeWithKey('driverHome', widget.eventId, (newMessage) {
      if (!mounted) return;
      if (newMessage.senderId != userId) {
        setState(() => _chatUnreadCount++);
      }
    });
  }

  void _subscribeToEventUpdates() {
    _eventChannel = Supabase.instance.client.channel('event_${widget.eventId}');
    _eventChannel!.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'tourism_events',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: widget.eventId,
      ),
      callback: (payload) {
        debugPrint('REALTIME -> tourism_events updated, reloading...');
        _loadEventData();
      },
    ).subscribe();
  }

  @override
  void dispose() {
    _eventChannel?.unsubscribe();
    _pulseController.dispose();
    _positionSubscription?.cancel();
    _locationUpdateTimer?.cancel();
    _mapController.dispose();
    _chatMessagingService.unsubscribeKey('driverHome');
    super.dispose();
  }

  Future<void> _loadEventData({bool showLoader = false}) async {
    if (showLoader && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      // Load event details
      final event = await _eventService.getEvent(widget.eventId);
      if (event != null) {
        _event = event;

        // Extract itinerary: read JSONB directly (source of truth for driver edits)
        // The normalized table may be out of sync due to RLS restrictions
        final jsonbRaw = await Supabase.instance.client
            .from('tourism_events')
            .select('itinerary')
            .eq('id', widget.eventId)
            .single();
        final jsonbItinerary = jsonbRaw['itinerary'] as List?;
        final normalizedItinerary = event['tourism_event_itinerary'] as List?;

        // Use whichever source has more data (JSONB is updated by driver, normalized may lag)
        final itineraryData = (jsonbItinerary != null && normalizedItinerary != null && jsonbItinerary.length >= normalizedItinerary.length)
            ? jsonbItinerary
            : (normalizedItinerary ?? jsonbItinerary ?? event['itinerary']);

        if (itineraryData != null && itineraryData is List && itineraryData.isNotEmpty) {
          _itinerary = List<Map<String, dynamic>>.from(
            itineraryData.map((e) => Map<String, dynamic>.from(e as Map)),
          );
          _itinerary.sort((a, b) {
            final orderA = (a['stop_order'] as int?) ?? (a['stopOrder'] as int?) ?? (a['order'] as int?) ?? 0;
            final orderB = (b['stop_order'] as int?) ?? (b['stopOrder'] as int?) ?? (b['order'] as int?) ?? 0;
            return orderA.compareTo(orderB);
          });
        }

        // Determine current stop index
        _currentStopIndex = _findCurrentStopIndex();
      }

      // Load invitation stats
      _stats = await _invitationService.getInvitationStats(widget.eventId);

      // Load pending join request count
      _pendingJoinCount =
          await _eventService.countPendingJoinRequests(widget.eventId);
    } catch (e) {
      debugPrint('Error loading event data: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  int _findCurrentStopIndex() {
    // Find the first stop that hasn't been arrived at yet
    for (int i = 0; i < _itinerary.length; i++) {
      if (_itinerary[i]['arrived_at'] == null) {
        return i;
      }
    }
    // All stops completed, return last
    return _itinerary.isEmpty ? 0 : _itinerary.length - 1;
  }

  Future<void> _startGpsTracking() async {
    final hasPermission = await _locationService.checkAndRequestPermission();
    if (!hasPermission) return;

    // Get initial position
    _currentPosition = await _locationService.getCurrentPosition();
    if (mounted) {
      setState(() => _isGpsActive = true);
    }

    // Start position stream
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 20, // Update every 20 meters
    );

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _isGpsActive = true;
        });
      }
    });

    // Update location in database every 10 seconds
    _locationUpdateTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _updateLocationInDatabase(),
    );
  }

  Future<void> _updateLocationInDatabase() async {
    if (_currentPosition == null) return;

    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    final driverId = driverProvider.driver?.id;
    final vehicleId = _event?['vehicle_id'] as String?;
    if (driverId == null) return;

    try {
      // Update driver table
      await Supabase.instance.client.from('drivers').update({
        'current_lat': _currentPosition!.latitude,
        'current_lng': _currentPosition!.longitude,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', driverId);

      // Update bus_driver_location table (for tourism tracking)
      await Supabase.instance.client.from('bus_driver_location').upsert({
        'driver_id': driverId,
        'route_id': widget.eventId, // Event ID as route ID for tourism
        'vehicle_id': vehicleId,
        'lat': _currentPosition!.latitude,
        'lng': _currentPosition!.longitude,
        'speed': _currentPosition!.speed,
        'heading': _currentPosition!.heading,
        'accuracy': _currentPosition!.accuracy,
        'altitude': _currentPosition!.altitude,
        'is_moving': _currentPosition!.speed > 1.0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'driver_id');

      debugPrint('TOURISM_GPS -> Updated both tables: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');
    } catch (e) {
      debugPrint('TOURISM_GPS -> Error updating location: $e');
    }
  }

  Future<void> _markStopArrived() async {
    if (_itinerary.isEmpty) return;

    HapticService.success();

    try {
      final stopName = _itinerary[_currentStopIndex]['name'] ?? 'tourism_stop_label'.tr(namedArgs: {'number': '${_currentStopIndex + 1}'});
      await _eventService.markStopArrived(widget.eventId, _currentStopIndex);
      await _loadEventData();

      // Notify organizer in real-time
      final organizerId = _event?['organizer_id'] as String?;
      if (organizerId != null) {
        _notifyOrganizer(
          organizerId,
          'tourism_arrival_at_stop'.tr(namedArgs: {'stop': stopName}),
          'tourism_driver_arrived_stop'.tr(namedArgs: {'number': '${_currentStopIndex + 1}', 'stop': stopName}),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('tourism_arrival_registered'.tr(namedArgs: {'stop': stopName})),
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
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Send notification to the organizer about driver actions
  Future<void> _notifyOrganizer(String organizerId, String title, String body) async {
    try {
      // Look up the organizer's user_id to send notification
      final orgData = await Supabase.instance.client
          .from('organizers')
          .select('user_id')
          .eq('id', organizerId)
          .maybeSingle();
      final orgUserId = orgData?['user_id'] as String?;
      if (orgUserId == null) return;

      await Supabase.instance.client.from('notifications').insert({
        'user_id': orgUserId,
        'title': title,
        'body': body,
        'type': 'driver_update',
        'data': {
          'event_id': widget.eventId,
          'stop_index': _currentStopIndex,
        },
        'read': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error notifying organizer: $e');
    }
  }

  Future<void> _startEvent() async {
    HapticService.success();

    try {
      await _eventService.startEvent(widget.eventId);
      await _loadEventData();

      // Notify organizer
      final organizerId = _event?['organizer_id'] as String?;
      final eventTitle = _event?['event_name'] ?? _event?['title'] ?? 'tourism_event'.tr();
      if (organizerId != null) {
        _notifyOrganizer(
          organizerId,
          'tourism_event_started_title'.tr(),
          'tourism_driver_started_event'.tr(namedArgs: {'event': eventTitle}),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('tourism_event_started'.tr()),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('tourism_error_start'.tr(namedArgs: {'error': '$e'})),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _completeEvent() async {
    HapticService.success();

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'tourism_finalize_event'.tr(),
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'tourism_finalize_event_confirm'.tr(),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('tourism_cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
            ),
            child: Text('tourism_finalize_event'.tr()),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Complete the event
      await _eventService.completeEvent(widget.eventId);
      if (!mounted) return;

      // Deactivate tourism mode for this driver
      final driverProvider = Provider.of<DriverProvider>(context, listen: false);
      final driver = driverProvider.driver;
      if (driver != null) {
        await Supabase.instance.client.from('drivers').update({
          'vehicle_mode': 'personal',
          'active_tourism_event_id': null,
          'tourism_enabled': false,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', driver.id);

        // Stop GPS tracking
        _positionSubscription?.cancel();
        _locationUpdateTimer?.cancel();

        // Refresh driver data
        await driverProvider.initialize(driver.id);
      }

      await _loadEventData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('tourism_event_completed_returning'.tr()),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
        // Navigate back to home - AuthWrapper will redirect to normal home
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('tourism_error_completing'.tr(namedArgs: {'error': '$e'})),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _callOrganizer() {
    final phone = _event?['organizers']?['phone'] as String?;
    if (phone != null && phone.isNotEmpty) {
      HapticService.lightImpact();
      launchUrlString('tel:$phone');
    }
  }

  void _messageOrganizer() {
    final phone = _event?['organizers']?['phone'] as String?;
    if (phone != null && phone.isNotEmpty) {
      HapticService.lightImpact();
      launchUrlString('sms:$phone');
    }
  }

  Future<void> _markStopDeparture() async {
    if (_itinerary.isEmpty) return;

    HapticService.success();

    // Check for missing passengers before allowing departure
    await _checkMissingPassengers();

    try {
      final currentStop = _itinerary[_currentStopIndex];
      final stopName = currentStop['name'] ?? 'tourism_stop_label'.tr(namedArgs: {'number': '${_currentStopIndex + 1}'});

      // Create bus event for departure
      await _createBusEvent('stop_departure', stopName);

      // Update event current stop index if this is not the last stop
      if (_currentStopIndex < _itinerary.length - 1) {
        await Supabase.instance.client.from('tourism_events').update({
          'current_stop_index': _currentStopIndex + 1,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', widget.eventId);
      }

      await _loadEventData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('tourism_departure_registered'.tr(namedArgs: {'stop': stopName})),
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
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _createBusEvent(String eventType, String stopName) async {
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    final driverId = driverProvider.driver?.id;
    if (driverId == null || _currentPosition == null) return;

    try {
      await Supabase.instance.client.from('bus_events').insert({
        'route_id': widget.eventId,
        'driver_id': driverId,
        'event_type': eventType,
        'stop_name': stopName,
        'lat': _currentPosition!.latitude,
        'lng': _currentPosition!.longitude,
        'passengers_on_board': _stats['checked_in'] ?? 0,
        'metadata': {'stop_index': _currentStopIndex},
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      debugPrint('BUS_EVENT -> Created $eventType event for $stopName');
    } catch (e) {
      debugPrint('BUS_EVENT -> Error creating event: $e');
    }
  }

  Future<void> _checkMissingPassengers() async {
    try {
      // Get all confirmed invitations (accepted + boarded + checked_in)
      final invitations = await Supabase.instance.client
          .from('tourism_invitations')
          .select()
          .eq('event_id', widget.eventId)
          .inFilter('status', ['accepted', 'boarded', 'checked_in']);

      final totalAccepted = invitations.length;
      final checkedIn = (_stats['checked_in'] ?? 0) + (_stats['boarded'] ?? 0);
      final missing = totalAccepted - checkedIn;

      if (missing > 0 && mounted) {
        // Show warning dialog
        final organizerName = _event?['organizers']?['company_name'] ?? 'tourism_organizer'.tr();

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 28),
                const SizedBox(width: 12),
                Text(
                  'tourism_missing_passengers_title'.tr(),
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 18),
                ),
              ],
            ),
            content: Text(
              'tourism_missing_passengers_body'.tr(namedArgs: {'count': '$missing', 'organizer': organizerName}),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('tourism_view_passengers'.tr()),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                ),
                child: Text('tourism_continue_anyway'.tr()),
              ),
            ],
          ),
        );

        // Send notification to organizer
        final organizerId = _event?['organizer_id'];
        if (organizerId != null) {
          await _sendOrganizerNotification(
            organizerId,
            'tourism_missing_passengers_title'.tr(),
            'tourism_missing_passengers_notification'.tr(namedArgs: {'count': '$missing'}),
          );
        }
      }
    } catch (e) {
      debugPrint('ERROR checking missing passengers: $e');
    }
  }

  Future<void> _sendOrganizerNotification(String organizerId, String title, String body) async {
    try {
      await Supabase.instance.client.from('notifications').insert({
        'user_id': organizerId,
        'title': title,
        'body': body,
        'type': 'tourism_warning',
        'data': {
          'event_id': widget.eventId,
          'stop_index': _currentStopIndex,
        },
        'read': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('ERROR sending organizer notification: $e');
    }
  }

  void _navigateToPassengers() {
    HapticService.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TourismPassengerListScreen(eventId: widget.eventId),
      ),
    ).then((_) => _loadEventData());
  }

  void _navigateToItinerary() {
    HapticService.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrganizerItineraryScreen(eventId: widget.eventId),
      ),
    );
  }

  void _navigateToChat() {
    HapticService.lightImpact();

    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    final driver = driverProvider.driver;

    if (driver == null) return;

    // Reset unread badge
    setState(() => _chatUnreadCount = 0);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TourismChatScreen(
          eventId: widget.eventId,
          userRole: 'driver',
          userId: driver.id,
          userName: driver.name,
          userAvatarUrl: driver.profileImageUrl,
        ),
      ),
    );
  }

  void _navigateToJoinRequests() {
    HapticService.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JoinRequestsScreen(
          eventId: widget.eventId,
          eventTitle: _event?['title'] as String?,
          pricePerKm: (_event?['price_per_km'] as num?)?.toDouble(),
        ),
      ),
    ).then((_) {
      // Refresh counts when returning from join requests screen
      _loadEventData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.surface,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : SafeArea(
                child: Column(
                  children: [
                    _buildHeader(),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            _buildEventInfo(),
                            _buildCurrentStop(),
                            _buildControlButton(),
                          ],
                        ),
                      ),
                    ),
                    _buildBottomNav(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border.withOpacity(0.5)),
        ),
      ),
      child: Row(
        children: [
          // Back button
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () {
              HapticService.lightImpact();
              Navigator.pop(context);
            },
          ),
          const SizedBox(width: 8),
          // Title
          Expanded(
            child: Text(
              'tourism_mode'.tr(),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // GPS indicator with toggle
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _isGpsActive
                          ? AppColors.error.withOpacity(_pulseAnimation.value * 0.3)
                          : AppColors.textTertiary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _isGpsActive
                            ? AppColors.error.withOpacity(_pulseAnimation.value)
                            : AppColors.textTertiary.withOpacity(0.5),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isGpsActive ? AppColors.error : AppColors.textTertiary,
                            boxShadow: _isGpsActive
                                ? [
                                    BoxShadow(
                                      color: AppColors.error.withOpacity(0.5),
                                      blurRadius: 4,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isGpsActive ? 'GPS En Vivo' : 'GPS Apagado',
                          style: TextStyle(
                            color: _isGpsActive ? AppColors.error : AppColors.textTertiary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () {
                  HapticService.lightImpact();
                  if (_isGpsActive) {
                    _positionSubscription?.cancel();
                    _locationUpdateTimer?.cancel();
                    setState(() => _isGpsActive = false);
                  } else {
                    _startGpsTracking();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (_isGpsActive ? AppColors.error : AppColors.success).withOpacity(0.15),
                  ),
                  child: Icon(
                    _isGpsActive ? Icons.gps_off : Icons.gps_fixed,
                    size: 16,
                    color: _isGpsActive ? AppColors.error : AppColors.success,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEventInfo() {
    final title = _event?['title'] ?? 'tourism_event'.tr();
    final organizer = _event?['organizers'] as Map<String, dynamic>?;
    final organizerName = organizer?['contact_name'] ??
        organizer?['business_name'] ??
        organizer?['company_name'] ??
        'tourism_organizer'.tr();
    final phone = organizer?['phone'] as String?;
    final organizerLogo = organizer?['company_logo_url'] as String?;
    final organizerEmail = organizer?['contact_email'] as String?;
    final organizerContactPhone = organizer?['contact_phone'] as String?;
    final organizerFacebook = organizer?['contact_facebook'] as String?;
    final startDate = _event?['event_date'] != null
        ? DateTime.tryParse(_event!['event_date'])
        : null;
    final startTime = _event?['start_time'] as String? ?? '8:00 AM';
    final endTime = _event?['end_time'] as String? ?? '6:00 PM';

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Organizer business banner ──
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                // Organizer logo
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: AppColors.surface,
                    image: organizerLogo != null
                        ? DecorationImage(
                            image: NetworkImage(organizerLogo),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: organizerLogo == null
                      ? Icon(Icons.business, color: AppColors.textTertiary, size: 24)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        organizerName,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 6,
                        runSpacing: 3,
                        children: [
                          if (organizerContactPhone != null && organizerContactPhone.isNotEmpty)
                            _buildOrgChip(Icons.phone, organizerContactPhone),
                          if (organizerEmail != null && organizerEmail.isNotEmpty)
                            _buildOrgChip(Icons.email, organizerEmail),
                          if (organizerFacebook != null && organizerFacebook.isNotEmpty)
                            _buildOrgChip(Icons.facebook, 'Facebook'),
                        ],
                      ),
                    ],
                  ),
                ),
                // Call button
                if (phone != null && phone.isNotEmpty)
                  GestureDetector(
                    onTap: _callOrganizer,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.phone, color: AppColors.primary, size: 18),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Event title
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          // Date and time row
          Row(
            children: [
              Icon(Icons.calendar_today, color: AppColors.textTertiary, size: 14),
              const SizedBox(width: 6),
              Text(
                startDate != null
                    ? '${startDate.day} ${_getMonthName(startDate.month)} ${startDate.year}'
                    : 'tourism_date_not_set'.tr(),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 16),
              Icon(Icons.access_time, color: AppColors.textTertiary, size: 14),
              const SizedBox(width: 6),
              Text(
                '$startTime - $endTime',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrgChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: AppColors.primary),
          const SizedBox(width: 3),
          Text(
            text,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _getMonthName(int month) {
    final months = [
      'tourism_month_jan'.tr(), 'tourism_month_feb'.tr(), 'tourism_month_mar'.tr(),
      'tourism_month_apr'.tr(), 'tourism_month_may'.tr(), 'tourism_month_jun'.tr(),
      'tourism_month_jul'.tr(), 'tourism_month_aug'.tr(), 'tourism_month_sep'.tr(),
      'tourism_month_oct'.tr(), 'tourism_month_nov'.tr(), 'tourism_month_dec'.tr()
    ];
    return months[month - 1];
  }

  Widget _buildCompactKPIs() {
    final accepted = _stats['accepted'] as int? ?? 0;
    final boarded = _stats['checked_in'] as int? ?? 0;
    final total = accepted + boarded;
    final missing = accepted;

    return Row(
      children: [
        _buildCompactKPI(Icons.people, '$total', 'Total', AppColors.textSecondary),
        const SizedBox(width: 12),
        _buildCompactKPI(Icons.how_to_reg, '$boarded', 'Aboard', AppColors.success),
        const SizedBox(width: 12),
        _buildCompactKPI(Icons.person_off, '$missing', 'Missing', missing > 0 ? AppColors.warning : AppColors.success),
      ],
    );
  }

  Widget _buildCompactKPI(IconData icon, String value, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 2),
        Text(
          label,
          style: TextStyle(color: color.withOpacity(0.7), fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildMapSection() {
    // Calculate center and bounds from itinerary
    LatLng center = const LatLng(33.4484, -112.0740); // Default Phoenix
    double zoom = 10;

    if (_currentPosition != null) {
      center = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      zoom = 13;
    } else if (_itinerary.isNotEmpty) {
      final firstStop = _itinerary.first;
      final lat = (firstStop['lat'] as num?)?.toDouble();
      final lng = (firstStop['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        center = LatLng(lat, lng);
        zoom = 11;
      }
    }

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: zoom,
            ),
            children: [
              // CartoDB dark tiles
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.toro.driver',
              ),
              // Route polyline
              if (_itinerary.length >= 2) _buildRoutePolyline(),
              // Stop markers
              MarkerLayer(markers: _buildStopMarkers()),
              // Current position marker
              if (_currentPosition != null)
                MarkerLayer(markers: [_buildCurrentLocationMarker()]),
            ],
          ),
          // Center on location button
          Positioned(
            bottom: 16,
            right: 16,
            child: GestureDetector(
              onTap: () {
                HapticService.lightImpact();
                if (_currentPosition != null) {
                  _mapController.move(
                    LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                    14,
                  );
                }
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.my_location,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoutePolyline() {
    final points = <LatLng>[];

    for (final stop in _itinerary) {
      final lat = (stop['lat'] as num?)?.toDouble();
      final lng = (stop['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        points.add(LatLng(lat, lng));
      }
    }

    return PolylineLayer(
      polylines: [
        Polyline(
          points: points,
          strokeWidth: 4,
          color: AppColors.primary.withOpacity(0.8),
          isDotted: false,
        ),
      ],
    );
  }

  List<Marker> _buildStopMarkers() {
    final markers = <Marker>[];

    for (int i = 0; i < _itinerary.length; i++) {
      final stop = _itinerary[i];
      final lat = (stop['lat'] as num?)?.toDouble();
      final lng = (stop['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      final isCurrentStop = i == _currentStopIndex;
      final isCompleted = stop['arrived_at'] != null;

      markers.add(
        Marker(
          point: LatLng(lat, lng),
          width: isCurrentStop ? 50 : 40,
          height: isCurrentStop ? 50 : 40,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted
                  ? AppColors.success
                  : (isCurrentStop ? AppColors.primary : AppColors.card),
              border: Border.all(
                color: isCurrentStop ? AppColors.primary : AppColors.border,
                width: isCurrentStop ? 3 : 2,
              ),
              boxShadow: isCurrentStop
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.5),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: isCompleted
                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                  : Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: isCurrentStop
                            ? Colors.white
                            : AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
            ),
          ),
        ),
      );
    }

    return markers;
  }

  Marker _buildCurrentLocationMarker() {
    return Marker(
      point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      width: 48,
      height: 48,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primary,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.5),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Icon(
          Icons.directions_bus,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }

  void _showEditStopDialog(int stopIndex) {
    if (stopIndex < 0 || stopIndex >= _itinerary.length) return;
    final stop = Map<String, dynamic>.from(_itinerary[stopIndex]);
    final nameController = TextEditingController(text: stop['name'] as String? ?? '');
    final addressController = TextEditingController(text: stop['address'] as String? ?? '');
    final durationController = TextEditingController(
      text: (stop['duration_minutes'] ?? stop['durationMinutes'] ?? 0).toString(),
    );
    double? selectedLat = (stop['lat'] as num?)?.toDouble();
    double? selectedLng = (stop['lng'] as num?)?.toDouble();
    List<Map<String, dynamic>> suggestions = [];
    List<Map<String, dynamic>> savedLocations = [];
    Timer? debounce;
    bool isSaving = false;
    TimeOfDay? selectedTime;

    // Load saved frequent locations
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getString('driver_saved_locations');
      if (saved != null && saved.isNotEmpty) {
        try {
          savedLocations = List<Map<String, dynamic>>.from(
            (json.decode(saved) as List).map((e) => Map<String, dynamic>.from(e)),
          );
        } catch (_) {}
      }
    });

    final scheduledStr = stop['scheduled_time'] as String?;
    if (scheduledStr != null) {
      final dt = DateTime.tryParse(scheduledStr);
      if (dt != null) selectedTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
    }

    final isOrigin = stopIndex == 0;
    final isDestination = _itinerary.length > 1 && stopIndex == _itinerary.length - 1;
    final label = isOrigin ? 'tourism_origin'.tr() : isDestination ? 'tourism_final_destination'.tr() : 'tourism_stop_label'.tr(namedArgs: {'number': '${stopIndex + 1}'});

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
                        Text('tourism_edit_label'.tr(namedArgs: {'label': label}),
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
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
                        hintText: 'tourism_stop_name_hint'.tr(),
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
                    const Text('Dirección', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: addressController,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                            decoration: InputDecoration(
                              hintText: 'Buscar dirección o negocio...',
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
                        ),
                        const SizedBox(width: 8),
                        // Map pin button
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: () async {
                              final result = await showDialog<Map<String, dynamic>>(
                                context: context,
                                builder: (ctx) => _HomeMapPicker(
                                  initialLocation: selectedLat != null && selectedLng != null
                                      ? LatLng(selectedLat!, selectedLng!)
                                      : null,
                                ),
                              );
                              if (result != null) {
                                setModalState(() {
                                  selectedLat = result['coords']['lat'] as double;
                                  selectedLng = result['coords']['lng'] as double;
                                  addressController.text = result['address'] as String? ?? '';
                                  suggestions = [];
                                });
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Icon(Icons.pin_drop, color: Colors.white, size: 20),
                          ),
                        ),
                      ],
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
                              title: Text(s['text'] as String,
                                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                              subtitle: Text(s['place_name'] as String,
                                style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                              onTap: () {
                                setModalState(() {
                                  addressController.text = s['place_name'] as String;
                                  selectedLat = s['lat'] as double;
                                  selectedLng = s['lng'] as double;
                                  if (nameController.text.isEmpty) nameController.text = s['text'] as String;
                                  suggestions = [];
                                });
                                HapticService.lightImpact();
                              },
                            );
                          },
                        ),
                      ),
                    // Saved / Frequent locations
                    if (savedLocations.isNotEmpty && suggestions.isEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.history, color: AppColors.textTertiary, size: 14),
                              const SizedBox(width: 6),
                              const Text('Lugares frecuentes', style: TextStyle(color: AppColors.textTertiary, fontSize: 11, fontWeight: FontWeight.w600)),
                              const Spacer(),
                              GestureDetector(
                                onTap: () async {
                                  final prefs = await SharedPreferences.getInstance();
                                  await prefs.remove('driver_saved_locations');
                                  setModalState(() => savedLocations = []);
                                  HapticService.lightImpact();
                                },
                                child: const Text('Borrar', style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 36,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: savedLocations.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 8),
                              itemBuilder: (context, index) {
                                final loc = savedLocations[index];
                                return GestureDetector(
                                  onTap: () {
                                    setModalState(() {
                                      nameController.text = loc['name'] as String? ?? '';
                                      addressController.text = loc['address'] as String? ?? '';
                                      selectedLat = (loc['lat'] as num?)?.toDouble();
                                      selectedLng = (loc['lng'] as num?)?.toDouble();
                                      suggestions = [];
                                    });
                                    HapticService.lightImpact();
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(color: AppColors.border),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.place, color: AppColors.primary, size: 14),
                                        const SizedBox(width: 4),
                                        Text(
                                          loc['name'] as String? ?? (loc['address'] as String? ?? '').split(',').first,
                                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500),
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
                                  final picked = await showScrollableTimePicker(
                                    context,
                                    selectedTime ?? TimeOfDay.now(),
                                    primaryColor: AppColors.primary,
                                  );
                                  if (picked != null) setModalState(() => selectedTime = picked);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: Row(children: [
                                    const Icon(Icons.schedule, color: AppColors.primary, size: 18),
                                    const SizedBox(width: 8),
                                    Text(
                                      selectedTime != null ? selectedTime!.format(context) : 'tourism_no_time'.tr(),
                                      style: TextStyle(color: selectedTime != null ? AppColors.textPrimary : AppColors.textTertiary, fontSize: 14),
                                    ),
                                  ]),
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
                                style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                                decoration: InputDecoration(
                                  filled: true, fillColor: AppColors.surface,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  prefixIcon: const Icon(Icons.timer, color: AppColors.primary, size: 18),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Save button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: isSaving ? null : () async {
                          setModalState(() => isSaving = true);
                          try {
                            // Update stop in itinerary
                            final updatedStop = Map<String, dynamic>.from(_itinerary[stopIndex]);
                            updatedStop['name'] = nameController.text.trim();
                            if (addressController.text.trim().isNotEmpty) {
                              updatedStop['address'] = addressController.text.trim();
                            }
                            if (selectedLat != null) updatedStop['lat'] = selectedLat;
                            if (selectedLng != null) updatedStop['lng'] = selectedLng;
                            updatedStop['duration_minutes'] = int.tryParse(durationController.text) ?? 0;
                            if (selectedTime != null) {
                              final eventDate = _event?['event_date'] as String?;
                              final baseDate = eventDate != null ? DateTime.tryParse(eventDate) : DateTime.now();
                              final dt = DateTime(baseDate!.year, baseDate.month, baseDate.day, selectedTime!.hour, selectedTime!.minute);
                              updatedStop['scheduled_time'] = dt.toIso8601String();
                            }

                            // Update local state
                            final newItinerary = List<Map<String, dynamic>>.from(_itinerary);
                            newItinerary[stopIndex] = updatedStop;

                            // Save to JSONB on tourism_events (source of truth, RLS allows driver)
                            await Supabase.instance.client
                                .from('tourism_events')
                                .update({
                                  'itinerary': newItinerary,
                                  'updated_at': DateTime.now().toUtc().toIso8601String(),
                                })
                                .eq('id', widget.eventId);

                            // Also try normalized table (may fail due to RLS, that's ok)
                            try {
                              await Supabase.instance.client
                                  .from('tourism_event_itinerary')
                                  .update({
                                    'name': updatedStop['name'],
                                    'address': updatedStop['address'],
                                    'lat': updatedStop['lat'],
                                    'lng': updatedStop['lng'],
                                    'duration_minutes': updatedStop['duration_minutes'],
                                    'scheduled_time': updatedStop['scheduled_time'],
                                  })
                                  .eq('id', updatedStop['id']);
                            } catch (_) {}

                            setState(() {
                              _itinerary = newItinerary;
                            });

                            // If coordinates changed, recalculate total distance + pricing
                            if (selectedLat != null && selectedLng != null) {
                              await _recalculateDistanceAndPricing(newItinerary);
                            }

                            // Save to frequent locations
                            if (selectedLat != null && selectedLng != null && addressController.text.trim().isNotEmpty) {
                              try {
                                final prefs = await SharedPreferences.getInstance();
                                final existing = prefs.getString('driver_saved_locations');
                                final List<Map<String, dynamic>> locations = existing != null && existing.isNotEmpty
                                    ? List<Map<String, dynamic>>.from(
                                        (json.decode(existing) as List).map((e) => Map<String, dynamic>.from(e)))
                                    : [];
                                // Remove duplicate by address
                                locations.removeWhere((l) => l['address'] == addressController.text.trim());
                                // Add at front
                                locations.insert(0, {
                                  'name': nameController.text.trim(),
                                  'address': addressController.text.trim(),
                                  'lat': selectedLat,
                                  'lng': selectedLng,
                                });
                                // Keep max 10
                                if (locations.length > 10) locations.removeLast();
                                await prefs.setString('driver_saved_locations', json.encode(locations));
                              } catch (_) {}
                            }

                            if (mounted) Navigator.pop(context);
                            HapticService.success();
                            _loadEventData();
                          } catch (e) {
                            setModalState(() => isSaving = false);
                            debugPrint('ERROR editing stop: $e');
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
                              );
                            }
                          }
                        },
                        icon: isSaving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save, size: 18),
                        label: Text(isSaving ? 'saving'.tr() : 'save_changes'.tr()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _addNewStop() {
    HapticService.lightImpact();
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    double? selectedLat;
    double? selectedLng;
    List<Map<String, dynamic>> suggestions = [];
    Timer? debounce;
    bool isSaving = false;

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
                        const Text('Nueva parada',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text('Nombre', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'Ej: Compostela Centro',
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
                    const Text('Dirección', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
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
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: () async {
                              final result = await showDialog<Map<String, dynamic>>(
                                context: context,
                                builder: (ctx) => _HomeMapPicker(
                                  initialLocation: selectedLat != null && selectedLng != null
                                      ? LatLng(selectedLat!, selectedLng!)
                                      : null,
                                ),
                              );
                              if (result != null) {
                                setModalState(() {
                                  selectedLat = result['coords']['lat'] as double;
                                  selectedLng = result['coords']['lng'] as double;
                                  addressController.text = result['address'] as String? ?? '';
                                  suggestions = [];
                                });
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Icon(Icons.pin_drop, color: Colors.white, size: 20),
                          ),
                        ),
                      ],
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
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: suggestions.length,
                          separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.border.withValues(alpha: 0.3)),
                          itemBuilder: (context, index) {
                            final s = suggestions[index];
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.location_on, color: AppColors.primary, size: 18),
                              title: Text(s['text'] as String,
                                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                              subtitle: Text(s['place_name'] as String,
                                style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                              onTap: () {
                                setModalState(() {
                                  addressController.text = s['place_name'] as String;
                                  selectedLat = s['lat'] as double;
                                  selectedLng = s['lng'] as double;
                                  if (nameController.text.isEmpty) nameController.text = s['text'] as String;
                                  suggestions = [];
                                });
                                HapticService.lightImpact();
                              },
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: (isSaving || nameController.text.trim().isEmpty || selectedLat == null) ? null : () async {
                          setModalState(() => isSaving = true);
                          try {
                            final newOrder = _itinerary.length;
                            final newStop = {
                              'name': nameController.text.trim(),
                              'address': addressController.text.trim(),
                              'lat': selectedLat,
                              'lng': selectedLng,
                              'stop_order': newOrder,
                              'duration_minutes': 0,
                              'event_id': widget.eventId,
                            };

                            // Update JSONB on tourism_events (source of truth, RLS allows driver)
                            final newItinerary = List<Map<String, dynamic>>.from(_itinerary);
                            newItinerary.add(newStop);

                            await Supabase.instance.client
                                .from('tourism_events')
                                .update({
                                  'itinerary': newItinerary,
                                  'updated_at': DateTime.now().toUtc().toIso8601String(),
                                })
                                .eq('id', widget.eventId);

                            // Also try normalized table (may fail due to RLS)
                            try {
                              await Supabase.instance.client
                                  .from('tourism_event_itinerary')
                                  .insert(newStop);
                            } catch (_) {}

                            setState(() {
                              _itinerary = newItinerary;
                            });

                            if (mounted) Navigator.pop(context);
                            HapticService.success();
                            // Reload to sync with DB
                            _loadEventData();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Parada "${nameController.text.trim()}" agregada'),
                                  backgroundColor: AppColors.success,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } catch (e) {
                            setModalState(() => isSaving = false);
                            debugPrint('ERROR adding stop: $e');
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
                              );
                            }
                          }
                        },
                        icon: isSaving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.add, size: 18),
                        label: Text(isSaving ? 'Guardando...' : 'Agregar parada'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.success.withOpacity(0.3),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDeleteStop(int stopIndex) {
    if (stopIndex < 0 || stopIndex >= _itinerary.length) return;
    final stop = _itinerary[stopIndex];
    final stopName = stop['name'] as String? ?? 'Parada ${stopIndex + 1}';

    HapticService.lightImpact();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Eliminar parada', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          '¿Eliminar "$stopName"? Esta acción se compartirá con todos los dispositivos conectados.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.textTertiary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                // Update JSONB on tourism_events (source of truth)
                final newItinerary = List<Map<String, dynamic>>.from(_itinerary);
                newItinerary.removeAt(stopIndex);
                // Re-order stops
                for (int i = 0; i < newItinerary.length; i++) {
                  newItinerary[i]['stop_order'] = i;
                }

                await Supabase.instance.client
                    .from('tourism_events')
                    .update({
                      'itinerary': newItinerary,
                      'updated_at': DateTime.now().toUtc().toIso8601String(),
                    })
                    .eq('id', widget.eventId);

                // Also try normalized table (may fail due to RLS)
                try {
                  final stopId = stop['id'];
                  if (stopId != null) {
                    await Supabase.instance.client
                        .from('tourism_event_itinerary')
                        .delete()
                        .eq('id', stopId);
                  }
                } catch (_) {}

                setState(() {
                  _itinerary = newItinerary;
                  if (_currentStopIndex >= _itinerary.length) {
                    _currentStopIndex = _itinerary.length - 1;
                  }
                });
                HapticService.success();
                _loadEventData();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
                  );
                }
              }
            },
            child: const Text('Eliminar', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
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

  Widget _buildCurrentStop() {
    if (_itinerary.isEmpty) {
      return const SizedBox.shrink();
    }

    final currentStop = _currentStopIndex < _itinerary.length
        ? _itinerary[_currentStopIndex]
        : _itinerary.last;

    final stopName = currentStop['name'] ?? 'tourism_stop_label'.tr(namedArgs: {'number': '${_currentStopIndex + 1}'});
    final stopAddress = currentStop['address'] as String?;
    final stopLat = (currentStop['lat'] as num?)?.toDouble();
    final stopLng = (currentStop['lng'] as num?)?.toDouble();
    final scheduledArrival = currentStop['scheduled_time'] as String? ?? '--:--';
    final scheduledDeparture = currentStop['departure_time'] as String? ?? '--:--';
    final hasArrived = currentStop['arrived_at'] != null;

    // Calculate next stop info
    String? nextStopName;
    String? nextStopAddress;
    double? nextStopLat;
    double? nextStopLng;
    if (_currentStopIndex + 1 < _itinerary.length) {
      final nextStop = _itinerary[_currentStopIndex + 1];
      nextStopName = nextStop['name'] ?? 'tourism_next_stop'.tr();
      nextStopAddress = nextStop['address'] as String?;
      nextStopLat = (nextStop['lat'] as num?)?.toDouble();
      nextStopLng = (nextStop['lng'] as num?)?.toDouble();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text(
                'tourism_current_stop'.tr(),
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'tourism_stop_count'.tr(namedArgs: {'current': '${_currentStopIndex + 1}', 'total': '${_itinerary.length}'}),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          // Compact KPIs row
          _buildCompactKPIs(),
          const SizedBox(height: 8),
          // Stop name
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasArrived ? AppColors.success : AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  stopName,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _showEditStopDialog(_currentStopIndex),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.edit, color: AppColors.primary, size: 16),
                ),
              ),
            ],
          ),
          // Address of current stop
          if (stopAddress != null && stopAddress.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(width: 22),
                const Icon(Icons.place, size: 14, color: AppColors.textTertiary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    stopAddress,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          // Times
          Text(
            'tourism_arrival_departure'.tr(namedArgs: {'arrival': scheduledArrival, 'departure': scheduledDeparture}),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          // Navigation + Mark arrival row
          Row(
            children: [
              // Navigate button (opens Google Maps / Waze)
              if (stopLat != null && stopLng != null && !hasArrived)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _openNavigation(stopLat, stopLng, stopName),
                    icon: const Icon(Icons.navigation, size: 18),
                    label: Text('tourism_navigate'.tr()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              if (stopLat != null && stopLng != null && !hasArrived)
                const SizedBox(width: 8),
              // Mark arrival button (only if not arrived)
              if (!hasArrived)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _markStopArrived,
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: Text('tourism_mark_arrival'.tr()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // Next stop info
          if (nextStopName != null) ...[
            const SizedBox(height: 12),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.arrow_forward, color: AppColors.textTertiary, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'tourism_next'.tr(namedArgs: {'name': nextStopName}),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (nextStopAddress != null && nextStopAddress.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            nextStopAddress,
                            style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                // Edit next stop button
                GestureDetector(
                  onTap: () => _showEditStopDialog(_currentStopIndex + 1),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.edit, color: AppColors.primary, size: 16),
                  ),
                ),
                // Navigate to next stop button
                if (nextStopLat != null && nextStopLng != null)
                  GestureDetector(
                    onTap: () => _openNavigation(nextStopLat!, nextStopLng!, nextStopName!),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.info.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.navigation, color: AppColors.info, size: 16),
                    ),
                  ),
              ],
            ),
            // Add/Remove stops
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: _addNewStop,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.success.withOpacity(0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_location_alt, color: AppColors.success, size: 14),
                        SizedBox(width: 4),
                        Text('Agregar parada', style: TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (_itinerary.length > 2)
                  GestureDetector(
                    onTap: () => _confirmDeleteStop(_currentStopIndex + 1 < _itinerary.length ? _currentStopIndex + 1 : _currentStopIndex),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.error.withOpacity(0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.remove_circle_outline, color: AppColors.error, size: 14),
                          SizedBox(width: 4),
                          Text('Quitar parada', style: TextStyle(color: AppColors.error, fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Opens external navigation app (Google Maps) to the given coordinates.
  void _openNavigation(double lat, double lng, String label) async {
    HapticService.lightImpact();
    final encodedLabel = Uri.encodeComponent(label);
    final googleMapsUrl = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&destination_place_id=&travelmode=driving';
    try {
      await launchUrlString(googleMapsUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      // Fallback to geo: URI
      final geoUrl = 'geo:$lat,$lng?q=$lat,$lng($encodedLabel)';
      try {
        await launchUrlString(geoUrl, mode: LaunchMode.externalApplication);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('tourism_error_open_navigation'.tr()),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Widget _buildControlButton() {
    final status = _event?['status'] as String? ?? '';

    if (status == 'vehicle_accepted') {
      return Container(
        margin: const EdgeInsets.all(12),
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _startEvent,
          icon: const Icon(Icons.play_arrow, size: 24),
          label: Text(
            'tourism_start_event'.tr(),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
        ),
      );
    } else if (status == 'in_progress') {
      return Container(
        margin: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Primary: Open Live Trip Panel
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  HapticService.mediumImpact();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LiveTripPanelScreen(
                        eventId: widget.eventId,
                      ),
                    ),
                  ).then((_) => _loadEventData());
                },
                icon: const Icon(Icons.dashboard, size: 24),
                label: Text(
                  'tourism_live_panel'.tr(),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Secondary: Finish event
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _completeEvent,
                icon: const Icon(Icons.flag, size: 20),
                label: Text(
                  'tourism_finalize_event'.tr(),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning.withOpacity(0.15),
                  foregroundColor: AppColors.warning,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: AppColors.warning.withOpacity(0.3),
                    ),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.border.withOpacity(0.5)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildNavItem(
              icon: Icons.people,
              label: 'tourism_passengers'.tr(),
              onTap: _navigateToPassengers,
            ),
            _buildNavItemWithBadge(
              icon: Icons.person_add_alt_1,
              label: 'tourism_requests'.tr(),
              badgeCount: _pendingJoinCount,
              onTap: _navigateToJoinRequests,
            ),
            _buildNavItem(
              icon: Icons.list_alt,
              label: 'tourism_itinerary'.tr(),
              onTap: _navigateToItinerary,
            ),
            // Only show chat if organizer hasn't disabled it
            if (_event?['chat_enabled_for_driver'] != false)
              _buildNavItemWithBadge(
                icon: Icons.chat_bubble_outline,
                label: 'tourism_chat'.tr(),
                badgeCount: _chatUnreadCount,
                onTap: _navigateToChat,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItemWithBadge({
    required IconData icon,
    required String label,
    required int badgeCount,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: AppColors.textSecondary, size: 24),
                if (badgeCount > 0)
                  Positioned(
                    top: -6,
                    right: -10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.warning,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(minWidth: 18),
                      child: Text(
                        '$badgeCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: badgeCount > 0
                    ? AppColors.warning
                    : AppColors.textSecondary,
                fontSize: 12,
                fontWeight:
                    badgeCount > 0 ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── MAP PICKER for Home Screen Edit Stop ──────────────────

class _HomeMapPicker extends StatefulWidget {
  final LatLng? initialLocation;

  const _HomeMapPicker({this.initialLocation});

  @override
  State<_HomeMapPicker> createState() => _HomeMapPickerState();
}

class _HomeMapPickerState extends State<_HomeMapPicker> {
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
      setState(() { _suggestions = []; _showSuggestions = false; });
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        final url = Uri.parse(
          'https://nominatim.openstreetmap.org/search'
          '?q=${Uri.encodeComponent(query)}'
          '&format=jsonv2&countrycodes=mx,us&limit=5&addressdetails=1&accept-language=es',
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
      } catch (_) {}
    });
  }

  Future<void> _reverseGeocode(LatLng location) async {
    setState(() => _isLoadingAddress = true);
    try {
      final placemarks = await placemarkFromCoordinates(location.latitude, location.longitude);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        List<String> parts = [];
        if (place.name != null && place.name!.isNotEmpty && place.name != place.street && !RegExp(r'^\d+$').hasMatch(place.name!)) {
          parts.add(place.name!);
        }
        if (place.street != null && place.street!.isNotEmpty) parts.add(place.street!);
        if (place.locality != null && place.locality!.isNotEmpty) parts.add(place.locality!);
        if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) parts.add(place.administrativeArea!);

        if (mounted) {
          setState(() {
            _addressText = parts.isNotEmpty ? parts.join(', ') : '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}';
            _isLoadingAddress = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _addressText = '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}';
          _isLoadingAddress = false;
        });
      }
    }
  }

  Future<void> _goToCurrentLocation() async {
    setState(() => _isLoadingGPS = true);
    try {
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) { setState(() => _isLoadingGPS = false); return; }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) { setState(() => _isLoadingGPS = false); return; }
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 15));
      final loc = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      _mapController.move(loc, 16);
      setState(() { _currentCenter = loc; _isLoadingGPS = false; });
      _reverseGeocode(loc);
    } catch (_) {
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
          leading: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
          title: const Text('Seleccionar Ubicación', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          centerTitle: true,
        ),
        body: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentCenter,
                initialZoom: 15,
                onPositionChanged: (position, hasGesture) {
                  if (hasGesture && !_isDragging) setState(() => _isDragging = true);
                  if (!hasGesture && _isDragging) {
                    setState(() { _isDragging = false; _currentCenter = _mapController.camera.center; });
                    _reverseGeocode(_mapController.camera.center);
                  }
                },
              ),
              children: [
                TileLayer(urlTemplate: 'https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png', userAgentPackageName: 'com.toro.driver'),
              ],
            ),
            // Search bar
            Positioned(
              top: 16, left: 16, right: 80,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))]),
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(fontSize: 14, color: Colors.white),
                      decoration: const InputDecoration(hintText: 'Buscar dirección o negocio...', hintStyle: TextStyle(color: Color(0xFF888888)), prefixIcon: Icon(Icons.search, color: Color(0xFFAAAAAA), size: 20), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                      onChanged: _fetchSuggestions,
                    ),
                  ),
                  if (_showSuggestions && _suggestions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 12)]),
                      constraints: const BoxConstraints(maxHeight: 250),
                      child: ListView.separated(
                        shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _suggestions.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: Colors.white.withOpacity(0.1), indent: 16, endIndent: 16),
                        itemBuilder: (context, index) {
                          final s = _suggestions[index];
                          return InkWell(
                            onTap: () {
                              final loc = LatLng(s['lat'] as double, s['lng'] as double);
                              _mapController.move(loc, 16);
                              setState(() { _currentCenter = loc; _showSuggestions = false; _searchController.text = s['text'] as String; });
                              _reverseGeocode(loc);
                              FocusScope.of(context).unfocus();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(children: [
                                const Icon(Icons.location_on, color: Colors.orange, size: 20),
                                const SizedBox(width: 12),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(s['text'] as String, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                                  const SizedBox(height: 2),
                                  Text(s['place_name'] as String, style: const TextStyle(color: Color(0xFF888888), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                                ])),
                              ]),
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
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))]),
                    child: const Icon(Icons.location_on, color: Colors.white, size: 28),
                  ),
                  Container(width: 12, height: 4, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(2))),
                ]),
              ),
            ),
            // GPS button
            Positioned(
              top: 16, right: 16,
              child: GestureDetector(
                onTap: _isLoadingGPS ? null : _goToCurrentLocation,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFF2A2A2A), shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8)]),
                  child: _isLoadingGPS
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange))
                      : const Icon(Icons.my_location, color: Colors.orange, size: 24),
                ),
              ),
            ),
            // Bottom panel
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: const BorderRadius.vertical(top: Radius.circular(24)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, -5))]),
                child: SafeArea(
                  top: false,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(16)),
                      child: Row(children: [
                        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.red.withOpacity(0.25), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.location_on, color: Colors.red, size: 22)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _isLoadingAddress
                              ? const Row(children: [SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange)), SizedBox(width: 10), Text('Obteniendo dirección...', style: TextStyle(color: Color(0xFF999999), fontSize: 14))])
                              : Text(_addressText, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white), maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context, {
                          'coords': {'lat': _currentCenter.latitude, 'lng': _currentCenter.longitude},
                          'address': _addressText,
                        });
                      },
                      child: Container(
                        width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(gradient: const LinearGradient(colors: [Colors.orange, Color(0xFFFF8C00)]), borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))]),
                        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.check_circle, color: Colors.white, size: 22), SizedBox(width: 10), Text('Confirmar Ubicación', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))]),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
