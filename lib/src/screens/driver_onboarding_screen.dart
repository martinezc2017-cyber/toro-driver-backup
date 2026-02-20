import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/auth_provider.dart';
import '../models/driver_model.dart';
import '../services/driver_service.dart';
import '../utils/app_colors.dart';
import '../utils/haptic_service.dart';

/// Simplified 2-step onboarding for new drivers and organizers.
/// Step 0: Role Selection (Driver/Organizer) + Country (US/MX)
/// Step 1: Basic Info (Name + Phone)
///
/// Vehicle, documents, and tax info are collected later from the app
/// via /add-vehicle, /documents, and /bank-account screens.
class DriverOnboardingScreen extends StatefulWidget {
  const DriverOnboardingScreen({super.key});

  @override
  State<DriverOnboardingScreen> createState() => _DriverOnboardingScreenState();
}

class _DriverOnboardingScreenState extends State<DriverOnboardingScreen> {
  int _currentStep = 0;
  bool _isLoading = false;

  // Step 0: Role + Country
  String _selectedRole = 'driver';
  String _countryCode = 'US';

  // Step 1: Basic Info
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();

  int get _totalSteps => 2;
  bool get _isLastStep => _currentStep == _totalSteps - 1;

  @override
  void initState() {
    super.initState();
    _detectCountry();
    _prefillFromAuth();
    _firstNameController.addListener(() => setState(() {}));
    _lastNameController.addListener(() => setState(() {}));
    _phoneController.addListener(() => setState(() {}));
  }

