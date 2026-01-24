import 'package:flutter_stripe/flutter_stripe.dart';

class StripeConfig {
  static const String publishableKey = 'pk_test_51SjZ6ZJkPkRlUpHxaozvdbpgbP8lRScfj5dLpcKv0AuUrjpcv73TnXrGk4Pq6NJzFU0vepYKxXiF0hHZBXXlPnWy009dN2qG0E';
  static const String merchantId = 'merchant.com.toro.driver';

  static Future<void> initialize() async {
    Stripe.publishableKey = publishableKey;
    Stripe.merchantIdentifier = merchantId;
    await Stripe.instance.applySettings();
  }
}
