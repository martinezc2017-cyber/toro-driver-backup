import 'package:flutter/foundation.dart';
import '../services/payment_service.dart';
import '../models/earning_model.dart';

class EarningsProvider with ChangeNotifier {
  final PaymentService _paymentService = PaymentService();

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
  double get availableBalance => _summary?.totalBalance ?? 0;

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
