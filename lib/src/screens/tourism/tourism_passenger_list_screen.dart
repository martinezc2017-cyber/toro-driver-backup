import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../providers/driver_provider.dart';
import '../../services/location_service.dart';
import '../../services/tourism_invitation_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';

/// Screen for drivers to view and manage passengers of a tourism event.
///
/// Displays a list of passengers with their status (boarded, pending, off-boarded),
/// allows filtering and searching, and provides actions like check-in, call, and SMS.
class TourismPassengerListScreen extends StatefulWidget {
  final String eventId;

  const TourismPassengerListScreen({
    super.key,
    required this.eventId,
  });

  @override
  State<TourismPassengerListScreen> createState() =>
      _TourismPassengerListScreenState();
}

class _TourismPassengerListScreenState extends State<TourismPassengerListScreen> {
  final TourismInvitationService _invitationService = TourismInvitationService();
  final LocationService _locationService = LocationService();
  final TextEditingController _searchController = TextEditingController();

  // Data
  List<Map<String, dynamic>> _allPassengers = [];
  List<Map<String, dynamic>> _filteredPassengers = [];
  Map<String, Map<String, dynamic>> _passengerLocations = {};

  // Stats
  int _totalAccepted = 0;
  int _boardedCount = 0;

  // Filter state
  String _selectedFilter = 'all'; // all, boarded, pending, off_boarded
  String _searchQuery = '';

  // UI State
  bool _isLoading = true;
  String? _error;

