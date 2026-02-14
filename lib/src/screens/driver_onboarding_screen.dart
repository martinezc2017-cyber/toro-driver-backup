import 'dart:io' show Platform;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/auth_provider.dart';
import '../models/driver_model.dart';
import '../services/driver_service.dart';
import '../services/document_ocr_service.dart';
import '../utils/app_colors.dart';
import '../utils/haptic_service.dart';
/// Multi-step onboarding for new drivers and organizers
/// Step 0: Role Selection (Driver or Organizer)
/// Driver path:    Step 1: Personal Info -> Step 2: Vehicle -> Step 3: Documents -> Step 4: Tax (W-9)
/// Organizer path: Step 1: Personal Info -> Step 2: Organizer Info -> Step 3: Tax (W-9)
class DriverOnboardingScreen extends StatefulWidget {
  const DriverOnboardingScreen({super.key});

  @override
  State<DriverOnboardingScreen> createState() => _DriverOnboardingScreenState();
}

class _DriverOnboardingScreenState extends State<DriverOnboardingScreen> {
  int _currentStep = 0;
  bool _isLoading = false;

  // Step 0: Role Selection
  String _selectedRole = 'driver'; // 'driver' or 'organizer'
  String _countryCode = 'MX'; // 'US' or 'MX' - auto-detected, user can override
  bool get _isMexico => _countryCode == 'MX';

  // Organizer-specific controllers
  final _orgCompanyNameController = TextEditingController();
  final _orgPhoneController = TextEditingController();
  final _orgStateController = TextEditingController();

  // Step 1: Personal Info
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  DateTime? _birthDate;

  // Step 2: Vehicle Info
  final _vehicleMakeController = TextEditingController();
  final _vehicleModelController = TextEditingController();
  final _vehicleYearController = TextEditingController();
  final _vehicleColorController = TextEditingController();
  final _licensePlateController = TextEditingController();
  String _vehicleType = 'sedan';

  // Step 3: Documents (store as bytes for web compatibility)
  Uint8List? _profilePhoto;
  Uint8List? _driverLicense;
  Uint8List? _vehicleRegistration;
  Uint8List? _insuranceCard;
  Uint8List? _vehicleInspectionReport; // Required for vehicles 2012-2017

  // Step 3: Background Check Consent
  bool _acceptsBackgroundCheck = false;

  // Step 4: Tax Information (W-9 for US, SAT for MX)
  final _ssnController = TextEditingController();
  final _legalNameController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _streetAddressController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _zipCodeController = TextEditingController();
  String _taxClassification = 'individual'; // individual, llc_single, llc_partnership, corporation
  bool _certifyW9 = false;

  // Mexico tax fields
  final _rfcController = TextEditingController();
  final _curpController = TextEditingController();
  String _satRegime = 'pfae'; // pfae, resico, moral
  bool _certifySAT = false;

  // OCR extraction results (ML Kit - offline, free)
  final DocumentOcrService _ocrService = DocumentOcrService();
  DriverLicenseData? _licenseOcrData;
  InsuranceCardData? _insuranceOcrData;
  bool _isVerifying = false;

  final _imagePicker = ImagePicker();

  // Vehicle year validation
  int? get _vehicleYear {
    final yearText = _vehicleYearController.text.trim();
    if (yearText.isEmpty) return null;
    return int.tryParse(yearText);
  }

  bool get _requiresInspectionReport {
    final year = _vehicleYear;
    if (year == null) return false;
    return year >= 2012 && year <= 2017;
  }

  bool get _vehicleTooOld {
    final year = _vehicleYear;
    if (year == null) return false;
    return year < 2012;
  }

  /// Total number of steps based on role
  /// Driver: roleSelect, personal, vehicle, documents, tax = 5
  /// Organizer: roleSelect, personal, organizerInfo, tax = 4
  int get _totalSteps => _selectedRole == 'organizer' ? 4 : 5;

  /// Whether the current step index is the last step
  bool get _isLastStep => _currentStep == _totalSteps - 1;

  @override
  void initState() {
    super.initState();
    _detectCountry();
    // Listen to year changes to update UI for inspection report requirement
    _vehicleYearController.addListener(_onYearChanged);
    // Add listeners for text fields to trigger UI updates
    _firstNameController.addListener(() => setState(() {}));
    _lastNameController.addListener(() => setState(() {}));
    _phoneController.addListener(() => setState(() {}));
    _addressController.addListener(() => setState(() {}));
    _vehicleMakeController.addListener(() => setState(() {}));
    _vehicleModelController.addListener(() => setState(() {}));
    _vehicleColorController.addListener(() => setState(() {}));
    _licensePlateController.addListener(() => setState(() {}));
    _orgCompanyNameController.addListener(() => setState(() {}));
    _orgPhoneController.addListener(() => setState(() {}));
    _orgStateController.addListener(() => setState(() {}));
    _ssnController.addListener(() => setState(() {}));
    _legalNameController.addListener(() => setState(() {}));
    _businessNameController.addListener(() => setState(() {}));
    _streetAddressController.addListener(() => setState(() {}));
    _cityController.addListener(() => setState(() {}));
    _stateController.addListener(() => setState(() {}));
    _zipCodeController.addListener(() => setState(() {}));
  }

  void _onYearChanged() {
    // Rebuild to show/hide warnings and inspection report field
    setState(() {});
  }

