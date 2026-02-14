import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../services/tourism_invitation_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';

/// Passenger List Screen for event organizers.
///
/// Displays all passengers/invitations for an event with:
/// - Search/filter functionality
/// - Status badges with color coding
/// - Contact buttons (Call, WhatsApp, SMS)
/// - Manual check-in capability
/// - Pull-to-refresh and real-time updates
/// - Stats header showing invitation counts
class OrganizerPassengersScreen extends StatefulWidget {
  final String eventId;

  const OrganizerPassengersScreen({
    super.key,
    required this.eventId,
  });

  @override
  State<OrganizerPassengersScreen> createState() =>
      _OrganizerPassengersScreenState();
}

class _OrganizerPassengersScreenState extends State<OrganizerPassengersScreen> {
  final TourismInvitationService _invitationService = TourismInvitationService();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _allPassengers = [];
  List<Map<String, dynamic>> _filteredPassengers = [];
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  String? _statusFilter;

  RealtimeChannel? _invitationsChannel;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _subscribeToUpdates();
    // Refresh stats every 30 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadStats();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _refreshTimer?.cancel();
    if (_invitationsChannel != null) {
      Supabase.instance.client.removeChannel(_invitationsChannel!);
      _invitationsChannel = null;
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
        _loadPassengers(),
        _loadStats(),
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

  Future<void> _loadPassengers() async {
    final passengers =
        await _invitationService.getEventInvitations(widget.eventId);
    if (mounted) {
      setState(() {
        _allPassengers = passengers;
        _applyFilters();
      });
    }
  }

  Future<void> _loadStats() async {
    final stats = await _invitationService.getInvitationStats(widget.eventId);
    if (mounted) {
      setState(() => _stats = stats);
    }
  }

  void _subscribeToUpdates() {
    final supabase = Supabase.instance.client;
    _invitationsChannel = supabase.channel('invitations_${widget.eventId}');

    _invitationsChannel!
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
            // Reload data on any change
            _loadPassengers();
            _loadStats();
          },
        )
        .subscribe();
  }

  void _applyFilters() {
    List<Map<String, dynamic>> filtered = List.from(_allPassengers);

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((p) {
        final name = (p['invitee_name'] as String? ?? '').toLowerCase();
        final email = (p['invitee_email'] as String? ?? '').toLowerCase();
        final phone = (p['invitee_phone'] as String? ?? '').toLowerCase();
        return name.contains(query) ||
            email.contains(query) ||
            phone.contains(query);
      }).toList();
    }

    // Apply status filter
    if (_statusFilter != null) {
      filtered = filtered.where((p) => p['status'] == _statusFilter).toList();
    }

    setState(() => _filteredPassengers = filtered);
  }

  void _onSearchChanged(String query) {
    setState(() => _searchQuery = query);
    _applyFilters();
  }

  void _onStatusFilterChanged(String? status) {
    HapticService.lightImpact();
    setState(() => _statusFilter = status);
    _applyFilters();
  }

  Future<void> _makePhoneCall(String phone) async {
    HapticService.lightImpact();
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showError('No se pudo abrir la aplicacion de llamadas');
    }
  }

  Future<void> _openWhatsApp(String phone) async {
    HapticService.lightImpact();
    // Clean phone number (remove spaces, dashes, etc.)
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('https://wa.me/$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showError('No se pudo abrir WhatsApp');
    }
  }

  Future<void> _sendSms(String phone) async {
    HapticService.lightImpact();
    final uri = Uri(scheme: 'sms', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showError('No se pudo abrir la aplicacion de mensajes');
    }
  }

  Future<void> _checkInPassenger(Map<String, dynamic> passenger) async {
    final invitationId = passenger['id'] as String;
    final name = passenger['invitee_name'] ?? 'Pasajero';
    final currentStatus = passenger['status'] as String? ?? 'pending';

    // Don't allow check-in if already checked in
    if (currentStatus == 'checked_in') {
      _showInfo('$name ya tiene check-in registrado');
      return;
    }

    // Confirm check-in
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Confirmar Check-in',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'Registrar check-in manual para $name?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: AppColors.textTertiary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    HapticService.mediumImpact();

    try {
      // Get current user (organizer)
      if (!mounted) return;
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final driver = authProvider.driver;

      if (driver == null) {
        _showError('Error: No se pudo obtener el perfil del organizador');
        return;
      }

      // Perform check-in
      await _invitationService.checkInPassenger(
        invitationId: invitationId,
        performedByType: 'organizer',
        performedById: driver.id,
        lat: 0.0, // Manual check-in doesn't require GPS
        lng: 0.0,
        checkInType: 'manual',
      );

      HapticService.success();
      _showSuccess('Check-in registrado para $name');

      // Reload data
      await _loadData();
    } catch (e) {
      HapticService.error();
      _showError('Error al registrar check-in: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showInfo(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showPassengerDetail(Map<String, dynamic> passenger) {
    HapticService.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _buildPassengerDetailModal(ctx, passenger),
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
                  child: _buildContent(),
                ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text(
        'Lista de Pasajeros',
        style: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
      centerTitle: true,
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
              color: AppColors.error.withValues(alpha: 0.7),
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

  Widget _buildContent() {
    return Column(
      children: [
        // Stats header
        _buildStatsHeader(),
        // Search bar
        _buildSearchBar(),
        // Status filter chips
        _buildStatusFilters(),
        // Passengers list
        Expanded(
          child: _filteredPassengers.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(
                    left: 12,
                    right: 12,
                    top: 4,
                    bottom: 80,
                  ),
                  itemCount: _filteredPassengers.length,
                  itemBuilder: (context, index) {
                    final passenger = _filteredPassengers[index];
                    return _buildPassengerCard(passenger);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildStatsHeader() {
    final total = _stats['total'] ?? 0;
    final accepted = _stats['accepted'] ?? 0;
    final checkedIn = _stats['checked_in'] ?? 0;
    final pending = _stats['pending'] ?? 0;
    final declined = _stats['declined'] ?? 0;
    final gpsActive = _stats['gps_active'] ?? 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.08),
            AppColors.card,
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Row(
        children: [
          // Total count with icon
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.groups, color: AppColors.primary, size: 24),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$total',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Pasajeros',
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Vertical divider
          Container(
            width: 1,
            height: 50,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.border.withValues(alpha: 0.2),
                  AppColors.border,
                  AppColors.border.withValues(alpha: 0.2),
                ],
              ),
            ),
          ),
          // Stats grid
          Expanded(
            flex: 3,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _buildCompactStat(Icons.check_circle, '$accepted', 'Aceptados', AppColors.success)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildCompactStat(Icons.airline_seat_recline_normal, '$checkedIn', 'A bordo', AppColors.primary)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _buildCompactStat(Icons.schedule, '$pending', 'Pendientes', AppColors.warning)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildCompactStat(Icons.cancel, '$declined', 'Rechazados', AppColors.error)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactStat(IconData icon, String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: color.withValues(alpha: 0.7),
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Buscar nombre o telefono...',
            hintStyle: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 12,
            ),
            prefixIcon: const Icon(
              Icons.search,
              color: AppColors.textTertiary,
              size: 18,
            ),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: AppColors.textTertiary, size: 16),
                    onPressed: () {
                      _searchController.clear();
                      _onSearchChanged('');
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          _buildFilterChip('Todo', null, null),
          _buildFilterChip('Abordo', 'checked_in', AppColors.primary),
          _buildFilterChip('OK', 'accepted', AppColors.success),
          _buildFilterChip('Pend', 'pending', AppColors.warning),
          _buildFilterChip('No', 'declined', AppColors.error),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String? filterValue, Color? color) {
    final isSelected = _statusFilter == filterValue;
    final chipColor = color ?? AppColors.primary;

    return GestureDetector(
      onTap: () => _onStatusFilterChanged(filterValue),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? chipColor.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? chipColor : AppColors.border,
            width: isSelected ? 1 : 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? chipColor : AppColors.textTertiary,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _searchQuery.isNotEmpty || _statusFilter != null
                ? Icons.search_off
                : Icons.people_outline,
            size: 48,
            color: AppColors.textTertiary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty || _statusFilter != null
                ? 'No se encontraron resultados'
                : 'No hay pasajeros registrados',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty || _statusFilter != null
                ? 'Intenta con otros filtros'
                : 'Invita pasajeros a tu evento',
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPassengerCard(Map<String, dynamic> passenger) {
    final name = passenger['invitee_name'] ??
        passenger['invited_name'] ??
        'Pasajero';
    final email = passenger['invitee_email'] ??
        passenger['invited_email'] as String?;
    final phone = passenger['invitee_phone'] ??
        passenger['invited_phone'] as String?;
    final status = passenger['status'] as String? ?? 'pending';
    final lastCheckInAt = passenger['last_check_in_at'] as String?;
    final seatNumber = passenger['seat_number'] as String?;
    final emergencyContact = passenger['emergency_contact'] as String?;
    final emergencyPhone = passenger['emergency_phone'] as String?;

    // Compact card design - all critical info visible at once
    return GestureDetector(
      onTap: () => _showPassengerDetail(passenger),
      onLongPress: phone != null ? () => _makePhoneCall(phone) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: status == 'checked_in'
                ? AppColors.success.withValues(alpha: 0.4)
                : AppColors.border,
            width: status == 'checked_in' ? 1.5 : 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Status indicator (small colored dot)
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _getStatusColor(status),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            // Main info column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Name + Seat
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (seatNumber != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '#$seatNumber',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  // Row 2: Phone (clickable) + Status label
                  Row(
                    children: [
                      if (phone != null) ...[
                        Icon(Icons.phone, size: 12, color: AppColors.success),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            phone,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ] else if (email != null) ...[
                        Icon(Icons.email, size: 12, color: AppColors.textTertiary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            email,
                            style: const TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ] else
                        const Expanded(
                          child: Text(
                            'Sin contacto',
                            style: TextStyle(
                              color: AppColors.error,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      _buildCompactStatusBadge(status),
                    ],
                  ),
                  // Row 3: Emergency contact (if available)
                  if (emergencyContact != null || emergencyPhone != null) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.emergency, size: 11, color: AppColors.error.withValues(alpha: 0.7)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            emergencyPhone ?? emergencyContact ?? '',
                            style: TextStyle(
                              color: AppColors.error.withValues(alpha: 0.7),
                              fontSize: 10,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  // Row 4: Check-in time (if checked in)
                  if (lastCheckInAt != null) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 11, color: AppColors.success),
                        const SizedBox(width: 4),
                        Text(
                          'Check-in: ${_formatShortTime(lastCheckInAt)}',
                          style: const TextStyle(
                            color: AppColors.success,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Quick action buttons
            if (phone != null) ...[
              _buildMiniActionButton(
                icon: Icons.phone,
                color: AppColors.success,
                onTap: () => _makePhoneCall(phone),
              ),
              const SizedBox(width: 8),
              _buildMiniActionButton(
                icon: Icons.message,
                color: AppColors.primary,
                onTap: () => _openWhatsApp(phone),
              ),
            ],
            // Check-in button
            if (status != 'checked_in' && status != 'declined') ...[
              const SizedBox(width: 8),
              _buildMiniActionButton(
                icon: Icons.how_to_reg,
                color: AppColors.warning,
                onTap: () => _checkInPassenger(passenger),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompactStatusBadge(String status) {
    Color color;
    String label;

    switch (status) {
      case 'accepted':
        color = AppColors.success;
        label = 'OK';
        break;
      case 'declined':
        color = AppColors.error;
        label = 'NO';
        break;
      case 'checked_in':
        color = AppColors.primary;
        label = 'ABORDO';
        break;
      case 'expired':
        color = AppColors.textTertiary;
        label = 'EXP';
        break;
      default:
        color = AppColors.warning;
        label = 'PEND';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildMiniActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.15),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  String _formatShortTime(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }

  Widget _buildStatusBadge(String status) {
    Color bgColor;
    Color textColor;
    IconData icon;
    String label;

    switch (status) {
      case 'accepted':
        bgColor = AppColors.success.withValues(alpha: 0.15);
        textColor = AppColors.success;
        icon = Icons.check_circle;
        label = 'Acepto';
        break;
      case 'declined':
        bgColor = AppColors.error.withValues(alpha: 0.15);
        textColor = AppColors.error;
        icon = Icons.cancel;
        label = 'Rechazo';
        break;
      case 'expired':
        bgColor = AppColors.textTertiary.withValues(alpha: 0.15);
        textColor = AppColors.textTertiary;
        icon = Icons.timer_off;
        label = 'Cancelado';
        break;
      case 'checked_in':
        bgColor = AppColors.primary.withValues(alpha: 0.15);
        textColor = AppColors.primary;
        icon = Icons.how_to_reg;
        label = 'Check-in';
        break;
      case 'no_show':
        bgColor = AppColors.error.withValues(alpha: 0.15);
        textColor = AppColors.error;
        icon = Icons.person_off;
        label = 'No show';
        break;
      default:
        bgColor = AppColors.warning.withValues(alpha: 0.15);
        textColor = AppColors.warning;
        icon = Icons.schedule;
        label = 'Pendiente';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPassengerDetailModal(
      BuildContext ctx, Map<String, dynamic> passenger) {
    final name = passenger['invitee_name'] ??
        passenger['invited_name'] ??
        'Pasajero';
    final email = passenger['invitee_email'] ??
        passenger['invited_email'] as String?;
    final phone = passenger['invitee_phone'] ??
        passenger['invited_phone'] as String?;
    final status = passenger['status'] as String? ?? 'pending';
    final createdAt = passenger['created_at'] as String?;
    final acceptedAt = passenger['accepted_at'] as String?;
    final lastCheckInAt = passenger['last_check_in_at'] as String?;
    final invitationCode = passenger['invitation_code'] as String?;
    final hasProfile = passenger['has_profile'] == true;
    final avatarUrl = passenger['avatar_url'] as String?;

    return Container(
      padding: const EdgeInsets.all(24),
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
          const SizedBox(height: 20),
          // Header with avatar
          Row(
            children: [
              hasProfile && avatarUrl != null
                  ? CircleAvatar(
                      radius: 28,
                      backgroundImage: NetworkImage(avatarUrl),
                      backgroundColor: _getStatusColor(status).withValues(alpha: 0.15),
                    )
                  : Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: _getStatusColor(status).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(
                          _getInitials(name),
                          style: TextStyle(
                            color: _getStatusColor(status),
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
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
                    const SizedBox(height: 4),
                    _buildStatusBadge(status),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(color: AppColors.border),
          const SizedBox(height: 16),
          // Details
          if (email != null) _buildDetailRow(Icons.email_outlined, 'Email', email),
          if (phone != null) _buildDetailRow(Icons.phone_outlined, 'Telefono', phone),
          if (invitationCode != null)
            _buildDetailRow(Icons.qr_code, 'Codigo', invitationCode),
          if (createdAt != null)
            _buildDetailRow(
                Icons.event, 'Invitado', _formatDateTime(createdAt)),
          if (acceptedAt != null)
            _buildDetailRow(
                Icons.check_circle_outline, 'Acepto', _formatDateTime(acceptedAt)),
          if (lastCheckInAt != null)
            _buildDetailRow(
                Icons.how_to_reg, 'Check-in', _formatDateTime(lastCheckInAt)),
          const SizedBox(height: 24),
          // Contact buttons
          if (phone != null)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _makePhoneCall(phone);
                    },
                    icon: const Icon(Icons.phone, size: 18),
                    label: const Text('Llamar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.success,
                      side: const BorderSide(color: AppColors.success),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openWhatsApp(phone);
                    },
                    icon: const Icon(Icons.message, size: 18),
                    label: const Text('WhatsApp'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _sendSms(phone);
                    },
                    icon: const Icon(Icons.sms, size: 18),
                    label: const Text('SMS'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.info,
                      side: const BorderSide(color: AppColors.info),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          if (phone != null) const SizedBox(height: 12),
          // Check-in button
          if (status != 'checked_in' && status != 'declined')
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _checkInPassenger(passenger);
                },
                icon: const Icon(Icons.how_to_reg, size: 20),
                label: const Text('Registrar Check-in Manual'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          SizedBox(height: MediaQuery.of(ctx).padding.bottom + 8),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textTertiary),
          const SizedBox(width: 12),
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════════════════════

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return '?';
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'accepted':
        return AppColors.success;
      case 'declined':
        return AppColors.error;
      case 'checked_in':
        return AppColors.primary;
      default:
        return AppColors.warning;
    }
  }

  String _formatDateTime(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      const months = [
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
      return '${date.day} ${months[date.month - 1]} ${date.year}, '
          '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return isoDate;
    }
  }
}