  // Realtime
  RealtimeChannel? _invitationsChannel;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _subscribeToUpdates();
    // Refresh locations every 30 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadPassengerLocations();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (_invitationsChannel != null) {
      Supabase.instance.client.removeChannel(_invitationsChannel!);
      _invitationsChannel = null;
    }
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await Future.wait([
        _loadPassengers(),
        _loadPassengerLocations(),
      ]);

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Error al cargar pasajeros: $e';
        });
      }
    }
  }

  Future<void> _loadPassengers() async {
    final passengers =
        await _invitationService.getEventInvitations(widget.eventId);

    // Filter only accepted passengers (they have confirmed attendance)
    _allPassengers = passengers
        .where((p) =>
            p['status'] == 'accepted' ||
            p['status'] == 'checked_in' ||
            p['status'] == 'boarded' ||
            p['status'] == 'off_boarded')
        .toList();

    // Sort by name
    _allPassengers.sort((a, b) {
      final nameA = (a['invitee_name'] ?? '').toString().toLowerCase();
      final nameB = (b['invitee_name'] ?? '').toString().toLowerCase();
      return nameA.compareTo(nameB);
    });

    // Calculate stats
    _totalAccepted = _allPassengers.length;
    _boardedCount = _allPassengers
        .where((p) =>
            p['status'] == 'checked_in' || p['status'] == 'boarded')
        .length;

    _applyFilters();
  }

  Future<void> _loadPassengerLocations() async {
    final locations =
        await _invitationService.getPassengerLocations(widget.eventId);

    final locationMap = <String, Map<String, dynamic>>{};
    for (final loc in locations) {
      final invitationId = loc['invitation_id'] as String?;
      if (invitationId != null) {
        locationMap[invitationId] = loc;
      }
    }

    if (mounted) {
      setState(() => _passengerLocations = locationMap);
    }
  }

  void _subscribeToUpdates() {
    _invitationsChannel = Supabase.instance.client
        .channel('passenger_updates_${widget.eventId}')
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
            // Reload passengers on any change
            _loadPassengers();
          },
        )
        .subscribe();
  }

  void _applyFilters() {
    var filtered = List<Map<String, dynamic>>.from(_allPassengers);

    // Apply status filter
    switch (_selectedFilter) {
      case 'boarded':
        filtered = filtered
            .where((p) =>
                p['status'] == 'checked_in' || p['status'] == 'boarded')
            .toList();
        break;
      case 'pending':
        filtered = filtered
            .where((p) =>
                p['status'] == 'accepted' && p['status'] != 'checked_in')
            .toList();
        break;
      case 'off_boarded':
        filtered =
            filtered.where((p) => p['status'] == 'off_boarded').toList();
        break;
    }

    // Apply search query
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((p) {
        final name = (p['invitee_name'] ?? '').toString().toLowerCase();
        final email = (p['invitee_email'] ?? '').toString().toLowerCase();
        final phone = (p['invitee_phone'] ?? '').toString().toLowerCase();
        return name.contains(query) ||
            email.contains(query) ||
            phone.contains(query);
      }).toList();
    }

    setState(() => _filteredPassengers = filtered);
  }

  void _onSearchChanged(String query) {
    _searchQuery = query;
    _applyFilters();
  }

  void _onFilterChanged(String? filter) {
    if (filter != null) {
      HapticService.selectionClick();
      setState(() => _selectedFilter = filter);
      _applyFilters();
    }
  }

  void _callPassenger(String? phone) {
    if (phone != null && phone.isNotEmpty) {
      HapticService.lightImpact();
      launchUrlString('tel:$phone');
    }
  }

  void _smsPassenger(String? phone) {
    if (phone != null && phone.isNotEmpty) {
      HapticService.lightImpact();
      launchUrlString('sms:$phone');
    }
  }

  void _showCheckInModal(Map<String, dynamic> passenger) {
    HapticService.lightImpact();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _CheckInModal(
        passenger: passenger,
        onCheckIn: (checkInType, notes) async {
          await _performCheckIn(passenger, checkInType, notes);
          if (!ctx.mounted) return;
          Navigator.pop(ctx);
        },
      ),
    );
  }

  Future<void> _performCheckIn(
    Map<String, dynamic> passenger,
    String checkInType,
    String? notes,
  ) async {
    try {
      // Get current driver location
      final position = await _locationService.getCurrentPosition();
      if (position == null) {
        _showError('No se pudo obtener la ubicacion GPS');
        return;
      }

      if (!mounted) return;
      final driverProvider =
          Provider.of<DriverProvider>(context, listen: false);
      final driverId = driverProvider.driver?.id;
      if (driverId == null) {
        _showError('Error: No se encontro el conductor');
        return;
      }

      final invitationId = passenger['id'] as String;

      await _invitationService.checkInPassenger(
        invitationId: invitationId,
        performedByType: 'driver',
        performedById: driverId,
        lat: position.latitude,
        lng: position.longitude,
        checkInType: checkInType,
        stopName: notes,
      );

      HapticService.success();
      _showSuccess('Check-in registrado');
      await _loadPassengers();
    } catch (e) {
      HapticService.error();
      _showError('Error al hacer check-in: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
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
                  child: Column(
                    children: [
                      _buildFilterBar(),
                      Expanded(child: _buildPassengerList()),
                    ],
                  ),
                ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
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
          const Text(
            'Pasajeros',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          Text(
            '$_boardedCount/$_totalAccepted a bordo',
            style: const TextStyle(
              color: AppColors.success,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
          onPressed: () {
            HapticService.lightImpact();
            _loadData();
          },
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
            Icon(
              Icons.error_outline,
              size: 48,
              color: AppColors.error.withOpacity(0.7),
            ),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Error desconocido',
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
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border.withOpacity(0.5)),
        ),
      ),
      child: Row(
        children: [
          // Filter dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedFilter,
                dropdownColor: AppColors.card,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                ),
                icon: const Icon(
                  Icons.keyboard_arrow_down,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('Todos')),
                  DropdownMenuItem(value: 'boarded', child: Text('A bordo')),
                  DropdownMenuItem(value: 'pending', child: Text('Pendientes')),
                  DropdownMenuItem(value: 'off_boarded', child: Text('Bajaron')),
                ],
                onChanged: _onFilterChanged,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Search field
          Expanded(
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Buscar...',
                  hintStyle: const TextStyle(color: AppColors.textTertiary),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: AppColors.textTertiary,
                    size: 20,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.clear,
                            color: AppColors.textTertiary,
                            size: 18,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPassengerList() {
    if (_filteredPassengers.isEmpty) {
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
            Text(
              _searchQuery.isNotEmpty
                  ? 'No se encontraron pasajeros'
                  : 'Sin pasajeros',
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _filteredPassengers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final passenger = _filteredPassengers[index];
        return _buildPassengerCard(passenger);
      },
    );
  }

  Widget _buildPassengerCard(Map<String, dynamic> passenger) {
    final name = passenger['invitee_name'] ?? 'Pasajero';
    final email = passenger['invitee_email'] as String?;
    final phone = passenger['invitee_phone'] as String?;
    final seat = passenger['seat_number'] as String?;
    final boardingStop = passenger['boarding_stop'] as String?;
    final dropoffStop = passenger['dropoff_stop'] as String?;
    final status = passenger['status'] as String? ?? 'accepted';
    final notes = passenger['notes'] as String?;
    final invitationId = passenger['id'] as String?;
    final gpsEnabled = passenger['gps_tracking_enabled'] as bool? ?? false;

    // Get GPS location info
    final location = invitationId != null
        ? _passengerLocations[invitationId]
        : null;
    final gpsInfo = _getGpsTimeAgo(location);

    // Status styling
    final statusConfig = _getStatusConfig(status);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: statusConfig.color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: Status indicator + Name + Status badge
          Row(
            children: [
              // Status indicator dot
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusConfig.color,
                  boxShadow: [
                    BoxShadow(
                      color: statusConfig.color.withOpacity(0.4),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Name
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Status badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusConfig.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  statusConfig.label,
                  style: TextStyle(
                    color: statusConfig.color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Contact info
          if (phone != null && phone.isNotEmpty)
            _buildInfoRow(Icons.phone, phone),
          if (email != null && email.isNotEmpty && (phone == null || phone.isEmpty))
            _buildInfoRow(Icons.email_outlined, email),
          // Seat number
          if (seat != null && seat.isNotEmpty)
            _buildInfoRow(Icons.event_seat, 'Asiento: $seat'),
          // Boarding/dropoff stops
          if (boardingStop != null && boardingStop.isNotEmpty)
            _buildInfoRow(Icons.arrow_upward, 'Sube: $boardingStop'),
          if (dropoffStop != null && dropoffStop.isNotEmpty)
            _buildInfoRow(Icons.arrow_downward, 'Baja: $dropoffStop'),
          // GPS info
          if (gpsInfo != null)
            _buildInfoRow(Icons.gps_fixed, 'GPS: $gpsInfo')
          else if (gpsEnabled)
            _buildInfoRow(Icons.gps_fixed, 'GPS: Activado (sin señal)')
          else
            _buildInfoRow(Icons.gps_off, 'GPS: Apagado'),
          // Notes
          if (notes != null && notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.warning.withOpacity(0.2),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.notes,
                      color: AppColors.warning,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
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
            ),
          const SizedBox(height: 12),
          // Action buttons
          Row(
            children: [
              // Check-in button
              Expanded(
                child: _buildActionButton(
                  icon: Icons.check_circle_outline,
                  label: 'Check-in',
                  color: AppColors.success,
                  onTap: () => _showCheckInModal(passenger),
                ),
              ),
              const SizedBox(width: 8),
              // Call button
              _buildIconButton(
                icon: Icons.phone,
                color: AppColors.primary,
                enabled: phone != null && phone.isNotEmpty,
                onTap: () => _callPassenger(phone),
              ),
              const SizedBox(width: 8),
              // SMS button
              _buildIconButton(
                icon: Icons.message,
                color: AppColors.info,
                enabled: phone != null && phone.isNotEmpty,
                onTap: () => _smsPassenger(phone),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textTertiary, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required Color color,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final effectiveColor = enabled ? color : AppColors.textTertiary;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: effectiveColor.withOpacity(enabled ? 0.15 : 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: effectiveColor.withOpacity(enabled ? 0.3 : 0.1),
          ),
        ),
        child: Icon(icon, color: effectiveColor, size: 20),
      ),
    );
  }

  _StatusConfig _getStatusConfig(String status) {
    switch (status) {
      case 'checked_in':
      case 'boarded':
        return _StatusConfig(
          color: AppColors.success,
          label: 'A bordo',
        );
      case 'off_boarded':
        return _StatusConfig(
          color: AppColors.info,
          label: 'Bajo',
        );
      case 'accepted':
      default:
        return _StatusConfig(
          color: AppColors.warning,
          label: 'Pendiente',
        );
    }
  }

  String? _getGpsTimeAgo(Map<String, dynamic>? location) {
    if (location == null) return null;

    final updatedAt = location['updated_at'] as String?;
    if (updatedAt == null) return null;

    final updateTime = DateTime.tryParse(updatedAt);
    if (updateTime == null) return null;

    final diff = DateTime.now().difference(updateTime);

    if (diff.inMinutes < 1) {
      return 'ahora';
    } else if (diff.inMinutes < 60) {
      return 'hace ${diff.inMinutes} min';
    } else if (diff.inHours < 24) {
      return 'hace ${diff.inHours}h';
    } else {
      return 'hace ${diff.inDays}d';
    }
  }
}

/// Status configuration helper class
class _StatusConfig {
  final Color color;
  final String label;

  const _StatusConfig({
    required this.color,
    required this.label,
  });
}

/// Modal for performing check-ins
class _CheckInModal extends StatefulWidget {
  final Map<String, dynamic> passenger;
  final Future<void> Function(String checkInType, String? notes) onCheckIn;

  const _CheckInModal({
    required this.passenger,
    required this.onCheckIn,
  });

  @override
  State<_CheckInModal> createState() => _CheckInModalState();
}

class _CheckInModalState extends State<_CheckInModal> {
  String _selectedType = 'boarding';
  final TextEditingController _notesController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);
    HapticService.lightImpact();

    try {
      await widget.onCheckIn(
        _selectedType,
        _notesController.text.isNotEmpty ? _notesController.text : null,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.passenger['invitee_name'] ?? 'Pasajero';

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
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
            // Title
            Text(
              'Check-in: $name',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            // Check-in type options
            const Text(
              'Tipo de check-in',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildTypeChip('boarding', 'Abordaje'),
                _buildTypeChip('stop_arrival', 'Llegada parada'),
                _buildTypeChip('stop_departure', 'Salida parada'),
                _buildTypeChip('return_boarding', 'Re-abordaje'),
                _buildTypeChip('final_arrival', 'Llegada final'),
              ],
            ),
            const SizedBox(height: 20),
            // Notes field
            const Text(
              'Notas (opcional)',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: _notesController,
                maxLines: 2,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                ),
                decoration: const InputDecoration(
                  hintText: 'Agregar notas...',
                  hintStyle: TextStyle(color: AppColors.textTertiary),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(12),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Submit button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  disabledBackgroundColor: AppColors.success.withOpacity(0.5),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Confirmar Check-in',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChip(String value, String label) {
    final isSelected = _selectedType == value;

    return GestureDetector(
      onTap: () {
        HapticService.selectionClick();
        setState(() => _selectedType = value);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.2)
              : AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? AppColors.primary
                : AppColors.textSecondary,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
