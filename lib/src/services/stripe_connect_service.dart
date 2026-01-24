import 'package:url_launcher/url_launcher.dart';
import '../config/supabase_config.dart';
import '../core/logging/app_logger.dart';

/// Servicio para manejar Stripe Connect Express
/// Permite a los drivers conectar su cuenta bancaria para recibir pagos
class StripeConnectService {
  static final StripeConnectService _instance = StripeConnectService._();
  static StripeConnectService get instance => _instance;
  StripeConnectService._();

  /// Crear cuenta de Stripe Connect y obtener link de onboarding
  /// Retorna el URL para que el driver complete su registro
  Future<String?> createConnectAccount({
    required String driverId,
    required String email,
    String? firstName,
    String? lastName,
  }) async {
    try {
      final supabase = SupabaseConfig.client;

      // Llamar a la Edge Function que crea la cuenta en Stripe
      final response = await supabase.functions.invoke(
        'stripe-connect-onboarding',
        body: {
          'driver_id': driverId,
          'email': email,
          'first_name': firstName,
          'last_name': lastName,
        },
      );

      if (response.status != 200) {
        AppLogger.log('STRIPE CONNECT -> Error: ${response.data}');
        return null;
      }

      final data = response.data as Map<String, dynamic>;
      final onboardingUrl = data['url'] as String?;
      final accountId = data['account_id'] as String?;

      if (accountId != null) {
        // Guardar el account_id en la tabla drivers
        await supabase
            .from('drivers')
            .update({'stripe_account_id': accountId})
            .eq('id', driverId);

        AppLogger.log('STRIPE CONNECT -> Account created: $accountId');
      }

      return onboardingUrl;
    } catch (e) {
      AppLogger.log('STRIPE CONNECT -> Error creating account: $e');
      return null;
    }
  }

  /// Obtener link de onboarding para cuenta existente
  /// Usar cuando el driver no completo el onboarding
  Future<String?> getOnboardingLink(String driverId) async {
    try {
      final supabase = SupabaseConfig.client;

      final response = await supabase.functions.invoke(
        'stripe-connect-onboarding',
        body: {
          'driver_id': driverId,
          'refresh': true, // Solo generar nuevo link
        },
      );

      if (response.status != 200) {
        return null;
      }

      final data = response.data as Map<String, dynamic>;
      return data['url'] as String?;
    } catch (e) {
      AppLogger.log('STRIPE CONNECT -> Error getting onboarding link: $e');
      return null;
    }
  }

  /// Verificar estado de la cuenta de Stripe Connect
  Future<StripeAccountStatus> getAccountStatus(String driverId) async {
    try {
      final supabase = SupabaseConfig.client;

      // Obtener stripe_account_id del driver
      final driver = await supabase
          .from('drivers')
          .select('stripe_account_id, stripe_account_status')
          .eq('id', driverId)
          .maybeSingle();

      if (driver == null) {
        return StripeAccountStatus.notFound;
      }

      final accountId = driver['stripe_account_id'];
      if (accountId == null || accountId.toString().isEmpty) {
        return StripeAccountStatus.notCreated;
      }

      // Verificar estado con Edge Function
      final response = await supabase.functions.invoke(
        'stripe-connect-status',
        body: {'account_id': accountId},
      );

      if (response.status != 200) {
        return StripeAccountStatus.error;
      }

      final data = response.data as Map<String, dynamic>;
      final chargesEnabled = data['charges_enabled'] as bool? ?? false;
      final payoutsEnabled = data['payouts_enabled'] as bool? ?? false;
      final detailsSubmitted = data['details_submitted'] as bool? ?? false;

      // Actualizar estado en la base de datos
      String status;
      if (chargesEnabled && payoutsEnabled) {
        status = 'active';
      } else if (detailsSubmitted) {
        status = 'pending';
      } else {
        status = 'incomplete';
      }

      await supabase
          .from('drivers')
          .update({'stripe_account_status': status})
          .eq('id', driverId);

      if (chargesEnabled && payoutsEnabled) {
        return StripeAccountStatus.active;
      } else if (detailsSubmitted) {
        return StripeAccountStatus.pendingVerification;
      } else {
        return StripeAccountStatus.incomplete;
      }
    } catch (e) {
      AppLogger.log('STRIPE CONNECT -> Error checking status: $e');
      return StripeAccountStatus.error;
    }
  }

