import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/tourism_messaging_service.dart';
import '../../services/tourism_event_service.dart';
import '../../services/tourism_invitation_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';
import '../home_screen.dart';

/// Group chat screen for a tourism event.
///
/// Used by drivers, organizers, and passengers to communicate
/// during the event. Supports text, images, announcements, and
/// special "call to bus" messages.
class TourismChatScreen extends StatefulWidget {
  final String eventId;
  final String userRole; // 'driver', 'organizer', 'passenger'
  final String userId;
  final String userName;
  final String? userAvatarUrl;

  const TourismChatScreen({
    super.key,
    required this.eventId,
    required this.userRole,
    required this.userId,
    required this.userName,
    this.userAvatarUrl,
  });

  @override
  State<TourismChatScreen> createState() => _TourismChatScreenState();
}

class _TourismChatScreenState extends State<TourismChatScreen> {
  final TourismMessagingService _messagingService = TourismMessagingService();
  final TourismEventService _eventService = TourismEventService();
  final TourismInvitationService _invitationService = TourismInvitationService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();

  List<TourismMessage> _messages = [];
  TourismMessage? _pinnedAnnouncement;
  Map<String, dynamic>? _event;
  int _participantCount = 0;
  List<Map<String, dynamic>> _participants = [];

  // Target selector: 'all' or specific user ID
  String _targetType = 'all';
  String? _targetUserId;
  String? _targetUserName;

  bool _isLoading = true;
  bool _isSending = false;
  bool _isUploadingImage = false;
  bool _userHasScrolledUp = false;

