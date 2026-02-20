import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/legal/consent_service.dart';
import '../core/legal/legal_constants.dart';
import '../core/legal/legal_documents.dart';
import '../core/logging/app_logger.dart';
import '../services/version_check_service.dart';
import '../widgets/version_check_dialog.dart';
import 'auth_wrapper.dart';

/// Terms Acceptance Screen for Drivers
/// Shows BEFORE login - user must accept to proceed
/// Tracks scroll percentage, reading time, and acceptance language
class TermsAcceptanceScreen extends StatefulWidget {
  const TermsAcceptanceScreen({super.key});

  @override
  State<TermsAcceptanceScreen> createState() => _TermsAcceptanceScreenState();
}

class _TermsAcceptanceScreenState extends State<TermsAcceptanceScreen> {
  bool _hasAcceptedTerms = false;
  bool _isOver21 = false;
  bool _isProcessing = false;

  // Scroll and reading tracking
  double _scrollPercentage = 0.0;
  late DateTime _screenOpenedAt;
  final ScrollController _termsScrollController = ScrollController();
  bool _hasOpenedTerms = false;

  // Theme colors
  static const Color primaryColor = Color(0xFF1E88E5);
  static const Color secondaryColor = Color(0xFF43A047);

  @override
  void initState() {
    super.initState();
    _screenOpenedAt = DateTime.now();
    AppLogger.log('TERMS_SCREEN -> Opened (pre-login)');

    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAppVersion());
  }

  @override
  void dispose() {
    _termsScrollController.dispose();
    super.dispose();
  }

  /// Get the current language code from EasyLocalization
  String get _currentLanguageCode {
    try {
      return context.locale.languageCode;
    } catch (_) {
      return 'en';
    }
  }

  Future<void> _checkAppVersion() async {
    try {
      final result = await VersionCheckService().checkVersion(appName: 'toro_driver');

      if (!mounted) return;

      if (result.needsHardUpdate || result.needsSoftUpdate) {
        await VersionCheckDialog.show(context, result);
      }
    } catch (e) {
      AppLogger.log('VERSION_CHECK -> Error: $e');
    }
  }

  Future<void> _onAccept() async {
    if (!_hasAcceptedTerms || !_isOver21 || _isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      final lang = _currentLanguageCode;
      final timeSpent = DateTime.now().difference(_screenOpenedAt).inMilliseconds;

      // Save acceptance locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(LegalConstants.termsAcceptedKey, true);
      await prefs.setString(LegalConstants.termsLanguageKey, lang);
      await prefs.setString(LegalConstants.termsVersionKey, LegalConstants.legalBundleVersion);

      // Record consent with real metrics
      final consentService = ConsentService.instance;
      await consentService.initialize();
      await consentService.recordFullAcceptance(
        userId: 'pre_login_${DateTime.now().millisecondsSinceEpoch}',
        languageCode: lang,
        scrollPercentage: _scrollPercentage,
        timeSpentReadingMs: timeSpent,
        ageVerified: true,
        backgroundCheckConsent: true,
      );

      AppLogger.log(
        'LEGAL_ACCEPTED -> Pre-login acceptance lang=$lang, '
        'scroll=${_scrollPercentage.toStringAsFixed(2)}, '
        'timeMs=$timeSpent',
      );

      // Request GPS permission AFTER T&C accepted
      await _requestLocationPermissions();

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/auth');
      }
    } catch (e) {
      AppLogger.log('LEGAL_ERROR -> Failed to save consent: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _requestLocationPermissions() async {
    try {
      // 1. Check if GPS service is enabled on the device
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        AppLogger.log('TERMS -> GPS service disabled, showing dialog');
        if (!mounted) return;
        final shouldOpen = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.location_off, size: 48, color: Colors.orange),
            title: Text('gps_required_title'.tr()),
            content: Text('gps_required_message'.tr()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('gps_skip'.tr()),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.location_on),
                label: Text('gps_enable_button'.tr()),
              ),
            ],
          ),
        );
        if (shouldOpen == true) {
          await Geolocator.openLocationSettings();
        }
        return;
      }

      // 2. Check permission status
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.my_location, size: 48, color: Colors.blue),
            title: Text('gps_permission_denied_title'.tr()),
            content: Text('gps_permission_denied_message'.tr()),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('gps_ok'.tr()),
              ),
            ],
          ),
        );
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          AppLogger.log('TERMS -> GPS permission denied by user');
          return;
        }
      }

      // 3. Handle permanently denied
      if (permission == LocationPermission.deniedForever) {
        AppLogger.log('TERMS -> GPS permission denied forever');
        if (!mounted) return;
        final shouldOpen = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.location_disabled, size: 48, color: Colors.red),
            title: Text('gps_permission_blocked_title'.tr()),
            content: Text('gps_permission_blocked_message'.tr()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('gps_skip'.tr()),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.settings),
                label: Text('gps_open_settings'.tr()),
              ),
            ],
          ),
        );
        if (shouldOpen == true) {
          await Geolocator.openAppSettings();
        }
        return;
      }

      AppLogger.log('TERMS -> GPS permission granted: $permission');
    } catch (e) {
      AppLogger.log('TERMS -> Error requesting GPS: $e');
    }
  }

  void _showTerms() {
    _hasOpenedTerms = true;
    _scrollPercentage = 0.0;
    final lang = _currentLanguageCode;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          // Track scroll for legal metrics
          scrollController.addListener(() {
            if (scrollController.hasClients &&
                scrollController.position.maxScrollExtent > 0) {
              final pct = scrollController.offset /
                  scrollController.position.maxScrollExtent;
              if (pct > _scrollPercentage) {
                _scrollPercentage = pct.clamp(0.0, 1.0);
              }
            }
          });

          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.description, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          lang == 'es' ? 'Documentos Legales' : 'Legal Documents',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      // Language indicator
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          lang.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: primaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Content
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      LegalDocuments.getCombinedDocument(lang),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = _currentLanguageCode;
    final isEs = lang == 'es';

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom -
                  48,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 24),

                // TORO Logo
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00D9FF).withValues(alpha: 0.35),
                      blurRadius: 30,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Image.asset(
                    'assets/images/toro_logo_new.png',
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Image.asset(
                        'assets/images/toro_logo.png',
                        width: 120,
                        height: 120,
                        fit: BoxFit.cover,
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Title
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [primaryColor, secondaryColor],
                ).createShader(bounds),
                child: Text(
                  isEs ? 'Bienvenido a Toro Driver' : 'Welcome to Toro Driver',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Subtitle
              Text(
                isEs
                    ? 'Para comenzar a conducir con ${LegalConstants.companyName} debes aceptar nuestros terminos y condiciones'
                    : 'To start driving with ${LegalConstants.companyName} you must accept our terms and conditions',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),

              const SizedBox(height: 32),

              // Read terms button
              OutlinedButton.icon(
                onPressed: _showTerms,
                icon: const Icon(Icons.menu_book),
                label: Text(isEs ? 'Leer Documentos Legales' : 'Read Legal Documents'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  foregroundColor: primaryColor,
                  side: const BorderSide(color: primaryColor),
                ),
              ),

              const SizedBox(height: 32),

              // Age verification checkbox (21+ for drivers)
              _buildCheckbox(
                value: _isOver21,
                onChanged: (v) => setState(() => _isOver21 = v ?? false),
                title: isEs ? 'Confirmo que tengo 21 anos o mas' : 'I confirm I am 21 years or older',
                subtitle: isEs
                    ? 'Debes tener al menos 21 anos para conducir con TORO DRIVER'
                    : 'You must be at least 21 years old to drive with TORO DRIVER',
                theme: theme,
                isChecked: _isOver21,
              ),

              const SizedBox(height: 8),

              // Terms checkbox
              _buildCheckbox(
                value: _hasAcceptedTerms,
                onChanged: (v) => setState(() => _hasAcceptedTerms = v ?? false),
                title: isEs
                    ? 'Acepto todos los Terminos, Politicas y Acuerdos'
                    : 'I accept all Terms, Policies and Agreements',
                subtitle: isEs
                    ? 'Terminos de Servicio, Politica de Privacidad, Acuerdo del Conductor y Exoneracion'
                    : 'Terms of Service, Privacy Policy, Driver Agreement and Liability Waiver',
                theme: theme,
                isChecked: _hasAcceptedTerms,
              ),

              const SizedBox(height: 24),

              // Accept button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: _canAccept()
                        ? const LinearGradient(colors: [primaryColor, secondaryColor])
                        : null,
                    color: _canAccept() ? null : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: _canAccept()
                        ? [
                            BoxShadow(
                              color: primaryColor.withValues(alpha: 0.4),
                              blurRadius: 15,
                              offset: const Offset(0, 6),
                            ),
                          ]
                        : null,
                  ),
                  child: FilledButton(
                    onPressed: _canAccept() ? _onAccept : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            isEs ? 'COMENZAR A CONDUCIR' : 'START DRIVING',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Version info + language
              Text(
                'v${LegalConstants.legalBundleVersion} | ${lang.toUpperCase()}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _canAccept() {
    return _hasAcceptedTerms && _isOver21 && !_isProcessing;
  }

  Widget _buildCheckbox({
    required bool value,
    required ValueChanged<bool?> onChanged,
    required String title,
    required String subtitle,
    required ThemeData theme,
    required bool isChecked,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isChecked ? primaryColor.withValues(alpha: 0.05) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isChecked ? primaryColor.withValues(alpha: 0.3) : Colors.transparent,
        ),
      ),
      child: CheckboxListTile(
        value: value,
        onChanged: onChanged,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isChecked ? primaryColor : null,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        activeColor: primaryColor,
        checkboxShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}
