import 'package:url_launcher/url_launcher.dart';
import '../config/supabase_config.dart';
import '../core/logging/app_logger.dart';

/// Stripe Connect Express para organizadores de turismo.
///
/// Mismo modelo que [StripeConnectService] (drivers) y `stripe-vendor-onboarding`
/// (vendors): cada organizer es una entidad legal/fiscal distinta y necesita
/// su propio `acct_xxx`, aún cuando el humano detrás también sea driver o vendor.
class OrganizerStripeService {
  static final OrganizerStripeService _instance = OrganizerStripeService._();
  static OrganizerStripeService get instance => _instance;
  OrganizerStripeService._();

  /// Crea la cuenta Express y retorna el link de onboarding.
  Future<String?> createConnectAccount({
    required String organizerId,
    String? email,
    String? companyName,
  }) async {
    try {
      final response = await SupabaseConfig.client.functions.invoke(
        'stripe-organizer-onboarding',
        body: {
          'organizer_id': organizerId,
          'email': email,
          'company_name': companyName,
        },
      );
      if (response.status != 200) {
        AppLogger.log('ORG_STRIPE -> error create: ${response.data}');
        return null;
      }
      final data = response.data as Map<String, dynamic>;
      return data['onboarding_url'] as String?;
    } catch (e) {
      AppLogger.log('ORG_STRIPE -> exception create: $e');
      return null;
    }
  }

  /// Genera un link fresco de onboarding para cuenta existente.
  Future<String?> getOnboardingLink(String organizerId) async {
    try {
      final response = await SupabaseConfig.client.functions.invoke(
        'stripe-organizer-onboarding',
        body: {'organizer_id': organizerId, 'refresh': true},
      );
      if (response.status != 200) return null;
      final data = response.data as Map<String, dynamic>;
      return data['onboarding_url'] as String?;
    } catch (e) {
      AppLogger.log('ORG_STRIPE -> exception refresh: $e');
      return null;
    }
  }

  /// Lee el estado actual desde la tabla `organizers`.
  Future<OrganizerStripeStatus> getStatus(String organizerId) async {
    try {
      final row = await SupabaseConfig.client
          .from('organizers')
          .select(
              'stripe_account_id, stripe_account_status, charges_enabled, payouts_enabled, details_submitted')
          .eq('id', organizerId)
          .maybeSingle();
      if (row == null) return OrganizerStripeStatus.notFound();
      return OrganizerStripeStatus(
        accountId: row['stripe_account_id'] as String?,
        statusRaw: row['stripe_account_status'] as String? ?? 'not_created',
        chargesEnabled: (row['charges_enabled'] as bool?) ?? false,
        payoutsEnabled: (row['payouts_enabled'] as bool?) ?? false,
        detailsSubmitted: (row['details_submitted'] as bool?) ?? false,
      );
    } catch (e) {
      AppLogger.log('ORG_STRIPE -> exception status: $e');
      return OrganizerStripeStatus.notFound();
    }
  }

  /// Abre el link en navegador externo.
  Future<bool> openOnboardingLink(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    }
    return false;
  }
}

/// Estado consolidado del Connect del organizer.
class OrganizerStripeStatus {
  final String? accountId;
  final String statusRaw;
  final bool chargesEnabled;
  final bool payoutsEnabled;
  final bool detailsSubmitted;

  const OrganizerStripeStatus({
    required this.accountId,
    required this.statusRaw,
    required this.chargesEnabled,
    required this.payoutsEnabled,
    required this.detailsSubmitted,
  });

  factory OrganizerStripeStatus.notFound() => const OrganizerStripeStatus(
        accountId: null,
        statusRaw: 'not_created',
        chargesEnabled: false,
        payoutsEnabled: false,
        detailsSubmitted: false,
      );

  bool get canReceivePayments => chargesEnabled && payoutsEnabled;
  bool get needsOnboarding => !detailsSubmitted;
  bool get isActive => canReceivePayments;
  bool get hasAccount => accountId != null && accountId!.isNotEmpty;
}
