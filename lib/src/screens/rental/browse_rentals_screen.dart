import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';
import '../../services/rental_vehicle_service.dart';
import 'rental_detail_screen.dart';

/// Browse available rental vehicles - Turo-style professional listing
class BrowseRentalsScreen extends StatefulWidget {
  const BrowseRentalsScreen({super.key});

  @override
  State<BrowseRentalsScreen> createState() => _BrowseRentalsScreenState();
}

class _BrowseRentalsScreenState extends State<BrowseRentalsScreen> {
  static const _accent = Color(0xFF8B5CF6);

  List<Map<String, dynamic>> _listings = [];
  bool _isLoading = true;
  String? _error;

  // Filters
  String _selectedType = '';
  final _searchCtrl = TextEditingController();
  String _sortBy = 'newest'; // newest, price_low, price_high

  @override
  void initState() {
    super.initState();
    _loadListings();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadListings() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final results = await RentalVehicleService.getActiveListings(
        vehicleType: _selectedType.isNotEmpty ? _selectedType : null,
      );

      // Sort
      if (_sortBy == 'price_low') {
        results.sort((a, b) => ((a['weekly_price_base'] ?? 0) as num)
            .compareTo((b['weekly_price_base'] ?? 0) as num));
      } else if (_sortBy == 'price_high') {
        results.sort((a, b) => ((b['weekly_price_base'] ?? 0) as num)
            .compareTo((a['weekly_price_base'] ?? 0) as num));
      }

      // Search filter
      final query = _searchCtrl.text.trim().toLowerCase();
      final filtered = query.isEmpty
          ? results
          : results.where((l) {
              final make = (l['vehicle_make'] ?? '').toString().toLowerCase();
              final model = (l['vehicle_model'] ?? '').toString().toLowerCase();
              final title = (l['title'] ?? '').toString().toLowerCase();
              return make.contains(query) || model.contains(query) || title.contains(query);
            }).toList();

      if (mounted) setState(() { _listings = filtered; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Error: $e'; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: CustomScrollView(
        slivers: [
          // App bar
          SliverAppBar(
            backgroundColor: AppColors.surface,
            floating: true,
            snap: true,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_rounded, color: AppColors.textPrimary, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'Vehiculos Disponibles',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(120),
              child: Column(
                children: [
                  // Search bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: TextField(
                        controller: _searchCtrl,
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                        decoration: InputDecoration(
                          hintText: 'Buscar por marca, modelo...',
                          hintStyle: TextStyle(color: AppColors.textDisabled, fontSize: 15),
                          prefixIcon: Icon(Icons.search_rounded, color: AppColors.textTertiary, size: 22),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.clear_rounded, color: AppColors.textTertiary, size: 20),
                                  onPressed: () { _searchCtrl.clear(); _loadListings(); },
                                )
                              : null,
                        ),
                        onSubmitted: (_) => _loadListings(),
                      ),
                    ),
                  ),
                  // Filter chips + sort
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        _buildFilterChip('Todos', ''),
                        _buildFilterChip('Sedan', 'sedan'),
                        _buildFilterChip('SUV', 'SUV'),
                        _buildFilterChip('Van', 'van'),
                        _buildFilterChip('Truck', 'truck'),
                        const SizedBox(width: 12),
                        _buildSortChip(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),

          // Results count
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Text(
                    '${_listings.length} vehiculo${_listings.length != 1 ? 's' : ''} disponible${_listings.length != 1 ? 's' : ''}',
                    style: TextStyle(color: AppColors.textTertiary, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  if (_isLoading)
                    SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
                    ),
                ],
              ),
            ),
          ),

          // Listings
          if (_isLoading && _listings.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: _accent),
              ),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: AppColors.error, fontSize: 14)),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _loadListings,
                      child: Text('Reintentar', style: TextStyle(color: _accent)),
                    ),
                  ],
                ),
              ),
            )
          else if (_listings.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.car_rental_rounded, color: _accent, size: 48),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'No hay vehiculos disponibles',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Intenta con otros filtros o vuelve mas tarde',
                      style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final listing = _listings[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _VehicleCard(
                        listing: listing,
                        onTap: () {
                          HapticService.lightImpact();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RentalDetailScreen(listing: listing),
                            ),
                          );
                        },
                      ),
                    );
                  },
                  childCount: _listings.length,
                ),
              ),
            ),

          // Bottom padding
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String type) {
    final isSelected = _selectedType == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) {
          HapticService.lightImpact();
          setState(() => _selectedType = type);
          _loadListings();
        },
        backgroundColor: AppColors.card,
        selectedColor: _accent.withValues(alpha: 0.2),
        checkmarkColor: _accent,
        labelStyle: TextStyle(
          color: isSelected ? _accent : AppColors.textSecondary,
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
        ),
        side: BorderSide(
          color: isSelected ? _accent.withValues(alpha: 0.5) : AppColors.border,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Widget _buildSortChip() {
    final labels = {
      'newest': 'Recientes',
      'price_low': 'Precio ↑',
      'price_high': 'Precio ↓',
    };
    return PopupMenuButton<String>(
      onSelected: (val) {
        setState(() => _sortBy = val);
        _loadListings();
      },
      itemBuilder: (ctx) => labels.entries.map((e) => PopupMenuItem(
        value: e.key,
        child: Row(
          children: [
            if (_sortBy == e.key)
              Icon(Icons.check_rounded, color: _accent, size: 18)
            else
              const SizedBox(width: 18),
            const SizedBox(width: 8),
            Text(e.value),
          ],
        ),
      )).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sort_rounded, color: AppColors.textTertiary, size: 18),
            const SizedBox(width: 6),
            Text(
              labels[_sortBy] ?? 'Ordenar',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// VEHICLE CARD - Professional Turo-style listing card
// ═══════════════════════════════════════════════════════════════════════════════

class _VehicleCard extends StatelessWidget {
  final Map<String, dynamic> listing;
  final VoidCallback onTap;

  const _VehicleCard({required this.listing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final imageUrls = List<String>.from(listing['image_urls'] ?? []);
    final make = listing['vehicle_make'] ?? '';
    final model = listing['vehicle_model'] ?? '';
    final year = listing['vehicle_year']?.toString() ?? '';
    final title = listing['title'] ?? '$make $model $year';
    final weeklyPrice = (listing['weekly_price_base'] ?? 0).toDouble();
    final dailyPrice = (listing['daily_price'] ?? 0).toDouble();
    final type = listing['vehicle_type'] ?? 'sedan';
    final color = listing['vehicle_color'] ?? '';
    final currency = listing['currency'] ?? 'MXN';
    final features = List<String>.from(listing['features'] ?? []);
    final address = listing['pickup_address'] ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo carousel
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: SizedBox(
                height: 200,
                width: double.infinity,
                child: imageUrls.isNotEmpty
                    ? PageView.builder(
                        itemCount: imageUrls.length,
                        itemBuilder: (ctx, i) => Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              imageUrls[i],
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _noPhotoPlaceholder(),
                            ),
                            // Photo counter
                            if (imageUrls.length > 1)
                              Positioned(
                                bottom: 10,
                                right: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${i + 1}/${imageUrls.length}',
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      )
                    : _noPhotoPlaceholder(),
              ),
            ),
            // Info
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + type badge
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          type.toUpperCase(),
                          style: TextStyle(
                            color: const Color(0xFF8B5CF6),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Year + Color
                  Row(
                    children: [
                      Icon(Icons.calendar_today_rounded, color: AppColors.textTertiary, size: 14),
                      const SizedBox(width: 4),
                      Text(year, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      if (color.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Icon(Icons.palette_rounded, color: AppColors.textTertiary, size: 14),
                        const SizedBox(width: 4),
                        Text(color, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      ],
                    ],
                  ),
                  // Location
                  if (address.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.location_on_rounded, color: AppColors.textTertiary, size: 14),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            address,
                            style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  // Features
                  if (features.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: features.take(4).map((f) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.cardSecondary,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
                        ),
                        child: Text(f, style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                      )).toList(),
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Price bar
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.cardSecondary,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        if (dailyPrice > 0) ...[
                          _priceTag('\$${dailyPrice.toStringAsFixed(0)}', '/dia', currency),
                          const SizedBox(width: 16),
                        ],
                        if (weeklyPrice > 0)
                          _priceTag('\$${weeklyPrice.toStringAsFixed(0)}', '/semana', currency),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [const Color(0xFF8B5CF6), const Color(0xFFA78BFA)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Ver Detalles',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _priceTag(String price, String period, String currency) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              price,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 2),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '$currency$period',
                style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _noPhotoPlaceholder() {
    return Container(
      color: AppColors.cardSecondary,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.directions_car_rounded, color: AppColors.textDisabled, size: 48),
            const SizedBox(height: 8),
            Text('Sin fotos', style: TextStyle(color: AppColors.textDisabled, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
