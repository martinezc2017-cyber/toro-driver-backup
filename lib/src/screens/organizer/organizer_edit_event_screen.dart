import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../services/tourism_event_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';
import '../../widgets/scrollable_time_picker.dart';

/// Screen for editing an existing tourism event.
///
/// Allows organizers to modify event details such as:
/// - Event name
/// - Description
/// - Event date
/// - Start and end times
/// - Maximum passengers
///
/// Can only edit events with status 'draft' or 'vehicle_accepted'.
class OrganizerEditEventScreen extends StatefulWidget {
  final String eventId;

  const OrganizerEditEventScreen({
    super.key,
    required this.eventId,
  });

  @override
  State<OrganizerEditEventScreen> createState() =>
      _OrganizerEditEventScreenState();
}

class _OrganizerEditEventScreenState extends State<OrganizerEditEventScreen> {
  final TourismEventService _tourismService = TourismEventService();
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _maxPassengersController = TextEditingController();

  // State
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  Map<String, dynamic>? _event;
  DateTime _eventDate = DateTime.now().add(const Duration(days: 7));
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 18, minute: 0);

  // Editable statuses
  static const _editableStatuses = ['draft', 'vehicle_accepted'];

  @override
  void initState() {
    super.initState();
    _loadEvent();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _maxPassengersController.dispose();
    super.dispose();
  }

  Future<void> _loadEvent() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final event = await _tourismService.getEvent(widget.eventId);

      if (event == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = 'Evento no encontrado';
          });
        }
        return;
      }

      // Check if event can be edited
      final status = event['status'] as String? ?? '';
      if (!_editableStatuses.contains(status)) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = 'Este evento no puede ser editado. Status: $status';
          });
        }
        return;
      }

      // Populate form fields
      _nameController.text = event['event_name'] as String? ?? '';
      _descriptionController.text = event['event_description'] as String? ?? '';
      _maxPassengersController.text =
          (event['max_passengers'] as int?)?.toString() ?? '';

      // Parse event date
      final eventDateStr = event['event_date'] as String?;
      if (eventDateStr != null && eventDateStr.isNotEmpty) {
        try {
          _eventDate = DateTime.parse(eventDateStr);
        } catch (_) {
          // Keep default date
        }
      }

      // Parse start time
      final startTimeStr = event['start_time'] as String?;
      if (startTimeStr != null && startTimeStr.isNotEmpty) {
        _startTime = _parseTime(startTimeStr);
      }

      // Parse end time
      final endTimeStr = event['end_time'] as String?;
      if (endTimeStr != null && endTimeStr.isNotEmpty) {
        _endTime = _parseTime(endTimeStr);
      }

      if (mounted) {
        setState(() {
          _event = event;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Error al cargar evento: $e';
        });
      }
    }
  }

  TimeOfDay _parseTime(String timeStr) {
    try {
      final parts = timeStr.split(':');
      if (parts.length >= 2) {
        return TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );
      }
    } catch (_) {
      // Return default
    }
    return const TimeOfDay(hour: 9, minute: 0);
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) {
      HapticService.warning();
      return;
    }

    setState(() => _isSaving = true);
    HapticService.lightImpact();

    try {
      final updates = <String, dynamic>{
        'event_name': _nameController.text.trim(),
        'event_description': _descriptionController.text.trim(),
        'event_date': _eventDate.toIso8601String().split('T')[0],
        'start_time':
            '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}:00',
        'end_time':
            '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}:00',
      };

      // Add max passengers if provided
      final maxPassengersText = _maxPassengersController.text.trim();
      if (maxPassengersText.isNotEmpty) {
        final maxPassengers = int.tryParse(maxPassengersText);
        if (maxPassengers != null && maxPassengers > 0) {
          updates['max_passengers'] = maxPassengers;
        }
      }

      final result =
          await _tourismService.updateEvent(widget.eventId, updates);

      if (mounted) {
        setState(() => _isSaving = false);

        if (result.isEmpty) {
          HapticService.error();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error al guardar cambios'),
              backgroundColor: AppColors.error,
            ),
          );
        } else {
          HapticService.success();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cambios guardados exitosamente'),
              backgroundColor: AppColors.success,
            ),
          );
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        HapticService.error();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _selectDate() async {
    HapticService.lightImpact();
    final picked = await showDatePicker(
      context: context,
      initialDate: _eventDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.primary,
              surface: AppColors.surface,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _eventDate = picked);
    }
  }

  Future<void> _selectStartTime() async {
    HapticService.lightImpact();
    final picked = await showScrollableTimePicker(context, _startTime, primaryColor: AppColors.primary);
    if (picked != null) {
      setState(() => _startTime = picked);
    }
  }

  Future<void> _selectEndTime() async {
    HapticService.lightImpact();
    final picked = await showScrollableTimePicker(context, _endTime, primaryColor: AppColors.primary);
    if (picked != null) {
      setState(() => _endTime = picked);
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
          icon: const Icon(Icons.close, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Editar Evento',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 16),
            Text(
              'Cargando evento...',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.error_outline,
                  color: AppColors.error,
                  size: 48,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _error!,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Volver'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _loadEvent,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return _buildForm();
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Event status banner
          _buildStatusBanner(),
          const SizedBox(height: 24),

          // Event Name
          _buildSectionTitle('Nombre del Evento'),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _nameController,
            hint: 'Ej: Tour a las Piramides',
            icon: Icons.event,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'El nombre del evento es requerido';
              }
              if (value.trim().length < 3) {
                return 'El nombre debe tener al menos 3 caracteres';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),

          // Description
          _buildSectionTitle('Descripcion'),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _descriptionController,
            hint: 'Describe el evento...',
            icon: Icons.description,
            maxLines: 4,
          ),
          const SizedBox(height: 20),

          // Event Date
          _buildSectionTitle('Fecha del Evento'),
          const SizedBox(height: 8),
          _buildDatePicker(),
          const SizedBox(height: 20),

          // Time pickers
          _buildSectionTitle('Horario'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildTimePicker('Hora de Inicio', _startTime, _selectStartTime)),
              const SizedBox(width: 12),
              Expanded(child: _buildTimePicker('Hora de Fin', _endTime, _selectEndTime)),
            ],
          ),
          const SizedBox(height: 12),
          _buildDurationInfo(),
          const SizedBox(height: 20),

          // Max Passengers
          _buildSectionTitle('Pasajeros Maximos (Opcional)'),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _maxPassengersController,
            hint: 'Ej: 40',
            icon: Icons.people,
            keyboardType: TextInputType.number,
            validator: (value) {
              if (value != null && value.trim().isNotEmpty) {
                final number = int.tryParse(value.trim());
                if (number == null || number <= 0) {
                  return 'Ingresa un numero valido';
                }
              }
              return null;
            },
          ),
          const SizedBox(height: 32),

          // Action buttons
          _buildActionButtons(),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  Widget _buildStatusBanner() {
    final status = _event?['status'] as String? ?? 'draft';
    final vehicleName = _event?['bus_vehicles']?['vehicle_name'] as String?;

    IconData statusIcon;
    Color statusColor;
    String statusLabel;

    switch (status) {
      case 'draft':
        statusIcon = Icons.edit_outlined;
        statusColor = AppColors.warning;
        statusLabel = 'Esperando Puja';
        break;
      case 'vehicle_accepted':
        statusIcon = Icons.check_circle_outline;
        statusColor = AppColors.success;
        statusLabel = 'Vehiculo Confirmado';
        break;
      default:
        statusIcon = Icons.info_outline;
        statusColor = AppColors.textTertiary;
        statusLabel = status;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(statusIcon, color: statusColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Estado: $statusLabel',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (vehicleName != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.directions_bus,
                        color: AppColors.textTertiary,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        vehicleName,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: TextFormField(
        controller: controller,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
        maxLines: maxLines,
        keyboardType: keyboardType,
        validator: validator,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
          prefixIcon: Padding(
            padding: EdgeInsets.only(
              left: 14,
              right: 10,
              top: maxLines > 1 ? 14 : 0,
            ),
            child: Icon(icon, size: 18, color: AppColors.textTertiary),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 42),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: maxLines > 1 ? 14 : 16,
          ),
          errorStyle: const TextStyle(
            color: AppColors.error,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _buildDatePicker() {
    return GestureDetector(
      onTap: _selectDate,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.calendar_today,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Fecha del Evento',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(_eventDate),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePicker(String label, TimeOfDay time, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.access_time, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Text(
                  _formatTime(time),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationInfo() {
    final startMinutes = _startTime.hour * 60 + _startTime.minute;
    final endMinutes = _endTime.hour * 60 + _endTime.minute;
    var durationMinutes = endMinutes - startMinutes;

    // Handle next day scenario
    if (durationMinutes < 0) {
      durationMinutes += 24 * 60;
    }

    final hours = durationMinutes ~/ 60;
    final minutes = durationMinutes % 60;

    final isValid = durationMinutes > 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isValid
            ? AppColors.primary.withValues(alpha: 0.1)
            : AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isValid
              ? AppColors.primary.withValues(alpha: 0.3)
              : AppColors.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.timer,
            color: isValid ? AppColors.primary : AppColors.error,
            size: 18,
          ),
          const SizedBox(width: 10),
          Text(
            isValid
                ? 'Duracion estimada: ${hours}h ${minutes > 0 ? '${minutes}m' : ''}'
                : 'Hora de fin debe ser despues de inicio',
            style: TextStyle(
              color: isValid ? AppColors.primary : AppColors.error,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        // Save button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _saveChanges,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.3),
              disabledForegroundColor: Colors.white60,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.save, size: 20),
                      SizedBox(width: 10),
                      Text(
                        'Guardar Cambios',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        // Cancel button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            onPressed: _isSaving ? null : () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Cancelar',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  String _formatDate(DateTime date) {
    const months = [
      'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
      'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
    ];
    const weekdays = [
      'Lun', 'Mar', 'Mie', 'Jue', 'Vie', 'Sab', 'Dom',
    ];
    return '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
