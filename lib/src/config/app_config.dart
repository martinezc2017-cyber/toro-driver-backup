class AppConfig {
  // App Info
  static const String appName = 'Toro Driver';
  static const String appVersion = '1.0.0';

  // API Endpoints (for external services)
  static const String googleMapsApiKey = 'YOUR_GOOGLE_MAPS_API_KEY';

  // ============================================================================
  // ⚠️ DEPRECATED: NO USAR ESTOS VALORES - Todos vienen de pricing_config en BD
  // ============================================================================
  // Usar StatePricingService.instance.getPricing() en su lugar
  // Estos valores existen SOLO para compatibilidad temporal y serán eliminados
  @Deprecated('Use StatePricingService.getPricing() instead')
  static const double baseFare = 0.0; // CONFIGURAR EN ADMIN WEB
  @Deprecated('Use StatePricingService.getPricing() instead')
  static const double perKmRate = 0.0; // CONFIGURAR EN ADMIN WEB
  @Deprecated('Use StatePricingService.getPricing() instead')
  static const double perMinuteRate = 0.0; // CONFIGURAR EN ADMIN WEB
  @Deprecated('Use StatePricingService.getPricing() instead')
  static const double minimumFare = 0.0; // CONFIGURAR EN ADMIN WEB
  @Deprecated('Use StatePricingService.getPricing() instead')
  static const double platformFeePercentage = 0.0; // CONFIGURAR EN ADMIN WEB

  // Driver Settings
  static const double minAcceptanceRate = 0.80; // 80%
  static const double minRating = 4.0;
  static const int maxCancellationsPerDay = 3;

  // Referral Settings
  static const double referralBonusDriver = 500.0;
  static const double referralBonusReferrer = 500.0;
  static const int requiredTripsForBonus = 1;

  // Location Settings
  static const int locationUpdateIntervalMs = 5000; // 5 seconds
  static const double locationDistanceFilter = 10.0; // 10 meters

  // Timeout Settings
  static const int rideRequestTimeoutSeconds = 30;
  static const int passengerWaitTimeMinutes = 5;

  // Currency
  static const String currency = 'MXN';
  static const String currencySymbol = '\$';
}
