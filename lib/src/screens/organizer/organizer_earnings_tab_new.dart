import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../config/supabase_config.dart';
import '../../services/organizer_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';

/// NEW Earnings tab - Sistema de Crédito Semanal
/// Muestra: balance crédito, eventos, estados de cuenta, breakdown completo
class OrganizerEarningsTabNew extends StatefulWidget {
  const OrganizerEarningsTabNew({super.key});

  @override
  State<OrganizerEarningsTabNew> createState() =>
      _OrganizerEarningsTabNewState();
}

enum _ViewMode { thisWeek, statements, allEvents }

class _OrganizerEarningsTabNewState extends State<OrganizerEarningsTabNew> {
  final OrganizerService _organizerService = OrganizerService();

  bool _isLoading = true;
  String? _error;
  _ViewMode _selectedMode = _ViewMode.thisWeek;
  bool _isSubmittingRequest = false;

  // Credit account
  Map<String, dynamic>? _creditAccount;

  // Reset requests
  List<Map<String, dynamic>> _resetRequests = [];

  // Current week events
  List<Map<String, dynamic>> _weekEvents = [];
  double _weekTotalKm = 0;
  double _weekTotalCost = 0;
  double _weekToroCommission = 0;

  // Statements
  List<Map<String, dynamic>> _statements = [];

  // All events
  List<Map<String, dynamic>> _allEvents = [];

  // Detailed event data for expanded cards
  Map<String, List<Map<String, dynamic>>> _eventChanges = {};
  Map<String, Map<String, int>> _eventStats = {};

  // Track which event cards are expanded
  final Set<String> _expandedEvents = {};

  // Dynamic commission rate (loaded from pricing_config)
  double _commissionRate = 0.18; // Default fallback, overwritten by DB value

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
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.driver?.odUserId;

      if (userId == null) {
        setState(() {
          _isLoading = false;
          _error = 'No se pudo obtener el usuario';
        });
        return;
      }

      // Get organizer_id from user
      final organizerResp = await SupabaseConfig.client
          .from('organizers')
          .select('id')
          .eq('user_id', userId)
          .maybeSingle();

      final organizerId = organizerResp?['id'];

      if (organizerId == null) {
        setState(() {
          _isLoading = false;
          _error = 'No tienes perfil de organizador';
        });
        return;
      }

      // Load this organizer's commission rate
      await _loadCommissionRate(organizerId);

      // Load credit account
      final creditResp = await SupabaseConfig.client
          .from('organizer_credit_accounts')
          .select()
          .eq('organizer_id', organizerId)
          .maybeSingle();

      // Load current week events
      final now = DateTime.now();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final weekStartStr = DateFormat('yyyy-MM-dd').format(weekStart);

      final weekEventsResp = await SupabaseConfig.client
          .from('tourism_events')
          .select('''
            *,
            driver:drivers(id, full_name, name),
            vehicle:bus_vehicles(vehicle_name, plate)
          ''')
          .eq('organizer_id', organizerId)
          .eq('status', 'completed')
          .gte('completed_at', weekStartStr)
          .order('completed_at', ascending: false);

      // Load statements
      final statementsResp = await SupabaseConfig.client
          .from('organizer_weekly_statements')
          .select()
          .eq('organizer_id', organizerId)
          .order('week_start_date', ascending: false)
          .limit(20);

      // Load all events
      final allEventsResp = await SupabaseConfig.client
          .from('tourism_events')
          .select('''
            *,
            driver:drivers(id, full_name, name),
            vehicle:bus_vehicles(vehicle_name, plate)
          ''')
          .eq('organizer_id', organizerId)
          .eq('status', 'completed')
          .order('completed_at', ascending: false)
          .limit(100);

      // Load reset requests
      final resetRequestsResp = await _organizerService.getMyResetRequests(
        userId,
      );

