import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/auth_provider.dart';
import '../utils/app_colors.dart';

/// Screen shown when user is authenticated but has no driver profile
/// Gives options to: register as driver, switch account, or create new account
class AccountChoiceScreen extends StatefulWidget {
  const AccountChoiceScreen({super.key});

  @override
  State<AccountChoiceScreen> createState() => _AccountChoiceScreenState();
}

class _AccountChoiceScreenState extends State<AccountChoiceScreen> {
  bool _isCreatingDriver = false;

  Future<void> _registerAsDriver() async {
    setState(() => _isCreatingDriver = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        setState(() => _isCreatingDriver = false);
        return;
      }

      // Create minimal driver record - user can complete profile later
      await Supabase.instance.client.from('drivers').upsert({
        'id': user.id,
        'email': user.email,
        'full_name': user.userMetadata?['full_name'] ?? user.email?.split('@').first ?? 'Driver',
        'phone': user.phone ?? '',
        'status': 'pending', // Pending until documents complete
        'created_at': DateTime.now().toIso8601String(),
      });

      // Refresh the auth provider to pick up the new driver record
      if (mounted) {
        await context.read<AuthProvider>().refreshProfile();
      }
    } catch (e) {
      debugPrint('Error creating driver record: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreatingDriver = false);
      }
    }
  }

  Future<void> _switchAccount() async {
    await context.read<AuthProvider>().signOut();
    // AuthWrapper will show LoginScreen automatically
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? 'Unknown';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.warning.withOpacity(0.15),
                  border: Border.all(
                    color: AppColors.warning.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.person_outline_rounded,
                  size: 50,
                  color: AppColors.warning,
                ),
              ),

              const SizedBox(height: 32),

              // Title
              const Text(
                'Account Not Registered',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 12),

              // Subtitle with email
              Text(
                'Logged in as:',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                email,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'This account is not registered as a TORO driver.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 40),

              // Register as Driver button (Primary)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isCreatingDriver ? null : _registerAsDriver,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isCreatingDriver
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.drive_eta_rounded, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Register as Driver',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 16),

              // Switch Account button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _switchAccount,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.swap_horiz_rounded, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Use Different Account',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // Info text
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: AppColors.textTertiary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'You can complete your driver profile and upload documents after registration.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textTertiary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
