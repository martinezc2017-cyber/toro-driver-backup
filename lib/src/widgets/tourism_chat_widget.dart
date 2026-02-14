import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/tourism_messaging_service.dart';
import '../services/tourism_invitation_service.dart';
import '../screens/home_screen.dart';
import '../utils/app_colors.dart';
import '../utils/haptic_service.dart';

/// Embeddable compact chat widget for the organizer event dashboard.
///
/// Displays messages in a timeline format with real-time updates.
/// Can be used inline (collapsible section) or inside a bottom sheet.
///
/// Features:
/// - Public/private message toggle
/// - Organizer and Driver role badges
/// - Lock icon on private messages
/// - Real-time subscription to new messages
/// - Unread message badge count
/// - Announcement and call-to-bus shortcuts
class TourismChatWidget extends StatefulWidget {
  final String eventId;
  final String userId;
  final String userRole; // 'organizer', 'driver', 'passenger'
  final String userName;
  final String? userAvatarUrl;

  /// Maximum height when embedded. Use double.infinity for full expansion.
  final double maxHeight;

  /// Whether to show the header bar (with title, participant count).
  final bool showHeader;

  /// Callback when unread count changes.
  final ValueChanged<int>? onUnreadCountChanged;

  const TourismChatWidget({
    super.key,
    required this.eventId,
    required this.userId,
    required this.userRole,
    required this.userName,
    this.userAvatarUrl,
    this.maxHeight = 450,
    this.showHeader = true,
    this.onUnreadCountChanged,
  });

