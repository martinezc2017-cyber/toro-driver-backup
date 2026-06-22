import 'dart:io';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/app_colors.dart';
import '../services/document_service.dart';
import '../services/mexico_documents_service.dart';
import '../config/supabase_config.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DocumentService _documentService = DocumentService.instance;
  final MexicoDocumentsService _mexicoService = MexicoDocumentsService();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isLoading = true;
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
  String _driverStateCode = 'CDMX';
  String? _driverCurp;
  String? _driverRfc;

  int get _totalDocs => _personalDocs.length + _vehicleDocs.length + _requiredMexicoDocs.length;
  int get _approvedDocs =>
      _personalDocs.where((d) => d.status == DocumentStatus.approved).length +
      _vehicleDocs.where((d) => d.status == DocumentStatus.approved).length +
      _mexicoDocs.where((d) => d.isApproved).length;

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
    setState(() => _isLoading = true);

    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      _completeStatus = await _documentService.getCompleteStatus(user.id);
      _vehicleId = await _documentService.getDriverVehicleId(user.id);

      // Resolve the real drivers.id (+ state / RFC / CURP) for the Fiscal MX tab.
      // The MX document service keys off drivers.id, not the auth user id.
      try {
        final driverRow = await SupabaseConfig.client
            .from('drivers')
            .select('id, state_code, rfc, curp')
            .eq('user_id', user.id)
            .maybeSingle();

        if (driverRow != null) {
          _driverId = driverRow['id'] as String?;
          _driverStateCode = (driverRow['state_code'] as String?) ?? 'CDMX';
          _driverRfc = driverRow['rfc'] as String?;
          _driverCurp = driverRow['curp'] as String?;

          _requiredMexicoDocs = _mexicoService.getRequiredDocuments(_driverStateCode);
          if (_driverId != null) {
            _mexicoDocs = await _mexicoService.getDriverDocuments(_driverId!);
          }
        }
      } catch (_) {
        // Non-fatal: keep the rest of the screen working if MX load fails.
        _requiredMexicoDocs = [];
        _mexicoDocs = [];
      }

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
          driverDocs.hasProfilePhoto ? 'doc_uploaded'.tr() : 'doc_not_uploaded'.tr(),
          'doc_required_verification'.tr(),
          Icons.person,
          driverDocs.hasProfilePhoto ? DocumentStatus.approved : DocumentStatus.missing,
          onTap: () => _showUploadDialog(DocumentUploadType.profilePhoto),
        ),
        DocumentItem(
          'doc_background_check'.tr(),
          driverDocs.backgroundCheckStatus ?? 'Pendiente',
          'doc_auto_verification'.tr(),
          Icons.security,
          _mapBackgroundCheckStatus(driverDocs.backgroundCheckStatus),
        ),
        DocumentItem(
          'doc_driver_agreement'.tr(),
          driverDocs.agreementSigned ? 'driver_agreement_accepted'.tr() : 'driver_agreement_not_signed'.tr(),
          driverDocs.agreementSigned ? 'doc_auto_verification'.tr() : 'doc_required'.tr(),
          Icons.description,
          driverDocs.agreementSigned ? DocumentStatus.approved : DocumentStatus.missing,
          onTap: () => Navigator.pushNamed(context, '/driver-agreement').then((_) => _loadDocuments()),
        ),
      ];

      // ===== Vehículo + Seguro (MX) — driver-based (tabla drivers) =====
      // Seguro (póliza), Tarjeta de circulación y las 4 fotos por lado. Se
      // muestran SIEMPRE (no dependen de registrar un vehículo aparte) y se
      // suben a `drivers`, que es donde el admin (Documentos México) los lee.
      DocumentStatus mapDoc(String s) {
        switch (s) {
          case 'approved':
            return DocumentStatus.approved;
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
      DocumentItem vehPhoto(String label, String hint, String? url, DocumentUploadType t) =>
          DocumentItem(
            label,
            (url != null && url.isNotEmpty) ? 'Subida ✓' : 'No proporcionada',
            hint,
            Icons.photo_camera,
            (url != null && url.isNotEmpty) ? DocumentStatus.approved : DocumentStatus.missing,
            onTap: () => _showUploadDialog(t),
          );
      _vehicleDocs = [
        DocumentItem(
          'Seguro (póliza)',
          driverDocs.hasInsurance ? 'Subido ✓' : 'No proporcionado',
          driverDocs.insuranceProvider ?? 'Foto de la póliza vigente',
          Icons.shield,
          mapDoc(driverDocs.insuranceStatus),
          onTap: () => _showUploadDialog(DocumentUploadType.insurancePolicy),
        ),
        DocumentItem(
          'Tarjeta de circulación',
          driverDocs.hasCirculationCard ? 'Subida ✓' : 'No proporcionada',
          driverDocs.circulationCardPlate != null
              ? 'Placa: ${driverDocs.circulationCardPlate}'
              : 'Foto de la tarjeta de circulación',
          Icons.directions_car,
          mapDoc(driverDocs.circulationCardStatus),
          onTap: () => _showUploadDialog(DocumentUploadType.circulationCard),
        ),
        vehPhoto('Foto del vehículo — Frente', 'Frente del auto',
            driverDocs.vehiclePhotoFrontUrl, DocumentUploadType.vehFront),
        vehPhoto('Foto del vehículo — Atrás', 'Parte trasera',
            driverDocs.vehiclePhotoBackUrl, DocumentUploadType.vehBack),
        vehPhoto('Foto del vehículo — Izquierda', 'Costado izquierdo',
            driverDocs.vehiclePhotoLeftUrl, DocumentUploadType.vehLeft),
        vehPhoto('Foto del vehículo — Derecha', 'Costado derecho',
            driverDocs.vehiclePhotoRightUrl, DocumentUploadType.vehRight),
      ];

      setState(() => _isLoading = false);
    } catch (e) {
      //DocumentsScreen: Error loading documents: $e');
      _personalDocs = [
        DocumentItem('doc_drivers_license'.tr(), 'doc_not_uploaded'.tr(), 'doc_required'.tr(), Icons.credit_card, DocumentStatus.missing),
      ];
      _vehicleDocs = [
        DocumentItem('doc_vehicle_insurance'.tr(), 'doc_not_uploaded'.tr(), 'doc_required'.tr(), Icons.shield, DocumentStatus.missing),
      ];
      setState(() => _isLoading = false);
    }
  }

  DocumentStatus _mapLicenseStatus(DriverDocumentStatus driverDocs) {
    if (!driverDocs.hasLicense) return DocumentStatus.missing;
    if (driverDocs.isLicenseExpired) return DocumentStatus.rejected;
    if (driverDocs.isLicenseExpiringSoon) return DocumentStatus.expiring;
    // Imagen subida pero el OCR aun no capturo el numero -> Pendiente (en revision),
    // no auto-aprobada: una imagen sin leer no debe contar como verificada.
    if (driverDocs.licenseNumber == null || driverDocs.licenseNumber!.isEmpty) {
      return DocumentStatus.pending;
    }
    return DocumentStatus.approved;
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
        return DocumentStatus.rejected;
      default:
        return DocumentStatus.pending;
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
      return 'doc_valid_until'.tr(namedArgs: {'date': '$month/$day/${expiry.year}'});
    }
  }

  /// Check if all required documents are complete and activate driver
  Future<void> _checkAndActivateDriver(String userId) async {
    try {
      // Get driver data by user_id
      final driverResponse = await SupabaseConfig.client
          .from('drivers')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (driverResponse == null) return;

      final driver = driverResponse;

      // Check all required documents
      final bool hasAgreement = driver['agreement_signed'] == true;
      final bool hasLicense = driver['license_number'] != null &&
                              driver['license_image_url'] != null;
      final bool hasProfilePhoto = driver['profile_photo_url'] != null;
      final bool hasBackgroundCheck = driver['background_check_status'] == 'approved';
      final bool hasVehicle = driver['vehicle_make'] != null &&
                              driver['vehicle_model'] != null;
      final bool hasInsurance = driver['insurance_policy'] != null;

      // All documents complete?
      final bool allComplete = hasAgreement &&
                               hasLicense &&
                               hasProfilePhoto &&
                               hasBackgroundCheck &&
                               hasVehicle &&
                               hasInsurance;

      if (allComplete) {
        await SupabaseConfig.client.from('drivers').update({
          'status': 'active',
          'is_active': true,
          'can_receive_rides': true,
        }).eq('id', driver['id']);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.celebration, color: Colors.white),
                  const SizedBox(width: 8),
                  Text('screens.documents.all_complete'.tr()),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      //Error checking driver activation: $e');
    }
  }

  void _showUploadDialog(DocumentUploadType type) {
    String title;
    String description;
    IconData icon;

    switch (type) {
      case DocumentUploadType.license:
        title = 'doc_drivers_license'.tr();
        description = 'Toma foto clara de tu licencia';
        icon = Icons.credit_card;
        break;
      case DocumentUploadType.profilePhoto:
        title = 'doc_profile_photo'.tr();
        description = 'Foto de tu rostro, fondo claro';
        icon = Icons.person;
        break;
      case DocumentUploadType.insurance:
        title = 'doc_vehicle_insurance'.tr();
        description = 'Foto de tu tarjeta de seguro';
        icon = Icons.shield;
        break;
      case DocumentUploadType.endorsement:
        title = 'doc_rideshare_endorsement'.tr();
        description = 'Documento de endoso TNC';
        icon = Icons.verified;
        break;
      case DocumentUploadType.registration:
        title = 'doc_vehicle_registration'.tr();
        description = 'Tarjeta de circulación';
        icon = Icons.directions_car;
        break;
      case DocumentUploadType.vehiclePhotos:
        title = 'doc_vehicle_photos'.tr();
        description = '4 fotos del vehículo';
        icon = Icons.photo_camera;
        break;
      case DocumentUploadType.insurancePolicy:
        title = 'Seguro (póliza)';
        description = 'Foto de la póliza de seguro vigente';
        icon = Icons.shield;
        break;
      case DocumentUploadType.circulationCard:
        title = 'Tarjeta de circulación';
        description = 'Foto clara de la tarjeta de circulación';
        icon = Icons.directions_car;
        break;
      case DocumentUploadType.vehFront:
        title = 'Foto del vehículo — Frente';
        description = 'Toma la foto del frente del auto';
        icon = Icons.photo_camera;
        break;
      case DocumentUploadType.vehBack:
        title = 'Foto del vehículo — Atrás';
        description = 'Toma la foto de la parte trasera';
        icon = Icons.photo_camera;
        break;
      case DocumentUploadType.vehLeft:
        title = 'Foto del vehículo — Izquierda';
        description = 'Toma la foto del costado izquierdo';
        icon = Icons.photo_camera;
        break;
      case DocumentUploadType.vehRight:
        title = 'Foto del vehículo — Derecha';
        description = 'Toma la foto del costado derecho';
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
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

  Future<void> _pickAndUpload(DocumentUploadType type, ImageSource source) async {
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
      if (user == null) return;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
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
          final url = await _documentService.uploadLicenseImage(user.id, file);
          success = url != null;
          break;
        case DocumentUploadType.profilePhoto:
          final url = await _documentService.uploadProfilePhoto(user.id, file);
          success = url != null;
          break;
        case DocumentUploadType.insurance:
          if (_vehicleId != null) {
            success = await _documentService.uploadInsuranceCard(vehicleId: _vehicleId!, frontImage: file);
          }
          break;
        case DocumentUploadType.endorsement:
          if (_vehicleId != null) {
            success = await _documentService.uploadEndorsementDocument(vehicleId: _vehicleId!, file: file);
          }
          break;
        case DocumentUploadType.registration:
          if (_vehicleId != null) {
            success = await _documentService.uploadRegistration(_vehicleId!, file);
          }
          break;
        case DocumentUploadType.vehiclePhotos:
          if (_vehicleId != null) {
            success = await _documentService.uploadVehiclePhotos(vehicleId: _vehicleId!, frontPhoto: file);
          }
          break;
        // ===== MX Fase 2: escriben a la tabla drivers =====
        case DocumentUploadType.insurancePolicy:
          success = await _documentService.uploadInsuranceImage(
                  _driverId ?? user.id, file) !=
              null;
          break;
        case DocumentUploadType.circulationCard:
          success = await _documentService.uploadCirculationCard(
                  _driverId ?? user.id, file) !=
              null;
          break;
        case DocumentUploadType.vehFront:
          success = await _documentService.uploadVehicleSidePhoto(
                  _driverId ?? user.id, 'front', file) !=
              null;
          break;
        case DocumentUploadType.vehBack:
          success = await _documentService.uploadVehicleSidePhoto(
                  _driverId ?? user.id, 'back', file) !=
              null;
          break;
        case DocumentUploadType.vehLeft:
          success = await _documentService.uploadVehicleSidePhoto(
                  _driverId ?? user.id, 'left', file) !=
              null;
          break;
        case DocumentUploadType.vehRight:
          success = await _documentService.uploadVehicleSidePhoto(
                  _driverId ?? user.id, 'right', file) !=
              null;
          break;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Documento subido' : 'Error al subir'),
            backgroundColor: success ? AppColors.success : AppColors.error,
          ),
        );
        if (success) {
          _loadDocuments();
          // Check if all documents are complete to activate driver
          await _checkAndActivateDriver(user.id);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
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
    try {
      return _mexicoDocs.firstWhere((d) => d.documentType == type);
    } catch (_) {
      return null;
    }
  }

  Widget _buildMexicoTab() {
    if (_requiredMexicoDocs.isEmpty) {
      // No driver row resolved / no MX docs required for this state.
      return RefreshIndicator(
        onRefresh: _loadDocuments,
        color: AppColors.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          children: [
            Icon(Icons.flag_outlined, color: AppColors.textSecondary, size: 40),
            const SizedBox(height: 12),
            Text(
              'mx_documents_title'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              _driverStateCode,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final approved = _mexicoDocs.where((d) => d.isApproved).length;
    final total = _requiredMexicoDocs.length;
    final progress = total > 0 ? approved / total : 0.0;

    return RefreshIndicator(
      onRefresh: _loadDocuments,
      color: AppColors.primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          // State + required count
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.location_on, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'mx_state'.tr(namedArgs: {'state': _driverStateCode}),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const Spacer(),
                Text(
                  '$total ${'mx_docs_required'.tr()}',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Progress bar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('mx_docs_progress'.tr(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    Text('${(progress * 100).toInt()}%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: AppColors.border,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  progress == 1.0
                      ? 'mx_docs_complete'.tr()
                      : 'mx_docs_pending'.tr(namedArgs: {'count': '${total - approved}'}),
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // RFC / CURP read-only summary (from drivers.rfc / drivers.curp).
          // CURP is auto-extracted by OCR when the INE is uploaded.
          _buildFiscalInfoCard(),
          const SizedBox(height: 12),

          // Required MX document cards
          ..._requiredMexicoDocs.map((docType) => _buildMexicoDocumentCard(docType)),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildFiscalInfoCard() {
    final rfc = (_driverRfc != null && _driverRfc!.isNotEmpty) ? _driverRfc! : 'doc_not_registered'.tr();
    final curp = (_driverCurp != null && _driverCurp!.isNotEmpty) ? _driverCurp! : 'doc_not_registered'.tr();

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
          _buildFiscalRow(Icons.badge, 'CURP', curp),
        ],
      ),
    );
  }

  Widget _buildFiscalRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 18),
        const SizedBox(width: 10),
        SizedBox(
          width: 48,
          child: Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
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
    } else {
      statusColor = AppColors.success;
      statusIcon = Icons.check_circle;
      statusText = 'mx_status_approved'.tr();
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
          child: Icon(_getMexicoDocIcon(docType.type), color: statusColor, size: 18),
        ),
        title: Text(
          docType.displayName,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(docType.description, style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            if (doc != null && doc.expiryDate != null)
              Text(
                'mx_expires'.tr(namedArgs: {'date': DateFormat('dd/MM/yyyy').format(doc.expiryDate!)}),
                style: TextStyle(color: doc.isExpiringSoon ? AppColors.warning : AppColors.textSecondary, fontSize: 10),
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
              Text(statusText, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w600)),
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
              Icon(_getMexicoDocIcon(docType.type), color: AppColors.primary, size: 32),
              const SizedBox(height: 12),
              Text(
                docType.displayName,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
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
                    labelText: docType.type == 'rfcConstancia' ? 'RFC' : 'mx_doc_number'.tr(),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
                      initialDate: DateTime.now().add(const Duration(days: 365)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
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
                        Icon(Icons.calendar_today, color: AppColors.primary, size: 18),
                        const SizedBox(width: 12),
                        Text(
                          expiryDate != null
                              ? DateFormat('dd/MM/yyyy').format(expiryDate!)
                              : 'mx_select_expiry'.tr(),
                          style: TextStyle(color: expiryDate != null ? AppColors.textPrimary : AppColors.textSecondary),
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
                      onPressed: () => _pickAndUploadMexico(docType, ImageSource.camera, documentNumber, expiryDate),
                      icon: const Icon(Icons.camera_alt, size: 18),
                      label: Text('mx_camera'.tr()),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _pickAndUploadMexico(docType, ImageSource.gallery, documentNumber, expiryDate),
                      icon: const Icon(Icons.photo_library, size: 18),
                      label: Text('mx_gallery'.tr()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
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
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
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
        title: Row(
          children: [
            Icon(Icons.folder, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('documents_title'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: AppColors.success, size: 14),
                const SizedBox(width: 4),
                Text('$_approvedDocs/$_totalDocs', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 12)),
              ],
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
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              isScrollable: false,
              tabs: [
                Tab(text: 'documents_personal'.tr()),
                Tab(text: 'documents_vehicle'.tr()),
                const Tab(text: 'Fiscal MX'),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildDocumentList(_personalDocs),
                      _buildDocumentList(_vehicleDocs),
                      _buildMexicoTab(),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.small(
        onPressed: _showUploadOptions,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.black, size: 20),
      ),
    );
  }

  Widget _buildDocumentList(List<DocumentItem> docs) {
    final approved = docs.where((d) => d.status == DocumentStatus.approved).length;
    final total = docs.length;
    final progress = total > 0 ? approved / total : 0.0;

    return RefreshIndicator(
      onRefresh: _loadDocuments,
      color: AppColors.primary,
      child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // Simple progress bar
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'documents_status'.tr(),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                  Text(
                    '${(progress * 100).toInt()}%',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: AppColors.border,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                approved == total
                    ? 'documents_complete'.tr()
                    : 'documents_missing'.tr(namedArgs: {'count': '${total - approved}'}),
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ...docs.map((doc) => _buildDocumentCard(doc)),
        const SizedBox(height: 80),
      ],
      ),
    );
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
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(doc.subtitle, style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 12),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    doc.description,
                    style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w500),
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
            style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w600),
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
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
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
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
            child: Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  void _showUploadOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            Text('Subir documento', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            _buildUploadOption(Icons.credit_card, 'Licencia', () {
              Navigator.pop(context);
              _showUploadDialog(DocumentUploadType.license);
            }),
            _buildUploadOption(Icons.person, 'Foto de perfil', () {
              Navigator.pop(context);
              _showUploadDialog(DocumentUploadType.profilePhoto);
            }),
            if (_vehicleId != null) ...[
              _buildUploadOption(Icons.shield, 'Seguro', () {
                Navigator.pop(context);
                _showUploadDialog(DocumentUploadType.insurance);
              }),
              _buildUploadOption(Icons.verified, 'Endoso', () {
                Navigator.pop(context);
                _showUploadDialog(DocumentUploadType.endorsement);
              }),
              _buildUploadOption(Icons.photo_camera, 'Fotos vehículo', () {
                Navigator.pop(context);
                _showUploadDialog(DocumentUploadType.vehiclePhotos);
              }),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadOption(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: AppColors.primary, size: 20),
      title: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
      trailing: Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 18),
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

  DocumentItem(this.title, this.subtitle, this.description, this.icon, this.status, {this.onTap});
}

enum DocumentStatus { approved, pending, expiring, missing, rejected }

enum DocumentUploadType {
  license,
  profilePhoto,
  insurance,
  endorsement,
  registration,
  vehiclePhotos,
  // MX Fase 2 (escriben a la tabla drivers):
  insurancePolicy,
  circulationCard,
  vehFront,
  vehBack,
  vehLeft,
  vehRight,
}
