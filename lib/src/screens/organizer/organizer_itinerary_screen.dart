import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../services/tourism_event_service.dart';
import '../../services/tourism_messaging_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';

/// Live itinerary screen for organizers.
///
/// Displays all stops from the event itinerary with:
/// - Visual timeline with connected dots/lines
/// - Stop details (name, address, scheduled/actual times, duration)
/// - Mark stop as Arrived/Departed buttons
/// - Current stop highlighting
/// - Progress indicator
/// - Notify Passengers button
/// - Real-time updates
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

  // Event data
  Map<String, dynamic>? _event;
  List<Map<String, dynamic>> _itinerary = [];

  // UI State
  bool _isLoading = true;
  String? _error;
  int _currentStopIndex = 0;

  // Real-time subscriptions
  RealtimeChannel? _eventChannel;
  RealtimeChannel? _itineraryChannel;

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
    final client = Supabase.instance.client;
    if (_eventChannel != null) {
      client.removeChannel(_eventChannel!);
      _eventChannel = null;
    }
    if (_itineraryChannel != null) {
      client.removeChannel(_itineraryChannel!);
      _itineraryChannel = null;
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load event with itinerary
      final event = await _eventService.getEvent(widget.eventId);

      if (event != null) {
        _event = event;

        // Extract itinerary: prefer normalized table, fallback to JSONB
        final itineraryData = event['tourism_event_itinerary'] ?? event['itinerary'];
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

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'tourism_error_loading_itinerary'.tr(namedArgs: {'error': '$e'});
        });
      }
    }
  }

  int _findCurrentStopIndex() {
    // Find the first stop that hasn't departed yet
    for (int i = 0; i < _itinerary.length; i++) {
      final stop = _itinerary[i];
      // If hasn't arrived yet, this is the current stop
      if (stop['arrived_at'] == null) {
        return i;
      }
      // If arrived but hasn't departed, this is still the current stop
      if (stop['departed_at'] == null) {
        return i;
      }
    }
    // All stops completed, return last
    return _itinerary.isEmpty ? 0 : _itinerary.length - 1;
  }

  void _subscribeToUpdates() {
    // Subscribe to event updates
    _eventChannel = _eventService.subscribeToEvent(
      widget.eventId,
      (event) {
        if (mounted) {
          setState(() => _event = {...?_event, ...event});
        }
      },
    );

    // Subscribe to itinerary changes via Supabase realtime
    _itineraryChannel = Supabase.instance.client.channel('itinerary_${widget.eventId}');
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
            // Reload data when itinerary changes
            _loadData();
          },
        )
        .subscribe();
  }

  Future<void> _markStopArrived(int stopIndex) async {
    HapticService.mediumImpact();

    try {
      final result = await _eventService.markStopArrived(widget.eventId, stopIndex);

      if (result.isNotEmpty) {
        HapticService.success();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text('tourism_arrival_registered'.tr(namedArgs: {'stop': _itinerary[stopIndex]['name'] ?? 'tourism_stop_label'.tr(namedArgs: {'number': '${stopIndex + 1}'})})),
                ],
              ),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('tourism_error_arrival'.tr(namedArgs: {'error': '$e'})),
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
      // Update the stop with departed time
      final response = await Supabase.instance.client
          .from('tourism_event_itinerary')
          .update({
            'departed_at': DateTime.now().toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('event_id', widget.eventId)
          .eq('stop_order', stopIndex)
          .select()
          .single();

      if (response.isNotEmpty) {
        HapticService.success();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.departure_board, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text('tourism_departure_registered'.tr(namedArgs: {'stop': _itinerary[stopIndex]['name'] ?? 'tourism_stop_label'.tr(namedArgs: {'number': '${stopIndex + 1}'})})),
                ],
              ),
              backgroundColor: AppColors.primary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('tourism_error_departure'.tr(namedArgs: {'error': '$e'})),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _notifyPassengers() async {
    HapticService.lightImpact();

    // Get current stop info
    final currentStop = _currentStopIndex < _itinerary.length
        ? _itinerary[_currentStopIndex]
        : null;

    final stopName = currentStop?['name'] ?? 'tourism_stop_label'.tr(namedArgs: {'number': '${_currentStopIndex + 1}'});

    // Show dialog to enter announcement
    final message = await showDialog<String>(
      context: context,
      builder: (ctx) => _NotifyPassengersDialog(
        defaultMessage: 'tourism_msg_arrived_at'.tr(namedArgs: {'stop': stopName}),
        stopName: stopName,
      ),
    );

    if (message == null || message.isEmpty) return;

    // Send announcement
    if (!mounted) return;
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
            content: Row(
              children: [
                const Icon(Icons.campaign, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text('tourism_announcement_sent'.tr()),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('tourism_error_announcement'.tr(namedArgs: {'error': '$e'})),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _callToBus() async {
    HapticService.heavyImpact();

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final driver = authProvider.driver;

    if (driver == null) return;

    try {
      final success = await _messagingService.sendCallToBus(
        eventId: widget.eventId,
        senderId: driver.id,
        senderType: 'organizer',
        senderName: driver.name,
        senderAvatarUrl: driver.profileImageUrl,
      );

      if (success && mounted) {
        HapticService.success();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.directions_bus, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text('tourism_call_to_bus'.tr()),
              ],
            ),
            backgroundColor: AppColors.warning,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('tourism_error_call_bus'.tr(namedArgs: {'error': '$e'})),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
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
                  child: _buildContent(),
                ),
      floatingActionButton: _buildFloatingActions(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final eventName = _event?['event_name'] ?? 'tourism_itinerary'.tr();
    final completedStops = _itinerary.where((s) => s['departed_at'] != null).length;
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
              'tourism_stop_count'.tr(namedArgs: {'current': '${_currentStopIndex + 1}', 'total': '$totalStops'}),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
      actions: [
        // Progress indicator
        if (totalStops > 0)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: SizedBox(
                width: 40,
                height: 40,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: totalStops > 0 ? completedStops / totalStops : 0,
                      backgroundColor: AppColors.border,
                      color: AppColors.success,
                      strokeWidth: 4,
                    ),
                    Text(
                      '${((completedStops / totalStops) * 100).round()}%',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 10,
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
                size: 48, color: AppColors.error.withValues(alpha: 0.7)),
            const SizedBox(height: 16),
            Text(
              _error ?? 'tourism_error_unknown'.tr(),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadData,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text('tourism_retry'.tr()),
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
        // Progress header card
        _buildProgressHeader(),
        const SizedBox(height: 16),
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
            Icon(
              Icons.route_outlined,
              size: 64,
              color: AppColors.textTertiary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'tourism_no_itinerary'.tr(),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'tourism_no_itinerary_desc'.tr(),
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressHeader() {
    final completedStops = _itinerary.where((s) => s['departed_at'] != null).length;
    final inProgressStops = _itinerary.where((s) =>
        s['arrived_at'] != null && s['departed_at'] == null).length;
    final pendingStops = _itinerary.where((s) => s['arrived_at'] == null).length;
    final totalStops = _itinerary.length;

    // Calculate total duration
    int totalDurationMinutes = 0;
    int elapsedDurationMinutes = 0;

    for (int i = 0; i < _itinerary.length; i++) {
      final duration = (_itinerary[i]['duration_minutes'] as num?)?.toInt() ?? 30;
      totalDurationMinutes += duration;

      if (_itinerary[i]['departed_at'] != null) {
        elapsedDurationMinutes += duration;
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.15),
            AppColors.primary.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          // Title row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.route, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'tourism_itinerary_progress'.tr(),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'tourism_stops_completed'.tr(namedArgs: {'completed': '$completedStops', 'total': '$totalStops'}),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: totalStops > 0 ? completedStops / totalStops : 0,
              backgroundColor: AppColors.border,
              color: AppColors.success,
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 16),
          // Stats row
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  icon: Icons.check_circle,
                  value: '$completedStops',
                  label: 'tourism_completed_stops'.tr(),
                  color: AppColors.success,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  icon: Icons.location_on,
                  value: '$inProgressStops',
                  label: 'tourism_at_stop'.tr(),
                  color: AppColors.warning,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  icon: Icons.schedule,
                  value: '$pendingStops',
                  label: 'tourism_pending_stops'.tr(),
                  color: AppColors.textTertiary,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  icon: Icons.timer,
                  value: '${(totalDurationMinutes / 60).toStringAsFixed(1)}h',
                  label: 'tourism_duration'.tr(),
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 10,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildTimeline() {
    return Column(
      children: List.generate(_itinerary.length, (index) {
        final stop = _itinerary[index];
        final isCurrentStop = index == _currentStopIndex;
        final hasArrived = stop['arrived_at'] != null;
        final hasDeparted = stop['departed_at'] != null;
        final isLastStop = index == _itinerary.length - 1;

        return _buildTimelineItem(
          index: index,
          stop: stop,
          isCurrentStop: isCurrentStop,
          hasArrived: hasArrived,
          hasDeparted: hasDeparted,
          isLastStop: isLastStop,
        );
      }),
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
    final stopName = stop['name'] ?? 'tourism_stop_label'.tr(namedArgs: {'number': '${index + 1}'});
    final address = stop['address'] as String?;
    // Handle both normalized and JSONB field names
    String? scheduledTime = stop['scheduled_time'] as String?;
    scheduledTime ??= stop['arrival_time'] as String?;
    if (scheduledTime == null && stop['estimatedArrival'] != null) {
      final dt = DateTime.tryParse(stop['estimatedArrival']);
      if (dt != null) {
        final local = dt.toLocal();
        scheduledTime = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
      }
    }
    final departureTime = stop['departure_time'] as String?;
    final durationMinutes = (stop['duration_minutes'] as num?)?.toInt() ??
        (stop['durationMinutes'] as num?)?.toInt() ?? 30;
    final notes = (stop['notes'] as String?) ?? (stop['description'] as String?);

    // Parse actual times
    DateTime? arrivedAt;
    DateTime? departedAt;
    if (stop['arrived_at'] != null) {
      arrivedAt = DateTime.tryParse(stop['arrived_at']);
    }
    if (stop['departed_at'] != null) {
      departedAt = DateTime.tryParse(stop['departed_at']);
    }

    // Determine status color
    Color statusColor;
    String statusLabel;
    if (hasDeparted) {
      statusColor = AppColors.success;
      statusLabel = 'tourism_stop_completed'.tr();
    } else if (hasArrived) {
      statusColor = AppColors.warning;
      statusLabel = 'tourism_at_stop'.tr();
    } else if (isCurrentStop) {
      statusColor = AppColors.primary;
      statusLabel = 'tourism_stop_next'.tr();
    } else {
      statusColor = AppColors.textTertiary;
      statusLabel = 'tourism_stop_pending'.tr();
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timeline column (dots and lines)
        SizedBox(
          width: 40,
          child: Column(
            children: [
              // Top line
              if (index > 0)
                Container(
                  width: 3,
                  height: 16,
                  color: hasDeparted || hasArrived
                      ? AppColors.success
                      : AppColors.border,
                ),
              // Dot/Indicator
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
                              : (isCurrentStop ? AppColors.primary : AppColors.card)),
                      border: Border.all(
                        color: statusColor,
                        width: isCurrentStop ? 3 : 2,
                      ),
                      boxShadow: isCurrentStop
                          ? [
                              BoxShadow(
                                color: statusColor.withValues(
                                    alpha: _pulseAnimation.value * 0.5),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: hasDeparted
                          ? const Icon(Icons.check, color: Colors.white, size: 14)
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
              // Bottom line
              if (!isLastStop)
                Container(
                  width: 3,
                  height: 120, // Adjust based on content height
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        hasDeparted ? AppColors.success : AppColors.border,
                        hasDeparted
                            ? AppColors.success
                            : (hasArrived ? AppColors.success : AppColors.border),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Content card
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isCurrentStop
                  ? AppColors.primary.withValues(alpha: 0.1)
                  : AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isCurrentStop
                    ? AppColors.primary.withValues(alpha: 0.5)
                    : AppColors.border,
                width: isCurrentStop ? 2 : 1,
              ),
              boxShadow: isCurrentStop ? AppColors.shadowSubtle : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        stopName,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight:
                              isCurrentStop ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: statusColor.withValues(alpha: 0.3)),
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
                const SizedBox(height: 8),
                // Address
                if (address != null && address.isNotEmpty)
                  Row(
                    children: [
                      Icon(Icons.place,
                          size: 14, color: AppColors.textTertiary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          address,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                // Times row
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    // Scheduled arrival
                    if (scheduledTime != null)
                      _buildTimeChip(
                        icon: Icons.schedule,
                        label: 'tourism_scheduled_arrival'.tr(),
                        time: scheduledTime,
                        color: AppColors.textTertiary,
                      ),
                    // Scheduled departure
                    if (departureTime != null)
                      _buildTimeChip(
                        icon: Icons.departure_board,
                        label: 'tourism_scheduled_departure'.tr(),
                        time: departureTime,
                        color: AppColors.textTertiary,
                      ),
                    // Duration
                    _buildTimeChip(
                      icon: Icons.timer,
                      label: 'tourism_duration'.tr(),
                      time: '$durationMinutes min',
                      color: AppColors.info,
                    ),
                  ],
                ),
                // Actual times (if available)
                if (arrivedAt != null || departedAt != null) ...[
                  const SizedBox(height: 8),
                  const Divider(color: AppColors.border, height: 1),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      if (arrivedAt != null)
                        _buildTimeChip(
                          icon: Icons.check_circle,
                          label: 'tourism_actual_arrival'.tr(),
                          time: _formatTime(arrivedAt),
                          color: AppColors.success,
                          isActual: true,
                        ),
                      if (departedAt != null)
                        _buildTimeChip(
                          icon: Icons.check_circle,
                          label: 'tourism_actual_departure'.tr(),
                          time: _formatTime(departedAt),
                          color: AppColors.success,
                          isActual: true,
                        ),
                    ],
                  ),
                ],
                // Notes
                if (notes != null && notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.notes, size: 14, color: AppColors.textTertiary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          notes,
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                // Action buttons (only for current or pending stops)
                if (!hasDeparted) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      // Mark Arrived button
                      if (!hasArrived)
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _markStopArrived(index),
                            icon: const Icon(Icons.check_circle_outline,
                                size: 18),
                            label: Text('tourism_stop_arrived'.tr()),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      // Mark Departed button (only if arrived)
                      if (hasArrived) ...[
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _markStopDeparted(index),
                            icon: const Icon(Icons.departure_board, size: 18),
                            label: Text('tourism_stop_departed'.tr()),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildTimeChip({
    required IconData icon,
    required String label,
    required String time,
    required Color color,
    bool isActual = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isActual ? 0.15 : 0.1),
        borderRadius: BorderRadius.circular(6),
        border: isActual
            ? Border.all(color: color.withValues(alpha: 0.3))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color.withValues(alpha: 0.8),
                  fontSize: 8,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                time,
                style: TextStyle(
                  color: color,
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

  Widget? _buildFloatingActions() {
    if (_itinerary.isEmpty) return null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Call to bus button
        FloatingActionButton(
          heroTag: 'callToBus',
          onPressed: _callToBus,
          backgroundColor: AppColors.warning,
          foregroundColor: Colors.white,
          mini: true,
          child: const Icon(Icons.directions_bus),
        ),
        const SizedBox(height: 12),
        // Notify passengers button
        FloatingActionButton.extended(
          heroTag: 'notify',
          onPressed: _notifyPassengers,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.campaign),
          label: Text('tourism_notify'.tr()),
        ),
      ],
    );
  }

  String _formatTime(DateTime time) {
    final localTime = time.toLocal();
    return '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
  }
}

/// Dialog for entering passenger notification message.
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
  List<String> get _quickMessages => [
    'tourism_msg_arrived'.tr(),
    'tourism_msg_leaving_5'.tr(),
    'tourism_msg_leaving_10'.tr(),
    'tourism_msg_return_bus'.tr(),
    'tourism_msg_free_time'.tr(),
    'tourism_msg_lunch'.tr(),
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
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.campaign, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'tourism_notify_passengers_title'.tr(),
              style: const TextStyle(
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
            // Current stop indicator
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
            // Quick messages
            Text(
              'tourism_quick_messages'.tr(),
              style: const TextStyle(
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
            // Custom message input
            TextField(
              controller: _controller,
              maxLines: 3,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'tourism_write_message'.tr(),
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
          child: Text(
            'tourism_cancel'.tr(),
            style: const TextStyle(color: AppColors.textTertiary),
          ),
        ),
        ElevatedButton.icon(
          onPressed: () {
            HapticService.mediumImpact();
            Navigator.pop(context, _controller.text);
          },
          icon: const Icon(Icons.send, size: 16),
          label: Text('tourism_send'.tr()),
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