  /// Show this widget as a bottom sheet.
  static Future<void> showAsBottomSheet(
    BuildContext context, {
    required String eventId,
    required String userId,
    required String userRole,
    required String userName,
    String? userAvatarUrl,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final screenHeight = MediaQuery.of(ctx).size.height;
        final keyboardHeight = MediaQuery.of(ctx).viewInsets.bottom;
        final sheetHeight = keyboardHeight > 0
            ? screenHeight - keyboardHeight - 50
            : screenHeight * 0.78;

        return Padding(
          padding: EdgeInsets.only(bottom: keyboardHeight),
          child: Container(
            height: sheetHeight,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // Drag handle
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: TourismChatWidget(
                    eventId: eventId,
                    userId: userId,
                    userRole: userRole,
                    userName: userName,
                    userAvatarUrl: userAvatarUrl,
                    maxHeight: double.infinity,
                    showHeader: true,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  State<TourismChatWidget> createState() => TourismChatWidgetState();
}

class TourismChatWidgetState extends State<TourismChatWidget> {
  final TourismMessagingService _messagingService = TourismMessagingService();
  final TourismInvitationService _invitationService =
      TourismInvitationService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<TourismMessage> _messages = [];
  TourismMessage? _pinnedAnnouncement;
  List<Map<String, dynamic>> _participants = [];
  int _participantCount = 0;

  bool _isLoading = true;
  bool _isSending = false;
  bool _userHasScrolledUp = false;

  // Public/private toggle
  bool _isPrivateMode = false;
  String? _privateTargetUserId;
  String? _privateTargetUserName;

  // Unread tracking
  int _unreadCount = 0;

  /// Publicly accessible unread count for external badge display.
  int get unreadCount => _unreadCount;

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
      _userHasScrolledUp = (maxScroll - currentScroll) > 100;
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      _messages = await _messagingService.getMessages(widget.eventId);
      _pinnedAnnouncement =
          await _messagingService.getPinnedAnnouncement(widget.eventId);
      _participantCount =
          await _messagingService.getParticipantCount(widget.eventId);

      // Load participants for private message selector (organizer/driver only)
      if (_canSendSpecialMessages) {
        _participants =
            await _invitationService.getEventInvitations(widget.eventId);
      }

      _calculateUnread();
    } catch (e) {
      debugPrint('TOURISM_CHAT_WIDGET -> Error loading data: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  void _subscribeToMessages() {
    _messagingService.subscribeToMessages(widget.eventId, (newMessage) {
      if (!mounted) return;
      setState(() {
        _messages.add(newMessage);
        if (newMessage.isPinned &&
            newMessage.messageType == TourismMessageType.announcement) {
          _pinnedAnnouncement = newMessage;
        }
        // Count as unread if not from me
        if (newMessage.senderId != widget.userId) {
          _unreadCount++;
          widget.onUnreadCountChanged?.call(_unreadCount);
        }
      });

      if (!_userHasScrolledUp) {
        _scrollToBottom();
      }
    });
  }

  void _calculateUnread() {
    _unreadCount = _messages
        .where((m) =>
            m.senderId != widget.userId && !m.readBy.contains(widget.userId))
        .length;
    widget.onUnreadCountChanged?.call(_unreadCount);
  }

  /// Mark all messages as read. Call this when the chat becomes visible.
  void markAllAsRead() {
    for (final msg in _messages) {
      if (!msg.readBy.contains(widget.userId)) {
        _messagingService.markAsRead(msg.id, widget.userId);
      }
    }
    setState(() => _unreadCount = 0);
    widget.onUnreadCountChanged?.call(0);
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

  bool get _canSendSpecialMessages =>
      widget.userRole == 'driver' || widget.userRole == 'organizer';

  // ===========================================================================
  // SEND ACTIONS
  // ===========================================================================

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
      targetType: _isPrivateMode ? 'individual' : 'all',
      targetUserId: _isPrivateMode ? _privateTargetUserId : null,
    );

    // Reset private mode after sending
    if (_isPrivateMode) {
      setState(() {
        _isPrivateMode = false;
        _privateTargetUserId = null;
        _privateTargetUserName = null;
      });
    }

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al enviar mensaje'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    if (mounted) setState(() => _isSending = false);
  }

  Future<void> _sendCallToBus() async {
    HapticService.heavyImpact();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Llamar al autobus',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          'Se enviara una alerta a todos los pasajeros para que regresen al autobus.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.directions_bus, size: 18),
            label: const Text('Enviar Alerta'),
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
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al enviar alerta'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.campaign, color: AppColors.primary, size: 22),
              SizedBox(width: 8),
              Text('Nuevo Anuncio',
                  style:
                      TextStyle(color: AppColors.textPrimary, fontSize: 16)),
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
                    borderSide: const BorderSide(color: AppColors.border),
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
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
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
                await _messagingService.sendAnnouncement(
                  eventId: widget.eventId,
                  senderId: widget.userId,
                  senderType: widget.userRole,
                  senderName: widget.userName,
                  message: text,
                  pin: pin,
                  senderAvatarUrl: widget.userAvatarUrl,
                );
                HapticService.success();
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

  void _showPrivateTargetSelector() {
    HapticService.lightImpact();
    final accepted =
        _participants.where((p) => p['status'] == 'accepted').toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.5),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            const Text('Enviar mensaje privado a',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Solo esta persona vera el mensaje',
                style: TextStyle(
                    color: AppColors.textTertiary, fontSize: 12)),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: accepted.length,
                itemBuilder: (context, index) {
                  final p = accepted[index];
                  final name = p['invitee_name'] ??
                      p['invited_name'] ??
                      'Pasajero';
                  final odooId = p['invited_user_id'] as String?;
                  return ListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.textSecondary.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    title: Text(name,
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 14)),
                    trailing: const Icon(Icons.lock_outline,
                        size: 16, color: AppColors.warning),
                    onTap: () {
                      if (odooId == null) return;
                      setState(() {
                        _isPrivateMode = true;
                        _privateTargetUserId = odooId;
                        _privateTargetUserName = name;
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

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: widget.maxHeight == double.infinity
          ? null
          : BoxConstraints(maxHeight: widget.maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showHeader) _buildHeader(),
          if (_pinnedAnnouncement != null) _buildPinnedBanner(),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : _messages.isEmpty
                    ? _buildEmptyState()
                    : _buildMessagesList(),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
            bottom: BorderSide(color: AppColors.border.withOpacity(0.5))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.chat, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Chat del Evento',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '$_participantCount participantes',
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // Unread badge
          if (_unreadCount > 0)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _unreadCount > 99 ? '99+' : '$_unreadCount',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Pinned Announcement Banner
  // ---------------------------------------------------------------------------
  Widget _buildPinnedBanner() {
    final ann = _pinnedAnnouncement!;
    final timeStr =
        DateFormat('h:mm a').format(ann.createdAt.toLocal());
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.campaign, color: AppColors.warning, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ANUNCIO FIJADO',
                    style: TextStyle(
                        color: AppColors.warning,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text(
                  ann.message ?? '',
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${ann.senderName ?? "Organizador"} - $timeStr',
                  style: TextStyle(
                      color: AppColors.textTertiary.withOpacity(0.7),
                      fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Empty State
  // ---------------------------------------------------------------------------
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline,
              size: 48, color: AppColors.textTertiary.withOpacity(0.4)),
          const SizedBox(height: 12),
          const Text('Sin mensajes',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Inicia la conversacion con el grupo',
              style:
                  TextStyle(color: AppColors.textTertiary, fontSize: 13)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Messages List
  // ---------------------------------------------------------------------------
  Widget _buildMessagesList() {
    // Filter: organizer/driver see all, passengers see 'all' + messages for them
    final filtered = _canSendSpecialMessages
        ? _messages
        : _messages
            .where((m) =>
                m.targetType == 'all' ||
                m.senderId == widget.userId ||
                m.targetUserId == widget.userId)
            .toList();

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      itemCount: filtered.length,
      itemBuilder: (context, index) => _buildMessageBubble(filtered[index]),
    );
  }

  Widget _buildMessageBubble(TourismMessage message) {
    final isMe = message.senderId == widget.userId;
    final timeStr =
        DateFormat('h:mm a').format(message.createdAt.toLocal());
    final isPrivate = message.targetType == 'individual';

    // Special: call-to-bus
    if (message.messageType == TourismMessageType.callToBus) {
      return _buildCallToBusBubble(message, timeStr);
    }

    // Special: announcement (not pinned -- pinned shows at top)
    if (message.messageType == TourismMessageType.announcement &&
        !message.isPinned) {
      return _buildAnnouncementBubble(message, timeStr);
    }

    // Regular / private message
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            _buildRoleBadge(message.senderType),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.70,
              ),
              decoration: BoxDecoration(
                color: isMe
                    ? _roleColor(widget.userRole)
                    : isPrivate
                        ? AppColors.card.withOpacity(0.9)
                        : AppColors.card,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(isMe ? 14 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 14),
                ),
                border: isPrivate
                    ? Border.all(
                        color: AppColors.warning.withOpacity(0.5), width: 1)
                    : isMe
                        ? null
                        : Border.all(
                            color: AppColors.border, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sender info (other people's messages)
                  if (!isMe)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _roleLabel(message.senderType),
                            style: TextStyle(
                              color: _roleColor(message.senderType),
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              message.senderName ?? 'Usuario',
                              style: TextStyle(
                                color: _roleColor(message.senderType),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Message text
                  if (message.messageType == TourismMessageType.image &&
                      message.imageUrl != null)
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          message.imageUrl!,
                          height: 160,
                          width: 220,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            height: 80,
                            width: 120,
                            color: AppColors.card,
                            child: const Icon(Icons.broken_image,
                                color: AppColors.textTertiary),
                          ),
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
                      child: Text(
                        message.message ?? '',
                        style: TextStyle(
                          color:
                              isMe ? Colors.white : AppColors.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  // Timestamp + private indicator
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isPrivate) ...[
                          Icon(
                            Icons.lock,
                            size: 10,
                            color: isMe
                                ? Colors.white.withOpacity(0.6)
                                : AppColors.warning,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'Privado',
                            style: TextStyle(
                              color: isMe
                                  ? Colors.white.withOpacity(0.6)
                                  : AppColors.warning,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 6),
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
            const SizedBox(width: 6),
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
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Icon(icon, color: color, size: 13),
    );
  }

  Widget _buildCallToBusBubble(TourismMessage message, String timeStr) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.warning.withOpacity(0.18),
            AppColors.error.withOpacity(0.12),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withOpacity(0.45)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.directions_bus,
                    color: AppColors.warning, size: 22),
              ),
              const SizedBox(width: 10),
              const Text(
                'Regresen al autobus!',
                style: TextStyle(
                  color: AppColors.warning,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${message.senderName ?? "Chofer"} - $timeStr',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildAnnouncementBubble(TourismMessage message, String timeStr) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.campaign,
              color: AppColors.primary.withOpacity(0.8), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message.message ?? '',
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 13)),
                const SizedBox(height: 3),
                Text(
                  '${message.senderName ?? "Organizador"} - $timeStr',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Input Area
  // ---------------------------------------------------------------------------
  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border:
            Border(top: BorderSide(color: AppColors.border.withOpacity(0.5))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Private mode indicator
          if (_isPrivateMode)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: AppColors.warning.withOpacity(0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock,
                      size: 14, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Mensaje privado para $_privateTargetUserName',
                      style: const TextStyle(
                          color: AppColors.warning,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() {
                      _isPrivateMode = false;
                      _privateTargetUserId = null;
                      _privateTargetUserName = null;
                    }),
                    child: const Icon(Icons.close,
                        size: 16, color: AppColors.warning),
                  ),
                ],
              ),
            ),
          // Action chips (organizer/driver only)
          if (_canSendSpecialMessages)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  _buildChip(
                    icon: Icons.lock_outline,
                    label: 'Privado',
                    color: AppColors.warning,
                    onTap: _showPrivateTargetSelector,
                  ),
                  const SizedBox(width: 6),
                  _buildChip(
                    icon: Icons.campaign,
                    label: 'Anuncio',
                    color: AppColors.primary,
                    onTap: _showAnnouncementDialog,
                  ),
                  const SizedBox(width: 6),
                  _buildChip(
                    icon: Icons.directions_bus,
                    label: 'Al autobus',
                    color: AppColors.warning,
                    onTap: _sendCallToBus,
                  ),
                ],
              ),
            ),
          // Text input + send button
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 14),
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: _isPrivateMode
                        ? 'Mensaje privado...'
                        : 'Mensaje...',
                    hintStyle:
                        const TextStyle(color: AppColors.textTertiary),
                    filled: true,
                    fillColor: AppColors.card,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide(
                        color: _isPrivateMode
                            ? AppColors.warning.withOpacity(0.5)
                            : AppColors.border,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide(
                        color: _isPrivateMode
                            ? AppColors.warning
                            : AppColors.primary,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _isSending ? null : _sendMessage,
                child: Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: _isPrivateMode
                        ? AppColors.warning
                        : AppColors.primary,
                    shape: BoxShape.circle,
                    boxShadow: _isPrivateMode
                        ? AppColors.glowWarning
                        : AppColors.glowPrimary,
                  ),
                  child: _isSending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Icon(
                          _isPrivateMode ? Icons.lock : Icons.send,
                          color: Colors.white,
                          size: 18,
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  Color _roleColor(String role) {
    switch (role) {
      case 'driver':
        return AppColors.success;
      case 'organizer':
        return AppColors.primary;
      default:
        return AppColors.textSecondary;
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'driver':
        return 'Chofer';
      case 'organizer':
        return 'Organizador';
      default:
        return 'Pasajero';
    }
  }
}

// =============================================================================
// Standalone helper: Chat FAB with badge
// =============================================================================

/// Floating action button that opens the chat widget as a bottom sheet.
/// Displays an unread-message badge count.
class TourismChatFab extends StatefulWidget {
  final String eventId;
  final String userId;
  final String userRole;
  final String userName;
  final String? userAvatarUrl;

  const TourismChatFab({
    super.key,
    required this.eventId,
    required this.userId,
    required this.userRole,
    required this.userName,
    this.userAvatarUrl,
  });

  @override
  State<TourismChatFab> createState() => _TourismChatFabState();
}

class _TourismChatFabState extends State<TourismChatFab> {
  final TourismMessagingService _messagingService = TourismMessagingService();
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUnread();
    _subscribeToMessages();
  }

  @override
  void dispose() {
    _messagingService.unsubscribe();
    super.dispose();
  }

  Future<void> _loadUnread() async {
    try {
      final messages =
          await _messagingService.getMessages(widget.eventId);
      final unread = messages
          .where((m) =>
              m.senderId != widget.userId &&
              !m.readBy.contains(widget.userId))
          .length;
      if (mounted) setState(() => _unreadCount = unread);
    } catch (_) {}
  }

  void _subscribeToMessages() {
    _messagingService.subscribeToMessages(widget.eventId, (newMessage) {
      if (!mounted) return;
      if (newMessage.senderId != widget.userId) {
        setState(() => _unreadCount++);
      }
    });
  }

  void _openChat() {
    HapticService.lightImpact();
    setState(() => _unreadCount = 0);
    TourismChatWidget.showAsBottomSheet(
      context,
      eventId: widget.eventId,
      userId: widget.userId,
      userRole: widget.userRole,
      userName: widget.userName,
      userAvatarUrl: widget.userAvatarUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        FloatingActionButton(
          heroTag: 'tourism_chat_fab',
          onPressed: _openChat,
          backgroundColor: AppColors.primary,
          child: const Icon(Icons.chat, color: Colors.white, size: 24),
        ),
        if (_unreadCount > 0)
          Positioned(
            right: -2,
            top: -4,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: AppColors.background, width: 1.5),
              ),
              child: Text(
                _unreadCount > 99 ? '99+' : '$_unreadCount',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
    );
  }
}
