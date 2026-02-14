import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/organizer_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';

/// Earnings tab for the organizer home screen.
///
/// Shows total commission earned (3%), a date-range filter (this week,
/// this month, all time), a list of reservations with per-reservation
/// commission, and a placeholder "Exportar PDF" button.
class OrganizerEarningsTab extends StatefulWidget {
  const OrganizerEarningsTab({super.key});

  @override
  State<OrganizerEarningsTab> createState() => _OrganizerEarningsTabState();
}

enum _DateRange { thisWeek, thisMonth, allTime }

class _OrganizerEarningsTabState extends State<OrganizerEarningsTab> {
  final OrganizerService _organizerService = OrganizerService();

  bool _isLoading = true;
  String? _error;
  _DateRange _selectedRange = _DateRange.thisMonth;

  double _totalCommission = 0;
  int _totalReservations = 0;
  List<Map<String, dynamic>> _reservations = [];

  @override
  void initState() {
    super.initState();
    _loadEarnings();
  }

  DateTime? _rangeFrom() {
    final now = DateTime.now();
    switch (_selectedRange) {
      case _DateRange.thisWeek:
        return now.subtract(Duration(days: now.weekday - 1));
      case _DateRange.thisMonth:
        return DateTime(now.year, now.month, 1);
      case _DateRange.allTime:
        return null;
    }
  }

  Future<void> _loadEarnings() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authProvider =
          Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.driver?.id;

      if (userId == null) {
        setState(() {
          _isLoading = false;
          _error = 'No se pudo obtener el perfil del organizador';
        });
        return;
      }

      final profile =
          await _organizerService.getOrganizerProfile(userId);
      final organizerId = profile?['id']?.toString() ?? userId;

      final result = await _organizerService.getEarnings(
        organizerId,
        from: _rangeFrom(),
      );

      if (mounted) {
        setState(() {
          _totalCommission =
              (result['total_commission'] as num?)?.toDouble() ?? 0;
          _totalReservations =
              (result['total_reservations'] as num?)?.toInt() ?? 0;
          _reservations = List<Map<String, dynamic>>.from(
              result['reservations'] ?? []);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Error al cargar ingresos: $e';
        });
      }
    }
  }

  void _onRangeChanged(_DateRange range) {
    HapticService.lightImpact();
    setState(() => _selectedRange = range);
    _loadEarnings();
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
        actions: [
          TextButton.icon(
            onPressed: () {
              HapticService.lightImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Proximamente'),
                  backgroundColor: AppColors.primary,
                ),
              );
            },
            icon: const Icon(Icons.picture_as_pdf,
                size: 16, color: AppColors.primary),
            label: const Text(
              'Exportar PDF',
              style: TextStyle(color: AppColors.primary, fontSize: 13),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _error != null
              ? _buildErrorState()
              : RefreshIndicator(
                  color: AppColors.primary,
                  backgroundColor: AppColors.surface,
                  onRefresh: _loadEarnings,
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
                  color: AppColors.textSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadEarnings,
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
      padding: const EdgeInsets.all(16),
      children: [
        // Summary card
        _buildSummaryCard(),
        const SizedBox(height: 16),
        // Date range filter
        _buildDateRangeFilter(),
        const SizedBox(height: 20),
        // Reservations header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Reservaciones',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '$_totalReservations total',
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Reservations list
        if (_reservations.isEmpty)
          _buildEmptyState()
        else
          ..._reservations.map(_buildReservationCard),
      ],
    );
  }

  Widget _buildSummaryCard() {
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
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Total earnings
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Total Ingresos',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '\$${_totalCommission.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '3% comision',
                    style: TextStyle(
                      color: AppColors.success,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Divider
          Container(
            width: 1,
            height: 60,
            color: AppColors.border,
          ),
          const SizedBox(width: 20),
          // Total reservations
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'Reservaciones',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$_totalReservations',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _buildDateRangeFilter() {
    return Row(
      children: [
        _buildFilterChip(
          label: 'Esta Semana',
          range: _DateRange.thisWeek,
        ),
        const SizedBox(width: 8),
        _buildFilterChip(
          label: 'Este Mes',
          range: _DateRange.thisMonth,
        ),
        const SizedBox(width: 8),
        _buildFilterChip(
          label: 'Todo',
          range: _DateRange.allTime,
        ),
      ],
    );
  }

  Widget _buildFilterChip({
    required String label,
    required _DateRange range,
  }) {
    final isSelected = _selectedRange == range;

    return GestureDetector(
      onTap: () => _onRangeChanged(range),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.border,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 40,
              color: AppColors.textTertiary.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          const Text(
            'Sin reservaciones en este periodo',
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReservationCard(Map<String, dynamic> reservation) {
    final commission =
        (reservation['organizer_commission'] as num?)?.toDouble() ?? 0;
    final seats = (reservation['seats'] as num?)?.toInt() ?? 1;
    final passengerName =
        reservation['passenger_name'] ?? 'Pasajero';
    final createdAt = reservation['created_at'] ?? '';
    final totalAmount =
        (reservation['total_amount'] as num?)?.toDouble() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          // Commission icon
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.paid,
                size: 20, color: AppColors.success),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  passengerName,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      '$seats asiento${seats == 1 ? '' : 's'}',
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Total: \$${totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDate(createdAt),
                  style: const TextStyle(
                    color: AppColors.textDisabled,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          // Commission amount
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '+\$${commission.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: AppColors.success,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Text(
                'comision',
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
}
