import 'dart:io';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/app_colors.dart';
import '../services/mexico_documents_service.dart';
import '../config/supabase_config.dart';

class MexicoDocumentsScreen extends StatefulWidget {
  const MexicoDocumentsScreen({super.key});

  @override
  State<MexicoDocumentsScreen> createState() => _MexicoDocumentsScreenState();
}

class _MexicoDocumentsScreenState extends State<MexicoDocumentsScreen> {
  final MexicoDocumentsService _documentsService = MexicoDocumentsService();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isLoading = true;
  List<MexicoDocument> _documents = [];
  List<MexicoDocumentType> _requiredDocuments = [];
  String _driverStateCode = 'CDMX';
  String? _driverId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Get driver info
      final driverResponse = await SupabaseConfig.client
          .from('drivers')
          .select('id, state_code')
          .eq('user_id', user.id)
          .maybeSingle();

      if (driverResponse != null) {
        _driverId = driverResponse['id'];
        _driverStateCode = driverResponse['state_code'] ?? 'CDMX';

        // Get required documents for state
        _requiredDocuments = _documentsService.getRequiredDocuments(_driverStateCode);

        // Get uploaded documents
        _documents = await _documentsService.getDriverDocuments(_driverId!);
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  MexicoDocument? _getDocument(String type) {
    try {
      return _documents.firstWhere((d) => d.documentType == type);
    } catch (e) {
      return null;
    }
  }

  int get _approvedCount => _documents.where((d) => d.isApproved).length;
  int get _totalRequired => _requiredDocuments.length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Image.asset('assets/images/mexico_flag.png', width: 24, height: 16,
              errorBuilder: (_, __, ___) => const Icon(Icons.flag, size: 18, color: AppColors.primary),
            ),
            const SizedBox(width: 8),
            Text('mx_documents_title'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
                Text('$_approvedCount/$_totalRequired', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.refresh, size: 20, color: AppColors.textSecondary),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // State indicator
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
                          '$_totalRequired ${'mx_docs_required'.tr()}',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Progress
                  _buildProgress(),
                  const SizedBox(height: 16),

                  // Documents list
                  ..._requiredDocuments.map((docType) => _buildDocumentCard(docType)),

                  // Expiring soon section
                  if (_documents.any((d) => d.isExpiringSoon)) ...[
                    const SizedBox(height: 24),
                    Text('mx_expiring_soon'.tr(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.warning)),
                    const SizedBox(height: 8),
                    ..._documents.where((d) => d.isExpiringSoon).map((doc) => _buildExpiringCard(doc)),
                  ],

                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _buildProgress() {
    final progress = _totalRequired > 0 ? _approvedCount / _totalRequired : 0.0;

    return Container(
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
              Text('mx_docs_progress'.tr(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
            progress == 1.0 ? 'mx_docs_complete'.tr() : 'mx_docs_pending'.tr(namedArgs: {'count': '${_totalRequired - _approvedCount}'}),
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentCard(MexicoDocumentType docType) {
    final doc = _getDocument(docType.type);
    final hasDoc = doc != null;

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
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(_getDocIcon(docType.type), color: statusColor, size: 20),
        ),
        title: Text(
          docType.displayName,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary),
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
        onTap: () => _showUploadDialog(docType),
      ),
    );
  }

  Widget _buildExpiringCard(MexicoDocument doc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: AppColors.warning, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.documentTypeInfo?.displayName ?? doc.documentType,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  'mx_days_to_expire'.tr(namedArgs: {'days': '${doc.daysUntilExpiry}'}),
                  style: TextStyle(color: AppColors.warning, fontSize: 11),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _showUploadDialog(doc.documentTypeInfo!),
            child: Text('mx_renew'.tr(), style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  IconData _getDocIcon(String type) {
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

  void _showUploadDialog(MexicoDocumentType docType) {
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
              Icon(_getDocIcon(docType.type), color: AppColors.primary, size: 32),
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

              // Document number input (if applicable)
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

              // Expiry date picker (if has expiry)
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
                      onPressed: () => _pickAndUpload(docType, ImageSource.camera, documentNumber, expiryDate),
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
                      onPressed: () => _pickAndUpload(docType, ImageSource.gallery, documentNumber, expiryDate),
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

  Future<void> _pickAndUpload(
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

      await _documentsService.uploadDocument(
        driverId: _driverId!,
        documentType: docType.type,
        frontFile: file,
        backFile: backFile,
        documentNumber: documentNumber,
        expiryDate: expiryDate,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('mx_doc_uploaded'.tr()),
            backgroundColor: AppColors.success,
          ),
        );
        _loadData();
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
}