  /// Abrir el link de onboarding en el navegador
  Future<bool> openOnboardingLink(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      }
      return false;
    } catch (e) {
      AppLogger.log('STRIPE CONNECT -> Error opening URL: $e');
      return false;
    }
  }

  /// Obtener link del dashboard de Stripe para el driver
  Future<String?> getDashboardLink(String driverId) async {
    try {
      final supabase = SupabaseConfig.client;

      final response = await supabase.functions.invoke(
        'stripe-connect-dashboard',
        body: {'driver_id': driverId},
      );

      if (response.status != 200) {
        return null;
      }

      final data = response.data as Map<String, dynamic>;
      return data['url'] as String?;
    } catch (e) {
      AppLogger.log('STRIPE CONNECT -> Error getting dashboard link: $e');
      return null;
    }
  }

  /// Obtener balance disponible del driver
  Future<DriverBalance?> getBalance(String driverId) async {
    try {
      final supabase = SupabaseConfig.client;

      final response = await supabase.functions.invoke(
        'stripe-connect-balance',
        body: {'driver_id': driverId},
      );

      if (response.status != 200) {
        AppLogger.log('STRIPE CONNECT -> Error getting balance: ${response.data}');
        return null;
      }

      final data = response.data as Map<String, dynamic>;
      return DriverBalance.fromJson(data);
    } catch (e) {
      AppLogger.log('STRIPE CONNECT -> Error getting balance: $e');
      return null;
    }
  }

  /// Solicitar retiro de fondos (payout)
  /// amount: cantidad en centavos (ej: 10000 = $100.00 MXN)
  Future<PayoutResult> requestPayout({
    required String driverId,
    required int amountCents,
    String currency = 'mxn',
  }) async {
    try {
      final supabase = SupabaseConfig.client;

      // Verificar que la cuenta este activa
      final status = await getAccountStatus(driverId);
      if (!status.canReceivePayments) {
        return PayoutResult(
          success: false,
          error: 'Tu cuenta de Stripe no está activa. Completa la verificación primero.',
        );
      }

      // Verificar balance disponible
      final balance = await getBalance(driverId);
      if (balance == null) {
        return PayoutResult(
          success: false,
          error: 'No se pudo obtener tu balance. Intenta de nuevo.',
        );
      }

      if (balance.availableCents < amountCents) {
        return PayoutResult(
          success: false,
          error: 'Balance insuficiente. Disponible: \$${(balance.availableCents / 100).toStringAsFixed(2)}',
        );
      }

      // Solicitar payout via Edge Function
      final response = await supabase.functions.invoke(
        'stripe-connect-payout',
        body: {
          'driver_id': driverId,
          'amount': amountCents,
          'currency': currency,
        },
      );

      if (response.status != 200) {
        final errorData = response.data as Map<String, dynamic>?;
        final errorMessage = errorData?['error'] ?? 'Error al procesar retiro';
        return PayoutResult(success: false, error: errorMessage);
      }

      final data = response.data as Map<String, dynamic>;
      return PayoutResult(
        success: true,
        payoutId: data['payout_id'] as String?,
        arrivalDate: data['arrival_date'] != null
            ? DateTime.tryParse(data['arrival_date'])
            : null,
      );
    } catch (e) {
      AppLogger.log('STRIPE CONNECT -> Error requesting payout: $e');
      return PayoutResult(
        success: false,
        error: 'Error de conexión. Intenta de nuevo.',
      );
    }
  }

  /// Obtener historial de payouts
  Future<List<PayoutRecord>> getPayoutHistory(String driverId, {int limit = 20}) async {
    try {
      final supabase = SupabaseConfig.client;

      final response = await supabase.functions.invoke(
        'stripe-connect-payout-history',
        body: {
          'driver_id': driverId,
          'limit': limit,
        },
      );

      if (response.status != 200) {
        return [];
      }

      final data = response.data as Map<String, dynamic>;
      final payouts = data['payouts'] as List<dynamic>? ?? [];

      return payouts
          .map((json) => PayoutRecord.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.log('STRIPE CONNECT -> Error getting payout history: $e');
      return [];
    }
  }
}

