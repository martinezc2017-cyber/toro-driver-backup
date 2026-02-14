import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../providers/driver_provider.dart';
import '../../services/tourism_event_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';
import 'tourism_driver_home_screen.dart';

/// Screen for drivers to view and manage all their bid requests.
///
/// Shows:
/// - Pending bids that need a response (accept/reject/counter)
/// - Counter-offers from organizers
/// - History of accepted, rejected, and selected bids
///
/// All text in Spanish for Mexico market.
class DriverBidScreen extends StatefulWidget {
  const DriverBidScreen({super.key});

  @override
  State<DriverBidScreen> createState() => _DriverBidScreenState();
}

class _DriverBidScreenState extends State<DriverBidScreen>
    with SingleTickerProviderStateMixin {
  final TourismEventService _eventService = TourismEventService();

  List<Map<String, dynamic>> _allBids = [];
  bool _isLoading = true;
  String? _error;
  RealtimeChannel? _bidsChannel;
  double _minPricePerKm = 10.0;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadMinPrice();
    _loadBids();
  }

  @override
  void dispose() {
    _tabController.dispose();
    if (_bidsChannel != null) {
      Supabase.instance.client.removeChannel(_bidsChannel!);
      _bidsChannel = null;
    }
    super.dispose();
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

  Future<void> _loadBids() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final driverProvider =
          Provider.of<DriverProvider>(context, listen: false);
      final driver = driverProvider.driver;

      if (driver == null) {
        setState(() {
          _isLoading = false;
          _error = 'No hay conductor conectado';
        });
        return;
      }

      final bids = await _eventService.getDriverBids(driver.id);

      if (mounted) {
        setState(() {
          _allBids = bids;
          _isLoading = false;
        });

        _subscribeToRealtime(driver.id);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Error al cargar pujas: $e';
        });
      }
    }
  }

  void _subscribeToRealtime(String driverId) {
    if (_bidsChannel != null) {
      Supabase.instance.client.removeChannel(_bidsChannel!);
      _bidsChannel = null;
    }
    _bidsChannel = _eventService.subscribeToDriverBids(
      driverId: driverId,
      onBidUpdate: (_) {
        if (mounted) _loadBids();
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Bid categories
  // ---------------------------------------------------------------------------

  List<Map<String, dynamic>> get _actionRequired {
    return _allBids.where((b) {
      final driverStatus = b['driver_status'] as String? ?? '';
      final organizerStatus = b['organizer_status'] as String? ?? '';
      // Needs action: pending bid or organizer sent counter-offer
      return (driverStatus == 'pending' && organizerStatus == 'pending') ||
          (organizerStatus == 'counter_offered');
    }).toList();
  }

  List<Map<String, dynamic>> get _activeBids {
    return _allBids.where((b) {
      final driverStatus = b['driver_status'] as String? ?? '';
      final organizerStatus = b['organizer_status'] as String? ?? '';
      // Active: driver accepted/counter-offered and waiting for organizer
      return (driverStatus == 'accepted' && organizerStatus == 'pending') ||
          (driverStatus == 'counter_offered' &&
              organizerStatus != 'counter_offered') ||
          (organizerStatus == 'selected' && b['is_winning_bid'] == true);
    }).toList();
  }

  List<Map<String, dynamic>> get _historyBids {
    return _allBids.where((b) {
      final driverStatus = b['driver_status'] as String? ?? '';
      final organizerStatus = b['organizer_status'] as String? ?? '';
      return driverStatus == 'rejected' || organizerStatus == 'rejected';
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _showBidDialog(Map<String, dynamic> bid) async {
    final bidId = bid['id'] as String?;
    if (bidId == null) return;

    final eventName = bid['event_name'] ?? 'Evento';
    final distanceKm =
        (bid['total_distance_km'] as num?)?.toDouble();
    final passengers = bid['max_passengers'] as int?;

    final priceController = TextEditingController();
    double? proposedPrice;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final price = proposedPrice ?? _minPricePerKm;
          final estimatedTotal =
              distanceKm != null ? distanceKm * price : null;
          final toroFee =
              estimatedTotal != null ? estimatedTotal * 0.18 : null;
          final driverEarnings = estimatedTotal != null && toroFee != null
              ? estimatedTotal - toroFee
              : null;

          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
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
                      'Propone tu precio por km para "$eventName"',
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
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: _minPricePerKm.toStringAsFixed(0),
                        hintStyle: TextStyle(
                          color: AppColors.textTertiary
                              .withValues(alpha: 0.5),
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
                        prefixIconConstraints:
                            const BoxConstraints(minWidth: 40),
                        suffixText: 'MXN/km',
                        suffixStyle: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 14,
                        ),
                        filled: true,
                        fillColor: AppColors.card,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide:
                              const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide:
                              const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                              color: AppColors.gold, width: 1.5),
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
                  // Earnings estimate
                  if (distanceKm != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color:
                              AppColors.success.withValues(alpha: 0.2),
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
                            const Divider(
                                color: AppColors.border, height: 16),
                            _buildEstimateRow(
                              'Total estimado',
                              '\$${estimatedTotal.toStringAsFixed(0)} MXN',
                            ),
                            _buildEstimateRow(
                              'Comision TORO (18%)',
                              '-\$${toroFee!.toStringAsFixed(0)} MXN',
                              valueColor: AppColors.error,
                            ),
                            const Divider(
                                color: AppColors.border, height: 16),
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
                              side: const BorderSide(
                                  color: AppColors.border),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14),
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
                            onPressed: () =>
                                Navigator.pop(context, true),
                            icon: const Icon(Icons.gavel_rounded,
                                size: 18),
                            label: const Text('Enviar Puja'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.gold,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14),
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
                  SizedBox(
                      height:
                          MediaQuery.of(context).padding.bottom + 8),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (confirmed != true) return;

    final finalPrice = proposedPrice ?? _minPricePerKm;

    if (finalPrice < _minPricePerKm) {
      _showSnack(
        'El precio minimo es \$${_minPricePerKm.toStringAsFixed(0)} MXN/km',
        AppColors.error,
      );
      return;
    }

    HapticService.success();

    try {
      final eventId = bid['event_id'] as String?;
      if (eventId == null) throw Exception('event_id no encontrado');

      await _eventService.respondToVehicleRequest(
        eventId,
        true,
        bidId: bidId,
        pricePerKm: finalPrice,
      );

      _showSnack(
        'Puja enviada: \$${finalPrice.toStringAsFixed(0)} MXN/km',
        AppColors.success,
      );

      _loadBids();
    } catch (e) {
      _showSnack('Error: $e', AppColors.error);
    }
  }

  Future<void> _rejectBid(Map<String, dynamic> bid) async {
    final bidId = bid['id'] as String?;
    final eventId = bid['event_id'] as String?;
    if (bidId == null || eventId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Rechazar Puja',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          '¿Rechazar la solicitud para "${bid['event_name'] ?? 'este evento'}"?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    HapticService.lightImpact();

    try {
      await _eventService.respondToVehicleRequest(
        eventId,
        false,
        bidId: bidId,
        reason: 'Rechazado por el chofer',
      );

      _showSnack('Puja rechazada', AppColors.textTertiary);
      _loadBids();
    } catch (e) {
      _showSnack('Error: $e', AppColors.error);
    }
  }

  Future<void> _acceptCounterOffer(Map<String, dynamic> bid) async {
    final bidId = bid['id'] as String?;
    if (bidId == null) return;

    final organizerPrice =
        (bid['organizer_proposed_price'] as num?)?.toDouble();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Aceptar Contra-oferta',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'El organizador propone \$${organizerPrice?.toStringAsFixed(2) ?? '?'} MXN/km',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 16, color: AppColors.success),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Al aceptar, quedaras asignado al evento',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
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
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                TextButton.styleFrom(foregroundColor: AppColors.success),
            child: const Text(
              'Aceptar',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    HapticService.success();

    try {
      await _eventService.acceptCounterOffer(bidId);

      _showSnack(
        organizerPrice != null
            ? 'Contra-oferta aceptada: \$${organizerPrice.toStringAsFixed(0)} MXN/km'
            : 'Contra-oferta aceptada',
        AppColors.success,
      );
      _loadBids();
    } catch (e) {
      _showSnack('Error: $e', AppColors.error);
    }
  }

  Future<void> _showDriverCounterOfferDialog(
      Map<String, dynamic> bid) async {
    final bidId = bid['id'] as String?;
    if (bidId == null) return;

    final organizerPrice =
        (bid['organizer_proposed_price'] as num?)?.toDouble();
    final round = (bid['negotiation_round'] as int?) ?? 0;
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
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.warning
                                .withValues(alpha: 0.15),
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
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
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
                      padding:
                          const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.warning
                              .withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.warning
                                .withValues(alpha: 0.2),
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TextField(
                      controller: priceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                              decimal: true),
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
                          color: AppColors.textTertiary
                              .withValues(alpha: 0.5),
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
                        prefixIconConstraints:
                            const BoxConstraints(minWidth: 40),
                        suffixText: 'MXN/km',
                        suffixStyle: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 14,
                        ),
                        filled: true,
                        fillColor: AppColors.card,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                              color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                              color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                              color: AppColors.warning, width: 1.5),
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                Navigator.pop(context, false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor:
                                  AppColors.textSecondary,
                              side: const BorderSide(
                                  color: AppColors.border),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                Navigator.pop(context, true),
                            icon: const Icon(
                                Icons.swap_horiz_rounded,
                                size: 18),
                            label:
                                const Text('Enviar Contra-oferta'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.warning,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                      height:
                          MediaQuery.of(context).padding.bottom + 8),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (confirmed != true) return;

    final finalPrice = proposedPrice ?? _minPricePerKm;

    if (finalPrice < _minPricePerKm) {
      _showSnack(
        'El precio minimo es \$${_minPricePerKm.toStringAsFixed(0)} MXN/km',
        AppColors.error,
      );
      return;
    }

    HapticService.success();

    try {
      await _eventService.sendDriverCounterOffer(
        bidId: bidId,
        proposedPrice: finalPrice,
      );

      _showSnack(
        'Contra-oferta enviada: \$${finalPrice.toStringAsFixed(0)} MXN/km',
        AppColors.warning,
      );
      _loadBids();
    } catch (e) {
      _showSnack('Error: $e', AppColors.error);
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
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

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      const months = [
        '',
        'Ene',
        'Feb',
        'Mar',
        'Abr',
        'May',
        'Jun',
        'Jul',
        'Ago',
        'Sep',
        'Oct',
        'Nov',
        'Dic',
      ];
      return '${date.day} ${months[date.month]} ${date.year}';
    } catch (_) {
      return dateStr;
    }
  }

  String _formatTime(String? timeStr) {
    if (timeStr == null) return '';
    // timeStr can be "09:00:00" or a full ISO date
    try {
      if (timeStr.contains('T')) {
        final date = DateTime.parse(timeStr);
        return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      }
      return timeStr.substring(0, 5); // "09:00"
    } catch (_) {
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

  String _bidStatusLabel(Map<String, dynamic> bid) {
    final driverStatus = bid['driver_status'] as String? ?? '';
    final organizerStatus = bid['organizer_status'] as String? ?? '';

    if (organizerStatus == 'selected' && bid['is_winning_bid'] == true) {
      return 'GANADOR';
    }
    if (organizerStatus == 'counter_offered') {
      return 'Contra-oferta del organizador';
    }
    if (driverStatus == 'counter_offered') {
      return 'Esperando respuesta';
    }
    if (driverStatus == 'accepted' && organizerStatus == 'pending') {
      return 'Puja enviada';
    }
    if (driverStatus == 'pending') {
      return 'Pendiente - Responde';
    }
    if (driverStatus == 'rejected') {
      return 'Rechazada por ti';
    }
    if (organizerStatus == 'rejected') {
      return 'Rechazada por organizador';
    }
    return driverStatus;
  }

  Color _bidStatusColor(Map<String, dynamic> bid) {
    final driverStatus = bid['driver_status'] as String? ?? '';
    final organizerStatus = bid['organizer_status'] as String? ?? '';

    if (organizerStatus == 'selected' && bid['is_winning_bid'] == true) {
      return AppColors.success;
    }
    if (organizerStatus == 'counter_offered') {
      return AppColors.warning;
    }
    if (driverStatus == 'counter_offered') {
      return AppColors.info;
    }
    if (driverStatus == 'accepted' && organizerStatus == 'pending') {
      return AppColors.primary;
    }
    if (driverStatus == 'pending') {
      return AppColors.gold;
    }
    return AppColors.error;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Mis Pujas',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.gold,
          labelColor: AppColors.gold,
          unselectedLabelColor: AppColors.textTertiary,
          labelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Nuevas'),
                  if (_actionRequired.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_actionRequired.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Activas'),
                  if (_activeBids.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_activeBids.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Tab(text: 'Historial'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold),
            )
          : _error != null
              ? _buildErrorState()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildBidList(_actionRequired, isActionRequired: true),
                    _buildBidList(_activeBids),
                    _buildBidList(_historyBids, isHistory: true),
                  ],
                ),
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
                size: 48,
                color: AppColors.error.withValues(alpha: 0.7)),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Error desconocido',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadBids,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBidList(
    List<Map<String, dynamic>> bids, {
    bool isActionRequired = false,
    bool isHistory = false,
  }) {
    if (bids.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isHistory
                    ? Icons.history
                    : isActionRequired
                        ? Icons.notifications_none
                        : Icons.local_offer_outlined,
                size: 48,
                color: AppColors.textTertiary.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                isHistory
                    ? 'Sin historial de pujas'
                    : isActionRequired
                        ? 'Sin pujas pendientes'
                        : 'Sin pujas activas',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                isActionRequired
                    ? 'Cuando un organizador te solicite, aparecera aqui'
                    : 'Tus pujas enviadas y ganadas aparecen aqui',
                style: const TextStyle(
                    color: AppColors.textTertiary, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.gold,
      backgroundColor: AppColors.surface,
      onRefresh: _loadBids,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: bids.length,
        itemBuilder: (context, index) => _buildBidCard(
          bids[index],
          isActionRequired: isActionRequired,
          isHistory: isHistory,
        ),
      ),
    );
  }

  Widget _buildBidCard(
    Map<String, dynamic> bid, {
    bool isActionRequired = false,
    bool isHistory = false,
  }) {
    final eventName = bid['event_name'] ?? 'Evento';
    final organizerName = bid['organizer_name'] ?? 'Organizador';
    final organizerVerified = bid['organizer_verified'] == true;
    final eventDate = bid['event_date'] as String?;
    final startTime = bid['start_time'] as String?;
    final distanceKm =
        (bid['total_distance_km'] as num?)?.toDouble();
    final passengers = bid['max_passengers'] as int?;
    final totalSeats = bid['total_seats'] as int?;
    final vehicleName = bid['vehicle_name'] as String?;
    final pricePerKm =
        (bid['proposed_price_per_km'] as num?)?.toDouble();
    final organizerProposedPrice =
        (bid['organizer_proposed_price'] as num?)?.toDouble();
    final driverStatus = bid['driver_status'] as String? ?? '';
    final organizerStatus = bid['organizer_status'] as String? ?? '';
    final negotiationRound =
        (bid['negotiation_round'] as num?)?.toInt() ?? 0;
    final isWinner =
        organizerStatus == 'selected' && bid['is_winning_bid'] == true;
    final isCounterOffer = organizerStatus == 'counter_offered';

    final statusLabel = _bidStatusLabel(bid);
    final statusColor = _bidStatusColor(bid);

    // Itinerary summary
    final itinerary = bid['itinerary'] as List?;
    String routeSummary = '';
    if (itinerary != null && itinerary.isNotEmpty) {
      final first =
          (itinerary.first as Map)['name'] as String? ?? '';
      final last =
          (itinerary.last as Map)['name'] as String? ?? '';
      routeSummary = '$first → $last';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isWinner
              ? AppColors.success.withValues(alpha: 0.4)
              : isActionRequired
                  ? AppColors.gold.withValues(alpha: 0.3)
                  : AppColors.border,
          width: isWinner || isActionRequired ? 1.5 : 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with status
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isWinner
                        ? Icons.emoji_events
                        : isCounterOffer
                            ? Icons.swap_horiz
                            : driverStatus == 'pending'
                                ? Icons.notifications_active
                                : Icons.gavel,
                    size: 20,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        eventName,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            organizerName,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          if (organizerVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.verified,
                                size: 12,
                                color: AppColors.primary),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (negotiationRound > 0) ...[
                        Icon(Icons.repeat,
                            size: 10, color: statusColor),
                        const SizedBox(width: 3),
                      ],
                      Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Bid creation timestamp ──
          if (bid['created_at'] != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined, size: 11, color: AppColors.textTertiary),
                  const SizedBox(width: 4),
                  Text(
                    'Puja creada: ${_formatTimeAgo(bid['created_at'] as String?)}',
                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 10),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatBidDateTime(bid['created_at'] as String?),
                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 10),
                  ),
                ],
              ),
            ),

          // ── Organizer credential card ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            child: _buildOrganizerCredential(bid),
          ),

          // ── Event type badge ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Row(
              children: [
                _buildEventTypeBadge(bid['event_type'] as String?),
                const Spacer(),
                // Share button
                InkWell(
                  onTap: () => _shareJob(bid),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.share, size: 14, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          'Compartir',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
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

          // ── Full Itinerary (all stops) ──
          if (itinerary != null && itinerary.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: _buildFullItinerary(itinerary),
            ),
          ],

          // ── Event description/notes ──
          if ((bid['event_description'] as String?)?.isNotEmpty == true) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.notes, size: 14, color: AppColors.textTertiary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        bid['event_description'] as String,
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
            ),
          ],

          // Event details (date, time, KPIs)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date + time
                if (eventDate != null)
                  Row(
                    children: [
                      const Icon(Icons.calendar_today,
                          size: 12, color: AppColors.textTertiary),
                      const SizedBox(width: 6),
                      Text(
                        _formatDate(eventDate),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      if (startTime != null) ...[
                        const SizedBox(width: 10),
                        const Icon(Icons.access_time,
                            size: 12,
                            color: AppColors.textTertiary),
                        const SizedBox(width: 4),
                        Text(
                          _formatTime(startTime),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),

                // KPIs row
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (distanceKm != null)
                      _buildKpiChip(
                        Icons.straighten,
                        '${distanceKm.toStringAsFixed(0)} km',
                        AppColors.primary,
                      ),
                    if (passengers != null) ...[
                      const SizedBox(width: 8),
                      _buildKpiChip(
                        Icons.people,
                        '$passengers pax',
                        AppColors.warning,
                      ),
                    ],
                    if (totalSeats != null || passengers != null) ...[
                      const SizedBox(width: 8),
                      _buildKpiChip(
                        Icons.event_seat,
                        '${passengers ?? totalSeats} asientos',
                        AppColors.textTertiary,
                      ),
                    ],
                    if (vehicleName != null) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          vehicleName,
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 10,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Price section
          if (pricePerKm != null || organizerProposedPrice != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Divider(
                  color: AppColors.border.withValues(alpha: 0.5),
                  height: 1),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Row(
                children: [
                  if (pricePerKm != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Tu precio/km',
                            style: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 10,
                            ),
                          ),
                          Text(
                            '\$${pricePerKm.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (organizerProposedPrice != null &&
                      isCounterOffer)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'Organizador propone',
                            style: TextStyle(
                              color: AppColors.warning,
                              fontSize: 10,
                            ),
                          ),
                          Text(
                            '\$${organizerProposedPrice.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: AppColors.warning,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (distanceKm != null && pricePerKm != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'Total estimado',
                            style: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 10,
                            ),
                          ),
                          Text(
                            '\$${(distanceKm * pricePerKm).toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: AppColors.success,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],

          // Action buttons
          if ((isActionRequired || isWinner) && !isHistory) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: _buildActionButtons(bid),
            ),
          ] else
            const SizedBox(height: 14),
        ],
      ),
    );
  }

  Widget _buildActionButtons(Map<String, dynamic> bid) {
    final driverStatus = bid['driver_status'] as String? ?? '';
    final organizerStatus = bid['organizer_status'] as String? ?? '';

    // Won bid: show "Administrar Evento" button
    if (organizerStatus == 'selected' && bid['is_winning_bid'] == true) {
      final eventId = bid['event_id'] as String?;
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: eventId != null
              ? () {
                  HapticService.mediumImpact();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          TourismDriverHomeScreen(eventId: eventId),
                    ),
                  );
                }
              : null,
          icon: const Icon(Icons.emoji_events, size: 18),
          label: const Text(
            'Administrar Evento',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
        ),
      );
    }

    // New bid: driver hasn't responded yet
    if (driverStatus == 'pending' && organizerStatus == 'pending') {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _rejectBid(bid),
              icon: const Icon(Icons.close, size: 16),
              label: const Text(
                'Rechazar',
                style: TextStyle(fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error, width: 1),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: () => _showBidDialog(bid),
              icon: const Icon(Icons.gavel_rounded, size: 16),
              label: const Text(
                'Enviar Puja',
                style:
                    TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
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
      );
    }

    // Counter-offer from organizer: accept or counter
    if (organizerStatus == 'counter_offered') {
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _acceptCounterOffer(bid),
                  icon: const Icon(Icons.check_circle, size: 16),
                  label: const Text(
                    'Aceptar',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
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
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showDriverCounterOfferDialog(bid),
                  icon: const Icon(Icons.swap_horiz, size: 16),
                  label: const Text(
                    'Contra-oferta',
                    style: TextStyle(fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.warning,
                    side: const BorderSide(
                        color: AppColors.warning, width: 1),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _rejectBid(bid),
              icon: const Icon(Icons.close, size: 16),
              label: const Text(
                'Rechazar',
                style: TextStyle(fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textTertiary,
                side: const BorderSide(
                    color: AppColors.border, width: 1),
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildKpiChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Organizer credential compact card shown in bid
  Widget _buildOrganizerCredential(Map<String, dynamic> bid) {
    final name = bid['organizer_name'] as String? ?? 'Organizador';
    final phone = bid['organizer_contact_phone'] as String? ?? bid['organizer_phone'] as String?;
    final email = bid['organizer_email'] as String?;
    final facebook = bid['organizer_facebook'] as String?;
    final logo = bid['organizer_logo'] as String?;
    final verified = bid['organizer_verified'] == true;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          // Organizer logo
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: AppColors.surface,
              image: logo != null
                  ? DecorationImage(image: NetworkImage(logo), fit: BoxFit.cover)
                  : null,
            ),
            child: logo == null
                ? Icon(Icons.business, color: AppColors.textTertiary, size: 22)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (verified) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified, size: 14, color: AppColors.primary),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 3,
                  children: [
                    if (phone != null && phone.isNotEmpty)
                      _buildContactMiniChip(Icons.phone, phone),
                    if (email != null && email.isNotEmpty)
                      _buildContactMiniChip(Icons.email, email),
                    if (facebook != null && facebook.isNotEmpty)
                      _buildContactMiniChip(Icons.facebook, 'Facebook'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactMiniChip(IconData icon, String text) {
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
          Flexible(
            child: Text(
              text,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Event type badge
  Widget _buildEventTypeBadge(String? eventType) {
    final typeMap = {
      'tour': ('Tour', Icons.tour, const Color(0xFF3B82F6)),
      'charter': ('Transporte', Icons.directions_bus, const Color(0xFF10B981)),
      'excursion': ('Excursión', Icons.hiking, const Color(0xFFF59E0B)),
      'corporate': ('Corporativo', Icons.business, const Color(0xFF6366F1)),
      'wedding': ('Boda', Icons.favorite, const Color(0xFFEC4899)),
      'other': ('Otro', Icons.category, AppColors.textSecondary),
    };

    final entry = typeMap[eventType] ?? typeMap['other']!;
    final label = entry.$1;
    final icon = entry.$2;
    final color = entry.$3;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// Full itinerary with all stops (colored dots)
  Widget _buildFullItinerary(List itinerary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.route, size: 13, color: AppColors.textTertiary),
            SizedBox(width: 5),
            Text(
              'Itinerario',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ...itinerary.asMap().entries.map((entry) {
          final index = entry.key;
          final stop = entry.value as Map;
          final name = stop['name'] as String? ?? 'Parada ${index + 1}';
          final isFirst = index == 0;
          final isLast = index == itinerary.length - 1;

          Color dotColor;
          if (isFirst) {
            dotColor = AppColors.success;
          } else if (isLast) {
            dotColor = AppColors.error;
          } else {
            dotColor = AppColors.textTertiary;
          }

          return Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 3),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      color: isFirst || isLast ? AppColors.textPrimary : AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: isFirst || isLast ? FontWeight.w600 : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  /// Share job details via platform share sheet
  void _shareJob(Map<String, dynamic> bid) {
    final eventName = bid['event_name'] ?? 'Evento';
    final organizerName = bid['organizer_name'] ?? '';
    final organizerPhone = bid['organizer_contact_phone'] as String? ?? bid['organizer_phone'] as String? ?? '';
    final eventDate = bid['event_date'] as String?;
    final startTime = bid['start_time'] as String?;
    final distanceKm = (bid['total_distance_km'] as num?)?.toDouble();
    final passengers = bid['max_passengers'] as int?;
    final itinerary = bid['itinerary'] as List?;

    // Build route string from itinerary
    String routeStr = '';
    if (itinerary != null && itinerary.isNotEmpty) {
      routeStr = itinerary.map((s) => (s as Map)['name'] ?? '').where((n) => n.isNotEmpty).join(' → ');
    }

    final dateStr = eventDate != null ? _formatDate(eventDate) : '';
    final timeStr = startTime != null ? _formatTime(startTime) : '';

    final text = '''TRABAJO DISPONIBLE - TORO
Evento: $eventName
${dateStr.isNotEmpty ? 'Fecha: $dateStr' : ''}${timeStr.isNotEmpty ? ' | Hora: $timeStr' : ''}
${routeStr.isNotEmpty ? 'Ruta: $routeStr' : ''}
${distanceKm != null ? 'Distancia: ${distanceKm.toStringAsFixed(0)} km' : ''}${passengers != null ? ' | Pasajeros: $passengers' : ''}
${organizerName.isNotEmpty ? 'Organizador: $organizerName' : ''}${organizerPhone.isNotEmpty ? ' | Tel: $organizerPhone' : ''}
Descarga TORO Driver para pujar.''';

    HapticService.lightImpact();
    Share.share(text.trim());
  }
}
