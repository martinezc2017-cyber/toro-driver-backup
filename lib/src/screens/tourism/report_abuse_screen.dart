import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/tourism_event_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';

/// Pantalla para que el conductor u organizador reporte abuso, problemas de
/// seguridad, fraude de precios u otros incidentes relacionados con un evento
/// de turismo.
///
/// Campos:
/// - Tipo de reporte (passenger_abuse, safety_issue, pricing_fraud, other)
/// - Severidad (low, medium, high, critical)
/// - Descripcion del incidente (campo de texto libre)
///
/// Al enviar, se crea un registro en `tourism_abuse_reports`.
class ReportAbuseScreen extends StatefulWidget {
  final String eventId;
  final String? eventTitle;
  final String? reportedUserId;

  const ReportAbuseScreen({
    super.key,
    required this.eventId,
    this.eventTitle,
    this.reportedUserId,
  });

  @override
  State<ReportAbuseScreen> createState() => _ReportAbuseScreenState();
}

class _ReportAbuseScreenState extends State<ReportAbuseScreen> {
  final TourismEventService _eventService = TourismEventService();
  final TextEditingController _descriptionController =
      TextEditingController();
  final FocusNode _descriptionFocus = FocusNode();

  String? _selectedType;
  String? _selectedSeverity;
  bool _isSubmitting = false;

  // Report type options (keys resolved at build time via .tr())
  static const List<Map<String, dynamic>> _reportTypesRaw = [
    {
      'value': 'passenger_abuse',
      'labelKey': 'report_abuse_passenger',
      'icon': Icons.person_off_rounded,
      'descKey': 'report_abuse_passenger_desc',
    },
    {
      'value': 'safety_issue',
      'labelKey': 'report_abuse_safety',
      'icon': Icons.health_and_safety_rounded,
      'descKey': 'report_abuse_safety_desc',
    },
    {
      'value': 'pricing_fraud',
      'labelKey': 'report_abuse_pricing',
      'icon': Icons.money_off_rounded,
      'descKey': 'report_abuse_pricing_desc',
    },
    {
      'value': 'other',
      'labelKey': 'report_abuse_other',
      'icon': Icons.report_problem_rounded,
      'descKey': 'report_abuse_other_desc',
    },
  ];

  // Severity options (keys resolved at build time via .tr())
  static const List<Map<String, dynamic>> _severityOptionsRaw = [
    {
      'value': 'low',
      'labelKey': 'report_severity_low',
      'descKey': 'report_severity_low_desc',
    },
    {
      'value': 'medium',
      'labelKey': 'report_severity_medium',
      'descKey': 'report_severity_medium_desc',
    },
    {
      'value': 'high',
      'labelKey': 'report_severity_high',
      'descKey': 'report_severity_high_desc',
    },
    {
      'value': 'critical',
      'labelKey': 'report_severity_critical',
      'descKey': 'report_severity_critical_desc',
    },
  ];

  @override
  void dispose() {
    _descriptionController.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _selectedType != null &&
      _selectedSeverity != null &&
      _descriptionController.text.trim().length >= 10;

  Color _severityColor(String value) {
    switch (value) {
      case 'low':
        return AppColors.info;
      case 'medium':
        return AppColors.warning;
      case 'high':
        return AppColors.error;
      case 'critical':
        return AppColors.errorDark;
      default:
        return AppColors.textTertiary;
    }
  }

  Future<void> _submitReport() async {
    if (!_canSubmit || _isSubmitting) return;

    HapticService.mediumImpact();
    setState(() => _isSubmitting = true);

    try {
      await _eventService.submitAbuseReport(
        eventId: widget.eventId,
        reportedUserId: widget.reportedUserId,
        reportType: _selectedType!,
        severity: _selectedSeverity!,
        description: _descriptionController.text.trim(),
      );

      HapticService.success();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'report_abuse_sent_success'.tr()),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 4),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      HapticService.error();

      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('report_abuse_error'.tr(namedArgs: {'error': '$e'})),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.background,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: GestureDetector(
                  onTap: () =>
                      FocusScope.of(context).unfocus(),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildInfoBanner(),
                      const SizedBox(height: 20),
                      _buildReportTypeSection(),
                      const SizedBox(height: 20),
                      _buildSeveritySection(),
                      const SizedBox(height: 20),
                      _buildDescriptionSection(),
                      const SizedBox(height: 28),
                      _buildSubmitButton(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(
            color: AppColors.border.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
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
                  color:
                      AppColors.border.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: AppColors.textSecondary,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'report_abuse_title'.tr(),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (widget.eventTitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.eventTitle!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.info.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AppColors.info,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'report_abuse_info_banner'.tr(),
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportTypeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'report_abuse_type'.tr(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        ..._reportTypesRaw.map((type) {
          final isSelected =
              _selectedType == type['value'];
          return GestureDetector(
            onTap: () {
              HapticService.selectionClick();
              setState(() =>
                  _selectedType = type['value'] as String);
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.error
                        .withValues(alpha: 0.08)
                    : AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? AppColors.error
                          .withValues(alpha: 0.4)
                      : AppColors.border,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    type['icon'] as IconData,
                    color: isSelected
                        ? AppColors.error
                        : AppColors.textTertiary,
                    size: 22,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          (type['labelKey'] as String).tr(),
                          style: TextStyle(
                            color: isSelected
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          (type['descKey'] as String).tr(),
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: isSelected
                        ? AppColors.error
                        : AppColors.textTertiary,
                    size: 20,
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSeveritySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'report_abuse_severity'.tr(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children:
              _severityOptionsRaw.asMap().entries.map((entry) {
            final option = entry.value;
            final isSelected =
                _selectedSeverity == option['value'];
            final color =
                _severityColor(option['value'] as String);
            final isLast =
                entry.key == _severityOptionsRaw.length - 1;

            return Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticService.selectionClick();
                  setState(() => _selectedSeverity =
                      option['value'] as String);
                },
                child: Container(
                  margin: EdgeInsets.only(
                      right: isLast ? 0 : 8),
                  padding: const EdgeInsets.symmetric(
                      vertical: 14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withValues(alpha: 0.15)
                        : AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? color.withValues(alpha: 0.5)
                          : AppColors.border,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? color
                              : AppColors.textTertiary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        (option['labelKey'] as String).tr(),
                        style: TextStyle(
                          color: isSelected
                              ? color
                              : AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
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

  Widget _buildDescriptionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'report_abuse_description'.tr(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'report_abuse_description_hint'.tr(),
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descriptionController,
          focusNode: _descriptionFocus,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
          ),
          decoration: InputDecoration(
            hintText: 'report_abuse_placeholder'.tr(),
            hintStyle: const TextStyle(
                color: AppColors.textTertiary),
            filled: true,
            fillColor: AppColors.card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                  color: AppColors.error, width: 1.5),
            ),
            contentPadding: const EdgeInsets.all(16),
            counterStyle: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 12,
            ),
          ),
          maxLines: 5,
          minLines: 3,
          maxLength: 1000,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return GestureDetector(
      onTap:
          _canSubmit && !_isSubmitting ? _submitReport : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: _canSubmit
              ? AppColors.error
              : AppColors.error.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(14),
          boxShadow: _canSubmit
              ? [
                  BoxShadow(
                    color: AppColors.error
                        .withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: _isSubmitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.report_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'report_abuse_submit'.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
