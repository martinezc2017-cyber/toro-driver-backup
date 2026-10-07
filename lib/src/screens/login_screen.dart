import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../providers/auth_provider.dart';
import '../services/biometric_service.dart';
import '../utils/app_colors.dart';
import '../widgets/toro_design_system.dart';
import '../utils/haptic_service.dart';
import '../widgets/neon_widgets.dart';
import '../core/logging/app_logger.dart';

/// Luxury Dark Login Screen for TORO Driver
/// With animated logo, city background, and biometric support
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  bool _obscurePassword = true;

  // For registration
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();

  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  final FocusNode _firstNameFocusNode = FocusNode();
  final FocusNode _lastNameFocusNode = FocusNode();
  final FocusNode _phoneFocusNode = FocusNode();

  // Biometric state
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  String _biometricName = 'Biometric';

  // Animation controllers
  late AnimationController _logoController;
  late AnimationController _pulseController;
  late AnimationController _shimmerController;
  late AnimationController _particleController;
  late AnimationController _cityLightsController;
  late AnimationController _carFlowController;

  // Animations
  late Animation<double> _shimmerAnimation;
  late Animation<double> _pulseAnimation;

  static const _prefKeyEmail = 'login_remembered_email';
  static const _prefKeyEmailHistory = 'login_email_history';
  final List<String> _emailHistory = [];
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _emailController.addListener(() => setState(() {}));
    _passwordController.addListener(() => setState(() {}));
    _firstNameController.addListener(() => setState(() {}));
    _lastNameController.addListener(() => setState(() {}));
    _phoneController.addListener(() => setState(() {}));
    AppLogger.log('OPEN -> LoginScreen');
    _loadAppVersion();
    _loadRememberedEmail();
    _checkBiometric();
    _initAnimations();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = 'v${info.version}');
    } catch (_) {
      if (mounted) setState(() => _appVersion = '');
    }
  }

  Future<void> _loadRememberedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    // Load history
    final historyList = prefs.getStringList(_prefKeyEmailHistory) ?? [];
    if (mounted) {
      setState(() {
        _emailHistory.clear();
        _emailHistory.addAll(historyList);
      });
    }
    // Pre-fill last used email
    final saved = prefs.getString(_prefKeyEmail);
    if (saved != null && saved.isNotEmpty && _emailController.text.isEmpty) {
      _emailController.text = saved;
    }
  }

  Future<void> _saveEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyEmail, email);
    // Add to history (most recent first, max 5, no duplicates)
    final history = prefs.getStringList(_prefKeyEmailHistory) ?? [];
    history.remove(email);
    history.insert(0, email);
    if (history.length > 5) history.removeLast();
    await prefs.setStringList(_prefKeyEmailHistory, history);
    if (mounted) {
      setState(() {
        _emailHistory.clear();
        _emailHistory.addAll(history);
      });
    }
  }

  void _showEmailHistoryDropdown() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.history, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'login.recent_emails'.tr(),
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ..._emailHistory.map(
              (email) => ListTile(
                leading: Icon(
                  Icons.email_outlined,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
                title: Text(
                  email,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                ),
                trailing: Icon(
                  Icons.arrow_forward_ios,
                  color: AppColors.textSecondary,
                  size: 14,
                ),
                onTap: () {
                  _emailController.text = email;
                  Navigator.pop(ctx);
                  HapticService.selectionClick();
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailSuggestions() {
    final query = _emailController.text.trim().toLowerCase();
    if (query.isEmpty || _emailHistory.isEmpty) return const SizedBox.shrink();

    final suggestions = _emailHistory
        .where(
          (e) => e.toLowerCase().contains(query) && e.toLowerCase() != query,
        )
        .toList();
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: suggestions
            .map(
              (email) => InkWell(
                onTap: () {
                  _emailController.text = email;
                  HapticService.selectionClick();
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.history, color: AppColors.primary, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          email,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.north_west,
                        color: AppColors.textSecondary,
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  void _initAnimations() {
    _logoController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    )..repeat();

    _shimmerAnimation = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.linear),
    );

    _particleController = AnimationController(
      duration: const Duration(seconds: 15),
      vsync: this,
    )..repeat();

    _cityLightsController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();

    _carFlowController = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    )..repeat();
  }

  Future<void> _checkBiometric() async {
    final available = await BiometricService.instance.isBiometricAvailable();
    final enabled = await BiometricService.instance.isBiometricEnabled();
    final name = await BiometricService.instance.getBiometricTypeName();

    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _biometricEnabled = enabled;
        _biometricName = name;
      });

      // Auto-prompt biometric if enabled
      if (available && enabled) {
        _handleBiometricLogin();
      }
    }
  }

  Future<void> _handleBiometricLogin() async {
    final authProvider = context.read<AuthProvider>();

    try {
      final credentials = await BiometricService.instance
          .getStoredCredentials();
      if (credentials != null) {
        final success = await authProvider.signIn(
          email: credentials['email']!,
          password: credentials['password']!,
        );

        if (success) {
          AppLogger.log('BIOMETRIC LOGIN -> Success');
          HapticFeedback.mediumImpact();
          // AuthWrapper handles navigation automatically via Consumer
        }
      }
    } catch (e) {
      AppLogger.log('BIOMETRIC LOGIN ERROR -> $e');
      // Don't show error for biometric - just let user login manually
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _logoController.dispose();
    _pulseController.dispose();
    _shimmerController.dispose();
    _particleController.dispose();
    _cityLightsController.dispose();
    _carFlowController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _firstNameFocusNode.dispose();
    _lastNameFocusNode.dispose();
    _phoneFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    HapticService.buttonPress();
    final authProvider = context.read<AuthProvider>();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    // Save email to history BEFORE auth (AuthWrapper may navigate away before async save completes)
    await _saveEmail(email);

    bool success;
    if (_isLogin) {
      success = await authProvider.signIn(email: email, password: password);
    } else {
      success = await authProvider.signUp(
        email: email,
        password: password,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phone: _phoneController.text.trim(),
        role: 'driver',
      );
    }

    if (success) {
      HapticService.success();

      // If this was a registration, show email confirmation message and switch to login
      if (!_isLogin) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('login.account_created_confirm'.tr()),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
          setState(() {
            _isLogin = true; // Switch to login mode
          });
        }
        return; // Don't navigate yet, user needs to confirm email
      }

      // Login successful - offer biometric setup
      if (_biometricAvailable && !_biometricEnabled && mounted) {
        await _showBiometricSetupDialog(email, password);
      }
      // AuthWrapper will automatically show the correct screen based on auth state
      // No manual navigation needed
    } else {
      HapticService.error();
      if (mounted && authProvider.error != null) {
        // Check if it's email not confirmed error - switch to login mode
        if (authProvider.error!.contains('Please confirm your email') ||
            authProvider.error!.contains('Email not confirmed')) {
          setState(() {
            _isLogin = true;
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authProvider.error!),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Future<void> _showBiometricSetupDialog(String email, String password) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _biometricName == 'Face ID' ? Icons.face : Icons.fingerprint,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'login.enable_biometric'.tr(
                  namedArgs: {'biometric': _biometricName},
                ),
                style: TextStyle(color: AppColors.textPrimary, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          'login.biometric_faster'.tr(namedArgs: {'biometric': _biometricName}),
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'not_now'.tr(),
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'login.enable'.tr(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (result == true) {
      final success = await BiometricService.instance.enableBiometric(
        email: email,
        password: password,
      );
      if (success) {
        setState(() {
          _biometricEnabled = true;
        });
        AppLogger.log('BIOMETRIC -> Setup complete');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColors.ink,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // La franja eléctrica de la marca a pantalla completa (continúa el
          // arranque); la tarjeta blanca con volumen flota encima.
          const Positioned.fill(
            child: ToroBand(overlap: 0, padding: EdgeInsets.zero, radius: 0, child: SizedBox.expand()),
          ),

          // Main content - constrained width on web for mobile-like experience
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: kIsWeb ? 420 : double.infinity,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Logo section
                          Column(
                            children: [
                              const SizedBox(height: 20),
                              _buildAnimatedLogo(),
                              const SizedBox(height: 24),
                              _buildBrandName(),
                              const SizedBox(height: 8),
                              _buildTagline(),
                              const SizedBox(height: 40),
                            ],
                          ),
                          _buildAuthCard(),
                          const SizedBox(height: 24),
                          _buildVersion(),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedLogo() {
    return const ToroLogo(size: 116);
  }


  Widget _buildBrandName() {
    return AnimatedBuilder(
      animation: _shimmerAnimation,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: const [
                Color(0xFFB0B0B0),
                Color(0xFFFFFFFF),
                Color(0xFFD0D0D0),
                Color(0xFFFFFFFF),
                Color(0xFFB0B0B0),
              ],
              stops: [
                0.0,
                (_shimmerAnimation.value - 0.2).clamp(0.0, 1.0),
                _shimmerAnimation.value.clamp(0.0, 1.0),
                (_shimmerAnimation.value + 0.2).clamp(0.0, 1.0),
                1.0,
              ],
            ).createShader(bounds);
          },
          child: const Text(
            'TORO DRIVER',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 6,
              shadows: [Shadow(color: Color(0x8035C6FF), blurRadius: 18)],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTagline() {
    return Text(
      'login.tagline'.tr(),
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: const Color(0xB8FFFFFF),
        letterSpacing: 1,
      ),
    ).animate().fadeIn(delay: 200.ms);
  }

  Widget _buildAuthCard() {
    return Container(
      width: kIsWeb ? 360 : null, // Constrain width on web
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ToroRadius.card),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(color: AppColors.edge, offset: Offset(0, 5)), ...ToroShadows.floating],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _isLogin ? Icons.login_rounded : Icons.person_add_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _isLogin
                    ? 'login.driver_sign_in'.tr()
                    : 'login.create_driver_account'.tr(),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Registration fields
          if (!_isLogin) ...[
            _buildTextField(
              controller: _firstNameController,
              label: 'login.first_name'.tr(),
              icon: Icons.person_outline_rounded,
              validator: (v) =>
                  v!.isEmpty ? 'login.enter_first_name'.tr() : null,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _lastNameController,
              label: 'login.last_name'.tr(),
              icon: Icons.person_outline_rounded,
              validator: (v) =>
                  v!.isEmpty ? 'login.enter_last_name'.tr() : null,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _phoneController,
              label: 'phone'.tr(),
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              validator: (v) => v!.isEmpty ? 'login.enter_phone'.tr() : null,
            ),
            const SizedBox(height: 12),
          ],

          // Email field
          _buildTextField(
            controller: _emailController,
            label: 'email'.tr(),
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v!.trim().isEmpty) return 'login.enter_email'.tr();
              return null;
            },
          ),
          // Autocomplete suggestions from email history
          if (_isLogin) _buildEmailSuggestions(),
          const SizedBox(height: 12),

          // Password field
          _buildPasswordField(),
          const SizedBox(height: 16),

          // Submit button
          _buildSubmitButton(),

          const SizedBox(height: 12),

          // Divider
          Row(
            children: [
              Expanded(child: Divider(color: AppColors.border)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'login.or_continue_with'.tr(),
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
              Expanded(child: Divider(color: AppColors.border)),
            ],
          ),

          const SizedBox(height: 12),

          // Platform-specific sign-in: Apple on iOS, Google on Android
          _buildPlatformSignInButton(),

          // Biometric button (only in login mode when available)
          if (_isLogin && _biometricAvailable) ...[
            const SizedBox(height: 10),
            if (_biometricEnabled)
              _buildBiometricButton()
            else
              _buildEnableBiometricOption(),
          ],

          const SizedBox(height: 12),

          // Toggle login/register
          _buildToggleMode(),

          if (_isLogin) ...[const SizedBox(height: 8), _buildForgotPassword()],
        ],
      ),
    ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    bool isEmailField =
        label.toLowerCase().contains('email') ||
        label.toLowerCase().contains('correo');
    bool isPhoneField = keyboardType == TextInputType.phone;

    // Pick the right FocusNode for this field
    final FocusNode fieldFocus = isEmailField
        ? _emailFocusNode
        : isPhoneField
        ? _phoneFocusNode
        : controller == _firstNameController
        ? _firstNameFocusNode
        : controller == _lastNameController
        ? _lastNameFocusNode
        : _emailFocusNode;

    return TextFormField(
      controller: controller,
      focusNode: fieldFocus,
      keyboardType: keyboardType,
      cursorColor: AppColors.primary,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        prefixIcon: Icon(icon, color: AppColors.primary, size: 18),
        suffixIcon: isEmailField && _emailHistory.isNotEmpty
            ? IconButton(
                icon: Icon(
                  Icons.arrow_drop_down_circle_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
                onPressed: _showEmailHistoryDropdown,
                tooltip: 'Email history',
              )
            : null,
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppColors.border.withValues(alpha: 0.5),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.error),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      focusNode: _passwordFocusNode,
      obscureText: _obscurePassword,
      cursorColor: AppColors.primary,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (v) {
        if (v!.isEmpty) return 'login.enter_password'.tr();
        if (v.length < 6) return 'login.minimum_password'.tr();
        return null;
      },
      style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: 'login.password'.tr(),
        labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        prefixIcon: Icon(
          Icons.lock_outline_rounded,
          color: AppColors.primary,
          size: 18,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_off : Icons.visibility,
            color: AppColors.textSecondary,
            size: 18,
          ),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppColors.border.withValues(alpha: 0.5),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        return NeonButton(
          text: _isLogin ? 'login.sign_in'.tr() : 'login.create_account'.tr(),
          icon: _isLogin
              ? Icons.arrow_forward_rounded
              : Icons.person_add_rounded,
          isLoading: authProvider.isLoading,
          onPressed: _submit,
          style: NeonButtonStyle.primary,
        );
      },
    );
  }

  Widget _buildBiometricButton() {
    return NeonButton(
      text: 'login.use_biometric'.tr(namedArgs: {'biometric': _biometricName}),
      icon: _biometricName == 'Face ID' ? Icons.face : Icons.fingerprint,
      onPressed: _handleBiometricLogin,
      style: NeonButtonStyle.subtle,
    );
  }

  Widget _buildGoogleButton() {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        return _GoogleNeonButton(
          text: 'login.continue_with_google'.tr(),
          isLoading: authProvider.isLoading,
          onPressed: () async {
            HapticService.buttonPress();
            await authProvider.signInWithGoogle();
          },
        );
      },
    );
  }

  Widget _buildPlatformSignInButton() {
    if (kIsWeb) return _buildGoogleButton();
    bool isIOS = false;
    try {
      isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    } catch (_) {}
    return isIOS ? _buildAppleButton() : _buildGoogleButton();
  }

  Widget _buildAppleButton() {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        return SizedBox(
          width: double.infinity,
          height: 48,
          child: SignInWithAppleButton(
            onPressed: authProvider.isLoading
                ? () {}
                : () async {
                    HapticService.buttonPress();
                    await authProvider.signInWithApple();
                  },
            text: 'continue_with_apple'.tr(),
            style: SignInWithAppleButtonStyle.whiteOutlined,
            borderRadius: BorderRadius.circular(12),
            height: 48,
          ),
        );
      },
    );
  }

  Widget _buildEnableBiometricOption() {
    return Center(
      child: TextButton.icon(
        onPressed: () async {
          if (_formKey.currentState!.validate()) {
            final email = _emailController.text.trim();
            final password = _passwordController.text;
            final authProvider = context.read<AuthProvider>();

            // Save email to history before auth (navigation may happen immediately)
            await _saveEmail(email);

            final success = await authProvider.signIn(
              email: email,
              password: password,
            );

            if (success) {
              final biometricSuccess = await BiometricService.instance
                  .enableBiometric(email: email, password: password);

              if (biometricSuccess && mounted) {
                setState(() => _biometricEnabled = true);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'login.biometric_enabled'.tr(
                        namedArgs: {'biometric': _biometricName},
                      ),
                    ),
                    backgroundColor: AppColors.success,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
                // AuthWrapper handles navigation automatically
              }
            }
          }
        },
        icon: Icon(
          _biometricName == 'Face ID' ? Icons.face_outlined : Icons.fingerprint,
          color: AppColors.textSecondary,
          size: 18,
        ),
        label: Text(
          'login.enable_biometric'.tr(namedArgs: {'biometric': _biometricName}),
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildToggleMode() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _isLogin ? 'login.no_account'.tr() : 'login.already_account'.tr(),
          style: TextStyle(color: AppColors.textSecondary),
        ),
        TextButton(
          onPressed: () {
            HapticService.selectionClick();
            setState(() => _isLogin = !_isLogin);
          },
          child: Text(
            _isLogin ? 'login.sign_up'.tr() : 'login.sign_in'.tr(),
            style: TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForgotPassword() {
    return Center(
      child: TextButton(
        onPressed: () async {
          if (_emailController.text.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('login.enter_email_first'.tr()),
                backgroundColor: AppColors.warning,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
            return;
          }

          HapticService.lightImpact();
          final authProvider = context.read<AuthProvider>();
          final success = await authProvider.resetPassword(
            _emailController.text.trim(),
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  success
                      ? 'login.recovery_sent'.tr()
                      : authProvider.error ?? 'login.recovery_error'.tr(),
                ),
                backgroundColor: success ? AppColors.success : AppColors.error,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
          }
        },
        child: Text(
          'login.forgot_password'.tr(),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ),
    );
  }

  Widget _buildVersion() {
    return Text(
      _appVersion,
      style: TextStyle(
        fontSize: 12,
        color: const Color(0xB8FFFFFF).withValues(alpha: 0.5),
        letterSpacing: 1,
      ),
    );
  }
}

// ============================================================================
// PAINTERS - City Skyline and Highway Animations
// ============================================================================

class _CitySkylinePainter extends CustomPainter {
  final double twinkleValue;

  _CitySkylinePainter({required this.twinkleValue});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final baseY = size.height * 0.55;

    final towers = [
      {'x': 0.05, 'w': 0.08, 'h': 0.25},
      {'x': 0.12, 'w': 0.05, 'h': 0.35},
      {'x': 0.18, 'w': 0.07, 'h': 0.28},
      {'x': 0.28, 'w': 0.04, 'h': 0.42},
      {'x': 0.33, 'w': 0.06, 'h': 0.30},
      {'x': 0.42, 'w': 0.05, 'h': 0.38},
      {'x': 0.50, 'w': 0.08, 'h': 0.32},
      {'x': 0.60, 'w': 0.04, 'h': 0.45},
      {'x': 0.66, 'w': 0.06, 'h': 0.28},
      {'x': 0.75, 'w': 0.05, 'h': 0.36},
      {'x': 0.82, 'w': 0.07, 'h': 0.30},
      {'x': 0.90, 'w': 0.05, 'h': 0.40},
    ];

    for (var tower in towers) {
      final x = tower['x']! * size.width;
      final w = tower['w']! * size.width;
      final h = tower['h']! * size.height;

      paint.color = const Color(0xFF0A0A0F);
      canvas.drawRect(
        Rect.fromLTWH(x, baseY - h, w, h + size.height * 0.2),
        paint,
      );

      final random = math.Random(tower.hashCode);
      for (int row = 0; row < (h / 12).floor(); row++) {
        for (int col = 0; col < (w / 6).floor(); col++) {
          if (random.nextDouble() > 0.4) {
            final twinkle =
                (math.sin((twinkleValue + random.nextDouble()) * math.pi * 2) +
                    1) /
                2;
            final opacity =
                0.2 + (twinkle * 0.5) * (random.nextDouble() > 0.7 ? 1 : 0.3);

            paint.color = Color.lerp(
              const Color(0xFFFFE4AA),
              const Color(0xFF6A8AAA),
              random.nextDouble(),
            )!.withValues(alpha: opacity);

            canvas.drawRect(
              Rect.fromLTWH(x + 3 + col * 6, baseY - h + 8 + row * 12, 3, 4),
              paint,
            );
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CitySkylinePainter oldDelegate) {
    return oldDelegate.twinkleValue != twinkleValue;
  }
}

class _HighwayPainter extends CustomPainter {
  final double carProgress;

  _HighwayPainter({required this.carProgress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final baseY = size.height * 0.65;

    paint.color = const Color(0xFF1A1A1A);
    canvas.drawRect(
      Rect.fromLTWH(0, baseY, size.width, size.height * 0.15),
      paint,
    );

    paint.color = AppColors.border;
    paint.strokeWidth = 2;
    canvas.drawLine(
      Offset(0, baseY + size.height * 0.05),
      Offset(size.width, baseY + size.height * 0.05),
      paint,
    );
    canvas.drawLine(
      Offset(0, baseY + size.height * 0.10),
      Offset(size.width, baseY + size.height * 0.10),
      paint,
    );

    paint.color = AppColors.borderStrong;
    for (double x = 0; x < size.width; x += 30) {
      canvas.drawLine(
        Offset(x, baseY + size.height * 0.075),
        Offset(x + 15, baseY + size.height * 0.075),
        paint,
      );
    }

    // Cars going right (tail lights - red)
    for (int i = 0; i < 6; i++) {
      final offset = ((carProgress + i * 0.15) % 1.0);
      final x = offset * size.width * 1.3 - size.width * 0.15;
      final y = baseY + size.height * 0.03 + (i % 2) * size.height * 0.04;

      paint.color = const Color(0xFFAA3030).withValues(alpha: 0.8);
      canvas.drawCircle(Offset(x, y), 2, paint);
      canvas.drawCircle(Offset(x + 4, y), 2, paint);

      final trailPaint = Paint()
        ..shader = ui.Gradient.linear(Offset(x - 30, y), Offset(x, y), [
          Colors.transparent,
          const Color(0xFFAA3030).withValues(alpha: 0.3),
        ]);
      canvas.drawRect(Rect.fromLTWH(x - 30, y - 1, 30, 2), trailPaint);
    }

    // Cars going left (headlights - white)
    for (int i = 0; i < 5; i++) {
      final offset = 1.0 - ((carProgress + i * 0.18) % 1.0);
      final x = offset * size.width * 1.3 - size.width * 0.15;
      final y = baseY + size.height * 0.11 + (i % 2) * size.height * 0.02;

      paint.color = const Color(0xFFEEEEFF).withValues(alpha: 0.9);
      canvas.drawCircle(Offset(x, y), 2.5, paint);
      canvas.drawCircle(Offset(x - 5, y), 2.5, paint);

      final glowPaint = Paint()
        ..shader = ui.Gradient.radial(Offset(x, y), 15, [
          const Color(0xFFEEEEFF).withValues(alpha: 0.2),
          Colors.transparent,
        ]);
      canvas.drawCircle(Offset(x, y), 15, glowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _HighwayPainter oldDelegate) {
    return oldDelegate.carProgress != carProgress;
  }
}

// ============================================================================
// GOOGLE NEON BUTTON - Special styling for Google Sign In
// ============================================================================
class _GoogleNeonButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;

  const _GoogleNeonButton({
    required this.text,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  State<_GoogleNeonButton> createState() => _GoogleNeonButtonState();
}

class _GoogleNeonButtonState extends State<_GoogleNeonButton>
    with SingleTickerProviderStateMixin {
  bool _isPressed = false;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.isLoading
          ? null
          : () {
              HapticFeedback.mediumImpact();
              widget.onPressed?.call();
            },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final value = _controller.value;
          final beginX = -3.0 + (value * 6.0);
          final endX = -1.0 + (value * 6.0);

          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 54,
            transform: Matrix4.diagonal3Values(
              _isPressed ? 0.98 : 1.0,
              _isPressed ? 0.98 : 1.0,
              1.0,
            ),
            transformAlignment: Alignment.center,
            decoration: ToroRaised.decoration(ToroTone.white),
            child: Container(
              margin: EdgeInsets.zero,
              decoration: const BoxDecoration(),
              child: Center(
                child: widget.isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.textPrimary,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Google G logo
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: const Center(
                              child: Text(
                                'G',
                                style: TextStyle(
                                  color: Color(0xFF4285F4),
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            widget.text,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}
