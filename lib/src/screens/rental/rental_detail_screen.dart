import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';
import '../../services/rental_vehicle_service.dart';

/// Vehicle detail screen - Professional Turo-style with photo gallery,
/// full specs, pricing, owner info, and contact options.
class RentalDetailScreen extends StatefulWidget {
  final Map<String, dynamic> listing;

  const RentalDetailScreen({super.key, required this.listing});

  @override
  State<RentalDetailScreen> createState() => _RentalDetailScreenState();
}

class _RentalDetailScreenState extends State<RentalDetailScreen> {
  static const _accent = Color(0xFF8B5CF6);

  Map<String, dynamic>? _ownerInfo;
  bool _loadingOwner = true;
  int _currentPhotoIndex = 0;
  final _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _loadOwner();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadOwner() async {
    final ownerId = widget.listing['owner_id'] as String?;
    if (ownerId != null) {
      final info = await RentalVehicleService.getOwnerInfo(ownerId);
      if (mounted)
        setState(() {
          _ownerInfo = info;
          _loadingOwner = false;
        });
    } else {
      if (mounted) setState(() => _loadingOwner = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.listing;
    final imageUrls = List<String>.from(l['image_urls'] ?? []);
    final make = l['vehicle_make'] ?? '';
    final model = l['vehicle_model'] ?? '';
    final year = l['vehicle_year']?.toString() ?? '';
    final title = l['title'] ?? '$make $model $year';
    final description = l['description'] ?? '';
    final color = l['vehicle_color'] ?? '';
    final plate = l['vehicle_plate'] ?? '';
    final vin = l['vehicle_vin'] ?? '';
    final type = l['vehicle_type'] ?? 'sedan';
    final weeklyPrice = (l['weekly_price_base'] ?? 0).toDouble();
    final dailyPrice = (l['daily_price'] ?? 0).toDouble();
    final monthlyPrice = (l['monthly_price'] ?? 0).toDouble();
    final deposit = (l['deposit_amount'] ?? 0).toDouble();
    final perKm = (l['per_km_base'] ?? 0).toDouble();
    final currency = l['currency'] ?? 'MXN';
    final features = List<String>.from(l['features'] ?? []);
    final address = l['pickup_address'] ?? '';
    final insCompany = l['insurance_company'] ?? '';
    final insPolicy = l['insurance_policy_number'] ?? '';
    final insExpiry = l['insurance_expiry'] ?? '';
    final fuelPolicy = l['fuel_policy'] ?? 'full_to_full';
    final mileageLimit = l['mileage_limit_km'] ?? 0;
    final minDays = l['min_rental_days'] ?? 1;
    final maxDays = l['max_rental_days'] ?? 90;
    final instant = l['instant_booking'] == true;
    final ownerName = l['owner_name'] ?? _ownerInfo?['name'] ?? 'Propietario';
    final ownerPhone = l['owner_phone'] ?? _ownerInfo?['phone'] ?? '';

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: CustomScrollView(
        slivers: [
          // Photo gallery
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            backgroundColor: AppColors.surface,
            leading: _circleButton(
              Icons.arrow_back_ios_rounded,
              () => Navigator.pop(context),
            ),
            actions: [
              _circleButton(Icons.share_rounded, () {
                HapticService.lightImpact();
                Clipboard.setData(
                  ClipboardData(text: 'Mira este $title en TORO Rentals'),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Link copiado'),
                    backgroundColor: _accent,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (imageUrls.isNotEmpty)
                    PageView.builder(
                      controller: _pageController,
                      itemCount: imageUrls.length,
                      onPageChanged: (i) =>
                          setState(() => _currentPhotoIndex = i),
                      itemBuilder: (_, i) => Image.network(
                        imageUrls[i],
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder(),
                      ),
                    )
                  else
                    _placeholder(),
                  // Gradient overlay
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, AppColors.surface],
                        ),
                      ),
                    ),
                  ),
                  // Photo dots
                  if (imageUrls.length > 1)
                    Positioned(
                      bottom: 16,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          imageUrls.length,
                          (i) => Container(
                            width: i == _currentPhotoIndex ? 24 : 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: i == _currentPhotoIndex
                                  ? _accent
                                  : Colors.white.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Photo counter badge
                  if (imageUrls.isNotEmpty)
                    Positioned(
                      bottom: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.photo_library_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${_currentPhotoIndex + 1}/${imageUrls.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + badges
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (instant)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.bolt_rounded,
                                color: AppColors.success,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Inmediato',
                                style: TextStyle(
                                  color: AppColors.success,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Type + Year + Color
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _infoBadge(
                        Icons.directions_car_rounded,
                        type.toUpperCase(),
                      ),
                      _infoBadge(Icons.calendar_today_rounded, year),
                      if (color.isNotEmpty)
                        _infoBadge(Icons.palette_rounded, color),
                      if (plate.isNotEmpty)
                        _infoBadge(Icons.confirmation_number_rounded, plate),
                    ],
                  ),

                  // Description
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _sectionTitle('Descripcion'),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ],

                  // ═══ PRICING ═══
                  const SizedBox(height: 24),
                  _sectionTitle('Precios'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _accent.withValues(alpha: 0.08),
                          _accent.withValues(alpha: 0.03),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _accent.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      children: [
                        if (dailyPrice > 0)
                          _priceRow(
                            'Por Dia',
                            '\$${dailyPrice.toStringAsFixed(0)} $currency',
                          ),
                        if (weeklyPrice > 0)
                          _priceRow(
                            'Por Semana',
                            '\$${weeklyPrice.toStringAsFixed(0)} $currency',
                          ),
                        if (monthlyPrice > 0)
                          _priceRow(
                            'Por Mes',
                            '\$${monthlyPrice.toStringAsFixed(0)} $currency',
                          ),
                        if (perKm > 0)
                          _priceRow(
                            'Por Km Extra',
                            '\$${perKm.toStringAsFixed(2)} $currency',
                          ),
                        if (deposit > 0) ...[
                          Divider(
                            color: AppColors.border.withValues(alpha: 0.3),
                            height: 20,
                          ),
                          _priceRow(
                            'Deposito',
                            '\$${deposit.toStringAsFixed(0)} $currency',
                            isDeposit: true,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // ═══ FEATURES ═══
                  if (features.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _sectionTitle('Caracteristicas'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: features
                          .map(
                            (f) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.check_circle_rounded,
                                    color: AppColors.success,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    f,
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],

                  // ═══ VEHICLE SPECS ═══
                  const SizedBox(height: 24),
                  _sectionTitle('Especificaciones'),
                  const SizedBox(height: 12),
                  _specCard([
                    if (vin.isNotEmpty) _specRow('VIN', vin),
                    _specRow('Combustible', _fuelPolicyLabel(fuelPolicy)),
                    if (mileageLimit > 0)
                      _specRow('Limite Km', '$mileageLimit km'),
                    _specRow(
                      'Minimo Renta',
                      '$minDays dia${minDays > 1 ? 's' : ''}',
                    ),
                    _specRow('Maximo Renta', '$maxDays dias'),
                  ]),

                  // ═══ INSURANCE ═══
                  if (insCompany.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _sectionTitle('Seguro'),
                    const SizedBox(height: 12),
                    _specCard([
                      _specRow('Compania', insCompany),
                      if (insPolicy.isNotEmpty) _specRow('Poliza', insPolicy),
                      if (insExpiry.isNotEmpty)
                        _specRow('Vencimiento', insExpiry),
                    ]),
                  ],

                  // ═══ LOCATION ═══
                  if (address.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _sectionTitle('Ubicacion de Entrega'),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.location_on_rounded,
                              color: _accent,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              address,
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // ═══ OWNER ═══
                  const SizedBox(height: 24),
                  _sectionTitle('Propietario'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: _loadingOwner
                        ? Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _accent,
                            ),
                          )
                        : Row(
                            children: [
                              CircleAvatar(
                                radius: 28,
                                backgroundColor: _accent.withValues(
                                  alpha: 0.15,
                                ),
                                backgroundImage:
                                    _ownerInfo?['profile_image_url'] != null
                                    ? NetworkImage(
                                        _ownerInfo!['profile_image_url'],
                                      )
                                    : null,
                                child: _ownerInfo?['profile_image_url'] == null
                                    ? Icon(
                                        Icons.person_rounded,
                                        color: _accent,
                                        size: 28,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      ownerName,
                                      style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    if (_ownerInfo?['rating'] != null)
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.star_rounded,
                                            color: AppColors.star,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            (_ownerInfo!['rating'] as num)
                                                .toStringAsFixed(1),
                                            style: TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 13,
                                            ),
                                          ),
                                          if (_ownerInfo?['total_rides'] !=
                                              null) ...[
                                            Text(
                                              ' · ',
                                              style: TextStyle(
                                                color: AppColors.textDisabled,
                                              ),
                                            ),
                                            Text(
                                              '${_ownerInfo!['total_rides']} viajes',
                                              style: TextStyle(
                                                color: AppColors.textTertiary,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                              if (ownerPhone.isNotEmpty)
                                IconButton(
                                  onPressed: () => _callOwner(ownerPhone),
                                  icon: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppColors.success.withValues(
                                        alpha: 0.15,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.phone_rounded,
                                      color: AppColors.success,
                                      size: 20,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),

                  const SizedBox(height: 100), // space for bottom bar
                ],
              ),
            ),
          ),
        ],
      ),
      // Bottom contact bar
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border(
            top: BorderSide(color: AppColors.border.withValues(alpha: 0.5)),
          ),
        ),
        child: Row(
          children: [
            // Price summary
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (dailyPrice > 0)
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '\$${dailyPrice.toStringAsFixed(0)}',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        TextSpan(
                          text: ' $currency/dia',
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (weeklyPrice > 0)
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '\$${weeklyPrice.toStringAsFixed(0)}',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        TextSpan(
                          text: ' $currency/sem',
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            // Contact button
            Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticService.mediumImpact();
                  if (ownerPhone.isNotEmpty) {
                    _callOwner(ownerPhone);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Telefono no disponible'),
                        backgroundColor: AppColors.warning,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_accent, const Color(0xFFA78BFA)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: _accent.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.phone_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Contactar Dueno',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _callOwner(String phone) async {
    final url = 'tel:$phone';
    try {
      await launchUrlString(url);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo llamar a $phone'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _infoBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.textTertiary, size: 14),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceRow(String label, String value, {bool isDeposit = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: isDeposit ? AppColors.warning : AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _specCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: children),
    );
  }

  Widget _specRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _fuelPolicyLabel(String policy) {
    switch (policy) {
      case 'full_to_full':
        return 'Lleno a Lleno';
      case 'same_level':
        return 'Mismo Nivel';
      case 'prepaid':
        return 'Prepagado';
      default:
        return policy;
    }
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.cardSecondary,
      child: Center(
        child: Icon(
          Icons.directions_car_rounded,
          color: AppColors.textDisabled,
          size: 64,
        ),
      ),
    );
  }
}