/// Estados posibles de la cuenta de Stripe Connect
enum StripeAccountStatus {
  /// No se encontro el driver
  notFound,

  /// No tiene cuenta de Stripe creada
  notCreated,

  /// Cuenta creada pero onboarding incompleto
  incomplete,

  /// Onboarding completo, pendiente verificacion de Stripe
  pendingVerification,

  /// Cuenta activa, puede recibir pagos
  active,

  /// Error al verificar estado
  error,
}

/// Extension para obtener informacion del estado
extension StripeAccountStatusExtension on StripeAccountStatus {
  String get displayName {
    switch (this) {
      case StripeAccountStatus.notFound:
        return 'No encontrado';
      case StripeAccountStatus.notCreated:
        return 'No configurado';
      case StripeAccountStatus.incomplete:
        return 'Incompleto';
      case StripeAccountStatus.pendingVerification:
        return 'Pendiente verificacion';
      case StripeAccountStatus.active:
        return 'Activo';
      case StripeAccountStatus.error:
        return 'Error';
    }
  }

  bool get canReceivePayments => this == StripeAccountStatus.active;

  bool get needsOnboarding =>
      this == StripeAccountStatus.notCreated ||
      this == StripeAccountStatus.incomplete;
}

/// Modelo de balance del driver
class DriverBalance {
  final int availableCents;
  final int pendingCents;
  final String currency;

  DriverBalance({
    required this.availableCents,
    required this.pendingCents,
    required this.currency,
  });

  factory DriverBalance.fromJson(Map<String, dynamic> json) {
    return DriverBalance(
      availableCents: json['available'] ?? 0,
      pendingCents: json['pending'] ?? 0,
      currency: json['currency'] ?? 'mxn',
    );
  }

  double get availableAmount => availableCents / 100;
  double get pendingAmount => pendingCents / 100;

  @override
  String toString() => 'Balance: \$${availableAmount.toStringAsFixed(2)} disponible, \$${pendingAmount.toStringAsFixed(2)} pendiente';
}

/// Resultado de solicitud de payout
class PayoutResult {
  final bool success;
  final String? payoutId;
  final String? error;
  final DateTime? arrivalDate;

  PayoutResult({
    required this.success,
    this.payoutId,
    this.error,
    this.arrivalDate,
  });

  @override
  String toString() => success
      ? 'Payout $payoutId - Llegará: $arrivalDate'
      : 'Error: $error';
}

/// Registro de payout en historial
class PayoutRecord {
  final String id;
  final int amountCents;
  final String currency;
  final String status;
  final DateTime createdAt;
  final DateTime? arrivalDate;

  PayoutRecord({
    required this.id,
    required this.amountCents,
    required this.currency,
    required this.status,
    required this.createdAt,
    this.arrivalDate,
  });

  factory PayoutRecord.fromJson(Map<String, dynamic> json) {
    return PayoutRecord(
      id: json['id'] ?? '',
      amountCents: json['amount'] ?? 0,
      currency: json['currency'] ?? 'mxn',
      status: json['status'] ?? 'unknown',
      createdAt: json['created'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['created'] * 1000)
          : DateTime.now(),
      arrivalDate: json['arrival_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['arrival_date'] * 1000)
          : null,
    );
  }

  double get amount => amountCents / 100;

  String get statusDisplay {
    switch (status) {
      case 'paid':
        return 'Pagado';
      case 'pending':
        return 'Pendiente';
      case 'in_transit':
        return 'En tránsito';
      case 'canceled':
        return 'Cancelado';
      case 'failed':
        return 'Fallido';
      default:
        return status;
    }
  }
}
