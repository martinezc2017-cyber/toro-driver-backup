import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../utils/app_colors.dart';
import '../providers/driver_provider.dart';
import '../services/ticket_service.dart';

class CreateTicketScreen extends StatefulWidget {
  final String category;
  final String subject;
  final String initialDescription;
  final bool requiresTripSelection;

  const CreateTicketScreen({
    super.key,
    required this.category,
    required this.subject,
    required this.initialDescription,
    this.requiresTripSelection = false,
  });

  @override
  State<CreateTicketScreen> createState() => _CreateTicketScreenState();
}

class _CreateTicketScreenState extends State<CreateTicketScreen> {
  final TextEditingController _commentsController = TextEditingController();
  final TextEditingController _manualTripIdController = TextEditingController();
  final TicketService _ticketService = TicketService();
  bool _isSubmitting = false;
  String _selectedPriority = 'medium';

  // Trip selection
  List<Map<String, dynamic>> _recentTrips = [];
  String? _selectedTripId;
  bool _isManualEntry = false;
  bool _isLoadingTrips = false;

  final Map<String, String> _priorityLabels = {
    'low': 'Baja',
    'medium': 'Media',
    'high': 'Alta',
    'urgent': 'Urgente',
  };

  final Map<String, Color> _priorityColors = {
    'low': Colors.green,
    'medium': Colors.orange,
    'high': Colors.deepOrange,
    'urgent': Colors.red,
  };

  @override
  void initState() {
    super.initState();
    if (widget.requiresTripSelection) {
      _loadRecentTrips();
    }
  }

  @override
  void dispose() {
    _commentsController.dispose();
    _manualTripIdController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentTrips() async {
    setState(() => _isLoadingTrips = true);
    try {
      final driverProvider = Provider.of<DriverProvider>(context, listen: false);
      final driver = driverProvider.driver;
      if (driver != null) {
        final trips = await _ticketService.getRecentTrips(driver.id);
        setState(() {
          _recentTrips = trips;
          _isLoadingTrips = false;
        });
      }
    } catch (e) {
      setState(() => _isLoadingTrips = false);
    }
  }

  Future<void> _submitTicket() async {
    if (_commentsController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('add_comments_message'.tr()),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Validate trip selection if required
    if (widget.requiresTripSelection) {
      if (_selectedTripId == null && !_isManualEntry) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('select_trip_message'.tr()),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      if (_isManualEntry && _manualTripIdController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('enter_trip_id_message'.tr()),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
    }

    setState(() => _isSubmitting = true);

    try {
      final driverProvider = Provider.of<DriverProvider>(context, listen: false);
      final driver = driverProvider.driver;

      if (driver == null) {
        throw Exception('No driver data found');
      }

      // Build description with trip info if applicable
      String fullDescription = widget.initialDescription;

      if (widget.requiresTripSelection) {
        final tripId = _isManualEntry ? _manualTripIdController.text.trim() : _selectedTripId;
        fullDescription += '\n\n🚗 Trip ID: $tripId';
      }

      fullDescription += '\n\nComentarios adicionales:\n${_commentsController.text.trim()}';

      final ticket = await _ticketService.createTicket(
        subject: widget.subject,
        description: fullDescription,
        category: widget.category,
        priority: _selectedPriority,
        userId: driver.id,
        userName: driver.fullName,
        userEmail: driver.email,
        userPhone: driver.phone,
      );

      if (!mounted) return;

      if (ticket != null) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ticket_created_success'.tr()),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        throw Exception('Failed to create ticket');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ticket_creation_error'.tr()),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
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
        leading: IconButton(
          icon: const Icon(Icons.close, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'create_ticket'.tr(),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Subject Card
            _buildInfoCard(
              icon: Icons.info_outline,
              title: 'subject'.tr(),
              content: widget.subject,
              color: AppColors.primary,
            ),
            const SizedBox(height: 16),

            // Priority Selector
            _buildPrioritySelector(),
            const SizedBox(height: 16),

            // Trip Selector (for Payment and Passenger Issues)
            if (widget.requiresTripSelection) ...[
              _buildTripSelector(),
              const SizedBox(height: 16),
            ],

            // Comments Section
            _buildCommentsSection(),
            const SizedBox(height: 24),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitTicket,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: AppColors.primary.withValues(alpha:0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'submit_ticket'.tr(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String content,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha:0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrioritySelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha:0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_outlined, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'priority'.tr(),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _priorityLabels.entries.map((entry) {
              final isSelected = _selectedPriority == entry.key;
              final color = _priorityColors[entry.key]!;
              return GestureDetector(
                onTap: () => setState(() => _selectedPriority = entry.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withValues(alpha:0.2)
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? color
                          : AppColors.border.withValues(alpha:0.3),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (entry.key == 'urgent')
                        Icon(Icons.priority_high, color: color, size: 16),
                      if (entry.key == 'urgent') const SizedBox(width: 4),
                      Text(
                        entry.value,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? color : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha:0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.comment_outlined, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'additional_comments'.tr(),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                '*',
                style: TextStyle(color: Colors.red, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _commentsController,
            maxLines: 6,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'comments_hint'.tr(),
              hintStyle: TextStyle(
                color: AppColors.textSecondary.withValues(alpha:0.5),
                fontSize: 13,
              ),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTripSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha:0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_taxi, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'select_trip'.tr(),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                '*',
                style: TextStyle(color: Colors.red, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isLoadingTrips)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (_recentTrips.isEmpty && !_isManualEntry)
            Column(
              children: [
                Text(
                  'no_recent_trips'.tr(),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 12),
                _buildManualEntryButton(),
              ],
            )
          else if (!_isManualEntry) ...[
            // Recent trips list
            ..._recentTrips.map((trip) {
              final isSelected = _selectedTripId == trip['id'];
              final tripDate = DateTime.tryParse(trip['created_at'] ?? '');
              final formattedDate = tripDate != null
                  ? '${tripDate.day}/${tripDate.month}/${tripDate.year}'
                  : '';

              return GestureDetector(
                onTap: () => setState(() => _selectedTripId = trip['id']),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha:0.1)
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.border.withValues(alpha:0.3),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.check_circle : Icons.circle_outlined,
                        color: isSelected ? AppColors.primary : AppColors.textSecondary,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              trip['pickup_address'] ?? 'N/A',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isSelected ? AppColors.primary : AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              formattedDate,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '\$${trip['final_price']?.toStringAsFixed(2) ?? '0.00'}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? AppColors.primary : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            _buildManualEntryButton(),
          ] else ...[
            // Manual entry
            TextField(
              controller: _manualTripIdController,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'enter_trip_id_hint'.tr(),
                hintStyle: TextStyle(
                  color: AppColors.textSecondary.withValues(alpha:0.5),
                  fontSize: 13,
                ),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() {
                _isManualEntry = false;
                _manualTripIdController.clear();
              }),
              child: Text(
                'select_from_list'.tr(),
                style: const TextStyle(color: AppColors.primary, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildManualEntryButton() {
    return TextButton.icon(
      onPressed: () => setState(() => _isManualEntry = true),
      icon: const Icon(Icons.edit, size: 16, color: AppColors.primary),
      label: Text(
        'other_trip'.tr(),
        style: const TextStyle(color: AppColors.primary, fontSize: 12),
      ),
    );
  }
}
