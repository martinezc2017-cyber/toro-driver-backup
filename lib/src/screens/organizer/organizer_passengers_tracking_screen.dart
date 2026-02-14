import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/supabase_config.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';

/// Real-time passenger tracking screen for tourism event organizers.
///
/// Displays:
/// - A map with real-time GPS locations of all passengers who are sharing
/// - A searchable/filterable list of all invited passengers with details
/// - Stats header showing invitation/check-in/GPS counts
/// - Real-time updates via Supabase subscriptions
/// - Contact options (call, SMS, WhatsApp) for each passenger
class OrganizerPassengersTrackingScreen extends StatefulWidget {
  final String eventId;
  final String? eventName;

  const OrganizerPassengersTrackingScreen({
    super.key,
    required this.eventId,
    this.eventName,
  });

  @override
  State<OrganizerPassengersTrackingScreen> createState() =>
      _OrganizerPassengersTrackingScreenState();
}

class _OrganizerPassengersTrackingScreenState
    extends State<OrganizerPassengersTrackingScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseClient _client = SupabaseConfig.client;
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  // Data
  List<Map<String, dynamic>> _allPassengers = [];
  List<Map<String, dynamic>> _filteredPassengers = [];
  Map<String, LatLng> _passengerLocations = {};
  final Map<String, dynamic> _stats = {
    'total': 0,
    'accepted': 0,
    'checked_in': 0,
    'gps_active': 0,
  };

  // State
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  String? _statusFilter;
  bool _isMapExpanded = false;

  // Subscriptions
  RealtimeChannel? _invitationsChannel;
  RealtimeChannel? _locationsChannel;
  Timer? _refreshTimer;

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _loadData();
    _subscribeToRealtime();
    // Refresh GPS locations every 15 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _loadPassengerLocations();
    });
  }

  void _initAnimations() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mapController.dispose();
    _pulseController.dispose();
    _refreshTimer?.cancel();
    if (_invitationsChannel != null) {
      _client.removeChannel(_invitationsChannel!);
      _invitationsChannel = null;
    }
    if (_locationsChannel != null) {
      _client.removeChannel(_locationsChannel!);
      _locationsChannel = null;
    }
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DATA LOADING
  // ═══════════════════════════════════════════════════════════════════════════

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

      _calculateStats();

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
    try {
      // Fetch invitations with profile data if user_id exists
      final response = await _client
          .from('tourism_invitations')
          .select('''
            *,
            profiles:user_id (
              id,
              full_name,
              email,
              phone,
              avatar_url
            )
          ''')
          .eq('event_id', widget.eventId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _allPassengers = List<Map<String, dynamic>>.from(response);
          _applyFilters();
        });
      }
    } catch (e) {
      // Fallback to basic query without joins
      try {
        final response = await _client
            .from('tourism_invitations')
            .select()
            .eq('event_id', widget.eventId)
            .order('created_at', ascending: false);

        if (mounted) {
          setState(() {
            _allPassengers = List<Map<String, dynamic>>.from(response);
            _applyFilters();
          });
        }
      } catch (e2) {
        rethrow;
      }
    }
  }

  Future<void> _loadPassengerLocations() async {
    try {
      // Get locations from tourism_invitations table (last_known_lat, last_known_lng)
      debugPrint('GPS_DEBUG -> Loading locations for event: ${widget.eventId}');
      final response = await _client
          .from('tourism_invitations')
          .select('id, last_known_lat, last_known_lng, last_gps_update, gps_tracking_enabled')
          .eq('event_id', widget.eventId)
          .not('last_known_lat', 'is', null);

      debugPrint('GPS_DEBUG -> Response: $response');
      debugPrint('GPS_DEBUG -> Response length: ${(response as List).length}');

      final locations = <String, LatLng>{};
      final now = DateTime.now();
      int gpsActive = 0;

      for (final row in response) {
        final id = row['id'] as String;
        final lat = (row['last_known_lat'] as num?)?.toDouble();
        final lng = (row['last_known_lng'] as num?)?.toDouble();
        final lastUpdate = row['last_gps_update'] as String?;
        final enabled = row['gps_tracking_enabled'] as bool? ?? true;

        debugPrint('GPS_DEBUG -> Row: id=$id, lat=$lat, lng=$lng, enabled=$enabled');

        if (lat != null && lng != null && enabled) {
          locations[id] = LatLng(lat, lng);

          // Count as active if updated within last 15 minutes
          if (lastUpdate != null) {
            final updateTime = DateTime.tryParse(lastUpdate);
            if (updateTime != null &&
                now.difference(updateTime).inMinutes < 15) {
              gpsActive++;
            }
          }
        }
      }

      debugPrint('GPS_DEBUG -> Final locations map: $locations');
      debugPrint('GPS_DEBUG -> Locations count: ${locations.length}');

      if (mounted) {
        setState(() {
          _passengerLocations = locations;
          _stats['gps_active'] = gpsActive;
        });
      }
    } catch (e) {
      debugPrint('GPS_DEBUG -> ERROR: $e');
    }
  }

  void _calculateStats() {
    int total = _allPassengers.length;
    int accepted = 0;
    int checkedIn = 0;

    for (final p in _allPassengers) {
      final status = p['status'] as String? ?? 'pending';
      final checkInStatus = p['current_check_in_status'] as String?;

      if (status == 'accepted' || status == 'checked_in') {
        accepted++;
      }

      if (status == 'checked_in' || checkInStatus == 'boarded') {
        checkedIn++;
      }
    }

    setState(() {
      _stats['total'] = total;
      _stats['accepted'] = accepted;
      _stats['checked_in'] = checkedIn;
    });
  }

  void _applyFilters() {
    List<Map<String, dynamic>> filtered = List.from(_allPassengers);

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((p) {
        final name = _getPassengerName(p).toLowerCase();
        final email = _getPassengerEmail(p).toLowerCase();
        final phone = _getPassengerPhone(p).toLowerCase();
        return name.contains(query) ||
            email.contains(query) ||
            phone.contains(query);
      }).toList();
    }

    // Apply status filter
    if (_statusFilter != null) {
      filtered = filtered.where((p) {
        final status = p['status'] as String? ?? 'pending';
        final checkInStatus = p['current_check_in_status'] as String?;

        switch (_statusFilter) {
          case 'accepted':
            return status == 'accepted';
          case 'checked_in':
            return status == 'checked_in' || checkInStatus == 'boarded';
          case 'pending':
            return status == 'pending';
          case 'declined':
            return status == 'declined';
          case 'gps_active':
            return _passengerLocations.containsKey(p['id']);
          default:
            return true;
        }
      }).toList();
    }

    setState(() => _filteredPassengers = filtered);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REALTIME SUBSCRIPTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  void _subscribeToRealtime() {
    // Subscribe to invitation changes
    _invitationsChannel = _client.channel('tracking_invitations_${widget.eventId}');
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
            _handleInvitationChange(payload);
          },
        )
        .subscribe();

    // Subscribe to check-in events
    _locationsChannel = _client.channel('tracking_checkins_${widget.eventId}');
    _locationsChannel!
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
            // Reload data when a new check-in happens
            _loadPassengers();
          },
        )
        .subscribe();
  }

  void _handleInvitationChange(PostgresChangePayload payload) {
    final newRecord = payload.newRecord;
    if (newRecord.isEmpty) {
      _loadPassengers();
      return;
    }

    // Update the specific passenger in the list
    final invitationId = newRecord['id'] as String?;
    if (invitationId == null) return;

    setState(() {
      final index = _allPassengers.indexWhere((p) => p['id'] == invitationId);
      if (index != -1) {
        // Merge new data with existing
        _allPassengers[index] = {..._allPassengers[index], ...newRecord};
      } else {
        // New invitation, add to list
        _allPassengers.insert(0, Map<String, dynamic>.from(newRecord));
      }

      // Update location if available
      final lat = (newRecord['last_known_lat'] as num?)?.toDouble();
      final lng = (newRecord['last_known_lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        _passengerLocations[invitationId] = LatLng(lat, lng);
      }

      _applyFilters();
      _calculateStats();
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _makePhoneCall(String phone) async {
    HapticService.lightImpact();
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showError('No se pudo abrir la app de llamadas');
    }
  }

  Future<void> _openWhatsApp(String phone) async {
    HapticService.lightImpact();
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
      _showError('No se pudo abrir la app de mensajes');
    }
  }

  void _focusOnPassenger(String invitationId) {
    final location = _passengerLocations[invitationId];
    if (location != null) {
      HapticService.mediumImpact();
      _mapController.move(location, 15);

      // Expand map if collapsed
      if (!_isMapExpanded) {
        setState(() => _isMapExpanded = true);
      }
    } else {
      _showInfo('Este pasajero no tiene GPS activo');
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

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  String _getPassengerName(Map<String, dynamic> passenger) {
    // Try profile first
    final profile = passenger['profiles'] as Map<String, dynamic>?;
    if (profile != null && profile['full_name'] != null) {
      return profile['full_name'] as String;
    }
    // Fallback to invitation fields
    return passenger['invited_name'] as String? ?? 'Pasajero';
  }

  String _getPassengerEmail(Map<String, dynamic> passenger) {
    final profile = passenger['profiles'] as Map<String, dynamic>?;
    if (profile != null && profile['email'] != null) {
      return profile['email'] as String;
    }
    return passenger['invited_email'] as String? ?? '';
  }

  String _getPassengerPhone(Map<String, dynamic> passenger) {
    final profile = passenger['profiles'] as Map<String, dynamic>?;
    if (profile != null && profile['phone'] != null) {
      return profile['phone'] as String;
    }
    return passenger['invited_phone'] as String? ?? '';
  }

  String? _getPassengerAvatar(Map<String, dynamic> passenger) {
    final profile = passenger['profiles'] as Map<String, dynamic>?;
    return profile?['avatar_url'] as String?;
  }

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
      case 'expired':
        return AppColors.textTertiary;
      case 'no_show':
        return AppColors.warning;
      default:
        return AppColors.warning; // pending
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'accepted':
        return 'Aceptado';
      case 'declined':
        return 'Rechazado';
      case 'checked_in':
        return 'Check-in';
      case 'expired':
        return 'Expirado';
      case 'no_show':
        return 'No Show';
      default:
        return 'Pendiente';
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'accepted':
        return Icons.check_circle;
      case 'declined':
        return Icons.cancel;
      case 'checked_in':
        return Icons.how_to_reg;
      case 'expired':
        return Icons.timer_off;
      case 'no_show':
        return Icons.person_off;
      default:
        return Icons.schedule;
    }
  }

  String _getCheckInStatusLabel(String? checkInStatus) {
    switch (checkInStatus) {
      case 'boarded':
        return 'A bordo';
      case 'off_boarded':
        return 'Descendio';
      default:
        return 'No abordado';
    }
  }

  Color _getCheckInStatusColor(String? checkInStatus) {
    switch (checkInStatus) {
      case 'boarded':
        return AppColors.success;
      case 'off_boarded':
        return AppColors.primary;
      default:
        return AppColors.textTertiary;
    }
  }

  String _formatDateTime(String? isoDate) {
    if (isoDate == null) return '-';
    try {
      final date = DateTime.parse(isoDate);
      const months = [
        'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
        'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
      ];
      return '${date.day} ${months[date.month - 1]}, '
          '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return isoDate;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD METHODS
  // ═══════════════════════════════════════════════════════════════════════════

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
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tracking Pasajeros',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          if (widget.eventName != null)
            Text(
              widget.eventName!,
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      actions: [
        // Toggle map size
        IconButton(
          icon: Icon(
            _isMapExpanded ? Icons.fullscreen_exit : Icons.fullscreen,
            color: AppColors.textSecondary,
          ),
          onPressed: () {
            HapticService.lightImpact();
            setState(() => _isMapExpanded = !_isMapExpanded);
          },
          tooltip: _isMapExpanded ? 'Minimizar mapa' : 'Expandir mapa',
        ),
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
        // Map section (collapsible)
        _buildMapSection(),
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
                    left: 16,
                    right: 16,
                    bottom: 32,
                  ),
                  itemCount: _filteredPassengers.length,
                  itemBuilder: (context, index) {
                    return _buildPassengerCard(_filteredPassengers[index]);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildStatsHeader() {
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            icon: Icons.people,
            value: '${_stats['total']}',
            label: 'Invitados',
            color: AppColors.primary,
          ),
          _buildStatDivider(),
          _buildStatItem(
            icon: Icons.check_circle,
            value: '${_stats['accepted']}',
            label: 'Aceptados',
            color: AppColors.success,
          ),
          _buildStatDivider(),
          _buildStatItem(
            icon: Icons.directions_bus,
            value: '${_stats['checked_in']}',
            label: 'A bordo',
            color: AppColors.warning,
          ),
          _buildStatDivider(),
          _buildStatItemAnimated(
            icon: Icons.gps_fixed,
            value: '${_stats['gps_active']}',
            label: 'GPS',
            color: AppColors.purple,
            isActive: (_stats['gps_active'] as int) > 0,
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildStatItemAnimated({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
    required bool isActive,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: isActive ? _pulseAnimation.value : 1.0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: isActive
                    ? BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.4),
                            blurRadius: 8 * _pulseAnimation.value,
                            spreadRadius: 2,
                          ),
                        ],
                      )
                    : null,
                child: Icon(icon, color: color, size: 20),
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: isActive ? color : AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildStatDivider() {
    return Container(
      width: 1,
      height: 40,
      color: AppColors.border,
    );
  }

  Widget _buildMapSection() {
    // Calculate map center
    LatLng center = const LatLng(29.0729, -110.9559); // Hermosillo default
    if (_passengerLocations.isNotEmpty) {
      final locations = _passengerLocations.values.toList();
      double avgLat = 0;
      double avgLng = 0;
      for (final loc in locations) {
        avgLat += loc.latitude;
        avgLng += loc.longitude;
      }
      center = LatLng(avgLat / locations.length, avgLng / locations.length);
    }

    final mapHeight = _isMapExpanded ? 350.0 : 180.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: mapHeight,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
        boxShadow: AppColors.shadowSubtle,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // Map
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: _isMapExpanded ? 13 : 11,
              ),
              children: [
                // CartoDB dark tiles
                TileLayer(
                  urlTemplate:
                      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.toro.driver',
                ),
                // Passenger markers
                MarkerLayer(
                  markers: _buildPassengerMarkers(),
                ),
              ],
            ),
            // Map header overlay
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.card,
                      AppColors.card.withValues(alpha: 0),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.map, color: AppColors.success, size: 16),
                    const SizedBox(width: 6),
                    const Text(
                      'Ubicaciones en tiempo real',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (_passengerLocations.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedBuilder(
                              animation: _pulseAnimation,
                              builder: (context, child) {
                                return Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: AppColors.success,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.success
                                            .withValues(alpha: 0.5),
                                        blurRadius: 4 * _pulseAnimation.value,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${_passengerLocations.length} activos',
                              style: const TextStyle(
                                color: AppColors.success,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Marker> _buildPassengerMarkers() {
    final markers = <Marker>[];

    for (final passenger in _allPassengers) {
      final id = passenger['id'] as String;
      final location = _passengerLocations[id];
      if (location == null) continue;

      final name = _getPassengerName(passenger);
      final status = passenger['status'] as String? ?? 'pending';
      final checkInStatus = passenger['current_check_in_status'] as String?;
      final isOnboard = checkInStatus == 'boarded';

      markers.add(
        Marker(
          point: location,
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: () => _showPassengerDetail(passenger),
            child: Tooltip(
              message: name,
              child: Container(
                decoration: BoxDecoration(
                  color: isOnboard ? AppColors.success : AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: (isOnboard ? AppColors.success : AppColors.primary)
                          .withValues(alpha: 0.5),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    _getInitials(name),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return markers;
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (value) {
            setState(() => _searchQuery = value);
            _applyFilters();
          },
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Buscar por nombre, email o telefono...',
            hintStyle: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 13,
            ),
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
                      setState(() => _searchQuery = '');
                      _applyFilters();
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildFilterChip(
            label: 'Todos',
            isSelected: _statusFilter == null,
            onTap: () {
              HapticService.lightImpact();
              setState(() => _statusFilter = null);
              _applyFilters();
            },
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            label: 'GPS Activo',
            isSelected: _statusFilter == 'gps_active',
            color: AppColors.purple,
            icon: Icons.gps_fixed,
            onTap: () {
              HapticService.lightImpact();
              setState(() => _statusFilter = 'gps_active');
              _applyFilters();
            },
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            label: 'A bordo',
            isSelected: _statusFilter == 'checked_in',
            color: AppColors.success,
            onTap: () {
              HapticService.lightImpact();
              setState(() => _statusFilter = 'checked_in');
              _applyFilters();
            },
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            label: 'Aceptados',
            isSelected: _statusFilter == 'accepted',
            color: AppColors.primary,
            onTap: () {
              HapticService.lightImpact();
              setState(() => _statusFilter = 'accepted');
              _applyFilters();
            },
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            label: 'Pendientes',
            isSelected: _statusFilter == 'pending',
            color: AppColors.warning,
            onTap: () {
              HapticService.lightImpact();
              setState(() => _statusFilter = 'pending');
              _applyFilters();
            },
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            label: 'Rechazados',
            isSelected: _statusFilter == 'declined',
            color: AppColors.error,
            onTap: () {
              HapticService.lightImpact();
              setState(() => _statusFilter = 'declined');
              _applyFilters();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    Color? color,
    IconData? icon,
    required VoidCallback onTap,
  }) {
    final chipColor = color ?? AppColors.primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? chipColor.withValues(alpha: 0.2)
              : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? chipColor.withValues(alpha: 0.5)
                : AppColors.border,
            width: isSelected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: isSelected ? chipColor : AppColors.textSecondary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? chipColor : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
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
    final id = passenger['id'] as String;
    final name = _getPassengerName(passenger);
    final email = _getPassengerEmail(passenger);
    final phone = _getPassengerPhone(passenger);
    final avatarUrl = _getPassengerAvatar(passenger);
    final status = passenger['status'] as String? ?? 'pending';
    final checkInStatus = passenger['current_check_in_status'] as String?;
    final hasGps = _passengerLocations.containsKey(id);
    final lastGpsUpdate = passenger['last_gps_update'] as String?;
    final seatNumber = passenger['seat_number'] as String?;
    final boardingStop = passenger['boarding_stop'] as String?;
    final dropoffStop = passenger['dropoff_stop'] as String?;
    final gpsEnabled = passenger['gps_tracking_enabled'] as bool? ?? false;

    return GestureDetector(
      onTap: () => _showPassengerDetail(passenger),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasGps
                ? AppColors.purple.withValues(alpha: 0.3)
                : AppColors.border,
            width: hasGps ? 1 : 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with avatar, name, and status
            Row(
              children: [
                // Avatar
                _buildAvatar(name, avatarUrl, status),
                const SizedBox(width: 12),
                // Name and contact info
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
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // GPS indicator
                          if (hasGps)
                            AnimatedBuilder(
                              animation: _pulseAnimation,
                              builder: (context, child) {
                                return Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: AppColors.purple.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.purple
                                            .withValues(alpha: 0.3),
                                        blurRadius: 4 * _pulseAnimation.value,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.gps_fixed,
                                    color: AppColors.purple,
                                    size: 12,
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      if (phone.isNotEmpty)
                        Text(
                          phone,
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 12,
                          ),
                        )
                      else if (email.isNotEmpty)
                        Text(
                          email,
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      // Seat + boarding info
                      if (seatNumber != null || boardingStop != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (seatNumber != null && seatNumber.isNotEmpty) ...[
                              Icon(Icons.event_seat, size: 11, color: AppColors.textTertiary),
                              const SizedBox(width: 3),
                              Text(seatNumber, style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
                              const SizedBox(width: 8),
                            ],
                            if (boardingStop != null && boardingStop.isNotEmpty) ...[
                              Icon(Icons.arrow_upward, size: 11, color: AppColors.textTertiary),
                              const SizedBox(width: 2),
                              Flexible(
                                child: Text(boardingStop, style: const TextStyle(color: AppColors.textTertiary, fontSize: 11), overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Status badge
                _buildStatusBadge(status),
              ],
            ),
            const SizedBox(height: 12),
            // Check-in status and GPS info row
            Row(
              children: [
                // Check-in status
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getCheckInStatusColor(checkInStatus)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        checkInStatus == 'boarded'
                            ? Icons.directions_bus
                            : Icons.airline_seat_recline_normal,
                        size: 12,
                        color: _getCheckInStatusColor(checkInStatus),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _getCheckInStatusLabel(checkInStatus),
                        style: TextStyle(
                          color: _getCheckInStatusColor(checkInStatus),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Last GPS update / GPS status
                if (hasGps && lastGpsUpdate != null)
                  Text(
                    'GPS: ${_formatDateTime(lastGpsUpdate)}',
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 10,
                    ),
                  )
                else if (gpsEnabled)
                  const Text(
                    'GPS: Activado (sin señal)',
                    style: TextStyle(color: AppColors.textTertiary, fontSize: 10),
                  )
                else
                  const Text(
                    'GPS: Apagado',
                    style: TextStyle(color: AppColors.textTertiary, fontSize: 10),
                  ),
                const Spacer(),
                // Focus on map button
                if (hasGps)
                  GestureDetector(
                    onTap: () => _focusOnPassenger(id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.purple.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.my_location,
                              size: 14, color: AppColors.purple),
                          SizedBox(width: 4),
                          Text(
                            'Ver en mapa',
                            style: TextStyle(
                              color: AppColors.purple,
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
            const SizedBox(height: 12),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 12),
            // Contact action buttons
            Row(
              children: [
                // Contact buttons (if phone available)
                if (phone.isNotEmpty) ...[
                  _buildActionButton(
                    icon: Icons.phone,
                    color: AppColors.success,
                    onTap: () => _makePhoneCall(phone),
                    tooltip: 'Llamar',
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    icon: Icons.message,
                    color: AppColors.primary,
                    onTap: () => _openWhatsApp(phone),
                    tooltip: 'WhatsApp',
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    icon: Icons.sms,
                    color: AppColors.info,
                    onTap: () => _sendSms(phone),
                    tooltip: 'SMS',
                  ),
                ],
                const Spacer(),
                // View details button
                GestureDetector(
                  onTap: () => _showPassengerDetail(passenger),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.cardSecondary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Ver detalles',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.chevron_right,
                            size: 16, color: AppColors.textSecondary),
                      ],
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

  Widget _buildAvatar(String name, String? avatarUrl, String status) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: _getStatusColor(status).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        image: avatarUrl != null
            ? DecorationImage(
                image: NetworkImage(avatarUrl),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: avatarUrl == null
          ? Center(
              child: Text(
                _getInitials(name),
                style: TextStyle(
                  color: _getStatusColor(status),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildStatusBadge(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _getStatusColor(status).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getStatusIcon(status),
            size: 14,
            color: _getStatusColor(status),
          ),
          const SizedBox(width: 4),
          Text(
            _getStatusLabel(status),
            style: TextStyle(
              color: _getStatusColor(status),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }

  void _showPassengerDetail(Map<String, dynamic> passenger) {
    HapticService.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _PassengerDetailModal(
        passenger: passenger,
        passengerLocation: _passengerLocations[passenger['id']],
        onCall: _makePhoneCall,
        onWhatsApp: _openWhatsApp,
        onSms: _sendSms,
        onFocusMap: () {
          Navigator.pop(ctx);
          _focusOnPassenger(passenger['id']);
        },
        getPassengerName: _getPassengerName,
        getPassengerEmail: _getPassengerEmail,
        getPassengerPhone: _getPassengerPhone,
        getPassengerAvatar: _getPassengerAvatar,
        getInitials: _getInitials,
        getStatusColor: _getStatusColor,
        getStatusLabel: _getStatusLabel,
        getCheckInStatusLabel: _getCheckInStatusLabel,
        getCheckInStatusColor: _getCheckInStatusColor,
        formatDateTime: _formatDateTime,
      ),
    );
  }
}

// =============================================================================
// PASSENGER DETAIL MODAL
// =============================================================================

class _PassengerDetailModal extends StatelessWidget {
  final Map<String, dynamic> passenger;
  final LatLng? passengerLocation;
  final Function(String) onCall;
  final Function(String) onWhatsApp;
  final Function(String) onSms;
  final VoidCallback onFocusMap;
  final String Function(Map<String, dynamic>) getPassengerName;
  final String Function(Map<String, dynamic>) getPassengerEmail;
  final String Function(Map<String, dynamic>) getPassengerPhone;
  final String? Function(Map<String, dynamic>) getPassengerAvatar;
  final String Function(String) getInitials;
  final Color Function(String) getStatusColor;
  final String Function(String) getStatusLabel;
  final String Function(String?) getCheckInStatusLabel;
  final Color Function(String?) getCheckInStatusColor;
  final String Function(String?) formatDateTime;

  const _PassengerDetailModal({
    required this.passenger,
    required this.passengerLocation,
    required this.onCall,
    required this.onWhatsApp,
    required this.onSms,
    required this.onFocusMap,
    required this.getPassengerName,
    required this.getPassengerEmail,
    required this.getPassengerPhone,
    required this.getPassengerAvatar,
    required this.getInitials,
    required this.getStatusColor,
    required this.getStatusLabel,
    required this.getCheckInStatusLabel,
    required this.getCheckInStatusColor,
    required this.formatDateTime,
  });

  @override
  Widget build(BuildContext context) {
    final name = getPassengerName(passenger);
    final email = getPassengerEmail(passenger);
    final phone = getPassengerPhone(passenger);
    final avatarUrl = getPassengerAvatar(passenger);
    final status = passenger['status'] as String? ?? 'pending';
    final checkInStatus = passenger['current_check_in_status'] as String?;
    final invitationCode = passenger['invitation_code'] as String?;
    final createdAt = passenger['created_at'] as String?;
    final acceptedAt = passenger['accepted_at'] as String?;
    final lastCheckInAt = passenger['last_check_in_at'] as String?;
    final lastGpsUpdate = passenger['last_gps_update'] as String?;
    final seatNumber = passenger['seat_number'] as String?;
    final seatType = passenger['seat_type'] as String?;
    final specialNeeds = passenger['special_needs'] as String?;
    final dietaryRestrictions = passenger['dietary_restrictions'] as String?;
    final emergencyContact = passenger['emergency_contact'] as String?;
    final emergencyPhone = passenger['emergency_phone'] as String?;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: const EdgeInsets.all(24),
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
                  color: AppColors.textTertiary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Header with avatar
            Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: getStatusColor(status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    image: avatarUrl != null
                        ? DecorationImage(
                            image: NetworkImage(avatarUrl),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: avatarUrl == null
                      ? Center(
                          child: Text(
                            getInitials(name),
                            style: TextStyle(
                              color: getStatusColor(status),
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      : null,
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
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color:
                                  getStatusColor(status).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              getStatusLabel(status),
                              style: TextStyle(
                                color: getStatusColor(status),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: getCheckInStatusColor(checkInStatus)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              getCheckInStatusLabel(checkInStatus),
                              style: TextStyle(
                                color: getCheckInStatusColor(checkInStatus),
                                fontSize: 11,
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
            const SizedBox(height: 24),
            const Divider(color: AppColors.border),
            const SizedBox(height: 16),
            // Contact info
            if (email.isNotEmpty)
              _buildDetailRow(Icons.email_outlined, 'Email', email),
            if (phone.isNotEmpty)
              _buildDetailRow(Icons.phone_outlined, 'Telefono', phone),
            if (invitationCode != null)
              _buildDetailRow(Icons.qr_code, 'Codigo', invitationCode),
            // Seat info
            if (seatNumber != null || seatType != null)
              _buildDetailRow(
                Icons.airline_seat_recline_normal,
                'Asiento',
                '${seatNumber ?? '-'} (${seatType ?? 'standard'})',
              ),
            // Dates
            if (createdAt != null)
              _buildDetailRow(
                  Icons.event, 'Invitado', formatDateTime(createdAt)),
            if (acceptedAt != null)
              _buildDetailRow(
                  Icons.check_circle_outline, 'Acepto', formatDateTime(acceptedAt)),
            if (lastCheckInAt != null)
              _buildDetailRow(
                  Icons.how_to_reg, 'Check-in', formatDateTime(lastCheckInAt)),
            // GPS info
            if (passengerLocation != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: AppColors.purple.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.gps_fixed,
                            size: 16, color: AppColors.purple),
                        const SizedBox(width: 8),
                        const Text(
                          'Ubicacion GPS',
                          style: TextStyle(
                            color: AppColors.purple,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        if (lastGpsUpdate != null)
                          Text(
                            formatDateTime(lastGpsUpdate),
                            style: const TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${passengerLocation!.latitude.toStringAsFixed(6)}, ${passengerLocation!.longitude.toStringAsFixed(6)}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Special needs / dietary restrictions
            if (specialNeeds != null || dietaryRestrictions != null) ...[
              const SizedBox(height: 16),
              const Text(
                'Necesidades Especiales',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              if (specialNeeds != null)
                _buildInfoBox(Icons.accessible, specialNeeds),
              if (dietaryRestrictions != null)
                _buildInfoBox(Icons.restaurant, dietaryRestrictions),
            ],
            // Emergency contact
            if (emergencyContact != null || emergencyPhone != null) ...[
              const SizedBox(height: 16),
              const Text(
                'Contacto de Emergencia',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.emergency,
                        size: 16, color: AppColors.warning),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (emergencyContact != null)
                            Text(
                              emergencyContact,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                              ),
                            ),
                          if (emergencyPhone != null)
                            Text(
                              emergencyPhone,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (emergencyPhone != null)
                      IconButton(
                        icon: const Icon(Icons.phone, color: AppColors.warning),
                        onPressed: () => onCall(emergencyPhone),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            // Action buttons
            if (phone.isNotEmpty)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        onCall(phone);
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
                        Navigator.pop(context);
                        onWhatsApp(phone);
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
                        Navigator.pop(context);
                        onSms(phone);
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
            if (phone.isNotEmpty) const SizedBox(height: 12),
            // Focus on map button
            if (passengerLocation != null)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: onFocusMap,
                  icon: const Icon(Icons.my_location, size: 20),
                  label: const Text('Ver en Mapa'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.purple,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
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
            width: 80,
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBox(IconData icon, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardSecondary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textTertiary),
          const SizedBox(width: 12),
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
}
