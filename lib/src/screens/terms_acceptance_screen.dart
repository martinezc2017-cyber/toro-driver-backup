import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/legal/consent_service.dart';
import '../core/legal/legal_constants.dart';
import '../core/legal/legal_documents.dart';
import '../core/logging/app_logger.dart';
import 'auth_wrapper.dart';

/// Terms Acceptance Screen for Drivers
/// Shows BEFORE login - user must accept to proceed
/// - Checkbox to accept terms
/// - Checkbox for 21+ age verification (drivers must be 21+)
/// - Checkbox for background check consent
/// - Button to read terms if driver wants
class TermsAcceptanceScreen extends StatefulWidget {
  const TermsAcceptanceScreen({super.key});

  @override
  State<TermsAcceptanceScreen> createState() => _TermsAcceptanceScreenState();
}

class _TermsAcceptanceScreenState extends State<TermsAcceptanceScreen> {
  bool _hasAcceptedTerms = false;
  bool _isOver21 = false;
  bool _isProcessing = false;

  // Theme colors
  static const Color primaryColor = Color(0xFF1E88E5);
  static const Color secondaryColor = Color(0xFF43A047);

  @override
  void initState() {
    super.initState();
    AppLogger.log('TERMS_SCREEN -> Opened (pre-login)');
  }

  Future<void> _onAccept() async {
    if (!_hasAcceptedTerms || !_isOver21 || _isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      // Save acceptance locally (before login)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AuthWrapper.termsAcceptedKey, true);

      // Record consent locally
      final consentService = ConsentService.instance;
      await consentService.initialize();
      await consentService.recordFullAcceptance(
        userId: 'pre_login_${DateTime.now().millisecondsSinceEpoch}',
        scrollPercentage: 1.0,
        timeSpentReadingMs: 0,
        ageVerified: true,
        backgroundCheckConsent: true,
      );

      AppLogger.log('LEGAL_ACCEPTED -> Pre-login acceptance (21+ verified, background check consent)');

      // Navigate to AuthWrapper - will now show LoginScreen
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

  void _showTerms() {
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
                      const Expanded(
                        child: Text(
                          'Documentos Legales',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
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
                      LegalDocuments.combinedLegalDocument,
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

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),

              // TORO Logo
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [primaryColor, secondaryColor],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: primaryColor.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/toro_logo.png',
                    width: 80,
                    height: 80,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      // Fallback to stylized "T" if image not found
                      return const Text(
                        'T',
                        style: TextStyle(
                          fontSize: 64,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontFamily: 'sans-serif',
                        ),
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
                  'Bienvenido a Toro Driver',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Subtitle
              Text(
                'Para comenzar a conducir con ${LegalConstants.companyName} debes aceptar nuestros terminos y condiciones',
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
                label: const Text('Leer Documentos Legales'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  foregroundColor: primaryColor,
                  side: const BorderSide(color: primaryColor),
                ),
              ),

              const Spacer(),

              // Age verification checkbox (21+ for drivers)
              _buildCheckbox(
                value: _isOver21,
                onChanged: (v) => setState(() => _isOver21 = v ?? false),
                title: 'Confirmo que tengo 21 anos o mas',
                subtitle: 'Debes tener al menos 21 anos para conducir con TORO DRIVER',
                theme: theme,
                isChecked: _isOver21,
              ),

              const SizedBox(height: 8),

              // Terms checkbox
              _buildCheckbox(
                value: _hasAcceptedTerms,
                onChanged: (v) => setState(() => _hasAcceptedTerms = v ?? false),
                title: 'Acepto todos los Terminos, Politicas y Acuerdos',
                subtitle: 'Terminos de Servicio, Politica de Privacidad, Acuerdo del Conductor y Exoneracion',
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
                        : const Text(
                            'COMENZAR A CONDUCIR',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Version info
              Text(
                'v${LegalConstants.legalBundleVersion}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
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
