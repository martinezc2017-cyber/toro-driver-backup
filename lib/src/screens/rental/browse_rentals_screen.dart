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

  List<Map<String, dynamic>> _allListings = [];
  List<Map<String, dynamic>> _listings = [];
  bool _isLoading = true;
  String? _error;

  // Filters
  String _selectedType = '';
  String _selectedState = '';
  List<String> _availableStates = [];
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

      // Extract unique states from pickup_address
      final states = <String>{};
      for (final l in results) {
        final state = _extractState(l['pickup_address'] ?? '');
        if (state.isNotEmpty) states.add(state);
      }

      _allListings = results;
      _availableStates = states.toList()..sort();

      _applyFilters();
    } catch (e) {
      if (mounted) setState(() { _error = 'Error: $e'; _isLoading = false; });
    }
  }

  String _extractState(String address) {
    if (address.isEmpty) return '';
    // pickup_address usually has "City, State" or "Street, City, State, Country"
    final parts = address.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (parts.length >= 2) return parts[parts.length - 2]; // second to last is usually state
    if (parts.length == 1) return parts[0];
    return '';
  }

  void _applyFilters() {
    var results = List<Map<String, dynamic>>.from(_allListings);

    // State filter
    if (_selectedState.isNotEmpty) {
      results = results.where((l) {
        final addr = (l['pickup_address'] ?? '').toString();
        return addr.toLowerCase().contains(_selectedState.toLowerCase());
      }).toList();
    }

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
    if (query.isNotEmpty) {
      results = results.where((l) {
        final make = (l['vehicle_make'] ?? '').toString().toLowerCase();
        final model = (l['vehicle_model'] ?? '').toString().toLowerCase();
        final title = (l['title'] ?? '').toString().toLowerCase();
        return make.contains(query) || model.contains(query) || title.contains(query);
      }).toList();
    }

    if (mounted) setState(() { _listings = results; _isLoading = false; });
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
              preferredSize: const Size.fromHeight(96),
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
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.clear_rounded, color: AppColors.textTertiary, size: 20),
                                  onPressed: () { _searchCtrl.clear(); _applyFilters(); },
                                )
                              : null,
                        ),
                        onSubmitted: (_) => _applyFilters(),
                      ),
                    ),
                  ),
                  // Filter chips + state + sort
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        _buildFilterChip('Todos', ''),
                        _buildFilterChip('Sedan', 'sedan'),
                        _buildFilterChip('SUV', 'SUV'),
                        _buildFilterChip('Van', 'van'),
                        _buildFilterChip('Truck', 'truck'),
                        if (_availableStates.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          _buildStateChip(),
                        ],
                        const SizedBox(width: 8),
                        _buildSortChip(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),

          // Results count
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
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
                      padding: const EdgeInsets.only(bottom: 8),
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
      padding: const EdgeInsets.only(right: 6),
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
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        labelStyle: TextStyle(
          color: isSelected ? _accent : AppColors.textSecondary,
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
        ),
        side: BorderSide(
          color: isSelected ? _accent.withValues(alpha: 0.5) : AppColors.border,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _buildStateChip() {
    final hasFilter = _selectedState.isNotEmpty;
    return PopupMenuButton<String>(
      onSelected: (val) {
        HapticService.lightImpact();
        setState(() => _selectedState = val);
        _applyFilters();
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: '',
          child: Row(
            children: [
              if (_selectedState.isEmpty)
                Icon(Icons.check_rounded, color: _accent, size: 16)
              else
                const SizedBox(width: 16),
              const SizedBox(width: 8),
              const Text('Todos'),
            ],
          ),
        ),
        ..._availableStates.map((s) => PopupMenuItem(
          value: s,
          child: Row(
            children: [
              if (_selectedState == s)
                Icon(Icons.check_rounded, color: _accent, size: 16)
              else
                const SizedBox(width: 16),
              const SizedBox(width: 8),
              Text(s),
            ],
          ),
        )),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: hasFilter ? _accent.withValues(alpha: 0.15) : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: hasFilter ? _accent.withValues(alpha: 0.5) : AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_on_rounded, color: hasFilter ? _accent : AppColors.textTertiary, size: 14),
            const SizedBox(width: 4),
            Text(
              hasFilter ? _selectedState : 'Estado',
              style: TextStyle(color: hasFilter ? _accent : AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
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
        _applyFilters();
      },
      itemBuilder: (ctx) => labels.entries.map((e) => PopupMenuItem(
        value: e.key,
        child: Row(
          children: [
            if (_sortBy == e.key)
              Icon(Icons.check_rounded, color: _accent, size: 16)
            else
              const SizedBox(width: 16),
            const SizedBox(width: 8),
            Text(e.value),
          ],
        ),
      )).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sort_rounded, color: AppColors.textTertiary, size: 14),
            const SizedBox(width: 4),
            Text(
              labels[_sortBy] ?? 'Ordenar',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// VEHICLE CARD - Compact horizontal layout
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
    final currency = listing['currency'] ?? 'MXN';
    final address = listing['pickup_address'] ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 110,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
              child: SizedBox(
                width: 120,
                height: 110,
                child: imageUrls.isNotEmpty
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            imageUrls.first,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _noPhotoPlaceholder(),
                          ),
                          if (imageUrls.length > 1)
                            Positioned(
                              bottom: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${imageUrls.length}',
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                        ],
                      )
                    : _noPhotoPlaceholder(),
              ),
            ),
            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title + type
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            type.toUpperCase(),
                            style: const TextStyle(
                              color: Color(0xFF8B5CF6),
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    // Year + Location
                    Row(
                      children: [
                        Text(year, style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                        if (address.isNotEmpty) ...[
                          Text(' · ', style: TextStyle(color: AppColors.textDisabled, fontSize: 11)),
                          Icon(Icons.location_on_rounded, color: AppColors.textTertiary, size: 11),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              address,
                              style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const Spacer(),
                    // Price row
                    Row(
                      children: [
                        if (dailyPrice > 0) ...[
                          Text(
                            '\$${dailyPrice.toStringAsFixed(0)}',
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w800),
                          ),
                          Text(
                            ' $currency/dia',
                            style: TextStyle(color: AppColors.textTertiary, fontSize: 10),
                          ),
                        ],
                        if (dailyPrice > 0 && weeklyPrice > 0)
                          Text(' · ', style: TextStyle(color: AppColors.textDisabled, fontSize: 11)),
                        if (weeklyPrice > 0) ...[
                          Text(
                            '\$${weeklyPrice.toStringAsFixed(0)}',
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w800),
                          ),
                          Text(
                            ' $currency/sem',
                            style: TextStyle(color: AppColors.textTertiary, fontSize: 10),
                          ),
                        ],
                        const Spacer(),
                        Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary, size: 20),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _noPhotoPlaceholder() {
    return Container(
      color: AppColors.cardSecondary,
      child: Center(
        child: Icon(Icons.directions_car_rounded, color: AppColors.textDisabled, size: 32),
      ),
    );
  }
}
