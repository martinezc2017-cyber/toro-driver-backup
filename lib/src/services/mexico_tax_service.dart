import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

/// Service for handling Mexican tax retentions (ISR and IVA)
class MexicoTaxService {
  final SupabaseClient _client = SupabaseConfig.client;

  /// Calculate tax retention for a transaction
  /// Returns the breakdown of ISR, IVA, and net amount
  Future<TaxRetentionResult> calculateRetention({
    required String driverId,
    required double grossAmount,
    String? rideId,
    String? deliveryId,
    String transactionType = 'ride',
  }) async {
    try {
      final response = await _client.functions.invoke(
        'calculate-tax-retention',
        body: {
          'driver_id': driverId,
          'gross_amount': grossAmount,
          'ride_id': rideId,
          'delivery_id': deliveryId,
          'transaction_type': transactionType,
        },
      );

      if (response.status != 200) {
        throw Exception('Error calculating retention: ${response.data}');
      }

      final data = response.data['data'];
      return TaxRetentionResult(
        grossAmount: (data['gross_amount'] as num).toDouble(),
        hasRfc: data['has_rfc'] as bool,
        isrRate: (data['isr_rate'] as num).toDouble(),
        isrAmount: (data['isr_amount'] as num).toDouble(),
        ivaRate: (data['iva_rate'] as num).toDouble(),
        ivaAmount: (data['iva_amount'] as num).toDouble(),
        ivaDriverOwes: (data['iva_driver_owes'] as num).toDouble(),
        netAmount: (data['net_amount'] as num).toDouble(),
        currency: data['currency'] as String,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Get tax summary for a period
  Future<TaxSummary?> getTaxSummary({
    required String driverId,
    required int year,
    int? month,
  }) async {
    try {
      final response = await _client.rpc(
        'get_driver_tax_summary',
        params: {
          'p_driver_id': driverId,
          'p_year': year,
          'p_month': month,
        },
      );

      if (response == null || (response as List).isEmpty) {
        return null;
      }

      final data = response[0];
      return TaxSummary(
        period: data['period'] as String,
        totalGross: (data['total_gross'] as num).toDouble(),
        totalIsr: (data['total_isr'] as num).toDouble(),
        totalIvaRetained: (data['total_iva_retained'] as num).toDouble(),
        totalIvaOwes: (data['total_iva_owes'] as num).toDouble(),
        totalNet: (data['total_net'] as num).toDouble(),
        transactionCount: data['transactions'] as int,
        hadRfc: data['had_rfc'] as bool,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Get monthly summaries for a year
  Future<List<TaxMonthlySummary>> getMonthlySummaries({
    required String driverId,
    required int year,
  }) async {
    try {
      final response = await _client
          .from('tax_monthly_summary')
          .select()
          .eq('driver_id', driverId)
          .eq('period_year', year)
          .order('period_month');

      return (response as List).map((data) {
        return TaxMonthlySummary(
          year: data['period_year'] as int,
          month: data['period_month'] as int,
          totalGross: (data['total_gross'] as num).toDouble(),
          totalIsrRetained: (data['total_isr_retained'] as num).toDouble(),
          totalIvaRetained: (data['total_iva_retained'] as num).toDouble(),
          totalIvaDriverOwes: (data['total_iva_driver_owes'] as num).toDouble(),
          totalNet: (data['total_net'] as num).toDouble(),
          transactionCount: data['transaction_count'] as int,
          hadRfc: data['had_rfc'] as bool,
          constanciaUrl: data['constancia_url'] as String?,
        );
      }).toList();
    } catch (e) {
      rethrow;
    }
  }

  /// Get detailed retentions for a month
  Future<List<TaxRetentionDetail>> getRetentionDetails({
    required String driverId,
    required int year,
    required int month,
  }) async {
    try {
      final response = await _client.rpc(
        'get_retention_details',
        params: {
          'p_driver_id': driverId,
          'p_year': year,
          'p_month': month,
        },
      );

      return (response as List).map((data) {
        return TaxRetentionDetail(
          date: DateTime.parse(data['transaction_date']),
          transactionType: data['transaction_type'] as String,
          grossAmount: (data['gross_amount'] as num).toDouble(),
          isrRate: (data['isr_rate'] as num).toDouble(),
          isrAmount: (data['isr_amount'] as num).toDouble(),
          ivaAmount: (data['iva_amount'] as num).toDouble(),
          netAmount: (data['net_amount'] as num).toDouble(),
          rideId: data['ride_id'] as String?,
          deliveryId: data['delivery_id'] as String?,
        );
      }).toList();
    } catch (e) {
      rethrow;
    }
  }

  /// Check if driver has validated RFC
  Future<bool> hasValidatedRfc(String driverId) async {
    try {
      final response = await _client
          .from('drivers')
          .select('rfc, rfc_validated')
          .eq('id', driverId)
          .single();

      return response['rfc'] != null && response['rfc_validated'] == true;
    } catch (e) {
      return false;
    }
  }

  /// Update driver RFC
  Future<bool> updateRfc(String driverId, String rfc) async {
    try {
      // Validate RFC format first
      if (!_isValidRfcFormat(rfc)) {
        throw Exception('Formato de RFC inválido');
      }

      await _client
          .from('drivers')
          .update({
            'rfc': rfc.toUpperCase(),
            'rfc_validated': true,
          })
          .eq('id', driverId);

      return true;
    } catch (e) {
      rethrow;
    }
  }

  /// Validate RFC format
  bool _isValidRfcFormat(String rfc) {
    final cleanRfc = rfc.toUpperCase().replaceAll(RegExp(r'\s'), '');

    if (cleanRfc.length < 12 || cleanRfc.length > 13) {
      return false;
    }

    // Persona física: AAAA######XXX (13 chars)
    // Persona moral: AAA######XXX (12 chars)
    final pattern = cleanRfc.length == 13
        ? RegExp(r'^[A-ZÑ&]{4}[0-9]{6}[A-Z0-9]{3}$')
        : RegExp(r'^[A-ZÑ&]{3}[0-9]{6}[A-Z0-9]{3}$');

    return pattern.hasMatch(cleanRfc);
  }
}

/// Result of tax retention calculation
class TaxRetentionResult {
  final double grossAmount;
  final bool hasRfc;
  final double isrRate;
  final double isrAmount;
  final double ivaRate;
  final double ivaAmount;
  final double ivaDriverOwes;
  final double netAmount;
  final String currency;

  TaxRetentionResult({
    required this.grossAmount,
    required this.hasRfc,
    required this.isrRate,
    required this.isrAmount,
    required this.ivaRate,
    required this.ivaAmount,
    required this.ivaDriverOwes,
    required this.netAmount,
    required this.currency,
  });

  /// ISR rate as percentage string
  String get isrRatePercent => '${(isrRate * 100).toStringAsFixed(1)}%';

  /// IVA rate as percentage string
  String get ivaRatePercent => '${(ivaRate * 100).toStringAsFixed(1)}%';
}

/// Tax summary for a period
class TaxSummary {
  final String period;
  final double totalGross;
  final double totalIsr;
  final double totalIvaRetained;
  final double totalIvaOwes;
  final double totalNet;
  final int transactionCount;
  final bool hadRfc;

  TaxSummary({
    required this.period,
    required this.totalGross,
    required this.totalIsr,
    required this.totalIvaRetained,
    required this.totalIvaOwes,
    required this.totalNet,
    required this.transactionCount,
    required this.hadRfc,
  });
}

/// Monthly tax summary
class TaxMonthlySummary {
  final int year;
  final int month;
  final double totalGross;
  final double totalIsrRetained;
  final double totalIvaRetained;
  final double totalIvaDriverOwes;
  final double totalNet;
  final int transactionCount;
  final bool hadRfc;
  final String? constanciaUrl;

  TaxMonthlySummary({
    required this.year,
    required this.month,
    required this.totalGross,
    required this.totalIsrRetained,
    required this.totalIvaRetained,
    required this.totalIvaDriverOwes,
    required this.totalNet,
    required this.transactionCount,
    required this.hadRfc,
    this.constanciaUrl,
  });

  String get periodString => '$year-${month.toString().padLeft(2, '0')}';

  String get monthName {
    const months = [
      'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
    ];
    return months[month - 1];
  }
}

/// Detailed retention record
class TaxRetentionDetail {
  final DateTime date;
  final String transactionType;
  final double grossAmount;
  final double isrRate;
  final double isrAmount;
  final double ivaAmount;
  final double netAmount;
  final String? rideId;
  final String? deliveryId;

  TaxRetentionDetail({
    required this.date,
    required this.transactionType,
    required this.grossAmount,
    required this.isrRate,
    required this.isrAmount,
    required this.ivaAmount,
    required this.netAmount,
    this.rideId,
    this.deliveryId,
  });
}
