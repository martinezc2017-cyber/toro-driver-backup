import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../utils/image_clipboard.dart'
    if (dart.library.html) '../../utils/image_clipboard_web.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/tourism_event_service.dart';
import '../../services/tourism_invitation_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';
import '../../widgets/travel_card_widget.dart';

/// Compact invite screen: KPI bar, travel card with QR, share actions,
/// add passengers form, and passenger list.
class OrganizerInviteScreen extends StatefulWidget {
  final String eventId;

  const OrganizerInviteScreen({
    super.key,
    required this.eventId,
  });

  @override
  State<OrganizerInviteScreen> createState() => _OrganizerInviteScreenState();
}

class _OrganizerInviteScreenState extends State<OrganizerInviteScreen>
    with SingleTickerProviderStateMixin {
  final TourismEventService _eventService = TourismEventService();
  final TourismInvitationService _invitationService =
      TourismInvitationService();

  final GlobalKey _cardKey = GlobalKey();

  // Slide panel animation
  late final AnimationController _panelController;
  late final Animation<double> _panelSlide;
  bool _panelOpen = false;

  bool _isLoading = true;
  Map<String, dynamic>? _event;
  List<Map<String, dynamic>> _invitations = [];
  Map<String, dynamic> _stats = {};
  bool _showPrice = true;

  // Manual invitation form
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  bool _isAddingInvitation = false;

  // Real-time updates
  RealtimeChannel? _invitationsChannel;
  RealtimeChannel? _eventChannel;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _panelSlide = CurvedAnimation(
      parent: _panelController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _loadData();
    _subscribeToUpdates();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshStats();
    });
  }

  @override
  void dispose() {
    _panelController.dispose();
    _nameController.dispose();
    _contactController.dispose();
    _refreshTimer?.cancel();
    final client = Supabase.instance.client;
    if (_invitationsChannel != null) {
      client.removeChannel(_invitationsChannel!);
      _invitationsChannel = null;
    }
    if (_eventChannel != null) {
      client.removeChannel(_eventChannel!);
      _eventChannel = null;
    }
    super.dispose();
  }

  void _togglePanel() {
    HapticService.lightImpact();
    if (_panelOpen) {
      _panelController.reverse();
    } else {
      _panelController.forward();
    }
    _panelOpen = !_panelOpen;
  }

  void _subscribeToUpdates() {
    final supabase = Supabase.instance.client;

    // Listen to invitation changes (accepted, declined, new, deleted)
    _invitationsChannel =
        supabase.channel('invitations_screen_${widget.eventId}');
    _invitationsChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tourism_invitations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'event_id',
            value: widget.eventId,
          ),
          callback: (payload) {
            _loadData();
          },
        )
        .subscribe();

    // Listen to event changes (seats, price, status, route, organizer/driver profile)
    _eventChannel =
        supabase.channel('event_screen_${widget.eventId}');
    _eventChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'tourism_events',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.eventId,
          ),
          callback: (payload) {
            _loadData();
          },
        )
        .subscribe();
  }

  Future<void> _refreshStats() async {
    try {
      final stats =
          await _invitationService.getInvitationStats(widget.eventId);
      if (mounted) {
        setState(() => _stats = stats);
      }
    } catch (_) {}
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        _eventService.getEvent(widget.eventId),
        _invitationService.getEventInvitations(widget.eventId),
        _invitationService.getInvitationStats(widget.eventId),
      ]);

      if (mounted) {
        setState(() {
          _event = results[0] as Map<String, dynamic>?;
          _invitations = results[1] as List<Map<String, dynamic>>;
          _stats = results[2] as Map<String, dynamic>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError('Error al cargar datos: $e');
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DATA GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  String get _invitationCode {
    return _event?['invitation_code'] ??
        'EVT-${widget.eventId.substring(0, 8).toUpperCase()}';
  }

  String get _invitationLink {
    return 'tororider://tourism/invite/$_invitationCode';
  }

  int get _totalSeats {
    final maxP = (_event?['max_passengers'] as num?)?.toInt() ?? 0;
    return maxP > 0 ? maxP : (_event?['total_seats'] ?? 40);
  }

  int get _acceptedCount => _stats['accepted'] ?? 0;
  int get _availableSeats => _totalSeats - _acceptedCount;

  List<dynamic> get _itinerary {
    final it = _event?['itinerary'];
    if (it is List) return it;
    return [];
  }

  String get _originName {
    if (_itinerary.isEmpty) return 'Origen';
    final first = _itinerary.first;
    if (first is Map) return first['name'] ?? 'Origen';
    return 'Origen';
  }

  String get _destinationName {
    if (_itinerary.isEmpty) return 'Destino';
    final last = _itinerary.last;
    if (last is Map) return last['name'] ?? 'Destino';
    return 'Destino';
  }

  int get _stopsCount => _itinerary.length;

  double get _distanceKm {
    final d = _event?['estimated_distance_km'] ??
        _event?['total_distance_km'] ??
        _event?['distance_km'];
    if (d is num) return d.toDouble();
    // Sum distance_km from stops if available
    double total = 0;
    for (final stop in _itinerary) {
      if (stop is Map) {
        final dist = stop['distance_km'];
        if (dist is num) total += dist.toDouble();
      }
    }
    if (total > 0) return total;
    // Calculate from coordinates (haversine) as fallback
    return _calculateDistanceFromCoords();
  }

  double _calculateDistanceFromCoords() {
    double total = 0;
    for (int i = 0; i < _itinerary.length - 1; i++) {
      final a = _itinerary[i];
      final b = _itinerary[i + 1];
      if (a is Map && b is Map) {
        final lat1 = (a['lat'] as num?)?.toDouble();
        final lng1 = (a['lng'] as num?)?.toDouble();
        final lat2 = (b['lat'] as num?)?.toDouble();
        final lng2 = (b['lng'] as num?)?.toDouble();
        if (lat1 != null && lng1 != null && lat2 != null && lng2 != null) {
          total += _haversine(lat1, lng1, lat2, lng2);
        }
      }
    }
    // Haversine gives straight-line; multiply by ~1.3 for road approximation
    return total * 1.3;
  }

  double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371.0; // Earth radius in km
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
        sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double get _ticketPrice {
    final pricePerKm = (_event?['price_per_km'] as num?)?.toDouble() ?? 0;
    if (pricePerKm > 0 && _distanceKm > 0) {
      return pricePerKm * _distanceKm;
    }
    return 0;
  }

  // Organizer has priority. If no organizer, use driver data.
  bool get _hasOrganizer {
    final org = _event?['organizers'] as Map<String, dynamic>?;
    return org != null && (org['company_name'] ?? '').toString().isNotEmpty;
  }

  Map<String, dynamic>? get _org =>
      _event?['organizers'] as Map<String, dynamic>?;
  Map<String, dynamic>? get _drv =>
      _event?['drivers'] as Map<String, dynamic>?;

  // Organizer: only use organizer-specific fields (company_name, contact_phone,
  // contact_email, company_logo_url, website). NEVER fall back to auth profile
  // fields (name, email, avatar_url, phone) which belong to the user account
  // and would mix driver/auth data into the organizer display.

  String get _personName {
    if (_hasOrganizer) return _org?['company_name'] ?? '';
    return _drv?['full_name'] ?? _drv?['name'] ?? '';
  }

  String get _personCompany {
    // For organizer: company_name is already the main title via _personName
    // For driver: no company
    return '';
  }

  String get _personPhone {
    if (_hasOrganizer) {
      final cp = _org?['contact_phone'] as String? ?? '';
      if (cp.isNotEmpty) return cp;
      return _org?['phone'] as String? ?? '';
    }
    return _drv?['contact_phone'] ?? _drv?['phone'] ?? '';
  }

  String get _personEmail {
    if (_hasOrganizer) {
      final ce = _org?['contact_email'] as String? ?? '';
      if (ce.isNotEmpty) return ce;
      return '';
    }
    return _drv?['contact_email'] ?? '';
  }

  String get _personAvatarUrl {
    // Organizer: prefer company logo, then avatar
    if (_hasOrganizer) {
      return _org?['company_logo_url'] ?? _org?['avatar_url'] ?? '';
    }
    return _drv?['profile_image_url'] ?? '';
  }

  String get _personLogoUrl {
    if (_hasOrganizer) return _org?['company_logo_url'] ?? '';
    return _drv?['business_card_url'] ?? '';
  }

  String get _personWebsite {
    if (_hasOrganizer) return _org?['website'] ?? '';
    return '';
  }

  String get _personDescription {
    if (_hasOrganizer) return _org?['description'] ?? '';
    return '';
  }

  String get _eventStatus {
    if (_availableSeats <= 0 && _totalSeats > 0) return 'full';
    final status = _event?['status'] as String?;
    if (status == 'cancelled') return 'cancelled';
    if (status == 'completed') return 'completed';
    return 'active';
  }

  String get _personRole {
    if (_hasOrganizer) return 'Organiza';
    return 'Conduce';
  }

  String get _eventName => _event?['event_name'] as String? ?? '';

  String get _formattedEventDate {
    try {
      final dateStr = _event?['event_date'] as String?;
      if (dateStr == null) return '';
      final date = DateTime.parse(dateStr);

      const days = ['Lun', 'Mar', 'Mie', 'Jue', 'Vie', 'Sab', 'Dom'];
      const months = [
        'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
        'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
      ];

      final dayName = days[date.weekday - 1];
      final monthName = months[date.month - 1];

      final timeStr = _event?['start_time'] as String? ?? '';
      String formattedTime = timeStr;
      if (timeStr.contains(':')) {
        final parts = timeStr.split(':');
        int hour = int.parse(parts[0]);
        final min = parts[1].padLeft(2, '0');
        final ampm = hour >= 12 ? 'PM' : 'AM';
        if (hour > 12) hour -= 12;
        if (hour == 0) hour = 12;
        formattedTime = '$hour:$min $ampm';
      }

      return '$dayName, ${date.day} $monthName \u2022 $formattedTime';
    } catch (e) {
      return '';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

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

  // ── Image capture ──

  Future<Uint8List?> _captureCardImage() async {
    try {
      await Future.delayed(const Duration(milliseconds: 100));
      final boundary = _cardKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('Error capturing card: $e');
      return null;
    }
  }

  String _buildShareText() {
    final buffer = StringBuffer();
    buffer.writeln('\u{1F68C} Viaje: $_originName \u2192 $_destinationName');
    if (_formattedEventDate.isNotEmpty) {
      buffer.writeln('\u{1F4C5} $_formattedEventDate');
    }
    if (_stopsCount > 0 || _distanceKm > 0) {
      buffer.writeln(
          '\u{1F4CD} $_stopsCount paradas \u2022 ${_distanceKm.toStringAsFixed(1)} km');
    }
    if (_showPrice && _ticketPrice > 0) {
      buffer.writeln(
          '\u{1F3AB} \$${_ticketPrice.toStringAsFixed(0)} MXN por boleto');
    }
    buffer.writeln(
        '\u{1F465} $_availableSeats lugares disponibles');
    buffer.writeln('\u{1F3AB} Codigo: $_invitationCode');
    return buffer.toString().trim();
  }

  /// Share card as image + text (native share sheet on mobile, text on web).
  Future<void> _shareCardAsImage() async {
    HapticService.lightImpact();
    final bytes = kIsWeb ? null : await _captureCardImage();

    if (bytes != null) {
      try {
        final tempDir = await getTemporaryDirectory();
        final file = File(
            '${tempDir.path}/toro_viaje_${_invitationCode.replaceAll('-', '_')}.png');
        await file.writeAsBytes(bytes);
        await Share.shareXFiles(
          [XFile(file.path)],
          text: _buildShareText(),
        );
        return;
      } catch (_) {}
    }
    // Fallback: copy text
    Clipboard.setData(ClipboardData(text: _buildShareText()));
    _showSuccess('Texto copiado al portapapeles');
  }

  /// Copy the full card as an image to the device clipboard.
  Future<void> _copyCardAsImage() async {
    HapticService.lightImpact();

    // Step 1: Capture
    Uint8List? bytes;
    try {
      bytes = await _captureCardImage();
    } catch (e) {
      _showError('Error al capturar: $e');
      return;
    }

    if (bytes == null || bytes.isEmpty) {
      _showError('No se pudo capturar la tarjeta');
      return;
    }

    // Step 2: Write to clipboard (uses conditional import: web vs mobile)
    try {
      final ok = await writeImageToClipboard(bytes);
      if (ok) {
        _showSuccess('Imagen copiada — pégala donde quieras');
      } else {
        _showError('El navegador no soporta copiar imagenes');
      }
    } catch (e) {
      _showError('Error clipboard: $e');
    }
  }

  /// Copy formatted text to clipboard.
  void _copyShareText() {
    HapticService.lightImpact();
    Clipboard.setData(ClipboardData(text: _buildShareText()));
    _showSuccess('Texto copiado al portapapeles');
  }

  // ── Manual invitation ──

  Future<void> _addManualInvitation() async {
    final name = _nameController.text.trim();
    final contact = _contactController.text.trim();

    if (name.isEmpty) {
      _showError('Ingresa el nombre del pasajero');
      return;
    }

    if (contact.isEmpty) {
      _showError('Ingresa el email o telefono');
      return;
    }

    setState(() => _isAddingInvitation = true);
    HapticService.lightImpact();

    try {
      final isEmail = contact.contains('@');
      final inviteeData = {
        'invitee_name': name,
        if (isEmail) 'invitee_email': contact else 'invitee_phone': contact,
        'delivery_method': 'manual',
      };

      await _invitationService.createInvitation(widget.eventId, inviteeData);

      if (mounted) {
        _nameController.clear();
        _contactController.clear();
        HapticService.success();
        _showSuccess('Pasajero agregado');
        await _loadData();
      }
    } catch (e) {
      HapticService.error();
      _showError('Error al agregar pasajero: $e');
    } finally {
      if (mounted) {
        setState(() => _isAddingInvitation = false);
      }
    }
  }

  // ── Delete / Resend / Cancel ──

  Future<void> _deleteInvitation(String invitationId) async {
    HapticService.warning();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Eliminar Pasajero',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          'Esta seguro de eliminar este pasajero?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _invitationService.deleteInvitation(invitationId);
      HapticService.success();
      _showSuccess('Pasajero eliminado');
      await _loadData();
    } catch (e) {
      HapticService.error();
      _showError('Error al eliminar: $e');
    }
  }

  Future<void> _resendInvitation(String invitationId) async {
    HapticService.lightImpact();

    try {
      await _invitationService.resendInvitation(invitationId);
      HapticService.success();
      _showSuccess('Invitacion reenviada');
      await _loadData();
    } catch (e) {
      HapticService.error();
      _showError('Error al reenviar: $e');
    }
  }

  Future<void> _cancelInvitation(String invitationId) async {
    HapticService.warning();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Cancelar Invitacion',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          'Esta seguro de cancelar esta invitacion? El pasajero ya no podra aceptar.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.warning),
            child: const Text('Si, Cancelar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _invitationService.cancelInvitation(invitationId);
      HapticService.success();
      _showSuccess('Invitacion cancelada');
      await _loadData();
    } catch (e) {
      HapticService.error();
      _showError('Error al cancelar: $e');
    }
  }

  // ── Edit Passenger ──

  Future<void> _editPassenger(
      String invitationId, Map<String, dynamic> current) async {
    final nameCtrl = TextEditingController(
        text: current['invitee_name'] ?? current['invited_name'] ?? '');
    final contactCtrl = TextEditingController(
        text: current['invitee_email'] ??
            current['invitee_phone'] ??
            current['invited_email'] ??
            current['invited_phone'] ??
            '');
    final seatCtrl =
        TextEditingController(text: current['seat_number'] ?? '');

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Editar Pasajero',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Nombre',
                labelStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.border)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: contactCtrl,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Email o Telefono',
                labelStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.border)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: seatCtrl,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Asiento (opcional)',
                labelStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.border)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              final updates = <String, dynamic>{};
              final name = nameCtrl.text.trim();
              final contact = contactCtrl.text.trim();
              final seat = seatCtrl.text.trim();
              if (name.isNotEmpty) updates['invitee_name'] = name;
              if (contact.isNotEmpty) {
                if (contact.contains('@')) {
                  updates['invitee_email'] = contact;
                } else {
                  updates['invitee_phone'] = contact;
                }
              }
              if (seat.isNotEmpty) {
                updates['seat_number'] = seat;
              }
              Navigator.pop(ctx, updates);
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    nameCtrl.dispose();
    contactCtrl.dispose();
    seatCtrl.dispose();

    if (result != null && result.isNotEmpty) {
      try {
        await _invitationService.updateInvitation(invitationId, result);
        HapticService.success();
        _showSuccess('Pasajero actualizado');
        await _loadData();
      } catch (e) {
        HapticService.error();
        _showError('Error al actualizar: $e');
      }
    }
  }

  void _showInvitationDetail(Map<String, dynamic> invitation) {
    HapticService.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _buildInvitationDetailModal(ctx, invitation),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
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
          'Invitar Pasajeros',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : Stack(
              children: [
                // ── Main content ──
                RefreshIndicator(
                  onRefresh: _loadData,
                  color: AppColors.primary,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. KPI Bar
                        _buildKpiBar(),
                        const SizedBox(height: 16),
                        // 2. Add Passengers
                        _buildAddPassengers(),
                        const SizedBox(height: 16),
                        // 3. Passengers list
                        _buildPassengersList(),
                        SizedBox(
                            height:
                                MediaQuery.of(context).padding.bottom + 16),
                      ],
                    ),
                  ),
                ),
                // ── Scrim (tap to close) ──
                AnimatedBuilder(
                  animation: _panelSlide,
                  builder: (context, _) {
                    if (_panelSlide.value == 0) {
                      return const SizedBox.shrink();
                    }
                    return GestureDetector(
                      onTap: _togglePanel,
                      child: Container(
                        color: Colors.black
                            .withValues(alpha: 0.5 * _panelSlide.value),
                      ),
                    );
                  },
                ),
                // ── Slide panel from right ──
                _buildSlidePanel(),
                // ── Ear tab (always visible) ──
                _buildEarTab(),
              ],
            ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  // ── KPI Bar ──

  Widget _buildKpiBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildStatItem(
            Icons.event_seat,
            'Disponibles',
            '$_availableSeats/$_totalSeats',
            _availableSeats > 0 ? AppColors.success : AppColors.error,
          ),
          Container(width: 1, height: 24, color: AppColors.border.withValues(alpha: 0.3)),
          _buildStatItem(
            Icons.check_circle,
            'Aceptados',
            '$_acceptedCount',
            AppColors.success,
          ),
          Container(width: 1, height: 24, color: AppColors.border.withValues(alpha: 0.3)),
          _buildStatItem(
            Icons.pending,
            'Pendientes',
            '${_stats['pending'] ?? 0}',
            AppColors.warning,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
      IconData icon, String label, String value, Color color) {
    final muted = color.withValues(alpha: 0.7);
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: muted),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                color: muted,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: TextStyle(
            color: AppColors.textTertiary.withValues(alpha: 0.6),
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  // ── Price toggle ──

  Widget _buildPriceToggle() {
    return GestureDetector(
      onTap: () => setState(() => _showPrice = !_showPrice),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(
            _showPrice ? Icons.visibility : Icons.visibility_off,
            size: 14,
            color: AppColors.textTertiary,
          ),
          const SizedBox(width: 4),
          Text(
            _showPrice ? 'Ocultar precio' : 'Mostrar precio',
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  // ── Ear Tab (always visible on right edge) ──

  Widget _buildEarTab() {
    return AnimatedBuilder(
      animation: _panelSlide,
      builder: (context, child) {
        final screenW = MediaQuery.of(context).size.width;
        final panelW = screenW * 0.85;
        // Tab slides with the panel
        final tabRight =
            panelW * _panelSlide.value - 0; // flush with panel edge
        return Positioned(
          right: tabRight,
          top: MediaQuery.of(context).size.height * 0.25,
          child: child!,
        );
      },
      child: GestureDetector(
        onTap: _togglePanel,
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null) {
            if (details.primaryVelocity! < -100 && !_panelOpen) {
              _togglePanel();
            } else if (details.primaryVelocity! > 100 && _panelOpen) {
              _togglePanel();
            }
          }
        },
        child: Container(
          width: 40,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(12),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(-3, 0),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _panelOpen ? Icons.chevron_right : Icons.qr_code_2,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(height: 6),
              const RotatedBox(
                quarterTurns: 1,
                child: Text(
                  'QR',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Slide Panel ──

  Widget _buildSlidePanel() {
    return AnimatedBuilder(
      animation: _panelSlide,
      builder: (context, child) {
        final screenW = MediaQuery.of(context).size.width;
        final panelW = screenW * 0.85;
        return Positioned(
          right: -panelW + (panelW * _panelSlide.value),
          top: 0,
          bottom: 0,
          width: panelW,
          child: child!,
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.97),
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 24,
              offset: const Offset(-4, 0),
            ),
          ],
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              children: [
                // Panel header
                Row(
                  children: [
                    const Icon(Icons.qr_code_2,
                        color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Tarjeta de Invitacion',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _togglePanel,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.close,
                            color: AppColors.textTertiary, size: 18),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Travel Card (inside RepaintBoundary for capture)
                RepaintBoundary(
                  key: _cardKey,
                  child: TravelCardWidget(
                    eventName: _eventName,
                    originName: _originName,
                    destinationName: _destinationName,
                    formattedDate: _formattedEventDate,
                    eventStatus: _eventStatus,
                    stopsCount: _stopsCount,
                    availableSeats: _availableSeats,
                    totalSeats: _totalSeats,
                    invitationCode: _invitationCode,
                    ticketPrice: _ticketPrice,
                    showPrice: _showPrice,
                    personName: _personName,
                    personRole: _personRole,
                    personCompany: _personCompany,
                    personAvatarUrl: _personAvatarUrl,
                    personLogoUrl: _personLogoUrl,
                    personPhone: _personPhone,
                    personEmail: _personEmail,
                    personWebsite: _personWebsite,
                    personDescription: _personDescription,
                  ),
                ),
                const SizedBox(height: 10),
                // Price toggle
                _buildPriceToggle(),
                const SizedBox(height: 10),
                // Share actions
                _buildShareActions(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Share Actions ──

  Widget _buildShareActions() {
    return Row(
      children: [
        Expanded(
          child: _buildActionButton(
            icon: Icons.share,
            label: 'Compartir',
            onTap: _shareCardAsImage,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildActionButton(
            icon: Icons.copy,
            label: 'Copiar Imagen',
            onTap: _copyCardAsImage,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildActionButton(
            icon: Icons.text_snippet_outlined,
            label: 'Copiar Texto',
            onTap: _copyShareText,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.25), width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: AppColors.textSecondary),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Add Passengers ──

  Widget _buildAddPassengers() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.person_add, color: AppColors.primary, size: 18),
              SizedBox(width: 8),
              Text(
                'Agregar Pasajeros',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildCompactInput(
                  controller: _nameController,
                  hint: 'Nombre',
                  icon: Icons.person_outline,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCompactInput(
                  controller: _contactController,
                  hint: 'Email o Tel.',
                  icon: Icons.contact_mail_outlined,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 42,
                child: ElevatedButton(
                  onPressed:
                      _isAddingInvitation ? null : _addManualInvitation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        AppColors.primary.withValues(alpha: 0.5),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _isAddingInvitation
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.add, size: 20),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactInput({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
              const TextStyle(color: AppColors.textTertiary, fontSize: 12),
          prefixIcon: Icon(icon, size: 16, color: AppColors.textTertiary),
          prefixIconConstraints: const BoxConstraints(minWidth: 36),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  // ── Passengers List ──

  Widget _buildPassengersList() {
    final total = _invitations.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Pasajeros ($total)',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (total > 0)
              TextButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh, size: 14),
                label:
                    const Text('Actualizar', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_invitations.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                'Sin pasajeros aun',
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 13,
                ),
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _invitations.length,
              separatorBuilder: (_, _) =>
                  const Divider(color: AppColors.border, height: 1),
              itemBuilder: (context, index) {
                return _buildInvitationTile(_invitations[index]);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildInvitationTile(Map<String, dynamic> invitation) {
    final name = invitation['invitee_name'] ??
        invitation['invited_name'] ??
        'Invitado';
    final email = invitation['invitee_email'] ??
        invitation['invited_email'] as String?;
    final phone = invitation['invitee_phone'] ??
        invitation['invited_phone'] as String?;
    final status = invitation['status'] as String? ?? 'pending';
    final method = invitation['delivery_method'] ??
        invitation['invitation_method'] as String? ??
        'manual';
    final createdAt = invitation['created_at'] as String?;
    final acceptedAt = invitation['accepted_at'] as String?;
    final hasProfile = invitation['has_profile'] == true;
    final avatarUrl = invitation['avatar_url'] as String?;
    final invitationCode = invitation['invitation_code'] as String?;

    IconData methodIcon;
    switch (method) {
      case 'email':
        methodIcon = Icons.email_outlined;
        break;
      case 'sms':
        methodIcon = Icons.sms_outlined;
        break;
      case 'qr':
        methodIcon = Icons.qr_code_2;
        break;
      case 'link':
        methodIcon = Icons.link;
        break;
      case 'whatsapp':
        methodIcon = Icons.message;
        break;
      case 'direct':
        methodIcon = Icons.person;
        break;
      default:
        methodIcon = Icons.person_add_outlined;
    }

    String subtitle = email ?? phone ?? 'Sin contacto';
    if (createdAt != null) {
      subtitle += ' \u2022 ${_formatShortDate(createdAt)}';
    }

    return ListTile(
      onTap: () => _showInvitationDetail(invitation),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      leading: hasProfile && avatarUrl != null
          ? CircleAvatar(
              radius: 20,
              backgroundImage: NetworkImage(avatarUrl),
              backgroundColor:
                  AppColors.primary.withValues(alpha: 0.12),
            )
          : Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _getStatusColor(status).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(methodIcon,
                  color: _getStatusColor(status), size: 20),
            ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasProfile)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.verified_user,
                  size: 12, color: AppColors.success),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 13,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (acceptedAt != null && status == 'accepted')
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Acepto: ${_formatShortDate(acceptedAt)}',
                style: const TextStyle(
                  color: AppColors.success,
                  fontSize: 12,
                ),
              ),
            ),
          if (invitationCode != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                invitationCode,
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
      trailing: _buildStatusBadge(status),
      isThreeLine: true,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATUS HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Color _getStatusColor(String status) {
    switch (status) {
      case 'accepted':
        return AppColors.success;
      case 'declined':
      case 'expired':
        return AppColors.error;
      case 'checked_in':
        return AppColors.primary;
      default:
        return AppColors.warning;
    }
  }

  Widget _buildStatusBadge(String status) {
    Color bgColor;
    Color textColor;
    IconData icon;
    String label;

    switch (status) {
      case 'accepted':
        bgColor = AppColors.success.withValues(alpha: 0.15);
        textColor = AppColors.success;
        icon = Icons.check_circle;
        label = 'Acepto';
        break;
      case 'declined':
        bgColor = AppColors.error.withValues(alpha: 0.15);
        textColor = AppColors.error;
        icon = Icons.cancel;
        label = 'Rechazo';
        break;
      case 'expired':
        bgColor = AppColors.textTertiary.withValues(alpha: 0.15);
        textColor = AppColors.textTertiary;
        icon = Icons.timer_off;
        label = 'Cancelado';
        break;
      case 'checked_in':
        bgColor = AppColors.primary.withValues(alpha: 0.15);
        textColor = AppColors.primary;
        icon = Icons.how_to_reg;
        label = 'Check-in';
        break;
      case 'no_show':
        bgColor = AppColors.error.withValues(alpha: 0.15);
        textColor = AppColors.error;
        icon = Icons.person_off;
        label = 'No show';
        break;
      default:
        bgColor = AppColors.warning.withValues(alpha: 0.15);
        textColor = AppColors.warning;
        icon = Icons.schedule;
        label = 'Pendiente';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DATE FORMATTING
  // ═══════════════════════════════════════════════════════════════════════════

  String _formatShortDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inMinutes < 1) {
        return 'Ahora';
      } else if (diff.inMinutes < 60) {
        return 'Hace ${diff.inMinutes} min';
      } else if (diff.inHours < 24) {
        return 'Hace ${diff.inHours}h';
      } else if (diff.inDays == 1) {
        return 'Ayer';
      } else if (diff.inDays < 7) {
        return 'Hace ${diff.inDays}d';
      } else {
        return '${date.day}/${date.month}';
      }
    } catch (e) {
      return '';
    }
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      const months = [
        'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
        'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
      ];
      return '${date.day} ${months[date.month - 1]} ${date.year}, ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return isoDate;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INVITATION DETAIL MODAL (with Edit)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildInvitationDetailModal(
      BuildContext ctx, Map<String, dynamic> invitation) {
    final name = invitation['invitee_name'] ??
        invitation['invited_name'] ??
        'Invitado';
    final email = invitation['invitee_email'] ??
        invitation['invited_email'] as String?;
    final phone = invitation['invitee_phone'] ??
        invitation['invited_phone'] as String?;
    final status = invitation['status'] as String? ?? 'pending';
    final method = invitation['delivery_method'] ??
        invitation['invitation_method'] as String? ??
        'manual';
    final createdAt = invitation['created_at'] as String?;
    final acceptedAt = invitation['accepted_at'] as String?;
    final declinedAt = invitation['declined_at'] as String?;
    final lastCheckInAt = invitation['last_check_in_at'] as String?;
    final invitationId = invitation['id'] as String;
    final invitationCode = invitation['invitation_code'] as String?;
    final hasProfile = invitation['has_profile'] == true;
    final avatarUrl = invitation['avatar_url'] as String?;
    final seatNumber = invitation['seat_number'] as String?;
    final specialNeeds = invitation['special_needs'] as String?;
    final emergencyContact = invitation['emergency_contact'] as String?;
    final emergencyPhone = invitation['emergency_phone'] as String?;

    String methodLabel;
    IconData methodIcon;
    switch (method) {
      case 'email':
        methodLabel = 'Email';
        methodIcon = Icons.email_outlined;
        break;
      case 'sms':
        methodLabel = 'SMS';
        methodIcon = Icons.sms_outlined;
        break;
      case 'qr':
        methodLabel = 'QR Code';
        methodIcon = Icons.qr_code_2;
        break;
      case 'link':
        methodLabel = 'Link';
        methodIcon = Icons.link;
        break;
      case 'whatsapp':
        methodLabel = 'WhatsApp';
        methodIcon = Icons.message;
        break;
      case 'direct':
        methodLabel = 'Directo';
        methodIcon = Icons.person;
        break;
      default:
        methodLabel = 'Manual';
        methodIcon = Icons.person_add_outlined;
    }

    final canResend =
        status == 'pending' || status == 'expired' || status == 'declined';
    final canCancel = status == 'pending';

    return Container(
      padding: const EdgeInsets.all(24),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(ctx).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
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
            // Header with avatar
            Row(
              children: [
                hasProfile && avatarUrl != null
                    ? CircleAvatar(
                        radius: 28,
                        backgroundImage: NetworkImage(avatarUrl),
                        backgroundColor:
                            _getStatusColor(status).withValues(alpha: 0.15),
                      )
                    : Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color:
                              _getStatusColor(status).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(methodIcon,
                            color: _getStatusColor(status), size: 26),
                      ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (hasProfile)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.success.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.verified_user,
                                      size: 12, color: AppColors.success),
                                  SizedBox(width: 4),
                                  Text(
                                    'Usuario',
                                    style: TextStyle(
                                        color: AppColors.success,
                                        fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _buildStatusBadge(status),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(color: AppColors.border),
            const SizedBox(height: 16),

            // Contact info
            _sectionTitle('Informacion de Contacto'),
            const SizedBox(height: 8),
            if (email != null) _detailRow('Email', email),
            if (phone != null) _detailRow('Telefono', phone),
            if (invitationCode != null) _detailRow('Codigo', invitationCode),
            _detailRow('Metodo', methodLabel),
            if (seatNumber != null) _detailRow('Asiento', seatNumber),

            // Timeline
            const SizedBox(height: 16),
            _sectionTitle('Cronologia'),
            const SizedBox(height: 8),
            if (createdAt != null)
              _detailRow('Invitado', _formatDate(createdAt)),
            if (acceptedAt != null)
              _detailRowColored(
                  'Acepto', _formatDate(acceptedAt), AppColors.success),
            if (declinedAt != null)
              _detailRowColored(
                  'Rechazo', _formatDate(declinedAt), AppColors.error),
            if (lastCheckInAt != null)
              _detailRowColored(
                  'Check-in', _formatDate(lastCheckInAt), AppColors.primary),

            // Special info
            if (specialNeeds != null || emergencyContact != null) ...[
              const SizedBox(height: 16),
              _sectionTitle('Informacion Adicional'),
              const SizedBox(height: 8),
              if (specialNeeds != null)
                _detailRow('Necesidades', specialNeeds),
              if (emergencyContact != null)
                _detailRow('Emergencia', emergencyContact),
              if (emergencyPhone != null)
                _detailRow('Tel. Emerg.', emergencyPhone),
            ],

            const SizedBox(height: 24),

            // Action buttons
            // Edit button
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _editPassenger(invitationId, invitation);
                  },
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Editar Pasajero'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),

            if (canResend)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _resendInvitation(invitationId);
                    },
                    icon: const Icon(Icons.send, size: 18),
                    label: const Text('Reenviar Invitacion'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _deleteInvitation(invitationId);
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Eliminar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                if (canCancel) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _cancelInvitation(invitationId);
                      },
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      label: const Text('Cancelar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.warning,
                        side: const BorderSide(color: AppColors.warning),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Cerrar'),
                  ),
                ),
              ],
            ),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 13,
              ),
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

  Widget _detailRowColored(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 85,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Icon(Icons.circle, size: 8, color: color),
                const SizedBox(width: 6),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
