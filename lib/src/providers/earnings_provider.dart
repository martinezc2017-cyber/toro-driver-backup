import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/payment_service.dart';
import '../models/earning_model.dart';

class EarningsProvider with ChangeNotifier {
  final PaymentService _paymentService = PaymentService();

  // REALTIME: refresca las ganancias en cuanto un viaje del chofer se completa,
  // en vez del poll lento que tardaba ~10 min en reflejar el dinero en el home.
  RealtimeChannel? _channel;
  String? _subscribedDriverId;

  EarningsSummary? _summary;
  List<EarningModel> _transactions = [];
  List<DailyEarning> _weeklyBreakdown = [];
  List<Map<String, dynamic>> _bankAccounts = [];
  StripeConnectStatus _stripeStatus = StripeConnectStatus.notConnected;
  bool _isLoading = false;
  String? _error;

  EarningsSummary? get summary => _summary;
  List<EarningModel> get transactions => _transactions;
  List<DailyEarning> get weeklyBreakdown => _weeklyBreakdown;
  List<Map<String, dynamic>> get bankAccounts => _bankAccounts;
  StripeConnectStatus get stripeStatus => _stripeStatus;
  bool get isLoading => _isLoading;
  String? get error => _error;

  double get todayEarnings => _summary?.todayEarnings ?? 0;
  double get weekEarnings => _summary?.weekEarnings ?? 0;
  double get weeklyEarnings => weekEarnings; // Alias for consistency
  double get monthEarnings => _summary?.monthEarnings ?? 0;
  double get availableBalance => _summary?.availableForPayout ?? 0;
  double get pendingPayout => _summary?.pendingPayout ?? 0;

  // Initialize provider
  Future<void> initialize(String driverId) async {
    _isLoading = true;
    notifyListeners();

    try {
      await Future.wait([
        _loadSummary(driverId),
        _loadWeeklyBreakdown(driverId),
        _loadStripeStatus(driverId),
      ]);
      _error = null;
    } catch (e) {
      _error = 'Error al cargar datos: $e';
    }

    _isLoading = false;
    notifyListeners();
    _subscribeRealtime(driverId);
  }

  /// Suscripción realtime: cuando un viaje de ESTE chofer pasa a completed/
  /// delivered, recarga las ganancias al instante (home "Hoy", semana, etc.).
  void _subscribeRealtime(String driverId) {
    if (_subscribedDriverId == driverId && _channel != null) return;
    _channel?.unsubscribe();
    _subscribedDriverId = driverId;
    void reload() {
      _loadSummary(driverId).then((_) {
        _loadWeeklyBreakdown(driverId).then((_) => notifyListeners());
      });
    }

    _channel = Supabase.instance.client
        .channel('earnings_$driverId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'driver_earnings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'driver_id',
            value: driverId,
          ),
          callback: (_) => reload(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'driver_payouts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'driver_id',
            value: driverId,
          ),
          callback: (_) => reload(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'drivers',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: driverId,
          ),
          callback: (_) => reload(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'deliveries',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'driver_id',
            value: driverId,
          ),
          callback: (payload) {
            final status = payload.newRecord['status']?.toString();
            // 'cancelled' incluido: un no-show de pasajero cierra el viaje como
            // cancelado PERO acredita al chofer (driver_earnings) -> hay que
            // recargar "Hoy"/semana o se queda en el valor viejo (se veía $0).
            if (status == 'completed' || status == 'delivered' || status == 'cancelled') {
              reload();
            }
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  // Load earnings summary
  Future<void> _loadSummary(String driverId) async {
    _summary = await _paymentService.getEarningsSummary(driverId);
  }

  // Load weekly breakdown
  Future<void> _loadWeeklyBreakdown(String driverId) async {
    _weeklyBreakdown = await _paymentService.getWeeklyBreakdown(driverId);
  }

  // Load Stripe connect status
  Future<void> _loadStripeStatus(String driverId) async {
    _stripeStatus = await _paymentService.getStripeConnectStatus(driverId);
  }

  // Refresh earnings data
  Future<void> refresh(String driverId) async {
    await initialize(driverId);
  }

  // Load transaction history
  Future<void> loadTransactions(String driverId, {int limit = 50, int offset = 0}) async {
    try {
      _isLoading = true;
      notifyListeners();

      final newTransactions = await _paymentService.getEarningsHistory(
        driverId,
        limit: limit,
        offset: offset,
      );

      if (offset == 0) {
        _transactions = newTransactions;
      } else {
        _transactions.addAll(newTransactions);
      }

      _error = null;
    } catch (e) {
      _error = 'Error al cargar transacciones: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  // Load bank accounts
  Future<void> loadBankAccounts(String driverId) async {
    try {
      _bankAccounts = await _paymentService.getBankAccounts(driverId);
      notifyListeners();
    } catch (e) {
      _error = 'Error al cargar cuentas: $e';
      notifyListeners();
    }
  }

  // Request payout
  Future<bool> requestPayout({
    required String driverId,
    required double amount,
    required String bankAccountId,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      await _paymentService.requestPayout(
        driverId: driverId,
        amount: amount,
        bankAccountId: bankAccountId,
      );

      // Refresh summary after payout
      await _loadSummary(driverId);

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al solicitar retiro: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Add bank account
  Future<bool> addBankAccount({
    required String driverId,
    required String accountNumber,
    required String routingNumber,
    required String accountHolderName,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      await _paymentService.addBankAccount(
        driverId: driverId,
        accountNumber: accountNumber,
        routingNumber: routingNumber,
        accountHolderName: accountHolderName,
      );

      await loadBankAccounts(driverId);

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al agregar cuenta: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Delete bank account
  Future<bool> deleteBankAccount(String accountId, String driverId) async {
    try {
      await _paymentService.deleteBankAccount(accountId);
      await loadBankAccounts(driverId);
      return true;
    } catch (e) {
      _error = 'Error al eliminar cuenta: $e';
      notifyListeners();
      return false;
    }
  }

  // Set default bank account
  Future<bool> setDefaultBankAccount(String accountId, String driverId) async {
    try {
      await _paymentService.setDefaultBankAccount(driverId, accountId);
      await loadBankAccounts(driverId);
      return true;
    } catch (e) {
      _error = 'Error al establecer cuenta predeterminada: $e';
      notifyListeners();
      return false;
    }
  }

  // Get Stripe onboarding link
  Future<String?> getStripeOnboardingLink(String driverId) async {
    try {
      return await _paymentService.getStripeOnboardingLink(driverId);
    } catch (e) {
      _error = 'Error al obtener link de Stripe: $e';
      notifyListeners();
      return null;
    }
  }

  // Get earnings for date range
  Future<double> getEarningsForDateRange({
    required String driverId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      return await _paymentService.getEarningsByDateRange(
        driverId: driverId,
        startDate: startDate,
        endDate: endDate,
      );
    } catch (e) {
      _error = 'Error al calcular ganancias: $e';
      notifyListeners();
      return 0;
    }
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
