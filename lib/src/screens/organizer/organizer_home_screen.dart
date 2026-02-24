import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/supabase_config.dart';
import '../../providers/driver_provider.dart';
import '../../services/tourism_event_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';
import '../profile_screen.dart';
import '../tourism/vehicle_request_screen.dart';
import 'organizer_vehicles_tab.dart';
import 'organizer_events_history_tab.dart';
import 'organizer_events_tab.dart';

/// Main shell for the Organizer role.
///
/// Provides a bottom navigation bar with five tabs:
///   0 - Eventos (tourism_events)
///   1 - Pujas (open events + invitations from [VehicleRequestScreen])
///   2 - Vehiculos
///   3 - Historial
///   4 - Perfil (reuses the existing [ProfileScreen])
class OrganizerHomeScreen extends StatefulWidget {
  /// Optional callback to switch back to Driver mode
  final VoidCallback? onSwitchToDriverMode;

  const OrganizerHomeScreen({
    super.key,
    this.onSwitchToDriverMode,
  });

  @override
  State<OrganizerHomeScreen> createState() => _OrganizerHomeScreenState();
}

class _OrganizerHomeScreenState extends State<OrganizerHomeScreen> {
  int _currentIndex = 0;

  late final List<Widget> _tabs;

  // Persistent bid notification banner
  int _activeBidCount = 0;
  bool _bannerDismissed = false;
  RealtimeChannel? _bidChannel;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabs = const [
      OrganizerEventsTab(),
      VehicleRequestScreen(embedded: true),
      OrganizerVehiclesTab(),
      OrganizerEventsHistoryTab(),
      ProfileScreen(),
    ];
    _loadActiveBidCount();
    _subscribeToBidUpdates();
    // Refresh every 30s
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadActiveBidCount();
    });
  }

  @override
  void dispose() {
    if (_bidChannel != null) {
      SupabaseConfig.client.removeChannel(_bidChannel!);
      _bidChannel = null;
    }
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadActiveBidCount() async {
    try {
      // Get organizer ID from auth user
      final userId = SupabaseConfig.client.auth.currentUser?.id;
      if (userId == null) return;

      final orgData = await SupabaseConfig.client
          .from('organizers')
          .select('id')
          .eq('user_id', userId)
          .maybeSingle();
      if (orgData == null) return;

      final organizerId = orgData['id'] as String;
      final count = await TourismEventService().getOrganizerPendingBidCount(organizerId);
      if (mounted && count != _activeBidCount) {
        setState(() {
          _activeBidCount = count;
          if (count > 0) _bannerDismissed = false;
        });
      }
    } catch (_) {}
  }

  void _subscribeToBidUpdates() {
    try {
      final driverProvider = Provider.of<DriverProvider>(context, listen: false);
      final driver = driverProvider.driver;
      if (driver == null) return;

      _bidChannel = SupabaseConfig.client
          .channel('organizer_bids_${driver.id}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'tourism_vehicle_bids',
            callback: (_) => _loadActiveBidCount(),
          )
          .subscribe();
    } catch (_) {}
  }

  void _onTabTapped(int index) {
    if (index == _currentIndex) return;
    HapticService.lightImpact();
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: widget.onSwitchToDriverMode != null ? _buildAppBar() : null,
      body: Column(
        children: [
          // Persistent bid notification banner (taps go to Pujas tab)
          if (_activeBidCount > 0 && !_bannerDismissed && _currentIndex != 1)
            _buildBidBanner(),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: _tabs,
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBidBanner() {
    return GestureDetector(
      onTap: () {
        HapticService.lightImpact();
        setState(() => _currentIndex = 1); // Go to Pujas tab
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF9500), Color(0xFFFF6B00)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF9500).withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.gavel_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$_activeBidCount puja${_activeBidCount > 1 ? 's' : ''} activa${_activeBidCount > 1 ? 's' : ''}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Text(
                    'Toca para ver tus pujas',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 14),
            const SizedBox(width: 4),
            // Dismiss button
            GestureDetector(
              onTap: () {
                setState(() => _bannerDismissed = true);
              },
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      automaticallyImplyLeading: false,
      toolbarHeight: 36,
      title: GestureDetector(
        onTap: () {
          HapticService.lightImpact();
          widget.onSwitchToDriverMode?.call();
        },
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFF9500), width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(7)),
                child: Icon(Icons.local_taxi_rounded, color: AppColors.textTertiary, size: 14),
              ),
              const SizedBox(width: 2),
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFFF9500), Color(0xFFFF6B00)]),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(
            color: AppColors.border,
            width: 0.5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onTabTapped,
          type: BottomNavigationBarType.fixed,
          backgroundColor: AppColors.surface,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textTertiary,
          selectedFontSize: 10,
          unselectedFontSize: 9,
          elevation: 0,
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.event_outlined),
              activeIcon: Icon(Icons.event),
              label: 'Eventos',
            ),
            BottomNavigationBarItem(
              icon: Badge(
                isLabelVisible: _activeBidCount > 0,
                label: Text('$_activeBidCount',
                    style: const TextStyle(fontSize: 9, color: Colors.white)),
                backgroundColor: Colors.orange,
                child: const Icon(Icons.gavel_outlined),
              ),
              activeIcon: Badge(
                isLabelVisible: _activeBidCount > 0,
                label: Text('$_activeBidCount',
                    style: const TextStyle(fontSize: 9, color: Colors.white)),
                backgroundColor: Colors.orange,
                child: const Icon(Icons.gavel),
              ),
              label: 'Pujas',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.directions_bus_outlined),
              activeIcon: Icon(Icons.directions_bus),
              label: 'Vehiculos',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.attach_money_outlined),
              activeIcon: Icon(Icons.attach_money),
              label: 'Historial',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Perfil',
            ),
          ],
        ),
      ),
    );
  }
}
