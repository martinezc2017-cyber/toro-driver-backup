import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../services/organizer_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';

/// Vehicles tab for the organizer home screen.
///
/// Displays a list of available bus vehicles from [OrganizerService.browseVehicles].
/// Includes a filter text field for state and a detail bottom sheet with a
/// "Contactar" button that triggers [OrganizerService.contactBusOwner].
class OrganizerVehiclesTab extends StatefulWidget {
  const OrganizerVehiclesTab({super.key});

  @override
  State<OrganizerVehiclesTab> createState() => _OrganizerVehiclesTabState();
}

class _OrganizerVehiclesTabState extends State<OrganizerVehiclesTab> {
  final OrganizerService _organizerService = OrganizerService();
  final TextEditingController _stateFilterController = TextEditingController();

  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _vehicles = [];
  String? _currentStateFilter;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
  }

  @override
  void dispose() {
    _stateFilterController.dispose();
    super.dispose();
  }

  Future<void> _loadVehicles() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final vehicles = await _organizerService.browseVehicles(
        state: _currentStateFilter,
      );

      if (mounted) {
        setState(() {
          _vehicles = vehicles;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = '${'organizer.vehicles_load_error'.tr()}: $e';
        });
      }
    }
  }

  void _applyFilter() {
    HapticService.lightImpact();
    final text = _stateFilterController.text.trim();
    _currentStateFilter = text.isEmpty ? null : text;
    _loadVehicles();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(
          'organizer.vehicles_title'.tr(),
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        centerTitle: false,
      ),
      body: Column(
        children: [
          // Filter bar
          _buildFilterBar(),
          // Invite banner
          _buildInviteBanner(),
          // Content
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : _error != null
                    ? _buildErrorState()
                    : _vehicles.isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                            color: AppColors.primary,
                            backgroundColor: AppColors.surface,
                            onRefresh: _loadVehicles,
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(16),
                              itemCount: _vehicles.length,
                              itemBuilder: (context, index) =>
                                  _buildVehicleCard(_vehicles[index]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildInviteBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: _GlowingInviteButton(
        onTap: _shareDriverAppLink,
      ),
    );
  }

  void _shareDriverAppLink() {
    HapticService.mediumImpact();

    const driverAppLink = 'https://play.google.com/store/apps/details?id=com.toro.driver';
    final message = 'organizer.invite_message'.tr(namedArgs: {'link': driverAppLink});

    Share.share(message, subject: 'organizer.invite_driver'.tr());
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border, width: 0.5),
              ),
              child: TextField(
                controller: _stateFilterController,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'organizer.filter_state_hint'.tr(),
                  hintStyle:
                      TextStyle(color: AppColors.textTertiary, fontSize: 13),
                  prefixIcon: Icon(Icons.filter_list,
                      size: 18, color: AppColors.textTertiary),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
                onSubmitted: (_) => _applyFilter(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _applyFilter,
            child: Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.search, size: 18, color: Colors.white),
            ),
          ),
        ],
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
              _error ?? 'common.unknown_error'.tr(),
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadVehicles,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text('common.retry'.tr()),
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
            Icon(Icons.directions_bus_outlined,
                size: 48,
                color: AppColors.textTertiary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              'organizer.no_vehicles_found'.tr(),
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              'organizer.try_change_filter'.tr(),
              style:
                  TextStyle(color: AppColors.textTertiary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleCard(Map<String, dynamic> vehicle) {
    final vehicleName = vehicle['vehicle_name'] ?? 'common.no_name'.tr();
    final vehicleType = vehicle['vehicle_type'] ?? 'autobus';
    // CHOFER DE TORO (driver assigned to operate the bus)
    final driverName = vehicle['driver_name'] ?? 'common.no_driver'.tr();
    final driverPhone = vehicle['driver_phone'] ?? '';
    // OWNER (dueño del camión/compañía)
    final ownerName = vehicle['owner_name'] ?? 'common.owner'.tr();
    final ownerPhone = vehicle['owner_phone'] ?? '';
    final totalSeats = vehicle['total_seats'] ?? 0;
    final vehicleId = vehicle['id']?.toString() ?? '';

    // Get first photo from image_urls array
    final imageUrls = vehicle['image_urls'] as List<dynamic>?;
    final firstPhoto = (imageUrls != null && imageUrls.isNotEmpty)
        ? imageUrls[0].toString()
        : null;

    final typeIcon =
        vehicleType == 'minibus' ? Icons.airport_shuttle : Icons.directions_bus;
    final typeLabel =
        vehicleType == 'minibus' ? 'organizer.vehicle_type_minibus'.tr() : 'organizer.vehicle_type_bus'.tr();

    return GestureDetector(
      onTap: () {
        HapticService.lightImpact();
        _showVehicleDetail(vehicle);
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
        child: Row(
          children: [
            // Vehicle photo (bigger)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: firstPhoto != null
                  ? Image.network(
                      firstPhoto,
                      width: 90,
                      height: 90,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(typeIcon, size: 36, color: AppColors.primary),
                        );
                      },
                    )
                  : Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(typeIcon, size: 36, color: AppColors.primary),
                    ),
            ),
            const SizedBox(width: 14),
            // Vehicle info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vehicleName,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  // Seats + Driver info - bigger and more prominent
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Seats row
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.event_seat,
                                size: 18, color: AppColors.success),
                            const SizedBox(width: 6),
                            Text(
                              '$totalSeats',
                              style: const TextStyle(
                                color: AppColors.success,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'organizer.seats'.tr(),
                              style: TextStyle(
                                color: AppColors.success.withValues(alpha: 0.8),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Driver info row (CHOFER DE TORO)
                        Row(
                          children: [
                            const Icon(Icons.person_outline,
                                size: 14, color: AppColors.success),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                driverName,
                                style: TextStyle(
                                  color: AppColors.success.withValues(alpha: 0.9),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppColors.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }

  void _showVehicleDetail(Map<String, dynamic> vehicle) {
    final vehicleName = vehicle['vehicle_name'] ?? 'Sin nombre';
    final vehicleType = vehicle['vehicle_type'] ?? 'autobus';
    // CHOFER DE TORO (driver assigned to operate the bus)
    final driverName = vehicle['driver_name'] ?? 'Sin chofer';
    final driverPhone = vehicle['driver_phone'] ?? '';
    // OWNER (dueño del camión/compañía)
    final ownerName = vehicle['owner_name'] ?? 'Propietario';
    final ownerPhone = vehicle['owner_phone'] ?? '';
    final totalSeats = vehicle['total_seats'] ?? 0;
    final ownerId = vehicle['owner_id']?.toString() ?? '';
    final vehicleId = vehicle['id']?.toString() ?? '';
    final state = vehicle['state'] ?? '';

    // Get first photo from image_urls array
    final imageUrls = vehicle['image_urls'] as List<dynamic>?;
    final firstPhoto = (imageUrls != null && imageUrls.isNotEmpty)
        ? imageUrls[0].toString()
        : null;

    final typeIcon =
        vehicleType == 'minibus' ? Icons.airport_shuttle : Icons.directions_bus;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
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
              // Vehicle photo
              if (firstPhoto != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    firstPhoto,
                    width: double.infinity,
                    height: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: double.infinity,
                        height: 200,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(typeIcon, size: 60, color: AppColors.primary),
                      );
                    },
                  ),
                ),
              if (firstPhoto != null) const SizedBox(height: 16),
              // Vehicle name
              Text(
                vehicleName,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              // Seats - prominent display
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.success.withValues(alpha: 0.3), width: 2),
                ),
                child: Column(
                  children: [
                    // Seats section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.event_seat, size: 32, color: AppColors.success),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$totalSeats',
                              style: const TextStyle(
                                color: AppColors.success,
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'organizer.seats_available'.tr(),
                              style: TextStyle(
                                color: AppColors.success.withValues(alpha: 0.8),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    // Divider
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Container(
                        height: 1,
                        color: AppColors.success.withValues(alpha: 0.2),
                      ),
                    ),
                    // Driver section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_outline,
                            size: 20,
                            color: AppColors.success),
                        const SizedBox(width: 8),
                        Text(
                          driverName,
                          style: TextStyle(
                            color: AppColors.success,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Details
              _detailRow(Icons.category, 'common.type'.tr(),
                  vehicleType == 'minibus' ? 'Minibus' : 'Autobus'),
              // CHOFER DE TORO (principal)
              _detailRow(Icons.drive_eta, 'organizer.toro_driver'.tr(), driverName),
              if (driverPhone.isNotEmpty)
                _detailRow(Icons.phone, 'organizer.driver_phone'.tr(), driverPhone),
              const SizedBox(height: 8),
              // OWNER (dueño del camión)
              _detailRow(Icons.business, 'common.owner'.tr(), ownerName),
              if (ownerPhone.isNotEmpty)
                _detailRow(Icons.phone_outlined, 'organizer.owner_phone'.tr(), ownerPhone),
              if (state.isNotEmpty)
                _detailRow(Icons.location_on, 'common.state'.tr(), state),
              const SizedBox(height: 24),
              // Contactar button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    HapticService.mediumImpact();
                    if (ownerId.isEmpty) {
                      Navigator.pop(ctx);
                      return;
                    }
                    try {
                      await _organizerService.contactBusOwner(
                        ownerId,
                        '', // organizerId -- filled by backend
                        'organizer.contact_message'.tr(namedArgs: {'vehicleName': vehicleName}),
                      );
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text('organizer.message_sent'.tr()),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      }
                    } catch (e) {
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text('${'organizer.contact_error'.tr()}: $e'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.message, size: 18),
                  label: Text(
                    'organizer.contact_owner'.tr(),
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
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
      },
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textTertiary),
          const SizedBox(width: 10),
          Text(
            '$label: ',
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 13,
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
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated glowing invite button
class _GlowingInviteButton extends StatefulWidget {
  final VoidCallback onTap;

  const _GlowingInviteButton({required this.onTap});

  @override
  State<_GlowingInviteButton> createState() => _GlowingInviteButtonState();
}

class _GlowingInviteButtonState extends State<_GlowingInviteButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.success.withValues(alpha: 0.2),
                  AppColors.primary.withValues(alpha: 0.15),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.success.withValues(alpha: _glowAnimation.value),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.success.withValues(alpha: _glowAnimation.value * 0.4),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.person_add,
                    color: AppColors.success,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'organizer.invite_driver'.tr(),
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'organizer.share_app_subtitle'.tr(),
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.share,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
