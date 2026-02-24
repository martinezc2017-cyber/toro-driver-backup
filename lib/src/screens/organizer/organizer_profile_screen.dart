import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/organizer_service.dart';
import '../../config/supabase_config.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';
import '../../widgets/travel_card_widget.dart';

/// Screen for organizers to view and edit their company profile.
/// Displays company name, logo, website, description, and social media links.
class OrganizerProfileScreen extends StatefulWidget {
  const OrganizerProfileScreen({super.key});

  @override
  State<OrganizerProfileScreen> createState() => _OrganizerProfileScreenState();
}

class _OrganizerProfileScreenState extends State<OrganizerProfileScreen> {
  final _organizerService = OrganizerService();
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _saving = false;
  Map<String, dynamic>? _profile;

  // Form controllers
  final _companyNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _websiteController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _facebookController = TextEditingController();
  final _instagramController = TextEditingController();
  final _twitterController = TextEditingController();

  String? _logoUrl;
  String? _businessCardUrl;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    // Rebuild preview when fields change
    _companyNameController.addListener(_onFieldChanged);
    _phoneController.addListener(_onFieldChanged);
    _emailController.addListener(_onFieldChanged);
    _websiteController.addListener(_onFieldChanged);
    _descriptionController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _companyNameController.removeListener(_onFieldChanged);
    _phoneController.removeListener(_onFieldChanged);
    _emailController.removeListener(_onFieldChanged);
    _websiteController.removeListener(_onFieldChanged);
    _descriptionController.removeListener(_onFieldChanged);
    _companyNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _websiteController.dispose();
    _descriptionController.dispose();
    _facebookController.dispose();
    _instagramController.dispose();
    _twitterController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;

    final profile = await _organizerService.getOrganizerProfile(userId);

