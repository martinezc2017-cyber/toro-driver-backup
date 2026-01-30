import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_colors.dart';
import '../models/vehicle_model.dart';

class VehicleScreen extends StatefulWidget {
  const VehicleScreen({super.key});

  @override
  State<VehicleScreen> createState() => _VehicleScreenState();
}

class _VehicleScreenState extends State<VehicleScreen> {
  VehicleModel? _vehicle;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVehicle();
  }

  Future<void> _loadVehicle() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      final response = await Supabase.instance.client
          .from('vehicles')
          .select()
          .eq('driver_id', user.id)
          .maybeSingle();

      if (response != null) {
        setState(() {
          _vehicle = VehicleModel.fromJson(response);
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _vehicle = null;
        });
      }
    } catch (e) {
      //VehicleScreen: Error loading vehicle: $e');
      setState(() => _isLoading = false);
    }
  }

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
            Icon(Icons.directions_car, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('my_vehicle'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, size: 20, color: AppColors.textSecondary),
            onPressed: _loadVehicle,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _vehicle == null
              ? _buildNoVehicle()
              : _buildVehicleContent(),
    );
  }

  Widget _buildNoVehicle() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.directions_car_outlined, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(
              'no_vehicle'.tr(),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'register_vehicle_trips'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/add-vehicle').then((_) => _loadVehicle()),
              icon: const Icon(Icons.add, size: 18),
              label: Text('register_vehicle'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleContent() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildVehicleCard(),
        const SizedBox(height: 12),
        _buildVehicleStats(),
        const SizedBox(height: 12),
        _buildVehicleDetails(),
        const SizedBox(height: 12),
        _buildInsuranceSection(),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildVehicleCard() {
    final vehicle = _vehicle!;
    final statusColor = vehicle.isVerified ? AppColors.success : Colors.orange;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(vehicle.isVerified ? Icons.verified : Icons.pending, color: statusColor, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      vehicle.isVerified ? 'verified'.tr() : 'pending'.tr(),
                      style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  vehicle.status.name.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Icon(Icons.directions_car, color: Colors.white, size: 40),
          const SizedBox(height: 12),
          Text(
            '${vehicle.brand} ${vehicle.model}',
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '${vehicle.year} - ${vehicle.color}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              vehicle.plateNumber,
              style: TextStyle(color: AppColors.primary, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleStats() {
    final vehicle = _vehicle!;
    return Row(
      children: [
        Expanded(child: _buildStatCard(Icons.speed, '${vehicle.totalKilometers}', 'km'.tr())),
        const SizedBox(width: 8),
        Expanded(child: _buildStatCard(Icons.drive_eta, '${vehicle.totalRides}', 'trips'.tr())),
        const SizedBox(width: 8),
        Expanded(child: _buildStatCard(Icons.star, vehicle.rating.toStringAsFixed(1), 'rating'.tr())),
      ],
    );
  }

  Widget _buildStatCard(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.primary, size: 18),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          Text(label, style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildVehicleDetails() {
    final vehicle = _vehicle!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.primary, size: 16),
              const SizedBox(width: 8),
              Text('vehicle_details'.tr(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 12),
          _buildDetailRow('brand'.tr(), vehicle.brand),
          _buildDetailRow('model'.tr(), vehicle.model),
          _buildDetailRow('year'.tr(), '${vehicle.year}'),
          _buildDetailRow('color'.tr(), vehicle.color),
          _buildDetailRow('plate'.tr(), vehicle.plateNumber),
          if (vehicle.vin != null) _buildDetailRow('VIN', vehicle.vin!),
        ],
      ),
    );
  }

  Widget _buildInsuranceSection() {
    final vehicle = _vehicle!;
    final isExpiringSoon = vehicle.insuranceExpiry != null &&
        vehicle.insuranceExpiry!.difference(DateTime.now()).inDays <= 30;
    final isExpired = vehicle.insuranceExpiry != null &&
        vehicle.insuranceExpiry!.isBefore(DateTime.now());

    final statusColor = isExpired ? AppColors.error : isExpiringSoon ? Colors.orange : AppColors.success;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.shield, color: statusColor, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('vehicle_insurance'.tr(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (vehicle.insuranceVerified ? AppColors.success : Colors.orange).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            vehicle.insuranceVerified ? 'verified'.tr() : 'pending'.tr(),
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: vehicle.insuranceVerified ? AppColors.success : Colors.orange),
                          ),
                        ),
                        if (vehicle.hasRideshareEndorsement) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('TNC', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.primary)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (isExpired || isExpiringSoon) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(isExpired ? Icons.error_outline : Icons.warning_amber, color: statusColor, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isExpired
                          ? 'insurance_expired'.tr()
                          : 'insurance_expiring'.tr(namedArgs: {'days': '${vehicle.insuranceExpiry!.difference(DateTime.now()).inDays}'}),
                      style: TextStyle(fontSize: 11, color: statusColor),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
          if (vehicle.insuranceCompany != null) _buildDetailRow('company'.tr(), vehicle.insuranceCompany!),
          if (vehicle.insurancePolicyNumber != null) _buildDetailRow('policy'.tr(), vehicle.insurancePolicyNumber!),
          if (vehicle.insuranceExpiry != null)
            _buildDetailRow('expires'.tr(), '${vehicle.insuranceExpiry!.month}/${vehicle.insuranceExpiry!.day}/${vehicle.insuranceExpiry!.year}'),
          _buildDetailRow('endorsement'.tr(), vehicle.hasRideshareEndorsement ? 'yes_tnc'.tr() : 'no'.tr()),

          if (!vehicle.hasRideshareEndorsement) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: AppColors.error, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'no_endorsement_warning'.tr(),
                      style: TextStyle(fontSize: 11, color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
