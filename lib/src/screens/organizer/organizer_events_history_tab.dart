import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/supabase_config.dart';
import '../../providers/auth_provider.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';

/// PANTALLA DE HISTORIAL DE EVENTOS - ORGANIZER
/// Muestra todos los eventos completados con tracking completo
/// Conectado a arquitectura fiscal MX (IVA, CFDI)
class OrganizerEventsHistoryTab extends StatefulWidget {
  const OrganizerEventsHistoryTab({super.key});

  @override
  State<OrganizerEventsHistoryTab> createState() => _OrganizerEventsHistoryTabState();
}

class _OrganizerEventsHistoryTabState extends State<OrganizerEventsHistoryTab> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _allEvents = [];
  List<Map<String, dynamic>> _filteredEvents = [];
  String _filterStatus = 'all';

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  List<Map<String, dynamic>> _applyFilter(List<Map<String, dynamic>> events) {
    if (_filterStatus == 'all') return events;
    return events.where((e) => e['status'] == _filterStatus).toList();
  }

  Future<void> _loadEvents() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.driver?.id;

      if (userId == null) {
        setState(() {
          _isLoading = false;
          _error = 'event_history.error_profile'.tr();
        });
        return;
      }

      final profile = await SupabaseConfig.client
          .from('organizers')
          .select('id')
          .eq('user_id', userId)
          .maybeSingle();

      final organizerId = profile?['id'] ?? userId;

      final response = await SupabaseConfig.client
          .from('tourism_events')
          .select('*')
          .eq('organizer_id', organizerId)
          .order('event_date', ascending: false);

      if (mounted) {
        setState(() {
          _allEvents = List<Map<String, dynamic>>.from(response);
          _filteredEvents = _applyFilter(_allEvents);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = '${'event_history.error_loading'.tr()}: $e';
        });
      }
    }
  }

  // Calculate financial breakdown for an event
  Map<String, double> _calcFinancials(Map<String, dynamic> event) {
    final pricePerKm = (event['price_per_km'] as num?)?.toDouble() ?? 0;
    final distance = (event['total_distance_km'] as num?)?.toDouble() ?? 0;
    final commissionRate = (event['toro_commission_rate'] as num?)?.toDouble() ?? 0.18;
    final isMX = (event['country_code'] as String?) == 'MX';

    final driverPayment = pricePerKm * distance;
    final commission = driverPayment * commissionRate;
    final iva = isMX ? commission * 0.16 : 0.0;
    final total = driverPayment + commission + iva;

    return {
      'driverPayment': driverPayment,
      'commissionRate': commissionRate,
      'commission': commission,
      'iva': iva,
      'total': total,
      'distance': distance,
    };
  }

  String _formatCurrency(double amount, String? currency) {
    final cur = currency ?? 'MXN';
    return '\$${amount.toStringAsFixed(2)} $cur';
  }

  Future<void> _downloadEventReport(Map<String, dynamic> event) async {
    HapticService.mediumImpact();

    try {
      final report = _generateReport(event);

      final directory = await getTemporaryDirectory();
      final fileName = 'TORO_Evento_${event['event_name']}_${DateFormat('yyyyMMdd').format(DateTime.parse(event['event_date']))}.txt';
      final file = File('${directory.path}/$fileName');
      await file.writeAsString(report);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: '${'event_history.report_title'.tr()} - ${event['event_name']}',
      );

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  String _generateReport(Map<String, dynamic> event) {
    final buffer = StringBuffer();
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final fin = _calcFinancials(event);
    final currency = event['currency'] as String? ?? 'MXN';
    final isMX = (event['country_code'] as String?) == 'MX';
    final commissionPct = ((fin['commissionRate']! * 100)).toStringAsFixed(0);

    buffer.writeln('=' * 60);
    buffer.writeln('event_history.report_title'.tr());
    buffer.writeln('=' * 60);
    buffer.writeln();

    buffer.writeln('event_history.report_event_info'.tr());
    buffer.writeln('-' * 40);
    buffer.writeln('${'event_history.date'.tr()}: ${event['event_date']}');
    buffer.writeln('${'event_history.time'.tr()}: ${event['start_time']}');
    buffer.writeln('${'event_history.status'.tr()}: ${event['status']}');
    buffer.writeln('${'event_history.distance'.tr()}: ${event['total_distance_km']} km');
    buffer.writeln();

    if (event['vehicle_id'] != null) {
      buffer.writeln('event_history.report_vehicle_info'.tr());
      buffer.writeln('-' * 40);
      buffer.writeln('ID: ${event['vehicle_id']}');
      buffer.writeln();
    }

    buffer.writeln('event_history.report_financial'.tr());
    buffer.writeln('-' * 40);
    buffer.writeln('${'event_history.driver_payment'.tr()} ${_formatCurrency(fin['driverPayment']!, currency)}');
    buffer.writeln('${'event_history.toro_commission'.tr(namedArgs: {'rate': commissionPct})} ${_formatCurrency(fin['commission']!, currency)}');
    if (isMX) {
      buffer.writeln('${'event_history.iva_tax'.tr()} ${_formatCurrency(fin['iva']!, currency)}');
    }
    buffer.writeln('${'event_history.total'.tr()} ${_formatCurrency(fin['total']!, currency)}');
    buffer.writeln();

    buffer.writeln('event_history.report_itinerary'.tr());
    buffer.writeln('-' * 40);
    final itinerary = event['itinerary'] as List<dynamic>? ?? [];
    for (int i = 0; i < itinerary.length; i++) {
      final stop = itinerary[i] as Map<String, dynamic>;
      buffer.writeln('${i + 1}. ${stop['name']}');
      if (stop['address'] != null) buffer.writeln('   ${stop['address']}');
      if (stop['estimated_time'] != null) buffer.writeln('   ${stop['estimated_time']}');
      buffer.writeln();
    }

    buffer.writeln('event_history.report_passengers'.tr());
    buffer.writeln('-' * 40);
    buffer.writeln('${'event_history.max_capacity'.tr()}: ${event['max_passengers'] ?? 'N/A'}');
    buffer.writeln();

    buffer.writeln('=' * 60);
    buffer.writeln('${'event_history.report_generated'.tr()}: ${dateFormat.format(DateTime.now())}');
    buffer.writeln('event_history.report_confidential'.tr());
    buffer.writeln('=' * 60);

    return buffer.toString();
  }

  void _showCfdiInfo() {
    HapticService.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('event_history.cfdi_coming_soon'.tr()),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(
          'event_history.title'.tr(),
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            onPressed: _loadEvents,
            icon: Icon(Icons.refresh, color: AppColors.primary),
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? _buildErrorState()
              : _buildContent(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: AppColors.error),
          SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: AppColors.textSecondary)),
          SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadEvents,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text('event_history.retry'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        _buildFilters(),
        Expanded(
          child: _filteredEvents.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: EdgeInsets.all(16),
                  itemCount: _filteredEvents.length + 1, // +1 for summary
                  itemBuilder: (context, index) {
                    if (index < _filteredEvents.length) {
                      return _buildEventCard(_filteredEvents[index], index);
                    }
                    // Last item = fiscal summary
                    return _buildFiscalSummary();
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip('event_history.filter_all'.tr(), 'all'),
            SizedBox(width: 8),
            _buildFilterChip('event_history.filter_completed'.tr(), 'completed'),
            SizedBox(width: 8),
            _buildFilterChip('event_history.filter_in_progress'.tr(), 'in_progress'),
            SizedBox(width: 8),
            _buildFilterChip('event_history.filter_cancelled'.tr(), 'cancelled'),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filterStatus == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _filterStatus = value;
          _filteredEvents = _applyFilter(_allEvents);
        });
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
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
          Icon(Icons.event_busy, size: 64, color: AppColors.textTertiary),
          SizedBox(height: 16),
          Text(
            _filterStatus == 'all'
                ? 'event_history.no_events'.tr()
                : 'event_history.no_filter_results'.tr(),
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventCard(Map<String, dynamic> event, int index) {
    final itinerary = event['itinerary'] as List<dynamic>? ?? [];
    final fin = _calcFinancials(event);
    final currency = event['currency'] as String? ?? 'MXN';
    final isMX = (event['country_code'] as String?) == 'MX';
    final commissionPct = ((fin['commissionRate']! * 100)).toStringAsFixed(0);

    final status = event['status'] as String?;
    final isCompleted = status == 'completed';

    return Card(
      margin: EdgeInsets.only(bottom: 16),
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isCompleted
              ? AppColors.success.withOpacity(0.3)
              : AppColors.border,
        ),
      ),
      child: InkWell(
        onTap: () => _showEventDetails(event),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: name + date + status
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event['event_name'] ?? 'event_history.unnamed_event'.tr(),
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '${event['event_date']} - ${event['start_time']}',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusBadge(status),
                ],
              ),

              Divider(height: 24, color: AppColors.border),

              // Vehicle info
              if (event['vehicle_id'] != null) ...[
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.primary.withOpacity(0.2),
                      child: Icon(Icons.directions_bus, color: AppColors.primary),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'event_history.vehicle_assigned'.tr(),
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
              ],

              // Stats row
              Row(
                children: [
                  _buildStat(
                    Icons.people,
                    '${event['max_passengers'] ?? '?'}',
                    'event_history.capacity'.tr(),
                  ),
                  SizedBox(width: 24),
                  _buildStat(
                    Icons.route,
                    '${fin['distance']!.toStringAsFixed(1)} km',
                    'event_history.distance'.tr(),
                  ),
                  SizedBox(width: 24),
                  _buildStat(
                    Icons.flag,
                    '${itinerary.length}',
                    'event_history.stops'.tr(),
                  ),
                ],
              ),

              SizedBox(height: 12),

              // Actions row (download + CFDI)
              Row(
                children: [
                  if (isMX)
                    TextButton.icon(
                      onPressed: _showCfdiInfo,
                      icon: Icon(Icons.receipt_long, size: 16),
                      label: Text('event_history.request_cfdi'.tr(), style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        padding: EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  Spacer(),
                  TextButton.icon(
                    onPressed: () => _downloadEventReport(event),
                    icon: Icon(Icons.download, size: 16),
                    label: Text('event_history.download_report'.tr(), style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ],
              ),

              // Financial breakdown - AT THE BOTTOM
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _buildFinancialRow(
                      'event_history.driver_payment'.tr(),
                      _formatCurrency(fin['driverPayment']!, currency),
                      color: AppColors.textPrimary,
                    ),
                    SizedBox(height: 4),
                    _buildFinancialRow(
                      'event_history.toro_commission'.tr(namedArgs: {'rate': commissionPct}),
                      _formatCurrency(fin['commission']!, currency),
                      color: AppColors.primary,
                    ),
                    if (isMX) ...[
                      SizedBox(height: 4),
                      _buildFinancialRow(
                        'event_history.iva_tax'.tr(),
                        _formatCurrency(fin['iva']!, currency),
                        color: AppColors.textSecondary,
                      ),
                    ],
                    Divider(height: 16, color: AppColors.border),
                    _buildFinancialRow(
                      'event_history.total'.tr(),
                      _formatCurrency(fin['total']!, currency),
                      color: AppColors.primary,
                      isBold: true,
                      fontSize: 16,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFinancialRow(String label, String value, {
    Color? color,
    bool isBold = false,
    double fontSize = 14,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isBold ? AppColors.textPrimary : AppColors.textSecondary,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: fontSize - 1,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color ?? AppColors.textPrimary,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: fontSize,
          ),
        ),
      ],
    );
  }

  // Running totals summary card at the bottom
  Widget _buildFiscalSummary() {
    double totalSpent = 0;
    double totalIva = 0;
    double totalDistance = 0;
    int eventCount = 0;
    String currency = 'MXN';

    for (final event in _filteredEvents) {
      final fin = _calcFinancials(event);
      totalSpent += fin['total']!;
      totalIva += fin['iva']!;
      totalDistance += fin['distance']!;
      eventCount++;
      currency = event['currency'] as String? ?? currency;
    }

    return Container(
      margin: EdgeInsets.only(bottom: 32, top: 8),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance, color: AppColors.primary, size: 20),
              SizedBox(width: 8),
              Text(
                'event_history.summary_title'.tr(),
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                  'event_history.summary_events'.tr(),
                  '$eventCount',
                  Icons.event,
                ),
              ),
              Expanded(
                child: _buildSummaryItem(
                  'event_history.summary_total_distance'.tr(),
                  '${totalDistance.toStringAsFixed(1)} km',
                  Icons.route,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Divider(color: AppColors.border),
          SizedBox(height: 12),
          _buildFinancialRow(
            'event_history.summary_total_spent'.tr(),
            _formatCurrency(totalSpent, currency),
            color: AppColors.primary,
            isBold: true,
            fontSize: 16,
          ),
          if (totalIva > 0) ...[
            SizedBox(height: 4),
            _buildFinancialRow(
              'event_history.summary_total_iva'.tr(),
              _formatCurrency(totalIva, currency),
              color: AppColors.textSecondary,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primary, size: 24),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String? status) {
    Color color;
    String label;

    switch (status) {
      case 'completed':
        color = AppColors.success;
        label = 'event_history.status_completed'.tr();
        break;
      case 'in_progress':
        color = AppColors.primary;
        label = 'event_history.status_in_progress'.tr();
        break;
      case 'cancelled':
        color = AppColors.error;
        label = 'event_history.status_cancelled'.tr();
        break;
      default:
        color = AppColors.textTertiary;
        label = 'event_history.status_pending'.tr();
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildStat(IconData icon, String value, String label) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 18),
        SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showEventDetails(Map<String, dynamic> event) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _EventDetailsScreen(event: event),
      ),
    );
  }
}

/// Pantalla de detalles del evento
class _EventDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> event;

  const _EventDetailsScreen({required this.event});

  @override
  Widget build(BuildContext context) {
    final vehicle = event['vehicle'] as Map<String, dynamic>?;
    final itinerary = event['itinerary'] as List<dynamic>? ?? [];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(
          event['event_name'] ?? 'event_history.unnamed_event'.tr(),
          style: TextStyle(color: AppColors.textPrimary),
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSection('event_history.general_info'.tr(), [
              _buildInfoRow('event_history.date'.tr(), event['event_date'] ?? 'N/A'),
              _buildInfoRow('event_history.time'.tr(), event['start_time'] ?? 'N/A'),
              _buildInfoRow('event_history.status'.tr(), event['status'] ?? 'N/A'),
              _buildInfoRow('event_history.distance'.tr(), '${event['total_distance_km'] ?? 0} km'),
            ]),

            if (vehicle != null)
              _buildSection('event_history.vehicle_info'.tr(), [
                _buildInfoRow('event_history.vehicle'.tr(), vehicle['vehicle_name'] ?? 'N/A'),
                _buildInfoRow('event_history.brand_model'.tr(), '${vehicle['make'] ?? ''} ${vehicle['model'] ?? ''} ${vehicle['year'] ?? ''}'),
                _buildInfoRow('event_history.seats'.tr(), '${vehicle['total_seats'] ?? 'N/A'}'),
              ]),

            _buildSection('event_history.itinerary'.tr(),
              itinerary.map((stop) {
                final s = stop as Map<String, dynamic>;
                return _buildInfoRow('•', '${s['name']}${s['estimated_time'] != null ? ' - ${s['estimated_time']}' : ''}');
              }).toList(),
            ),

            _buildSection('event_history.passengers'.tr(), [
              _buildInfoRow('event_history.max_capacity'.tr(), '${event['max_passengers'] ?? 'N/A'}'),
              _buildInfoRow('', 'event_history.passengers_note'.tr()),
            ]),

            _buildSection('event_history.gps_tracking'.tr(), [
              _buildInfoRow('', 'event_history.available_admin'.tr()),
            ]),

            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 8),
        ...children,
        SizedBox(height: 20),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty) ...[
            Text(
              '$label ',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
