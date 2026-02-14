import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';
import 'bus_location_map_screen.dart';

/// Dashboard tab for the organizer home screen.
///
/// Displays summary KPIs from tourism_events and recent event activity.
class OrganizerDashboardTab extends StatefulWidget {
  const OrganizerDashboardTab({super.key});

  @override
  State<OrganizerDashboardTab> createState() => _OrganizerDashboardTabState();
}

class _OrganizerDashboardTabState extends State<OrganizerDashboardTab> {
  final _client = Supabase.instance.client;

  bool _isLoading = true;
  String? _error;

  int _activeEventsCount = 0;
  int _totalPassengers = 0;
  int _acceptedPassengers = 0;
  int _pendingInvitations = 0;
  List<Map<String, dynamic>> _recentEvents = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        setState(() {
          _isLoading = false;
          _error = 'No se pudo obtener el perfil del organizador';
        });
        return;
      }

      // Get organizer ID
      final organizerResponse = await _client
          .from('organizers')
          .select('id')
          .eq('user_id', userId)
          .maybeSingle();

      if (organizerResponse == null) {
        setState(() {
          _isLoading = false;
          _error = 'No eres un organizador registrado';
        });
        return;
      }

      final organizerId = organizerResponse['id'];

      // Load events for this organizer
      final eventsResponse = await _client
          .from('tourism_events')
          .select('''
            id,
            event_name,
            event_date,
            start_time,
            status,
            itinerary,
            max_passengers
          ''')
          .eq('organizer_id', organizerId)
          .order('event_date', ascending: false);

      final events = List<Map<String, dynamic>>.from(eventsResponse);

      // Count active events
      final activeEvents = events.where((e) =>
          e['status'] == 'active' ||
          e['status'] == 'in_progress' ||
          e['status'] == 'vehicle_accepted').toList();

      // Get all event IDs to load invitations
      final eventIds = events.map((e) => e['id']).toList();

      int totalPassengers = 0;
      int acceptedPassengers = 0;
      int pendingInvitations = 0;

      if (eventIds.isNotEmpty) {
        // Load invitation stats
        final invitationsResponse = await _client
            .from('tourism_invitations')
            .select('id, status, gps_tracking_enabled, seat_number')
            .inFilter('event_id', eventIds);

        final invitations = List<Map<String, dynamic>>.from(invitationsResponse);
        totalPassengers = invitations.length;
        acceptedPassengers = invitations.where((i) =>
            i['status'] == 'accepted' || i['status'] == 'boarded' || i['status'] == 'checked_in').length;
        pendingInvitations = invitations.where((i) => i['status'] == 'pending').length;
      }

      if (mounted) {
        setState(() {
          _activeEventsCount = activeEvents.length;
          _totalPassengers = totalPassengers;
          _acceptedPassengers = acceptedPassengers;
          _pendingInvitations = pendingInvitations;
          _recentEvents = events.take(10).toList();
          _isLoading = false;
        });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
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
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        // Header with gradient
        _buildHeader(),

        // KPIs row - 4 items spread evenly
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  icon: Icons.event,
                  value: '$_activeEventsCount',
                  label: 'Activos',
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildKpiCard(
                  icon: Icons.people,
                  value: '$_totalPassengers',
                  label: 'Invitados',
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildKpiCard(
                  icon: Icons.check_circle,
                  value: '$_acceptedPassengers',
                  label: 'Aceptados',
                  color: AppColors.purple,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildKpiCard(
                  icon: Icons.pending,
                  value: '$_pendingInvitations',
                  label: 'Pendientes',
                  color: AppColors.warning,
                ),
              ),
            ],
          ),
        ),

        // Quick action - Live Map
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildQuickActionButton(
            icon: Icons.map,
            label: 'Ver Mapa en Tiempo Real',
            subtitle: 'Eventos y pasajeros con GPS',
            color: AppColors.success,
            onTap: () {
              HapticService.mediumImpact();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BusLocationMapScreen(),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),

        // Recent activity header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: const Row(
            children: [
              Icon(Icons.history, size: 18, color: AppColors.textSecondary),
              SizedBox(width: 8),
              Text(
                'Mis Eventos',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Recent events list
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _recentEvents.isEmpty
              ? _buildEmptyActivity()
              : Column(
                  children: _recentEvents.map(_buildEventActivityCard).toList(),
                ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 16,
        20,
        20,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.15),
            AppColors.surface,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.dashboard,
              color: AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dashboard',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Resumen de tus eventos',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          // Edit organizer profile
          IconButton(
            icon: const Icon(Icons.business, color: AppColors.primary),
            tooltip: 'Perfil de Empresa',
            onPressed: () {
              HapticService.lightImpact();
              Navigator.pushNamed(context, '/organizer-profile');
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
            onPressed: () {
              HapticService.lightImpact();
              _loadData();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyActivity() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        children: [
          Icon(Icons.event_busy,
              size: 40, color: AppColors.textTertiary.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          const Text(
            'Sin eventos creados',
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Crea tu primer evento en la pestaña Eventos',
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventActivityCard(Map<String, dynamic> event) {
    final name = event['event_name'] ?? 'Evento';
    final itinerary = event['itinerary'] as List<dynamic>?;
    final destination = itinerary != null && itinerary.length > 1
        ? (itinerary[itinerary.length - 2]['name'] as String? ?? '')
        : '';
    final status = event['status'] ?? 'draft';
    final eventDate = event['event_date'] ?? '';
    final startTime = event['start_time'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _statusColor(status).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.event, size: 18, color: _statusColor(status)),
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
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      _formatDate(eventDate),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    if (startTime != null) ...[
                      const Text(
                        ' • ',
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        startTime.substring(0, 5),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
                if (destination.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.location_on,
                          size: 10, color: AppColors.textTertiary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          destination,
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 10,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          _buildStatusBadge(status),
        ],
      ),
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
      case 'active':
      case 'vehicle_accepted':
        return AppColors.primary;
      case 'in_progress':
        return AppColors.warning;
      case 'completed':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      case 'draft':
        return AppColors.textTertiary;
      default:
        return AppColors.textTertiary;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return 'Activo';
      case 'vehicle_accepted':
        return 'Vehículo OK';
      case 'in_progress':
        return 'En curso';
      case 'completed':
        return 'Completado';
      case 'cancelled':
        return 'Cancelado';
      case 'draft':
        return 'Esperando Puja';
      default:
        return status;
    }
  }

  String _formatDate(String isoDate) {
    final dt = DateTime.tryParse(isoDate);
    if (dt == null) return isoDate;
    final months = [
      'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
      'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.2),
              color.withValues(alpha: 0.1),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color, size: 16),
          ],
        ),
      ),
    );
  }
}
