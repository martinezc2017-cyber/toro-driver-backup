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
/// Privacidad: Solo datos necesarios, información sensible encriptada para TORO admin
class OrganizerEventsHistoryTab extends StatefulWidget {
  const OrganizerEventsHistoryTab({super.key});

  @override
  State<OrganizerEventsHistoryTab> createState() => _OrganizerEventsHistoryTabState();
}

class _OrganizerEventsHistoryTabState extends State<OrganizerEventsHistoryTab> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _events = [];
  String _filterStatus = 'all'; // all, completed, in_progress, cancelled

  @override
  void initState() {
    super.initState();
    _loadEvents();
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
          _error = 'No se pudo obtener el perfil';
        });
        return;
      }

      // Obtener perfil de organizador (tabla correcta: organizers)
      final profile = await SupabaseConfig.client
          .from('organizers')
          .select('id')
          .eq('user_id', userId)
          .maybeSingle();

      final organizerId = profile?['id'] ?? userId;

      // Consulta simple - solo datos de tourism_events
      final response = await SupabaseConfig.client
          .from('tourism_events')
          .select('*')
          .eq('organizer_id', organizerId)
          .order('event_date', ascending: false);

      if (mounted) {
        setState(() {
          _events = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Error al cargar eventos: $e';
        });
      }
    }
  }

  Future<void> _downloadEventReport(Map<String, dynamic> event) async {
    HapticService.mediumImpact();
    
    try {
      // Generar reporte completo
      final report = _generateReport(event);
      
      // Guardar temporalmente
      final directory = await getTemporaryDirectory();
      final fileName = 'TORO_Evento_${event['event_name']}_${DateFormat('yyyyMMdd').format(DateTime.parse(event['event_date']))}.txt';
      final file = File('${directory.path}/$fileName');
      await file.writeAsString(report);
      
      // Compartir
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Reporte Evento TORO - ${event['event_name']}',
      );
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al generar reporte: $e')),
        );
      }
    }
  }

  String _generateReport(Map<String, dynamic> event) {
    final buffer = StringBuffer();
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    
    buffer.writeln('=' * 60);
    buffer.writeln('REPORTE DE EVENTO - TORO RIDESHARE');
    buffer.writeln('=' * 60);
    buffer.writeln();
    
    // Información del Evento
    buffer.writeln('INFORMACIÓN DEL EVENTO');
    buffer.writeln('-' * 40);
    buffer.writeln('Nombre: ${event['event_name']}');
    buffer.writeln('Fecha: ${event['event_date']}');
    buffer.writeln('Hora inicio: ${event['start_time']}');
    buffer.writeln('Estado: ${event['status']}');
    buffer.writeln('Distancia: ${event['total_distance_km']} km');
    buffer.writeln();
    
    // Información del Vehículo
    if (event['vehicle_id'] != null) {
      buffer.writeln('INFORMACIÓN DEL VEHÍCULO');
      buffer.writeln('-' * 40);
      buffer.writeln('Vehículo ID: ${event['vehicle_id']}');
      buffer.writeln('(Detalles completos en panel de administración)');
      buffer.writeln();
    }
    
    // Información Financiera
    buffer.writeln('INFORMACIÓN FINANCIERA');
    buffer.writeln('-' * 40);
    final pricePerKm = (event['price_per_km'] as num?)?.toDouble() ?? 0;
    final distance = (event['total_distance_km'] as num?)?.toDouble() ?? 0;
    final totalDriver = pricePerKm * distance;
    final toroCommission = totalDriver * 0.18;
    final totalOrganizer = totalDriver + toroCommission;
    
    buffer.writeln('Precio por km: \$${pricePerKm.toStringAsFixed(2)}');
    buffer.writeln('Distancia total: ${distance.toStringAsFixed(1)} km');
    buffer.writeln('Pago al chofer: \$${totalDriver.toStringAsFixed(2)}');
    buffer.writeln('Comisión TORO (18%): \$${toroCommission.toStringAsFixed(2)}');
    buffer.writeln('TOTAL GASTADO: \$${totalOrganizer.toStringAsFixed(2)}');
    buffer.writeln();
    
    // Itinerario
    buffer.writeln('ITINERARIO');
    buffer.writeln('-' * 40);
    final itinerary = event['itinerary'] as List<dynamic>? ?? [];
    for (int i = 0; i < itinerary.length; i++) {
      final stop = itinerary[i] as Map<String, dynamic>;
      buffer.writeln('${i + 1}. ${stop['name']}');
      buffer.writeln('   Dirección: ${stop['address'] ?? 'N/A'}');
      buffer.writeln('   Hora estimada: ${stop['estimated_time'] ?? 'N/A'}');
      buffer.writeln();
    }
    
    // Pasajeros
    buffer.writeln('PASAJEROS');
    buffer.writeln('-' * 40);
    buffer.writeln('Capacidad máxima: ${event['max_passengers'] ?? 'N/A'} pasajeros');
    buffer.writeln();
    buffer.writeln('(Detalles de pasajeros disponibles en panel de administración)');
    buffer.writeln();
    
    // Tracking
    buffer.writeln('TRACKING GPS');
    buffer.writeln('-' * 40);
    buffer.writeln('Información disponible en panel de administración TORO');
    
    buffer.writeln();
    buffer.writeln('=' * 60);
    buffer.writeln('Generado: ${dateFormat.format(DateTime.now())}');
    buffer.writeln('TORO RIDESHARE - Reporte Confidencial');
    buffer.writeln('=' * 60);
    
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(
          'Historial de Eventos',
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
            child: Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        // Filtros
        _buildFilters(),
        
        // Lista de eventos
        Expanded(
          child: _events.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: EdgeInsets.all(16),
                  itemCount: _events.length,
                  itemBuilder: (context, index) {
                    return _buildEventCard(_events[index]);
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
            _buildFilterChip('Todos', 'all'),
            SizedBox(width: 8),
            _buildFilterChip('Completados', 'completed'),
            SizedBox(width: 8),
            _buildFilterChip('En Progreso', 'in_progress'),
            SizedBox(width: 8),
            _buildFilterChip('Cancelados', 'cancelled'),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filterStatus == value;
    return GestureDetector(
      onTap: () {
        setState(() => _filterStatus = value);
        _loadEvents();
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
            'No hay eventos',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventCard(Map<String, dynamic> event) {
    // Datos básicos del evento
    final itinerary = event['itinerary'] as List<dynamic>? ?? [];
    
    // Calcular totales (datos del evento)
    final pricePerKm = (event['price_per_km'] as num?)?.toDouble() ?? 0;
    final distance = (event['total_distance_km'] as num?)?.toDouble() ?? 0;
    final totalDriver = pricePerKm * distance;
    final toroCommission = totalDriver * 0.18;
    final totalOrganizer = totalDriver + toroCommission;
    
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
              // Header
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event['event_name'] ?? 'Evento sin nombre',
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
              
              // Info básica del vehículo (si existe vehicle_id)
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
                        'Vehículo asignado',
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
              
              // Stats
              Row(
                children: [
                  _buildStat(
                    Icons.people,
                    '${event['max_passengers'] ?? '?'}',
                    'Capacidad',
                  ),
                  SizedBox(width: 24),
                  _buildStat(
                    Icons.route,
                    '${distance.toStringAsFixed(1)} km',
                    'Distancia',
                  ),
                  SizedBox(width: 24),
                  _buildStat(
                    Icons.flag,
                    '${itinerary.length}',
                    'Paradas',
                  ),
                ],
              ),
              
              SizedBox(height: 16),
              
              // Financial
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Pago al chofer:',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        Text(
                          '\$${totalDriver.toStringAsFixed(2)}',
                          style: TextStyle(color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Comisión TORO (18%):',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        Text(
                          '\$${toroCommission.toStringAsFixed(2)}',
                          style: TextStyle(color: AppColors.primary),
                        ),
                      ],
                    ),
                    Divider(height: 16, color: AppColors.border),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'TOTAL:',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '\$${totalOrganizer.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: 12),
              
              // Download button
              Row(
                children: [
                  Spacer(),
                  TextButton.icon(
                    onPressed: () => _downloadEventReport(event),
                    icon: Icon(Icons.download, size: 18),
                    label: Text('Descargar Reporte'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String? status) {
    Color color;
    String label;
    
    switch (status) {
      case 'completed':
        color = AppColors.success;
        label = 'Completado';
        break;
      case 'in_progress':
        color = AppColors.primary;
        label = 'En Progreso';
        break;
      case 'cancelled':
        color = AppColors.error;
        label = 'Cancelado';
        break;
      default:
        color = AppColors.textTertiary;
        label = 'Pendiente';
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
    // Navegar a pantalla de detalles completa
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _EventDetailsScreen(event: event),
      ),
    );
  }
}

/// Sheet de detalles del evento
class _EventDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> event;

  const _EventDetailsScreen({required this.event});

  @override
  Widget build(BuildContext context) {
    final driver = event['driver'] as Map<String, dynamic>?;
    final vehicle = event['vehicle'] as Map<String, dynamic>?;
    final passengers = event['passengers'] as List<dynamic>? ?? [];
    final itinerary = event['itinerary'] as List<dynamic>? ?? [];
    final tracking = event['tracking'] as List<dynamic>? ?? [];
    
    return Container(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          SizedBox(height: 20),
          
          // Title
          Text(
            event['event_name'] ?? 'Evento',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 20),
          
          // Sections
          _buildSection('Información General', [
            _buildInfoRow('Fecha', event['event_date'] ?? 'N/A'),
            _buildInfoRow('Hora', event['start_time'] ?? 'N/A'),
            _buildInfoRow('Estado', event['status'] ?? 'N/A'),
            _buildInfoRow('Distancia', '${event['total_distance_km']} km'),
          ]),
          
          if (vehicle != null)
            _buildSection('Información del Vehículo', [
              _buildInfoRow('Vehículo', vehicle['vehicle_name'] ?? 'N/A'),
              _buildInfoRow('Marca/Modelo', '${vehicle['make'] ?? ''} ${vehicle['model'] ?? ''} ${vehicle['year'] ?? ''}'),
              _buildInfoRow('Asientos', '${vehicle['total_seats'] ?? 'N/A'}'),
            ]),
          
          _buildSection('Itinerario', 
            itinerary.map((stop) {
              final s = stop as Map<String, dynamic>;
              return _buildInfoRow('•', '${s['name']}${s['estimated_time'] != null ? ' - ${s['estimated_time']}' : ''}');
            }).toList(),
          ),
          
          _buildSection('Pasajeros',
            [
              _buildInfoRow('Capacidad máxima', '${event['max_passengers'] ?? 'N/A'} pasajeros'),
              _buildInfoRow('Nota', 'Detalles de pasajeros en panel de admin'),
            ],
          ),
          
          // Tracking (TORO Admin only)
          _buildSection('Tracking GPS', [
            _buildInfoRow('Estado', 'Disponible para TORO Admin'),
          ]),
          
          SizedBox(height: 20),
        ],
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