  /// Auto-detect country from GPS only
  Future<void> _detectCountry() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
        ).timeout(const Duration(seconds: 5));
        // Mexico bounds: lat 14-33, lng -118 to -86
        if (position.latitude >= 14 && position.latitude <= 33 &&
            position.longitude >= -118 && position.longitude <= -86) {
          if (mounted) setState(() => _countryCode = 'MX');
        } else {
          if (mounted) setState(() => _countryCode = 'US');
        }
      }
    } catch (_) {}
  }

  /// Pre-fill name and phone from Google auth metadata
  void _prefillFromAuth() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final metadata = user.userMetadata;
    if (metadata != null) {
      final fullName = metadata['full_name'] as String? ??
          metadata['name'] as String? ??
          '';
      final parts = fullName.split(' ');
      if (parts.isNotEmpty && _firstNameController.text.isEmpty) {
        _firstNameController.text = parts.first;
      }
      if (parts.length > 1 && _lastNameController.text.isEmpty) {
        _lastNameController.text = parts.sublist(1).join(' ');
      }
    }

    final phone = user.phone ?? '';
    if (phone.isNotEmpty && _phoneController.text.isEmpty) {
      _phoneController.text = phone;
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (!_isLastStep) {
      if (_validateCurrentStep()) {
        HapticService.buttonPress();
        setState(() => _currentStep++);
      }
    } else {
      _submitRegistration();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      HapticService.lightImpact();
      setState(() => _currentStep--);
    }
  }

  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0:
        return true; // Role + country always valid
      case 1:
        if (_firstNameController.text.trim().isEmpty ||
            _lastNameController.text.trim().isEmpty ||
            _phoneController.text.trim().isEmpty) {
          _showError('onb_error_fill_fields'.tr());
          return false;
        }
        return true;
      default:
        return true;
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _submitRegistration() async {
    if (!_validateCurrentStep()) return;

    setState(() => _isLoading = true);
    HapticService.buttonPress();

    try {
      final driverService = DriverService();
      final authProvider = context.read<AuthProvider>();
      final currentUser = Supabase.instance.client.auth.currentUser;

      if (currentUser == null) {
        _showError('onb_error_auth'.tr());
        setState(() => _isLoading = false);
        return;
      }

      final driverId = currentUser.id;
      final now = DateTime.now();
      final fullName =
          '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
              .trim();

      final newDriver = DriverModel(
        id: driverId,
        odUserId: driverId,
        email: currentUser.email ?? '',
        phone: _phoneController.text.trim(),
        name: fullName,
        role: _selectedRole,
        status: DriverStatus.pending,
        isVerified: false,
        countryCode: _countryCode,
        createdAt: now,
        updatedAt: now,
      );

      final savedDriver = await driverService.createDriver(newDriver);

      // If organizer, create minimal organizer record
      if (_selectedRole == 'organizer') {
        try {
          await Supabase.instance.client.from('organizers').insert({
            'id': savedDriver.id,
            'user_id': savedDriver.id,
            'status': 'pending',
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          });
        } catch (_) {}
      }

      // Update AuthProvider — AuthWrapper will route to HomeScreen
      authProvider.updateDriver(savedDriver);

      if (mounted) {
        HapticService.success();
      }
    } catch (e) {
      _showError('Registration failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ─── UI ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _currentStep > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded,
                    color: AppColors.textPrimary),
                onPressed: _previousStep,
              )
            : null,
        actions: const [],
        title: Text(
          'onb_step_x_of_y'.tr(namedArgs: {
            'current': '${_currentStep + 1}',
            'total': '$_totalSteps',
          }),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              children: [
                _buildProgressIndicator(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    child: _currentStep == 0
                        ? _buildRoleSelectionStep()
                        : _buildBasicInfoStep(),
                  ),
                ),
                _buildBottomButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: List.generate(_totalSteps, (index) {
          final isActive = index <= _currentStep;
          return Expanded(
            child: Container(
              margin:
                  EdgeInsets.only(right: index < _totalSteps - 1 ? 6 : 0),
              height: 3,
              decoration: BoxDecoration(
                color: isActive ? AppColors.success : AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ─── Step 0: Role + Country ───────────────────────────────────────────

  Widget _buildRoleSelectionStep() {
    final userEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Show which email is being registered
        if (userEmail.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(Icons.email_outlined, color: AppColors.textTertiary, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    userEmail,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final authProvider = context.read<AuthProvider>();
                    await authProvider.signOut();
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Not you?',
                    style: TextStyle(
                      color: AppColors.error,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Text(
          'onb_select_role'.tr(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'onb_select_role_desc'.tr(),
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 24),
        _buildRoleCard(
          roleId: 'driver',
          title: 'onb_role_im_driver'.tr(),
          subtitle: 'onb_role_im_driver_desc'.tr(),
          icon: Icons.directions_car,
        ),
        const SizedBox(height: 16),
        _buildRoleCard(
          roleId: 'organizer',
          title: 'onb_role_im_organizer'.tr(),
          subtitle: 'onb_role_im_organizer_desc'.tr(),
          icon: Icons.business_center,
        ),
        const SizedBox(height: 32),
        Text(
          'onb_country_label'.tr(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildCountryChip('US', '\u{1F1FA}\u{1F1F8}', 'onb_country_us'.tr()),
            const SizedBox(width: 12),
            _buildCountryChip('MX', '\u{1F1F2}\u{1F1FD}', 'onb_country_mx'.tr()),
          ],
        ),
      ],
    );
  }

  Widget _buildCountryChip(String code, String flag, String label) {
    final isSelected = _countryCode == code;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticService.buttonPress();
          setState(() => _countryCode = code);
          // Switch app language based on country
          if (code == 'MX') {
            context.setLocale(const Locale('es', 'MX'));
          } else {
            context.setLocale(const Locale('en'));
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.08)
                : AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(flag, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard({
    required String roleId,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _selectedRole == roleId;
    return GestureDetector(
      onTap: () {
        HapticService.buttonPress();
        setState(() => _selectedRole = roleId);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.08)
              : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    blurRadius: 20,
                    spreadRadius: -2,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : AppColors.cardSecondary,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color:
                    isSelected ? AppColors.primary : AppColors.textTertiary,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? AppColors.primary : Colors.transparent,
                border: Border.all(
                  color:
                      isSelected ? AppColors.primary : AppColors.textTertiary,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Step 1: Basic Info ───────────────────────────────────────────────

  Widget _buildBasicInfoStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'onb_personal_title'.tr(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'onb_quick_setup_desc'.tr(),
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 20),
        _buildTextField(
          controller: _firstNameController,
          label: '${'onb_first_name'.tr()} *',
          icon: Icons.person_outline_rounded,
        ),
        const SizedBox(height: 12),
        _buildTextField(
          controller: _lastNameController,
          label: '${'onb_last_name'.tr()} *',
          icon: Icons.person_outline_rounded,
        ),
        const SizedBox(height: 12),
        _buildTextField(
          controller: _phoneController,
          label: '${'onb_phone'.tr()} *',
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 24),
        // Hint: vehicle and documents can be added later
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'onb_complete_later_hint'.tr(),
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType ?? TextInputType.text,
      textCapitalization: TextCapitalization.words,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
        prefixIcon: Icon(icon, color: AppColors.textTertiary, size: 20),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        filled: true,
        fillColor: AppColors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.success, width: 2),
        ),
      ),
    );
  }

  // ─── Bottom Button ────────────────────────────────────────────────────

  Widget _buildBottomButton() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.border),
        ),
      ),
      child: SafeArea(
        top: false,
        child: GestureDetector(
          onTap: _isLoading ? null : _nextStep,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              gradient: _isLoading ? null : AppColors.successGradient,
              color: _isLoading ? AppColors.card : null,
              borderRadius: BorderRadius.circular(12),
              boxShadow: _isLoading
                  ? null
                  : [
                      BoxShadow(
                        color: AppColors.success.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: _isLoading
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.success,
                      ),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _isLastStep
                            ? 'onb_btn_submit'.tr()
                            : 'onb_btn_continue'.tr(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        _isLastStep
                            ? Icons.send_rounded
                            : Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
