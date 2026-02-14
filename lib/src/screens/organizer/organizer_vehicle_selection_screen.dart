import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/organizer_service.dart';
import '../../services/tourism_event_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';

/// Screen for organizers to select and request a vehicle for a tourism event.
///
/// Displays available bus vehicles and allows the organizer to send a request
/// to a specific driver to use their vehicle for the event.
class OrganizerVehicleSelectionScreen extends StatefulWidget {
  final String eventId;

  const OrganizerVehicleSelectionScreen({
    super.key,
    required this.eventId,
  });

  @override
  State<OrganizerVehicleSelectionScreen> createState() =>
      _OrganizerVehicleSelectionScreenState();
}

class _OrganizerVehicleSelectionScreenState
    extends State<OrganizerVehicleSelectionScreen> {
  final OrganizerService _organizerService = OrganizerService();
  final TourismEventService _eventService = TourismEventService();
  final TextEditingController _stateFilterController = TextEditingController();

  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _vehicles = [];
  String? _currentStateFilter;
  Map<String, dynamic>? _event;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _stateFilterController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _eventService.getEvent(widget.eventId),
        _organizerService.browseVehicles(state: _currentStateFilter),
      ]);

      if (mounted) {
        setState(() {
          _event = results[0] as Map<String, dynamic>?;
          _vehicles = results[1] as List<Map<String, dynamic>>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Error al cargar vehiculos: $e';
        });
      }
    }
  }

  void _applyFilter() {
    HapticService.lightImpact();
    final text = _stateFilterController.text.trim();
    _currentStateFilter = text.isEmpty ? null : text;
    _loadData();
  }

  Future<void> _requestVehicle(Map<String, dynamic> vehicle) async {
    final vehicleId = vehicle['id'] as String?;
    final ownerId = vehicle['owner_id'] as String?;

    if (vehicleId == null || ownerId == null) {
      _showError('Datos del vehiculo incompletos');
      return;
    }

    // Confirm before sending request
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Solicitar Vehiculo',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          '¿Deseas solicitar el vehiculo "${vehicle['vehicle_name']}" para este evento?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            child: const Text('Solicitar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    HapticService.mediumImpact();

    try {
      await _eventService.requestVehicle(
        widget.eventId,
        vehicleId,
        ownerId,
      );

      if (mounted) {
        HapticService.success();
        _showSuccess('Solicitud enviada al conductor');
        // Go back to event dashboard
        Navigator.pop(context, true);
      }
    } catch (e) {
      HapticService.error();
      _showError('Error al enviar solicitud: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eventName = _event?['event_name'] ?? 'Evento';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Seleccionar Vehiculo',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Event header
          _buildEventHeader(eventName),
          // Filter bar
          _buildFilterBar(),
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
                            onRefresh: _loadData,
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

  Widget _buildEventHeader(String eventName) {
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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.directions_bus,
              color: AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Selecciona un vehiculo para:',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  eventName,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
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
                decoration: const InputDecoration(
                  hintText: 'Filtrar por estado (ej: AZ)',
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
              _error ?? 'Error desconocido',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14),
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
            const Text(
              'No se encontraron vehiculos',
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text(
              'Intenta cambiar el filtro de estado',
              style:
                  TextStyle(color: AppColors.textTertiary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleCard(Map<String, dynamic> vehicle) {
    final vehicleName = vehicle['vehicle_name'] ?? 'Sin nombre';
    final type = vehicle['type'] ?? 'autobus';
    final ownerName = vehicle['owner_name'] ?? 'Propietario';
    final ownerPhone = vehicle['owner_phone'] ?? '';
    final totalSeats = vehicle['total_seats'] ?? 0;

    final typeIcon =
        type == 'minibus' ? Icons.airport_shuttle : Icons.directions_bus;
    final typeLabel = type == 'minibus' ? 'Minibus' : 'Autobus';

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
            // Vehicle icon
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(typeIcon, size: 26, color: AppColors.primary),
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
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          typeLabel,
                          style: const TextStyle(
                            color: AppColors.primaryLight,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.event_seat,
                          size: 12, color: AppColors.textTertiary),
                      const SizedBox(width: 3),
                      Text(
                        '$totalSeats asientos',
                        style: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.person_outline,
                          size: 12, color: AppColors.textTertiary),
                      const SizedBox(width: 4),
                      Text(
                        ownerName,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      if (ownerPhone.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.phone_outlined,
                            size: 12, color: AppColors.textTertiary),
                        const SizedBox(width: 3),
                        Text(
                          ownerPhone,
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
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
    final type = vehicle['type'] ?? 'autobus';

    // Bus/Company owner
    final busOwnerName = vehicle['owner_name'] ?? '';
    final busOwnerPhone = vehicle['owner_phone'] ?? '';

    // Driver (who operates the bus)
    final driverName = vehicle['driver_name'] ?? 'Sin nombre';
    final driverPhone = vehicle['driver_phone'] ?? '';
    final driverEmail = vehicle['driver_email'] ?? '';
    final driverPhoneHidden = vehicle['driver_phone_hidden'] == true;

    // Co-driver
    final codriverName = vehicle['codriver_name'] ?? '';
    final codriverPhone = vehicle['codriver_phone'] ?? '';

    final totalSeats = vehicle['total_seats'] ?? 0;
    final state = vehicle['state'] ?? '';
    final imageUrls = (vehicle['image_urls'] as List?)?.cast<String>() ?? [];
    final availableDays = (vehicle['available_days'] as List?)?.cast<String>() ?? [];
    final availableStart = vehicle['available_hours_start'] ?? '';
    final availableEnd = vehicle['available_hours_end'] ?? '';
    final availabilityNotes = vehicle['availability_notes'] ?? '';

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
              // Photos section
              if (imageUrls.isNotEmpty) ...[
                SizedBox(
                  height: 120,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: imageUrls.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: EdgeInsets.only(
                          right: index < imageUrls.length - 1 ? 8 : 0,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            imageUrls[index],
                            width: 160,
                            height: 120,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 160,
                                height: 120,
                                color: AppColors.surface,
                                child: const Icon(
                                  Icons.broken_image,
                                  color: AppColors.textTertiary,
                                  size: 40,
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
              // Details
              _detailRow(Icons.category, 'Tipo',
                  type == 'minibus' ? 'Minibus' : 'Autobus'),
              _detailRow(Icons.event_seat, 'Asientos', '$totalSeats'),
              if (state.isNotEmpty)
                _detailRow(Icons.location_on, 'Estado', state),
              const SizedBox(height: 16),
              // Bus/Company Owner contact
              if (busOwnerName.isNotEmpty || busOwnerPhone.isNotEmpty)
                _buildContactCard(
                  name: busOwnerName.isEmpty ? 'Dueño del Camión' : busOwnerName,
                  phone: busOwnerPhone,
                  role: 'Dueño del Camión',
                  icon: Icons.business,
                  color: Color(0xFF9C27B0), // Purple
                ),
              if (busOwnerName.isNotEmpty || busOwnerPhone.isNotEmpty)
                const SizedBox(height: 12),
              // Driver contact
              _buildContactCard(
                name: driverName,
                phone: driverPhone,
                email: driverEmail,
                role: 'Chofer',
                icon: Icons.drive_eta,
                color: AppColors.primary,
                phoneHidden: driverPhoneHidden,
              ),
              // Co-driver contact
              if (codriverName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _buildContactCard(
                    name: codriverName,
                    phone: codriverPhone,
                    role: 'Cohofer',
                    icon: Icons.person_outline,
                    color: AppColors.success,
                  ),
                ),
              const SizedBox(height: 16),
              // Availability section
              if (availableDays.isNotEmpty || availableStart.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.schedule, color: AppColors.primary, size: 16),
                          SizedBox(width: 8),
                          Text(
                            'Disponibilidad',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (availableStart.isNotEmpty && availableEnd.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Horario: $availableStart - $availableEnd',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (availableDays.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: availableDays.map((day) {
                            final dayLabel = _getDayLabel(day);
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                dayLabel,
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      if (availabilityNotes.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          availabilityNotes,
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              // Request button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _requestVehicle(vehicle);
                  },
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text(
                    'Solicitar para Evento',
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

  Widget _buildContactCard({
    required String name,
    required String phone,
    String? email,
    required String role,
    required IconData icon,
    required Color color,
    bool phoneHidden = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 18),
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
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      role,
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                    if (email != null && email.isNotEmpty)
                      Text(
                        email,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (phoneHidden) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.lock_outline, size: 14, color: AppColors.textTertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Teléfono oculto por privacidad',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ] else if (phone.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    phone,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildMiniActionButton(
                  icon: Icons.phone,
                  color: AppColors.success,
                  onTap: () => _launchPhone(phone),
                ),
                const SizedBox(width: 6),
                _buildMiniActionButton(
                  icon: Icons.message,
                  color: AppColors.purple,
                  onTap: () => _launchSMS(phone),
                ),
                const SizedBox(width: 6),
                _buildMiniActionButton(
                  icon: Icons.chat_bubble,
                  color: Color(0xFF25D366),
                  onTap: () => _launchWhatsApp(phone),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMiniActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticService.lightImpact();
        onTap();
      },
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

  Future<void> _launchPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showError('No se puede abrir el telefono');
    }
  }

  Future<void> _launchSMS(String phone) async {
    final uri = Uri.parse('sms:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showError('No se puede abrir mensajes');
    }
  }

  Future<void> _launchWhatsApp(String phone) async {
    // Remove any non-digit characters from phone
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    final uri = Uri.parse('https://wa.me/$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showError('No se puede abrir WhatsApp');
    }
  }

  String _getDayLabel(String day) {
    final labels = {
      'monday': 'Lun',
      'tuesday': 'Mar',
      'wednesday': 'Mié',
      'thursday': 'Jue',
      'friday': 'Vie',
      'saturday': 'Sáb',
      'sunday': 'Dom',
    };
    return labels[day.toLowerCase()] ?? day;
  }
}
