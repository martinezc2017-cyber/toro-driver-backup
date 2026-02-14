import 'package:flutter/material.dart';
import '../services/bus_tracking_service.dart';

/// Panel with quick action buttons for bus events
class BusEventPanel extends StatefulWidget {
  final String routeId;
  final String driverId;
  final String? vehicleId;
  final VoidCallback? onRouteCompleted;

  const BusEventPanel({
    super.key,
    required this.routeId,
    required this.driverId,
    this.vehicleId,
    this.onRouteCompleted,
  });

  @override
  State<BusEventPanel> createState() => _BusEventPanelState();
}

class _BusEventPanelState extends State<BusEventPanel> {
  final _trackingService = BusTrackingService();
  bool _isTracking = false;
  int _passengers = 0;

  @override
  void initState() {
    super.initState();
    _trackingService.addListener(_onTrackingUpdate);
  }

  @override
  void dispose() {
    _trackingService.removeListener(_onTrackingUpdate);
    super.dispose();
  }

  void _onTrackingUpdate() {
    if (mounted) {
      setState(() {
        _isTracking = _trackingService.isTracking;
        _passengers = _trackingService.passengersOnBoard;
      });
    }
  }

  Future<void> _startRoute() async {
    await _trackingService.startTracking(
      driverId: widget.driverId,
      routeId: widget.routeId,
      vehicleId: widget.vehicleId,
    );
    await _trackingService.departed();
    _showSnackBar('Ruta iniciada - GPS activo');
  }

  Future<void> _endRoute() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Finalizar Ruta', style: TextStyle(color: Colors.white)),
        content: const Text(
          '¿Estás seguro de que quieres finalizar esta ruta?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _trackingService.completed();
      _showSnackBar('Ruta completada');
      widget.onRouteCompleted?.call();
    }
  }

  Future<void> _logStop() async {
    final stopName = await _showInputDialog('Nombre de la parada', 'Ej: Estación Central');
    if (stopName != null && stopName.isNotEmpty) {
      await _trackingService.arrivedAtStop(stopName);
      _showSnackBar('Parada registrada: $stopName');
    }
  }

  Future<void> _passengerBoarded() async {
    final countStr = await _showInputDialog('Pasajeros que suben', '1', isNumber: true);
    final count = int.tryParse(countStr ?? '1') ?? 1;
    await _trackingService.passengerBoarded(count: count);
    _showSnackBar('+$count pasajero(s) abordaron');
  }

  Future<void> _passengerDropped() async {
    final countStr = await _showInputDialog('Pasajeros que bajan', '1', isNumber: true);
    final count = int.tryParse(countStr ?? '1') ?? 1;
    await _trackingService.passengerDropped(count: count);
    _showSnackBar('-$count pasajero(s) bajaron');
  }

  Future<void> _reportEmergency() async {
    final notes = await _showInputDialog('Descripción de la emergencia', 'Describe lo que pasó...');
    if (notes != null && notes.isNotEmpty) {
      await _trackingService.emergency(notes);
      _showSnackBar('EMERGENCIA REPORTADA', isError: true);
    }
  }

  Future<void> _reportDelay() async {
    final notes = await _showInputDialog('Motivo del retraso', 'Ej: Tráfico en la autopista');
    if (notes != null && notes.isNotEmpty) {
      await _trackingService.reportDelay(notes);
      _showSnackBar('Retraso reportado');
    }
  }

  Future<String?> _showInputDialog(String title, String hint, {bool isNumber = false}) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF0A0A0A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with passenger count
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _isTracking
                      ? Colors.green.withOpacity(0.2)
                      : Colors.grey.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isTracking ? Icons.gps_fixed : Icons.gps_off,
                  color: _isTracking ? Colors.green : Colors.grey,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isTracking ? 'GPS Activo' : 'GPS Inactivo',
                      style: TextStyle(
                        color: _isTracking ? Colors.green : Colors.grey,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_isTracking)
                      Text(
                        'Enviando ubicación cada 10s',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              // Passenger counter
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.people, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '$_passengers',
                      style: const TextStyle(
                        color: Colors.blue,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Start/End route button
          if (!_isTracking)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _startRoute,
                icon: const Icon(Icons.play_arrow),
                label: const Text('INICIAR RUTA'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            )
          else ...[
            // Action buttons grid
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildEventButton(
                  icon: Icons.location_on,
                  label: 'Parada',
                  color: Colors.blue,
                  onTap: _logStop,
                ),
                _buildEventButton(
                  icon: Icons.person_add,
                  label: 'Subieron',
                  color: Colors.green,
                  onTap: _passengerBoarded,
                ),
                _buildEventButton(
                  icon: Icons.person_remove,
                  label: 'Bajaron',
                  color: Colors.purple,
                  onTap: _passengerDropped,
                ),
                _buildEventButton(
                  icon: Icons.schedule,
                  label: 'Retraso',
                  color: Colors.orange,
                  onTap: _reportDelay,
                ),
                _buildEventButton(
                  icon: Icons.emergency,
                  label: 'Emergencia',
                  color: Colors.red,
                  onTap: _reportEmergency,
                ),
              ],
            ),
            const SizedBox(height: 16),
            // End route button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _endRoute,
                icon: const Icon(Icons.check_circle),
                label: const Text('FINALIZAR RUTA'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.green,
                  side: const BorderSide(color: Colors.green),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEventButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
