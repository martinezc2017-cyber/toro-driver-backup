import 'dart:async';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../utils/app_colors.dart';
import '../services/ranking_service.dart';
import '../providers/driver_provider.dart';
import '../config/supabase_config.dart';

class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  StreamSubscription? _realtimeSubscription;

  // Data loading
  bool _isLoading = true;
  List<RankedDriver> _stateDrivers = [];  // All drivers from my state
  List<RankedDriver> _usaTop10 = [];      // Top 10 drivers USA

  // My position data
  int _myStateRank = 0;      // My rank in state
  int _myUsaRank = 0;        // My rank in USA
  int _totalInState = 0;     // Total drivers in my state
  int _myPoints = 0;         // My acceptance rate %
  int _myChange = 0;         // Rank change
  String? _myDriverId;
  String? _myState;          // My state

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);  // 2 tabs: State & USA
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});  // Refresh UI when tab changes
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRankingData();
      _subscribeToRealtimeUpdates();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _realtimeSubscription?.cancel();
    super.dispose();
  }

  void _subscribeToRealtimeUpdates() {
    // Subscribe to realtime changes in drivers table
    _realtimeSubscription = SupabaseConfig.client
        .from('drivers')
        .stream(primaryKey: ['id'])
        .listen((data) {
          // Reload ranking data when any driver data changes
          _loadRankingData();
        });
  }

  Future<void> _loadRankingData() async {
    setState(() => _isLoading = true);

    try {
      // Get current driver data
      final driverProvider = Provider.of<DriverProvider>(context, listen: false);
      final driver = driverProvider.driver;

      if (driver != null) {
        _myDriverId = driver.id;

        // Get my position first to know my state
        final myPosition = await RankingService.getMyPosition(driver.id);
        final myStateFromDB = driver.state ?? 'Unknown';

        // Load rankings in parallel
        final results = await Future.wait([
          RankingService.getRanking(period: 'alltime', stateFilter: myStateFromDB, limit: 100),  // All drivers from my state
          RankingService.getRanking(period: 'alltime', limit: 10),  // Top 10 USA
        ]);

        setState(() {
          _stateDrivers = results[0] as List<RankedDriver>;
          _usaTop10 = results[1] as List<RankedDriver>;

          // My position data
          _myState = myStateFromDB;
          _myUsaRank = myPosition['rank'] as int;
          _myPoints = myPosition['points'] as int;
          _myChange = myPosition['change'] as int;

          // Calculate my state rank
          final myIndexInState = _stateDrivers.indexWhere((d) => d.id == driver.id);
          _myStateRank = myIndexInState >= 0 ? myIndexInState + 1 : 0;
          _totalInState = _stateDrivers.length;

          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading ranking data: $e');
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
            Icon(Icons.leaderboard, size: 18, color: AppColors.star),
            const SizedBox(width: 8),
            Text('ranking'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : Column(
              children: [
                // My position - clean design
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary.withValues(alpha: 0.08),
                        AppColors.primary.withValues(alpha: 0.03),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Row(
                    children: [
                      // State Rank
                      Expanded(
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.location_on,
                                  size: 16,
                                  color: _tabController.index == 0 ? AppColors.primary : AppColors.textSecondary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '#${_myStateRank > 0 ? _myStateRank : '-'}',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: _tabController.index == 0 ? AppColors.primary : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _myState ?? 'State',
                              style: TextStyle(
                                fontSize: 11,
                                color: _tabController.index == 0 ? AppColors.primary : AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Divider
                      Container(
                        height: 40,
                        width: 1,
                        color: AppColors.border,
                      ),

                      // USA Rank
                      Expanded(
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '🇺🇸',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: _tabController.index == 1 ? AppColors.primary : AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '#${_myUsaRank > 0 ? _myUsaRank : '-'}',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: _tabController.index == 1 ? AppColors.primary : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'USA Rank',
                              style: TextStyle(
                                fontSize: 11,
                                color: _tabController.index == 1 ? AppColors.primary : AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Divider
                      Container(
                        height: 40,
                        width: 1,
                        color: AppColors.border,
                      ),

                      // Acceptance Rate
                      Expanded(
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_circle, size: 16, color: AppColors.success),
                                const SizedBox(width: 6),
                                Text(
                                  '$_myPoints%',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.success,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Aceptación',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

          // Tab bar - compact
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
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
              tabs: [
                Tab(text: _myState ?? 'State'),   // Solo el nombre del estado
                const Tab(text: 'USA'),            // Solo USA
              ],
            ),
          ),
          const SizedBox(height: 8),

                // Ranking list
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildRankingList(_stateDrivers, isStateTab: true),   // All drivers from my state
                      _buildRankingList(_usaTop10, isStateTab: false),      // Top 10 USA only
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildRankingList(List<RankedDriver> drivers, {required bool isStateTab}) {
    if (drivers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.leaderboard, size: 48, color: AppColors.textSecondary.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(
              isStateTab
                  ? 'No hay drivers en $_myState'
                  : 'No hay datos de top 10 USA',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: drivers.length,
      itemBuilder: (context, index) {
        final driver = drivers[index];
        final position = driver.rank;
        final isCurrentUser = driver.id == _myDriverId;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isCurrentUser ? AppColors.primary.withValues(alpha: 0.1) : AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isCurrentUser ? AppColors.primary.withValues(alpha: 0.4) : AppColors.border.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              // Position
              SizedBox(
                width: 28,
                child: Text(
                  '#$position',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: position <= 3 ? AppColors.star : AppColors.textSecondary,
                  ),
                ),
              ),
              // Avatar
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    driver.initial,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Name
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        driver.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isCurrentUser ? FontWeight.bold : FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isCurrentUser) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('Tú', style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
              ),
              // Acceptance Rate
              Row(
                children: [
                  const Icon(Icons.check_circle, size: 12, color: AppColors.success),
                  const SizedBox(width: 4),
                  Text(
                    '${driver.points}%',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              // Change indicator
              _buildChangeIndicator(driver.rankChange),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChangeIndicator(int change) {
    if (change == 0) {
      return SizedBox(
        width: 24,
        child: Center(
          child: Text('-', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ),
      );
    }

    final isPositive = change > 0;
    return SizedBox(
      width: 24,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPositive ? Icons.arrow_drop_up : Icons.arrow_drop_down,
            color: isPositive ? AppColors.success : AppColors.error,
            size: 16,
          ),
          Text(
            '${change.abs()}',
            style: TextStyle(
              fontSize: 10,
              color: isPositive ? AppColors.success : AppColors.error,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
