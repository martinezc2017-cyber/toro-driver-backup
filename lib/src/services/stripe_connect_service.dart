import 'package:url_launcher/url_launcher.dart';
import '../config/supabase_config.dart';
import '../core/logging/app_logger.dart';

/// Servicio para manejar Stripe Connect Express
/// Permite a los drivers conectar su cuenta bancaria para recibir pagos
/// Soporta múltiples proveedores: 'us' para Estados Unidos, 'mx' para México
class StripeConnectService {
  static final StripeConnectService _instance = StripeConnectService._();
  static StripeConnectService get instance => _instance;
  StripeConnectService._();

  /// Crear cuenta de Stripe Connect y obtener link de onboarding
  /// Retorna el URL para que el driver complete su registro
  /// provider: 'us' para Estados Unidos, 'mx' para México
  Future<String?> createConnectAccount({
    required String driverId,
    required String email,
    String? firstName,
    String? lastName,
    String provider = 'us',
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
          'provider': provider,
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
        // Guardar el account_id en driver_stripe_accounts_mx (la tabla real;
        // 'driver_stripe_accounts' no existe -> el upsert tiraba y este metodo
        // retornaba null aunque la cuenta SI se creo). Sin columna 'provider';
        // unique en driver_id.
        await supabase.from('driver_stripe_accounts_mx').upsert({
          'driver_id': driverId,
          'stripe_account_id': accountId,
          'is_active': true,
        }, onConflict: 'driver_id');

        // Sync drivers.stripe_account_id for BOTH providers. stripe-process-split reads the
        // payout account from drivers.stripe_account_id; gating this to 'us' left MX drivers'
        // accounts ONLY in driver_stripe_accounts_mx, so their payout transfers found no
        // account ('no_stripe_account') and the money stayed stuck in TORO's balance. Mirror
        // it always so MX driver payouts actually land.
        await supabase
            .from('drivers')
            .update({'stripe_account_id': accountId})
            .eq('id', driverId);

        AppLogger.log('STRIPE CONNECT -> Account created: $accountId ($provider)');
      }

      return onboardingUrl;
    } catch (e) {
      AppLogger.log('STRIPE CONNECT -> Error creating account: $e');
      return null;
    }
  }

  /// Obtener link de onboarding para cuenta existente
  /// Usar cuando el driver no completo el onboarding
  /// provider: 'us' para Estados Unidos, 'mx' para México
  Future<String?> getOnboardingLink(String driverId, {String provider = 'us'}) async {
    try {
      final supabase = SupabaseConfig.client;

      final response = await supabase.functions.invoke(
        'stripe-connect-onboarding',
        body: {
          'driver_id': driverId,
          'refresh': true, // Solo generar nuevo link
          'provider': provider,
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
  /// provider: 'us' para Estados Unidos, 'mx' para México
  Future<StripeAccountStatus> getAccountStatus(String driverId, {String provider = 'us'}) async {
    try {
      final supabase = SupabaseConfig.client;

      // Obtener stripe_account_id de driver_stripe_accounts_mx (tabla real,
      // col account_status, sin 'provider', unique en driver_id).
      final account = await supabase
          .from('driver_stripe_accounts_mx')
          .select('stripe_account_id, account_status')
          .eq('driver_id', driverId)
          .maybeSingle();

      if (account == null) {
        // Fallback: revisar en drivers si es US
        if (provider == 'us') {
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
          return _checkAccountStatus(supabase, driverId, accountId, provider);
        }
        return StripeAccountStatus.notCreated;
      }

      final accountId = account['stripe_account_id'];
      if (accountId == null || accountId.toString().isEmpty) {
        return StripeAccountStatus.notCreated;
      }

      return _checkAccountStatus(supabase, driverId, accountId, provider);
    } catch (e) {
      AppLogger.log('STRIPE CONNECT -> Error checking status: $e');
      return StripeAccountStatus.error;
    }
  }

  Future<StripeAccountStatus> _checkAccountStatus(
    dynamic supabase,
    String driverId,
    String accountId,
    String provider,
  ) async {
    // Verificar estado con Edge Function
    final response = await supabase.functions.invoke(
      'stripe-connect-status',
      body: {'account_id': accountId, 'provider': provider},
    );

    if (response.status != 200) {
      return StripeAccountStatus.error;
    }

    final data = response.data as Map<String, dynamic>;
    final payoutsEnabled = data['payouts_enabled'] as bool? ?? false;
    final detailsSubmitted = data['details_submitted'] as bool? ?? false;

    // El chofer/vendedor RECIBE payouts (no cobra a clientes). Por eso "listo" =
    // payouts_enabled. Exigir charges_enabled era un bug: una cuenta de solo-
    // transferencias tiene charges_enabled=false SIEMPRE -> nunca quedaba 'active'.
    final ready = payoutsEnabled;
    String status;
    if (ready) {
      status = 'active';
    } else if (detailsSubmitted) {
      status = 'pending';
    } else {
      status = 'incomplete';
    }

    // Actualizar en driver_stripe_accounts_mx (col account_status, sin provider)
    await supabase.from('driver_stripe_accounts_mx').upsert({
      'driver_id': driverId,
      'stripe_account_id': accountId,
      'account_status': status,
    }, onConflict: 'driver_id');

    // También actualizar en drivers si es US
    if (provider == 'us') {
      await supabase
          .from('drivers')
          .update({'stripe_account_status': status})
          .eq('id', driverId);
    }

    if (ready) {
      return StripeAccountStatus.active;
    } else if (detailsSubmitted) {
      return StripeAccountStatus.pendingVerification;
    } else {
      return StripeAccountStatus.incomplete;
    }
  }

  /// Abrir el link de onboarding en el navegador
  Future<bool> openOnboardingLink(String url) async {
    final uri = Uri.parse(url);
    // canLaunchUrl es POCO FIABLE en Android 11+ (visibilidad de paquetes):
    // devuelve false aunque SI haya navegador -> el link "no salia". Lanzar
    // directo con modos de respaldo (externo -> default -> in-app webview).
    for (final mode in const [
      LaunchMode.externalApplication,
      LaunchMode.platformDefault,
      LaunchMode.inAppWebView,
    ]) {
      try {
        if (await launchUrl(uri, mode: mode)) return true;
      } catch (e) {
        AppLogger.log('STRIPE CONNECT -> open URL ($mode) fallo: $e');
      }
    }
    return false;
  }

  /// Obtener link del dashboard de Stripe para el driver
  /// provider: 'us' para Estados Unidos, 'mx' para México
  Future<String?> getDashboardLink(String driverId, {String provider = 'us'}) async {
    try {
      final supabase = SupabaseConfig.client;

      final response = await supabase.functions.invoke(
        'stripe-connect-dashboard',
        body: {'driver_id': driverId, 'provider': provider},
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
  /// provider: 'us' para Estados Unidos, 'mx' para México
  Future<DriverBalance?> getBalance(String driverId, {String provider = 'us'}) async {
    try {
      final supabase = SupabaseConfig.client;

      try {
        final sync = await supabase.functions.invoke(
          'stripe-instant-payout',
          body: {'driver_id': driverId, 'mode': 'balance_sync'},
        );
        final data = (sync.data is Map)
            ? Map<String, dynamic>.from(sync.data as Map)
            : <String, dynamic>{};
        if (sync.status == 200 && data['success'] == true) {
          final availablePesos = (data['available_balance'] as num?)?.toDouble() ?? 0;
          final pendingPesos = (data['pending_balance'] as num?)?.toDouble() ?? 0;
          return DriverBalance(
            availableCents: (availablePesos * 100).round(),
            pendingCents: (pendingPesos * 100).round(),
            currency: (data['currency'] ?? (provider == 'mx' ? 'mxn' : 'usd')).toString(),
          );
        }
      } catch (e) {
        AppLogger.log('STRIPE CONNECT -> Balance sync unavailable, using DB balance: $e');
      }

      // Rewire: TORO mantiene el balance canónico en drivers.available_balance
      // (recalculado desde driver_earnings card-net − payouts). Antes invocaba
      // 'stripe-connect-balance' que NO existe. Lee la columna directo.
      final row = await supabase
          .from('drivers')
          .select('available_balance, pending_balance, country_code')
          .eq('id', driverId)
          .maybeSingle();

      if (row == null) return null;

      // Columnas en pesos → modelo espera centavos.
      final availablePesos = (row['available_balance'] as num?)?.toDouble() ?? 0;
      final pendingPesos = (row['pending_balance'] as num?)?.toDouble() ?? 0;
      return DriverBalance(
        availableCents: (availablePesos * 100).round(),
        pendingCents: (pendingPesos * 100).round(),
        currency: (row['country_code'] == 'MX') ? 'mxn' : 'usd',
      );
    } catch (e) {
      AppLogger.log('STRIPE CONNECT -> Error getting balance: $e');
      return null;
    }
  }

  /// Obtener todas las cuentas conectadas del driver
  Future<List<ConnectedAccount>> getConnectedAccounts(String driverId) async {
    try {
      final supabase = SupabaseConfig.client;

      final response = await supabase
          .from('driver_stripe_accounts_mx')
          .select()
          .eq('driver_id', driverId)
          .eq('is_active', true);

      return (response as List).map((data) {
        return ConnectedAccount(
          provider: 'mx', // table is MX-specific (no 'provider' column)
          stripeAccountId: data['stripe_account_id'] as String,
          status: data['account_status'] as String? ?? 'unknown',
          isDefault: data['is_default'] as bool? ?? false,
        );
      }).toList();
    } catch (e) {
      AppLogger.log('STRIPE CONNECT -> Error getting connected accounts: $e');
      return [];
    }
  }

  /// Solicitar retiro de fondos (payout)
  /// amount: cantidad en centavos (ej: 10000 = $100.00 MXN)
  /// provider: 'us' para Estados Unidos, 'mx' para México
  Future<PayoutResult> requestPayout({
    required String driverId,
    required int amountCents,
    String currency = 'mxn',
    String provider = 'us',
  }) async {
    try {
      final supabase = SupabaseConfig.client;

      // LOGS (Carlos): cada paso del retiro a app_logs para diagnosticar.
      Future<void> plog(String m) async {
        try {
          await supabase.from('app_logs').insert({
            'level': 'info',
            'message': 'PAYOUT_DBG driver=$driverId | $m',
          });
        } catch (_) {}
      }
      await plog('START amountCents=$amountCents amount=${amountCents / 100.0}');

      // SIN pre-checks en el app (getBalance/payouts_enabled tronaban o bloqueaban
      // con falsos negativos -> "Error de conexión"). stripe-instant-payout es la
      // AUTORIDAD: valida la cuenta, liquida el saldo del pool de la plataforma al
      // Connect y paga al banco. Si algo falla, devuelve un error claro.
      final response = await supabase.functions.invoke(
        'stripe-instant-payout',
        body: {
          'driver_id': driverId,
          'amount': amountCents / 100.0,
        },
      );

      await plog('INVOKE status=${response.status} data=${response.data}');

      final data = (response.data is Map)
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      if (response.status != 200 || data['success'] != true) {
        final errorMessage = (data['error'] ?? 'Error al procesar retiro').toString();
        await plog('ERROR: $errorMessage');
        return PayoutResult(success: false, error: errorMessage);
      }

      await plog('SUCCESS payout_id=${data['payout_id']}');
      return PayoutResult(
        success: true,
        payoutId: data['payout_id'] as String?,
        arrivalDate: data['arrival_date'] != null
            ? DateTime.tryParse(data['arrival_date'].toString())
            : null,
      );
    } catch (e) {
      AppLogger.log('STRIPE CONNECT -> Error requesting payout: $e');
      // LOG a app_logs el error crudo + details (Carlos: ponle logs).
      try {
        await SupabaseConfig.client.from('app_logs').insert({
          'level': 'error',
          'message': 'PAYOUT_DBG driver=$driverId | CATCH: $e',
        });
      } catch (_) {}
      // Si es FunctionException (la fn devolvió >=400), tiene .details con el
      // error REAL — mostrarlo en vez del genérico "Error de conexión".
      try {
        final d = (e as dynamic).details;
        if (d is Map && d['error'] != null) {
          return PayoutResult(success: false, error: d['error'].toString());
        }
      } catch (_) {}
      return PayoutResult(
        success: false,
        error: 'Error de conexión. Intenta de nuevo.',
      );
    }
  }

  /// Obtener historial de payouts
  /// provider: 'us' para Estados Unidos, 'mx' para México
  Future<List<PayoutRecord>> getPayoutHistory(String driverId, {int limit = 20, String provider = 'us'}) async {
    try {
      final supabase = SupabaseConfig.client;

      // Rewire: TORO mantiene driver_payouts canónica (escrita por
      // stripe-instant-payout / stripe-weekly-payout y sincronizada por
      // stripe-payout-webhook). Antes invocaba 'stripe-connect-payout-history'
      // que NO existe. Query directo.
      final rows = await supabase
          .from('driver_payouts')
          .select('id, amount, status, created_at, stripe_payout_id, metadata')
          .eq('driver_id', driverId)
          .order('created_at', ascending: false)
          .limit(limit);

      return (rows as List).map((data) {
        final amountPesos = (data['amount'] as num?)?.toDouble() ?? 0;
        final createdAt = DateTime.tryParse(data['created_at']?.toString() ?? '') ?? DateTime.now();
        final meta = data['metadata'] as Map<String, dynamic>?;
        final arrivalStr = meta?['arrival_date']?.toString();
        return PayoutRecord(
          id: (data['stripe_payout_id'] ?? data['id'] ?? '').toString(),
          amountCents: (amountPesos * 100).round(),
          currency: (meta?['currency'] ?? 'mxn').toString(),
          status: (data['status'] ?? 'unknown').toString(),
          createdAt: createdAt,
          arrivalDate: arrivalStr != null ? DateTime.tryParse(arrivalStr) : null,
        );
      }).toList();
    } catch (e) {
      AppLogger.log('STRIPE CONNECT -> Error getting payout history: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> getOpenPayout(String driverId) async {
    try {
      final row = await SupabaseConfig.client
          .from('driver_payouts')
          .select('id, amount, status, stripe_payout_id, created_at')
          .eq('driver_id', driverId)
          .inFilter('status', ['pending', 'processing', 'in_transit'])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      return row == null ? null : Map<String, dynamic>.from(row);
    } catch (e) {
      AppLogger.log('STRIPE CONNECT -> Error getting open payout: $e');
      return null;
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

/// Cuenta conectada de Stripe
class ConnectedAccount {
  final String provider;
  final String stripeAccountId;
  final String status;
  final bool isDefault;

  ConnectedAccount({
    required this.provider,
    required this.stripeAccountId,
    required this.status,
    required this.isDefault,
  });

  String get providerDisplayName {
    switch (provider) {
      case 'us':
        return 'Estados Unidos';
      case 'mx':
        return 'México';
      default:
        return provider.toUpperCase();
    }
  }

  String get currencyCode {
    switch (provider) {
      case 'us':
        return 'USD';
      case 'mx':
        return 'MXN';
      default:
        return 'USD';
    }
  }

  bool get isActive => status == 'active';
}
