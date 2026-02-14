import 'dart:async';
import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import '../services/cash_account_service.dart';

enum CashAccountStatus { idle, loading, loaded, error }

class CashAccountProvider with ChangeNotifier {
  final CashAccountService _service = CashAccountService();

  CashAccountStatus _status = CashAccountStatus.idle;
  Map<String, dynamic>? _cashAccount;
  List<Map<String, dynamic>> _ledgerEntries = [];
  List<Map<String, dynamic>> _weeklyStatements = [];
  List<Map<String, dynamic>> _deposits = [];
  Map<String, dynamic> _ledgerSummary = {};
  String? _error;
  String? _driverId;
  StreamSubscription? _accountSubscription;

  CashAccountStatus get status => _status;
  Map<String, dynamic>? get cashAccount => _cashAccount;
  List<Map<String, dynamic>> get ledgerEntries => _ledgerEntries;
  List<Map<String, dynamic>> get weeklyStatements => _weeklyStatements;
  List<Map<String, dynamic>> get deposits => _deposits;
  Map<String, dynamic> get ledgerSummary => _ledgerSummary;
  String? get error => _error;

  // Convenience getters
  double get cashOwed =>
      (_cashAccount?['current_balance'] as num?)?.toDouble() ?? 0;

  String get accountStatus =>
      _cashAccount?['status'] as String? ?? 'active';

  bool get isSuspended => accountStatus == 'suspended';
  bool get isBlocked => accountStatus == 'blocked';
  bool get isActive => accountStatus == 'active';

  double get autoSuspendThreshold =>
      (_cashAccount?['auto_suspend_threshold'] as num?)?.toDouble() ?? 500;

  int get totalCashRides =>
      (_cashAccount?['total_cash_rides_completed'] as num?)?.toInt() ?? 0;

  // Breakdown by source type
  Map<String, double> get owedByType =>
      Map<String, double>.from(_ledgerSummary['by_source_type'] ?? {});

  /// Initialize provider for a driver
  Future<void> initialize(String driverId) async {
    _driverId = driverId;
    _status = CashAccountStatus.loading;
    notifyListeners();

    try {
      // Load all data in parallel
      final results = await Future.wait([
        _service.getCashAccount(driverId),
        _service.getLedgerSummary(driverId),
        _service.getCashLedger(driverId, limit: 30),
        _service.getWeeklyStatements(driverId, limit: 5),
        _service.getDepositHistory(driverId, limit: 10),
      ]);

      _cashAccount = results[0] as Map<String, dynamic>?;
      _ledgerSummary = results[1] as Map<String, dynamic>;
      _ledgerEntries = results[2] as List<Map<String, dynamic>>;
      _weeklyStatements = results[3] as List<Map<String, dynamic>>;
      _deposits = results[4] as List<Map<String, dynamic>>;

      _status = CashAccountStatus.loaded;
      _error = null;

      // Subscribe to real-time updates
      _subscribeToAccount(driverId);
    } catch (e) {
      debugPrint('Error initializing cash account: $e');
      _status = CashAccountStatus.error;
      _error = e.toString();
    }

    notifyListeners();
  }

  void _subscribeToAccount(String driverId) {
    _accountSubscription?.cancel();
    _accountSubscription = _service.streamCashAccount(driverId).listen(
      (data) {
        if (data.isNotEmpty) {
          _cashAccount = data;
          notifyListeners();
        }
      },
      onError: (e) => debugPrint('Cash account stream error: $e'),
    );
  }

  /// Refresh all data
  Future<void> refresh() async {
    if (_driverId == null) return;
    await initialize(_driverId!);
  }

  /// Refresh just the ledger
  Future<void> refreshLedger() async {
    if (_driverId == null) return;
    _ledgerEntries = await _service.getCashLedger(_driverId!, limit: 30);
    _ledgerSummary = await _service.getLedgerSummary(_driverId!);
    notifyListeners();
  }

  /// Submit a deposit
  Future<bool> submitDeposit({
    required double amount,
    required String paymentMethod,
    String? referenceNumber,
    String? proofUrl,
    String? statementId,
    String countryCode = 'MX',
  }) async {
    if (_driverId == null) return false;

    final result = await _service.submitDeposit(
      driverId: _driverId!,
      amount: amount,
      paymentMethod: paymentMethod,
      referenceNumber: referenceNumber,
      proofUrl: proofUrl,
      statementId: statementId,
      countryCode: countryCode,
    );

    if (result != null) {
      // Refresh deposits list
      _deposits = await _service.getDepositHistory(_driverId!, limit: 10);
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Request a week reset
  Future<bool> requestWeekReset({
    required double amountOwed,
    String? message,
    String? statementId,
  }) async {
    if (_driverId == null) return false;

    final result = await _service.requestWeekReset(
      driverId: _driverId!,
      amountOwed: amountOwed,
      message: message,
      statementId: statementId,
    );

    return result != null;
  }

  /// Upload proof image and return URL
  Future<String?> uploadProofImage(String filePath) async {
    if (_driverId == null) return null;
    return await _service.uploadProofImage(_driverId!, filePath);
  }

  @override
  void dispose() {
    _accountSubscription?.cancel();
    super.dispose();
  }
}
