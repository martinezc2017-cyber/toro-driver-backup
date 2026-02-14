import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/supabase_config.dart';
import '../providers/driver_provider.dart';
import '../providers/location_provider.dart';
import '../services/abuse_report_service.dart';
import '../utils/app_colors.dart';
import '../utils/haptic_service.dart';

/// General-purpose report screen for drivers to report riders/incidents.
/// Works for ALL ride types: regular rides, carpools, deliveries, tourism, bus.
/// Uses the general `abuse_reports` table via [AbuseReportService].
///
/// Auto-captures:
/// - Reporter GPS coordinates (lat/lng at time of report)
/// - Reporter profile data (name, email, phone from DriverProvider + Supabase Auth)
/// - Incident timestamp
/// - GPS context data (speed, heading, accuracy)
class ReportRideScreen extends StatefulWidget {
  final String? rideId;
  final String? rideType; // 'ride', 'carpool', 'delivery', 'tourism', 'bus'
  final String? reportedUserId;
  final String? reportedUserName;

  const ReportRideScreen({
    super.key,
    this.rideId,
    this.rideType,
    this.reportedUserId,
    this.reportedUserName,
  });

  @override
  State<ReportRideScreen> createState() => _ReportRideScreenState();
}

class _ReportRideScreenState extends State<ReportRideScreen> {
  final AbuseReportService _reportService = AbuseReportService();
  final TextEditingController _descriptionController = TextEditingController();
  final FocusNode _descriptionFocus = FocusNode();

  ReportCategory? _selectedCategory;
  ReportSeverity? _selectedSeverity;
  bool _isSubmitting = false;

  // Auto-captured context data
  double? _capturedLat;
  double? _capturedLng;
  double? _capturedSpeed;
  double? _capturedHeading;
  double? _capturedAccuracy;
  String? _reporterName;
  String? _reporterEmail;
  String? _reporterPhone;
  DateTime? _incidentAt;

  @override
  void initState() {
    super.initState();
    _captureContextData();
  }

  /// Capture GPS + driver profile data as soon as the screen opens.
  void _captureContextData() {
    _incidentAt = DateTime.now();

    // Capture GPS
    try {
      final locationProvider =
          Provider.of<LocationProvider>(context, listen: false);
      _capturedLat = locationProvider.latitude;
      _capturedLng = locationProvider.longitude;
      _capturedSpeed = locationProvider.speed;
      _capturedHeading = locationProvider.heading;
      final pos = locationProvider.currentPosition;
      _capturedAccuracy = pos?.accuracy;
    } catch (_) {
      // GPS may not be available
    }

    // Capture driver profile
    try {
      final driverProvider =
          Provider.of<DriverProvider>(context, listen: false);
      final driver = driverProvider.driver;
      _reporterName = driver?.name;
      _reporterPhone = driver?.phone;
    } catch (_) {}

    // Capture email from Supabase auth
    try {
      _reporterEmail = SupabaseConfig.client.auth.currentUser?.email;
    } catch (_) {}
  }

  // Report category options with icons and i18n keys
  List<Map<String, dynamic>> get _reportCategories => [
        {
          'value': ReportCategory.harassment,
          'icon': Icons.person_off_rounded,
          'label': 'report_cat_harassment'.tr(),
          'desc': 'report_cat_harassment_desc'.tr(),
        },
        {
          'value': ReportCategory.sexualMisconduct,
          'icon': Icons.warning_amber_rounded,
          'label': 'report_cat_sexual_misconduct'.tr(),
          'desc': 'report_cat_sexual_misconduct_desc'.tr(),
        },
        {
          'value': ReportCategory.violence,
          'icon': Icons.gavel_rounded,
          'label': 'report_cat_violence'.tr(),
          'desc': 'report_cat_violence_desc'.tr(),
        },
        {
          'value': ReportCategory.threats,
          'icon': Icons.report_gmailerrorred_rounded,
          'label': 'report_cat_threats'.tr(),
          'desc': 'report_cat_threats_desc'.tr(),
        },
        {
          'value': ReportCategory.substanceImpairment,
          'icon': Icons.local_bar_rounded,
          'label': 'report_cat_substance'.tr(),
          'desc': 'report_cat_substance_desc'.tr(),
        },
        {
          'value': ReportCategory.fraud,
          'icon': Icons.money_off_rounded,
          'label': 'report_cat_fraud'.tr(),
          'desc': 'report_cat_fraud_desc'.tr(),
        },
        {
          'value': ReportCategory.theft,
          'icon': Icons.remove_circle_outline_rounded,
          'label': 'report_cat_theft'.tr(),
          'desc': 'report_cat_theft_desc'.tr(),
        },
        {
          'value': ReportCategory.vehicleCondition,
          'icon': Icons.car_crash_rounded,
          'label': 'report_cat_vehicle_damage'.tr(),
          'desc': 'report_cat_vehicle_damage_desc'.tr(),
        },
        {
          'value': ReportCategory.noShow,
          'icon': Icons.person_search_rounded,
          'label': 'report_cat_no_show'.tr(),
          'desc': 'report_cat_no_show_desc'.tr(),
        },
        {
          'value': ReportCategory.cancellationAbuse,
          'icon': Icons.cancel_rounded,
          'label': 'report_cat_cancellation'.tr(),
          'desc': 'report_cat_cancellation_desc'.tr(),
        },
        {
          'value': ReportCategory.discrimination,
          'icon': Icons.diversity_1_rounded,
          'label': 'report_cat_discrimination'.tr(),
          'desc': 'report_cat_discrimination_desc'.tr(),
        },
        {
          'value': ReportCategory.other,
          'icon': Icons.report_problem_rounded,
          'label': 'report_cat_other'.tr(),
          'desc': 'report_cat_other_desc'.tr(),
        },
      ];

