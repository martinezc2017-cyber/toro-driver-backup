import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../models/driver_model.dart';
import '../utils/app_colors.dart';
import '../utils/haptic_service.dart';

/// Waiting screen for admin approval
/// Driver must wait until admin approves their account
class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Timer? _checkTimer;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();

    // Pulse animation for icon
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Check status every 30 seconds
    _checkTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkApprovalStatus();
    });

    // Initial check - DEFER to avoid setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkApprovalStatus();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _checkTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkApprovalStatus() async {
    if (_isChecking) return;

    setState(() => _isChecking = true);

    try {
      final authProvider = context.read<AuthProvider>();
      await authProvider.refreshProfile();

      if (!mounted) return;

      final status = authProvider.driver?.status;

      if (status == DriverStatus.active) {
        HapticService.heavyImpact();
        // AuthWrapper will detect the change and navigate automatically
      }
    } catch (e) {
      debugPrint('Error checking approval status: $e');
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  Future<void> _signOut() async {
    final authProvider = context.read<AuthProvider>();
    await authProvider.signOut();
  }

  String get _statusMessage {
    final status = context.watch<AuthProvider>().driver?.status;
    switch (status) {
      case DriverStatus.pending:
        return 'Your application is being reviewed';
      case DriverStatus.suspended:
        return 'Your account has been suspended. Please contact support.';
      case DriverStatus.rejected:
        return 'Your application was rejected. Please contact support.';
      default:
        return 'Your application is being reviewed';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),

              // Animated pulse icon
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.warning.withValues(alpha: 0.3),
                            AppColors.warning.withValues(alpha: 0.1),
                          ],
                        ),
                        border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.5),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.warning.withValues(alpha: 0.2),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.hourglass_top_rounded,
                          size: 60,
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 40),

              // Title
              const Text(
                'PENDING APPROVAL',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  letterSpacing: 3,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              // Status message
              Text(
                _statusMessage,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 40),

              // Info card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.border,
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    _buildInfoRow(
                      Icons.schedule_rounded,
                      'Review Time',
                      '24-48 hours',
                    ),
                    const Divider(color: AppColors.divider, height: 24),
                    _buildInfoRow(
                      Icons.verified_user_rounded,
                      'Verification',
                      'Documents & background check',
                    ),
                    const Divider(color: AppColors.divider, height: 24),
                    _buildInfoRow(
                      Icons.notifications_active_rounded,
                      'Notification',
                      'We\'ll notify you by email',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Complete Documents button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pushNamed(context, '/documents'),
                  icon: const Icon(Icons.folder_open_rounded, size: 20),
                  label: const Text('Complete Documents'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Refresh button
              GestureDetector(
                onTap: _isChecking ? null : _checkApprovalStatus,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isChecking)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      else
                        const Icon(
                          Icons.refresh_rounded,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      const SizedBox(width: 10),
                      Text(
                        _isChecking ? 'Checking...' : 'Check Status',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // Sign out button
              TextButton(
                onPressed: _signOut,
                child: const Text(
                  'Sign Out',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 14,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Version
              const Text(
                'TORO DRIVER v1.0.0',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textDisabled,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String title, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.cardSecondary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: AppColors.textTertiary,
            size: 20,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
