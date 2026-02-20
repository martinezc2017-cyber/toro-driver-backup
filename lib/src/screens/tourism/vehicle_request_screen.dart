import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../../providers/driver_provider.dart';
import '../../services/tourism_event_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';
import 'tourism_driver_home_screen.dart';

/// Screen for drivers to view and respond to vehicle/bid requests from organizers.
///
/// Redesigned as a bidding (puja) system:
/// - Driver sees event info + full itinerary (NOT vehicle info)
/// - Driver proposes their price per km
/// - If price is left empty, min_price_per_km is used as anti-fraud default
class VehicleRequestScreen extends StatefulWidget {
  final bool embedded;
  const VehicleRequestScreen({super.key, this.embedded = false});

  @override
  State<VehicleRequestScreen> createState() => _VehicleRequestScreenState();
}

class _VehicleRequestScreenState extends State<VehicleRequestScreen>
    with SingleTickerProviderStateMixin {
  final TourismEventService _eventService = TourismEventService();

  // Invited bids (existing)
  List<Map<String, dynamic>> _requests = [];
  // Open events (new - visible to all drivers)
  List<Map<String, dynamic>> _openEvents = [];
  // Driver's own bids (all statuses)
  List<Map<String, dynamic>> _myBids = [];
  bool _isLoading = true;
  bool _isLoadingOpen = true;
  bool _isLoadingMyBids = true;
  String? _error;
  RealtimeChannel? _realtimeChannel;
  RealtimeChannel? _bidStatusChannel;
  double _minPricePerKm = 10.0; // default, loaded from pricing_rules_mx
  int _driverVehicleSeats = 0; // loaded from bus_vehicles

  // Tab controller for "Eventos Abiertos", "Invitaciones", "Mis Pujas"
  late TabController _tabController;

  // Filter for open events
  final _filterController = TextEditingController();
  String _filterText = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadMinPrice();
    _loadDriverVehicle();
    _loadRequests();
    _loadOpenEvents();
    _loadMyBids();
    _subscribeToRequests();
    _subscribeToBidStatusChanges();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    // Refresh data when switching to "Mis Pujas" tab (index 2)
    if (_tabController.index == 2) {
      _loadMyBids();
    }
  }

  /// Subscribe to realtime changes on tourism_vehicle_bids for this driver.
  /// Detects when organizer accepts/rejects/counter-offers a bid.
  void _subscribeToBidStatusChanges() {
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    final driver = driverProvider.driver;
    if (driver == null) return;

    _bidStatusChannel = Supabase.instance.client
        .channel('bid_status_${driver.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'tourism_vehicle_bids',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'driver_id',
            value: driver.id,
          ),
          callback: (payload) {
            if (!mounted) return;
            final newRecord = payload.newRecord;
            final orgStatus = newRecord['organizer_status'] as String?;
            debugPrint('🔔 Bid status changed: organizer_status=$orgStatus');
            // Refresh bids list
            _loadMyBids();
            // Show in-app banner for won bid
            if (orgStatus == 'selected' && newRecord['is_winning_bid'] == true) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.emoji_events, color: Colors.amber, size: 28),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('Tu puja fue aceptada!',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                      ),
                    ],
                  ),
                  backgroundColor: Colors.green.shade700,
                  duration: const Duration(seconds: 5),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              HapticService.heavyImpact();
            }
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _filterController.dispose();
    _unsubscribeFromRequests();
    if (_bidStatusChannel != null) {
      Supabase.instance.client.removeChannel(_bidStatusChannel!);
      _bidStatusChannel = null;
    }
    super.dispose();
  }

  Future<void> _loadOpenEvents() async {
    setState(() => _isLoadingOpen = true);
    try {
      final driverProvider = Provider.of<DriverProvider>(context, listen: false);
      final driver = driverProvider.driver;
      if (driver == null) {
        setState(() => _isLoadingOpen = false);
        return;
      }

      final events = await _eventService.getOpenEventsForBidding(driver.id);
      setState(() {
        _openEvents = events;
        _isLoadingOpen = false;
      });
    } catch (e) {
      setState(() => _isLoadingOpen = false);
    }
  }

  Future<void> _loadMyBids() async {
    setState(() => _isLoadingMyBids = true);
    try {
      final driverProvider = Provider.of<DriverProvider>(context, listen: false);
      final driver = driverProvider.driver;
      if (driver == null) {
        setState(() => _isLoadingMyBids = false);
        return;
      }

      final bids = await _eventService.getDriverBids(driver.id);
      setState(() {
        _myBids = bids;
        _isLoadingMyBids = false;
      });
    } catch (e) {
      setState(() => _isLoadingMyBids = false);
    }
  }

  Future<void> _loadMinPrice() async {
    try {
      final response = await Supabase.instance.client
          .from('pricing_rules_mx')
          .select('min_price_per_km')
          .limit(1)
          .maybeSingle();
      if (response != null && response['min_price_per_km'] != null) {
        setState(() {
          _minPricePerKm = (response['min_price_per_km'] as num).toDouble();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadDriverVehicle() async {
    try {
      final driverProvider = Provider.of<DriverProvider>(context, listen: false);
      final driver = driverProvider.driver;
      if (driver == null) return;

      final vehicles = await Supabase.instance.client
          .from('bus_vehicles')
          .select('total_seats')
          .eq('owner_id', driver.id)
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(1);

      if (vehicles.isNotEmpty && vehicles.first['total_seats'] != null) {
        setState(() {
          _driverVehicleSeats = vehicles.first['total_seats'] as int;
        });
      }
    } catch (_) {}
  }

  bool _isOverCapacity(Map<String, dynamic> request) {
    if (_driverVehicleSeats <= 0) return false;
    final passengers = request['max_passengers'] as int? ??
        request['expected_passengers'] as int? ?? 0;
    return passengers > _driverVehicleSeats;
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final driverProvider = Provider.of<DriverProvider>(context, listen: false);
      final driver = driverProvider.driver;

      if (driver == null) {
        setState(() {
          _isLoading = false;
          _error = 'No hay conductor conectado';
        });
        return;
      }

      final requests = await _eventService.getPendingVehicleRequests(driver.id);

      setState(() {
        _requests = requests;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  void _subscribeToRequests() {
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    final driver = driverProvider.driver;
    if (driver == null) return;

    _realtimeChannel = _eventService.subscribeToVehicleRequests(
      driver.id,
      (request) {
        _loadRequests();
        _loadMyBids();
      },
    );
  }

  Future<void> _unsubscribeFromRequests() async {
    if (_realtimeChannel != null) {
      await _eventService.unsubscribe(_realtimeChannel!);
    }
  }

  /// Show bid dialog where driver proposes their price per km
  Future<void> _showBidDialog(Map<String, dynamic> request) async {
    final eventId = request['id'] as String?;
    if (eventId == null) return;

    final bidId = request['bid_id'] as String?;
    final eventTitle = request['event_name'] ?? request['title'] ?? 'este evento';
    final distanceKm = (request['total_distance_km'] as num?)?.toDouble() ??
        (request['estimated_distance_km'] as num?)?.toDouble();
    final passengers = request['max_passengers'] as int? ??
        request['expected_passengers'] as int?;

    final priceController = TextEditingController();
    double? proposedPrice;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final price = proposedPrice ?? _minPricePerKm;
          final estimatedTotal = distanceKm != null ? distanceKm * price : null;
          // TORO commission 18%
          final toroFee = estimatedTotal != null ? estimatedTotal * 0.18 : null;
          final driverEarnings = estimatedTotal != null && toroFee != null
              ? estimatedTotal - toroFee
              : null;

          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
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
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Title
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.gavel_rounded,
                          color: AppColors.gold,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Enviar Puja',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Propone tu precio por km para "$eventTitle"',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Price input
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: priceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: _minPricePerKm.toStringAsFixed(0),
                      hintStyle: TextStyle(
                        color: AppColors.textTertiary.withValues(alpha: 0.5),
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(left: 16),
                        child: Text(
                          '\$',
                          style: TextStyle(
                            color: AppColors.gold,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 40),
                      suffixText: 'MXN/km',
                      suffixStyle: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 14,
                      ),
                      filled: true,
                      fillColor: AppColors.card,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
                      ),
                    ),
                    onChanged: (val) {
                      setModalState(() {
                        proposedPrice = double.tryParse(val);
                      });
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Precio minimo: \$${_minPricePerKm.toStringAsFixed(0)} MXN/km',
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                ),
                // Estimated earnings
                if (distanceKm != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.success.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildEstimateRow(
                          'Distancia',
                          '${distanceKm.toStringAsFixed(0)} km',
                        ),
                        if (passengers != null)
                          _buildEstimateRow(
                            'Pasajeros',
                            '$passengers personas',
                          ),
                        _buildEstimateRow(
                          'Tu precio/km',
                          '\$${price.toStringAsFixed(0)} MXN',
                        ),
                        if (estimatedTotal != null) ...[
                          const Divider(color: AppColors.border, height: 16),
                          _buildEstimateRow(
                            'Precio total viaje',
                            '\$${estimatedTotal.toStringAsFixed(0)} MXN',
                            valueBold: true,
                          ),
                          if (passengers != null && passengers > 0)
                            _buildEstimateRow(
                              'Boleto por persona',
                              '\$${(estimatedTotal / passengers).toStringAsFixed(0)} MXN',
                            ),
                          _buildEstimateRow(
                            'Comision TORO (18%)',
                            '-\$${toroFee!.toStringAsFixed(0)} MXN',
                            valueColor: AppColors.error,
                          ),
                          const Divider(color: AppColors.border, height: 16),
                          _buildEstimateRow(
                            'Tu ganancia estimada',
                            '\$${driverEarnings!.toStringAsFixed(0)} MXN',
                            labelStyle: const TextStyle(
                              color: AppColors.success,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                            valueColor: AppColors.success,
                            valueBold: true,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                // Action buttons
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            side: const BorderSide(color: AppColors.border),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(context, true),
                          icon: const Icon(Icons.gavel_rounded, size: 18),
                          label: const Text('Enviar Puja'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.gold,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
              ],
            ),
          );
        },
      ),
    );

    if (confirmed != true) return;

    // Use proposed price or min price as default
    final finalPrice = proposedPrice ?? _minPricePerKm;

    HapticService.success();

    try {
      final result = await _eventService.respondToVehicleRequest(
        eventId,
        true,
        bidId: bidId,
        pricePerKm: finalPrice,
      );

      if (result.isEmpty) {
        throw Exception('Error al enviar la puja');
      }

      // Remove from list
      setState(() {
        _requests.removeWhere((r) => r['id'] == eventId);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Puja enviada: \$${finalPrice.toStringAsFixed(0)} MXN/km',
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
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

  Widget _buildEstimateRow(
    String label,
    String value, {
    TextStyle? labelStyle,
    Color? valueColor,
    bool valueBold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: labelStyle ??
                const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppColors.textPrimary,
              fontSize: 13,
              fontWeight: valueBold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _rejectRequest(Map<String, dynamic> request) async {
    final eventId = request['id'] as String?;
    if (eventId == null) return;

    final bidId = request['bid_id'] as String?;

    final reason = await _showRejectionDialog();
    if (reason == null) return;

    HapticService.lightImpact();

    try {
      final result = await _eventService.respondToVehicleRequest(
        eventId,
        false,
        reason: reason.isNotEmpty ? reason : null,
        bidId: bidId,
      );

      if (result.isEmpty) {
        throw Exception('Error al rechazar la solicitud');
      }

      setState(() {
        _requests.removeWhere((r) => r['id'] == eventId);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Solicitud rechazada'),
            backgroundColor: AppColors.textTertiary,
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

  /// Accept the organizer's counter-offer price
  Future<void> _acceptCounterOffer(Map<String, dynamic> request) async {
    final bidId = request['bid_id'] as String?;
    if (bidId == null) return;

    HapticService.success();

    try {
      await _eventService.acceptCounterOffer(bidId);

      setState(() {
        _requests.removeWhere((r) => r['bid_id'] == bidId);
      });

      if (mounted) {
        final price = (request['organizer_proposed_price'] as num?)?.toDouble();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              price != null
                  ? 'Contra-oferta aceptada: \$${price.toStringAsFixed(0)} MXN/km'
                  : 'Contra-oferta aceptada',
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
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

  /// Show dialog for driver to send a counter-offer back to organizer
  Future<void> _showDriverCounterOfferDialog(Map<String, dynamic> request) async {
    final bidId = request['bid_id'] as String?;
    if (bidId == null) return;

    final organizerPrice = (request['organizer_proposed_price'] as num?)?.toDouble();
    final round = (request['negotiation_round'] as int?) ?? 0;
    final priceController = TextEditingController();
    double? proposedPrice;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
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
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Title
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.swap_horiz_rounded,
                          color: AppColors.warning,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Tu Contra-oferta',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Ronda de negociacion ${round + 1}',
                              style: const TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (organizerPrice != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        'El organizador propone: \$${organizerPrice.toStringAsFixed(0)} MXN/km',
                        style: const TextStyle(
                          color: AppColors.warning,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                // Price input
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: priceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: organizerPrice != null
                          ? (organizerPrice + 2).toStringAsFixed(0)
                          : _minPricePerKm.toStringAsFixed(0),
                      hintStyle: TextStyle(
                        color: AppColors.textTertiary.withValues(alpha: 0.5),
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(left: 16),
                        child: Text(
                          '\$',
                          style: TextStyle(
                            color: AppColors.warning,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 40),
                      suffixText: 'MXN/km',
                      suffixStyle: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 14,
                      ),
                      filled: true,
                      fillColor: AppColors.card,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: AppColors.warning, width: 1.5),
                      ),
                    ),
                    onChanged: (val) {
                      setModalState(() {
                        proposedPrice = double.tryParse(val);
                      });
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Precio minimo: \$${_minPricePerKm.toStringAsFixed(0)} MXN/km',
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Action buttons
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            side: const BorderSide(color: AppColors.border),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(context, true),
                          icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                          label: const Text('Enviar Contra-oferta'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.warning,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
              ],
            ),
          );
        },
      ),
    );

    if (confirmed != true) return;

    final finalPrice = proposedPrice ?? _minPricePerKm;

    if (finalPrice < _minPricePerKm) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'El precio minimo es \$${_minPricePerKm.toStringAsFixed(0)} MXN/km',
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    HapticService.success();

    try {
      await _eventService.sendDriverCounterOffer(
        bidId: bidId,
        proposedPrice: finalPrice,
      );

      // Update the local request to reflect driver_status = counter_offered
      setState(() {
        final idx = _requests.indexWhere((r) => r['bid_id'] == bidId);
        if (idx != -1) {
          _requests[idx]['bid_driver_status'] = 'counter_offered';
          _requests[idx]['proposed_price_per_km'] = finalPrice;
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Contra-oferta enviada: \$${finalPrice.toStringAsFixed(0)} MXN/km',
            ),
            backgroundColor: AppColors.warning,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
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

  Future<String?> _showRejectionDialog() async {
    String? selectedReason;
    final customController = TextEditingController();

    final reasons = [
      'No estoy disponible en esa fecha',
      'Conflicto de horario',
      'Distancia muy larga',
      'No me interesa este viaje',
      'Otro',
    ];

    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Razon del rechazo (opcional)',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ...reasons.map((reason) {
                  final isSelected = selectedReason == reason;
                  return GestureDetector(
                    onTap: () {
                      HapticService.selectionClick();
                      setModalState(() {
                        selectedReason = reason;
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary.withValues(alpha: 0.1)
                            : AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.border,
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.textTertiary,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            reason,
                            style: TextStyle(
                              color: isSelected
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                if (selectedReason == 'Otro')
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: customController,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Escribe la razon...',
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
                          borderSide: const BorderSide(color: AppColors.primary),
                        ),
                      ),
                      maxLines: 2,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, null),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            side: const BorderSide(color: AppColors.border),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            final finalReason = selectedReason == 'Otro'
                                ? customController.text
                                : (selectedReason ?? '');
                            Navigator.pop(context, finalReason);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.error,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Rechazar'),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: MediaQuery.of(context).padding.bottom),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showEventDetails(Map<String, dynamic> request) {
    HapticService.lightImpact();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _EventDetailsSheet(
        request: request,
        minPricePerKm: _minPricePerKm,
        driverVehicleSeats: _driverVehicleSeats,
        onBid: _isOverCapacity(request)
            ? null
            : () {
                Navigator.pop(context);
                _showBidDialog(request);
              },
        onReject: () {
          Navigator.pop(context);
          _rejectRequest(request);
        },
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Fecha no definida';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('d MMM yyyy', 'es').format(date);
    } catch (e) {
      return 'Fecha no definida';
    }
  }

  String _formatTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '';
    try {
      final parts = timeStr.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return timeStr;
    }
  }

  String _formatTimeAgo(String? isoDate) {
    if (isoDate == null) return '';
    try {
      final dt = DateTime.parse(isoDate);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'Justo ahora';
      if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
      if (diff.inHours < 24) return 'hace ${diff.inHours}h';
      if (diff.inDays < 7) return 'hace ${diff.inDays}d';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  String _formatBidDateTime(String? isoDate) {
    if (isoDate == null) return '';
    try {
      final dt = DateTime.parse(isoDate);
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.background,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildTabs(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1: Open events for all drivers
                    _buildOpenEventsTab(),
                    // Tab 2: Invited bids (existing)
                    _isLoading
                        ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
                        : _error != null
                            ? _buildErrorState()
                            : _requests.isEmpty
                                ? _buildEmptyInvitationsState()
                                : _buildRequestsList(),
                    // Tab 3: My bids (all statuses)
                    _buildMyBidsTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      color: AppColors.surface,
      child: Row(
        children: [
          if (!widget.embedded)
            GestureDetector(
              onTap: () {
                HapticService.lightImpact();
                Navigator.pop(context);
              },
              child: const Padding(
                padding: EdgeInsets.only(right: 10),
                child: Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textSecondary, size: 16),
              ),
            ),
          const Expanded(
            child: Text('Pujas Disponibles',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
          ),
          GestureDetector(
            onTap: () {
              HapticService.lightImpact();
              _loadRequests();
              _loadOpenEvents();
            },
            child: const Icon(Icons.refresh, color: AppColors.gold, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      color: AppColors.surface,
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorColor: AppColors.gold,
        indicatorWeight: 3,
        labelColor: AppColors.gold,
        unselectedLabelColor: AppColors.textTertiary,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        tabs: [
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Eventos Abiertos'),
                if (_openEvents.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_openEvents.length}',
                      style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Invitaciones'),
                if (_requests.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_requests.length}',
                      style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Mis Pujas'),
                if (_myBids.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_myBids.length}',
                      style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ====== OPEN EVENTS TAB ======

  Widget _buildOpenEventsTab() {
    if (_isLoadingOpen) {
      return const Center(child: CircularProgressIndicator(color: AppColors.gold));
    }

    // Filter events by search text
    final filtered = _filterText.isEmpty
        ? _openEvents
        : _openEvents.where((e) {
            final name = (e['event_name'] as String? ?? '').toLowerCase();
            final orgName = (e['organizers'] as Map?)?['company_name']?.toString().toLowerCase() ?? '';
            final itinerary = e['itinerary'] as List?;
            final stopNames = itinerary?.map((s) => (s as Map?)?['name']?.toString().toLowerCase() ?? '').join(' ') ?? '';
            final query = _filterText.toLowerCase();
            return name.contains(query) || orgName.contains(query) || stopNames.contains(query);
          }).toList();

    return Column(
      children: [
        // Search filter - compact
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: SizedBox(
            height: 36,
            child: TextField(
              controller: _filterController,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Buscar destino, organizador...',
                hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                prefixIcon: const Icon(Icons.search, color: AppColors.textTertiary, size: 16),
                prefixIconConstraints: const BoxConstraints(minWidth: 32),
                suffixIcon: _filterText.isNotEmpty
                    ? GestureDetector(
                        onTap: () { _filterController.clear(); setState(() => _filterText = ''); },
                        child: const Icon(Icons.clear, size: 14, color: AppColors.textTertiary),
                      )
                    : null,
                suffixIconConstraints: const BoxConstraints(minWidth: 28),
                filled: true,
                fillColor: AppColors.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.border.withValues(alpha: 0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.border.withValues(alpha: 0.3)),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              ),
              onChanged: (val) => setState(() => _filterText = val),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyOpenState()
              : RefreshIndicator(
                  onRefresh: _loadOpenEvents,
                  color: AppColors.gold,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      return _buildOpenEventCard(filtered[index]);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildOpenEventCard(Map<String, dynamic> event) {
    final title = event['event_name'] as String? ?? 'Evento';
    final organizer = event['organizers'] as Map<String, dynamic>?;
    final organizerName = organizer?['company_name'] ?? 'Organizador';
    final isVerified = organizer?['is_verified'] == true;
    final startDate = event['event_date'] as String?;
    final startTime = event['start_time'] as String?;
    final estimatedDistance = (event['total_distance_km'] as num?)?.toDouble();
    final passengers = event['max_passengers'] as int?;
    final itinerary = event['itinerary'] as List?;
    final alreadyBid = event['already_bid'] == true;
    final routeText = _buildRouteText(itinerary);
    final createdAt = event['created_at'] as String?;

    return GestureDetector(
      onTap: () => _showOpenEventBidDialog(event),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: alreadyBid
                ? AppColors.success.withValues(alpha: 0.3)
                : AppColors.gold.withValues(alpha: 0.15),
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: title + badge + time ago
            Row(
              children: [
                Expanded(
                  child: Text(title,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: (alreadyBid ? AppColors.success : AppColors.gold).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(alreadyBid ? 'ENVIADA' : 'ABIERTO',
                    style: TextStyle(
                      color: alreadyBid ? AppColors.success : AppColors.gold,
                      fontSize: 8, fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            // Row 2: organizer + route
            Row(
              children: [
                Text(organizerName,
                  style: const TextStyle(color: AppColors.textTertiary, fontSize: 10),
                ),
                if (isVerified) ...[
                  const SizedBox(width: 2),
                  const Icon(Icons.verified, color: AppColors.primaryCyan, size: 10),
                ],
                if (routeText.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.route, color: AppColors.success, size: 10),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(routeText,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ] else
                  const Spacer(),
              ],
            ),
            const SizedBox(height: 4),
            // Row 3: date + time + km + passengers + bid button
            Row(
              children: [
                _buildMiniChip(Icons.calendar_today, _formatDate(startDate)),
                const SizedBox(width: 8),
                if (startTime != null && startTime.isNotEmpty) ...[
                  _buildMiniChip(Icons.access_time, _formatTime(startTime)),
                  const SizedBox(width: 8),
                ],
                if (estimatedDistance != null) ...[
                  _buildMiniChip(Icons.straighten, '${estimatedDistance.toStringAsFixed(0)} km'),
                  const SizedBox(width: 8),
                ],
                if (passengers != null)
                  _buildMiniChip(Icons.event_seat, '$passengers'),
                const Spacer(),
                if (createdAt != null)
                  Text(_formatTimeAgo(createdAt),
                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 9),
                  ),
                if (!alreadyBid) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('Pujar',
                      style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Bid dialog for open events (driver initiates bid)
  Future<void> _showOpenEventBidDialog(Map<String, dynamic> event) async {
    final eventId = event['id'] as String?;
    if (eventId == null) return;

    final eventTitle = event['event_name'] ?? 'este evento';
    final distanceKm = (event['total_distance_km'] as num?)?.toDouble();
    final passengers = event['max_passengers'] as int?;

    final priceController = TextEditingController();
    double? proposedPrice;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final price = proposedPrice ?? _minPricePerKm;
          final estimatedTotal = distanceKm != null ? distanceKm * price : null;
          final toroFee = estimatedTotal != null ? estimatedTotal * 0.18 : null;
          final driverEarnings = estimatedTotal != null && toroFee != null
              ? estimatedTotal - toroFee
              : null;

          return Container(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4,
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.gavel_rounded, color: AppColors.gold, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('Enviar Puja',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('Propone tu precio por km para "$eventTitle"',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ),
                const SizedBox(height: 20),
                // Price input
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: priceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: _minPricePerKm.toStringAsFixed(0),
                      hintStyle: TextStyle(color: AppColors.textTertiary.withValues(alpha: 0.5), fontSize: 24, fontWeight: FontWeight.w700),
                      prefixIcon: const Padding(padding: EdgeInsets.only(left: 16),
                        child: Text('\$', style: TextStyle(color: AppColors.gold, fontSize: 24, fontWeight: FontWeight.w700))),
                      prefixIconConstraints: const BoxConstraints(minWidth: 40),
                      suffixText: 'MXN/km',
                      suffixStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 14),
                      filled: true, fillColor: AppColors.card,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.gold, width: 1.5)),
                    ),
                    onChanged: (val) => setModalState(() => proposedPrice = double.tryParse(val)),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('Precio minimo: \$${_minPricePerKm.toStringAsFixed(0)} MXN/km',
                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 12)),
                ),
                if (distanceKm != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.card, borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
                    ),
                    child: Column(children: [
                      _buildEstimateRow('Distancia', '${distanceKm.toStringAsFixed(0)} km'),
                      if (passengers != null)
                        _buildEstimateRow('Pasajeros', '$passengers personas'),
                      _buildEstimateRow('Tu precio/km', '\$${price.toStringAsFixed(0)} MXN'),
                      if (estimatedTotal != null) ...[
                        const Divider(color: AppColors.border, height: 16),
                        _buildEstimateRow('Precio total viaje', '\$${estimatedTotal.toStringAsFixed(0)} MXN',
                          valueBold: true),
                        if (passengers != null && passengers > 0)
                          _buildEstimateRow('Boleto por persona', '\$${(estimatedTotal / passengers).toStringAsFixed(0)} MXN'),
                        _buildEstimateRow('Comision TORO (18%)', '-\$${toroFee!.toStringAsFixed(0)} MXN', valueColor: AppColors.error),
                        const Divider(color: AppColors.border, height: 16),
                        _buildEstimateRow('Tu ganancia estimada', '\$${driverEarnings!.toStringAsFixed(0)} MXN',
                          labelStyle: const TextStyle(color: AppColors.success, fontSize: 15, fontWeight: FontWeight.w700),
                          valueColor: AppColors.success, valueBold: true),
                      ],
                    ]),
                  ),
                ],
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: const BorderSide(color: AppColors.border),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context, true),
                        icon: const Icon(Icons.gavel_rounded, size: 18),
                        label: const Text('Enviar Puja'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.gold, foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ]),
                ),
                SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
              ],
            ),
          );
        },
      ),
    );

    if (confirmed != true) return;

    final finalPrice = proposedPrice ?? _minPricePerKm;
    HapticService.success();

    try {
      final driverProvider = Provider.of<DriverProvider>(context, listen: false);
      final driver = driverProvider.driver;
      if (driver == null) throw Exception('No driver');

      await _eventService.submitBidOnOpenEvent(
        eventId: eventId,
        driverId: driver.id,
        pricePerKm: finalPrice,
      );

      // Reload to refresh badge
      _loadOpenEvents();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Puja enviada: \$${finalPrice.toStringAsFixed(0)} MXN/km'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error, behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Widget _buildEmptyOpenState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.card,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.event_busy, size: 48, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 24),
            const Text('No hay eventos abiertos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text('Cuando un organizador publique un evento, aparecera aqui para que puedas enviar tu puja.',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyInvitationsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.card,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.mail_outline, size: 48, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 24),
            const Text('No tienes invitaciones',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text('Cuando un organizador te invite directamente a un viaje, aparecera aqui.',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 48,
            color: AppColors.error,
          ),
          const SizedBox(height: 16),
          const Text(
            'Error al cargar solicitudes',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _loadRequests,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestsList() {
    return RefreshIndicator(
      onRefresh: _loadRequests,
      color: AppColors.gold,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _requests.length,
        itemBuilder: (context, index) {
          final request = _requests[index];
          return _buildBidCard(request);
        },
      ),
    );
  }

  Widget _buildBidCard(Map<String, dynamic> request) {
    final title = request['event_name'] as String? ??
        request['title'] as String? ?? 'Evento';
    final organizer = request['organizers'] as Map<String, dynamic>?;
    final organizerName = organizer?['company_name'] ??
        organizer?['contact_name'] ??
        organizer?['business_name'] ??
        'Organizador';

    final startDate = request['event_date'] as String? ??
        request['start_date'] as String?;
    final startTime = request['start_time'] as String?;
    final estimatedDistance = request['total_distance_km'] as num? ??
        request['estimated_distance_km'] as num?;
    final passengers = request['max_passengers'] as int? ??
        request['expected_passengers'] as int?;

    final itinerary = request['itinerary'] as List?;
    final organizerNotes = request['organizer_notes'] as String?;
    final overCapacity = _isOverCapacity(request);

    // Negotiation state
    final bidOrganizerStatus = request['bid_organizer_status'] as String?;
    final bidDriverStatus = request['bid_driver_status'] as String?;
    final organizerProposedPrice =
        (request['organizer_proposed_price'] as num?)?.toDouble();
    final negotiationRound = (request['negotiation_round'] as int?) ?? 0;

    final isOrganizerCounterOffer = bidOrganizerStatus == 'counter_offered';
    final isDriverCounterOffer = bidDriverStatus == 'counter_offered';

    // Determine card border color based on state
    Color borderColor;
    if (overCapacity) {
      borderColor = AppColors.error.withValues(alpha: 0.4);
    } else if (isOrganizerCounterOffer) {
      borderColor = AppColors.warning.withValues(alpha: 0.5);
    } else if (isDriverCounterOffer) {
      borderColor = AppColors.primaryCyan.withValues(alpha: 0.4);
    } else {
      borderColor = AppColors.gold.withValues(alpha: 0.3);
    }

    // Determine badge
    String badgeText;
    Color badgeColor;
    if (isOrganizerCounterOffer) {
      badgeText = 'CONTRA-OFERTA';
      badgeColor = AppColors.warning;
    } else if (isDriverCounterOffer) {
      badgeText = 'ESPERANDO';
      badgeColor = AppColors.primaryCyan;
    } else {
      badgeText = 'NUEVA';
      badgeColor = AppColors.gold;
    }

    final routeText = _buildRouteText(itinerary);

    return GestureDetector(
      onTap: () => _showEventDetails(request),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: logo + title + organizer + badge
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (isOrganizerCounterOffer ? AppColors.warning : AppColors.gold)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isOrganizerCounterOffer ? Icons.swap_horiz_rounded : Icons.gavel_rounded,
                      color: isOrganizerCounterOffer ? AppColors.warning : AppColors.gold,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                      Row(
                        children: [
                          const Icon(Icons.business, color: AppColors.textTertiary, size: 11),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(organizerName,
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(badgeText,
                    style: TextStyle(color: badgeColor, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Row 2: route inline
            if (routeText.isNotEmpty)
              Row(
                children: [
                  const Icon(Icons.route, color: AppColors.success, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(routeText,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            else if (request['pickup_location'] != null) ...[
              Row(
                children: [
                  const Icon(Icons.route, color: AppColors.success, size: 14),
                  const SizedBox(width: 6),
                  Flexible(child: Text(
                    '${request['pickup_location']}${request['dropoff_location'] != null ? '  →  ${request['dropoff_location']}' : ''}',
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  )),
                ],
              ),
            ],
            const SizedBox(height: 6),
            // Row 3: all info chips in one line
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                _buildMiniChip(Icons.calendar_today, _formatDate(startDate)),
                if (startTime != null && startTime.isNotEmpty)
                  _buildMiniChip(Icons.access_time, _formatTime(startTime)),
                if (estimatedDistance != null)
                  _buildMiniChip(Icons.straighten, '${estimatedDistance.toStringAsFixed(0)} km'),
                if (passengers != null)
                  _buildMiniChip(Icons.people, '$passengers'),
              ],
            ),
            // Capacity warning
            if (overCapacity) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock, color: AppColors.error, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tu vehiculo tiene $_driverVehicleSeats asientos. Este evento necesita ${passengers ?? 0} pasajeros.',
                        style: const TextStyle(
                          color: AppColors.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Organizer counter-offer banner
            if (isOrganizerCounterOffer && organizerProposedPrice != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.price_change_rounded,
                      color: AppColors.warning,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Contra-oferta del organizador',
                            style: TextStyle(
                              color: AppColors.warning,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '\$${organizerProposedPrice.toStringAsFixed(0)} MXN/km',
                            style: const TextStyle(
                              color: AppColors.warning,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (negotiationRound > 0)
                            Text(
                              'Ronda $negotiationRound de negociacion',
                              style: const TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Driver waiting status
            if (isDriverCounterOffer) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primaryCyan.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.primaryCyan.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primaryCyan.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Esperando respuesta del organizador...',
                        style: TextStyle(
                          color: AppColors.primaryCyan,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Organizer notes
            if (organizerNotes != null && organizerNotes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primaryCyan.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.primaryCyan.withValues(alpha: 0.15),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.message_outlined,
                      color: AppColors.primaryCyan,
                      size: 14,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        organizerNotes,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            // Action buttons based on state
            _buildCardActions(
              request: request,
              isOrganizerCounterOffer: isOrganizerCounterOffer,
              isDriverCounterOffer: isDriverCounterOffer,
              overCapacity: overCapacity,
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the action buttons area for a bid card depending on negotiation state.
  Widget _buildCardActions({
    required Map<String, dynamic> request,
    required bool isOrganizerCounterOffer,
    required bool isDriverCounterOffer,
    required bool overCapacity,
  }) {
    // State: organizer sent counter-offer -> show 3 buttons
    if (isOrganizerCounterOffer) {
      return Column(
        children: [
          // Primary: Accept counter-offer price
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                HapticService.lightImpact();
                _acceptCounterOffer(request);
              },
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Aceptar Precio'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Secondary row: Counter-offer + Reject
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    HapticService.lightImpact();
                    _rejectRequest(request);
                  },
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Rechazar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticService.lightImpact();
                    _showDriverCounterOfferDialog(request);
                  },
                  icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                  label: const Text('Contra-oferta'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.warning,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    // State: driver already sent counter-offer -> no action buttons, just waiting
    if (isDriverCounterOffer) {
      return const SizedBox.shrink();
    }

    // Default state: pending -> Rechazar | Enviar Puja
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _rejectRequest(request),
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Rechazar'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: overCapacity ? null : () => _showBidDialog(request),
            icon: Icon(
              overCapacity ? Icons.lock : Icons.gavel_rounded,
              size: 16,
            ),
            label: Text(overCapacity ? 'Sin capacidad' : 'Enviar Puja'),
            style: ElevatedButton.styleFrom(
              backgroundColor: overCapacity
                  ? AppColors.textTertiary
                  : AppColors.gold,
              foregroundColor: overCapacity
                  ? AppColors.textSecondary
                  : Colors.black,
              disabledBackgroundColor: AppColors.card,
              disabledForegroundColor: AppColors.textTertiary,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }

  /// Mini itinerary timeline for the bid card
  Widget _buildMiniItinerary(List itinerary) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: List.generate(itinerary.length, (index) {
          final stop = itinerary[index] as Map<String, dynamic>? ?? {};
          final name = stop['name'] as String? ?? 'Parada ${index + 1}';
          final time = stop['scheduled_time'] as String?;
          final isFirst = index == 0;
          final isLast = index == itinerary.length - 1;

          Color dotColor;
          IconData dotIcon;
          if (isFirst) {
            dotColor = AppColors.success;
            dotIcon = Icons.trip_origin;
          } else if (isLast) {
            dotColor = AppColors.error;
            dotIcon = Icons.place;
          } else {
            dotColor = AppColors.primaryCyan;
            dotIcon = Icons.circle;
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 20,
                child: Column(
                  children: [
                    Icon(dotIcon, color: dotColor, size: isFirst || isLast ? 14 : 8),
                    if (!isLast)
                      Container(
                        width: 1.5,
                        height: 16,
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        color: AppColors.border,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            color: (isFirst || isLast)
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: (isFirst || isLast)
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (time != null && time.isNotEmpty)
                        Text(
                          time,
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.textTertiary, size: 14),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// Inline route text: "Tepic → Compostela" from itinerary
  String _buildRouteText(List? itinerary) {
    if (itinerary == null || itinerary.isEmpty) return '';
    final names = itinerary
        .map((s) => (s as Map<String, dynamic>?)?['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    if (names.isEmpty) return '';
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names.first}  →  ${names.last}';
    return '${names.first}  →  ${names.last}';
  }

  /// Small logo widget reused in compact cards
  Widget _buildSmallLogo(String? logoUrl, double size) {
    if (logoUrl != null && logoUrl.isNotEmpty) {
      return Image.network(logoUrl, width: size, height: size, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildLogoPlaceholder(size),
      );
    }
    return _buildLogoPlaceholder(size);
  }

  Widget _buildLogoPlaceholder(double size) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.business, color: AppColors.gold, size: size * 0.5),
    );
  }

  /// Compact chip for inline info display
  Widget _buildMiniChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.textTertiary, size: 12),
        const SizedBox(width: 3),
        Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      ],
    );
  }

  // ====== MIS PUJAS TAB ======

  Widget _buildMyBidsTab() {
    if (_isLoadingMyBids) {
      return const Center(child: CircularProgressIndicator(color: AppColors.gold));
    }

    if (_myBids.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.gavel_outlined, size: 48, color: AppColors.textTertiary.withOpacity(0.5)),
              const SizedBox(height: 16),
              const Text(
                'No tienes pujas enviadas',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 6),
              const Text(
                'Busca eventos abiertos y envía tu primera puja',
                style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Separate by status
    final won = _myBids.where((b) => b['organizer_status'] == 'selected' && b['is_winning_bid'] == true).toList();
    final pending = _myBids.where((b) => b['organizer_status'] == 'pending' && b['driver_status'] == 'accepted').toList();
    final counterOffer = _myBids.where((b) => b['organizer_status'] == 'counter_offered' || b['driver_status'] == 'counter_offered').toList();
    final rejected = _myBids.where((b) => b['organizer_status'] == 'rejected' || b['driver_status'] == 'rejected').toList();

    return RefreshIndicator(
      onRefresh: _loadMyBids,
      color: AppColors.gold,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          // Won bids first (most important)
          if (won.isNotEmpty) ...[
            _buildBidSectionHeader('Pujas Ganadas', Icons.emoji_events, AppColors.success, won.length),
            const SizedBox(height: 8),
            ...won.map((b) => _buildMyBidCard(b, 'won')),
            const SizedBox(height: 16),
          ],
          // Counter-offers (needs action)
          if (counterOffer.isNotEmpty) ...[
            _buildBidSectionHeader('Contra-ofertas', Icons.swap_horiz, Colors.orange, counterOffer.length),
            const SizedBox(height: 8),
            ...counterOffer.map((b) => _buildMyBidCard(b, 'counter')),
            const SizedBox(height: 16),
          ],
          // Pending (waiting for organizer)
          if (pending.isNotEmpty) ...[
            _buildBidSectionHeader('Esperando Respuesta', Icons.hourglass_empty, AppColors.gold, pending.length),
            const SizedBox(height: 8),
            ...pending.map((b) => _buildMyBidCard(b, 'pending')),
            const SizedBox(height: 16),
          ],
          // Rejected
          if (rejected.isNotEmpty) ...[
            _buildBidSectionHeader('Rechazadas', Icons.cancel_outlined, AppColors.error, rejected.length),
            const SizedBox(height: 8),
            ...rejected.map((b) => _buildMyBidCard(b, 'rejected')),
          ],
        ],
      ),
    );
  }

  Widget _buildBidSectionHeader(String title, IconData icon, Color color, int count) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }

  Widget _buildMyBidCard(Map<String, dynamic> bid, String type) {
    final eventName = bid['event_name'] as String? ?? 'Evento';
    final orgName = bid['organizer_name'] as String? ?? 'Organizador';
    final orgLogo = bid['organizer_logo'] as String?;
    final price = (bid['proposed_price_per_km'] as num?)?.toDouble();
    final totalDist = (bid['total_distance_km'] as num?)?.toDouble() ?? 0;
    final totalPrice = price != null ? price * totalDist : null;
    final eventDate = bid['event_date'] as String?;
    final startTime = bid['start_time'] as String?;
    final eventId = bid['event_id'] as String?;
    final itinerary = bid['itinerary'] as List?;

    // Route text
    String routeText = '';
    if (itinerary != null && itinerary.isNotEmpty) {
      final first = (itinerary.first as Map?)?['name']?.toString() ?? '';
      String last = '';
      if (itinerary.length > 1) {
        last = (itinerary.last as Map?)?['name']?.toString() ?? '';
      }
      routeText = last.isNotEmpty ? '$first → $last' : first;
    }

    // Status colors and labels
    Color accentColor;
    String statusLabel;
    IconData statusIcon;
    switch (type) {
      case 'won':
        accentColor = AppColors.success;
        statusLabel = 'GANADA';
        statusIcon = Icons.emoji_events;
        break;
      case 'counter':
        accentColor = Colors.orange;
        statusLabel = 'CONTRA-OFERTA';
        statusIcon = Icons.swap_horiz;
        break;
      case 'rejected':
        accentColor = AppColors.error;
        statusLabel = 'RECHAZADA';
        statusIcon = Icons.cancel;
        break;
      default:
        accentColor = AppColors.gold;
        statusLabel = 'ENVIADA';
        statusIcon = Icons.hourglass_empty;
    }

    return GestureDetector(
      onTap: type == 'won' && eventId != null
          ? () {
              HapticService.mediumImpact();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TourismDriverHomeScreen(eventId: eventId),
                ),
              ).then((_) => _loadMyBids());
            }
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: accentColor.withOpacity(type == 'won' ? 0.5 : 0.3),
            width: type == 'won' ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: name + status badge
            Row(
              children: [
                // Organizer logo
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _buildSmallLogo(orgLogo, 34),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        eventName,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        orgName,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 12, color: accentColor),
                      const SizedBox(width: 4),
                      Text(
                        statusLabel,
                        style: TextStyle(color: accentColor, fontSize: 9, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Route
            if (routeText.isNotEmpty)
              Row(
                children: [
                  const Icon(Icons.route, color: AppColors.success, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(routeText,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 6),
            // Info chips
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                if (eventDate != null) _buildMiniChip(Icons.calendar_today, _formatDate(eventDate)),
                if (startTime != null) _buildMiniChip(Icons.access_time, _formatTime(startTime)),
                if (totalDist > 0) _buildMiniChip(Icons.straighten, '${totalDist.toStringAsFixed(0)} km'),
              ],
            ),
            // Price info
            if (price != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Text(
                      '\$${price.toStringAsFixed(2)}/km',
                      style: TextStyle(color: accentColor, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    if (totalPrice != null) ...[
                      const Spacer(),
                      Text(
                        'Total: \$${totalPrice.toStringAsFixed(0)}',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            // Won bid: action button
            if (type == 'won' && eventId != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticService.mediumImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TourismDriverHomeScreen(eventId: eventId),
                      ),
                    ).then((_) => _loadMyBids());
                  },
                  icon: const Icon(Icons.emoji_events, size: 16),
                  label: const Text('Ver Evento', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet showing full event details with itinerary timeline.
class _EventDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> request;
  final double minPricePerKm;
  final int driverVehicleSeats;
  final VoidCallback? onBid;
  final VoidCallback onReject;

  const _EventDetailsSheet({
    required this.request,
    required this.minPricePerKm,
    required this.driverVehicleSeats,
    required this.onBid,
    required this.onReject,
  });

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Fecha no definida';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('EEEE d MMMM yyyy', 'es').format(date);
    } catch (e) {
      return 'Fecha no definida';
    }
  }

  String _formatTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '';
    try {
      final parts = timeStr.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return timeStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = request['event_name'] as String? ??
        request['title'] as String? ?? 'Evento';
    final description = request['event_description'] as String? ??
        request['description'] as String?;
    final organizer = request['organizers'] as Map<String, dynamic>?;
    final organizerName = organizer?['company_name'] ??
        organizer?['contact_name'] ??
        organizer?['business_name'] ??
        'Organizador';
    final organizerPhone = organizer?['phone'] as String?;

    final startDate = request['event_date'] as String? ??
        request['start_date'] as String?;
    final endDate = request['end_date'] as String?;
    final startTime = request['start_time'] as String?;
    final endTime = request['end_time'] as String?;

    final itinerary = request['itinerary'] as List?;
    final estimatedDistance = request['total_distance_km'] as num? ??
        request['estimated_distance_km'] as num?;
    final passengers = request['max_passengers'] as int? ??
        request['expected_passengers'] as int?;
    final organizerNotes = request['organizer_notes'] as String?;
    final eventType = request['event_type'] as String?;
    final serviceType = request['service_type'] as String?;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + type badge
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (eventType != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryCyan.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            eventType,
                            style: const TextStyle(
                              color: AppColors.primaryCyan,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (description != null && description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // Event Info
                  _buildSectionTitle('Informacion del Evento'),
                  const SizedBox(height: 12),
                  _buildInfoCard([
                    _buildInfoRow(
                      Icons.calendar_today,
                      'Fecha',
                      _formatDate(startDate),
                    ),
                    if (endDate != null && endDate != startDate)
                      _buildInfoRow(Icons.event, 'Fecha fin', _formatDate(endDate)),
                    if (startTime != null && startTime.isNotEmpty)
                      _buildInfoRow(
                        Icons.access_time,
                        'Horario',
                        '${_formatTime(startTime)}${endTime != null && endTime.isNotEmpty ? ' - ${_formatTime(endTime)}' : ''}',
                      ),
                    if (serviceType != null)
                      _buildInfoRow(Icons.category, 'Tipo de servicio', serviceType),
                    if (passengers != null)
                      _buildInfoRow(
                        Icons.people,
                        'Pasajeros',
                        '$passengers personas',
                      ),
                    if (estimatedDistance != null)
                      _buildInfoRow(
                        Icons.route,
                        'Distancia total',
                        '${estimatedDistance.toStringAsFixed(0)} km',
                      ),
                  ]),
                  const SizedBox(height: 20),

                  // Itinerary Timeline
                  if (itinerary != null && itinerary.isNotEmpty) ...[
                    _buildSectionTitle('Itinerario (${itinerary.length} paradas)'),
                    const SizedBox(height: 12),
                    _buildItineraryTimeline(itinerary),
                    const SizedBox(height: 20),
                  ],

                  // Organizer
                  _buildSectionTitle('Organizador'),
                  const SizedBox(height: 12),
                  _buildInfoCard([
                    _buildInfoRow(Icons.business, 'Empresa', organizerName),
                    if (organizerPhone != null && organizerPhone.isNotEmpty)
                      _buildInfoRow(Icons.phone, 'Telefono', organizerPhone),
                  ]),

                  // Organizer notes
                  if (organizerNotes != null && organizerNotes.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _buildSectionTitle('Mensaje del Organizador'),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primaryCyan.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primaryCyan.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        organizerNotes,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],

                  // Capacity warning
                  if (driverVehicleSeats > 0 && passengers != null && passengers > driverVehicleSeats) ...[
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock, color: AppColors.error, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Capacidad insuficiente',
                                  style: TextStyle(
                                    color: AppColors.error,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Tu vehiculo tiene $driverVehicleSeats asientos pero este evento necesita $passengers pasajeros. No puedes enviar puja.',
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
                    ),
                  ],

                  // Pricing hint
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.gold.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: AppColors.gold,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Propone tu precio por km al enviar tu puja. Precio minimo de mercado: \$${minPricePerKm.toStringAsFixed(0)} MXN/km',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          // Action buttons
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(
                top: BorderSide(color: AppColors.border.withValues(alpha: 0.5)),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onReject,
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Rechazar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: onBid,
                      icon: Icon(
                        onBid == null ? Icons.lock : Icons.gavel_rounded,
                        size: 18,
                      ),
                      label: Text(onBid == null ? 'Sin capacidad' : 'Enviar Puja'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: onBid == null
                            ? AppColors.textTertiary
                            : AppColors.gold,
                        foregroundColor: onBid == null
                            ? AppColors.textSecondary
                            : Colors.black,
                        disabledBackgroundColor: AppColors.card,
                        disabledForegroundColor: AppColors.textTertiary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItineraryTimeline(List itinerary) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: List.generate(itinerary.length, (index) {
          final stop = itinerary[index] as Map<String, dynamic>? ?? {};
          final name = stop['name'] as String? ?? 'Parada ${index + 1}';
          final address = stop['address'] as String?;
          final time = stop['scheduled_time'] as String?;
          final duration = stop['duration_minutes'] as int?;
          final isFirst = index == 0;
          final isLast = index == itinerary.length - 1;

          Color dotColor;
          if (isFirst) {
            dotColor = AppColors.success;
          } else if (isLast) {
            dotColor = AppColors.error;
          } else {
            dotColor = AppColors.primaryCyan;
          }

          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Timeline dot + line
                  SizedBox(
                    width: 24,
                    child: Column(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: dotColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: dotColor.withValues(alpha: 0.4),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                        if (!isLast)
                          Container(
                            width: 2,
                            height: 40,
                            color: AppColors.border,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Stop info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: (isFirst || isLast)
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                            if (time != null && time.isNotEmpty)
                              Text(
                                time,
                                style: const TextStyle(
                                  color: AppColors.textTertiary,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                        if (address != null && address.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              address,
                              style: const TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 12,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (duration != null && duration > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '$duration min de parada',
                              style: const TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        if (!isLast) const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildInfoCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value, {
    Color? iconColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: iconColor ?? AppColors.textTertiary,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