    if (mounted && profile != null) {
      setState(() {
        _profile = profile;
        _companyNameController.text = profile['company_name'] ?? '';
        _phoneController.text = profile['contact_phone'] ?? profile['phone'] ?? '';
        _emailController.text = profile['contact_email'] ?? profile['email'] ?? '';
        _websiteController.text = profile['website'] ?? '';
        _descriptionController.text = profile['description'] ?? '';
        _logoUrl = profile['company_logo_url'];
        _businessCardUrl = profile['business_card_url'];

        // Parse social media JSON
        final socialMedia = profile['social_media'] as Map<String, dynamic>? ?? {};
        _facebookController.text = socialMedia['facebook'] ?? '';
        _instagramController.text = socialMedia['instagram'] ?? '';
        _twitterController.text = socialMedia['twitter'] ?? '';

        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickAndUploadLogo() async {
    if (_profile == null) return;

    // Mostrar diálogo simple: Galería o Cámara
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cambiar Logo', style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.primary),
              title: const Text('Galería', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.success),
              title: const Text('Cámara', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );

    if (image == null) return;

    setState(() => _saving = true);

    final imageBytes = await image.readAsBytes();
    final newUrl = await _organizerService.uploadCompanyLogo(
      _profile!['id'],
      image.path,
      bytes: imageBytes,
    );

    if (mounted) {
      setState(() {
        if (newUrl != null) _logoUrl = newUrl;
        _saving = false;
      });

      if (newUrl != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Logo actualizado'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  Future<void> _pickAndUploadBusinessCard() async {
    if (_profile == null) return;

    final source = await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Tarjeta de Presentación', style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.primary),
              title: const Text('Galería', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.success),
              title: const Text('Cámara', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: source,
      maxWidth: 1200,
      maxHeight: 800,
      imageQuality: 90,
    );

    if (image == null) return;

    setState(() => _saving = true);

    try {
      final newUrl = await _organizerService.uploadBusinessCard(
        _profile!['id'],
        image.path,
      );

      if (mounted) {
        setState(() {
          if (newUrl != null) _businessCardUrl = newUrl;
          _saving = false;
        });

        if (newUrl != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tarjeta de presentación actualizada'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _saveProfile() async {
    if (_profile == null || !_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final socialMedia = <String, dynamic>{};
      if (_facebookController.text.isNotEmpty) {
        socialMedia['facebook'] = _facebookController.text.trim();
      }
      if (_instagramController.text.isNotEmpty) {
        socialMedia['instagram'] = _instagramController.text.trim();
      }
      if (_twitterController.text.isNotEmpty) {
        socialMedia['twitter'] = _twitterController.text.trim();
      }

      final updates = {
        'company_name': _companyNameController.text.trim(),
        'contact_phone': _phoneController.text.trim(),
        'contact_email': _emailController.text.trim(),
        'website': _websiteController.text.trim(),
        'description': _descriptionController.text.trim(),
        'social_media': socialMedia,
      };

      await _organizerService.updateOrganizerProfile(
        _profile!['id'],
        updates,
      );

      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Perfil guardado'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _openUrl(String url) async {
    if (url.isEmpty) return;
    String fullUrl = url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      fullUrl = 'https://$url';
    }
    final uri = Uri.parse(fullUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
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
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Mi Perfil',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        actions: [
          if (!_loading && _profile != null)
            TextButton(
              onPressed: _saving ? null : _saveProfile,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  : const Text(
                      'Guardar',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _profile == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.business, size: 64, color: AppColors.textTertiary),
                      const SizedBox(height: 16),
                      const Text(
                        'No tienes perfil registrado',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Logo section
                        Center(
                          child: GestureDetector(
                            onTap: _saving ? null : () {
                              HapticService.lightImpact();
                              _pickAndUploadLogo();
                            },
                            child: Stack(
                              children: [
                                CircleAvatar(
                                  radius: 60,
                                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                                  backgroundImage: _logoUrl != null
                                      ? NetworkImage(_logoUrl!)
                                      : null,
                                  child: _logoUrl == null
                                      ? const Icon(
                                          Icons.business,
                                          size: 48,
                                          color: AppColors.primary,
                                        )
                                      : null,
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: AppColors.background, width: 3),
                                    ),
                                    child: const Icon(
                                      Icons.camera_alt,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Center(
                          child: Text(
                            'Toca para cambiar logo',
                            style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Basic info section
                        _buildSectionTitle('Informacion Basica'),
                        const SizedBox(height: 12),
                        _buildCard(
                          children: [
                            _buildTextField(
                              controller: _companyNameController,
                              label: 'Nombre de la Empresa',
                              icon: Icons.business,
                              validator: (v) => v == null || v.isEmpty
                                  ? 'Requerido'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: _phoneController,
                              label: 'Telefono',
                              icon: Icons.phone,
                              keyboardType: TextInputType.phone,
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: _emailController,
                              label: 'Email de Contacto',
                              icon: Icons.email,
                              keyboardType: TextInputType.emailAddress,
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Website & Description
                        _buildSectionTitle('Descripcion'),
                        const SizedBox(height: 12),
                        _buildCard(
                          children: [
                            _buildTextField(
                              controller: _websiteController,
                              label: 'Sitio Web',
                              icon: Icons.language,
                              keyboardType: TextInputType.url,
                              suffixIcon: _websiteController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.open_in_new,
                                          color: AppColors.primary),
                                      onPressed: () =>
                                          _openUrl(_websiteController.text),
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: _descriptionController,
                              label: 'Descripcion de la Empresa',
                              icon: Icons.description,
                              maxLines: 4,
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Social media
                        _buildSectionTitle('Redes Sociales'),
                        const SizedBox(height: 12),
                        _buildCard(
                          children: [
                            _buildTextField(
                              controller: _facebookController,
                              label: 'Facebook',
                              icon: Icons.facebook,
                              hint: 'facebook.com/tu-pagina',
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: _instagramController,
                              label: 'Instagram',
                              icon: Icons.camera_alt_outlined,
                              hint: '@tu_usuario',
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              controller: _twitterController,
                              label: 'Twitter / X',
                              icon: Icons.alternate_email,
                              hint: '@tu_usuario',
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Live travel card preview
                        _buildSectionTitle('Vista Previa de Tarjeta'),
                        const SizedBox(height: 8),
                        Text(
                          'Asi se ve tu tarjeta en los eventos',
                          style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        TravelCardWidget(
                          originName: 'Origen',
                          destinationName: 'Destino',
                          formattedDate: 'Vista previa',
                          invitationCode: 'EVT-XXXXXXXX',
                          personName: _companyNameController.text.isNotEmpty
                              ? _companyNameController.text
                              : 'Tu Empresa',
                          personCompany: _companyNameController.text,
                          personPhone: _phoneController.text,
                          personEmail: _emailController.text,
                          personWebsite: _websiteController.text,
                          personLogoUrl: _logoUrl ?? '',
                          personDescription: _descriptionController.text,
                          showPrice: false,
                          stopsCount: 3,
                          totalSeats: 40,
                          availableSeats: 40,
                        ),
                        const SizedBox(height: 24),

                        // Business card image (optional)
                        _buildSectionTitle('Tarjeta de Presentacion (Imagen)'),
                        const SizedBox(height: 8),
                        Text(
                          'Sube una foto de tu tarjeta fisica (opcional)',
                          style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: _saving ? null : () {
                            HapticService.lightImpact();
                            _pickAndUploadBusinessCard();
                          },
                          child: Container(
                            width: double.infinity,
                            height: 180,
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _businessCardUrl != null
                                    ? AppColors.primary.withValues(alpha: 0.3)
                                    : AppColors.border,
                                width: _businessCardUrl != null ? 1.5 : 0.5,
                              ),
                              image: _businessCardUrl != null
                                  ? DecorationImage(
                                      image: NetworkImage(_businessCardUrl!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: _businessCardUrl == null
                                ? Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add_a_photo_outlined,
                                        size: 40,
                                        color: AppColors.textTertiary,
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Sube tu tarjeta de presentacion',
                                        style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Foto o imagen de tu tarjeta',
                                        style: TextStyle(
                                          color: AppColors.textTertiary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  )
                                : Align(
                                    alignment: Alignment.bottomRight,
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: AppColors.card.withValues(alpha: 0.85),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.edit,
                                          size: 18,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textTertiary),
        prefixIcon: Icon(icon, size: 20, color: AppColors.textTertiary),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
        filled: true,
        fillColor: AppColors.cardSecondary,
      ),
    );
  }
}