  List<Map<String, dynamic>> get _severityOptions => [
        {
          'value': ReportSeverity.low,
          'label': 'report_sev_low'.tr(),
        },
        {
          'value': ReportSeverity.medium,
          'label': 'report_sev_medium'.tr(),
        },
        {
          'value': ReportSeverity.high,
          'label': 'report_sev_high'.tr(),
        },
        {
          'value': ReportSeverity.critical,
          'label': 'report_sev_critical'.tr(),
        },
      ];

  @override
  void dispose() {
    _descriptionController.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _selectedCategory != null &&
      _selectedSeverity != null &&
      _descriptionController.text.trim().length >= 10;

  Color _severityColor(ReportSeverity value) {
    switch (value) {
      case ReportSeverity.low:
        return AppColors.info;
      case ReportSeverity.medium:
        return AppColors.warning;
      case ReportSeverity.high:
        return AppColors.error;
      case ReportSeverity.critical:
        return const Color(0xFFB71C1C);
    }
  }

  Future<void> _submitReport() async {
    if (!_canSubmit || _isSubmitting) return;

    HapticService.mediumImpact();
    setState(() => _isSubmitting = true);

    try {
      // Build GPS context data (JSONB)
      final gpsData = <String, dynamic>{};
      if (_capturedLat != null) gpsData['latitude'] = _capturedLat;
      if (_capturedLng != null) gpsData['longitude'] = _capturedLng;
      if (_capturedSpeed != null) gpsData['speed_mps'] = _capturedSpeed;
      if (_capturedHeading != null) gpsData['heading'] = _capturedHeading;
      if (_capturedAccuracy != null) gpsData['accuracy_m'] = _capturedAccuracy;
      gpsData['captured_at'] = _incidentAt?.toIso8601String();

      await _reportService.submitReport(
        rideId: widget.rideId,
        rideType: widget.rideType ?? 'ride',
        reportedUserId: widget.reportedUserId ?? 'unknown',
        reportedUserName: widget.reportedUserName,
        category: _selectedCategory!,
        severity: _selectedSeverity!,
        description: _descriptionController.text.trim(),
        title: _selectedCategory!.toDatabase(),
        // GPS location
        incidentLatitude: _capturedLat,
        incidentLongitude: _capturedLng,
        incidentAt: _incidentAt,
        // Reporter context
        reporterName: _reporterName,
        reporterEmail: _reporterEmail,
        reporterPhone: _reporterPhone,
        // GPS context data (JSONB)
        gpsData: gpsData.isNotEmpty ? gpsData : null,
      );

      HapticService.success();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('report_success'.tr()),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
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
            content: Text('${'report_error'.tr()}: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

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
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: GestureDetector(
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildInfoBanner(),
                      if (_capturedLat != null) ...[
                        const SizedBox(height: 8),
                        _buildLocationCapturedBadge(),
                      ],
                      const SizedBox(height: 20),
                      _buildCategorySection(),
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
                  color: AppColors.border.withValues(alpha: 0.2),
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
                  'report_incident'.tr(),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (widget.reportedUserName != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.reportedUserName!,
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
          const Icon(Icons.info_outline_rounded,
              color: AppColors.info, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'report_info_banner'.tr(),
              style: const TextStyle(
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

  /// Shows a small badge confirming GPS location was captured.
  Widget _buildLocationCapturedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.success.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.gps_fixed_rounded,
              color: AppColors.success, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'report_location_captured'.tr(),
              style: const TextStyle(
                color: AppColors.success,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'report_type'.tr(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        ..._reportCategories.map((cat) {
          final isSelected = _selectedCategory == cat['value'];
          return GestureDetector(
            onTap: () {
              HapticService.selectionClick();
              setState(
                  () => _selectedCategory = cat['value'] as ReportCategory);
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.error.withValues(alpha: 0.08)
                    : AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? AppColors.error.withValues(alpha: 0.4)
                      : AppColors.border,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    cat['icon'] as IconData,
                    color:
                        isSelected ? AppColors.error : AppColors.textTertiary,
                    size: 22,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cat['label'] as String,
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
                          cat['desc'] as String,
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
                    color:
                        isSelected ? AppColors.error : AppColors.textTertiary,
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
          'report_severity'.tr(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: _severityOptions.asMap().entries.map((entry) {
            final option = entry.value;
            final sev = option['value'] as ReportSeverity;
            final isSelected = _selectedSeverity == sev;
            final color = _severityColor(sev);
            final isLast = entry.key == _severityOptions.length - 1;

            return Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticService.selectionClick();
                  setState(() => _selectedSeverity = sev);
                },
                child: Container(
                  margin: EdgeInsets.only(right: isLast ? 0 : 8),
                  padding: const EdgeInsets.symmetric(vertical: 14),
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
                          color:
                              isSelected ? color : AppColors.textTertiary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        option['label'] as String,
                        style: TextStyle(
                          color:
                              isSelected ? color : AppColors.textSecondary,
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
          'report_description'.tr(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'report_description_min'.tr(),
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descriptionController,
          focusNode: _descriptionFocus,
          style:
              const TextStyle(color: AppColors.textPrimary, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'report_description_hint'.tr(),
            hintStyle: const TextStyle(color: AppColors.textTertiary),
            filled: true,
            fillColor: AppColors.card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  const BorderSide(color: AppColors.error, width: 1.5),
            ),
            contentPadding: const EdgeInsets.all(16),
            counterStyle: const TextStyle(
                color: AppColors.textTertiary, fontSize: 12),
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
      onTap: _canSubmit && !_isSubmitting ? _submitReport : null,
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
                    color: AppColors.error.withValues(alpha: 0.3),
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
                    const Icon(Icons.report_rounded,
                        color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      'report_submit'.tr(),
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