      if (mounted) {
        final weekEventsList = List<Map<String, dynamic>>.from(
          weekEventsResp as List? ?? [],
        );
        final allEventsList = List<Map<String, dynamic>>.from(
          allEventsResp as List? ?? [],
        );

        // Calculate week totals
        double totalKm = 0;
        double totalCost = 0;
        double totalCommission = 0;

        for (final event in weekEventsList) {
          final km = (event['total_distance_km'] as num?)?.toDouble() ?? 0;
          final pricePerKm = (event['price_per_km'] as num?)?.toDouble() ?? 85;
          final cost = km * pricePerKm;
          final commission = cost * _commissionRate;

          totalKm += km;
          totalCost += cost;
          totalCommission += commission;
        }

        // --- Load detailed event data (changes, invitation stats) ---
        final eventIds = [...weekEventsList, ...allEventsList]
            .map((e) => e['id'] as String?)
            .where((id) => id != null)
            .cast<String>()
            .toSet()
            .toList();

        final Map<String, List<Map<String, dynamic>>> loadedChanges = {};
        final Map<String, Map<String, int>> loadedStats = {};

        if (eventIds.isNotEmpty) {
          // Load audit log of itinerary changes
          try {
            final changesResp = await SupabaseConfig.client
                .from('tourism_event_changes')
                .select()
                .inFilter('event_id', eventIds)
                .order('created_at', ascending: false);

            for (final c in (changesResp as List)) {
              final eid = c['event_id'] as String?;
              if (eid != null) {
                loadedChanges
                    .putIfAbsent(eid, () => [])
                    .add(Map<String, dynamic>.from(c));
              }
            }
          } catch (_) {
            // tourism_event_changes table may not exist yet
          }

          // Load invitation and check-in counts per event
          for (final eid in eventIds) {
            try {
              final invResp = await SupabaseConfig.client
                  .from('tourism_invitations')
                  .select('id, status, gps_tracking_enabled, seat_number')
                  .eq('event_id', eid);
              final invs = List<Map<String, dynamic>>.from(invResp as List);
              final accepted = invs
                  .where(
                    (i) =>
                        i['status'] == 'accepted' ||
                        i['status'] == 'checked_in' ||
                        i['status'] == 'boarded',
                  )
                  .length;
              final checkedIn = invs
                  .where(
                    (i) =>
                        i['status'] == 'checked_in' || i['status'] == 'boarded',
                  )
                  .length;

              loadedStats[eid] = {
                'total_invited': invs.length,
                'accepted': accepted,
                'checked_in': checkedIn,
              };
            } catch (_) {
              // Silently skip if table doesn't exist
            }
          }
        }

        setState(() {
          _creditAccount = creditResp;
          _weekEvents = weekEventsList;
          _weekTotalKm = totalKm;
          _weekTotalCost = totalCost;
          _weekToroCommission = totalCommission;
          _statements = List<Map<String, dynamic>>.from(
            statementsResp as List? ?? [],
          );
          _allEvents = allEventsList;
          _resetRequests = resetRequestsResp;
          _eventChanges = loadedChanges;
          _eventStats = loadedStats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Error: $e';
        });
      }
    }
  }

  /// Load this organizer's commission rate from their record.
  /// Each organizer negotiates their own % (e.g., 3%, 10%, 18%).
  /// Falls back to 0.18 (18%) only if the DB query fails.
  Future<void> _loadCommissionRate(String organizerId) async {
    try {
      // Read THIS organizer's commission_rate
      final orgResp = await SupabaseConfig.client
          .from('organizers')
          .select('commission_rate')
          .eq('id', organizerId)
          .maybeSingle();

      if (orgResp != null && orgResp['commission_rate'] != null) {
        final rate = (orgResp['commission_rate'] as num).toDouble();
        _commissionRate = rate / 100.0;
        debugPrint('ORGANIZER_EARNINGS -> Commission from organizer: $rate%');
        return;
      }

      debugPrint(
        'ORGANIZER_EARNINGS -> No commission_rate on organizer, using default 18%',
      );
    } catch (e) {
      debugPrint(
        'ORGANIZER_EARNINGS -> Error loading commission rate: $e, using default 18%',
      );
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
          'Ingresos',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        centerTitle: false,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _error != null
          ? _buildErrorState()
          : RefreshIndicator(
              color: AppColors.primary,
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
            Icon(
              Icons.error_outline,
              size: 48,
              color: AppColors.error.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 16),
            Text(
              _error ?? '',
              style: const TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadData,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
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
      padding: const EdgeInsets.all(16),
      children: [
        // Credit account card
        _buildCreditCard(),
        const SizedBox(height: 12),

        // Request assistance button
        _buildRequestAssistanceButton(),
        const SizedBox(height: 16),

        // Mode selector
        _buildModeSelector(),
        const SizedBox(height: 20),

        // Content by mode
        if (_selectedMode == _ViewMode.thisWeek) ..._buildThisWeekView(),
        if (_selectedMode == _ViewMode.statements) ..._buildStatementsView(),
        if (_selectedMode == _ViewMode.allEvents) ..._buildAllEventsView(),
      ],
    );
  }

  Widget _buildCreditCard() {
    final creditLimit =
        (_creditAccount?['credit_limit'] as num?)?.toDouble() ?? 0;
    final currentBalance =
        (_creditAccount?['current_balance'] as num?)?.toDouble() ?? 0;
    final availableCredit = creditLimit - currentBalance;
    final status = _creditAccount?['status'] as String? ?? 'unknown';

    Color statusColor = AppColors.success;
    String statusText = 'Activo';

    if (status == 'suspended') {
      statusColor = AppColors.warning;
      statusText = 'Suspendido';
    } else if (status == 'blocked') {
      statusColor = AppColors.error;
      statusText = 'Bloqueado';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.15),
            AppColors.primaryLight.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Cuenta de Crédito',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Crédito Disponible',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '\$${availableCredit.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 40, color: AppColors.border),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Deuda Actual',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '\$${currentBalance.toStringAsFixed(0)}',
                      style: TextStyle(
                        color: currentBalance > 0
                            ? AppColors.error
                            : AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Límite Total: \$${creditLimit.toStringAsFixed(0)}',
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                ),
              ),
              const Text(
                '⚠️ Pago en efectivo',
                style: TextStyle(
                  color: AppColors.warning,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRequestAssistanceButton() {
    final currentBalance =
        (_creditAccount?['current_balance'] as num?)?.toDouble() ?? 0;
    final status = _creditAccount?['status'] as String? ?? 'active';

    // Check if there's already a pending request
    final hasPendingRequest = _resetRequests.any(
      (r) => r['status'] == 'pending',
    );

    if (hasPendingRequest) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.hourglass_top, color: AppColors.warning, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Solicitud en proceso',
                    style: TextStyle(
                      color: AppColors.warning,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tu solicitud de limpieza de semana esta pendiente de revision por TORO',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Show button if there's a balance or account is blocked/suspended
    if (currentBalance <= 0 && status == 'active') {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isSubmittingRequest
            ? null
            : () => _showRequestAssistanceDialog(currentBalance),
        icon: _isSubmittingRequest
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.support_agent, size: 18),
        label: Text(
          _isSubmittingRequest
              ? 'Enviando...'
              : 'Pedir Asistencia para Limpiar Semana',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  void _showRequestAssistanceDialog(double amountOwed) {
    final messageController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Solicitar Limpieza de Semana',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.account_balance_wallet,
                    color: AppColors.error,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Deuda Pendiente',
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 10,
                        ),
                      ),
                      Text(
                        '\$${amountOwed.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: AppColors.error,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Al enviar esta solicitud, confirmas que ya realizaste el pago a TORO. El equipo verificara y limpiara tu cuenta.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: messageController,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Mensaje opcional (referencia de pago, etc.)',
                hintStyle: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 12,
                ),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.primary),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: AppColors.textTertiary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _submitResetRequest(amountOwed, messageController.text.trim());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Enviar Solicitud'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitResetRequest(double amountOwed, String message) async {
    setState(() => _isSubmittingRequest = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.driver?.odUserId;

      if (userId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: No se pudo obtener tu ID'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }

      // Get organizer_id
      final organizerResp = await SupabaseConfig.client
          .from('organizers')
          .select('id')
          .eq('user_id', userId)
          .maybeSingle();

      final organizerId = organizerResp?['id'];

      await _organizerService.submitWeekResetRequest(
        requesterId: userId,
        requesterType: 'organizer',
        organizerId: organizerId?.toString(),
        amountOwed: amountOwed,
        message: message.isNotEmpty ? message : null,
      );

      if (mounted) {
        HapticService.success();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Solicitud enviada. TORO revisara tu pago.'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmittingRequest = false);
      }
    }
  }

  Widget _buildModeSelector() {
    return Row(
      children: [
        _buildModeChip(
          label: 'Esta Semana',
          mode: _ViewMode.thisWeek,
          count: _weekEvents.length,
        ),
        const SizedBox(width: 8),
        _buildModeChip(
          label: 'Estados Cuenta',
          mode: _ViewMode.statements,
          count: _statements.length,
        ),
        const SizedBox(width: 8),
        _buildModeChip(
          label: 'Todos',
          mode: _ViewMode.allEvents,
          count: _allEvents.length,
        ),
      ],
    );
  }

  Widget _buildModeChip({
    required String label,
    required _ViewMode mode,
    required int count,
  }) {
    final isSelected = _selectedMode == mode;
    return GestureDetector(
      onTap: () {
        HapticService.lightImpact();
        setState(() => _selectedMode = mode);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.25)
                      : AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildThisWeekView() {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));
    final dueDate = weekEnd.add(const Duration(days: 3));

    return [
      // Week summary
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Semana Actual: ${DateFormat('dd MMM').format(weekStart)} - ${DateFormat('dd MMM').format(weekEnd)}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildKPI(
                    'Eventos',
                    '${_weekEvents.length}',
                    Icons.event,
                    AppColors.primary,
                  ),
                ),
                Expanded(
                  child: _buildKPI(
                    'Km Total',
                    _weekTotalKm.toStringAsFixed(0),
                    Icons.route,
                    AppColors.success,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildKPI(
                    'Total Chofer',
                    '\$${_weekTotalCost.toStringAsFixed(0)}',
                    Icons.attach_money,
                    AppColors.warning,
                  ),
                ),
                Expanded(
                  child: _buildKPI(
                    'TORO (${(_commissionRate * 100).toStringAsFixed(0)}%)',
                    '\$${_weekToroCommission.toStringAsFixed(0)}',
                    Icons.account_balance,
                    AppColors.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Corte: ${DateFormat('dd MMM yyyy').format(weekEnd)}',
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 10,
                  ),
                ),
                Text(
                  'Pago antes: ${DateFormat('dd MMM').format(dueDate)}',
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        'Eventos de la Semana',
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 12),
      if (_weekEvents.isEmpty)
        _buildEmptyState('Sin eventos esta semana')
      else
        ..._weekEvents.map((e) => _buildEventCard(e)),
    ];
  }

  List<Widget> _buildStatementsView() {
    return [
      const Text(
        'Estados de Cuenta Semanales',
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 12),
      if (_statements.isEmpty)
        _buildEmptyState('Sin estados de cuenta')
      else
        ..._statements.map((s) => _buildStatementCard(s)),
    ];
  }

  List<Widget> _buildAllEventsView() {
    return [
      const Text(
        'Todos los Eventos',
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 12),
      if (_allEvents.isEmpty)
        _buildEmptyState('Sin eventos completados')
      else
        ..._allEvents.map((e) => _buildEventCard(e)),
    ];
  }

  Widget _buildKPI(String label, String value, IconData icon, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 10,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildEventCard(Map<String, dynamic> event) {
    final eventId = event['id'] as String? ?? '';
    final eventName = event['event_name'] ?? 'Sin nombre';
    final km = (event['total_distance_km'] as num?)?.toDouble() ?? 0;
    final pricePerKm = (event['price_per_km'] as num?)?.toDouble() ?? 85;
    final cost = km * pricePerKm;
    final commission = cost * _commissionRate;
    final net = cost - commission;
    final driverName =
        event['driver']?['full_name'] ??
        event['driver']?['name'] ??
        'Sin chofer';
    final driverPhone = event['driver']?['phone'] as String? ?? '';
    final vehicleName = event['vehicle']?['vehicle_name'] ?? 'Sin vehiculo';
    final vehiclePlate = event['vehicle']?['plate'] as String? ?? '';
    final completedAt = event['completed_at'] as String?;
    final eventDate = event['event_date'] as String?;
    final startTime = event['start_time'] as String?;
    final endTime = event['end_time'] as String?;
    final maxPassengers = (event['max_passengers'] as num?)?.toInt() ?? 0;
    final itinerary = event['itinerary'];

    final isExpanded = _expandedEvents.contains(eventId);

    // Stats for this event
    final stats = _eventStats[eventId];
    final acceptedCount = stats?['accepted'] ?? 0;
    final checkedInCount = stats?['checked_in'] ?? 0;

    // Changes log
    final changes = _eventChanges[eventId] ?? [];

    // Parse itinerary route
    List<String> routeStops = [];
    if (itinerary != null) {
      try {
        final dynamic itin = itinerary is String
            ? jsonDecode(itinerary)
            : itinerary;
        if (itin is Map) {
          final origin = itin['origin'] as String?;
          final destination = itin['destination'] as String?;
          final stops = itin['stops'] as List?;
          if (origin != null && origin.isNotEmpty) routeStops.add(origin);
          if (stops != null) {
            for (final s in stops) {
              final stopName = s is Map
                  ? (s['name'] ?? s['location'] ?? s.toString())
                  : s.toString();
              routeStops.add(stopName.toString());
            }
          }
          if (destination != null && destination.isNotEmpty)
            routeStops.add(destination);
        } else if (itin is List) {
          for (final s in itin) {
            final stopName = s is Map
                ? (s['name'] ?? s['location'] ?? s.toString())
                : s.toString();
            routeStops.add(stopName.toString());
          }
        }
      } catch (_) {
        // Could not parse itinerary
      }
    }

    return GestureDetector(
      onTap: () {
        HapticService.lightImpact();
        setState(() {
          if (isExpanded) {
            _expandedEvents.remove(eventId);
          } else {
            _expandedEvents.add(eventId);
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isExpanded
                ? AppColors.primary.withValues(alpha: 0.4)
                : AppColors.border,
            width: isExpanded ? 1.0 : 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Header (always visible) ---
            Row(
              children: [
                Expanded(
                  child: Text(
                    eventName,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '\$${cost.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: AppColors.success,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: Icon(
                    Icons.expand_more,
                    size: 20,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),

            // Compact summary when collapsed
            if (!isExpanded) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    Icons.directions_bus,
                    size: 12,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      vehicleName,
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Icon(Icons.person, size: 12, color: AppColors.textTertiary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      driverName,
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${km.toStringAsFixed(0)} km',
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    'TORO: \$${commission.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: AppColors.error,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],

            // --- Expanded detail sheet ---
            if (isExpanded) ...[
              const SizedBox(height: 12),
              const Divider(color: AppColors.border, height: 1),
              const SizedBox(height: 12),

              // Fecha y Hora
              _buildDetailSection(
                icon: Icons.calendar_today,
                title: 'Fecha y Hora',
                child: Text(
                  '${eventDate != null ? _formatDate(eventDate) : 'N/A'}  ${startTime ?? ''} - ${endTime ?? ''}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Ruta
              if (routeStops.isNotEmpty) ...[
                _buildDetailSection(
                  icon: Icons.route,
                  title: 'Ruta',
                  child: _buildRouteWidget(routeStops),
                ),
                const SizedBox(height: 10),
              ],

              // Distancia
              _buildDetailSection(
                icon: Icons.straighten,
                title: 'Distancia',
                child: Text(
                  '${km.toStringAsFixed(1)} km',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Chofer
              _buildDetailSection(
                icon: Icons.person,
                title: 'Chofer',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      driverName,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                      ),
                    ),
                    if (driverPhone.isNotEmpty)
                      Text(
                        driverPhone,
                        style: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Vehiculo
              _buildDetailSection(
                icon: Icons.directions_bus,
                title: 'Vehiculo',
                child: Text(
                  '$vehicleName${vehiclePlate.isNotEmpty ? '  [$vehiclePlate]' : ''}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Pasajeros
              _buildDetailSection(
                icon: Icons.group,
                title: 'Pasajeros',
                child: Row(
                  children: [
                    Text(
                      '$acceptedCount',
                      style: const TextStyle(
                        color: AppColors.success,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      ' / $maxPassengers',
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (checkedInCount > 0) ...[
                      Icon(
                        Icons.check_circle,
                        size: 12,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$checkedInCount check-ins',
                        style: const TextStyle(
                          color: AppColors.success,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Financiero
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.attach_money,
                          size: 14,
                          color: AppColors.warning,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Financiero',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildFinancialRow(
                      '${km.toStringAsFixed(1)} km x \$${pricePerKm.toStringAsFixed(0)}/km',
                      '\$${cost.toStringAsFixed(0)}',
                      AppColors.textPrimary,
                    ),
                    const SizedBox(height: 4),
                    _buildFinancialRow(
                      'TORO (${(_commissionRate * 100).toStringAsFixed(0)}%)',
                      '-\$${commission.toStringAsFixed(0)}',
                      AppColors.error,
                    ),
                    const SizedBox(height: 6),
                    const Divider(color: AppColors.border, height: 1),
                    const SizedBox(height: 6),
                    _buildFinancialRow(
                      'Neto Chofer',
                      '\$${net.toStringAsFixed(0)}',
                      AppColors.success,
                      bold: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Cambios al itinerario
              if (changes.isNotEmpty) ...[
                _buildDetailSection(
                  icon: Icons.history,
                  title: 'Cambios al Itinerario (${changes.length})',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: changes.take(5).map((c) {
                      final changeDate = c['created_at'] as String?;
                      final changeType =
                          c['change_type'] as String? ??
                          c['type'] as String? ??
                          '';
                      final summary =
                          c['summary'] as String? ??
                          c['description'] as String? ??
                          changeType;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.only(top: 5, right: 8),
                              decoration: BoxDecoration(
                                color: AppColors.warning,
                                shape: BoxShape.circle,
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    summary,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 11,
                                    ),
                                  ),
                                  if (changeDate != null)
                                    Text(
                                      _formatDate(changeDate),
                                      style: const TextStyle(
                                        color: AppColors.textDisabled,
                                        fontSize: 9,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // Fecha completado
              if (completedAt != null)
                _buildDetailSection(
                  icon: Icons.check_circle_outline,
                  title: 'Completado',
                  child: Text(
                    _formatDate(completedAt),
                    style: const TextStyle(
                      color: AppColors.success,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// Builds a labeled detail row used inside the expanded event card.
  Widget _buildDetailSection({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              child,
            ],
          ),
        ),
      ],
    );
  }

  /// Renders the route as a vertical chain: origin -> stop -> ... -> destination.
  Widget _buildRouteWidget(List<String> stops) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(stops.length, (i) {
        final isLast = i == stops.length - 1;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == 0
                        ? AppColors.success
                        : isLast
                        ? AppColors.error
                        : AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Container(width: 1, height: 16, color: AppColors.border),
              ],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  stops[i],
                  style: TextStyle(
                    color: i == 0 || isLast
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: i == 0 || isLast
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  /// Renders a single financial line item (label on left, amount on right).
  Widget _buildFinancialRow(
    String label,
    String amount,
    Color amountColor, {
    bool bold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.textTertiary,
            fontSize: 11,
            fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        Text(
          amount,
          style: TextStyle(
            color: amountColor,
            fontSize: bold ? 14 : 12,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildStatementCard(Map<String, dynamic> statement) {
    final weekStart = statement['week_start_date'] as String?;
    final weekEnd = statement['week_end_date'] as String?;
    final totalEvents = statement['total_events'] as int? ?? 0;
    final totalKm = (statement['total_km'] as num?)?.toDouble() ?? 0;
    final amountDue = (statement['amount_due'] as num?)?.toDouble() ?? 0;
    final paymentStatus = statement['payment_status'] as String? ?? 'pending';
    final paidAt = statement['paid_at'] as String?;

    Color statusColor = AppColors.warning;
    String statusText = 'Pendiente';

    if (paymentStatus == 'paid') {
      statusColor = AppColors.success;
      statusText = 'Pagado';
    } else if (paymentStatus == 'overdue') {
      statusColor = AppColors.error;
      statusText = 'Vencido';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Semana: ${weekStart ?? ''} - ${weekEnd ?? ''}',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  statusText,
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
          Row(
            children: [
              Text(
                '$totalEvents eventos',
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${totalKm.toStringAsFixed(0)} km',
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total a Pagar TORO:',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
              Text(
                '\$${amountDue.toStringAsFixed(0)}',
                style: const TextStyle(
                  color: AppColors.error,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (paidAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Pagado: ${_formatDate(paidAt)}',
              style: const TextStyle(color: AppColors.success, fontSize: 9),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 40,
            color: AppColors.textTertiary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 14),
          ),
        ],
      ),
    );
  }

  String _formatDate(String isoDate) {
    final dt = DateTime.tryParse(isoDate);
    if (dt == null) return isoDate;
    return DateFormat('dd MMM yyyy').format(dt);
  }
}
