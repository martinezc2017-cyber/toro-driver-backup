import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Lee el kill switch de pago con TARJETA por pais
/// (`countries.card_payments_enabled`, RPC `get_country_payment_methods`).
///
/// En el app del CHOFER solo se usa para una cosa: decidir si se le ofrece
/// liquidar su comision con tarjeta, o solo por deposito/transferencia externa.
///
/// Falla ABIERTA a proposito (default true): si no se puede leer, se sigue
/// ofreciendo tarjeta y el servidor decide. Fallar cerrado dejaria a los
/// choferes de USA sin forma de pagar por un parpadeo de red.
class DriverPaymentMethodsConfig {
  DriverPaymentMethodsConfig._();
  static final DriverPaymentMethodsConfig instance =
      DriverPaymentMethodsConfig._();

  bool _cardEnabled = true;
  String? _country;

  bool get cardEnabled => _cardEnabled;
  String? get country => _country;

  Future<void> load(String countryCode) async {
    final code = countryCode.toUpperCase();
    try {
      final res = await Supabase.instance.client.rpc(
        'get_country_payment_methods',
        params: {'p_country_code': code},
      );
      if (res is Map) {
        _cardEnabled = (res['card_enabled'] as bool?) ?? true;
        _country = code;
        debugPrint('DRIVER PAYMENT SWITCH -> $code card=$_cardEnabled');
      }
    } catch (e) {
      debugPrint('DRIVER PAYMENT SWITCH -> no se pudo leer ($e), se deja en $_cardEnabled');
    }
  }
}
