import 'dart:io';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/app_colors.dart';
import '../services/document_service.dart';
import '../services/mexico_documents_service.dart';
import '../config/supabase_config.dart';
import 'pending_approval_screen.dart';
import '../widgets/datos_fiscales_sheet.dart';
import '../widgets/driver_connect_banner.dart';
import '../widgets/leyenda_retencion_isr.dart';
import '../models/driver_document_readiness.dart';
import '../services/driver_document_readiness_service.dart';


class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key, this.initialSection = 'personal'});

  final String initialSection;

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final DocumentService _documentService = DocumentService.instance;
  final MexicoDocumentsService _mexicoService = MexicoDocumentsService();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isLoading = false;
  bool _isMexico = false;
  bool _loadError = false;
  DriverDocumentReadiness? _readiness;
  Map<String, dynamic> _driverData = {};
  bool _initialSectionApplied = false;
  CompleteDocumentStatus? _completeStatus;
  String? _vehicleId;
  String? _driverId;

  List<DocumentItem> _personalDocs = [];
  List<DocumentItem> _vehicleDocs = [];

  // Fiscal MX (INE / RFC / CURP and any other state-required Mexican docs).
  // Reuses MexicoDocumentsService + DocumentService.uploadIneImage (OCR -> CURP)
  // so the merged tab behaves exactly like the old standalone MX screen.
  List<MexicoDocument> _mexicoDocs = [];
  List<MexicoDocumentType> _requiredMexicoDocs = [];
  String _driverStateCode = 'MX';
  String? _driverCurp;
  String? _driverRfc;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadDocuments();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDocuments() async {
    if (!mounted || _isLoading) return;
    setState(() {
      _isLoading = true;
      _loadError = false;
      _readiness = null;
    });
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) throw StateError('No authenticated driver');
      var driverRow = await SupabaseConfig.client.from('drivers').select()
          .eq('user_id', user.id).maybeSingle();
      driverRow ??= await SupabaseConfig.client.from('drivers').select()
          .eq('id', user.id).maybeSingle();
      if (driverRow == null) throw StateError('Driver not found');
      final country = driverRow['country_code']?.toString().trim().toUpperCase();
      if (country != 'MX' && country != 'US') {
        throw StateError('Driver country is not configured');
      }
      _driverData = driverRow;
      _driverId = driverRow['id'] as String;
      final isMexico = country == 'MX';
      _driverStateCode = (driverRow['state_code'] as String?) ?? 'MX';
      _driverRfc = driverRow['rfc'] as String?;
      _driverCurp = driverRow['curp'] as String?;
      _completeStatus = await _documentService.getCompleteStatus(_driverId!);
      _vehicleId = _completeStatus!.vehicleId;
      _requiredMexicoDocs = isMexico
          ? _mexicoService.getRequiredDocuments(_driverStateCode)
          : [];
      _mexicoDocs = isMexico
          ? await _mexicoService.getDriverDocuments(_driverId!)
          : [];
      try {
        _readiness = await DriverDocumentReadinessService.instance.load(_driverId!);
      } catch (e) {
        debugPrint('Documents readiness unavailable: $e');
      }
      if (!mounted) return;
      _isMexico = isMexico;
      final tabCount = _isMexico ? 4 : 3;
      final initialIndex = switch (widget.initialSection) {
        'vehicle' => 1,
        'tax' => 2,
        'payments' => tabCount - 1,
        _ => 0,
      };
      if (_tabController.length != tabCount) {
        final old = _tabController;
        _tabController = TabController(length: tabCount, vsync: this,
          initialIndex: _initialSectionApplied ? old.index.clamp(0, tabCount - 1).toInt() : initialIndex);
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      } else if (!_initialSectionApplied) {
        _tabController.index = initialIndex;
      }
      _initialSectionApplied = true;

      final driverDocs = _completeStatus!.driverDocs;
      final vehicleDocs = _completeStatus!.vehicleDocs;

      _personalDocs = [
        DocumentItem(
          'doc_drivers_license'.tr(),
          driverDocs.licenseNumber ?? 'doc_not_registered'.tr(),
          _buildExpiryText(driverDocs.licenseExpiry),
          Icons.credit_card,
          _mapLicenseStatus(driverDocs),
          onTap: () => _showUploadDialog(DocumentUploadType.license),
        ),
        DocumentItem(
          'doc_profile_photo'.tr(),
          driverDocs.hasProfilePhoto
              ? 'doc_uploaded'.tr()
              : 'doc_not_uploaded'.tr(),
          'doc_required_verification'.tr(),
          Icons.person,
          driverDocs.hasProfilePhoto
              ? DocumentStatus.received
              : DocumentStatus.missing,
          onTap: () => _showUploadDialog(DocumentUploadType.profilePhoto),
        ),
        DocumentItem(
          'doc_background_check'.tr(),
          _labelBackgroundCheckStatus(driverDocs.backgroundCheckStatus),
          'doc_auto_verification'.tr(),
          Icons.security,
          _mapBackgroundCheckStatus(driverDocs.backgroundCheckStatus),
        ),
        DocumentItem(
          'doc_driver_agreement'.tr(),
          driverDocs.agreementSigned
              ? 'driver_agreement_accepted'.tr()
              : 'driver_agreement_not_signed'.tr(),
          driverDocs.agreementSigned
              ? 'doc_auto_verification'.tr()
              : 'doc_required'.tr(),
          Icons.description,
          driverDocs.agreementSigned
              ? DocumentStatus.approved
              : DocumentStatus.missing,
          onTap: () => Navigator.pushNamed(
            context,
            '/driver-agreement',
          ).then((_) => _loadDocuments()),
        ),
      ];

      // ===== Vehículo + Seguro (MX) — driver-based (tabla drivers) =====
      // Seguro (póliza), Tarjeta de circulación y las 4 fotos por lado. Se
      // muestran SIEMPRE (no dependen de registrar un vehículo aparte) y se
      // suben a `drivers`, que es donde el admin (Documentos México) los lee.
      DocumentStatus mapDoc(String s) {
        switch (s) {
          case 'approved':
            return DocumentStatus.received;
          case 'expired':
          case 'rejected':
            return DocumentStatus.rejected;
          case 'expiring':
            return DocumentStatus.expiring;
          case 'pending':
            return DocumentStatus.pending;
          default:
            return DocumentStatus.missing;
        }
      }

      DocumentItem vehPhoto(
        String label,
        String hint,
        String? url,
        DocumentUploadType t,
      ) => DocumentItem(
        label,
        (url != null && url.isNotEmpty) ? 'docs.uploaded_check'.tr() : 'docs.not_provided_f'.tr(),
        hint,
        Icons.photo_camera,
        (url != null && url.isNotEmpty)
            ? DocumentStatus.received
            : DocumentStatus.missing,
        onTap: () => _showUploadDialog(t),
      );
      if (_isMexico) {
        _vehicleDocs = [
          DocumentItem(
            'docs.insurance_policy'.tr(),
            (driverDocs.hasInsurance || vehicleDocs?.hasInsurance == true) ? 'docs.uploaded_check_m'.tr() : 'docs.not_provided_m'.tr(),
            driverDocs.insuranceProvider ?? vehicleDocs?.insuranceCompany ?? 'docs.photo_current_policy'.tr(),
            Icons.shield,
            driverDocs.hasInsurance || vehicleDocs == null
                ? mapDoc(driverDocs.insuranceStatus) : _mapInsuranceStatus(vehicleDocs),
            onTap: () => _showUploadDialog(DocumentUploadType.insurancePolicy),
          ),
          DocumentItem(
            'docs.circulation_card'.tr(),
            (driverDocs.hasCirculationCard || vehicleDocs?.hasRegistration == true) ? 'docs.uploaded_check'.tr() : 'docs.not_provided_f'.tr(),
            driverDocs.circulationCardPlate != null
                ? '${'docs.plate'.tr()}: ${driverDocs.circulationCardPlate}'
                : 'docs.photo_circulation_card'.tr(),
            Icons.directions_car,
            vehicleDocs?.hasRegistration == true && !driverDocs.hasCirculationCard
                ? DocumentStatus.received : mapDoc(driverDocs.circulationCardStatus),
            onTap: () => _showUploadDialog(DocumentUploadType.circulationCard),
          ),
          vehPhoto(
            'docs.vehicle_photo_front'.tr(),
            'docs.front_of_car'.tr(),
            driverDocs.vehiclePhotoFrontUrl ?? vehicleDocs?.vehiclePhotoFrontUrl,
            DocumentUploadType.vehFront,
          ),
          vehPhoto(
            'docs.vehicle_photo_back'.tr(),
            'docs.rear_side'.tr(),
            driverDocs.vehiclePhotoBackUrl ?? vehicleDocs?.vehiclePhotoBackUrl,
            DocumentUploadType.vehBack,
          ),
          vehPhoto(
            'docs.vehicle_photo_left'.tr(),
            'docs.left_side'.tr(),
            driverDocs.vehiclePhotoLeftUrl,
            DocumentUploadType.vehLeft,
          ),
          vehPhoto(
            'docs.vehicle_photo_right'.tr(),
            'docs.right_side'.tr(),
            driverDocs.vehiclePhotoRightUrl,
            DocumentUploadType.vehRight,
          ),
        ];
      } else {
        final usVehicleDocs = vehicleDocs;
        _vehicleDocs = [
          DocumentItem(
            'doc_vehicle_insurance'.tr(),
            usVehicleDocs?.hasInsurance == true
                ? 'doc_uploaded'.tr()
                : 'doc_not_uploaded'.tr(),
            usVehicleDocs?.insuranceCompany ?? 'doc_required'.tr(),
            Icons.shield,
            usVehicleDocs == null
                ? DocumentStatus.missing
                : _mapInsuranceStatus(usVehicleDocs),
            onTap: () => _showUploadDialog(DocumentUploadType.insurance),
          ),
          DocumentItem(
            'doc_rideshare_endorsement'.tr(),
            usVehicleDocs?.hasEndorsement == true
                ? 'doc_uploaded'.tr()
                : 'doc_not_uploaded'.tr(),
            'doc_required'.tr(),
            Icons.verified,
            usVehicleDocs?.hasEndorsement == true
                ? DocumentStatus.pending
                : DocumentStatus.missing,
            onTap: () => _showUploadDialog(DocumentUploadType.endorsement),
          ),
          // La regla oficial cuenta la tarjeta de circulación en drivers.circulation_card_url
          // (vehicles no tiene registration_url ni columnas de fotos: esas subidas fallaban).
          DocumentItem(
            'doc_vehicle_registration'.tr(),
            (driverDocs.hasCirculationCard || usVehicleDocs?.hasRegistration == true)
                ? 'doc_uploaded'.tr()
                : 'doc_not_uploaded'.tr(),
            'doc_required'.tr(),
            Icons.directions_car,
            driverDocs.hasCirculationCard
                ? mapDoc(driverDocs.circulationCardStatus)
                : usVehicleDocs?.hasRegistration == true
                    ? DocumentStatus.pending
                    : DocumentStatus.missing,
            onTap: () => _showUploadDialog(DocumentUploadType.registration),
          ),
          vehPhoto('docs.vehicle_photo_front'.tr(), 'docs.front_of_car'.tr(),
              driverDocs.vehiclePhotoFrontUrl, DocumentUploadType.vehFront),
          vehPhoto('docs.vehicle_photo_back'.tr(), 'docs.rear_side'.tr(),
              driverDocs.vehiclePhotoBackUrl, DocumentUploadType.vehBack),
          vehPhoto('docs.vehicle_photo_left'.tr(), 'docs.left_side'.tr(),
              driverDocs.vehiclePhotoLeftUrl, DocumentUploadType.vehLeft),
          vehPhoto('docs.vehicle_photo_right'.tr(), 'docs.right_side'.tr(),
              driverDocs.vehiclePhotoRightUrl, DocumentUploadType.vehRight),
        ];
      }

      DriverDocumentReadinessService.instance.invalidate();
      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Documents load failed: $e');
      if (mounted) setState(() {
        _loadError = true;
        _isLoading = false;
      });
    }
  }

  DocumentStatus _mapLicenseStatus(DriverDocumentStatus driverDocs) {
    if (!driverDocs.hasLicenseImage) return DocumentStatus.missing;
    if (driverDocs.isLicenseExpired) return DocumentStatus.rejected;
    if (driverDocs.isLicenseExpiringSoon) return DocumentStatus.expiring;
    // Imagen subida pero el OCR aun no capturo el numero -> Pendiente (en revision),
    // no auto-aprobada: una imagen sin leer no debe contar como verificada.
    if (driverDocs.licenseNumber == null || driverDocs.licenseNumber!.isEmpty) {
      return DocumentStatus.pending;
    }
    return DocumentStatus.received;
  }

  DocumentStatus _mapInsuranceStatus(VehicleDocumentStatus vehicleDocs) {
    if (!vehicleDocs.hasInsurance) return DocumentStatus.missing;
    if (vehicleDocs.isInsuranceExpired) return DocumentStatus.rejected;
    if (!vehicleDocs.insuranceVerified) return DocumentStatus.pending;
    return DocumentStatus.approved;
  }

  DocumentStatus _mapBackgroundCheckStatus(String? status) {
    switch (status) {
      case 'approved':
      case 'passed':
        return DocumentStatus.approved;
      case 'pending':
        return DocumentStatus.pending;
      case 'failed':
      case 'rejected':
        return DocumentStatus.rejected;
      default:
        return DocumentStatus.pending;
    }
  }

  /// Texto que ve el chofer. Antes se pintaba el valor crudo de la base y en
  /// pantalla salia "pending" en ingles, en medio de todo lo demas en espanol.
  String _labelBackgroundCheckStatus(String? status) {
    switch (status) {
      case 'approved':
      case 'passed':
        return 'doc_bgcheck_approved'.tr();
      case 'failed':
      case 'rejected':
        return 'doc_bgcheck_failed'.tr();
      default:
        return 'doc_bgcheck_pending'.tr();
    }
  }

  String _buildExpiryText(DateTime? expiry) {
    if (expiry == null) return 'doc_no_expiry'.tr();

    final now = DateTime.now();
    final daysUntil = expiry.difference(now).inDays;

    if (daysUntil < 0) {
      return 'doc_expired_days'.tr(namedArgs: {'days': '${-daysUntil}'});
    } else if (daysUntil <= 30) {
      return 'doc_expires_days'.tr(namedArgs: {'days': '$daysUntil'});
    } else {
      final month = expiry.month.toString().padLeft(2, '0');
      final day = expiry.day.toString().padLeft(2, '0');
      return 'doc_valid_until'.tr(
        namedArgs: {'date': '$month/$day/${expiry.year}'},
      );
    }
  }

  void _showUploadDialog(DocumentUploadType type) {
    if (_driverId == null || _isLoading || _loadError) return;
    if (!_isMexico && _vehicleId == null &&
        ![DocumentUploadType.license, DocumentUploadType.profilePhoto].contains(type)) {
      Navigator.pushNamed(context, '/add-vehicle').then((_) => _loadDocuments());
      return;
    }
    if (type == DocumentUploadType.vehiclePhotos) {
      _showVehiclePhotoOptions();
      return;
    }
    String title;
    String description;
    IconData icon;

    switch (type) {
      case DocumentUploadType.license:
        title = 'doc_drivers_license'.tr();
        description = 'docs.take_clear_license_photo'.tr();
        icon = Icons.credit_card;
        break;
      case DocumentUploadType.profilePhoto:
        title = 'doc_profile_photo'.tr();
        description = 'docs.face_photo_clear_bg'.tr();
        icon = Icons.person;
        break;
      case DocumentUploadType.insurance:
        title = 'doc_vehicle_insurance'.tr();
        description = 'docs.insurance_card_photo'.tr();
        icon = Icons.shield;
        break;
      case DocumentUploadType.endorsement:
        title = 'doc_rideshare_endorsement'.tr();
        description = 'docs.tnc_endorsement_doc'.tr();
        icon = Icons.verified;
        break;
      case DocumentUploadType.registration:
        title = 'doc_vehicle_registration'.tr();
        description = 'docs.circulation_card'.tr();
        icon = Icons.directions_car;
        break;
      case DocumentUploadType.usFront:
      case DocumentUploadType.usBack:
      case DocumentUploadType.usInterior:
      case DocumentUploadType.usSide:
      case DocumentUploadType.vehiclePhotos:
        title = 'doc_vehicle_photos'.tr();
        description = 'docs.four_vehicle_photos'.tr();
        icon = Icons.photo_camera;
        break;
      case DocumentUploadType.insurancePolicy:
        title = 'docs.insurance_policy'.tr();
        description = 'docs.photo_current_insurance_policy'.tr();
        icon = Icons.shield;
        break;
      case DocumentUploadType.circulationCard:
        title = 'docs.circulation_card'.tr();
        description = 'docs.clear_photo_circulation_card'.tr();
        icon = Icons.directions_car;
        break;
      case DocumentUploadType.vehFront:
        title = 'docs.vehicle_photo_front'.tr();
        description = 'docs.take_front_photo'.tr();
        icon = Icons.photo_camera;
        break;
      case DocumentUploadType.vehBack:
        title = 'docs.vehicle_photo_back'.tr();
        description = 'docs.take_rear_photo'.tr();
        icon = Icons.photo_camera;
        break;
      case DocumentUploadType.vehLeft:
        title = 'docs.vehicle_photo_left'.tr();
        description = 'docs.take_left_photo'.tr();
        icon = Icons.photo_camera;
        break;
      case DocumentUploadType.vehRight:
        title = 'docs.vehicle_photo_right'.tr();
        description = 'docs.take_right_photo'.tr();
        icon = Icons.photo_camera;
        break;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Icon(icon, color: AppColors.primary, size: 32),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickAndUpload(type, ImageSource.camera),
                    icon: const Icon(Icons.camera_alt, size: 18),
                    label: Text('screens.documents.camera'.tr()),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickAndUpload(type, ImageSource.gallery),
                    icon: const Icon(Icons.photo_library, size: 18),
                    label: Text('screens.documents.gallery'.tr()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUpload(
    DocumentUploadType type,
    ImageSource source,
  ) async {
    Navigator.pop(context);

    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      final file = File(pickedFile.path);
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null || _driverId == null) return;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Text('screens.documents.uploading'.tr()),
              ],
            ),
            duration: const Duration(seconds: 30),
          ),
        );
      }

      bool success = false;

      switch (type) {
        case DocumentUploadType.license:
          final url = await _documentService.uploadLicenseImage(_driverId!, file);
          success = url != null;
          break;
        case DocumentUploadType.profilePhoto:
          final url = await _documentService.uploadProfilePhoto(_driverId!, file);
          success = url != null;
          break;
        case DocumentUploadType.insurance:
          if (_vehicleId != null) {
            success = await _documentService.uploadInsuranceCard(
              vehicleId: _vehicleId!,
              frontImage: file,
            );
          }
          break;
        case DocumentUploadType.endorsement:
          if (_vehicleId != null) {
            success = await _documentService.uploadEndorsementDocument(
              vehicleId: _vehicleId!,
              file: file,
            );
          }
          break;
        case DocumentUploadType.registration:
          success =
              await _documentService.uploadCirculationCard(_driverId!, file) !=
              null;
          break;
        case DocumentUploadType.vehiclePhotos:
        case DocumentUploadType.usFront:
        case DocumentUploadType.usBack:
        case DocumentUploadType.usInterior:
        case DocumentUploadType.usSide:
          if (_vehicleId != null) {
            success = await _documentService.uploadVehiclePhotos(
              vehicleId: _vehicleId!,
              frontPhoto: type == DocumentUploadType.usFront ? file : null,
              backPhoto: type == DocumentUploadType.usBack ? file : null,
              interiorPhoto: type == DocumentUploadType.usInterior ? file : null,
              sidePhoto: type == DocumentUploadType.usSide ? file : null,
            );
          }
          break;
        // ===== MX Fase 2: escriben a la tabla drivers =====
        case DocumentUploadType.insurancePolicy:
          success =
              await _documentService.uploadInsuranceImage(
                _driverId!,
                file,
              ) !=
              null;
          break;
        case DocumentUploadType.circulationCard:
          success =
              await _documentService.uploadCirculationCard(
                _driverId!,
                file,
              ) !=
              null;
          break;
        case DocumentUploadType.vehFront:
          success =
              await _documentService.uploadVehicleSidePhoto(
                _driverId!,
                'front',
                file,
              ) !=
              null;
          break;
        case DocumentUploadType.vehBack:
          success =
              await _documentService.uploadVehicleSidePhoto(
                _driverId!,
                'back',
                file,
              ) !=
              null;
          break;
        case DocumentUploadType.vehLeft:
          success =
              await _documentService.uploadVehicleSidePhoto(
                _driverId!,
                'left',
                file,
              ) !=
              null;
          break;
        case DocumentUploadType.vehRight:
          success =
              await _documentService.uploadVehicleSidePhoto(
                _driverId!,
                'right',
                file,
              ) !=
              null;
          break;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'docs.document_uploaded'.tr() : 'docs.upload_error'.tr()),
            backgroundColor: success ? AppColors.success : AppColors.error,
          ),
        );
        if (success) {
          await _loadDocuments();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // ==========================================================================
  // FISCAL MX TAB (INE / RFC / CURP + state-required Mexican documents)
  // Reuses MexicoDocumentsService and the INE OCR path so the merged tab
  // behaves exactly like the old standalone "Documentos México" screen.
  // ==========================================================================

  MexicoDocument? _getMexicoDocument(String type) {
    for (final document in _mexicoDocs) {
      if (document.documentType == type) return document;
    }
    final ine = _driverData['ine_image_url']?.toString().trim();
    if (type == 'ine' && ine != null && ine.isNotEmpty && _driverId != null) {
      return MexicoDocument(id: 'driver-ine', driverId: _driverId!, documentType: type,
        frontFileUrl: ine, verificationStatus: 'pending',
        createdAt: DateTime.tryParse(_driverData['updated_at']?.toString() ?? '') ?? DateTime.now());
    }
    return null;
  }

  Widget _buildMexicoTab() {
    return RefreshIndicator(
      onRefresh: _loadDocuments,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Text('docs_center_sat_description'.tr(), style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          _buildFiscalInfoCard(),
          const SizedBox(height: 12),
          if (_getMexicoDocument('rfcConstancia') != null)
            _buildMexicoDocumentCard(MexicoDocumentsService.allDocumentTypes
                .firstWhere((type) => type.type == 'rfcConstancia'))
          else TextButton.icon(icon: const Icon(Icons.attach_file),
            label: Text('docs_center_optional_certificate'.tr()),
            onPressed: () => _showMexicoUploadDialog(MexicoDocumentsService.allDocumentTypes
                .firstWhere((type) => type.type == 'rfcConstancia'))),
          _centerLink(Icons.account_balance, 'mx_tax_title'.tr(), '/mexico-tax'),
          _centerLink(Icons.receipt_long, 'mx_cfdi_title'.tr(), '/mexico-invoices'),
        ],
      ),
    );
  }

  Widget _centerLink(IconData icon, String label, String route) => Card(
    child: ListTile(leading: Icon(icon, color: AppColors.primary),
      title: Text(label), trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.pushNamed(context, route).then((_) => _loadDocuments())),
  );

  Widget _buildPaymentsTab() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
    children: [
      Text((_isMexico ? 'docs_center_payments_mx' : 'docs_center_payments_us').tr(),
          style: TextStyle(color: AppColors.textSecondary)),
      const SizedBox(height: 16),
      DriverConnectBanner(
        key: ValueKey('$_driverId-$_isMexico'),
        driverId: _driverId!, email: _driverData['email']?.toString() ?? '',
        provider: _isMexico ? 'mx' : 'us', margin: EdgeInsets.zero),
      const SizedBox(height: 12),
      _centerLink(Icons.account_balance, 'bank_account'.tr(), '/bank-account'),
    ],
  );

  Widget _buildReadinessSummary() {
    final readiness = _readiness;
    final ready = readiness?.hasRequiredDocuments == true;
    final countryMismatch = readiness?.hasCountryMismatch(_isMexico ? 'MX' : 'US') == true;
    final approved = _driverData['admin_approved'] == true &&
        _driverData['can_receive_rides'] == true &&
        _driverData['onboarding_stage'] == 'approved';
    final detail = countryMismatch ? 'docs_center_country_mismatch'.tr()
        : readiness == null ? 'docs_center_unavailable'.tr()
        : ready ? (approved ? 'docs_center_ready_desc' : 'docs_center_review_pending').tr()
        : [
            ...readiness.expired.map((type) => 'doc_tipo_vencido'.tr(args: ['doc_tipo_$type'.tr()])),
            ...readiness.missing.map((type) => 'doc_tipo_$type'.tr()),
          ].join(', ');
    return Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: ready ? AppColors.success.withValues(alpha: .08) : AppColors.warningSoft,
        borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text((ready ? 'docs_center_ready' : 'docs_center_title').tr(),
          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const SizedBox(height: 6), Text(detail, style: TextStyle(color: AppColors.textSecondary)),
        if (countryMismatch) TextButton(
          onPressed: () => Navigator.pushNamed(context, '/support'),
          child: Text('support'.tr())),
        if (readiness == null) TextButton(onPressed: _loadDocuments, child: Text('retry'.tr())),
        if (ready && !approved) TextButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PendingApprovalScreen())),
          child: Text('gate_why_blocked'.tr())),
      ]),
    );
  }

  Widget _buildFiscalInfoCard() {
    final rfc = (_driverRfc != null && _driverRfc!.isNotEmpty)
        ? _driverRfc!
        : 'doc_not_registered'.tr();
    final empresa = DatosFiscales.esEmpresa(_driverRfc);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFiscalRow(Icons.description, 'RFC', rfc),
          const SizedBox(height: 8),
          // Persona física o empresa: sale del RFC (12 = empresa, 13 = persona), nunca de una columna aparte.
          if ((_driverRfc ?? '').isNotEmpty) ...[
            _buildFiscalRow(empresa ? Icons.business : Icons.person, 'fiscal_tipo'.tr(),
                (empresa ? 'fiscal_tipo_moral' : 'fiscal_tipo_fisica').tr()),
            const SizedBox(height: 8),
          ],
          for (final field in {'fiscal_nombre': empresa ? 'fiscal_razon_social' : 'fiscal_nombre', 'fiscal_cp': 'fiscal_cp', 'fiscal_regimen': 'fiscal_regimen'}.entries)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: _buildFiscalRow(
              Icons.description_outlined, field.value.tr(),
              _valorFiscal(field.key))),
          if (_driverId != null) ...[
            const SizedBox(height: 8),
            // Botón visible: como texto plano nadie lo encontraba (Carlos, 13 oct 2026).
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final ok = await mostrarDatosFiscales(context, _driverId!);
                  if (ok && mounted) _loadDocuments();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.edit_note, size: 20),
                label: Text(
                  (_driverRfc ?? '').isEmpty ? 'fiscal_boton'.tr() : 'fiscal_editar'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (empresa) const LeyendaEmpresa() else const LeyendaRetencionIsr(),
          ],
        ],
      ),
    );
  }

  /// El régimen se guarda como clave SAT ('625'); en pantalla va con su nombre.
  String _valorFiscal(String campo) {
    final v = _driverData[campo]?.toString().trim() ?? '';
    if (v.isEmpty) return 'doc_not_registered'.tr();
    if (campo == 'fiscal_regimen' && DatosFiscales.regimenes.contains(v)) return 'fiscal_reg_$v'.tr();
    return v;
  }

  Widget _buildFiscalRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 18),
        const SizedBox(width: 10),
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildMexicoDocumentCard(MexicoDocumentType docType) {
    final doc = _getMexicoDocument(docType.type);

    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (doc == null) {
      statusColor = AppColors.error;
      statusIcon = Icons.cancel;
      statusText = 'mx_status_missing'.tr();
    } else if (doc.isExpired) {
      statusColor = AppColors.error;
      statusIcon = Icons.error;
      statusText = 'mx_status_expired'.tr();
    } else if (doc.isRejected) {
      statusColor = AppColors.error;
      statusIcon = Icons.block;
      statusText = 'mx_status_rejected'.tr();
    } else if (doc.isPending) {
      statusColor = AppColors.warning;
      statusIcon = Icons.hourglass_empty;
      statusText = 'mx_status_pending'.tr();
    } else if (doc.isExpiringSoon) {
      statusColor = AppColors.star;
      statusIcon = Icons.warning;
      statusText = 'mx_status_expiring'.tr();
    } else if (doc.isApproved) {
      statusColor = AppColors.success;
      statusIcon = Icons.check_circle;
      statusText = 'mx_status_approved'.tr();
    } else {
      statusColor = AppColors.warning;
      statusIcon = Icons.hourglass_empty;
      statusText = 'mx_status_pending'.tr();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _getMexicoDocIcon(docType.type),
            color: statusColor,
            size: 18,
          ),
        ),
        title: Text(
          docType.displayName,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              docType.description,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
            if (doc != null && doc.expiryDate != null)
              Text(
                'mx_expires'.tr(
                  namedArgs: {
                    'date': DateFormat('dd/MM/yyyy').format(doc.expiryDate!),
                  },
                ),
                style: TextStyle(
                  color: doc.isExpiringSoon
                      ? AppColors.warning
                      : AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(statusIcon, color: statusColor, size: 12),
              const SizedBox(width: 4),
              Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        onTap: () => _showMexicoUploadDialog(docType),
      ),
    );
  }

  IconData _getMexicoDocIcon(String type) {
    switch (type) {
      case 'ine':
        return Icons.badge;
      case 'rfcConstancia':
        return Icons.description;
      case 'licenciaE1':
      case 'driverLicense':
        return Icons.credit_card;
      case 'tarjeton':
        return Icons.card_membership;
      case 'constanciaSemovi':
      case 'constanciaVehicular':
        return Icons.verified;
      case 'seguroERT':
        return Icons.shield;
      case 'comprobanteDomicilio':
        return Icons.home;
      case 'cartaNoAntecedentes':
        return Icons.security;
      default:
        return Icons.folder;
    }
  }

  void _showMexicoUploadDialog(MexicoDocumentType docType) {
    DateTime? expiryDate;
    String? documentNumber;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Icon(
                _getMexicoDocIcon(docType.type),
                color: AppColors.primary,
                size: 32,
              ),
              const SizedBox(height: 12),
              Text(
                docType.displayName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                docType.description,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),

              // Document number input (INE / RFC)
              if (docType.type == 'ine' || docType.type == 'rfcConstancia') ...[
                TextField(
                  decoration: InputDecoration(
                    labelText: docType.type == 'rfcConstancia'
                        ? 'RFC'
                        : 'mx_doc_number'.tr(),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    filled: true,
                    fillColor: AppColors.card,
                  ),
                  onChanged: (value) => documentNumber = value,
                ),
                const SizedBox(height: 12),
              ],

              // Expiry date picker
              if (docType.hasExpiry)
                GestureDetector(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now().add(
                        const Duration(days: 365),
                      ),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(
                        const Duration(days: 365 * 10),
                      ),
                    );
                    if (date != null) {
                      setSheetState(() => expiryDate = date);
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
                        Icon(
                          Icons.calendar_today,
                          color: AppColors.primary,
                          size: 18,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          expiryDate != null
                              ? DateFormat('dd/MM/yyyy').format(expiryDate!)
                              : 'mx_select_expiry'.tr(),
                          style: TextStyle(
                            color: expiryDate != null
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickAndUploadMexico(
                        docType,
                        ImageSource.camera,
                        documentNumber,
                        expiryDate,
                      ),
                      icon: const Icon(Icons.camera_alt, size: 18),
                      label: Text('mx_camera'.tr()),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _pickAndUploadMexico(
                        docType,
                        ImageSource.gallery,
                        documentNumber,
                        expiryDate,
                      ),
                      icon: const Icon(Icons.photo_library, size: 18),
                      label: Text('mx_gallery'.tr()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadMexico(
    MexicoDocumentType docType,
    ImageSource source,
    String? documentNumber,
    DateTime? expiryDate,
  ) async {
    Navigator.pop(context);

    if (_driverId == null) return;

    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      final file = File(pickedFile.path);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Text('mx_uploading'.tr()),
              ],
            ),
            duration: const Duration(seconds: 30),
          ),
        );
      }

      // Pick back file if needed
      File? backFile;
      if (docType.hasFrontBack) {
        if (!mounted) return;
        final shouldUploadBack = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('mx_back_photo'.tr()),
            content: Text('mx_upload_back_question'.tr()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('mx_skip'.tr()),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('mx_upload'.tr()),
              ),
            ],
          ),
        );

        if (shouldUploadBack == true) {
          final backXFile = await _imagePicker.pickImage(
            source: source,
            maxWidth: 1920,
            maxHeight: 1920,
            imageQuality: 85,
          );
          if (backXFile != null) {
            backFile = File(backXFile.path);
          }
        }
      }

      await _mexicoService.uploadDocument(
        driverId: _driverId!,
        documentType: docType.type,
        frontFile: file,
        backFile: backFile,
        documentNumber: documentNumber,
        expiryDate: expiryDate,
      );

      // INE: also persist to drivers.ine_image_url + auto-OCR the CURP into
      // drivers.curp (read from the real document, never typed by the user).
      if (docType.type == 'ine') {
        await DocumentService.instance.uploadIneImage(_driverId!, file);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('mx_doc_uploaded'.tr()),
            backgroundColor: AppColors.success,
          ),
        );
        await _loadDocuments();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        // Se quito el icono de carpeta que iba antes del titulo: con el badge
        // y los tres botones de la derecha ya no cabia y el titulo salia
        // cortado ("Mis Documen..."). El Flexible se queda de red de seguridad
        // para idiomas con palabras mas largas.
        title: Row(
          children: [
            Flexible(
              child: Text(
                'documents_title'.tr(),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        actions: [
          // Unica entrada a PendingApprovalScreen. Ya no es una traba del
          // arranque: se abre desde aqui, con su flecha para regresar.
          IconButton(
            icon: Icon(
              Icons.help_outline_rounded,
              size: 20,
              color: AppColors.textSecondary,
            ),
            tooltip: 'gate_why_blocked'.tr(),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PendingApprovalScreen(),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.refresh, size: 20, color: AppColors.textSecondary),
            onPressed: _loadDocuments,
          ),
        ],
      ),
      body: Column(
        children: [
          // Tab bar
          Container(
            margin: const EdgeInsets.all(16),
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(8),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: AppColors.textSecondary,
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
              isScrollable: false,
              tabs: [
                Tab(text: 'documents_personal'.tr()),
                Tab(text: 'documents_vehicle'.tr()),
                if (_isMexico) Tab(text: 'docs.fiscal_mx'.tr()),
                Tab(text: 'docs_center_payments'.tr()),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _loadError ? Center(child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('docs_center_load_error'.tr(), textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _loadDocuments, child: Text('retry'.tr())),
                    ])))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildDocumentList(_personalDocs, vehicle: false),
                      _buildDocumentList(_vehicleDocs, vehicle: true),
                      if (_isMexico) _buildMexicoTab(),
                      _buildPaymentsTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentList(List<DocumentItem> docs, {required bool vehicle}) {
    final legacyType = vehicle ? 'seguroERT' : (_driverStateCode == 'CDMX' ? 'licenciaE1' : 'driverLicense');
    final useMexicoCard = _isMexico &&
        (legacyType == 'licenciaE1' ||
          (_getMexicoDocument(legacyType) != null &&
            (vehicle ? !_completeStatus!.driverDocs.hasInsurance &&
                _completeStatus!.vehicleDocs?.hasInsurance != true
              : !_completeStatus!.driverDocs.hasLicenseImage)));
    final extraMexicoDocs = _requiredMexicoDocs.where((type) =>
        !['driverLicense', 'licenciaE1', 'seguroERT'].contains(type.type) &&
        (vehicle ? type.type == 'constanciaVehicular' : type.type != 'constanciaVehicular'));
    return RefreshIndicator(onRefresh: _loadDocuments, child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        _buildReadinessSummary(),
        Text('docs_center_country'.tr(namedArgs: {
          'country': (_isMexico ? 'docs_center_mexico' : 'docs_center_us').tr(),
        }), style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 6),
        Text('docs_center_tap_document'.tr(), style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 12),
        if (vehicle) _centerLink(Icons.directions_car,
            (_vehicleId == null ? 'register_vehicle' : 'my_vehicle').tr(),
            _vehicleId == null ? '/add-vehicle' : '/vehicle'),
        if (!vehicle && _isMexico && (_driverCurp ?? '').isNotEmpty)
          Padding(padding: const EdgeInsets.only(bottom: 12),
            child: _buildFiscalRow(Icons.badge, 'CURP', _driverCurp!)),
        if (useMexicoCard) _buildMexicoDocumentCard(MexicoDocumentsService.allDocumentTypes
            .firstWhere((type) => type.type == legacyType)),
        ...docs.skip(useMexicoCard ? 1 : 0).map(_buildDocumentCard),
        ...extraMexicoDocs.map(_buildMexicoDocumentCard),
      ],
    ));
  }

  Widget _buildDocumentCard(DocumentItem doc) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (doc.status) {
      case DocumentStatus.approved:
        statusColor = AppColors.success;
        statusIcon = Icons.check_circle;
        statusText = 'status_approved'.tr();
        break;
      case DocumentStatus.received:
        statusColor = AppColors.primary;
        statusIcon = Icons.task_alt;
        statusText = 'docs_center_sent'.tr();
        break;
      case DocumentStatus.pending:
        statusColor = AppColors.warning;
        statusIcon = Icons.hourglass_empty;
        statusText = 'status_pending'.tr();
        break;
      case DocumentStatus.expiring:
        statusColor = AppColors.star;
        statusIcon = Icons.warning;
        statusText = 'status_expiring'.tr();
        break;
      case DocumentStatus.missing:
        statusColor = AppColors.error;
        statusIcon = Icons.cancel;
        statusText = 'status_missing'.tr();
        break;
      case DocumentStatus.rejected:
        statusColor = AppColors.error;
        statusIcon = Icons.error;
        statusText = 'status_expired'.tr();
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(doc.icon, color: statusColor, size: 18),
        ),
        title: Text(
          doc.title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              doc.subtitle,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 12),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    doc.description,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        onTap: doc.onTap ?? () => _showDocumentDetail(doc),
      ),
    );
  }

  void _showDocumentDetail(DocumentItem doc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(doc.icon, color: AppColors.primary, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    doc.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildDetailRow('documents_number_id'.tr(), doc.subtitle),
            _buildDetailRow('documents_status_label'.tr(), doc.description),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.upload_file, size: 18),
                label: Text('documents_update'.tr()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showVehiclePhotoOptions() {
    showModalBottomSheet(context: context, backgroundColor: AppColors.surface,
      builder: (sheetContext) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in const {
            DocumentUploadType.usFront: 'docs.vehicle_photo_front',
            DocumentUploadType.usBack: 'docs.vehicle_photo_back',
            DocumentUploadType.usInterior: 'docs_center_photo_interior',
            DocumentUploadType.usSide: 'docs_center_photo_side',
          }.entries)
            _buildUploadOption(Icons.photo_camera, entry.value.tr(), () {
              Navigator.pop(sheetContext);
              _showUploadDialog(entry.key);
            }),
        ],
      )),
    );
  }

  Widget _buildUploadOption(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: AppColors.primary, size: 20),
      title: Text(
        title,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: AppColors.textSecondary,
        size: 18,
      ),
      onTap: onTap,
    );
  }
}

class DocumentItem {
  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final DocumentStatus status;
  final VoidCallback? onTap;

  DocumentItem(
    this.title,
    this.subtitle,
    this.description,
    this.icon,
    this.status, {
    this.onTap,
  });
}

enum DocumentStatus { approved, received, pending, expiring, missing, rejected }

enum DocumentUploadType {
  license,
  profilePhoto,
  insurance,
  endorsement,
  registration,
  vehiclePhotos,
  usFront,
  usBack,
  usInterior,
  usSide,
  // MX Fase 2 (escriben a la tabla drivers):
  insurancePolicy,
  circulationCard,
  vehFront,
  vehBack,
  vehLeft,
  vehRight,
}