  @override
  void initState() {
    super.initState();
    ActiveDriverChatTracker.open(widget.eventId);
    _loadData();
    _subscribeToMessages();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    ActiveDriverChatTracker.close(widget.eventId);
    _messagingService.unsubscribe();
    _messageController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.offset;
      // User has scrolled up if they're more than 100 pixels from the bottom
      _userHasScrolledUp = (maxScroll - currentScroll) > 100;
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Load event details
      _event = await _eventService.getEvent(widget.eventId);

      // Load messages
      _messages = await _messagingService.getMessages(widget.eventId);

      // Load pinned announcement
      _pinnedAnnouncement =
          await _messagingService.getPinnedAnnouncement(widget.eventId);

      // Load participant count
      _participantCount =
          await _messagingService.getParticipantCount(widget.eventId);

      // Load participants list for target selector (organizer/driver only)
      if (_canSendSpecialMessages) {
        _participants = await _invitationService.getEventInvitations(widget.eventId);
      }
    } catch (e) {
      debugPrint('Error loading chat data: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  void _subscribeToMessages() {
    _messagingService.subscribeToMessages(widget.eventId, (newMessage) {
      if (mounted) {
        setState(() {
          _messages.add(newMessage);
          // Update pinned announcement if this is a new pinned announcement
          if (newMessage.isPinned &&
              newMessage.messageType == TourismMessageType.announcement) {
            _pinnedAnnouncement = newMessage;
          }
        });

        // Auto-scroll only if user hasn't scrolled up
        if (!_userHasScrolledUp) {
          _scrollToBottom();
        }
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    HapticService.lightImpact();
    setState(() => _isSending = true);
    _messageController.clear();

    final success = await _messagingService.sendMessage(
      eventId: widget.eventId,
      senderId: widget.userId,
      senderType: widget.userRole,
      senderName: widget.userName,
      message: text,
      senderAvatarUrl: widget.userAvatarUrl,
      targetType: _targetType,
      targetUserId: _targetUserId,
    );

    // Reset target to 'all' after sending individual message
    if (_targetType == 'individual') {
      setState(() {
        _targetType = 'all';
        _targetUserId = null;
        _targetUserName = null;
      });
    }

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Error al enviar mensaje'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    if (mounted) {
      setState(() => _isSending = false);
    }
  }

  Future<void> _pickAndSendImage() async {
    HapticService.lightImpact();

    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );

    if (image == null) return;

    setState(() => _isUploadingImage = true);

    try {
      final bytes = await image.readAsBytes();
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${image.name}';

      final imageUrl = await _messagingService.uploadImage(
        imageBytes: bytes,
        fileName: fileName,
        eventId: widget.eventId,
      );

      if (imageUrl != null) {
        await _messagingService.sendImageMessage(
          eventId: widget.eventId,
          senderId: widget.userId,
          senderType: widget.userRole,
          senderName: widget.userName,
          imageUrl: imageUrl,
          senderAvatarUrl: widget.userAvatarUrl,
        );
        HapticService.success();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Error al subir imagen'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error sending image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Error al enviar imagen'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    if (mounted) {
      setState(() => _isUploadingImage = false);
    }
  }

  Future<void> _sendCallToBus() async {
    HapticService.heavyImpact();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Llamar al autobus',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          'Esto enviara una alerta a todos los pasajeros para que regresen al autobus.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.directions_bus, size: 18),
            label: const Text('Enviar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final success = await _messagingService.sendCallToBus(
      eventId: widget.eventId,
      senderId: widget.userId,
      senderType: widget.userRole,
      senderName: widget.userName,
      senderAvatarUrl: widget.userAvatarUrl,
    );

    if (success) {
      HapticService.success();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Alerta enviada'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Error al enviar alerta'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _openImage(String imageUrl) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _FullScreenImageViewer(
          imageUrl: imageUrl,
        ),
      ),
    );
  }

  bool get _canSendSpecialMessages =>
      widget.userRole == 'driver' || widget.userRole == 'organizer';

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.surface,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              if (_pinnedAnnouncement != null) _buildPinnedAnnouncement(),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child:
                            CircularProgressIndicator(color: AppColors.primary),
                      )
                    : _messages.isEmpty
                        ? _buildEmptyState()
                        : _buildMessagesList(),
              ),
              _buildInputSection(keyboardHeight),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final eventTitle = _event?['event_name'] ?? _event?['title'] ?? 'Evento';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border.withOpacity(0.5)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () {
              HapticService.lightImpact();
              Navigator.pop(context);
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Chat del Evento',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$eventTitle - $_participantCount personas',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPinnedAnnouncement() {
    final announcement = _pinnedAnnouncement!;
    final senderName = announcement.senderName ?? 'Organizador';
    final timeStr = DateFormat('h:mm a').format(announcement.createdAt.toLocal());

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.campaign,
              color: AppColors.warning,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ANUNCIO',
                  style: TextStyle(
                    color: AppColors.warning,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  announcement.message ?? '',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '- $senderName $timeStr',
                  style: TextStyle(
                    color: AppColors.textSecondary.withOpacity(0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: AppColors.textTertiary.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'Sin mensajes',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Inicia la conversacion con el grupo',
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    // Filter messages: organizer/driver see all, passengers see 'all' + messages for them
    final filtered = _canSendSpecialMessages
        ? _messages
        : _messages.where((m) =>
            m.targetType == 'all' ||
            m.senderId == widget.userId ||
            m.targetUserId == widget.userId).toList();

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final message = filtered[index];
        return _buildMessageBubble(message);
      },
    );
  }

  Widget _buildMessageBubble(TourismMessage message) {
    final isMe = message.senderId == widget.userId;
    final timeStr = DateFormat('h:mm a').format(message.createdAt.toLocal());

    // Handle special message types
    if (message.messageType == TourismMessageType.callToBus) {
      return _buildCallToBusMessage(message, timeStr);
    }

    if (message.messageType == TourismMessageType.announcement && !message.isPinned) {
      return _buildAnnouncementMessage(message, timeStr);
    }

    // Regular message bubble
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            _buildRoleBadge(message.senderType),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              decoration: BoxDecoration(
                color: isMe
                    ? _getColorForRole(widget.userRole)
                    : AppColors.card,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
                border: isMe
                    ? null
                    : Border.all(color: AppColors.border, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sender name (for others' messages)
                  if (!isMe)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _getRoleLabel(message.senderType),
                            style: TextStyle(
                              color: _getColorForRole(message.senderType),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            message.senderName ?? 'Usuario',
                            style: TextStyle(
                              color: _getColorForRole(message.senderType),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Message content
                  if (message.messageType == TourismMessageType.image &&
                      message.imageUrl != null)
                    _buildImageContent(message.imageUrl!, isMe)
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: Text(
                        message.message ?? '',
                        style: TextStyle(
                          color: isMe ? Colors.white : AppColors.textPrimary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  // Timestamp + individual indicator
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (message.targetType == 'individual') ...[
                          Icon(
                            Icons.person,
                            size: 10,
                            color: isMe ? Colors.white.withOpacity(0.6) : AppColors.warning,
                          ),
                          const SizedBox(width: 3),
                        ],
                        Text(
                          timeStr,
                          style: TextStyle(
                            color: isMe
                                ? Colors.white.withOpacity(0.7)
                                : AppColors.textTertiary,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            _buildRoleBadge(widget.userRole),
          ],
        ],
      ),
    );
  }

  Widget _buildRoleBadge(String role) {
    IconData icon;
    Color color;

    switch (role) {
      case 'driver':
        icon = Icons.directions_bus;
        color = AppColors.success;
        break;
      case 'organizer':
        icon = Icons.business_center;
        color = AppColors.primary;
        break;
      default:
        icon = Icons.person;
        color = AppColors.textSecondary;
    }

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Icon(icon, color: color, size: 14),
    );
  }

  Widget _buildImageContent(String imageUrl, bool isMe) {
    return GestureDetector(
      onTap: () => _openImage(imageUrl),
      child: Container(
        margin: const EdgeInsets.fromLTRB(4, 4, 4, 4),
        constraints: const BoxConstraints(
          maxHeight: 200,
          maxWidth: 250,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            imageUrl,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                height: 150,
                width: 200,
                color: AppColors.card,
                child: const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 2,
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Container(
                height: 100,
                width: 150,
                color: AppColors.card,
                child: const Center(
                  child: Icon(
                    Icons.broken_image,
                    color: AppColors.textTertiary,
                    size: 32,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCallToBusMessage(TourismMessage message, String timeStr) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.warning.withOpacity(0.2),
            AppColors.error.withOpacity(0.15),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: AppColors.warning.withOpacity(0.2),
            blurRadius: 12,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.directions_bus,
                  color: AppColors.warning,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Regresen al autobus!',
                style: TextStyle(
                  color: AppColors.warning,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${message.senderName ?? "Chofer"} - $timeStr',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnnouncementMessage(TourismMessage message, String timeStr) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.campaign,
            color: AppColors.primary.withOpacity(0.8),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.message ?? '',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${message.senderName ?? "Organizador"} - $timeStr',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputSection(double keyboardHeight) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 12 + (keyboardHeight > 0 ? 0 : 8)),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.border.withOpacity(0.5)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Target selector + action buttons (only for driver/organizer)
          if (_canSendSpecialMessages)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  // Target selector chip
                  GestureDetector(
                    onTap: _showTargetSelector,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _targetType == 'all'
                            ? AppColors.primary.withOpacity(0.15)
                            : AppColors.warning.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _targetType == 'all'
                              ? AppColors.primary.withOpacity(0.4)
                              : AppColors.warning.withOpacity(0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _targetType == 'all' ? Icons.groups : Icons.person,
                            size: 16,
                            color: _targetType == 'all' ? AppColors.primary : AppColors.warning,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _targetType == 'all' ? 'Todos' : _targetUserName ?? 'Individual',
                            style: TextStyle(
                              color: _targetType == 'all' ? AppColors.primary : AppColors.warning,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_drop_down,
                            size: 16,
                            color: _targetType == 'all' ? AppColors.primary : AppColors.warning,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Announcement button
                  _buildActionChip(
                    icon: Icons.campaign,
                    label: 'Anuncio',
                    color: AppColors.primary,
                    onTap: _showAnnouncementDialog,
                  ),
                  const SizedBox(width: 8),
                  // Call to bus button
                  _buildActionChip(
                    icon: Icons.directions_bus,
                    label: 'Al autobus',
                    color: AppColors.warning,
                    onTap: _sendCallToBus,
                  ),
                ],
              ),
            ),
          // Message input row
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Photo button
              GestureDetector(
                onTap: _isUploadingImage ? null : _pickAndSendImage,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: _isUploadingImage
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.camera_alt,
                          color: AppColors.textSecondary,
                          size: 20,
                        ),
                ),
              ),
              const SizedBox(width: 8),
              // Text field
              Expanded(
                child: TextField(
                  controller: _messageController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  maxLines: 4,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: 'Mensaje...',
                    hintStyle: const TextStyle(color: AppColors.textTertiary),
                    filled: true,
                    fillColor: AppColors.card,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              // Send button
              GestureDetector(
                onTap: _isSending ? null : _sendMessage,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    boxShadow: AppColors.glowPrimary,
                  ),
                  child: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.send,
                          color: Colors.white,
                          size: 20,
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  void _showTargetSelector() {
    HapticService.lightImpact();
    final accepted = _participants.where((p) => p['status'] == 'accepted').toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            const Text('Enviar a', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            // "Todos" option
            ListTile(
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.groups, color: AppColors.primary, size: 20),
              ),
              title: const Text('Todos', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
              subtitle: const Text('Mensaje visible para todos', style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
              selected: _targetType == 'all',
              selectedTileColor: AppColors.primary.withOpacity(0.08),
              onTap: () {
                setState(() {
                  _targetType = 'all';
                  _targetUserId = null;
                  _targetUserName = null;
                });
                Navigator.pop(ctx);
              },
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            // Individual participants
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: accepted.length,
                itemBuilder: (context, index) {
                  final p = accepted[index];
                  final name = p['invitee_name'] ?? p['invited_name'] ?? 'Pasajero';
                  final odooId = p['invited_user_id'] as String?;
                  return ListTile(
                    leading: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.textSecondary.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    title: Text(name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                    selected: _targetUserId == odooId,
                    selectedTileColor: AppColors.warning.withOpacity(0.08),
                    onTap: () {
                      if (odooId == null) return;
                      setState(() {
                        _targetType = 'individual';
                        _targetUserId = odooId;
                        _targetUserName = name;
                      });
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  void _showAnnouncementDialog() {
    HapticService.lightImpact();
    final controller = TextEditingController();
    bool pin = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.campaign, color: AppColors.primary, size: 22),
              SizedBox(width: 8),
              Text('Nuevo Anuncio', style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                style: const TextStyle(color: AppColors.textPrimary),
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Escribe el anuncio...',
                  hintStyle: const TextStyle(color: AppColors.textTertiary),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Switch(
                    value: pin,
                    activeColor: AppColors.primary,
                    onChanged: (v) => setDialogState(() => pin = v),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Fijar anuncio arriba del chat',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final text = controller.text.trim();
                if (text.isEmpty) return;
                Navigator.pop(ctx);
                final success = await _messagingService.sendAnnouncement(
                  eventId: widget.eventId,
                  senderId: widget.userId,
                  senderType: widget.userRole,
                  senderName: widget.userName,
                  message: text,
                  pin: pin,
                  senderAvatarUrl: widget.userAvatarUrl,
                );
                if (success) {
                  HapticService.success();
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Error al enviar anuncio'),
                      backgroundColor: AppColors.error,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.send, size: 16),
              label: const Text('Enviar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getColorForRole(String role) {
    switch (role) {
      case 'driver':
        return AppColors.success;
      case 'organizer':
        return AppColors.primary;
      default:
        return AppColors.textSecondary;
    }
  }

  String _getRoleLabel(String role) {
    switch (role) {
      case 'driver':
        return '[Chofer]';
      case 'organizer':
        return '[Organizador]';
      default:
        return '[Pasajero]';
    }
  }
}

/// Full screen image viewer with zoom and share capabilities.
class _FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;

  const _FullScreenImageViewer({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _shareImage(context),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            },
            errorBuilder: (context, error, stackTrace) => const Center(
              child: Icon(
                Icons.broken_image,
                color: AppColors.textTertiary,
                size: 64,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _shareImage(BuildContext context) async {
    try {
      await Share.share(imageUrl, subject: 'Foto del evento');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Error al compartir'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
