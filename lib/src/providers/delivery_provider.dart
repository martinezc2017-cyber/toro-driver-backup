import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/delivery_service.dart';
import '../models/package_delivery_model.dart';

class DeliveryProvider with ChangeNotifier {
  final DeliveryService _deliveryService = DeliveryService();

  List<DriverTicketModel> _availableTickets = [];
  PackageDeliveryModel? _activeDelivery;
  List<PackageDeliveryModel> _deliveryHistory = [];
  TaxSummary? _taxSummary;
  bool _isLoading = false;
  String? _error;

  StreamSubscription? _ticketsSubscription;
  StreamSubscription? _deliverySubscription;

  List<DriverTicketModel> get availableTickets => _availableTickets;
  PackageDeliveryModel? get activeDelivery => _activeDelivery;
  List<PackageDeliveryModel> get deliveryHistory => _deliveryHistory;
  TaxSummary? get taxSummary => _taxSummary;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasActiveDelivery => _activeDelivery != null;

  // Initialize provider
  Future<void> initialize(String driverId, {double? lat, double? lng}) async {
    _isLoading = true;
    notifyListeners();

    try {
      await Future.wait([
        _loadActiveDelivery(driverId),
        _loadAvailableTickets(lat: lat, lng: lng),
        _loadTaxSummary(driverId, DateTime.now().year),
      ]);
      _error = null;
    } catch (e) {
      _error = 'Error al inicializar: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  // Load active delivery
  Future<void> _loadActiveDelivery(String driverId) async {
    _activeDelivery = await _deliveryService.getActiveDelivery(driverId);
    if (_activeDelivery != null) {
      _startDeliveryStream(_activeDelivery!.id);
    }
  }

  // Load available tickets
  Future<void> _loadAvailableTickets({double? lat, double? lng}) async {
    if (lat != null && lng != null) {
      _availableTickets = await _deliveryService.getAvailableTickets(
        latitude: lat,
        longitude: lng,
      );
    }
  }

  // Load tax summary
  Future<void> _loadTaxSummary(String driverId, int year) async {
    _taxSummary = await _deliveryService.getTaxSummary(driverId, year);
  }

  // Start streaming available tickets
  void startTicketsStream() {
    _ticketsSubscription?.cancel();
    _ticketsSubscription = _deliveryService.streamAvailableTickets().listen(
      (tickets) {
        _availableTickets = tickets;
        notifyListeners();
      },
      onError: (e) {
        _error = 'Error en stream de tickets: $e';
        notifyListeners();
      },
    );
  }

  // Start streaming delivery updates
  void _startDeliveryStream(String deliveryId) {
    _deliverySubscription?.cancel();
    _deliverySubscription = _deliveryService.streamDelivery(deliveryId).listen(
      (delivery) {
        _activeDelivery = delivery;
        notifyListeners();
      },
      onError: (e) {
        _error = 'Error en stream de entrega: $e';
        notifyListeners();
      },
    );
  }

  // Refresh available tickets
  Future<void> refreshAvailableTickets({double? lat, double? lng}) async {
    try {
      if (lat != null && lng != null) {
        _availableTickets = await _deliveryService.getAvailableTickets(
          latitude: lat,
          longitude: lng,
        );
        notifyListeners();
      }
    } catch (e) {
      _error = 'Error al refrescar tickets: $e';
      notifyListeners();
    }
  }

  // Accept a ticket
  Future<bool> acceptTicket(String ticketId, String driverId) async {
    try {
      _isLoading = true;
      notifyListeners();

      final ticket = await _deliveryService.acceptTicket(ticketId, driverId);

      // Load the full delivery
      final delivery = await _deliveryService.getDelivery(ticket.deliveryId);
      _activeDelivery = delivery;

      // Remove from available list
      _availableTickets.removeWhere((t) => t.id == ticketId);

      // Start streaming updates
      if (delivery != null) {
        _startDeliveryStream(delivery.id);
      }

      _isLoading = false;
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al aceptar ticket: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Update delivery status: Start en route
  Future<bool> startEnRoute() async {
    if (_activeDelivery == null) return false;

    try {
      _isLoading = true;
      notifyListeners();

      _activeDelivery = await _deliveryService.startEnRoute(_activeDelivery!.id);

      _isLoading = false;
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al iniciar ruta: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Update delivery status: Pickup package
  Future<bool> pickupPackage() async {
    if (_activeDelivery == null) return false;

    try {
      _isLoading = true;
      notifyListeners();

      _activeDelivery = await _deliveryService.pickupPackage(_activeDelivery!.id);

      _isLoading = false;
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al recoger paquete: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Update delivery status: Start transit
  Future<bool> startTransit() async {
    if (_activeDelivery == null) return false;

    try {
      _isLoading = true;
      notifyListeners();

      _activeDelivery = await _deliveryService.startTransit(_activeDelivery!.id);

      _isLoading = false;
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al iniciar tránsito: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Complete delivery
  Future<bool> completeDelivery(String driverId) async {
    if (_activeDelivery == null) return false;

    try {
      _isLoading = true;
      notifyListeners();

      final completedDelivery = await _deliveryService.completeDelivery(
        _activeDelivery!.id,
        driverId,
      );

      // Add to history
      _deliveryHistory.insert(0, completedDelivery);

      // Clear active delivery
      _activeDelivery = null;
      _deliverySubscription?.cancel();

      // Refresh tax summary
      await _loadTaxSummary(driverId, DateTime.now().year);

      _isLoading = false;
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al completar entrega: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Cancel delivery
  Future<bool> cancelDelivery(String reason) async {
    if (_activeDelivery == null) return false;

    try {
      _isLoading = true;
      notifyListeners();

      final cancelledDelivery = await _deliveryService.cancelDelivery(
        _activeDelivery!.id,
        reason,
      );

      // Add to history
      _deliveryHistory.insert(0, cancelledDelivery);

      // Clear active delivery
      _activeDelivery = null;
      _deliverySubscription?.cancel();

      _isLoading = false;
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al cancelar entrega: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Update driver location
  Future<void> updateLocation(String driverId, double lat, double lng) async {
    try {
      await _deliveryService.updateDriverLocation(driverId, lat, lng);
    } catch (e) {
      _error = 'Error al actualizar ubicación: $e';
      notifyListeners();
    }
  }

  // Load delivery history
  Future<void> loadDeliveryHistory(String driverId, {int limit = 50, int offset = 0}) async {
    try {
      _isLoading = true;
      notifyListeners();

      final newHistory = await _deliveryService.getDeliveryHistory(
        driverId,
        limit: limit,
        offset: offset,
      );

      if (offset == 0) {
        _deliveryHistory = newHistory;
      } else {
        _deliveryHistory.addAll(newHistory);
      }

      _isLoading = false;
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = 'Error al cargar historial: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  // Get today's stats
  Future<Map<String, dynamic>> getTodayStats(String driverId) async {
    try {
      final count = await _deliveryService.getTodayDeliveriesCount(driverId);
      final earnings = await _deliveryService.getTodayDeliveryEarnings(driverId);
      return {
        'count': count,
        'earnings': earnings,
      };
    } catch (e) {
      return {
        'count': 0,
        'earnings': 0.0,
      };
    }
  }

  // Send message
  Future<void> sendMessage({
    required String deliveryId,
    required String senderId,
    required String message,
  }) async {
    try {
      await _deliveryService.sendMessage(
        deliveryId: deliveryId,
        senderId: senderId,
        message: message,
        isDriver: true,
      );
    } catch (e) {
      _error = 'Error al enviar mensaje: $e';
      notifyListeners();
    }
  }

  // Get messages for current delivery
  Future<List<Map<String, dynamic>>> getMessages() async {
    if (_activeDelivery == null) return [];
    return await _deliveryService.getMessages(_activeDelivery!.id);
  }

  // Stream messages for current delivery
  Stream<List<Map<String, dynamic>>>? streamMessages() {
    if (_activeDelivery == null) return null;
    return _deliveryService.streamMessages(_activeDelivery!.id);
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticketsSubscription?.cancel();
    _deliverySubscription?.cancel();
    super.dispose();
  }
}
