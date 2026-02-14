import 'package:flutter/material.dart';
import '../../services/bus_route_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';

/// Routes tab for the organizer home screen.
///
/// Lists published bus routes from [BusRouteService.searchPublishedRoutes].
/// Each card shows origin, destination, departure date, available seats,
/// price per km, and a status badge. Tapping a card opens a bottom sheet
/// with the passenger list from [BusRouteService.getRoutePassengers].
class OrganizerRoutesTab extends StatefulWidget {
  const OrganizerRoutesTab({super.key});

  @override
  State<OrganizerRoutesTab> createState() => _OrganizerRoutesTabState();
}

class _OrganizerRoutesTabState extends State<OrganizerRoutesTab> {
  final BusRouteService _busRouteService = BusRouteService();

  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _routes = [];

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final routes = await _busRouteService.searchPublishedRoutes();

      if (mounted) {
        setState(() {
          _routes = routes;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Error al cargar rutas: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text(
          'Rutas',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
            onPressed: () {
              HapticService.lightImpact();
              _loadRoutes();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _error != null
              ? _buildErrorState()
              : _routes.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      color: AppColors.primary,
                      backgroundColor: AppColors.surface,
                      onRefresh: _loadRoutes,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        itemCount: _routes.length,
                        itemBuilder: (context, index) =>
                            _buildRouteCard(_routes[index]),
                      ),
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
              onPressed: _loadRoutes,
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

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.route_outlined,
                size: 48,
                color: AppColors.textTertiary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text(
              'No hay rutas publicadas',
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text(
              'Las rutas publicadas apareceran aqui',
              style:
                  TextStyle(color: AppColors.textTertiary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteCard(Map<String, dynamic> route) {
    final origin = route['origin'] ?? 'Origen';
    final destination = route['destination'] ?? 'Destino';
    final status = route['status'] ?? 'published';
    final departureDate = route['departure_date'] ?? '';
    final availableSeats = (route['available_seats'] as num?)?.toInt() ??
        ((route['total_seats'] as num?)?.toInt() ?? 0) -
            ((route['booked_seats'] as num?)?.toInt() ?? 0);
    final pricePerKm =
        (route['price_per_km'] as num?)?.toDouble() ?? 0;

    return GestureDetector(
      onTap: () {
        HapticService.lightImpact();
        _showRoutePassengers(route);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, width: 0.5),
          boxShadow: AppColors.shadowSubtle,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Route: origin -> destination + status badge
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.trip_origin,
                          size: 14, color: AppColors.success),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          origin,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusBadge(status),
              ],
            ),
            // Arrow connector
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Column(
                children: [
                  Container(
                    width: 1.5,
                    height: 12,
                    color: AppColors.textTertiary.withValues(alpha: 0.3),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                const Icon(Icons.location_on,
                    size: 14, color: AppColors.error),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    destination,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Bottom row: date, seats, price
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.cardSecondary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildInfoChip(
                    icon: Icons.calendar_today,
                    value: _formatDate(departureDate),
                  ),
                  _buildInfoChip(
                    icon: Icons.event_seat,
                    value: '$availableSeats disp.',
                  ),
                  _buildInfoChip(
                    icon: Icons.attach_money,
                    value: '\$${pricePerKm.toStringAsFixed(2)}/km',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip({required IconData icon, required String value}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppColors.textTertiary),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _statusColor(status).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          color: _statusColor(status),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'published':
        return AppColors.primary;
      case 'in_progress':
        return AppColors.warning;
      case 'full':
        return AppColors.purple;
      case 'completed':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      default:
        return AppColors.textTertiary;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'published':
        return 'Publicada';
      case 'in_progress':
        return 'En Progreso';
      case 'full':
        return 'Llena';
      case 'completed':
        return 'Completada';
      case 'cancelled':
        return 'Cancelada';
      default:
        return status;
    }
  }

  void _showRoutePassengers(Map<String, dynamic> route) {
    final routeId = route['id']?.toString() ?? '';
    final origin = route['origin'] ?? 'Origen';
    final destination = route['destination'] ?? 'Destino';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return _PassengerListSheet(
          routeId: routeId,
          origin: origin,
          destination: destination,
          busRouteService: _busRouteService,
        );
      },
    );
  }

  String _formatDate(String isoDate) {
    final dt = DateTime.tryParse(isoDate);
    if (dt == null) return isoDate;
    final months = [
      'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
      'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
    ];
    return '${dt.day} ${months[dt.month - 1]}, '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// =============================================================================
// Passenger List Bottom Sheet
// =============================================================================

class _PassengerListSheet extends StatefulWidget {
  final String routeId;
  final String origin;
  final String destination;
  final BusRouteService busRouteService;

  const _PassengerListSheet({
    required this.routeId,
    required this.origin,
    required this.destination,
    required this.busRouteService,
  });

  @override
  State<_PassengerListSheet> createState() => _PassengerListSheetState();
}

class _PassengerListSheetState extends State<_PassengerListSheet> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _passengers = [];

  @override
  void initState() {
    super.initState();
    _loadPassengers();
  }

  Future<void> _loadPassengers() async {
    try {
      final passengers =
          await widget.busRouteService.getRoutePassengers(widget.routeId);
      if (mounted) {
        setState(() {
          _passengers = passengers;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      padding: EdgeInsets.fromLTRB(24, 24, 24, bottomPadding + 16),
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
                color: AppColors.textTertiary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Header
          Text(
            '${widget.origin} -> ${widget.destination}',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            '${_passengers.length} pasajero${_passengers.length == 1 ? '' : 's'}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 12),
          // Content
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child:
                    CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (_passengers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.people_outline,
                        size: 40,
                        color:
                            AppColors.textTertiary.withValues(alpha: 0.5)),
                    const SizedBox(height: 12),
                    const Text(
                      'Sin pasajeros registrados',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _passengers.length,
                separatorBuilder: (_, _) =>
                    const Divider(color: AppColors.border, height: 1),
                itemBuilder: (_, index) =>
                    _buildPassengerRow(_passengers[index], index + 1),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPassengerRow(Map<String, dynamic> passenger, int number) {
    final name = passenger['passenger_name'] ?? 'Pasajero $number';
    final seats = (passenger['seats'] as num?)?.toInt() ?? 1;
    final status = passenger['status'] ?? 'confirmed';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$number',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
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
                Text(
                  name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '$seats asiento${seats == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // Status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: status == 'confirmed'
                  ? AppColors.success.withValues(alpha: 0.12)
                  : AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              status == 'confirmed' ? 'Confirmado' : status,
              style: TextStyle(
                color: status == 'confirmed'
                    ? AppColors.success
                    : AppColors.warning,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
