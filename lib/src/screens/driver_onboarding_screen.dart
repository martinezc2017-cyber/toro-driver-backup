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
import '../widgets/custom_keyboard.dart';

/// Multi-step onboarding for new drivers
/// Step 1: Personal Information
/// Step 2: Vehicle Information
/// Step 3: Document Upload
/// Step 4: Tax Information (W-9)
class DriverOnboardingScreen extends StatefulWidget {
  const DriverOnboardingScreen({super.key});

  @override
  State<DriverOnboardingScreen> createState() => _DriverOnboardingScreenState();
}

class _DriverOnboardingScreenState extends State<DriverOnboardingScreen> {
  int _currentStep = 0;
  bool _isLoading = false;

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

  // Step 4: Tax Information (W-9)
  final _ssnController = TextEditingController();
  final _legalNameController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _streetAddressController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _zipCodeController = TextEditingController();
  String _taxClassification = 'individual'; // individual, llc_single, llc_partnership, corporation
  bool _certifyW9 = false;

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

  // Custom keyboard state
  bool _showEmailKeyboard = false;
  bool _showTextKeyboard = false;
  bool _showPhoneKeyboard = false;
  bool _showNumericKeyboard = false;
  String? _activeField;
  late FocusNode _keyboardListenerFocus;

  @override
  void initState() {
    super.initState();
    _keyboardListenerFocus = FocusNode();
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

  @override
  void dispose() {
    _keyboardListenerFocus.dispose();
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
    // W-9 controllers
    _ssnController.dispose();
    _legalNameController.dispose();
    _businessNameController.dispose();
    _streetAddressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _zipCodeController.dispose();
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
        docName = "Driver's License";
        hasData = _licenseOcrData?.hasAnyData ?? false;
        if (_licenseOcrData != null) {
          extractedInfo = _licenseOcrData!.licenseNumber;
          expiryDate = _licenseOcrData!.expiryDate;
        }
        break;
      case 'registration':
        docName = 'Vehicle Registration';
        hasData = true; // Registration doesn't have specific data to extract
        break;
      case 'insurance':
        docName = 'Insurance';
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
    if (_currentStep < 3) {
      if (_validateCurrentStep()) {
        HapticService.buttonPress();
        setState(() => _currentStep++);
        // Auto-fill W-9 legal name from personal info when entering Step 4
        if (_currentStep == 3 && _legalNameController.text.isEmpty) {
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

  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0:
        if (_firstNameController.text.isEmpty ||
            _lastNameController.text.isEmpty ||
            _phoneController.text.isEmpty) {
          _showError('Please fill in all required fields');
          return false;
        }
        return true;
      case 1:
        if (_vehicleMakeController.text.isEmpty ||
            _vehicleModelController.text.isEmpty ||
            _licensePlateController.text.isEmpty) {
          _showError('Please fill in all required vehicle information');
          return false;
        }
        // Validate vehicle year
        if (_vehicleYearController.text.isNotEmpty) {
          final year = _vehicleYear;
          if (year == null) {
            _showError('Please enter a valid vehicle year');
            return false;
          }
          if (year < 2012) {
            _showError('Vehicles older than 2012 are not eligible for registration');
            return false;
          }
          final currentYear = DateTime.now().year;
          if (year > currentYear + 1) {
            _showError('Please enter a valid vehicle year');
            return false;
          }
        }
        return true;
      case 2:
        if (_profilePhoto == null || _driverLicense == null) {
          _showError('Please upload your profile photo and driver\'s license');
          return false;
        }
        // Vehicle Inspection Report required for 2012-2017 vehicles
        if (_requiresInspectionReport && _vehicleInspectionReport == null) {
          _showError('Vehicle Inspection Report is required for vehicles 2012-2017');
          return false;
        }
        // Background check consent is required
        if (!_acceptsBackgroundCheck) {
          _showError('You must consent to background check verification');
          return false;
        }
        return true;
      case 3:
        // W-9 Tax Information validation
        if (_ssnController.text.isEmpty) {
          _showError('Social Security Number is required');
          return false;
        }
        // SSN should be 9 digits (without dashes)
        final ssnDigits = _ssnController.text.replaceAll(RegExp(r'\D'), '');
        if (ssnDigits.length != 9) {
          _showError('Please enter a valid 9-digit SSN');
          return false;
        }
        if (_legalNameController.text.isEmpty) {
          _showError('Legal name is required');
          return false;
        }
        if (_streetAddressController.text.isEmpty ||
            _cityController.text.isEmpty ||
            _stateController.text.isEmpty ||
            _zipCodeController.text.isEmpty) {
          _showError('Complete mailing address is required');
          return false;
        }
        if (!_certifyW9) {
          _showError('You must certify the W-9 information');
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

      // Get current user from Supabase
      final currentUser = Supabase.instance.client.auth.currentUser;
      //ONBOARDING -> currentUser: ${currentUser?.email ?? "NULL"}');

      if (currentUser == null) {
        _showError('User not authenticated. Please sign in again.');
        setState(() => _isLoading = false);
        return;
      }

      // Use Supabase auth user ID as driver ID (must match for profile lookup)
      final driverId = currentUser.id;
      final now = DateTime.now();
      //ONBOARDING -> Creating driver with ID: $driverId');

      // Create driver model with pending status
      final fullName = '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'.trim();
      final newDriver = DriverModel(
        id: driverId,
        odUserId: driverId,
        email: currentUser.email ?? '',
        phone: _phoneController.text.trim(),
        name: fullName,
        vehicleType: _vehicleType,
        vehiclePlate: _licensePlateController.text.trim(),
        vehicleModel: '${_vehicleMakeController.text.trim()} ${_vehicleModelController.text.trim()}'.trim(),
        status: DriverStatus.pending,
        isVerified: false,
        createdAt: now,
        updatedAt: now,
      );

      //ONBOARDING -> Saving to database...');
      // Save driver to database
      final savedDriver = await driverService.createDriver(newDriver);
      //ONBOARDING -> Driver saved successfully: ${savedDriver.id}');

      // Save W-9 Tax Information
      //ONBOARDING -> Saving W-9 tax info...');
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
      //ONBOARDING -> W-9 saved successfully');

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

  void _handleExternalKeyboardInput(String char) {
    if (_activeField == null) return;

    final controller = _getControllerForField(_activeField!);
    if (controller == null) return;

    final value = controller.value;
    final start = value.selection.baseOffset;
    final end = value.selection.extentOffset;

    if (start < 0) {
      controller.text += char;
    } else {
      final newText = value.text.replaceRange(start, end, char);
      controller.value = value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: start + char.length),
      );
    }

    setState(() {});
  }

  void _handleExternalBackspace() {
    if (_activeField == null) return;

    final controller = _getControllerForField(_activeField!);
    if (controller == null || controller.text.isEmpty) return;

    final value = controller.value;
    final start = value.selection.baseOffset;
    final end = value.selection.extentOffset;

    if (start < 0) {
      controller.text = value.text.substring(0, value.text.length - 1);
    } else if (start == end) {
      controller.value = value.copyWith(
        text: value.text.replaceRange(start - 1, end, ''),
        selection: TextSelection.collapsed(offset: start - 1),
      );
    } else {
      controller.value = value.copyWith(
        text: value.text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
      );
    }

    setState(() {});
  }

  TextEditingController? _getControllerForField(String fieldName) {
    switch (fieldName) {
      case 'firstName': return _firstNameController;
      case 'lastName': return _lastNameController;
      case 'phone': return _phoneController;
      case 'address': return _addressController;
      case 'vehicleMake': return _vehicleMakeController;
      case 'vehicleModel': return _vehicleModelController;
      case 'vehicleYear': return _vehicleYearController;
      case 'vehicleColor': return _vehicleColorController;
      case 'licensePlate': return _licensePlateController;
      case 'ssn': return _ssnController;
      case 'legalName': return _legalNameController;
      case 'businessName': return _businessNameController;
      case 'streetAddress': return _streetAddressController;
      case 'city': return _cityController;
      case 'state': return _stateController;
      case 'zipCode': return _zipCodeController;
      default: return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _keyboardListenerFocus,
      onKeyEvent: (event) {
        // Handle physical keyboard input
        if (event.logicalKey == LogicalKeyboardKey.backspace) {
          _handleExternalBackspace();
        } else if (event.character != null && event.character!.isNotEmpty) {
          _handleExternalKeyboardInput(event.character!);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
            onPressed: _currentStep > 0 ? _previousStep : () => Navigator.pop(context),
          ),
          title: Text(
            'Step ${_currentStep + 1} of 4',
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
              child: Stack(
                children: [
                  Column(
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
                  // Keyboard overlay
                  if (_showTextKeyboard)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: CustomTextKeyboard(
                        controller: _getControllerForField(_activeField!) ?? TextEditingController(),
                        onDone: () => setState(() {
                          _showTextKeyboard = false;
                          _activeField = null;
                          FocusScope.of(context).unfocus();
                        }),
                        onChanged: () => setState(() {}),
                      ),
                    ),
                  if (_showEmailKeyboard)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: CustomEmailKeyboard(
                        controller: _getControllerForField(_activeField!) ?? TextEditingController(),
                        onDone: () => setState(() {
                          _showEmailKeyboard = false;
                          _activeField = null;
                          FocusScope.of(context).unfocus();
                        }),
                        onChanged: () => setState(() {}),
                      ),
                    ),
                  if (_showPhoneKeyboard)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: CustomPhoneKeyboard(
                        controller: _getControllerForField(_activeField!) ?? TextEditingController(),
                        onDone: () => setState(() {
                          _showPhoneKeyboard = false;
                          _activeField = null;
                          FocusScope.of(context).unfocus();
                        }),
                        onChanged: () => setState(() {}),
                      ),
                    ),
                  if (_showNumericKeyboard)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: CustomNumericKeyboard(
                        controller: _getControllerForField(_activeField!) ?? TextEditingController(),
                        onDone: () => setState(() {
                          _showNumericKeyboard = false;
                          _activeField = null;
                          FocusScope.of(context).unfocus();
                        }),
                        onChanged: () => setState(() {}),
                      ),
                    ),
                ],
              ),
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
        children: List.generate(4, (index) {
          final isActive = index <= _currentStep;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: index < 3 ? 6 : 0),
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
    switch (_currentStep) {
      case 0:
        return _buildPersonalInfoStep();
      case 1:
        return _buildVehicleInfoStep();
      case 2:
        return _buildDocumentsStep();
      case 3:
        return _buildTaxInfoStep();
      default:
        return const SizedBox();
    }
  }

  Widget _buildPersonalInfoStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Personal Information',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tell us about yourself',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 20),

        _buildTextField(
          controller: _firstNameController,
          label: 'First Name *',
          icon: Icons.person_outline_rounded,
          fieldName: 'firstName',
        ),
        const SizedBox(height: 12),

        _buildTextField(
          controller: _lastNameController,
          label: 'Last Name *',
          icon: Icons.person_outline_rounded,
          fieldName: 'lastName',
        ),
        const SizedBox(height: 12),

        _buildTextField(
          controller: _phoneController,
          label: 'Phone Number *',
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          fieldName: 'phone',
        ),
        const SizedBox(height: 12),

        _buildTextField(
          controller: _addressController,
          label: 'Address',
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
        const Text(
          'Vehicle Information',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tell us about your vehicle',
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
          label: 'Make *',
          icon: Icons.directions_car_outlined,
          hint: 'e.g., Toyota',
          fieldName: 'vehicleMake',
        ),
        const SizedBox(height: 12),

        _buildTextField(
          controller: _vehicleModelController,
          label: 'Model *',
          icon: Icons.directions_car_outlined,
          hint: 'e.g., Camry',
          fieldName: 'vehicleModel',
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _vehicleYearController,
                label: 'Year',
                icon: Icons.calendar_today_outlined,
                keyboardType: TextInputType.number,
                hint: 'e.g., 2020',
                fieldName: 'vehicleYear',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTextField(
                controller: _vehicleColorController,
                label: 'Color',
                icon: Icons.palette_outlined,
                hint: 'e.g., White',
                fieldName: 'vehicleColor',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        _buildTextField(
          controller: _licensePlateController,
          label: 'License Plate *',
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
                    'Vehicles older than 2012 are not eligible for registration.',
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
                    'Vehicles from 2012-2017 require a Vehicle Inspection Report.',
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
        const Text(
          'Upload Documents',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'We need to verify your identity',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 20),

        _buildDocumentUpload(
          title: 'Profile Photo *',
          subtitle: 'Clear photo of your face',
          icon: Icons.face_rounded,
          imageBytes: _profilePhoto,
          onTap: () => _pickImage('profile'),
        ),
        const SizedBox(height: 10),

        _buildDocumentUpload(
          title: 'Driver\'s License *',
          subtitle: 'Front side of your license',
          icon: Icons.badge_outlined,
          imageBytes: _driverLicense,
          onTap: () => _pickImage('license'),
          ocrExtracted: _licenseOcrData?.hasAnyData ?? false,
          extractedText: _licenseOcrData?.licenseNumber,
          expiryDate: _licenseOcrData?.expiryDate,
        ),
        const SizedBox(height: 10),

        _buildDocumentUpload(
          title: 'Vehicle Registration',
          subtitle: 'Current registration document',
          icon: Icons.description_outlined,
          imageBytes: _vehicleRegistration,
          onTap: () => _pickImage('registration'),
        ),
        const SizedBox(height: 10),

        _buildDocumentUpload(
          title: 'Insurance Card',
          subtitle: 'Proof of insurance',
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
            title: 'Vehicle Inspection Report *',
            subtitle: 'Required for vehicles 2012-2017',
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
                'Background Check Verification *',
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
            'As a TORO Driver, you will be transporting passengers and packages. '
            'For everyone\'s safety, we conduct background checks on all drivers.',
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
                    'I consent to background check verification',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tax Information (W-9)',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Required for IRS 1099 tax reporting',
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
                  'Your SSN is encrypted and only used for tax filing',
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
          label: 'Legal Name (as shown on tax return) *',
          icon: Icons.person_outline,
          fieldName: 'legalName',
        ),
        const SizedBox(height: 12),

        _buildTextField(
          controller: _businessNameController,
          label: 'Business Name (if different)',
          icon: Icons.business_outlined,
          hint: 'Leave blank if individual',
          fieldName: 'businessName',
        ),
        const SizedBox(height: 12),

        // Tax Classification
        _buildTaxClassificationSelector(),
        const SizedBox(height: 16),

        // Mailing Address Section
        Text(
          'Mailing Address',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),

        _buildTextField(
          controller: _streetAddressController,
          label: 'Street Address *',
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
                label: 'City *',
                icon: Icons.location_city_outlined,
                fieldName: 'city',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildTextField(
                controller: _stateController,
                label: 'State *',
                icon: Icons.map_outlined,
                hint: 'CA',
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
            label: 'ZIP Code *',
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

  Widget _buildSSNField() {
    return TextFormField(
      controller: _ssnController,
      keyboardType: TextInputType.none, // Disable system keyboard
      obscureText: true,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(9),
        _SSNInputFormatter(),
      ],
      onTap: () => _showKeyboardForField('ssn', TextInputType.number),
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, letterSpacing: 2),
      decoration: InputDecoration(
        labelText: 'Social Security Number *',
        hintText: '***-**-****',
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
      {'id': 'individual', 'label': 'Individual / Sole Proprietor'},
      {'id': 'llc_single', 'label': 'LLC (Single Member)'},
      {'id': 'llc_partnership', 'label': 'LLC (Partnership)'},
      {'id': 'corporation', 'label': 'C or S Corporation'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tax Classification',
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
                'W-9 Certification',
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
            'Under penalties of perjury, I certify that:\n'
            '1. The number shown is my correct taxpayer identification number\n'
            '2. I am a U.S. citizen or other U.S. person\n'
            '3. I am not subject to backup withholding',
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
                    'I certify that the above information is correct',
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
      keyboardType: TextInputType.none, // Disable system keyboard
      textCapitalization: textCapitalization,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      onTap: fieldName != null ? () => _showKeyboardForField(fieldName, keyboardType) : null,
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

  void _showKeyboardForField(String fieldName, TextInputType? keyboardType) {
    setState(() {
      _activeField = fieldName;

      // Hide all keyboards first
      _showTextKeyboard = false;
      _showEmailKeyboard = false;
      _showPhoneKeyboard = false;
      _showNumericKeyboard = false;

      // Show appropriate keyboard based on field type
      if (keyboardType == TextInputType.phone) {
        _showPhoneKeyboard = true;
      } else if (keyboardType == TextInputType.number) {
        _showNumericKeyboard = true;
      } else if (keyboardType == TextInputType.emailAddress) {
        _showEmailKeyboard = true;
      } else {
        _showTextKeyboard = true;
      }
    });
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
                  : 'Date of Birth',
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
      {'id': 'sedan', 'label': 'Sedan', 'icon': Icons.directions_car},
      {'id': 'suv', 'label': 'SUV', 'icon': Icons.directions_car},
      {'id': 'van', 'label': 'Van', 'icon': Icons.airport_shuttle},
      {'id': 'truck', 'label': 'Truck', 'icon': Icons.local_shipping},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Vehicle Type',
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
        verificationText = 'Data extracted';
      } else {
        verificationText = 'Pending admin review';
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
                      hasImage ? 'Tap to change' : subtitle,
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
    final isLastStep = _currentStep == 3;

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
                        isLastStep ? 'SUBMIT APPLICATION' : 'CONTINUE',
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
