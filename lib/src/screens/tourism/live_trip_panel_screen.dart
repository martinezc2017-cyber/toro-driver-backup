import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';
import '../../providers/driver_provider.dart';
import '../../services/location_service.dart';
import '../../services/tourism_event_service.dart';
import '../../services/tourism_invitation_service.dart';
import '../../services/trip_fare_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';

/// Live Trip Panel Screen - the core screen a driver sees during an active
/// tourism trip.
///
/// Features:
/// - Fixed top bar with event name, status indicator, elapsed time
/// - Passenger summary strip (boarded / total, fare collected, next stop)
/// - Check-in list grouped by status (aboard, waiting, exited)
/// - Action buttons: Siguiente Parada, Detener Abordaje, Emergencia
/// - Real-time fare calculation per passenger
/// - Auto check-out prompt when arriving at a stop
class LiveTripPanelScreen extends StatefulWidget {
  final String eventId;

  const LiveTripPanelScreen({
    super.key,
    required this.eventId,
  });

  @override
  State<LiveTripPanelScreen> createState() => _LiveTripPanelScreenState();
}

class _LiveTripPanelScreenState extends State<LiveTripPanelScreen>
    with SingleTickerProviderStateMixin {
  // Services
  final TourismEventService _eventService = TourismEventService();
  final TourismInvitationService _invitationService =
      TourismInvitationService();
  final TripFareService _fareService = TripFareService();
  final LocationService _locationService = LocationService();

  // Data
  Map<String, dynamic> _tripSummary = {};
  List<Map<String, dynamic>> _passengers = [];
  List<Map<String, dynamic>> _itinerary = [];
  Map<String, dynamic>? _event;

  // State
  bool _isLoading = true;
  bool _acceptingBoardings = true;
  String _tripStatus = 'en_ruta'; // en_ruta, detenido, esperando
  int _currentStopIndex = 0;

  // Elapsed time
  Timer? _elapsedTimer;
  DateTime? _tripStartTime;
  String _elapsedFormatted = '00:00';

  // GPS
  Position? _currentPosition;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _locationUpdateTimer;

  // Realtime
  RealtimeChannel? _invitationsChannel;
  Timer? _refreshTimer;

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initPulseAnimation();
    _loadTripData();
    _startGpsTracking();
    _subscribeToRealtimeUpdates();
    // Refresh data every 15 seconds
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _loadTripData(),
    );
  }

  void _initPulseAnimation() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _elapsedTimer?.cancel();
    _positionSubscription?.cancel();
    _locationUpdateTimer?.cancel();
    if (_invitationsChannel != null) {
      Supabase.instance.client.removeChannel(_invitationsChannel!);
      _invitationsChannel = null;
    }
    _refreshTimer?.cancel();
    super.dispose();
  }

  // ===========================================================================
  // DATA LOADING
  // ===========================================================================

  Future<void> _loadTripData() async {
    try {
      final summary =
          await _fareService.getActiveTripSummary(widget.eventId);

      if (summary.containsKey('error')) {
        debugPrint('LIVE_TRIP -> Error: ${summary['error']}');
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }

      // Also load event data for extra fields
      _event ??= await _eventService.getEvent(widget.eventId);

      if (mounted) {
        setState(() {
          _tripSummary = summary;
          _passengers =
              List<Map<String, dynamic>>.from(summary['passengers'] ?? []);
          _itinerary =
              List<Map<String, dynamic>>.from(summary['itinerary'] ?? []);
          _currentStopIndex =
              (summary['current_stop_index'] as int?) ?? 0;
          _elapsedFormatted =
              (summary['elapsed_time'] as String?) ?? '00:00';
          _isLoading = false;

          // Set trip start time for local timer
          if (_tripStartTime == null && _event?['started_at'] != null) {
            _tripStartTime =
                DateTime.tryParse(_event!['started_at'] as String);
            _startElapsedTimer();
          }
        });
      }
    } catch (e) {
      debugPrint('LIVE_TRIP -> Error loading data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    // Update immediately on first call
    _updateElapsedDisplay();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_tripStartTime == null || !mounted) return;
      _updateElapsedDisplay();
    });
  }

  void _updateElapsedDisplay() {
    if (_tripStartTime == null) return;
    final diff = DateTime.now().toUtc().difference(_tripStartTime!);
    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;
    final seconds = diff.inSeconds % 60;
    setState(() {
      _elapsedFormatted = hours > 0
          ? '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}'
          : '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    });
  }

  // ===========================================================================
  // GPS TRACKING
  // ===========================================================================

  Future<void> _startGpsTracking() async {
    final hasPermission = await _locationService.checkAndRequestPermission();
    if (!hasPermission) return;

    _currentPosition = await _locationService.getCurrentPosition();

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 30,
    );

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      if (mounted) {
        _currentPosition = position;
        // Update status based on speed
        final isMoving = position.speed > 1.5;
        final newStatus = isMoving ? 'en_ruta' : 'detenido';
        if (newStatus != _tripStatus) {
          setState(() => _tripStatus = newStatus);
        }
      }
    });

    // Update driver location in DB every 10 seconds
    _locationUpdateTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _updateDriverLocation(),
    );
  }

  Future<void> _updateDriverLocation() async {
    if (_currentPosition == null) return;
    final driverProvider =
        Provider.of<DriverProvider>(context, listen: false);
    final driverId = driverProvider.driver?.id;
    if (driverId == null) return;

    try {
      await Supabase.instance.client.from('bus_driver_location').upsert({
        'driver_id': driverId,
        'route_id': widget.eventId,
        'lat': _currentPosition!.latitude,
        'lng': _currentPosition!.longitude,
        'speed': _currentPosition!.speed,
        'heading': _currentPosition!.heading,
        'accuracy': _currentPosition!.accuracy,
        'is_moving': _currentPosition!.speed > 1.5,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'driver_id');
    } catch (e) {
      debugPrint('LIVE_TRIP -> GPS update error: $e');
    }
  }

  // ===========================================================================
  // REALTIME SUBSCRIPTIONS
  // ===========================================================================

  void _subscribeToRealtimeUpdates() {
    _invitationsChannel = Supabase.instance.client
        .channel('live_trip_${widget.eventId}')
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
            // Reload trip data on any passenger change
            _loadTripData();
          },
        )
        .subscribe();
  }

  // ===========================================================================
  // ACTIONS
  // ===========================================================================

  /// Marks arrival at the next stop and checks for passengers exiting.
  Future<void> _onNextStop() async {
    HapticService.success();

    final nextStopIndex = _currentStopIndex;
    final stopName = _getStopName(nextStopIndex);

    try {
      // 1. Mark stop as arrived
      await _eventService.markStopArrived(widget.eventId, nextStopIndex);

      // 2. Check which passengers exit here
      final exitingPassengers =
          await _fareService.getPassengersExitingAtStop(
        eventId: widget.eventId,
        stopIndex: nextStopIndex,
      );

      if (exitingPassengers.isNotEmpty && mounted) {
        // Show exit confirmation dialog
        await _showExitConfirmationDialog(
          exitingPassengers,
          nextStopIndex,
          stopName,
        );
      }

      // 3. Advance stop index
      if (nextStopIndex < _itinerary.length - 1) {
        await Supabase.instance.client.from('tourism_events').update({
          'current_stop_index': nextStopIndex + 1,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', widget.eventId);
      }

      if (!mounted) return;

      // 4. Create bus event (non-blocking — FK may fail if bus_routes is empty)
      if (!mounted) return;
      final driverProvider =
          Provider.of<DriverProvider>(context, listen: false);
      final driverId = driverProvider.driver?.id;
      if (driverId != null && _currentPosition != null) {
        try {
          await Supabase.instance.client.from('bus_events').insert({
            'route_id': widget.eventId,
            'driver_id': driverId,
            'event_type': 'stop_arrival',
            'stop_name': stopName,
            'lat': _currentPosition!.latitude,
            'lng': _currentPosition!.longitude,
            'passengers_on_board': _tripSummary['passengers_aboard'] ?? 0,
            'metadata': {'stop_index': nextStopIndex},
            'created_at': DateTime.now().toUtc().toIso8601String(),
          });
        } catch (e) {
          debugPrint('LIVE_TRIP -> bus_events insert error (non-fatal): $e');
        }
      }

      // 5. Notify passengers exiting at next stop
      _notifyNextStopPassengers(nextStopIndex + 1);

      // 6. Reload
      await _loadTripData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Llegada a "$stopName" registrada'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Shows dialog prompting driver to confirm passenger exits at a stop.
  Future<void> _showExitConfirmationDialog(
    List<Map<String, dynamic>> exitingPassengers,
    int stopIndex,
    String stopName,
  ) async {
    final pricePerKm =
        ((_tripSummary['price_per_km'] as num?)?.toDouble()) ?? 0.0;

    // Calculate fares for each exiting passenger
    final passengerFares = <Map<String, dynamic>>[];
    for (final p in exitingPassengers) {
      final boardingIdx = (p['boarding_stop_index'] as int?) ?? 0;
      final fare = _fareService.calculatePassengerFare(
        itinerary: _itinerary,
        boardingStopIndex: boardingIdx,
        exitStopIndex: stopIndex,
        pricePerKm: pricePerKm,
      );
      passengerFares.add({
        ...p,
        'calculated_fare': fare,
      });
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.exit_to_app,
                color: AppColors.warning,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${exitingPassengers.length} pasajero${exitingPassengers.length > 1 ? 's' : ''} baja${exitingPassengers.length > 1 ? 'n' : ''} aqui',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    stopName,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: passengerFares.length,
              separatorBuilder: (_, _) => Divider(
                color: AppColors.border.withOpacity(0.5),
                height: 1,
              ),
              itemBuilder: (_, i) {
                final p = passengerFares[i];
                final name = p['invited_name'] ?? 'Pasajero';
                final fare = (p['calculated_fare'] as num?)?.toDouble() ?? 0.0;
                final payment =
                    (p['payment_method'] as String?) ?? 'efectivo';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            name.isNotEmpty
                                ? name[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
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
                            ),
                            Text(
                              payment == 'efectivo'
                                  ? 'Pago en efectivo'
                                  : 'Pago con tarjeta',
                              style: const TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '\$${fare.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: AppColors.success,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Confirmar bajada'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Batch exit all passengers
      final exitedCount = await _fareService.batchExitPassengers(
        passengers: exitingPassengers,
        exitStopIndex: stopIndex,
        itinerary: _itinerary,
        pricePerKm: pricePerKm,
      );

      HapticService.completed();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$exitedCount pasajero${exitedCount > 1 ? 's' : ''} bajaron en $stopName',
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Sends notifications to passengers whose exit is the next stop.
  Future<void> _notifyNextStopPassengers(int nextStopIndex) async {
    try {
      // Notify ALL aboard passengers about the next stop
      // (we don't track per-passenger exit stops)
      final nextStopPassengers = _passengers
          .where((p) => p['category'] == 'aboard')
          .toList();

      if (nextStopPassengers.isEmpty) return;

      final stopName = _getStopName(nextStopIndex);

      for (final p in nextStopPassengers) {
        final userId = p['user_id'] as String?;
        if (userId == null) continue;

        await Supabase.instance.client
            .from(SupabaseConfig.notificationsTable)
            .insert({
          'user_id': userId,
          'title': 'Proxima parada: $stopName',
          'body': 'Tu parada es la siguiente. Preparate para bajar.',
          'type': 'tourism_next_stop',
          'data': {
            'event_id': widget.eventId,
            'stop_index': nextStopIndex,
          },
          'read': false,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('LIVE_TRIP -> Error notifying next stop: $e');
    }
  }

  /// Toggles boarding acceptance on/off.
  Future<void> _onToggleBoarding() async {
    HapticService.mediumImpact();

    final newState = !_acceptingBoardings;

    try {
      await _fareService.toggleBoardingAcceptance(
        eventId: widget.eventId,
        acceptingBoardings: newState,
      );

      setState(() => _acceptingBoardings = newState);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newState
                  ? 'Abordaje habilitado'
                  : 'Abordaje detenido - no se aceptan nuevos pasajeros',
            ),
            backgroundColor: newState ? AppColors.success : AppColors.warning,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Sends an emergency broadcast to all passengers.
  Future<void> _onEmergency() async {
    HapticService.error();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.error,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Alerta de Emergencia',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: const Text(
          'Esto enviara una notificacion de emergencia a TODOS los pasajeros y al organizador del evento.\n\n'
          'Solo usar en situaciones reales de emergencia.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.warning, size: 18),
            label: const Text('Enviar Alerta'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Broadcast to all passengers
      await _eventService.notifyEventPassengers(
        eventId: widget.eventId,
        title: 'ALERTA DE EMERGENCIA',
        body: 'El conductor ha emitido una alerta de emergencia. '
            'Por favor siga las instrucciones del conductor.',
        type: 'tourism_emergency',
        extraData: {
          'level': 4,
          'lat': _currentPosition?.latitude,
          'lng': _currentPosition?.longitude,
        },
      );

      // Also notify organizer
      final organizerId = _event?['organizer_id'] as String?;
      if (organizerId != null) {
        await Supabase.instance.client
            .from(SupabaseConfig.notificationsTable)
            .insert({
          'user_id': organizerId,
          'title': 'EMERGENCIA - Conductor',
          'body':
              'El conductor ha emitido una alerta de emergencia en el evento.',
          'type': 'tourism_emergency',
          'data': {
            'event_id': widget.eventId,
            'level': 4,
            'lat': _currentPosition?.latitude,
            'lng': _currentPosition?.longitude,
          },
          'read': false,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Alerta de emergencia enviada a todos'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar alerta: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Shows passenger detail bottom sheet.
  void _showPassengerDetail(Map<String, dynamic> passenger) {
    HapticService.lightImpact();

    final name = passenger['invited_name'] ?? 'Pasajero';
    final phone = passenger['invited_phone'] as String?;
    final status = passenger['status'] as String? ?? 'accepted';
    final boardingStop = passenger['boarding_stop_name'] ?? '-';
    final exitStop = passenger['exit_stop_name'] ?? 'No definido';
    final estimatedFare =
        (passenger['estimated_fare'] as num?)?.toDouble() ?? 0.0;
    final finalFare = (passenger['final_fare'] as num?)?.toDouble();
    final payment = (passenger['payment_method'] as String?) ?? 'efectivo';
    final boardedAt = passenger['boarded_at'] as String?;
    final exitedAt = passenger['exited_at'] as String?;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Name and avatar
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _getCategoryColor(
                            passenger['category'] as String? ?? 'waiting')
                        .withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: _getCategoryColor(
                            passenger['category'] as String? ?? 'waiting'),
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      _buildStatusBadge(status),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 16),
            // Details
            _buildDetailRow(Icons.directions_bus, 'Sube en', boardingStop),
            const SizedBox(height: 10),
            _buildDetailRow(Icons.location_on, 'Baja en', exitStop),
            const SizedBox(height: 10),
            _buildDetailRow(
              Icons.attach_money,
              'Tarifa estimada',
              '\$${estimatedFare.toStringAsFixed(2)}',
            ),
            if (finalFare != null) ...[
              const SizedBox(height: 10),
              _buildDetailRow(
                Icons.receipt,
                'Tarifa final',
                '\$${finalFare.toStringAsFixed(2)}',
                valueColor: AppColors.success,
              ),
            ],
            const SizedBox(height: 10),
            _buildDetailRow(
              Icons.payment,
              'Metodo de pago',
              payment == 'efectivo' ? 'Efectivo' : 'Tarjeta',
            ),
            if (boardedAt != null) ...[
              const SizedBox(height: 10),
              _buildDetailRow(
                Icons.login,
                'Abordo a las',
                _formatTime(boardedAt),
              ),
            ],
            if (exitedAt != null) ...[
              const SizedBox(height: 10),
              _buildDetailRow(
                Icons.logout,
                'Bajo a las',
                _formatTime(exitedAt),
              ),
            ],
            if (phone != null && phone.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildDetailRow(Icons.phone, 'Telefono', phone),
            ],
            const SizedBox(height: 24),
            // Quick actions
            if (status == 'accepted')
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _manualBoardPassenger(passenger);
                  },
                  icon: const Icon(Icons.person_add, size: 18),
                  label: const Text('Registrar abordaje'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            if (status == 'boarded' || status == 'checked_in')
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _manualExitPassenger(passenger);
                  },
                  icon: const Icon(Icons.exit_to_app, size: 18),
                  label: const Text('Registrar bajada'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.warning,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom),
          ],
        ),
      ),
    );
  }

  /// Manually boards a passenger at the current stop.
  Future<void> _manualBoardPassenger(Map<String, dynamic> passenger) async {
    final invitationId = passenger['id'] as String?;
    if (invitationId == null) return;

    try {
      await _fareService.recordPassengerBoarding(
        invitationId: invitationId,
        boardingStopIndex: _currentStopIndex,
      );
      HapticService.success();
      await _loadTripData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${passenger['invited_name'] ?? "Pasajero"} abordado',
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Manually exits a passenger at the current stop.
  Future<void> _manualExitPassenger(Map<String, dynamic> passenger) async {
    final invitationId = passenger['id'] as String?;
    if (invitationId == null) return;

    final pricePerKm =
        ((_tripSummary['price_per_km'] as num?)?.toDouble()) ?? 0.0;
    final boardingIdx = (passenger['boarding_stop_index'] as int?) ?? 0;
    final fare = _fareService.calculatePassengerFare(
      itinerary: _itinerary,
      boardingStopIndex: boardingIdx,
      exitStopIndex: _currentStopIndex,
      pricePerKm: pricePerKm,
    );

    try {
      await _fareService.recordPassengerExit(
        invitationId: invitationId,
        exitStopIndex: _currentStopIndex,
        fare: fare,
        paymentMethod:
            (passenger['payment_method'] as String?) ?? 'efectivo',
      );
      HapticService.success();
      await _loadTripData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${passenger['invited_name'] ?? "Pasajero"} bajo - '
              'Tarifa: \$${fare.toStringAsFixed(2)}',
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  String _getStopName(int index) {
    for (final stop in _itinerary) {
      final order = (stop['stop_order'] as int?) ?? 0;
      if (order == index) {
        return (stop['name'] as String?) ?? 'Parada ${index + 1}';
      }
    }
    return 'Parada ${index + 1}';
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'aboard':
        return AppColors.success;
      case 'waiting':
        return AppColors.warning;
      case 'exited':
        return AppColors.textTertiary;
      default:
        return AppColors.textSecondary;
    }
  }

  String _getCategoryLabel(String category) {
    switch (category) {
      case 'aboard':
        return 'A bordo';
      case 'waiting':
        return 'Esperando';
      case 'exited':
        return 'Bajaron';
      default:
        return category;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'aboard':
        return Icons.airline_seat_recline_normal;
      case 'waiting':
        return Icons.schedule;
      case 'exited':
        return Icons.check_circle_outline;
      default:
        return Icons.person;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'en_ruta':
        return 'En Ruta';
      case 'detenido':
        return 'Detenido';
      case 'esperando':
        return 'Esperando';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'en_ruta':
        return AppColors.success;
      case 'detenido':
        return AppColors.warning;
      case 'esperando':
        return AppColors.info;
      default:
        return AppColors.textSecondary;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'en_ruta':
        return Icons.directions_bus;
      case 'detenido':
        return Icons.pause_circle_filled;
      case 'esperando':
        return Icons.hourglass_top;
      default:
        return Icons.info;
    }
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return '--:--';
    final dt = DateTime.tryParse(isoString)?.toLocal();
    if (dt == null) return '--:--';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildStatusBadge(String status) {
    final label = switch (status) {
      'boarded' || 'checked_in' => 'A bordo',
      'off_boarded' => 'Bajo',
      'accepted' => 'Esperando',
      _ => status,
    };
    final color = switch (status) {
      'boarded' || 'checked_in' => AppColors.success,
      'off_boarded' => AppColors.textTertiary,
      'accepted' => AppColors.warning,
      _ => AppColors.textSecondary,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, color: AppColors.textTertiary, size: 18),
        const SizedBox(width: 12),
        Text(
          '$label: ',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

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
            ? _buildLoadingState()
            : SafeArea(
                child: Column(
                  children: [
                    _buildTopBar(),
                    _buildPassengerSummaryStrip(),
                    Expanded(child: _buildPassengerList()),
                  ],
                ),
              ),
        bottomNavigationBar: _isLoading ? null : _buildActionButtons(),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          SizedBox(height: 16),
          Text(
            'Cargando panel de viaje...',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TOP BAR
  // ---------------------------------------------------------------------------

  Widget _buildTopBar() {
    final eventTitle =
        (_tripSummary['event_title'] as String?) ?? 'Viaje en curso';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
          const SizedBox(width: 4),
          // Event name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eventTitle,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                // Elapsed time
                Row(
                  children: [
                    const Icon(
                      Icons.timer_outlined,
                      color: AppColors.textTertiary,
                      size: 13,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _elapsedFormatted,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Status indicator
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              final statusColor = _getStatusColor(_tripStatus);
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor
                      .withOpacity(_pulseAnimation.value * 0.25),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color:
                        statusColor.withOpacity(_pulseAnimation.value),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getStatusIcon(_tripStatus),
                      color: statusColor,
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _getStatusLabel(_tripStatus),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
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

  // ---------------------------------------------------------------------------
  // PASSENGER SUMMARY STRIP
  // ---------------------------------------------------------------------------

  Widget _buildPassengerSummaryStrip() {
    final aboard = (_tripSummary['passengers_aboard'] as int?) ?? 0;
    final total = (_tripSummary['total_passengers'] as int?) ?? 0;
    final maxPassengers = (_tripSummary['max_passengers'] as int?) ?? total;
    final collected =
        ((_tripSummary['total_fare_collected'] as num?)?.toDouble()) ?? 0.0;
    final estimated =
        ((_tripSummary['estimated_total_fare'] as num?)?.toDouble()) ?? 0.0;
    final nextStopName =
        (_tripSummary['next_stop_name'] as String?) ?? 'Final';
    final progress =
        maxPassengers > 0 ? (aboard / maxPassengers).clamp(0.0, 1.0) : 0.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Top row: boarded count + fare
          Row(
            children: [
              // Boarded count with progress
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.people,
                          color: AppColors.primary,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$aboard/$maxPassengers abordados',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: AppColors.border,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.primary,
                        ),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Fare collected
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '\$${collected.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: AppColors.success,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'de \$${estimated.toStringAsFixed(0)} est.',
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 8),
          // Next stop
          Row(
            children: [
              const Icon(
                Icons.arrow_forward,
                color: AppColors.info,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                'Siguiente: ',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              Expanded(
                child: Text(
                  nextStopName,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Parada ${_currentStopIndex + 1}/${_itinerary.length}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PASSENGER LIST (grouped)
  // ---------------------------------------------------------------------------

  Widget _buildPassengerList() {
    if (_passengers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline,
              size: 48,
              color: AppColors.textTertiary.withOpacity(0.5),
            ),
            const SizedBox(height: 12),
            const Text(
              'Sin pasajeros registrados',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    // Group passengers by category
    final aboard = _passengers
        .where((p) => p['category'] == 'aboard')
        .toList();
    final waiting = _passengers
        .where((p) => p['category'] == 'waiting')
        .toList();
    final exited = _passengers
        .where((p) => p['category'] == 'exited')
        .toList();

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      onRefresh: _loadTripData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        children: [
          if (aboard.isNotEmpty) ...[
            _buildSectionHeader(
              'A bordo',
              aboard.length,
              AppColors.success,
              Icons.airline_seat_recline_normal,
            ),
            ...aboard.map(_buildPassengerCard),
          ],
          if (waiting.isNotEmpty) ...[
            _buildSectionHeader(
              'Esperando pickup',
              waiting.length,
              AppColors.warning,
              Icons.schedule,
            ),
            ...waiting.map(_buildPassengerCard),
          ],
          if (exited.isNotEmpty) ...[
            _buildSectionHeader(
              'Bajaron',
              exited.length,
              AppColors.textTertiary,
              Icons.check_circle_outline,
            ),
            ...exited.map(_buildPassengerCard),
          ],
          // Bottom padding for action buttons
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    int count,
    Color color,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPassengerCard(Map<String, dynamic> passenger) {
    final name = (passenger['invited_name'] as String?) ?? 'Pasajero';
    final category = (passenger['category'] as String?) ?? 'waiting';
    final boardingStop =
        (passenger['boarding_stop_name'] as String?) ?? '-';
    final exitStop = passenger['exit_stop_name'] as String?;
    final estimatedFare =
        (passenger['estimated_fare'] as num?)?.toDouble() ?? 0.0;
    final finalFare = (passenger['final_fare'] as num?)?.toDouble();
    final payment =
        (passenger['payment_method'] as String?) ?? 'efectivo';
    final seatNumber = passenger['seat_number'] as String?;
    final gpsEnabled = passenger['gps_tracking_enabled'] as bool? ?? false;
    final hasGps = passenger['last_known_lat'] != null;

    final categoryColor = _getCategoryColor(category);
    final displayFare = finalFare ?? estimatedFare;
    final isExited = category == 'exited';

    return GestureDetector(
      onTap: () => _showPassengerDetail(passenger),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isExited
              ? AppColors.card.withOpacity(0.6)
              : AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: categoryColor.withOpacity(0.2),
          ),
        ),
        child: Row(
          children: [
            // Avatar circle with GPS indicator
            Stack(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: categoryColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      seatNumber ?? (name.isNotEmpty ? name[0].toUpperCase() : '?'),
                      style: TextStyle(
                        color: categoryColor,
                        fontWeight: FontWeight.w700,
                        fontSize: seatNumber != null ? 12 : 16,
                      ),
                    ),
                  ),
                ),
                if (gpsEnabled && hasGps)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.card, width: 1.5),
                      ),
                      child: const Icon(Icons.gps_fixed, color: Colors.white, size: 7),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            // Name + stops
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: isExited
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.arrow_upward,
                        size: 11,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          boardingStop,
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (exitStop != null) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.arrow_downward,
                          size: 11,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            exitStop,
                            style: const TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Fare + payment indicator
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\$${displayFare.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: finalFare != null
                        ? AppColors.success
                        : AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: payment == 'efectivo'
                        ? AppColors.warning.withOpacity(0.15)
                        : AppColors.success.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    payment == 'efectivo' ? 'Efectivo' : 'Pagado',
                    style: TextStyle(
                      color: payment == 'efectivo'
                          ? AppColors.warning
                          : AppColors.success,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ACTION BUTTONS (floating bottom)
  // ---------------------------------------------------------------------------

  bool _isCompleting = false;

  /// Completes the trip: marks event as completed, notifies all passengers,
  /// creates a bus_event 'completed', and pops back.
  Future<void> _onCompleteTrip() async {
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
                color: AppColors.success.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.flag, color: AppColors.success, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'tourism_complete_trip_title'.tr(),
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: Text(
          'tourism_complete_trip_confirm'.tr(),
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
            label: Text('tourism_complete_trip_title'.tr()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Extract context-dependent values BEFORE async operations
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    final driverId = driverProvider.driver?.id;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _isCompleting = true);
    HapticService.completed();

    try {
      // 1. Complete the event
      await _eventService.completeEvent(widget.eventId);

      // 2. Create bus_event 'completed' so rider gets realtime notification
      if (driverId != null) {
        try {
          await Supabase.instance.client.from('bus_events').insert({
            'route_id': widget.eventId,
            'driver_id': driverId,
            'event_type': 'completed',
            'stop_name': 'Final',
            'passengers_on_board': _tripSummary['passengers_aboard'] ?? 0,
            'lat': _currentPosition?.latitude,
            'lng': _currentPosition?.longitude,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          });
        } catch (e) {
          debugPrint('LIVE_TRIP -> bus_events completed insert error: $e');
        }
      }

      // 3. Notify all passengers
      await _eventService.notifyEventPassengers(
        eventId: widget.eventId,
        title: 'tourism_trip_completed'.tr(),
        body: 'tourism_trip_completed_notify'.tr(),
        type: 'tourism_trip_completed',
      );

      // 4. Also notify organizer
      final organizerId = _event?['organizer_id'] as String?;
      if (organizerId != null) {
        await Supabase.instance.client
            .from(SupabaseConfig.notificationsTable)
            .insert({
          'user_id': organizerId,
          'title': 'tourism_trip_completed'.tr(),
          'body': 'tourism_trip_completed_organizer'.tr(),
          'type': 'tourism_trip_completed',
          'data': {'event_id': widget.eventId},
          'read': false,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      }

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('tourism_trip_completed'.tr()),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      navigator.pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isCompleting = false);
      }
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('tourism_error_completing'.tr(namedArgs: {'error': '$e'})),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildActionButtons() {
    final isLastStop = _currentStopIndex >= _itinerary.length - 1;

    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        10,
        12,
        MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.border.withOpacity(0.5)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Primary action: Next Stop or Complete Trip
          Expanded(
            flex: 3,
            child: isLastStop
                ? ElevatedButton.icon(
                    onPressed: _isCompleting ? null : _onCompleteTrip,
                    icon: _isCompleting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.flag, size: 20),
                    label: Text(
                      _isCompleting ? 'tourism_completing'.tr() : 'tourism_complete_trip'.tr(),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: _onNextStop,
                    icon: const Icon(Icons.skip_next, size: 20),
                    label: Text(
                      'tourism_next_stop'.tr(),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          // Toggle boarding button
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _onToggleBoarding,
              icon: Icon(
                _acceptingBoardings
                    ? Icons.person_off
                    : Icons.person_add,
                size: 18,
              ),
              label: Text(
                _acceptingBoardings ? 'tourism_boarding_closed'.tr() : 'tourism_boarding_open'.tr(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _acceptingBoardings
                    ? AppColors.warning.withOpacity(0.15)
                    : AppColors.success.withOpacity(0.15),
                foregroundColor:
                    _acceptingBoardings ? AppColors.warning : AppColors.success,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: _acceptingBoardings
                        ? AppColors.warning.withOpacity(0.3)
                        : AppColors.success.withOpacity(0.3),
                  ),
                ),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Emergency button
          SizedBox(
            width: 52,
            height: 52,
            child: ElevatedButton(
              onPressed: _onEmergency,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error.withOpacity(0.15),
                foregroundColor: AppColors.error,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: AppColors.error.withOpacity(0.3),
                  ),
                ),
                elevation: 0,
              ),
              child: const Icon(Icons.sos, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}
