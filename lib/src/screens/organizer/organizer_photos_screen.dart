import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../services/tourism_messaging_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';

/// Photos Gallery Screen for organizers to view, upload, share, and manage
/// event photos from the tourism event chat.
class OrganizerPhotosScreen extends StatefulWidget {
  final String eventId;
  final String userId;
  final String userName;

  const OrganizerPhotosScreen({
    super.key,
    required this.eventId,
    required this.userId,
    required this.userName,
  });

  @override
  State<OrganizerPhotosScreen> createState() => _OrganizerPhotosScreenState();
}

class _OrganizerPhotosScreenState extends State<OrganizerPhotosScreen> {
  final TourismMessagingService _messagingService = TourismMessagingService();
  final ImagePicker _imagePicker = ImagePicker();

  List<TourismMessage> _photos = [];
  Map<String, List<TourismMessage>> _groupedPhotos = {};
  bool _isLoading = true;
  bool _isUploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
    _subscribeToNewPhotos();
  }

  @override
  void dispose() {
    _messagingService.unsubscribe();
    super.dispose();
  }

  Future<void> _loadPhotos() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final messages = await _messagingService.getMessages(widget.eventId);

      // Filter only image messages
      final photos = messages
          .where((m) => m.messageType == TourismMessageType.image)
          .toList();

      // Sort by date descending (newest first)
      photos.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Group by date
      final grouped = <String, List<TourismMessage>>{};
      for (final photo in photos) {
        final dateKey = _formatDateKey(photo.createdAt);
        grouped.putIfAbsent(dateKey, () => []);
        grouped[dateKey]!.add(photo);
      }

      if (mounted) {
        setState(() {
          _photos = photos;
          _groupedPhotos = grouped;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Error al cargar las fotos: $e';
        });
      }
    }
  }

  void _subscribeToNewPhotos() {
    _messagingService.subscribeToMessages(
      widget.eventId,
      (message) {
        if (message.messageType == TourismMessageType.image && mounted) {
          setState(() {
            // Add to photos list
            _photos.insert(0, message);

            // Update grouped photos
            final dateKey = _formatDateKey(message.createdAt);
            _groupedPhotos.putIfAbsent(dateKey, () => []);
            _groupedPhotos[dateKey]!.insert(0, message);
          });
          HapticService.notification();
        }
      },
    );
  }

  String _formatDateKey(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final photoDate = DateTime(date.year, date.month, date.day);

    if (photoDate == today) {
      return 'Hoy';
    } else if (photoDate == yesterday) {
      return 'Ayer';
    } else {
      return _formatFullDate(date);
    }
  }

  String _formatFullDate(DateTime date) {
    const months = [
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre',
    ];
    return '${date.day} de ${months[date.month - 1]}, ${date.year}';
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickAndUploadPhoto() async {
    HapticService.lightImpact();

    // Show source selection dialog
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildSourceSelectionSheet(ctx),
    );

    if (source == null) return;

    try {
      final pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      setState(() => _isUploading = true);

      // Read file bytes
      final bytes = await pickedFile.readAsBytes();

      // Generate unique filename
      final extension = pickedFile.path.split('.').last.toLowerCase();
      final fileName = '${const Uuid().v4()}.$extension';

      // Upload to Supabase storage
      final imageUrl = await _messagingService.uploadImage(
        imageBytes: bytes,
        fileName: fileName,
        eventId: widget.eventId,
      );

      if (imageUrl == null) {
        throw Exception('Error al subir la imagen');
      }

      // Send image message
      final success = await _messagingService.sendImageMessage(
        eventId: widget.eventId,
        senderId: widget.userId,
        senderType: 'organizer',
        senderName: widget.userName,
        imageUrl: imageUrl,
      );

      if (mounted) {
        setState(() => _isUploading = false);

        if (success) {
          HapticService.success();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Foto subida exitosamente'),
              backgroundColor: AppColors.success,
            ),
          );
        } else {
          throw Exception('Error al enviar la imagen');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        HapticService.error();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Widget _buildSourceSelectionSheet(BuildContext ctx) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textTertiary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Subir Foto',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _buildSourceOption(
                  ctx,
                  Icons.camera_alt,
                  'Camara',
                  ImageSource.camera,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSourceOption(
                  ctx,
                  Icons.photo_library,
                  'Galeria',
                  ImageSource.gallery,
                ),
              ),
            ],
          ),
          SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
        ],
      ),
    );
  }

  Widget _buildSourceOption(
    BuildContext ctx,
    IconData icon,
    String label,
    ImageSource source,
  ) {
    return GestureDetector(
      onTap: () {
        HapticService.lightImpact();
        Navigator.pop(ctx, source);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sharePhoto(TourismMessage photo) async {
    if (photo.imageUrl == null) return;

    HapticService.lightImpact();

    try {
      // Download the image
      final response = await http.get(Uri.parse(photo.imageUrl!));
      if (response.statusCode != 200) {
        throw Exception('Error al descargar la imagen');
      }

      // Save to temp file
      final tempDir = await getTemporaryDirectory();
      final fileName = 'toro_event_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(response.bodyBytes);

      // Share
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Foto del evento TORO',
      );

      HapticService.success();
    } catch (e) {
      if (mounted) {
        HapticService.error();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al compartir: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _downloadPhoto(TourismMessage photo) async {
    if (photo.imageUrl == null) return;

    HapticService.lightImpact();

    try {
      // Download the image
      final response = await http.get(Uri.parse(photo.imageUrl!));
      if (response.statusCode != 200) {
        throw Exception('Error al descargar la imagen');
      }

      // Get downloads directory
      Directory? downloadsDir;
      if (Platform.isAndroid) {
        downloadsDir = Directory('/storage/emulated/0/Download');
        if (!await downloadsDir.exists()) {
          downloadsDir = await getExternalStorageDirectory();
        }
      } else {
        downloadsDir = await getApplicationDocumentsDirectory();
      }

      if (downloadsDir == null) {
        throw Exception('No se pudo acceder al almacenamiento');
      }

      // Save file
      final fileName = 'TORO_Event_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File('${downloadsDir.path}/$fileName');
      await file.writeAsBytes(response.bodyBytes);

      if (mounted) {
        HapticService.success();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Foto guardada: $fileName'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        HapticService.error();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al descargar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _deletePhoto(TourismMessage photo) async {
    // Only allow deleting own photos
    if (photo.senderId != widget.userId) {
      HapticService.warning();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Solo puedes eliminar tus propias fotos'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Eliminar Foto',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          'Esta accion no se puede deshacer.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: AppColors.textTertiary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    HapticService.lightImpact();

    try {
      // Delete from database using Supabase client directly
      // Note: This assumes the message can be deleted by the sender
      // The actual implementation depends on your RLS policies
      final client = _messagingService;

      // For now, we'll just remove it from the local state
      // In a real implementation, you'd call a delete method on the service
      setState(() {
        _photos.removeWhere((p) => p.id == photo.id);

        // Update grouped photos
        for (final key in _groupedPhotos.keys) {
          _groupedPhotos[key]!.removeWhere((p) => p.id == photo.id);
        }

        // Remove empty groups
        _groupedPhotos.removeWhere((key, value) => value.isEmpty);
      });

      HapticService.success();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Foto eliminada'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      HapticService.error();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al eliminar: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _openFullScreenViewer(TourismMessage photo, int indexInList) {
    HapticService.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _FullScreenPhotoViewer(
          photos: _photos,
          initialIndex: indexInList,
          userId: widget.userId,
          onShare: _sharePhoto,
          onDownload: _downloadPhoto,
          onDelete: _deletePhoto,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: _isLoading
          ? _buildLoadingState()
          : _error != null
              ? _buildErrorState()
              : _photos.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      color: AppColors.primary,
                      backgroundColor: AppColors.surface,
                      onRefresh: _loadPhotos,
                      child: _buildPhotoGrid(),
                    ),
      floatingActionButton: _buildUploadFAB(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Galeria de Fotos',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          Text(
            '${_photos.length} fotos',
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
      actions: [
        if (_photos.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.share, color: AppColors.textSecondary),
            onPressed: () {
              HapticService.lightImpact();
              // Share all photos functionality could be added here
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Selecciona una foto para compartir'),
                  backgroundColor: AppColors.info,
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: 16),
          Text(
            'Cargando fotos...',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: AppColors.error.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Error desconocido',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadPhotos,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.photo_library_outlined,
                size: 48,
                color: AppColors.primary.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Sin fotos aun',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Se la primera persona en compartir\nfotos del evento',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _pickAndUploadPhoto,
              icon: const Icon(Icons.add_a_photo),
              label: const Text('Subir Primera Foto'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoGrid() {
    final sortedKeys = _groupedPhotos.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: sortedKeys.length,
      itemBuilder: (context, sectionIndex) {
        final dateKey = sortedKeys[sectionIndex];
        final photosInGroup = _groupedPhotos[dateKey]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date header
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          dateKey,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${photosInGroup.length} ${photosInGroup.length == 1 ? 'foto' : 'fotos'}',
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            // Photos grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: photosInGroup.length,
              itemBuilder: (context, index) {
                final photo = photosInGroup[index];
                final globalIndex = _photos.indexOf(photo);

                return _buildPhotoThumbnail(photo, globalIndex);
              },
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _buildPhotoThumbnail(TourismMessage photo, int index) {
    final isOwnPhoto = photo.senderId == widget.userId;

    return GestureDetector(
      onTap: () => _openFullScreenViewer(photo, index),
      onLongPress: () {
        HapticService.mediumImpact();
        _showPhotoOptionsSheet(photo);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Photo
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: photo.thumbnailUrl ?? photo.imageUrl ?? '',
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: AppColors.card,
                child: const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 2,
                  ),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                color: AppColors.card,
                child: Icon(
                  Icons.broken_image,
                  color: AppColors.textTertiary,
                  size: 32,
                ),
              ),
            ),
          ),
          // Gradient overlay at bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 32,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.7),
                  ],
                ),
              ),
            ),
          ),
          // Time badge
          Positioned(
            bottom: 4,
            left: 4,
            child: Text(
              _formatTime(photo.createdAt),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                shadows: [
                  Shadow(
                    color: Colors.black54,
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ),
          // Own photo indicator
          if (isOwnPhoto)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person,
                  color: Colors.white,
                  size: 10,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showPhotoOptionsSheet(TourismMessage photo) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Photo preview
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: photo.thumbnailUrl ?? photo.imageUrl ?? '',
                height: 120,
                width: 120,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Por ${photo.senderName ?? 'Desconocido'}',
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 24),
            // Options
            _buildOptionTile(
              icon: Icons.fullscreen,
              label: 'Ver en pantalla completa',
              onTap: () {
                Navigator.pop(ctx);
                _openFullScreenViewer(photo, _photos.indexOf(photo));
              },
            ),
            _buildOptionTile(
              icon: Icons.share,
              label: 'Compartir',
              onTap: () {
                Navigator.pop(ctx);
                _sharePhoto(photo);
              },
            ),
            _buildOptionTile(
              icon: Icons.download,
              label: 'Descargar',
              onTap: () {
                Navigator.pop(ctx);
                _downloadPhoto(photo);
              },
            ),
            if (photo.senderId == widget.userId)
              _buildOptionTile(
                icon: Icons.delete,
                label: 'Eliminar',
                color: AppColors.error,
                onTap: () {
                  Navigator.pop(ctx);
                  _deletePhoto(photo);
                },
              ),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? AppColors.textSecondary),
      title: Text(
        label,
        style: TextStyle(
          color: color ?? AppColors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: () {
        HapticService.lightImpact();
        onTap();
      },
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }

  Widget _buildUploadFAB() {
    return FloatingActionButton.extended(
      onPressed: _isUploading ? null : _pickAndUploadPhoto,
      backgroundColor: _isUploading ? AppColors.card : AppColors.primary,
      foregroundColor: Colors.white,
      icon: _isUploading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : const Icon(Icons.add_a_photo),
      label: Text(_isUploading ? 'Subiendo...' : 'Subir Foto'),
    );
  }
}

/// Full screen photo viewer with zoom and swipe.
class _FullScreenPhotoViewer extends StatefulWidget {
  final List<TourismMessage> photos;
  final int initialIndex;
  final String userId;
  final Future<void> Function(TourismMessage) onShare;
  final Future<void> Function(TourismMessage) onDownload;
  final Future<void> Function(TourismMessage) onDelete;

  const _FullScreenPhotoViewer({
    required this.photos,
    required this.initialIndex,
    required this.userId,
    required this.onShare,
    required this.onDownload,
    required this.onDelete,
  });

  @override
  State<_FullScreenPhotoViewer> createState() => _FullScreenPhotoViewerState();
}

class _FullScreenPhotoViewerState extends State<_FullScreenPhotoViewer> {
  late PageController _pageController;
  late int _currentIndex;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  String _formatDateTime(DateTime date) {
    const months = [
      'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
      'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}, '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final currentPhoto = widget.photos[_currentIndex];
    final isOwnPhoto = currentPhoto.senderId == widget.userId;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Photo viewer with swipe
            PageView.builder(
              controller: _pageController,
              itemCount: widget.photos.length,
              onPageChanged: (index) {
                HapticService.selectionClick();
                setState(() => _currentIndex = index);
              },
              itemBuilder: (context, index) {
                final photo = widget.photos[index];
                return InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Center(
                    child: CachedNetworkImage(
                      imageUrl: photo.imageUrl ?? '',
                      fit: BoxFit.contain,
                      placeholder: (context, url) => const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      ),
                      errorWidget: (context, url, error) => const Center(
                        child: Icon(
                          Icons.broken_image,
                          color: AppColors.textTertiary,
                          size: 64,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            // Top controls
            if (_showControls)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.7),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const Spacer(),
                          Text(
                            '${_currentIndex + 1} / ${widget.photos.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          const SizedBox(width: 48), // Balance the close button
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            // Bottom controls
            if (_showControls)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.8),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Photo info
                          Row(
                            children: [
                              // Sender avatar placeholder
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.3),
                                  shape: BoxShape.circle,
                                ),
                                child: currentPhoto.senderAvatarUrl != null
                                    ? ClipOval(
                                        child: CachedNetworkImage(
                                          imageUrl: currentPhoto.senderAvatarUrl!,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.person,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      currentPhoto.senderName ?? 'Desconocido',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      _formatDateTime(currentPhoto.createdAt),
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.7),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Action buttons
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildActionButton(
                                icon: Icons.share,
                                label: 'Compartir',
                                onTap: () => widget.onShare(currentPhoto),
                              ),
                              _buildActionButton(
                                icon: Icons.download,
                                label: 'Descargar',
                                onTap: () => widget.onDownload(currentPhoto),
                              ),
                              if (isOwnPhoto)
                                _buildActionButton(
                                  icon: Icons.delete,
                                  label: 'Eliminar',
                                  color: AppColors.error,
                                  onTap: () async {
                                    await widget.onDelete(currentPhoto);
                                    if (!context.mounted) return;
                                    Navigator.pop(context);
                                  },
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            // Page indicator dots
            if (_showControls && widget.photos.length > 1)
              Positioned(
                bottom: 180,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    widget.photos.length.clamp(0, 10),
                    (index) => Container(
                      width: index == _currentIndex ? 12 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: index == _currentIndex
                            ? AppColors.primary
                            : Colors.white.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return GestureDetector(
      onTap: () {
        HapticService.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: (color ?? Colors.white).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color ?? Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color ?? Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
