import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import '../providers/auth_provider.dart';
import '../config/supabase_config.dart';
import '../services/organizer_service.dart';
import '../utils/app_colors.dart';
import '../utils/haptic_service.dart';

/// Driver credential / business card screen.
/// Same fields as organizer credential: email, phone, facebook, logo/tarjeta.
/// Saved directly to the `drivers` table.
class DriverCredentialScreen extends StatefulWidget {
  const DriverCredentialScreen({super.key});

  @override
  State<DriverCredentialScreen> createState() => _DriverCredentialScreenState();
}

class _DriverCredentialScreenState extends State<DriverCredentialScreen> {
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _facebookController = TextEditingController();
  String? _businessCardUrl;
  bool _loading = true;
  bool _saving = false;
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    _loadCredential();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _facebookController.dispose();
    super.dispose();
  }

  Future<void> _loadCredential() async {
    final driver = context.read<AuthProvider>().driver;
    if (driver == null) {
      setState(() => _loading = false);
      return;
    }

    setState(() {
      _emailController.text = driver.contactEmail ?? '';
      _phoneController.text = driver.contactPhone ?? '';
      _facebookController.text = driver.contactFacebook ?? '';
      _businessCardUrl = driver.businessCardUrl;
      _loading = false;
      // If any data exists, show compact view
      final hasData = _emailController.text.isNotEmpty ||
          _phoneController.text.isNotEmpty ||
          _facebookController.text.isNotEmpty ||
          _businessCardUrl != null;
      _expanded = !hasData;
    });
  }

  Future<void> _saveCredential() async {
    final driver = context.read<AuthProvider>().driver;
    if (driver == null) return;

    setState(() => _saving = true);
    try {
      final updates = {
        'contact_email': _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
        'contact_phone': _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        'contact_facebook': _facebookController.text.trim().isEmpty
            ? null
            : _facebookController.text.trim(),
        'business_card_url': _businessCardUrl,
        'updated_at': DateTime.now().toIso8601String(),
      };

      await SupabaseConfig.client
          .from('drivers')
          .update(updates)
          .eq('id', driver.id);

      // Also update organizer profile if user has one (keeps data in sync)
      try {
        final userId = SupabaseConfig.client.auth.currentUser?.id;
        if (userId != null) {
          final orgService = OrganizerService();
          final orgProfile = await orgService.getOrganizerProfile(userId);
          if (orgProfile != null) {
            await orgService.updateOrganizerProfile(orgProfile['id'], {
              'contact_phone': _phoneController.text.trim().isEmpty
                  ? null
                  : _phoneController.text.trim(),
              'contact_email': _emailController.text.trim().isEmpty
                  ? null
                  : _emailController.text.trim(),
            });
          }
        }
      } catch (_) {
        // Non-critical: organizer sync failed, driver data still saved
      }

      // Update local driver model
      if (mounted) {
        context.read<AuthProvider>().updateDriver(driver.copyWith(
              contactEmail: _emailController.text.trim(),
              contactPhone: _phoneController.text.trim(),
              contactFacebook: _facebookController.text.trim(),
              businessCardUrl: _businessCardUrl,
            ));
      }

      if (mounted) {
        setState(() {
          _saving = false;
          _expanded = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Credencial guardada'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _uploadBusinessCard() async {
    final driver = context.read<AuthProvider>().driver;
    if (driver == null) return;

    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image == null) return;

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );

      final bytes = await image.readAsBytes();
      final ext = image.path.split('.').last.toLowerCase();
      final fileName = '${driver.id}/business_card_${DateTime.now().millisecondsSinceEpoch}.$ext';

      await SupabaseConfig.client.storage
          .from('organizer-logos')
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );

      final publicUrl = SupabaseConfig.client.storage
          .from('organizer-logos')
          .getPublicUrl(fileName);

      if (mounted) Navigator.pop(context);

      setState(() => _businessCardUrl = publicUrl);
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al subir: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final driver = context.watch<AuthProvider>().driver;
    final driverName = driver?.name ?? 'Sin nombre';
    final photoUrl = driver?.profileImageUrl;

    // Calculate time with Toro
    String timeWithToro = 'Nuevo';
    if (driver != null) {
      final difference = DateTime.now().difference(driver.createdAt);
      if (difference.inDays >= 365) {
        final years = (difference.inDays / 365).floor();
        timeWithToro = '$years año${years > 1 ? 's' : ''} con Toro';
      } else if (difference.inDays >= 30) {
        final months = (difference.inDays / 30).floor();
        timeWithToro = '$months mes${months > 1 ? 'es' : ''} con Toro';
      } else if (difference.inDays > 0) {
        timeWithToro = '${difference.inDays} día${difference.inDays > 1 ? 's' : ''} con Toro';
      } else {
        timeWithToro = 'Nuevo con Toro';
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Mi Credencial',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Profile header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.primary, width: 2),
                            image: photoUrl != null
                                ? DecorationImage(
                                    image: NetworkImage(photoUrl),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: photoUrl == null
                              ? Icon(Icons.person, color: AppColors.textTertiary, size: 36)
                              : null,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                driverName,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.access_time, size: 14, color: AppColors.primary),
                                  const SizedBox(width: 4),
                                  Text(
                                    timeWithToro,
                                    style: TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              if (driver?.rating != null && driver!.rating > 0) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.star, size: 14, color: Colors.amber),
                                    const SizedBox(width: 4),
                                    Text(
                                      driver.rating.toStringAsFixed(1),
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Credential section
                  if (!_expanded) ...[
                    // ── COMPACT CARD ──
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.check_circle, color: AppColors.success, size: 18),
                              const SizedBox(width: 8),
                              const Text(
                                'Credencial Guardada',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: () => setState(() => _expanded = true),
                                icon: Icon(Icons.edit, size: 16, color: AppColors.primary),
                                label: Text(
                                  'Editar',
                                  style: TextStyle(color: AppColors.primary, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              if (_emailController.text.isNotEmpty)
                                _chip(Icons.email, _emailController.text),
                              if (_phoneController.text.isNotEmpty)
                                _chip(Icons.phone, _phoneController.text),
                              if (_facebookController.text.isNotEmpty)
                                _chip(Icons.facebook, 'Facebook'),
                              if (_businessCardUrl != null)
                                _chip(Icons.image, 'Logo/Tarjeta'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    // ── EXPANDED FORM ──
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Información de Contacto',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Email
                          TextFormField(
                            controller: _emailController,
                            style: const TextStyle(color: AppColors.textPrimary),
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: 'Email de Negocios',
                              labelStyle: TextStyle(color: AppColors.textSecondary),
                              prefixIcon: Icon(Icons.email, color: AppColors.textSecondary),
                              hintText: 'contacto@empresa.com',
                              hintStyle: TextStyle(color: AppColors.textTertiary),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: AppColors.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: AppColors.border),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Phone
                          TextFormField(
                            controller: _phoneController,
                            style: const TextStyle(color: AppColors.textPrimary),
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              labelText: 'Teléfono de Negocios',
                              labelStyle: TextStyle(color: AppColors.textSecondary),
                              prefixIcon: Icon(Icons.business, color: AppColors.textSecondary),
                              hintText: '664-123-4567',
                              hintStyle: TextStyle(color: AppColors.textTertiary),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: AppColors.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: AppColors.border),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Facebook
                          TextFormField(
                            controller: _facebookController,
                            style: const TextStyle(color: AppColors.textPrimary),
                            decoration: InputDecoration(
                              labelText: 'Facebook de Negocios',
                              labelStyle: TextStyle(color: AppColors.textSecondary),
                              prefixIcon: Icon(Icons.facebook, color: AppColors.textSecondary),
                              hintText: 'facebook.com/tupagina',
                              hintStyle: TextStyle(color: AppColors.textTertiary),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: AppColors.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: AppColors.border),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Business Card / Logo upload
                          InkWell(
                            onTap: _uploadBusinessCard,
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _businessCardUrl != null ? AppColors.primary : AppColors.border,
                                  width: _businessCardUrl != null ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      color: AppColors.surface,
                                      image: _businessCardUrl != null
                                          ? DecorationImage(
                                              image: NetworkImage(_businessCardUrl!),
                                              fit: BoxFit.cover,
                                            )
                                          : null,
                                    ),
                                    child: _businessCardUrl == null
                                        ? Icon(Icons.business_center, color: AppColors.textTertiary, size: 24)
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _businessCardUrl != null ? 'Logo/Tarjeta Cargada' : 'Agregar Logo o Tarjeta',
                                          style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Tarjeta de presentación profesional',
                                          style: TextStyle(
                                            color: AppColors.textTertiary,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    _businessCardUrl != null ? Icons.check_circle : Icons.upload,
                                    color: _businessCardUrl != null ? AppColors.primary : AppColors.textSecondary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),

                          // Save button
                          SizedBox(
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: _saving ? null : _saveCredential,
                              icon: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.save, size: 20),
                              label: Text(
                                _saving ? 'Guardando...' : 'Guardar Credencial',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.success,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Info
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: AppColors.primary, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Tu credencial se muestra a organizadores y clientes cuando aceptas un evento.',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
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

  Widget _chip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.primary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
