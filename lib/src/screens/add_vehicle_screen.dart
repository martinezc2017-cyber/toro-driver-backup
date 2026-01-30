import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/document_ocr_service.dart';
import '../utils/app_colors.dart';
import '../utils/haptic_service.dart';
import '../widgets/custom_keyboard.dart';

/// Screen for drivers to register their vehicle
/// Required fields: Make, Model, Year, Color, Plate, Type
/// Optional: VIN
class AddVehicleScreen extends StatefulWidget {
  const AddVehicleScreen({super.key});

  @override
  State<AddVehicleScreen> createState() => _AddVehicleScreenState();
}

class _AddVehicleScreenState extends State<AddVehicleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _makeController = TextEditingController();
  final _modelController = TextEditingController();
  final _yearController = TextEditingController();
  final _colorController = TextEditingController();
  final _plateController = TextEditingController();
  final _vinController = TextEditingController();

  // Insurance fields
  final _insuranceCompanyController = TextEditingController();
  final _insurancePolicyController = TextEditingController();
  DateTime? _insuranceExpiry;
  bool _hasRideshareEndorsement = false;

  // Insurance document photos
  final ImagePicker _imagePicker = ImagePicker();
  final DocumentOcrService _ocrService = DocumentOcrService();
  XFile? _insuranceCardFront;
  XFile? _insuranceCardBack;
  XFile? _endorsementDoc;
  bool _isExtractingData = false;
  InsuranceCardData? _extractedData;

  String _selectedType = 'sedan';
  bool _isLoading = false;

  // Custom keyboard state
  bool _showTextKeyboard = false;
  bool _showNumericKeyboard = false;
  String? _activeField;
  late FocusNode _keyboardListenerFocus;

  final List<Map<String, dynamic>> _vehicleTypes = [
    {'value': 'sedan', 'label': 'Sedan', 'icon': Icons.directions_car},
    {'value': 'suv', 'label': 'SUV', 'icon': Icons.directions_car_filled},
    {'value': 'van', 'label': 'Van', 'icon': Icons.airport_shuttle},
    {'value': 'truck', 'label': 'Pickup', 'icon': Icons.local_shipping},
  ];

  @override
  void initState() {
    super.initState();
    _keyboardListenerFocus = FocusNode();
    _makeController.addListener(() => setState(() {}));
    _modelController.addListener(() => setState(() {}));
    _yearController.addListener(() => setState(() {}));
    _colorController.addListener(() => setState(() {}));
    _plateController.addListener(() => setState(() {}));
    _vinController.addListener(() => setState(() {}));
    _insuranceCompanyController.addListener(() => setState(() {}));
    _insurancePolicyController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _makeController.dispose();
    _modelController.dispose();
    _yearController.dispose();
    _colorController.dispose();
    _plateController.dispose();
    _vinController.dispose();
    _insuranceCompanyController.dispose();
    _insurancePolicyController.dispose();
    _keyboardListenerFocus.dispose();
    super.dispose();
  }

  /// Pick an image from camera or gallery
  Future<void> _pickImage(String type) async {
    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: AppColors.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Seleccionar Foto',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _buildSourceOption(
                        icon: Icons.camera_alt_rounded,
                        label: 'Cámara',
                        onTap: () => Navigator.pop(context, ImageSource.camera),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildSourceOption(
                        icon: Icons.photo_library_rounded,
                        label: 'Galería',
                        onTap: () =>
                            Navigator.pop(context, ImageSource.gallery),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      );

      if (source == null) return;

      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image != null) {
        HapticService.lightImpact();
        setState(() {
          switch (type) {
            case 'front':
              _insuranceCardFront = image;
              break;
            case 'back':
              _insuranceCardBack = image;
              break;
            case 'endorsement':
              _endorsementDoc = image;
              break;
          }
        });

        // Run OCR on insurance card front to extract data
        if (type == 'front') {
          _extractInsuranceData(image);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al seleccionar imagen: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Widget _buildSourceOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Extract insurance data from card image using OCR
  Future<void> _extractInsuranceData(XFile image) async {
    setState(() => _isExtractingData = true);

    try {
      final data = await _ocrService.extractFromImage(image);

      if (data != null && mounted) {
        setState(() {
          _extractedData = data;

          // Auto-fill fields with extracted data
          if (data.insuranceCompany != null &&
              _insuranceCompanyController.text.isEmpty) {
            _insuranceCompanyController.text = data.insuranceCompany!;
          }
          if (data.policyNumber != null &&
              _insurancePolicyController.text.isEmpty) {
            _insurancePolicyController.text = data.policyNumber!;
          }
          if (data.expiryDate != null && _insuranceExpiry == null) {
            _insuranceExpiry = data.expiryDate;
          }
          if (data.vin != null && _vinController.text.isEmpty) {
            _vinController.text = data.vin!;
          }
          // Auto-fill vehicle info if available
          if (data.vehicleMake != null && _makeController.text.isEmpty) {
            _makeController.text = data.vehicleMake!;
          }
          if (data.vehicleModel != null && _modelController.text.isEmpty) {
            _modelController.text = data.vehicleModel!;
          }
          if (data.vehicleYear != null && _yearController.text.isEmpty) {
            _yearController.text = data.vehicleYear.toString();
          }
        });

        // Show success feedback
        if (data.hasAnyData) {
          HapticService.success();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Datos extraidos automaticamente de tu tarjeta de seguro',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF22C55E),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      //OCR Error: $e');
      // Don't show error to user - manual entry is still available
    } finally {
      if (mounted) {
        setState(() => _isExtractingData = false);
      }
    }
  }

  /// Upload image to Supabase Storage
  Future<String?> _uploadImage(XFile image, String path) async {
    try {
      final bytes = await image.readAsBytes();
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${image.name}';
      final fullPath = '$path/$fileName';

      await Supabase.instance.client.storage
          .from('vehicle-documents')
          .uploadBinary(
            fullPath,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      final url = Supabase.instance.client.storage
          .from('vehicle-documents')
          .getPublicUrl(fullPath);

      return url;
    } catch (e) {
      //Upload error: $e');
      return null;
    }
  }

  void _handleExternalKeyboardInput(String char) {
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
      case 'make':
        return _makeController;
      case 'model':
        return _modelController;
      case 'year':
        return _yearController;
      case 'color':
        return _colorController;
      case 'plate':
        return _plateController;
      case 'vin':
        return _vinController;
      case 'insuranceCompany':
        return _insuranceCompanyController;
      case 'insurancePolicy':
        return _insurancePolicyController;
      default:
        return null;
    }
  }

  void _showKeyboardForField(String fieldName, TextInputType keyboardType) {
    _keyboardListenerFocus.requestFocus();
    setState(() {
      _showTextKeyboard = false;
      _showNumericKeyboard = false;
      _activeField = fieldName;

      if (keyboardType == TextInputType.number) {
        _showNumericKeyboard = true;
      } else {
        _showTextKeyboard = true;
      }
    });
  }

  Future<void> _submitVehicle() async {
    if (!_formKey.currentState!.validate()) return;

    // Validate insurance expiry date
    if (_insuranceExpiry == null) {
      HapticService.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Selecciona la fecha de vencimiento del seguro'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Validate insurance card photos
    if (_insuranceCardFront == null) {
      HapticService.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Sube la foto del frente de tu tarjeta de seguro',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_insuranceCardBack == null) {
      HapticService.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Sube la foto del reverso de tu tarjeta de seguro',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Validate endorsement if they claim to have one
    if (_hasRideshareEndorsement && _endorsementDoc == null) {
      HapticService.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Sube la foto del documento de endorsement'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('No autenticado');

      // Upload insurance card photos
      String? frontUrl;
      String? backUrl;
      String? endorsementUrl;

      if (_insuranceCardFront != null) {
        frontUrl = await _uploadImage(
          _insuranceCardFront!,
          '${user.id}/insurance',
        );
      }
      if (_insuranceCardBack != null) {
        backUrl = await _uploadImage(
          _insuranceCardBack!,
          '${user.id}/insurance',
        );
      }
      if (_endorsementDoc != null) {
        endorsementUrl = await _uploadImage(
          _endorsementDoc!,
          '${user.id}/endorsement',
        );
      }

      final now = DateTime.now().toIso8601String();

      await Supabase.instance.client.from('vehicles').insert({
        'driver_id': user.id,
        'make': _makeController.text.trim(),
        'model': _modelController.text.trim(),
        'year': int.parse(_yearController.text.trim()),
        'color': _colorController.text.trim(),
        'plate': _plateController.text.trim().toUpperCase(),
        'vin': _vinController.text.trim().isEmpty
            ? null
            : _vinController.text.trim().toUpperCase(),
        'type': _selectedType,
        'status': 'pendingVerification',
        'is_verified': false,
        'mileage': 0,
        'total_rides': 0,
        'rating': 5.0,
        // Insurance fields
        'insurance_company': _insuranceCompanyController.text.trim().isEmpty
            ? null
            : _insuranceCompanyController.text.trim(),
        'insurance_policy_number':
            _insurancePolicyController.text.trim().isEmpty
            ? null
            : _insurancePolicyController.text.trim(),
        'insurance_expiry': _insuranceExpiry?.toIso8601String().split('T')[0],
        'has_rideshare_endorsement': _hasRideshareEndorsement,
        'insurance_verified': false,
        // Document URLs
        'insurance_card_front_url': frontUrl,
        'insurance_card_back_url': backUrl,
        'endorsement_document_url': endorsementUrl,
        'created_at': now,
        'updated_at': now,
      });

      if (mounted) {
        HapticService.success();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Vehiculo registrado exitosamente'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        HapticService.error();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _keyboardListenerFocus,
      onKeyEvent: (event) {
        if (_activeField == null) return;
        if (event is! KeyDownEvent) return;
        if (event.logicalKey == LogicalKeyboardKey.backspace) {
          _handleExternalBackspace();
        } else if (event.character != null && event.character!.isNotEmpty) {
          _handleExternalKeyboardInput(event.character!);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildVehicleTypeSelector(),
                            const SizedBox(height: 24),
                            _buildFormSection(),
                            const SizedBox(height: 24),
                            _buildInsuranceSection(),
                            const SizedBox(height: 32),
                            _buildSubmitButton(),
                            const SizedBox(height: 80),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Custom Keyboard Overlays
            if (_showTextKeyboard)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: CustomTextKeyboard(
                  controller:
                      _getControllerForField(_activeField!) ?? _makeController,
                  onDone: () {
                    setState(() => _showTextKeyboard = false);
                    _activeField = null;
                  },
                  onChanged: () => setState(() {}),
                ),
              ),
            if (_showNumericKeyboard)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: CustomNumericKeyboard(
                  controller:
                      _getControllerForField(_activeField!) ?? _yearController,
                  onDone: () {
                    setState(() => _showNumericKeyboard = false);
                    _activeField = null;
                  },
                  onChanged: () => setState(() {}),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF22C55E).withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF22C55E).withValues(alpha: 0.15),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              HapticService.lightImpact();
              Navigator.pop(context);
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.border.withValues(alpha: 0.5),
                ),
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: AppColors.textPrimary,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.3),
                  blurRadius: 8,
                ),
              ],
            ),
            child: const Icon(
              Icons.add_circle_outline,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Registrar Vehiculo',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0);
  }

  Widget _buildVehicleTypeSelector() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.category_rounded, color: AppColors.primary, size: 22),
              const SizedBox(width: 10),
              Text(
                'Tipo de Vehiculo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: _vehicleTypes.map((type) {
              final isSelected = _selectedType == type['value'];
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticService.selectionClick();
                    setState(() => _selectedType = type['value']);
                  },
                  child: Container(
                    margin: EdgeInsets.only(
                      right: type != _vehicleTypes.last ? 8 : 0,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.15)
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.border.withValues(alpha: 0.5),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          type['icon'] as IconData,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          size: 28,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          type['label'] as String,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.textSecondary,
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
      ),
    ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildFormSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_document, color: AppColors.primary, size: 22),
              const SizedBox(width: 10),
              Text(
                'Informacion del Vehiculo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Make field with autocomplete
          _buildTextField(
            controller: _makeController,
            label: 'Marca',
            hint: 'Toyota, Honda, Ford...',
            icon: Icons.business,
            validator: (v) => v?.isEmpty ?? true ? 'Requerido' : null,
            fieldName: 'make',
          ),
          const SizedBox(height: 16),

          // Model field
          _buildTextField(
            controller: _modelController,
            label: 'Modelo',
            hint: 'Camry, Civic, F-150...',
            icon: Icons.directions_car,
            validator: (v) => v?.isEmpty ?? true ? 'Requerido' : null,
            fieldName: 'model',
          ),
          const SizedBox(height: 16),

          // Year and Color row
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  controller: _yearController,
                  label: 'Ano',
                  hint: '2020',
                  icon: Icons.calendar_today,
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v?.isEmpty ?? true) return 'Requerido';
                    final year = int.tryParse(v!);
                    if (year == null) return 'Invalido';
                    if (year < 2000 || year > DateTime.now().year + 1) {
                      return 'Invalido';
                    }
                    return null;
                  },
                  fieldName: 'year',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextField(
                  controller: _colorController,
                  label: 'Color',
                  hint: 'Blanco, Negro...',
                  icon: Icons.palette,
                  validator: (v) => v?.isEmpty ?? true ? 'Requerido' : null,
                  fieldName: 'color',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Plate field
          _buildTextField(
            controller: _plateController,
            label: 'Numero de Placa',
            hint: 'ABC-1234',
            icon: Icons.confirmation_number,
            textCapitalization: TextCapitalization.characters,
            validator: (v) => v?.isEmpty ?? true ? 'Requerido' : null,
            fieldName: 'plate',
          ),
          const SizedBox(height: 16),

          // VIN field (optional)
          _buildTextField(
            controller: _vinController,
            label: 'VIN (Opcional)',
            hint: '17 caracteres',
            icon: Icons.qr_code,
            textCapitalization: TextCapitalization.characters,
            validator: (v) {
              if (v?.isEmpty ?? true) return null; // Optional
              if (v!.length != 17) return 'VIN debe tener 17 caracteres';
              return null;
            },
            fieldName: 'vin',
          ),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildInsuranceSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFFF9500).withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF9500).withValues(alpha: 0.1),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9500).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  color: Color(0xFFFF9500),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Seguro del Vehiculo',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Requerido para conductores TNC en Arizona',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Warning banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFF9500).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFFF9500).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: Color(0xFFFF9500),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Arizona requiere cobertura minima de \$1,000,000 con endorsement de rideshare',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Insurance Company
          _buildTextField(
            controller: _insuranceCompanyController,
            label: 'Compania de Seguros',
            hint: 'State Farm, Geico, Progressive...',
            icon: Icons.business_rounded,
            validator: (v) => v?.isEmpty ?? true ? 'Requerido' : null,
            fieldName: 'insuranceCompany',
          ),
          const SizedBox(height: 16),

          // Policy Number
          _buildTextField(
            controller: _insurancePolicyController,
            label: 'Numero de Poliza',
            hint: 'Ej: POL-123456789',
            icon: Icons.confirmation_number_rounded,
            textCapitalization: TextCapitalization.characters,
            validator: (v) => v?.isEmpty ?? true ? 'Requerido' : null,
            fieldName: 'insurancePolicy',
          ),
          const SizedBox(height: 16),

          // Expiry Date
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Fecha de Vencimiento',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate:
                        _insuranceExpiry ??
                        DateTime.now().add(const Duration(days: 180)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: ColorScheme.dark(
                            primary: AppColors.primary,
                            onPrimary: Colors.white,
                            surface: AppColors.card,
                            onSurface: AppColors.textPrimary,
                          ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (date != null) {
                    setState(() => _insuranceExpiry = date);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _insuranceExpiry == null
                          ? AppColors.error.withValues(alpha: 0.5)
                          : AppColors.border.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _insuranceExpiry != null
                            ? '${_insuranceExpiry!.day}/${_insuranceExpiry!.month}/${_insuranceExpiry!.year}'
                            : 'Seleccionar fecha',
                        style: TextStyle(
                          color: _insuranceExpiry != null
                              ? AppColors.textPrimary
                              : AppColors.textSecondary.withValues(alpha: 0.5),
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.arrow_drop_down,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Insurance Card Photos Section
          Text(
            'Fotos de Tarjeta de Seguro',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'El VIN de tu vehículo se extraerá de la tarjeta',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildPhotoUploadCard(
                  label: 'Frente',
                  icon: Icons.credit_card,
                  image: _insuranceCardFront,
                  onTap: () => _pickImage('front'),
                  isRequired: true,
                  isProcessing: _isExtractingData,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPhotoUploadCard(
                  label: 'Reverso',
                  icon: Icons.credit_card,
                  image: _insuranceCardBack,
                  onTap: () => _pickImage('back'),
                  isRequired: true,
                ),
              ),
            ],
          ),

          // Show extracted data indicator
          if (_extractedData != null && _extractedData!.hasAnyData) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_awesome,
                    color: Color(0xFF22C55E),
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Datos detectados automaticamente',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF22C55E),
                          ),
                        ),
                        Text(
                          _buildExtractedSummary(),
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),

          // Rideshare Endorsement Checkbox
          GestureDetector(
            onTap: () {
              HapticService.selectionClick();
              setState(
                () => _hasRideshareEndorsement = !_hasRideshareEndorsement,
              );
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _hasRideshareEndorsement
                    ? const Color(0xFF22C55E).withValues(alpha: 0.1)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _hasRideshareEndorsement
                      ? const Color(0xFF22C55E)
                      : AppColors.border.withValues(alpha: 0.5),
                  width: _hasRideshareEndorsement ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _hasRideshareEndorsement
                          ? const Color(0xFF22C55E)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _hasRideshareEndorsement
                            ? const Color(0xFF22C55E)
                            : AppColors.textSecondary,
                        width: 2,
                      ),
                    ),
                    child: _hasRideshareEndorsement
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tengo Endorsement de Rideshare',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Mi poliza incluye cobertura comercial/TNC',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (!_hasRideshareEndorsement) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.error,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Sin endorsement no podras recibir viajes. Contacta a tu aseguradora para agregarlo.',
                      style: TextStyle(fontSize: 12, color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Endorsement document upload (when checkbox is checked)
          if (_hasRideshareEndorsement) ...[
            const SizedBox(height: 20),
            Text(
              'Documento de Endorsement',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Sube el documento que confirma tu cobertura TNC/comercial',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 12),
            _buildPhotoUploadCard(
              label: 'Endorsement',
              icon: Icons.verified_user_rounded,
              image: _endorsementDoc,
              onTap: () => _pickImage('endorsement'),
              isRequired: true,
              isWide: true,
            ),
          ],
        ],
      ),
    ).animate().fadeIn(delay: 250.ms).slideY(begin: 0.1, end: 0);
  }

  /// Build summary text of extracted data
  String _buildExtractedSummary() {
    if (_extractedData == null) return '';

    final parts = <String>[];
    if (_extractedData!.insuranceCompany != null) {
      parts.add(_extractedData!.insuranceCompany!);
    }
    if (_extractedData!.policyNumber != null) {
      parts.add('Poliza: ${_extractedData!.policyNumber}');
    }
    if (_extractedData!.vin != null) {
      parts.add('VIN detectado');
    }
    if (_extractedData!.expiryDate != null) {
      parts.add(
        'Vence: ${_extractedData!.expiryDate!.day}/${_extractedData!.expiryDate!.month}/${_extractedData!.expiryDate!.year}',
      );
    }

    return parts.isEmpty ? 'Procesando...' : parts.join(' • ');
  }

  Widget _buildPhotoUploadCard({
    required String label,
    required IconData icon,
    required XFile? image,
    required VoidCallback onTap,
    required bool isRequired,
    bool isWide = false,
    bool isProcessing = false,
  }) {
    final hasImage = image != null;

    return GestureDetector(
      onTap: isProcessing ? null : onTap,
      child: Container(
        height: isWide ? 120 : 140,
        decoration: BoxDecoration(
          color: hasImage ? Colors.transparent : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isProcessing
                ? const Color(0xFF3B82F6).withValues(alpha: 0.5)
                : hasImage
                ? const Color(0xFF22C55E).withValues(alpha: 0.5)
                : isRequired
                ? const Color(0xFFFF9500).withValues(alpha: 0.5)
                : AppColors.border.withValues(alpha: 0.5),
            width: hasImage || isProcessing ? 2 : 1.5,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
          boxShadow: hasImage
              ? [
                  BoxShadow(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.2),
                    blurRadius: 8,
                  ),
                ]
              : isProcessing
              ? [
                  BoxShadow(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: hasImage
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    // Image preview
                    kIsWeb
                        ? Image.network(
                            image.path,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                _buildPlaceholder(icon, label, isRequired),
                          )
                        : Image.file(
                            File(image.path),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                _buildPlaceholder(icon, label, isRequired),
                          ),
                    // Gradient overlay
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.7),
                            ],
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: Color(0xFF22C55E),
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                HapticService.lightImpact();
                                setState(() {
                                  if (label == 'Frente') {
                                    _insuranceCardFront = null;
                                  } else if (label == 'Reverso') {
                                    _insuranceCardBack = null;
                                  } else {
                                    _endorsementDoc = null;
                                  }
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : isProcessing
              ? _buildProcessingPlaceholder(label)
              : _buildPlaceholder(icon, label, isRequired),
        ),
      ),
    );
  }

  Widget _buildProcessingPlaceholder(String label) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: const Color(0xFF3B82F6),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Extrayendo datos...',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF3B82F6),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'VIN, Poliza, Compañia',
          style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildPlaceholder(IconData icon, String label, bool isRequired) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFF9500).withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: const Color(0xFFFF9500), size: 28),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.camera_alt_rounded,
              size: 12,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              isRequired ? 'Requerido' : 'Opcional',
              style: TextStyle(
                fontSize: 11,
                color: isRequired
                    ? const Color(0xFFFF9500)
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.words,
    String? Function(String?)? validator,
    String? fieldName,
  }) {
    final fieldId = fieldName ?? label.toLowerCase().replaceAll(' ', '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: TextInputType.none,
          textCapitalization: textCapitalization,
          validator: validator,
          onTap: () => _showKeyboardForField(fieldId, keyboardType),
          style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.5),
            ),
            prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 20),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: AppColors.border.withValues(alpha: 0.5),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AppColors.primary, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AppColors.error),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return GestureDetector(
      onTap: _isLoading ? null : _submitVehicle,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          gradient: _isLoading
              ? null
              : const LinearGradient(
                  colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                ),
          color: _isLoading ? AppColors.surface : null,
          borderRadius: BorderRadius.circular(18),
          boxShadow: _isLoading
              ? null
              : [
                  BoxShadow(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.4),
                    blurRadius: 15,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Center(
          child: _isLoading
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.textSecondary,
                  ),
                )
              : const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, color: Colors.white, size: 22),
                    SizedBox(width: 10),
                    Text(
                      'REGISTRAR VEHICULO',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1, end: 0);
  }
}
