import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/ride_provider.dart';
import '../providers/driver_provider.dart';
import '../providers/location_provider.dart';
import '../models/ride_model.dart';
import '../services/pricing_config_service.dart';
import '../utils/app_colors.dart';
import '../utils/haptic_service.dart';
import '../widgets/futuristic_widgets.dart';

class RidesScreen extends StatefulWidget {
  const RidesScreen({super.key});

  @override
  State<RidesScreen> createState() => _RidesScreenState();
}

class _RidesScreenState extends State<RidesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedFilterIndex = 0;

  // Driver commission percent from pricing_config (dynamic)
  double _driverPercent = 49.0; // Default until loaded from BD

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadPricingConfig();
  }

  /// Load driver commission percentage from pricing_config
  Future<void> _loadPricingConfig() async {
    try {
      final config = await PricingConfigService.instance.getConfig();
      if (mounted) {
        setState(() {
          _driverPercent = config.driverPercent;
        });
      }
    } catch (e) {
      // Keep default if config not available
      //Failed to load pricing config: $e');
    }
  }

  void _onTabChanged() {
    if (_tabController.index == 1 && !_tabController.indexIsChanging) {
      final driverId = context.read<DriverProvider>().driver?.id;
      if (driverId != null) {
        context.read<RideProvider>().loadRideHistory(driverId);
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            const SizedBox(height: 8),
            _buildFilters(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildAvailableRides(),
                  _buildRideHistory(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Consumer<DriverProvider>(
      builder: (context, driverProvider, child) {
        final isOnline = driverProvider.isOnline;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Icon(
                  Icons.local_taxi_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'trips_title'.tr(),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              _OnlineStatusButton(
                isOnline: isOnline,
                onTap: () async {
                  await driverProvider.toggleOnlineStatus();
                  if (driverProvider.isOnline) {
                    HapticService.success();
                  } else {
                    HapticService.mediumImpact();
                  }
                },
              ),
            ],
          ),
        ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0);
      },
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 6,
            ),
          ],
        ),
        labelColor: Colors.white,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        labelPadding: EdgeInsets.zero,
        tabs: [
          Tab(
            height: 36,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.pending_actions_rounded, size: 14),
                const SizedBox(width: 6),
                Text('available_tab'.tr()),
              ],
            ),
          ),
          Tab(
            height: 36,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.history_rounded, size: 14),
                const SizedBox(width: 6),
                Text('history_tab'.tr()),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms);
  }

  Widget _buildFilters() {
    final filters = ['filter_all'.tr(), 'filter_nearby'.tr(), 'filter_best_pay'.tr(), 'filter_short'.tr(), 'filter_long'.tr()];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: filters.asMap().entries.map((entry) {
          final filter = entry.value;
          final index = entry.key;
          final isSelected = index == _selectedFilterIndex;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () {
                HapticService.selectionClick();
                setState(() => _selectedFilterIndex = index);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: isSelected ? AppColors.successGradient : null,
                  color: isSelected ? null : AppColors.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? Colors.transparent : AppColors.border.withValues(alpha: 0.5),
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppColors.success.withValues(alpha: 0.3),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  filter,
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          )
              .animate(delay: Duration(milliseconds: 50 * index))
              .fadeIn()
              .slideX(begin: 0.2, end: 0);
        }).toList(),
      ),
    );
  }

  Widget _buildAvailableRides() {
    return Consumer<RideProvider>(
      builder: (context, rideProvider, child) {
        final rides = _filterRides(rideProvider.availableRides);
        final isLoading = rideProvider.isLoading;

        if (isLoading && rides.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          );
        }

        if (rides.isEmpty) {
          return _buildEmptyState('available');
        }

        return RefreshIndicator(
          onRefresh: () => rideProvider.refreshAvailableRides(),
          color: AppColors.primary,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            itemCount: rides.length,
            itemBuilder: (context, index) => _buildRideCard(rides[index], index),
          ),
        );
      },
    );
  }

  Widget _buildRideHistory() {
    return Consumer<RideProvider>(
      builder: (context, rideProvider, child) {
        final rides = rideProvider.rideHistory;
        final isLoading = rideProvider.isLoading;

        if (isLoading && rides.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          );
        }

        if (rides.isEmpty) {
          return _buildEmptyState('history');
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          physics: const BouncingScrollPhysics(),
          itemCount: rides.length,
          itemBuilder: (context, index) => _buildHistoryCard(rides[index], index),
        );
      },
    );
  }

  List<RideModel> _filterRides(List<RideModel> rides) {
    switch (_selectedFilterIndex) {
      case 1: // Nearby
        final filtered = List<RideModel>.from(rides);
        filtered.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
        return filtered;
      case 2: // Best pay
        final filtered = List<RideModel>.from(rides);
        filtered.sort((a, b) => b.driverEarnings.compareTo(a.driverEarnings));
        return filtered;
      case 3: // Short
        return rides.where((r) => r.distanceKm <= 5).toList();
      case 4: // Long
        return rides.where((r) => r.distanceKm > 5).toList();
      default: // All (0)
        return rides;
    }
  }

  Widget _buildEmptyState(String type) {
    final isHistory = type == 'history';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: Icon(
              isHistory ? Icons.history_rounded : Icons.local_taxi_rounded,
              size: 40,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isHistory ? 'no_completed_trips'.tr() : 'no_available_trips'.tr(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isHistory
                ? 'completed_trips_appear'.tr()
                : 'stay_online'.tr(),
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    ).animate().fadeIn().scale(begin: const Offset(0.9, 0.9));
  }

  Widget _buildRideCard(RideModel ride, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
        boxShadow: AppColors.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            HapticService.lightImpact();
            _showRideDetails(ride);
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.3),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.local_taxi_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  ride.displayName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: AppColors.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (ride.isRoundTrip) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF00C853), Color(0xFF00BFA5)],
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'ROUND TRIP',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                              if (ride.passengerRating > 0) ...[
                                const SizedBox(width: 6),
                                Icon(Icons.star_rounded, color: AppColors.star, size: 12),
                                const SizedBox(width: 2),
                                Text(
                                  ride.passengerRating.toStringAsFixed(1),
                                  style: TextStyle(
                                    color: AppColors.star,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              // Distance to pickup (how far driver is from client)
                              Builder(
                                builder: (context) {
                                  final distToPickup = _calculateDistanceToPickup(ride);
                                  if (distToPickup != null) {
                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.near_me, size: 10, color: AppColors.warning),
                                        const SizedBox(width: 2),
                                        Text(
                                          '${distToPickup.toStringAsFixed(1)} mi',
                                          style: TextStyle(
                                            color: AppColors.warning,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          ' → ',
                                          style: TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                              // Trip distance and duration
                              Text(
                                '${(ride.distanceKm * 0.621371).toStringAsFixed(1)} mi • ${ride.estimatedMinutes} min',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                              if (ride.recurringDays.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Text(
                                  _formatRecurringDays(ride.recurringDays),
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              if (ride.type == RideType.carpool && ride.filledSeats > 0) ...[
                                const SizedBox(width: 6),
                                ...List.generate(3, (i) {
                                  final color = i < ride.filledSeats ? AppColors.success : AppColors.textSecondary.withValues(alpha: 0.3);
                                  return Padding(
                                    padding: EdgeInsets.only(left: i > 0 ? 1 : 0),
                                    child: Icon(Icons.person, color: color, size: 12),
                                  );
                                }),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // PREVIEW: If no real earnings yet, calculate from fare * driver%
                        Builder(builder: (context) {
                          final earnings = ride.driverEarnings > 0
                              ? ride.driverEarnings
                              : ride.fare * (_driverPercent / 100);
                          return Text(
                            '\$${earnings.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.success,
                            ),
                          );
                        }),
                        Text(
                          ride.driverEarnings > 0 ? 'card'.tr() : 'est.'.tr(),
                          style: TextStyle(
                            color: ride.driverEarnings > 0 ? AppColors.primary : AppColors.warning,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Column(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              gradient: AppColors.successGradient,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Container(
                            width: 2,
                            height: 18,
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [AppColors.success, AppColors.error],
                              ),
                            ),
                          ),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: AppColors.error,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ride.pickupLocation.address ?? 'pickup_address'.tr(),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              ride.dropoffLocation.address ?? 'destination_address'.tr(),
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: NeonButton(
                        text: 'ignore'.tr(),
                        onPressed: () => HapticService.lightImpact(),
                        isOutlined: true,
                        color: AppColors.textSecondary,
                        height: 38,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: NeonButton(
                        text: 'accept'.tr(),
                        icon: Icons.check_rounded,
                        onPressed: () async {
                          final driverId = context.read<DriverProvider>().driver?.id;
                          if (driverId != null) {
                            final success = await context.read<RideProvider>().acceptRide(ride.id, driverId);
                            if (success) {
                              HapticService.success();
                              if (mounted) {
                                Navigator.pushNamed(context, '/navigation');
                              }
                            } else {
                              HapticService.error();
                            }
                          }
                        },
                        gradient: AppColors.successGradient,
                        height: 38,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    )
        .animate(delay: Duration(milliseconds: 100 * index))
        .fadeIn()
        .slideY(begin: 0.1, end: 0);
  }

  Widget _buildHistoryCard(RideModel ride, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        ride.displayName,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (ride.isRoundTrip) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00C853), Color(0xFF00BFA5)],
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'RT',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  '${(ride.distanceKm * 0.621371).toStringAsFixed(1)} mi • ${_formatDate(ride.createdAt)}',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Builder(builder: (context) {
                final earnings = ride.driverEarnings > 0
                    ? ride.driverEarnings
                    : ride.fare * (_driverPercent / 100);
                return Text(
                  '+\$${earnings.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.success,
                    fontSize: 14,
                  ),
                );
              }),
              if (ride.tip > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.volunteer_activism_rounded, color: AppColors.star, size: 12),
                    const SizedBox(width: 2),
                    Text(
                      '+\$${ride.tip.toStringAsFixed(0)}',
                      style: TextStyle(
                        color: AppColors.star,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    )
        .animate(delay: Duration(milliseconds: 80 * index))
        .fadeIn()
        .slideX(begin: 0.1, end: 0);
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'today_time'.tr(args: [DateFormat('HH:mm').format(date)]);
    } else if (diff.inDays == 1) {
      return 'yesterday_time'.tr(args: [DateFormat('HH:mm').format(date)]);
    } else if (diff.inDays < 7) {
      return 'days_ago_label'.tr(args: [diff.inDays.toString()]);
    } else {
      return DateFormat('dd/MM/yyyy').format(date);
    }
  }

  /// Calculate distance from driver to pickup location (Haversine formula)
  /// Returns distance in miles
  double? _calculateDistanceToPickup(RideModel ride) {
    final locationProvider = context.read<LocationProvider>();
    final driverLat = locationProvider.latitude;
    final driverLng = locationProvider.longitude;

    if (driverLat == null || driverLng == null) return null;

    final pickupLat = ride.pickupLocation.latitude;
    final pickupLng = ride.pickupLocation.longitude;

    // Haversine formula
    const double earthRadiusMiles = 3958.8;
    final double dLat = _toRadians(pickupLat - driverLat);
    final double dLng = _toRadians(pickupLng - driverLng);

    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(driverLat)) * math.cos(_toRadians(pickupLat)) *
        math.sin(dLng / 2) * math.sin(dLng / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadiusMiles * c;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180;

  /// Format recurring days as short day names (L M X J V S D)
  String _formatRecurringDays(List<int> days) {
    if (days.isEmpty) return '';
    const dayNames = ['', 'L', 'M', 'X', 'J', 'V', 'S', 'D'];
    return days.map((d) => d >= 1 && d <= 7 ? dayNames[d] : '').join(' ');
  }

  void _showRideDetails(RideModel ride) {
    HapticService.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(28),
            topRight: Radius.circular(28),
          ),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 5,
              margin: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundImage: ride.displayImageUrl != null
                              ? NetworkImage(ride.displayImageUrl!)
                              : null,
                          backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                          child: ride.displayImageUrl == null
                              ? Text(
                                  ride.displayName.isNotEmpty ? ride.displayName[0] : 'P',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 24,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      ride.displayName,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 22,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  if (ride.isRoundTrip) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [Color(0xFF00C853), Color(0xFF00BFA5)],
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'ROUND TRIP',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  if (ride.passengerRating > 0) ...[
                                    Icon(Icons.star_rounded, color: AppColors.star, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      ride.passengerRating.toStringAsFixed(1),
                                      style: TextStyle(color: AppColors.textSecondary),
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  // Distance to pickup in modal
                                  Builder(
                                    builder: (context) {
                                      final distToPickup = _calculateDistanceToPickup(ride);
                                      if (distToPickup != null) {
                                        return Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.near_me, size: 12, color: AppColors.warning),
                                            const SizedBox(width: 3),
                                            Text(
                                              '${distToPickup.toStringAsFixed(1)} mi away',
                                              style: TextStyle(
                                                color: AppColors.warning,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Text(
                                              ' • ',
                                              style: TextStyle(color: AppColors.textSecondary),
                                            ),
                                          ],
                                        );
                                      }
                                      return const SizedBox.shrink();
                                    },
                                  ),
                                  Text(
                                    '${(ride.distanceKm * 0.621371).toStringAsFixed(1)} mi • ${ride.estimatedMinutes} min',
                                    style: TextStyle(color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                              if (ride.recurringDays.isNotEmpty || (ride.type == RideType.carpool && ride.filledSeats > 1)) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    if (ride.recurringDays.isNotEmpty)
                                      Text(
                                        _formatRecurringDays(ride.recurringDays),
                                        style: TextStyle(
                                          color: AppColors.primary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    if (ride.recurringDays.isNotEmpty && ride.type == RideType.carpool)
                                      const SizedBox(width: 12),
                                    if (ride.type == RideType.carpool && ride.filledSeats > 0)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: List.generate(3, (i) {
                                          final color = i < ride.filledSeats ? AppColors.success : AppColors.textSecondary.withValues(alpha: 0.3);
                                          return Padding(
                                            padding: EdgeInsets.only(left: i > 0 ? 2 : 0),
                                            child: Icon(Icons.person, color: color, size: 16),
                                          );
                                        }),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        // PREVIEW: If no real earnings yet, calculate from fare * driver%
                        Builder(builder: (context) {
                          final earnings = ride.driverEarnings > 0
                              ? ride.driverEarnings
                              : ride.fare * (_driverPercent / 100);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '\$${earnings.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.success,
                                ),
                              ),
                              if (ride.driverEarnings <= 0)
                                Text(
                                  'estimated'.tr(),
                                  style: TextStyle(
                                    color: AppColors.warning,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'trip_details'.tr(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _buildDetailRow(Icons.location_on_rounded, 'pickup'.tr(), ride.pickupLocation.address ?? 'N/A'),
                    _buildDetailRow(Icons.flag_rounded, 'destination'.tr(), ride.dropoffLocation.address ?? 'N/A'),
                    _buildDetailRow(Icons.payment_rounded, 'payment_method'.tr(), 'card'.tr()),
                    if (ride.notes != null && ride.notes!.isNotEmpty)
                      _buildDetailRow(Icons.note_rounded, 'note'.tr(), ride.notes!),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: NeonButton(
                            text: 'reject'.tr(),
                            onPressed: () {
                              HapticService.warning();
                              Navigator.pop(context);
                            },
                            isOutlined: true,
                            color: AppColors.error,
                            height: 54,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: NeonButton(
                            text: 'accept_trip_btn'.tr(),
                            icon: Icons.check_rounded,
                            onPressed: () async {
                              final navigator = Navigator.of(context);
                              final rideProvider = context.read<RideProvider>();
                              final driverId = context.read<DriverProvider>().driver?.id;
                              if (driverId != null) {
                                final success = await rideProvider.acceptRide(ride.id, driverId);
                                if (success) {
                                  HapticService.success();
                                  if (mounted) {
                                    navigator.pop();
                                    navigator.pushNamed('/navigation');
                                  }
                                } else {
                                  HapticService.error();
                                }
                              }
                            },
                            gradient: AppColors.successGradient,
                            height: 54,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ONLINE STATUS BUTTON - With press feedback
// ═══════════════════════════════════════════════════════════════════════════════

class _OnlineStatusButton extends StatefulWidget {
  final bool isOnline;
  final VoidCallback onTap;

  const _OnlineStatusButton({
    required this.isOnline,
    required this.onTap,
  });

  @override
  State<_OnlineStatusButton> createState() => _OnlineStatusButtonState();
}

class _OnlineStatusButtonState extends State<_OnlineStatusButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.isOnline ? AppColors.success : AppColors.textSecondary;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _isPressed
              ? color.withValues(alpha: 0.25)
              : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _isPressed
                ? color.withValues(alpha: 0.5)
                : color.withValues(alpha: 0.2),
            width: _isPressed ? 1.5 : 1,
          ),
          boxShadow: _isPressed
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: widget.isOnline ? AppColors.success : AppColors.textSecondary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              widget.isOnline ? 'online'.tr() : 'offline_status'.tr(),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