  /// Auto-detect country from device locale (e.g. es_MX → MX, en_US → US)
  void _detectCountry() {
    try {
      if (!kIsWeb) {
        final locale = Platform.localeName; // e.g. "es_MX", "en_US"
        final parts = locale.split('_');
        if (parts.length >= 2) {
          final region = parts.last.toUpperCase();
          if (region == 'MX') {
            _countryCode = 'MX';
          }
        }
      }
    } catch (_) {
      // Fallback: keep default US
    }
  }

  @override
  void dispose() {
    _vehicleYearController.removeListener(_onYearChanged);
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _vehicleMakeController.dispose();
    _vehicleModelController.dispose();
    _vehicleYearController.dispose();
    _vehicleColorController.dispose();
    _licensePlateController.dispose();
    // Organizer controllers
    _orgCompanyNameController.dispose();
    _orgPhoneController.dispose();
    _orgStateController.dispose();
    // W-9 controllers
    _ssnController.dispose();
    _legalNameController.dispose();
    _businessNameController.dispose();
    _streetAddressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _zipCodeController.dispose();
    // MX tax controllers
    _rfcController.dispose();
    _curpController.dispose();
    _ocrService.dispose();
    super.dispose();
  }

  Future<void> _pickImage(String type) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );

      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() {
          switch (type) {
            case 'profile':
              _profilePhoto = bytes;
              break;
            case 'license':
              _driverLicense = bytes;
              break;
            case 'registration':
              _vehicleRegistration = bytes;
              break;
            case 'insurance':
              _insuranceCard = bytes;
              break;
            case 'inspection':
              _vehicleInspectionReport = bytes;
              break;
          }
        });
        HapticService.lightImpact();

        // Run OCR verification for documents (not on web)
        if (!kIsWeb && (type == 'license' || type == 'registration' || type == 'insurance')) {
          _verifyDocument(type, picked.path);
        }
      }
    } catch (e) {
      //Error picking image: $e');
    }
  }

  /// Extract data from document using ML Kit OCR (offline, free)
  Future<void> _verifyDocument(String type, String imagePath) async {
    if (!_ocrService.isAvailable) {
      //OCR not available on this platform');
      return;
    }

    setState(() => _isVerifying = true);

    try {
      switch (type) {
        case 'license':
          final licenseData = await _ocrService.extractFromLicense(XFile(imagePath));
          setState(() => _licenseOcrData = licenseData);

          // Auto-fill name if extracted and fields are empty
          if (licenseData?.fullName != null) {
            final nameParts = licenseData!.fullName!.split(' ');
            if (_firstNameController.text.isEmpty && nameParts.isNotEmpty) {
              _firstNameController.text = nameParts.first;
            }
            if (_lastNameController.text.isEmpty && nameParts.length > 1) {
              _lastNameController.text = nameParts.sublist(1).join(' ');
            }
          }
          break;

        case 'insurance':
          final insuranceData = await _ocrService.extractFromImage(XFile(imagePath));
          setState(() => _insuranceOcrData = insuranceData);

          // Auto-fill vehicle info if extracted and fields are empty
          if (insuranceData != null) {
            if (insuranceData.vehicleMake != null && _vehicleMakeController.text.isEmpty) {
              _vehicleMakeController.text = insuranceData.vehicleMake!;
            }
            if (insuranceData.vehicleModel != null && _vehicleModelController.text.isEmpty) {
              _vehicleModelController.text = insuranceData.vehicleModel!;
            }
            if (insuranceData.vehicleYear != null && _vehicleYearController.text.isEmpty) {
              _vehicleYearController.text = insuranceData.vehicleYear.toString();
            }
          }
          break;

        case 'registration':
          // Registration uses same insurance parser for VIN extraction
          final regData = await _ocrService.extractFromImage(XFile(imagePath));
          // Auto-fill VIN if found (but no separate state variable needed)
          //Registration OCR: VIN=${regData?.vin}');
          break;
      }

      // Show extraction result
      if (mounted) {
        _showVerificationResult(type);
      }
    } catch (e) {
      //Document OCR error: $e');
    } finally {
      if (mounted) {
        setState(() => _isVerifying = false);
      }
    }
  }

  /// Show OCR extraction result to user
  void _showVerificationResult(String type) {
    String docName;
    bool hasData = false;
    String? extractedInfo;
    DateTime? expiryDate;

    switch (type) {
      case 'license':
        docName = 'onb_doc_license'.tr();
        hasData = _licenseOcrData?.hasAnyData ?? false;
        if (_licenseOcrData != null) {
          extractedInfo = _licenseOcrData!.licenseNumber;
          expiryDate = _licenseOcrData!.expiryDate;
        }
        break;
      case 'registration':
        docName = 'onb_doc_registration'.tr();
        hasData = true; // Registration doesn't have specific data to extract
        break;
      case 'insurance':
        docName = 'onb_doc_insurance'.tr();
        hasData = _insuranceOcrData?.hasAnyData ?? false;
        if (_insuranceOcrData != null) {
          extractedInfo = _insuranceOcrData!.policyNumber ?? _insuranceOcrData!.insuranceCompany;
          expiryDate = _insuranceOcrData!.expiryDate;
        }
        break;
      default:
        return;
    }

    Color bgColor;
    IconData icon;
    String message;

    if (hasData && extractedInfo != null) {
      // Check if document is expired
      if (expiryDate != null && expiryDate.isBefore(DateTime.now())) {
        bgColor = AppColors.error;
        icon = Icons.error_outline;
        message = '$docName appears EXPIRED (${_formatDate(expiryDate)})';
        HapticService.error();
      } else {
        bgColor = AppColors.success;
        icon = Icons.check_circle_outline;
        final expText = expiryDate != null ? ' • Exp: ${_formatDate(expiryDate)}' : '';
        message = '$docName: $extractedInfo$expText';
        HapticService.success();
      }
    } else if (hasData) {
      bgColor = AppColors.primary;
      icon = Icons.document_scanner;
      message = '$docName uploaded. Admin will verify.';
    } else {
      bgColor = AppColors.warning;
      icon = Icons.help_outline;
      message = 'Could not read $docName. Try a clearer photo.';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return '${date.month}/${date.day}/${date.year}';
  }

  void _nextStep() {
    if (!_isLastStep) {
      if (_validateCurrentStep()) {
        HapticService.buttonPress();
        setState(() => _currentStep++);
        // Auto-fill W-9 legal name from personal info when entering tax step
        if (_isLastStep && _legalNameController.text.isEmpty) {
          _legalNameController.text = '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'.trim();
        }
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

  /// Map the current step index to the logical step name based on role
  String get _currentStepName {
    if (_selectedRole == 'organizer') {
      // Organizer: 0=roleSelect, 1=personal, 2=organizerInfo, 3=tax
      switch (_currentStep) {
        case 0: return 'roleSelect';
        case 1: return 'personal';
        case 2: return 'organizerInfo';
        case 3: return 'tax';
        default: return 'unknown';
      }
    } else {
      // Driver: 0=roleSelect, 1=personal, 2=vehicle, 3=documents, 4=tax
      switch (_currentStep) {
        case 0: return 'roleSelect';
        case 1: return 'personal';
        case 2: return 'vehicle';
        case 3: return 'documents';
        case 4: return 'tax';
        default: return 'unknown';
      }
    }
  }

  bool _validateCurrentStep() {
    switch (_currentStepName) {
      case 'roleSelect':
        // Always valid - just selecting a role
        return true;
      case 'personal':
        if (_firstNameController.text.isEmpty ||
            _lastNameController.text.isEmpty ||
            _phoneController.text.isEmpty) {
          _showError('onb_error_fill_fields'.tr());
          return false;
        }
        return true;
      case 'vehicle':
        if (_vehicleMakeController.text.isEmpty ||
            _vehicleModelController.text.isEmpty ||
            _licensePlateController.text.isEmpty) {
          _showError('onb_error_vehicle_fields'.tr());
          return false;
        }
        // Validate vehicle year
        if (_vehicleYearController.text.isNotEmpty) {
          final year = _vehicleYear;
          if (year == null) {
            _showError('onb_error_valid_year'.tr());
            return false;
          }
          if (year < 2012) {
            _showError('onb_vehicle_old_error'.tr());
            return false;
          }
          final currentYear = DateTime.now().year;
          if (year > currentYear + 1) {
            _showError('onb_error_valid_year'.tr());
            return false;
          }
        }
        return true;
      case 'documents':
        if (_profilePhoto == null || _driverLicense == null) {
          _showError('onb_error_docs_upload'.tr());
          return false;
        }
        // Vehicle Inspection Report required for 2012-2017 vehicles
        if (_requiresInspectionReport && _vehicleInspectionReport == null) {
          _showError('onb_error_inspection'.tr());
          return false;
        }
        // Background check consent is required
        if (!_acceptsBackgroundCheck) {
          _showError('onb_error_bg_check'.tr());
          return false;
        }
        return true;
      case 'organizerInfo':
        if (_orgCompanyNameController.text.isEmpty) {
          _showError('onb_error_company'.tr());
          return false;
        }
        if (_orgPhoneController.text.isEmpty) {
          _showError('onb_error_phone'.tr());
          return false;
        }
        if (_orgStateController.text.isEmpty) {
          _showError('onb_error_state'.tr());
          return false;
        }
        return true;
      case 'tax':
        if (_isMexico) {
          return _validateMexicoTax();
        }
        return _validateUSTax();
      default:
        return true;
    }
  }

  bool _validateUSTax() {
    if (_ssnController.text.isEmpty) {
      _showError('onb_error_ssn_required'.tr());
      return false;
    }
    final ssnDigits = _ssnController.text.replaceAll(RegExp(r'\D'), '');
    if (ssnDigits.length != 9) {
      _showError('onb_error_ssn'.tr());
      return false;
    }
    if (_legalNameController.text.isEmpty) {
      _showError('onb_error_required'.tr());
      return false;
    }
    if (_streetAddressController.text.isEmpty ||
        _cityController.text.isEmpty ||
        _stateController.text.isEmpty ||
        _zipCodeController.text.isEmpty) {
      _showError('onb_error_address'.tr());
      return false;
    }
    if (!_certifyW9) {
      _showError('onb_error_certify_w9'.tr());
      return false;
    }
    return true;
  }

  bool _validateMexicoTax() {
    final rfc = _rfcController.text.trim();
    if (rfc.isEmpty) {
      _showError('onb_error_rfc'.tr());
      return false;
    }
    // RFC: 12 chars (moral) or 13 chars (física)
    if (!RegExp(r'^[A-ZÑ&]{3,4}\d{6}[A-Z0-9]{3}$').hasMatch(rfc)) {
      _showError('onb_tax_rfc_error'.tr());
      return false;
    }
    final curp = _curpController.text.trim();
    if (curp.isEmpty) {
      _showError('onb_error_curp'.tr());
      return false;
    }
    if (curp.length != 18) {
      _showError('onb_tax_curp_error'.tr());
      return false;
    }
    if (_legalNameController.text.isEmpty) {
      _showError('onb_error_required'.tr());
      return false;
    }
    if (_streetAddressController.text.isEmpty ||
        _cityController.text.isEmpty ||
        _stateController.text.isEmpty ||
        _zipCodeController.text.isEmpty) {
      _showError('onb_error_required'.tr());
      return false;
    }
    if (!_certifySAT) {
      _showError('onb_error_certify_sat'.tr());
      return false;
    }
    return true;
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

      // Get current user from Supabase
      final currentUser = Supabase.instance.client.auth.currentUser;
      //ONBOARDING -> currentUser: ${currentUser?.email ?? "NULL"}');

      if (currentUser == null) {
        _showError('onb_error_auth'.tr());
        setState(() => _isLoading = false);
        return;
      }

      // Use Supabase auth user ID as driver ID (must match for profile lookup)
      final driverId = currentUser.id;
      final now = DateTime.now();
      //ONBOARDING -> Creating driver with ID: $driverId');

      // Create driver model with pending status
      final fullName = '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'.trim();
      final isOrganizer = _selectedRole == 'organizer';
      final newDriver = DriverModel(
        id: driverId,
        odUserId: driverId,
        email: currentUser.email ?? '',
        phone: _phoneController.text.trim(),
        name: fullName,
        vehicleType: isOrganizer ? null : _vehicleType,
        vehiclePlate: isOrganizer ? null : _licensePlateController.text.trim(),
        vehicleModel: isOrganizer ? null : '${_vehicleMakeController.text.trim()} ${_vehicleModelController.text.trim()}'.trim(),
        role: _selectedRole,
        status: DriverStatus.pending,
        isVerified: false,
        countryCode: _countryCode,
        createdAt: now,
        updatedAt: now,
      );

      //ONBOARDING -> Saving to database...');
      // Save driver to database
      final savedDriver = await driverService.createDriver(newDriver);
      //ONBOARDING -> Driver saved successfully: ${savedDriver.id}');

      // Save tax information based on country
      if (_isMexico) {
        await driverService.saveMexicoTaxInfo(
          driverId: savedDriver.id,
          rfc: _rfcController.text.trim(),
          curp: _curpController.text.trim(),
          satRegime: _satRegime,
          legalName: _legalNameController.text.trim(),
          businessName: _businessNameController.text.trim().isNotEmpty
              ? _businessNameController.text.trim()
              : null,
          streetAddress: _streetAddressController.text.trim(),
          city: _cityController.text.trim(),
          state: _stateController.text.trim(),
          zipCode: _zipCodeController.text.trim(),
          certificationSigned: _certifySAT,
        );
      } else {
        await driverService.saveW9TaxInfo(
          driverId: savedDriver.id,
          ssn: _ssnController.text,
          legalName: _legalNameController.text.trim(),
          businessName: _businessNameController.text.trim().isNotEmpty
              ? _businessNameController.text.trim()
              : null,
          taxClassification: _taxClassification,
          streetAddress: _streetAddressController.text.trim(),
          city: _cityController.text.trim(),
          state: _stateController.text.trim().toUpperCase(),
          zipCode: _zipCodeController.text.trim(),
          certificationSigned: _certifyW9,
        );
      }

      // If organizer, also insert into organizers table
      if (isOrganizer) {
        //ONBOARDING -> Saving organizer info...');
        try {
          await Supabase.instance.client.from('organizers').insert({
            'id': savedDriver.id,
            'user_id': savedDriver.id,
            'company_name': _orgCompanyNameController.text.trim(),
            'phone': _orgPhoneController.text.trim(),
            'state': _orgStateController.text.trim(),
            'status': 'pending',
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          });
          //ONBOARDING -> Organizer info saved successfully');
        } catch (e) {
          //ONBOARDING -> Organizer insert error (non-fatal): $e');
        }
      }

      // Update AuthProvider with the new driver
      authProvider.updateDriver(savedDriver);
      //ONBOARDING -> AuthProvider updated');

      if (mounted) {
        HapticService.success();
        // Navigate to pending approval
        Navigator.of(context).pushNamedAndRemoveUntil('/pending', (route) => false);
      }
    } catch (e, stackTrace) {
      //ONBOARDING ERROR -> $e');
      //ONBOARDING STACK -> $stackTrace');
      _showError('Registration failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: _currentStep > 0 ? _previousStep : () => Navigator.pop(context),
        ),
        title: Text(
          'onb_step_x_of_y'.tr(namedArgs: {'current': '${_currentStep + 1}', 'total': '$_totalSteps'}),
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
                // Progress indicator
                _buildProgressIndicator(),

                // Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: _buildStepContent(),
                  ),
                ),

                // Bottom button
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
              margin: EdgeInsets.only(right: index < _totalSteps - 1 ? 6 : 0),
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

  Widget _buildStepContent() {
    switch (_currentStepName) {
      case 'roleSelect':
        return _buildRoleSelectionStep();
      case 'personal':
        return _buildPersonalInfoStep();
      case 'vehicle':
        return _buildVehicleInfoStep();
      case 'documents':
        return _buildDocumentsStep();
      case 'organizerInfo':
        return _buildOrganizerInfoStep();
      case 'tax':
        return _buildTaxInfoStep();
      default:
        return const SizedBox();
    }
  }

  Widget _buildRoleSelectionStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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

        // Country selector
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
            _buildCountryChip('US', '🇺🇸', 'onb_country_us'.tr()),
            const SizedBox(width: 12),
            _buildCountryChip('MX', '🇲🇽', 'onb_country_mx'.tr()),
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
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary.withValues(alpha: 0.08) : AppColors.card,
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
                  color: isSelected ? AppColors.primary : AppColors.textSecondary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
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
                color: isSelected ? AppColors.primary : AppColors.textTertiary,
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
                  color: isSelected ? AppColors.primary : AppColors.textTertiary,
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

  Widget _buildOrganizerInfoStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'onb_org_title'.tr(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'onb_org_desc'.tr(),
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 20),

        _buildTextField(
          controller: _orgCompanyNameController,
          label: '${'onb_org_company'.tr()} *',
          icon: Icons.business_outlined,
          hint: 'onb_org_company_hint'.tr(),
          fieldName: 'orgCompanyName',
        ),
        const SizedBox(height: 12),

        _buildTextField(
          controller: _orgPhoneController,
          label: '${'onb_org_phone'.tr()} *',
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          fieldName: 'orgPhone',
        ),
        const SizedBox(height: 12),

        _buildTextField(
          controller: _orgStateController,
          label: '${'onb_org_state'.tr()} *',
          icon: Icons.map_outlined,
          hint: 'onb_org_state_hint'.tr(),
          fieldName: 'orgState',
        ),
      ],
    );
  }

  Widget _buildPersonalInfoStep() {
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
          'onb_personal_desc'.tr(),
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
          fieldName: 'firstName',
        ),
        const SizedBox(height: 12),

        _buildTextField(
          controller: _lastNameController,
          label: '${'onb_last_name'.tr()} *',
          icon: Icons.person_outline_rounded,
          fieldName: 'lastName',
        ),
        const SizedBox(height: 12),

        _buildTextField(
          controller: _phoneController,
          label: '${'onb_phone'.tr()} *',
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          fieldName: 'phone',
        ),
        const SizedBox(height: 12),

        _buildTextField(
          controller: _addressController,
          label: 'onb_address'.tr(),
          icon: Icons.location_on_outlined,
          fieldName: 'address',
        ),
        const SizedBox(height: 12),

        _buildDatePicker(),
      ],
    );
  }

  Widget _buildVehicleInfoStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'onb_vehicle_title'.tr(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'onb_vehicle_desc'.tr(),
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 20),

        // Vehicle Type
        _buildVehicleTypeSelector(),
        const SizedBox(height: 16),

        _buildTextField(
          controller: _vehicleMakeController,
          label: '${'onb_vehicle_make'.tr()} *',
          icon: Icons.directions_car_outlined,
          hint: 'onb_vehicle_make_hint'.tr(),
          fieldName: 'vehicleMake',
        ),
        const SizedBox(height: 12),

        _buildTextField(
          controller: _vehicleModelController,
          label: '${'onb_vehicle_model'.tr()} *',
          icon: Icons.directions_car_outlined,
          hint: 'onb_vehicle_model_hint'.tr(),
          fieldName: 'vehicleModel',
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _vehicleYearController,
                label: 'onb_vehicle_year'.tr(),
                icon: Icons.calendar_today_outlined,
                keyboardType: TextInputType.number,
                hint: 'onb_vehicle_year_hint'.tr(),
                fieldName: 'vehicleYear',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTextField(
                controller: _vehicleColorController,
                label: 'onb_vehicle_color'.tr(),
                icon: Icons.palette_outlined,
                hint: 'onb_vehicle_color_hint'.tr(),
                fieldName: 'vehicleColor',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        _buildTextField(
          controller: _licensePlateController,
          label: '${'onb_vehicle_plate'.tr()} *',
          icon: Icons.credit_card_outlined,
          textCapitalization: TextCapitalization.characters,
          fieldName: 'licensePlate',
        ),

        // Warning for old vehicles
        if (_vehicleTooOld) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: AppColors.error, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'onb_vehicle_old_error'.tr(),
                    style: TextStyle(
                      color: AppColors.error,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Notice for 2012-2017 vehicles requiring inspection
        if (_requiresInspectionReport) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.warning, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'onb_vehicle_inspection_notice'.tr(),
                    style: TextStyle(
                      color: AppColors.warning,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDocumentsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'onb_doc_title'.tr(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'onb_doc_subtitle'.tr(),
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 20),

        _buildDocumentUpload(
          title: '${'onb_doc_photo'.tr()} *',
          subtitle: 'onb_doc_photo_desc'.tr(),
          icon: Icons.face_rounded,
          imageBytes: _profilePhoto,
          onTap: () => _pickImage('profile'),
        ),
        const SizedBox(height: 10),

        _buildDocumentUpload(
          title: '${'onb_doc_license'.tr()} *',
          subtitle: 'onb_doc_license_front'.tr(),
          icon: Icons.badge_outlined,
          imageBytes: _driverLicense,
          onTap: () => _pickImage('license'),
          ocrExtracted: _licenseOcrData?.hasAnyData ?? false,
          extractedText: _licenseOcrData?.licenseNumber,
          expiryDate: _licenseOcrData?.expiryDate,
        ),
        const SizedBox(height: 10),

        _buildDocumentUpload(
          title: 'onb_doc_registration'.tr(),
          subtitle: 'onb_doc_registration_desc'.tr(),
          icon: Icons.description_outlined,
          imageBytes: _vehicleRegistration,
          onTap: () => _pickImage('registration'),
        ),
        const SizedBox(height: 10),

        _buildDocumentUpload(
          title: 'onb_doc_insurance'.tr(),
          subtitle: 'onb_doc_insurance_desc'.tr(),
          icon: Icons.security_outlined,
          imageBytes: _insuranceCard,
          onTap: () => _pickImage('insurance'),
          ocrExtracted: _insuranceOcrData?.hasAnyData ?? false,
          extractedText: _insuranceOcrData?.policyNumber ?? _insuranceOcrData?.insuranceCompany,
          expiryDate: _insuranceOcrData?.expiryDate,
        ),

        // Vehicle Inspection Report - only for vehicles 2012-2017
        if (_requiresInspectionReport) ...[
          const SizedBox(height: 10),
          _buildDocumentUpload(
            title: '${'onb_vehicle_inspection_title'.tr()} *',
            subtitle: 'onb_vehicle_inspection_desc'.tr(),
            icon: Icons.assignment_outlined,
            imageBytes: _vehicleInspectionReport,
            onTap: () => _pickImage('inspection'),
            isRequired: true,
          ),
        ],

        const SizedBox(height: 20),

        // Background Check Consent
        _buildBackgroundCheckConsent(),
      ],
    );
  }

  Widget _buildBackgroundCheckConsent() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _acceptsBackgroundCheck
            ? AppColors.success.withValues(alpha: 0.1)
            : AppColors.warning.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _acceptsBackgroundCheck
              ? AppColors.success
              : AppColors.warning.withValues(alpha: 0.5),
          width: _acceptsBackgroundCheck ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.verified_user_outlined,
                color: _acceptsBackgroundCheck ? AppColors.success : AppColors.warning,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '${'onb_bg_check_title'.tr()} *',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'onb_bg_check_desc'.tr(),
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              HapticService.lightImpact();
              setState(() => _acceptsBackgroundCheck = !_acceptsBackgroundCheck);
            },
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: _acceptsBackgroundCheck ? AppColors.success : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: _acceptsBackgroundCheck ? AppColors.success : AppColors.textTertiary,
                      width: 2,
                    ),
                  ),
                  child: _acceptsBackgroundCheck
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'onb_bg_check_agree'.tr(),
                    style: TextStyle(
                      color: _acceptsBackgroundCheck ? AppColors.success : AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: _acceptsBackgroundCheck ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaxInfoStep() {
    return _isMexico ? _buildMexicoTaxStep() : _buildUSTaxStep();
  }

  Widget _buildUSTaxStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'onb_tax_title_us'.tr(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'onb_tax_subtitle_us'.tr(),
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.security_outlined, color: AppColors.warning, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'onb_tax_ssn_note'.tr(),
                  style: TextStyle(
                    color: AppColors.warning,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // SSN Field with masking
        _buildSSNField(),
        const SizedBox(height: 12),

        _buildTextField(
          controller: _legalNameController,
          label: '${'onb_tax_legal_name'.tr()} *',
          icon: Icons.person_outline,
          fieldName: 'legalName',
        ),
        const SizedBox(height: 12),

        _buildTextField(
          controller: _businessNameController,
          label: 'onb_tax_business_name'.tr(),
          icon: Icons.business_outlined,
          hint: 'onb_tax_business_hint'.tr(),
          fieldName: 'businessName',
        ),
        const SizedBox(height: 12),

        // Tax Classification
        _buildTaxClassificationSelector(),
        const SizedBox(height: 16),

        // Mailing Address Section
        Text(
          'onb_tax_address'.tr(),
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),

        _buildTextField(
          controller: _streetAddressController,
          label: '${'onb_address'.tr()} *',
          icon: Icons.home_outlined,
          fieldName: 'streetAddress',
        ),
        const SizedBox(height: 10),

        Row(
          children: [
            Expanded(
              flex: 2,
              child: _buildTextField(
                controller: _cityController,
                label: '${'onb_city'.tr()} *',
                icon: Icons.location_city_outlined,
                fieldName: 'city',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildTextField(
                controller: _stateController,
                label: '${'onb_state'.tr()} *',
                icon: Icons.map_outlined,
                hint: 'onb_state_hint_us'.tr(),
                textCapitalization: TextCapitalization.characters,
                fieldName: 'state',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        SizedBox(
          width: 150,
          child: _buildTextField(
            controller: _zipCodeController,
            label: '${'onb_zip'.tr()} *',
            icon: Icons.markunread_mailbox_outlined,
            keyboardType: TextInputType.number,
            fieldName: 'zipCode',
          ),
        ),
        const SizedBox(height: 16),

        // W-9 Certification
        _buildW9Certification(),
      ],
    );
  }

  Widget _buildMexicoTaxStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'onb_tax_title_mx'.tr(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'onb_tax_subtitle_mx'.tr(),
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.security_outlined, color: AppColors.warning, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'onb_tax_mx_note'.tr(),
                  style: TextStyle(
                    color: AppColors.warning,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // RFC Field
        TextFormField(
          controller: _rfcController,
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
            LengthLimitingTextInputFormatter(13),
            _UpperCaseInputFormatter(),
          ],
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, letterSpacing: 1.5),
          decoration: InputDecoration(
            labelText: '${'onb_tax_rfc'.tr()} *',
            hintText: 'onb_tax_rfc_hint'.tr(),
            labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
            prefixIcon: Icon(Icons.badge_outlined, color: AppColors.textTertiary, size: 20),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            filled: true,
            fillColor: AppColors.card,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.success, width: 2)),
          ),
        ),
        const SizedBox(height: 12),

        // CURP Field
        TextFormField(
          controller: _curpController,
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
            LengthLimitingTextInputFormatter(18),
            _UpperCaseInputFormatter(),
          ],
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, letterSpacing: 1.5),
          decoration: InputDecoration(
            labelText: '${'onb_tax_curp'.tr()} *',
            hintText: 'onb_tax_curp_hint'.tr(),
            labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
            prefixIcon: Icon(Icons.fingerprint, color: AppColors.textTertiary, size: 20),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            filled: true,
            fillColor: AppColors.card,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.success, width: 2)),
          ),
        ),
        const SizedBox(height: 12),

        _buildTextField(
          controller: _legalNameController,
          label: '${'onb_tax_legal_name'.tr()} *',
          icon: Icons.person_outline,
          fieldName: 'legalName',
        ),
        const SizedBox(height: 12),

        _buildTextField(
          controller: _businessNameController,
          label: 'onb_tax_business_name'.tr(),
          icon: Icons.business_outlined,
          fieldName: 'businessName',
        ),
        const SizedBox(height: 12),

        // SAT Regime selector
        _buildSATRegimeSelector(),
        const SizedBox(height: 16),

        // Address Section
        Text(
          'onb_tax_address'.tr(),
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),

        _buildTextField(
          controller: _streetAddressController,
          label: '${'onb_address'.tr()} *',
          icon: Icons.home_outlined,
          fieldName: 'streetAddress',
        ),
        const SizedBox(height: 10),

        Row(
          children: [
            Expanded(
              flex: 2,
              child: _buildTextField(
                controller: _cityController,
                label: '${'onb_city'.tr()} *',
                icon: Icons.location_city_outlined,
                fieldName: 'city',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildTextField(
                controller: _stateController,
                label: '${'onb_state'.tr()} *',
                icon: Icons.map_outlined,
                hint: 'onb_state_hint_mx'.tr(),
                fieldName: 'state',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        SizedBox(
          width: 150,
          child: _buildTextField(
            controller: _zipCodeController,
            label: '${'onb_zip'.tr()} *',
            icon: Icons.markunread_mailbox_outlined,
            keyboardType: TextInputType.number,
            fieldName: 'zipCode',
          ),
        ),
        const SizedBox(height: 16),

        // SAT Certification
        GestureDetector(
          onTap: () {
            HapticService.buttonPress();
            setState(() => _certifySAT = !_certifySAT);
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _certifySAT ? AppColors.success.withValues(alpha: 0.08) : AppColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _certifySAT ? AppColors.success : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _certifySAT ? Icons.check_circle : Icons.circle_outlined,
                  color: _certifySAT ? AppColors.success : AppColors.textTertiary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'onb_tax_certify_sat'.tr(),
                    style: TextStyle(
                      color: _certifySAT ? AppColors.textPrimary : AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSATRegimeSelector() {
    final regimes = [
      {'id': 'pfae', 'label': 'onb_tax_sat_regime_pfae'.tr()},
      {'id': 'resico', 'label': 'onb_tax_sat_regime_resico'.tr()},
      {'id': 'moral', 'label': 'onb_tax_sat_regime_moral'.tr()},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'onb_tax_sat_regime'.tr(),
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _satRegime,
              isExpanded: true,
              dropdownColor: AppColors.card,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              items: regimes.map((r) => DropdownMenuItem(
                value: r['id'],
                child: Text(r['label']!, style: const TextStyle(fontSize: 13)),
              )).toList(),
              onChanged: (value) {
                if (value != null) setState(() => _satRegime = value);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSSNField() {
    return TextFormField(
      controller: _ssnController,
      keyboardType: TextInputType.number,
      obscureText: true,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(9),
        _SSNInputFormatter(),
      ],
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, letterSpacing: 2),
      decoration: InputDecoration(
        labelText: '${'onb_tax_ssn'.tr()} *',
        hintText: 'onb_tax_ssn_hint'.tr(),
        labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
        prefixIcon: Icon(Icons.lock_outline, color: AppColors.textTertiary, size: 20),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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

  Widget _buildTaxClassificationSelector() {
    final classifications = [
      {'id': 'individual', 'label': 'onb_tax_classification_individual'.tr()},
      {'id': 'llc_single', 'label': 'onb_tax_classification_llc'.tr()},
      {'id': 'llc_partnership', 'label': 'onb_tax_classification_partnership'.tr()},
      {'id': 'corporation', 'label': 'onb_tax_classification_corp'.tr()},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'onb_tax_classification'.tr(),
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _taxClassification,
              isExpanded: true,
              dropdownColor: AppColors.card,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              icon: Icon(Icons.keyboard_arrow_down, color: AppColors.textTertiary),
              items: classifications.map((c) {
                return DropdownMenuItem<String>(
                  value: c['id'],
                  child: Text(c['label']!),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  HapticService.lightImpact();
                  setState(() => _taxClassification = value);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildW9Certification() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _certifyW9 ? AppColors.success : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.gavel_rounded,
                color: AppColors.textSecondary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'onb_tax_w9_title'.tr(),
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'onb_tax_w9_text'.tr(),
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () {
              HapticService.lightImpact();
              setState(() => _certifyW9 = !_certifyW9);
            },
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: _certifyW9 ? AppColors.success : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: _certifyW9 ? AppColors.success : AppColors.textTertiary,
                      width: 2,
                    ),
                  ),
                  child: _certifyW9
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'onb_tax_certify_correct'.tr(),
                    style: TextStyle(
                      color: _certifyW9 ? AppColors.success : AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: _certifyW9 ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.words,
    String? fieldName,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType ?? TextInputType.text,
      textCapitalization: textCapitalization,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
        prefixIcon: Icon(icon, color: AppColors.textTertiary, size: 20),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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

  Widget _buildDatePicker() {
    return GestureDetector(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: DateTime(2000),
          firstDate: DateTime(1950),
          lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: ColorScheme.dark(
                  primary: AppColors.success,
                  surface: AppColors.card,
                ),
              ),
              child: child!,
            );
          },
        );
        if (date != null) {
          setState(() => _birthDate = date);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.cake_outlined, color: AppColors.textTertiary, size: 20),
            const SizedBox(width: 10),
            Text(
              _birthDate != null
                  ? '${_birthDate!.month}/${_birthDate!.day}/${_birthDate!.year}'
                  : 'onb_dob'.tr(),
              style: TextStyle(
                color: _birthDate != null
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleTypeSelector() {
    final types = [
      {'id': 'sedan', 'label': 'onb_vehicle_type_sedan'.tr(), 'icon': Icons.directions_car},
      {'id': 'suv', 'label': 'onb_vehicle_type_suv'.tr(), 'icon': Icons.directions_car},
      {'id': 'van', 'label': 'onb_vehicle_type_van'.tr(), 'icon': Icons.airport_shuttle},
      {'id': 'truck', 'label': 'onb_vehicle_type_truck'.tr(), 'icon': Icons.local_shipping},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'onb_vehicle_type'.tr(),
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: types.map((type) {
            final isSelected = _vehicleType == type['id'];
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticService.lightImpact();
                  setState(() => _vehicleType = type['id'] as String);
                },
                child: Container(
                  margin: EdgeInsets.only(
                    right: type != types.last ? 6 : 0,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.success.withValues(alpha: 0.1)
                        : AppColors.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? AppColors.success : AppColors.border,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        type['icon'] as IconData,
                        color: isSelected
                            ? AppColors.success
                            : AppColors.textTertiary,
                        size: 20,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        type['label'] as String,
                        style: TextStyle(
                          color: isSelected
                              ? AppColors.success
                              : AppColors.textSecondary,
                          fontSize: 10,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDocumentUpload({
    required String title,
    required String subtitle,
    required IconData icon,
    required Uint8List? imageBytes,
    required VoidCallback onTap,
    bool isRequired = false,
    bool ocrExtracted = false,
    String? extractedText,
    DateTime? expiryDate,
  }) {
    final hasImage = imageBytes != null;
    final isExpired = expiryDate != null && expiryDate.isBefore(DateTime.now());

    // Determine color based on OCR extraction status
    Color highlightColor;
    if (hasImage && isExpired) {
      highlightColor = AppColors.error;
    } else if (hasImage && ocrExtracted) {
      highlightColor = AppColors.success;
    } else if (hasImage) {
      highlightColor = AppColors.primary; // Uploaded but no OCR data
    } else if (isRequired) {
      highlightColor = AppColors.warning;
    } else {
      highlightColor = AppColors.success;
    }

    // Build status text from OCR data
    String? verificationText;
    if (hasImage) {
      if (isExpired) {
        verificationText = 'EXPIRED: ${_formatDate(expiryDate)}';
      } else if (extractedText != null) {
        final expText = expiryDate != null ? ' • Exp: ${_formatDate(expiryDate)}' : '';
        verificationText = '$extractedText$expText';
      } else if (ocrExtracted) {
        verificationText = 'onb_doc_uploaded'.tr();
      } else {
        verificationText = 'onb_doc_pending_review'.tr();
      }
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: hasImage
              ? highlightColor.withValues(alpha: 0.1)
              : isRequired && !hasImage
                  ? AppColors.warning.withValues(alpha: 0.05)
                  : AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasImage
                ? highlightColor
                : isRequired
                    ? AppColors.warning.withValues(alpha: 0.5)
                    : AppColors.border,
            width: hasImage || isRequired ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: hasImage
                    ? highlightColor.withValues(alpha: 0.2)
                    : isRequired
                        ? AppColors.warning.withValues(alpha: 0.1)
                        : AppColors.cardSecondary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: imageBytes != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(imageBytes, fit: BoxFit.cover),
                    )
                  : Icon(icon, color: isRequired ? AppColors.warning : AppColors.textTertiary, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (verificationText != null)
                    Text(
                      verificationText,
                      style: TextStyle(
                        color: highlightColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else
                    Text(
                      hasImage ? 'onb_doc_tap_change'.tr() : subtitle,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            if (_isVerifying && hasImage && !ocrExtracted)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.success,
                ),
              )
            else
              Icon(
                isExpired
                    ? Icons.error_rounded
                    : ocrExtracted
                        ? Icons.verified_rounded
                        : hasImage
                            ? Icons.check_circle_rounded
                            : Icons.add_a_photo_outlined,
                color: hasImage
                    ? highlightColor
                    : isRequired
                        ? AppColors.warning
                        : AppColors.textTertiary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomButton() {
    final isLastStep = _isLastStep;

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
                        isLastStep ? 'onb_btn_submit'.tr() : 'onb_btn_continue'.tr(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        isLastStep
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

/// Custom input formatter for SSN (formats as XXX-XX-XXXX)
class _UpperCaseInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

class _SSNInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();

    for (int i = 0; i < text.length && i < 9; i++) {
      if (i == 3 || i == 5) {
        buffer.write('-');
      }
      buffer.write(text[i]);
    }

    return TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection.collapsed(offset: buffer.length),
    );
  }
}
