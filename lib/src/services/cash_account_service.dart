import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class CashAccountService {
  final SupabaseClient _client = SupabaseConfig.client;

  // ========================================================================
  // CREDIT ACCOUNT
  // ========================================================================

  /// Get driver's cash credit account
  Future<Map<String, dynamic>?> getCashAccount(String driverId) async {
    try {
      final response = await _client
          .from('driver_credit_accounts')
          .select()
          .eq('driver_id', driverId)
          .maybeSingle();
      return response;
    } catch (e) {
      debugPrint('Error getting cash account: $e');
      return null;
    }
  }

  /// Stream driver's cash balance in real-time
  Stream<Map<String, dynamic>> streamCashAccount(String driverId) {
    return _client
        .from('driver_credit_accounts')
        .stream(primaryKey: ['id'])
        .eq('driver_id', driverId)
        .map((list) => list.isNotEmpty ? list.first : <String, dynamic>{});
  }

  // ========================================================================
  // CASH LEDGER
  // ========================================================================

  /// Get cash ledger entries for a driver (paginated, newest first)
  Future<List<Map<String, dynamic>>> getCashLedger(
    String driverId, {
    int limit = 50,
    int offset = 0,
    String? sourceType,
  }) async {
    try {
      var query = _client
          .from('cash_ledger_entries')
          .select()
          .eq('driver_id', driverId);

      if (sourceType != null) {
        query = query.eq('source_type', sourceType);
      }

      final response = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error getting cash ledger: $e');
      return [];
    }
  }

  /// Get ledger summary (total debits, total credits, by source type)
  Future<Map<String, dynamic>> getLedgerSummary(String driverId) async {
    try {
      final ledger = await _client
          .from('cash_ledger_entries')
          .select('direction, amount, source_type')
          .eq('driver_id', driverId);

      double totalDebits = 0;
      double totalCredits = 0;
      final byType = <String, double>{};

      for (final entry in ledger) {
        final amount = (entry['amount'] as num?)?.toDouble() ?? 0;
        final direction = entry['direction'] as String?;
        final sourceType = entry['source_type'] as String? ?? 'ride';

        if (direction == 'debit') {
          totalDebits += amount;
          byType[sourceType] = (byType[sourceType] ?? 0) + amount;
        } else {
          totalCredits += amount;
        }
      }

      return {
        'total_debits': totalDebits,
        'total_credits': totalCredits,
        'net_owed': totalDebits - totalCredits,
        'by_source_type': byType,
      };
    } catch (e) {
      debugPrint('Error getting ledger summary: $e');
      return {
        'total_debits': 0.0,
        'total_credits': 0.0,
        'net_owed': 0.0,
        'by_source_type': <String, double>{},
      };
    }
  }

  // ========================================================================
  // WEEKLY STATEMENTS
  // ========================================================================

  /// Get weekly statements for a driver
  Future<List<Map<String, dynamic>>> getWeeklyStatements(
    String driverId, {
    int limit = 10,
  }) async {
    try {
      final response = await _client
          .from('driver_weekly_statements')
          .select()
          .eq('driver_id', driverId)
          .order('week_start_date', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error getting weekly statements: $e');
      return [];
    }
  }

  /// Get current week's statement
  Future<Map<String, dynamic>?> getCurrentWeekStatement(String driverId) async {
    try {
      final now = DateTime.now();
      final weekday = now.weekday; // 1=Mon, 7=Sun
      final weekStart = now.subtract(Duration(days: weekday - 1));
      final weekStartStr =
          '${weekStart.year}-${weekStart.month.toString().padLeft(2, '0')}-${weekStart.day.toString().padLeft(2, '0')}';

      final response = await _client
          .from('driver_weekly_statements')
          .select()
          .eq('driver_id', driverId)
          .eq('week_start_date', weekStartStr)
          .maybeSingle();

      return response;
    } catch (e) {
      debugPrint('Error getting current week statement: $e');
      return null;
    }
  }

  // ========================================================================
  // DEPOSITS
  // ========================================================================

  /// Submit a deposit with proof of payment
  Future<Map<String, dynamic>?> submitDeposit({
    required String driverId,
    required double amount,
    required String paymentMethod,
    String? referenceNumber,
    String? proofUrl,
    String? statementId,
    String countryCode = 'MX',
  }) async {
    try {
      final response = await _client.from('driver_deposits').insert({
        'driver_id': driverId,
        'amount': amount,
        'payment_method': paymentMethod,
        'reference_number': referenceNumber,
        'proof_url': proofUrl,
        'statement_id': statementId,
        'country_code': countryCode,
      }).select().single();

      return response;
    } catch (e) {
      debugPrint('Error submitting deposit: $e');
      return null;
    }
  }

  /// Upload deposit proof image
  Future<String?> uploadProofImage(String driverId, String filePath) async {
    try {
      final fileName =
          'deposit_${driverId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final storagePath = 'deposits/$driverId/$fileName';

      await _client.storage.from('documents').upload(
            storagePath,
            File(filePath),
          );

      final publicUrl =
          _client.storage.from('documents').getPublicUrl(storagePath);
      return publicUrl;
    } catch (e) {
      debugPrint('Error uploading proof image: $e');
      return null;
    }
  }

  /// Get deposit history for a driver
  Future<List<Map<String, dynamic>>> getDepositHistory(
    String driverId, {
    int limit = 20,
  }) async {
    try {
      final response = await _client
          .from('driver_deposits')
          .select()
          .eq('driver_id', driverId)
          .order('created_at', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error getting deposit history: $e');
      return [];
    }
  }

  /// Get pending deposits count
  Future<int> getPendingDepositsCount(String driverId) async {
    try {
      final response = await _client
          .from('driver_deposits')
          .select('id')
          .eq('driver_id', driverId)
          .eq('status', 'pending');

      return (response as List).length;
    } catch (e) {
      debugPrint('Error getting pending deposits: $e');
      return 0;
    }
  }

  // ========================================================================
  // WEEK RESET REQUEST
  // ========================================================================

  /// Submit a week reset request (driver asks admin to clear their week)
  Future<Map<String, dynamic>?> requestWeekReset({
    required String driverId,
    required double amountOwed,
    String? message,
    String? statementId,
  }) async {
    try {
      final response = await _client.from('week_reset_requests').insert({
        'requester_id': driverId,
        'requester_type': 'driver',
        'driver_id': driverId,
        'driver_statement_id': statementId,
        'amount_owed': amountOwed,
        'message': message,
      }).select().single();

      return response;
    } catch (e) {
      debugPrint('Error requesting week reset: $e');
      return null;
    }
  }

  /// Get driver's reset requests
  Future<List<Map<String, dynamic>>> getResetRequests(String driverId) async {
    try {
      final response = await _client
          .from('week_reset_requests')
          .select()
          .eq('requester_id', driverId)
          .eq('requester_type', 'driver')
          .order('created_at', ascending: false)
          .limit(10);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error getting reset requests: $e');
      return [];
    }
  }
}
