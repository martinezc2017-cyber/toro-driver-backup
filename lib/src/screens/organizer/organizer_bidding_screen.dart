import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/supabase_config.dart';
import '../../services/organizer_service.dart';
import '../../services/tourism_event_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';

/// Screen for organizers to manage bidding process for tourism events.
///
/// Allows organizers to:
/// - Browse available vehicles
/// - Send bid requests to multiple drivers
/// - View received bids with proposed prices
/// - Compare offers in a table
/// - Select winning bid
class OrganizerBiddingScreen extends StatefulWidget {
  final String eventId;

  const OrganizerBiddingScreen({
    super.key,
    required this.eventId,
  });

  @override
  State<OrganizerBiddingScreen> createState() => _OrganizerBiddingScreenState();
}

class _OrganizerBiddingScreenState extends State<OrganizerBiddingScreen> {
  final OrganizerService _organizerService = OrganizerService();
  final TourismEventService _eventService = TourismEventService();

  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _event;

  // Tab state
  int _currentTab = 0; // 0 = browse vehicles, 1 = view bids

  // Browse vehicles state
  List<Map<String, dynamic>> _vehicles = [];
  final Set<String> _selectedVehicles = {};

  // View bids state
  List<Map<String, dynamic>> _bids = [];
  RealtimeChannel? _bidsChannel;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    if (_bidsChannel != null) {
      Supabase.instance.client.removeChannel(_bidsChannel!);
      _bidsChannel = null;
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _eventService.getEvent(widget.eventId),
        _organizerService.browseVehicles(),
        _organizerService.getBidsForEvent(widget.eventId),
      ]);

      if (mounted) {
        setState(() {
          _event = results[0] as Map<String, dynamic>?;
          _vehicles = results[1] as List<Map<String, dynamic>>;
          _bids = results[2] as List<Map<String, dynamic>>;
          _isLoading = false;
        });

        _subscribeToRealtime();
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

  void _subscribeToRealtime() {
    _bidsChannel = _organizerService.subscribeToBids(
      eventId: widget.eventId,
      onBidUpdate: (bid) {
        if (!mounted) return;
        _loadData(); // Reload bids when updated
      },
    );
  }

  Future<void> _sendBidRequests() async {
    if (_selectedVehicles.isEmpty) {
      _showError('Selecciona al menos un vehiculo');
      return;
    }

    // Confirm before sending
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Enviar Solicitudes de Puja',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          '¿Enviar solicitud de puja a ${_selectedVehicles.length} chofer(es)?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    HapticService.mediumImpact();

    try {
      await _organizerService.sendBidRequests(
        widget.eventId,
        _selectedVehicles.toList(),
      );

      if (mounted) {
        HapticService.success();
        _showSuccess('Solicitudes enviadas a ${_selectedVehicles.length} chofer(es)');
        _selectedVehicles.clear();
        setState(() => _currentTab = 1); // Switch to bids tab
        _loadData();
      }
    } catch (e) {
      HapticService.error();
      _showError('Error al enviar solicitudes: $e');
    }
  }

  Future<void> _selectWinningBid(Map<String, dynamic> bid) async {
    final bidId = bid['id'] as String?;
    final vehicleName = bid['vehicle_name'] ?? 'Vehiculo';
    final driverName = bid['driver_name'] ?? 'Chofer';
    final pricePerKm = (bid['proposed_price_per_km'] as num?)?.toDouble() ?? 0;

    if (bidId == null) {
      _showError('Datos de puja incompletos');
      return;
    }

    // Confirm selection
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Seleccionar Puja Ganadora',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '¿Confirmar selección?',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 12),
            _detailRow('Vehículo', vehicleName),
            _detailRow('Chofer', driverName),
            _detailRow('Precio/km', '\$${pricePerKm.toStringAsFixed(2)}'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 16, color: AppColors.warning),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Las demás pujas serán rechazadas automáticamente',
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
            style: TextButton.styleFrom(foregroundColor: AppColors.success),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    HapticService.mediumImpact();

    try {
      await _organizerService.selectWinningBid(bidId, widget.eventId);

      if (mounted) {
        HapticService.success();
        _showSuccess('Puja seleccionada. El evento ha sido actualizado');
        // Go back to event dashboard
        Navigator.pop(context, true);
      }
    } catch (e) {
      HapticService.error();
      _showError('Error al seleccionar puja: $e');
    }
  }

  Future<void> _showCounterOfferDialog(Map<String, dynamic> bid) async {
    final bidId = bid['id'] as String?;
    final driverName = bid['driver_name'] ?? 'Chofer';
    final currentPrice = (bid['proposed_price_per_km'] as num?)?.toDouble() ?? 0;

    if (bidId == null) {
      _showError('Datos de puja incompletos');
      return;
    }

    final controller = TextEditingController();

    final proposedPrice = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Contra-oferta',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chofer: $driverName',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_offer, size: 16, color: AppColors.textTertiary),
                  const SizedBox(width: 8),
                  const Text(
                    'Precio actual:',
                    style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                  ),
                  const Spacer(),
                  Text(
                    '\$${currentPrice.toStringAsFixed(2)}/km',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Tu propuesta (precio/km):',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                prefixText: '\$ ',
                prefixStyle: const TextStyle(
                  color: AppColors.warning,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
                suffixText: '/km',
                suffixStyle: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 14,
                ),
                filled: true,
                fillColor: AppColors.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.warning, width: 1.5),
                ),
                hintText: '0.00',
                hintStyle: const TextStyle(color: AppColors.textTertiary),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              if (value == null || value <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Ingresa un precio valido'),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }
              Navigator.pop(ctx, value);
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.warning),
            child: const Text(
              'Enviar Contra-oferta',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    if (proposedPrice == null) return;

    HapticService.lightImpact();

    try {
      await _organizerService.sendCounterOffer(
        bidId: bidId,
        proposedPrice: proposedPrice,
      );

      if (mounted) {
        HapticService.success();
        _showSuccess('Contra-oferta enviada: \$${proposedPrice.toStringAsFixed(2)}/km');
        _loadData();
      }
    } catch (e) {
      HapticService.error();
      _showError('Error al enviar contra-oferta: $e');
    }
  }

  Future<void> _acceptDriverCounterOffer(Map<String, dynamic> bid) async {
    final bidId = bid['id'] as String?;
    final driverName = bid['driver_name'] ?? 'Chofer';
    final driverPrice = (bid['driver_proposed_price'] as num?)?.toDouble() ?? 0;

    if (bidId == null) {
      _showError('Datos de puja incompletos');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Aceptar Contra-oferta del Chofer',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('Chofer', driverName),
            _detailRow('Precio propuesto', '\$${driverPrice.toStringAsFixed(2)}/km'),
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
                  Icon(Icons.info_outline, size: 16, color: AppColors.success),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Al aceptar, esta puja sera seleccionada como ganadora',
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
            style: TextButton.styleFrom(foregroundColor: AppColors.success),
            child: const Text(
              'Aceptar',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    HapticService.mediumImpact();

    try {
      await _organizerService.acceptDriverCounterOffer(
        bidId: bidId,
        eventId: widget.eventId,
        driverProposedPrice: driverPrice,
      );

      if (mounted) {
        HapticService.success();
        _showSuccess('Contra-oferta aceptada. Evento actualizado');
        Navigator.pop(context, true);
      }
    } catch (e) {
      HapticService.error();
      _showError('Error al aceptar contra-oferta: $e');
    }
  }

  void _toggleVehicleSelection(String vehicleId) {
    HapticService.lightImpact();
    setState(() {
      if (_selectedVehicles.contains(vehicleId)) {
        _selectedVehicles.remove(vehicleId);
      } else {
        _selectedVehicles.add(vehicleId);
      }
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eventName = _event?['event_name'] ?? 'Evento';

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
          'Sistema de Puja',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Event header
          _buildEventHeader(eventName),
          // Tab bar
          _buildTabBar(),
          // Content
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : _error != null
                    ? _buildErrorState()
                    : _currentTab == 0
                        ? _buildBrowseVehiclesTab()
                        : _buildViewBidsTab(),
          ),
        ],
      ),
      // Floating action button for sending bid requests (only on browse tab)
      floatingActionButton: _currentTab == 0 && _selectedVehicles.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _sendBidRequests,
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.send, size: 20),
              label: Text(
                'Enviar (${_selectedVehicles.length})',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            )
          : null,
    );
  }

  Widget _buildEventHeader(String eventName) {
    final totalDistance = (_event?['total_distance_km'] as num?)?.toDouble() ?? 0;

    return Container(
      margin: const EdgeInsets.all(16),
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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.gavel,
              color: AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eventName,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.route, size: 12, color: AppColors.textTertiary),
                    const SizedBox(width: 4),
                    Text(
                      '${totalDistance.toStringAsFixed(0)} km',
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${_bids.length} puja${_bids.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: AppColors.success,
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
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              index: 0,
              label: 'Buscar Vehículos',
              icon: Icons.directions_bus,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildTabButton(
              index: 1,
              label: 'Ver Pujas (${_bids.length})',
              icon: Icons.compare_arrows,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required int index,
    required String label,
    required IconData icon,
  }) {
    final isActive = _currentTab == index;

    return GestureDetector(
      onTap: () {
        HapticService.lightImpact();
        setState(() => _currentTab = index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? AppColors.primary : AppColors.border,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.white : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrowseVehiclesTab() {
    if (_vehicles.isEmpty) {
      return _buildEmptyState(
        icon: Icons.directions_bus_outlined,
        message: 'No se encontraron vehículos disponibles',
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      onRefresh: _loadData,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _vehicles.length,
        itemBuilder: (context, index) => _buildVehicleCard(_vehicles[index]),
      ),
    );
  }

  Widget _buildViewBidsTab() {
    if (_bids.isEmpty) {
      return _buildEmptyState(
        icon: Icons.price_check_outlined,
        message: 'Aún no hay pujas',
        subtitle: 'Envía solicitudes a choferes desde la pestaña "Buscar Vehículos"',
      );
    }

    // Separate bids by status
    final pending = _bids.where((b) =>
        b['driver_status'] == 'pending' &&
        b['organizer_status'] == 'pending').toList();
    final received = _bids.where((b) =>
        b['driver_status'] == 'accepted' &&
        b['organizer_status'] == 'pending').toList();
    final negotiating = _bids.where((b) =>
        b['organizer_status'] == 'counter_offered' ||
        b['driver_status'] == 'counter_offered').toList();
    final rejected = _bids.where((b) =>
        b['driver_status'] == 'rejected' ||
        b['organizer_status'] == 'rejected').toList();
    final selected = _bids.where((b) =>
        b['organizer_status'] == 'selected' &&
        b['is_winning_bid'] == true).toList();

    // Bids that have a price (received + negotiating) for comparison table
    final comparableBids = _bids.where((b) {
      final ds = b['driver_status'] as String? ?? '';
      final os = b['organizer_status'] as String? ?? '';
      final hasPrice = b['proposed_price_per_km'] != null;
      return hasPrice &&
          ds != 'rejected' &&
          os != 'rejected';
    }).toList();

    // Sort by price ascending (cheapest first)
    comparableBids.sort((a, b) {
      final priceA = (a['proposed_price_per_km'] as num?)?.toDouble() ?? 999;
      final priceB = (b['proposed_price_per_km'] as num?)?.toDouble() ?? 999;
      return priceA.compareTo(priceB);
    });

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          // ---- Comparison table (only if 2+ comparable bids) ----
          if (comparableBids.length >= 2) ...[
            _buildComparisonTable(comparableBids),
            const SizedBox(height: 20),
          ],

          // Selected bid (if any)
          if (selected.isNotEmpty) ...[
            _buildSectionHeader(
              title: 'Puja Seleccionada',
              icon: Icons.emoji_events,
              color: AppColors.success,
            ),
            const SizedBox(height: 8),
            ...selected.map((bid) => _buildBidCard(bid, isWinner: true)),
            const SizedBox(height: 20),
          ],

          // Negotiating (counter-offers in progress)
          if (negotiating.isNotEmpty) ...[
            _buildSectionHeader(
              title: 'En Negociacion (${negotiating.length})',
              icon: Icons.swap_horiz,
              color: AppColors.warning,
            ),
            const SizedBox(height: 8),
            ...negotiating.map(_buildBidCard),
            const SizedBox(height: 20),
          ],

          // Received bids with prices
          if (received.isNotEmpty) ...[
            _buildSectionHeader(
              title: 'Ofertas Recibidas (${received.length})',
              icon: Icons.local_offer,
              color: AppColors.primary,
            ),
            const SizedBox(height: 8),
            ...received.map(_buildBidCard),
            const SizedBox(height: 20),
          ],

          // Pending (waiting for driver response)
          if (pending.isNotEmpty) ...[
            _buildSectionHeader(
              title: 'Esperando Respuesta (${pending.length})',
              icon: Icons.hourglass_empty,
              color: AppColors.warning,
            ),
            const SizedBox(height: 8),
            ...pending.map((bid) => _buildBidCard(bid, isPending: true)),
            const SizedBox(height: 20),
          ],

          // Rejected
          if (rejected.isNotEmpty) ...[
            _buildSectionHeader(
              title: 'Rechazadas (${rejected.length})',
              icon: Icons.cancel_outlined,
              color: AppColors.error,
            ),
            const SizedBox(height: 8),
            ...rejected.map((bid) => _buildBidCard(bid, isRejected: true)),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  /// Comparison table showing all bids side-by-side sorted by price.
  ///
  /// Highlights the cheapest bid in green. Shows vehicle name, driver,
  /// seats, price/km, and estimated total for quick comparison.
  Widget _buildComparisonTable(List<Map<String, dynamic>> comparableBids) {
    final totalDistance =
        (_event?['total_distance_km'] as num?)?.toDouble() ?? 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.compare_arrows,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text(
                'Comparar Ofertas',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${comparableBids.length} ofertas',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Chofer / Vehiculo',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Asientos',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '\$/km',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Total Est.',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),

          // Table rows
          ...comparableBids.asMap().entries.map((entry) {
            final idx = entry.key;
            final bid = entry.value;
            final isCheapest = idx == 0;
            final driverName = bid['driver_name'] ?? 'Chofer';
            final vehicleName = bid['vehicle_name'] ?? '';
            final seats = bid['total_seats'] ?? 0;
            final price =
                (bid['proposed_price_per_km'] as num?)?.toDouble() ?? 0;
            final total = price * totalDistance;
            final isWinner = bid['is_winning_bid'] == true;
            final driverStatus = bid['driver_status'] as String? ?? '';
            final organizerStatus = bid['organizer_status'] as String? ?? '';
            final isNegotiating = organizerStatus == 'counter_offered' ||
                driverStatus == 'counter_offered';

            Color rowColor = Colors.transparent;
            if (isWinner) {
              rowColor = AppColors.success.withValues(alpha: 0.08);
            } else if (isCheapest) {
              rowColor = AppColors.primary.withValues(alpha: 0.06);
            } else if (isNegotiating) {
              rowColor = AppColors.warning.withValues(alpha: 0.04);
            }

            return GestureDetector(
              onTap: () {
                // If bid is actionable, scroll down or select
                if (driverStatus == 'accepted' &&
                    organizerStatus == 'pending') {
                  _selectWinningBid(bid);
                }
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: rowColor,
                  borderRadius: BorderRadius.circular(6),
                  border: isCheapest && !isWinner
                      ? Border.all(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          width: 0.5,
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    // Driver / Vehicle
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (isWinner) ...[
                                const Icon(Icons.emoji_events,
                                    size: 12, color: AppColors.success),
                                const SizedBox(width: 3),
                              ] else if (isCheapest) ...[
                                const Icon(Icons.arrow_downward,
                                    size: 12, color: AppColors.primary),
                                const SizedBox(width: 3),
                              ],
                              Flexible(
                                child: Text(
                                  driverName,
                                  style: TextStyle(
                                    color: isWinner
                                        ? AppColors.success
                                        : AppColors.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (vehicleName.isNotEmpty)
                            Text(
                              vehicleName,
                              style: const TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 10,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    // Seats
                    Expanded(
                      flex: 1,
                      child: Text(
                        '$seats',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    // Price/km
                    Expanded(
                      flex: 2,
                      child: Text(
                        '\$${price.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: isWinner
                              ? AppColors.success
                              : isCheapest
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    // Total estimated
                    Expanded(
                      flex: 2,
                      child: Text(
                        '\$${total.toStringAsFixed(0)}',
                        style: TextStyle(
                          color: isWinner
                              ? AppColors.success
                              : AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

          // Legend
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.arrow_downward,
                  size: 10, color: AppColors.primary),
              const SizedBox(width: 4),
              const Text(
                'Mas economico',
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 9,
                ),
              ),
              const Spacer(),
              Text(
                '${totalDistance.toStringAsFixed(0)} km total',
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleCard(Map<String, dynamic> vehicle) {
    final vehicleId = vehicle['id'] as String;
    final vehicleName = vehicle['vehicle_name'] ?? 'Sin nombre';
    // Always show the vehicle's actual seat capacity when browsing
    final totalSeats = vehicle['total_seats'] ?? 0;
    final ownerName = vehicle['owner_name'] ?? 'Propietario';
    final driverName = vehicle['driver_name'] ?? 'Chofer';
    final isSelected = _selectedVehicles.contains(vehicleId);

    // Check if already sent bid request
    final alreadyRequested = _bids.any((b) => b['vehicle_id'] == vehicleId);

    return GestureDetector(
      onTap: alreadyRequested ? null : () => _toggleVehicleSelection(vehicleId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.08)
              : AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : alreadyRequested
                    ? AppColors.success.withValues(alpha: 0.3)
                    : AppColors.border,
            width: isSelected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          children: [
            // Checkbox
            if (!alreadyRequested)
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.border,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, size: 12, color: AppColors.success),
                    SizedBox(width: 4),
                    Text(
                      'Enviado',
                      style: TextStyle(
                        color: AppColors.success,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(width: 12),
            // Vehicle photo
            Builder(builder: (context) {
              final imageUrls = vehicle['image_urls'] as List<dynamic>? ?? [];
              final firstImage = imageUrls.isNotEmpty ? imageUrls[0].toString() : null;
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: firstImage != null
                      ? Image.network(firstImage, fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: AppColors.surface,
                            child: const Icon(Icons.directions_bus, color: AppColors.textTertiary, size: 24),
                          ),
                        )
                      : Container(
                          color: AppColors.surface,
                          child: const Icon(Icons.directions_bus, color: AppColors.textTertiary, size: 24),
                        ),
                ),
              );
            }),
            const SizedBox(width: 10),
            // Vehicle info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vehicleName,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.event_seat,
                          size: 11, color: AppColors.textTertiary),
                      const SizedBox(width: 3),
                      Text(
                        '$totalSeats asientos',
                        style: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Dueño: $ownerName | Chofer: $driverName',
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 10,
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
    );
  }

  Widget _buildBidCard(
    Map<String, dynamic> bid, {
    bool isPending = false,
    bool isRejected = false,
    bool isWinner = false,
  }) {
    final vehicleName = bid['vehicle_name'] ?? 'Vehiculo';
    final driverName = bid['driver_name'] ?? 'Chofer';
    final bidEventMaxP = (_event?['max_passengers'] as num?)?.toInt() ?? 0;
    final totalSeats = bidEventMaxP > 0 ? bidEventMaxP : (bid['total_seats'] ?? 0);
    final pricePerKm = (bid['proposed_price_per_km'] as num?)?.toDouble();
    final notes = bid['driver_notes'] as String?;
    final organizerStatus = bid['organizer_status'] as String? ?? '';
    final driverStatus = bid['driver_status'] as String? ?? '';
    final organizerProposedPrice =
        (bid['organizer_proposed_price'] as num?)?.toDouble();
    final driverProposedPrice =
        (bid['driver_proposed_price'] as num?)?.toDouble();
    final negotiationRound =
        (bid['negotiation_round'] as num?)?.toInt() ?? 0;

    // Determine if this bid is in a negotiation state
    final isOrganizerCounterOffered = organizerStatus == 'counter_offered';
    final isDriverCounterOffered = driverStatus == 'counter_offered';
    final isNegotiating = isOrganizerCounterOffered || isDriverCounterOffered;

    // Calculate estimated total
    final totalDistance =
        (_event?['total_distance_km'] as num?)?.toDouble() ?? 0;
    final estimatedTotal =
        pricePerKm != null ? pricePerKm * totalDistance : null;

    // Event date and time
    final eventDate = _event?['event_date'] as String?;
    final startDate = _event?['start_date'] as String?;
    final dateStr = eventDate ?? startDate;

    // Color scheme based on status
    Color accentColor = AppColors.primary;
    if (isWinner) accentColor = AppColors.success;
    if (isRejected) accentColor = AppColors.error;
    if (isPending) accentColor = AppColors.warning;
    if (isNegotiating) accentColor = AppColors.warning;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.3),
          width: isWinner || isNegotiating ? 1.5 : 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isWinner
                      ? Icons.emoji_events
                      : isNegotiating
                          ? Icons.swap_horiz
                          : isPending
                              ? Icons.hourglass_empty
                              : isRejected
                                  ? Icons.cancel
                                  : Icons.local_offer,
                  size: 20,
                  color: accentColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicleName,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      driverName,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (isWinner)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle,
                          size: 12, color: AppColors.success),
                      SizedBox(width: 4),
                      Text(
                        'GANADOR',
                        style: TextStyle(
                          color: AppColors.success,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              if (isNegotiating && negotiationRound > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.repeat,
                          size: 12, color: AppColors.warning),
                      const SizedBox(width: 4),
                      Text(
                        'Ronda $negotiationRound',
                        style: const TextStyle(
                          color: AppColors.warning,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          // Event date/time
          if (dateStr != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.calendar_today,
                    size: 12, color: AppColors.textTertiary),
                const SizedBox(width: 6),
                Text(
                  _formatEventDate(dateStr),
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
                if (totalSeats > 0) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.event_seat,
                      size: 12, color: AppColors.textTertiary),
                  const SizedBox(width: 4),
                  Text(
                    '$totalSeats asientos',
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ],

          // Bid creation timestamp
          if (bid['created_at'] != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.timer_outlined, size: 11, color: AppColors.textTertiary),
                const SizedBox(width: 4),
                Text(
                  '${_formatTimeAgo(bid['created_at'] as String?)}  •  ${_formatBidDateTime(bid['created_at'] as String?)}',
                  style: const TextStyle(color: AppColors.textTertiary, fontSize: 10),
                ),
              ],
            ),
          ],

          // Price info (if available)
          if (!isPending && pricePerKm != null) ...[
            const SizedBox(height: 12),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Precio/km',
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '\$${pricePerKm.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: isRejected
                              ? AppColors.textSecondary
                              : accentColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (estimatedTotal != null)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'Total Estimado',
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '\$${estimatedTotal.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: isRejected
                                ? AppColors.textSecondary
                                : AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '(${totalDistance.toStringAsFixed(0)} km)',
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],

          // Counter-offer status: organizer sent a counter-offer
          if (isOrganizerCounterOffered &&
              organizerProposedPrice != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.arrow_forward,
                      size: 16, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Contra-oferta enviada',
                          style: TextStyle(
                            color: AppColors.warning,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '\$${organizerProposedPrice.toStringAsFixed(2)}/km',
                          style: const TextStyle(
                            color: AppColors.warning,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Esperando respuesta',
                      style: TextStyle(
                        color: AppColors.warning,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Counter-offer status: driver sent a counter-offer
          if (isDriverCounterOffered && driverProposedPrice != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.arrow_back,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Chofer propone',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '\$${driverProposedPrice.toStringAsFixed(2)}/km',
                          style: const TextStyle(
                            color: AppColors.primaryLight,
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

          // Notes
          if (notes != null && notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.notes,
                      size: 14, color: AppColors.textTertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      notes,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Action buttons for driver counter-offer: Accept or Counter
          if (isDriverCounterOffered && driverProposedPrice != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: ElevatedButton.icon(
                      onPressed: () => _acceptDriverCounterOffer(bid),
                      icon: const Icon(Icons.check_circle, size: 18),
                      label: const Text(
                        'Aceptar',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: OutlinedButton.icon(
                      onPressed: () => _showCounterOfferDialog(bid),
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: const Text(
                        'Contra-oferta',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.warning,
                        side: const BorderSide(
                            color: AppColors.warning, width: 1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],

          // Action buttons for received bids (not in negotiation)
          if (!isPending &&
              !isRejected &&
              !isWinner &&
              !isNegotiating &&
              pricePerKm != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: ElevatedButton.icon(
                      onPressed: () => _selectWinningBid(bid),
                      icon: const Icon(Icons.check_circle, size: 18),
                      label: const Text(
                        'Seleccionar Puja',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 42,
                  child: OutlinedButton.icon(
                    onPressed: () => _showCounterOfferDialog(bid),
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: const Text(
                      'Contra-oferta',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.warning,
                      side:
                          const BorderSide(color: AppColors.warning, width: 1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
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

  Widget _buildEmptyState({
    required IconData icon,
    required String message,
    String? subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 48, color: AppColors.textTertiary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
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

  String _formatEventDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final months = [
        '', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
        'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
      ];
      final day = date.day;
      final month = months[date.month];
      final year = date.year;
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      return '$day $month $year, $hour:$minute';
    } catch (_) {
      return dateStr;
    }
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$label:',
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 13,
            ),
          ),
          Text(
            value,
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
}
