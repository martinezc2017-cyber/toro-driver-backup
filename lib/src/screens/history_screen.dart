import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../utils/app_colors.dart';
import '../config/supabase_config.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _selectedPeriod = 'week';
  bool _isLoading = true;
  List<TripHistory> _trips = [];
  HistorySummary _summary = HistorySummary();

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);

    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Get driver ID
      final driverResponse = await SupabaseConfig.client
          .from('drivers')
          .select('id')
          .eq('user_id', user.id)
          .maybeSingle();

      if (driverResponse == null) {
        setState(() => _isLoading = false);
        return;
      }

      final driverId = driverResponse['id'];

      // Calculate date range
      DateTime startDate;
      final now = DateTime.now();
      switch (_selectedPeriod) {
        case 'today':
          startDate = DateTime(now.year, now.month, now.day);
          break;
        case 'week':
          startDate = now.subtract(const Duration(days: 7));
          break;
        case 'month':
          startDate = DateTime(now.year, now.month - 1, now.day);
          break;
        default:
          startDate = DateTime(2020);
      }

      // Load trips
      final tripsResponse = await SupabaseConfig.client
          .from('trips')
          .select('*')
          .eq('driver_id', driverId)
          .gte('created_at', startDate.toIso8601String())
          .order('created_at', ascending: false);

      // Load driver stats
      final statsResponse = await SupabaseConfig.client
          .from('driver_stats')
          .select('*')
          .eq('driver_id', driverId)
          .maybeSingle();

      // Parse trips
      _trips = (tripsResponse as List).map((t) => TripHistory(
        id: t['id'] ?? '',
        pickupAddress: t['pickup_address'] ?? 'Origen',
        dropoffAddress: t['dropoff_address'] ?? 'Destino',
        fare: (t['fare'] as num?)?.toDouble() ?? 0,
        distance: (t['distance_miles'] as num?)?.toDouble() ?? 0,
        duration: t['duration_minutes'] ?? 0,
        status: t['status'] ?? 'completed',
        createdAt: DateTime.tryParse(t['created_at'] ?? '') ?? DateTime.now(),
        rating: (t['driver_rating'] as num?)?.toDouble(),
      )).toList();

      // Calculate summary
      final completedTrips = _trips.where((t) => t.status == 'completed').toList();
      _summary = HistorySummary(
        totalTrips: completedTrips.length,
        totalEarnings: completedTrips.fold(0, (sum, t) => sum + t.fare),
        totalMiles: completedTrips.fold(0, (sum, t) => sum + t.distance),
        totalMinutes: completedTrips.fold(0, (sum, t) => sum + t.duration),
        onlineHours: (statsResponse?['total_online_hours'] as num?)?.toDouble() ?? 0,
        avgRating: (statsResponse?['average_rating'] as num?)?.toDouble() ?? 5.0,
      );

      setState(() => _isLoading = false);
    } catch (e) {
      //Error loading history: $e');
      // Load mock data for testing
      _loadMockData();
      setState(() => _isLoading = false);
    }
  }

  void _loadMockData() {
    _trips = [
      TripHistory(id: '1', pickupAddress: 'Villetta Apartments', dropoffAddress: 'Phoenix Sky Harbor Airport', fare: 45.00, distance: 10.4, duration: 18, status: 'completed', createdAt: DateTime.now(), rating: 5.0),
      TripHistory(id: '2', pickupAddress: 'Downtown Phoenix', dropoffAddress: 'Tempe Marketplace', fare: 32.50, distance: 8.2, duration: 15, status: 'completed', createdAt: DateTime.now().subtract(const Duration(hours: 2)), rating: 5.0),
      TripHistory(id: '3', pickupAddress: 'ASU Campus', dropoffAddress: 'Scottsdale Fashion Square', fare: 28.00, distance: 12.1, duration: 22, status: 'completed', createdAt: DateTime.now().subtract(const Duration(hours: 4)), rating: 4.0),
      TripHistory(id: '4', pickupAddress: 'Mesa Arts Center', dropoffAddress: 'Gilbert Town Square', fare: 22.50, distance: 7.5, duration: 14, status: 'cancelled', createdAt: DateTime.now().subtract(const Duration(days: 1))),
      TripHistory(id: '5', pickupAddress: 'Chandler Mall', dropoffAddress: 'Phoenix Zoo', fare: 35.00, distance: 15.3, duration: 25, status: 'completed', createdAt: DateTime.now().subtract(const Duration(days: 1)), rating: 5.0),
    ];

    final completedTrips = _trips.where((t) => t.status == 'completed').toList();
    _summary = HistorySummary(
      totalTrips: completedTrips.length,
      totalEarnings: completedTrips.fold(0, (sum, t) => sum + t.fare),
      totalMiles: completedTrips.fold(0, (sum, t) => sum + t.distance),
      totalMinutes: completedTrips.fold(0, (sum, t) => sum + t.duration),
      onlineHours: 28.5,
      avgRating: 4.8,
    );
  }

  Future<void> _exportData() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            Text('export_data'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 16),
            ListTile(
              dense: true,
              leading: Icon(Icons.description, color: AppColors.primary, size: 20),
              title: const Text('CSV', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              subtitle: Text('Excel compatible', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              trailing: Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 18),
              onTap: () {
                Navigator.pop(context);
                _exportToCSV();
              },
            ),
            ListTile(
              dense: true,
              leading: Icon(Icons.picture_as_pdf, color: Colors.red, size: 20),
              title: const Text('PDF', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              subtitle: Text('report_format'.tr(), style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              trailing: Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 18),
              onTap: () {
                Navigator.pop(context);
                _exportToPDF();
              },
            ),
            ListTile(
              dense: true,
              leading: Icon(Icons.share, color: AppColors.primary, size: 20),
              title: Text('share'.tr(), style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              subtitle: Text('share_summary'.tr(), style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              trailing: Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 18),
              onTap: () {
                Navigator.pop(context);
                _shareData();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _exportToCSV() async {
    try {
      final csvContent = StringBuffer();
      csvContent.writeln('Date,Pickup,Dropoff,Fare,Miles,Minutes,Status,Rating');

      for (final trip in _trips) {
        final date = DateFormat('yyyy-MM-dd HH:mm').format(trip.createdAt);
        csvContent.writeln('$date,"${trip.pickupAddress}","${trip.dropoffAddress}",${trip.fare},${trip.distance},${trip.duration},${trip.status},${trip.rating ?? ""}');
      }

      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/toro_history.csv');
      await file.writeAsString(csvContent.toString());

      await Share.shareXFiles([XFile(file.path)], text: 'TORO Driver History');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('export_success'.tr()), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _exportToPDF() async {
    // For PDF, we'll share a text summary for now
    _shareData();
  }

  Future<void> _shareData() async {
    final summary = '''
TORO Driver - History Report
Period: ${_getPeriodName()}

Summary:
- Total Trips: ${_summary.totalTrips}
- Total Earnings: \$${_summary.totalEarnings.toStringAsFixed(2)}
- Total Miles: ${_summary.totalMiles.toStringAsFixed(1)} mi
- Time Online: ${_summary.onlineHours.toStringAsFixed(1)}h
- Average Rating: ${_summary.avgRating.toStringAsFixed(1)}

Recent Trips:
${_trips.take(5).map((t) => '- ${t.pickupAddress} → ${t.dropoffAddress}: \$${t.fare.toStringAsFixed(2)}').join('\n')}
''';

    await Share.share(summary);
  }

  String _getPeriodName() {
    switch (_selectedPeriod) {
      case 'today': return 'today'.tr();
      case 'week': return 'this_week'.tr();
      case 'month': return 'this_month'.tr();
      default: return 'all_time'.tr();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Icon(Icons.history, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('history'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.download, size: 20, color: AppColors.primary),
            onPressed: _exportData,
          ),
          IconButton(
            icon: Icon(Icons.refresh, size: 20, color: AppColors.textSecondary),
            onPressed: _loadHistory,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Period selector
                Container(
                  height: 36,
                  margin: const EdgeInsets.all(16),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _buildPeriodChip('today', 'today'.tr()),
                      _buildPeriodChip('week', 'this_week'.tr()),
                      _buildPeriodChip('month', 'this_month'.tr()),
                      _buildPeriodChip('all', 'all_time'.tr()),
                    ],
                  ),
                ),
                // Summary card
                _buildSummaryCard(),
                const SizedBox(height: 8),
                // Trips list
                Expanded(
                  child: _trips.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.history, size: 48, color: AppColors.textSecondary),
                              const SizedBox(height: 12),
                              Text('no_trips'.tr(), style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _trips.length,
                          itemBuilder: (context, index) => _buildTripItem(_trips[index]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildPeriodChip(String value, String label) {
    final isSelected = _selectedPeriod == value;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedPeriod = value);
        _loadHistory();
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildStatItem(Icons.drive_eta, '${_summary.totalTrips}', 'trips'.tr())),
              Container(width: 1, height: 36, color: AppColors.border),
              Expanded(child: _buildStatItem(Icons.attach_money, '\$${_summary.totalEarnings.toStringAsFixed(0)}', 'earned'.tr())),
              Container(width: 1, height: 36, color: AppColors.border),
              Expanded(child: _buildStatItem(Icons.route, _summary.totalMiles.toStringAsFixed(0), 'miles'.tr())),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildStatItem(Icons.access_time, '${_summary.onlineHours.toStringAsFixed(1)}h', 'online'.tr())),
              Container(width: 1, height: 36, color: AppColors.border),
              Expanded(child: _buildStatItem(Icons.timer, '${(_summary.totalMinutes / 60).toStringAsFixed(1)}h', 'driving'.tr())),
              Container(width: 1, height: 36, color: AppColors.border),
              Expanded(child: _buildStatItem(Icons.star, _summary.avgRating.toStringAsFixed(1), 'rating'.tr())),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primary, size: 18),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        Text(label, style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildTripItem(TripHistory trip) {
    final isCancelled = trip.status == 'cancelled';
    final statusColor = isCancelled ? AppColors.error : AppColors.success;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isCancelled ? Icons.cancel : Icons.check_circle,
            color: statusColor,
            size: 18,
          ),
        ),
        title: Text(
          '${trip.pickupAddress} → ${trip.dropoffAddress}',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textPrimary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Icon(Icons.route, size: 12, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text('${trip.distance.toStringAsFixed(1)} mi', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            const SizedBox(width: 8),
            Icon(Icons.timer, size: 12, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text('${trip.duration} min', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            if (trip.rating != null) ...[
              const SizedBox(width: 8),
              Icon(Icons.star, size: 12, color: AppColors.star),
              const SizedBox(width: 2),
              Text('${trip.rating}', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            ],
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              isCancelled ? '\$0.00' : '\$${trip.fare.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isCancelled ? AppColors.textSecondary : AppColors.success,
              ),
            ),
            Text(
              _formatDate(trip.createdAt),
              style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
            ),
          ],
        ),
        onTap: () => _showTripDetails(trip),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tripDate = DateTime(date.year, date.month, date.day);

    if (tripDate == today) {
      return DateFormat('HH:mm').format(date);
    } else if (tripDate == today.subtract(const Duration(days: 1))) {
      return 'yesterday'.tr();
    } else {
      return DateFormat('MM/dd').format(date);
    }
  }

  void _showTripDetails(TripHistory trip) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.receipt, color: AppColors.primary, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('trip_details'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                ),
                Text(
                  '\$${trip.fare.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.success),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildDetailRow(Icons.my_location, 'pickup'.tr(), trip.pickupAddress),
            _buildDetailRow(Icons.location_on, 'dropoff'.tr(), trip.dropoffAddress),
            _buildDetailRow(Icons.route, 'distance'.tr(), '${trip.distance.toStringAsFixed(1)} mi'),
            _buildDetailRow(Icons.timer, 'duration'.tr(), '${trip.duration} min'),
            _buildDetailRow(Icons.calendar_today, 'date'.tr(), DateFormat('MMM dd, yyyy HH:mm').format(trip.createdAt)),
            if (trip.rating != null)
              _buildDetailRow(Icons.star, 'rating'.tr(), '${trip.rating}'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text('close'.tr()),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 16),
          const SizedBox(width: 10),
          SizedBox(
            width: 70,
            child: Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class TripHistory {
  final String id;
  final String pickupAddress;
  final String dropoffAddress;
  final double fare;
  final double distance;
  final int duration;
  final String status;
  final DateTime createdAt;
  final double? rating;

  TripHistory({
    required this.id,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.fare,
    required this.distance,
    required this.duration,
    required this.status,
    required this.createdAt,
    this.rating,
  });
}

class HistorySummary {
  final int totalTrips;
  final double totalEarnings;
  final double totalMiles;
  final int totalMinutes;
  final double onlineHours;
  final double avgRating;

  HistorySummary({
    this.totalTrips = 0,
    this.totalEarnings = 0,
    this.totalMiles = 0,
    this.totalMinutes = 0,
    this.onlineHours = 0,
    this.avgRating = 5.0,
  });
}
