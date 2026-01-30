import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/message_model.dart';
import '../models/ride_model.dart';
import '../providers/ride_provider.dart';
import '../providers/driver_provider.dart';
import '../providers/location_provider.dart';
import '../services/chat_service.dart';
import '../services/report_service.dart';
import '../utils/app_colors.dart';
import '../utils/haptic_service.dart';
import '../widgets/custom_keyboard.dart';

/// Real-time Chat Screen - Driver to Rider messaging during active ride
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String? _conversationId;
  List<MessageModel> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  StreamSubscription? _messageSubscription;

  // Custom keyboard state
  bool _showTextKeyboard = false;
  late FocusNode _keyboardListenerFocus;

  @override
  void initState() {
    super.initState();
    _keyboardListenerFocus = FocusNode();
    _messageController.addListener(() => setState(() {}));
    _initializeChat();
  }

  Future<void> _initializeChat() async {
    final rideProvider = Provider.of<RideProvider>(context, listen: false);
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    final activeRide = rideProvider.activeRide;
    final driver = driverProvider.driver;

    if (activeRide == null || driver == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // Get or create conversation for this ride
      _conversationId = await _chatService.getOrCreateConversation(
        activeRide.id,
        driver.id,
        activeRide.passengerId,
      );

      // Load existing messages
      _messages = await _chatService.getMessages(_conversationId!);

      // Subscribe to real-time messages
      _messageSubscription = _chatService.streamMessages(_conversationId!).listen(
        (messages) {
          setState(() => _messages = messages);
          _scrollToBottom();
          // Mark as read
          _chatService.markConversationAsRead(_conversationId!, driver.id);
        },
      );

      setState(() => _isLoading = false);
      _scrollToBottom();
    } catch (e) {
      //Chat init error: $e');
      setState(() => _isLoading = false);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _conversationId == null || _isSending) return;

    final rideProvider = Provider.of<RideProvider>(context, listen: false);
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    final activeRide = rideProvider.activeRide;
    final driver = driverProvider.driver;

    if (activeRide == null || driver == null) return;

    setState(() => _isSending = true);
    _messageController.clear();
    HapticService.lightImpact();

    try {
      await _chatService.sendMessage(
        conversationId: _conversationId!,
        senderId: driver.id,
        receiverId: activeRide.passengerId,
        content: text,
      );
    } catch (e) {
      //Send message error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error sending message')),
        );
      }
    }

    if (mounted) setState(() => _isSending = false);
  }

  Future<void> _sendQuickResponse(QuickResponseType type) async {
    if (_conversationId == null) return;

    final rideProvider = Provider.of<RideProvider>(context, listen: false);
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    final activeRide = rideProvider.activeRide;
    final driver = driverProvider.driver;

    if (activeRide == null || driver == null) return;

    HapticService.lightImpact();

    try {
      await _chatService.sendQuickResponse(
        conversationId: _conversationId!,
        senderId: driver.id,
        receiverId: activeRide.passengerId,
        responseType: type,
      );
    } catch (e) {
      //Quick response error: $e');
    }
  }

  Future<void> _sendLocation() async {
    if (_conversationId == null) return;

    final rideProvider = Provider.of<RideProvider>(context, listen: false);
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);
    final activeRide = rideProvider.activeRide;
    final driver = driverProvider.driver;

    if (activeRide == null || driver == null) return;

    HapticService.mediumImpact();

    // Get real location from LocationProvider
    final position = locationProvider.currentPosition ??
        await locationProvider.getCurrentPosition();

    if (position == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get location')),
        );
      }
      return;
    }

    try {
      await _chatService.sendLocationMessage(
        conversationId: _conversationId!,
        senderId: driver.id,
        receiverId: activeRide.passengerId,
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (e) {
      //Send location error: $e');
    }
  }

  Future<void> _callPassenger(String? phone) async {
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number available')),
      );
      return;
    }

    final url = Uri.parse('tel:$phone');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      }
    } catch (e) {
      //Call error: $e');
    }
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _keyboardListenerFocus.dispose();
    super.dispose();
  }

  void _handleExternalKeyboardInput(String char) {
    final value = _messageController.value;
    final start = value.selection.baseOffset;
    final end = value.selection.extentOffset;

    if (start < 0) {
      _messageController.text += char;
    } else {
      final newText = value.text.replaceRange(start, end, char);
      _messageController.value = value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: start + char.length),
      );
    }
    setState(() {});
  }

  void _handleExternalBackspace() {
    if (_messageController.text.isEmpty) return;

    final value = _messageController.value;
    final start = value.selection.baseOffset;
    final end = value.selection.extentOffset;

    if (start < 0) {
      _messageController.text = value.text.substring(0, value.text.length - 1);
    } else if (start == end) {
      _messageController.value = value.copyWith(
        text: value.text.replaceRange(start - 1, end, ''),
        selection: TextSelection.collapsed(offset: start - 1),
      );
    } else {
      _messageController.value = value.copyWith(
        text: value.text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
      );
    }
    setState(() {});
  }

  void _toggleTextKeyboard() {
    _keyboardListenerFocus.requestFocus();
    setState(() {
      _showTextKeyboard = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RideProvider>(
      builder: (context, rideProvider, child) {
        final activeRide = rideProvider.activeRide;

        if (activeRide == null) {
          return _buildNoActiveRide();
        }

        return KeyboardListener(
          focusNode: _keyboardListenerFocus,
          onKeyEvent: (event) {
            if (!_showTextKeyboard) return;
            if (event is! KeyDownEvent) return;
            if (event.logicalKey == LogicalKeyboardKey.backspace) {
              _handleExternalBackspace();
            } else if (event.character != null && event.character!.isNotEmpty) {
              _handleExternalKeyboardInput(event.character!);
            }
          },
          child: Scaffold(
            backgroundColor: AppColors.background,
            appBar: _buildAppBar(activeRide),
            body: Stack(
              children: [
                Column(
                  children: [
                    // Quick responses
                    _buildQuickResponses(),

                    // Messages list
                    Expanded(
                      child: _isLoading
                          ? const Center(
                              child: CircularProgressIndicator(color: Color(0xFFFF9500)),
                            )
                          : _messages.isEmpty
                              ? _buildEmptyChat(activeRide)
                              : _buildMessagesList(activeRide),
                    ),

                    // Input field
                    _buildInputField(),
                  ],
                ),
                // Custom Keyboard Overlay
                if (_showTextKeyboard)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: CustomTextKeyboard(
                      controller: _messageController,
                      onDone: () {
                        setState(() => _showTextKeyboard = false);
                      },
                      onChanged: () => setState(() {}),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNoActiveRide() {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('Messages', style: TextStyle(color: AppColors.textPrimary)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.card,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline,
                size: 48,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No active ride',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Chat is available during active rides',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(RideModel ride) {
    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.textPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          // Passenger avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFF9500),
                  const Color(0xFFFF9500).withValues(alpha: 0.7),
                ],
              ),
            ),
            child: Center(
              child: Text(
                ride.passengerName.isNotEmpty
                    ? ride.passengerName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ride.passengerName,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Active ride',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        // Call button
        IconButton(
          icon: const Icon(Icons.phone_rounded, color: Color(0xFFFF9500)),
          onPressed: () {
            HapticService.lightImpact();
            _callPassenger(ride.passengerPhone);
          },
        ),
        // Report button
        IconButton(
          icon: const Icon(Icons.flag_outlined, color: AppColors.textSecondary),
          onPressed: () => _showReportDialog(ride),
        ),
      ],
    );
  }

  Widget _buildQuickResponses() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(
            color: AppColors.border.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _QuickResponseChip(
              label: 'On my way',
              icon: Icons.directions_car,
              onTap: () => _sendQuickResponse(QuickResponseType.onMyWay),
            ),
            _QuickResponseChip(
              label: 'Arrived',
              icon: Icons.location_on,
              onTap: () => _sendQuickResponse(QuickResponseType.arrived),
            ),
            _QuickResponseChip(
              label: 'Waiting',
              icon: Icons.hourglass_empty,
              onTap: () => _sendQuickResponse(QuickResponseType.waiting),
            ),
            _QuickResponseChip(
              label: 'Traffic',
              icon: Icons.traffic,
              onTap: () => _sendQuickResponse(QuickResponseType.traffic),
            ),
            _QuickResponseChip(
              label: "Can't find",
              icon: Icons.help_outline,
              onTap: () => _sendQuickResponse(QuickResponseType.cantFind),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyChat(RideModel ride) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            'Start a conversation',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Send a message to ${ride.passengerName}',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList(RideModel ride) {
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    final driverId = driverProvider.driver?.id ?? '';

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isMe = message.senderId == driverId;
        final showAvatar = index == 0 ||
            _messages[index - 1].senderId != message.senderId;

        return _MessageBubble(
          message: message,
          isMe: isMe,
          showAvatar: showAvatar,
          passengerName: ride.passengerName,
        );
      },
    );
  }

  Widget _buildInputField() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(
            color: AppColors.border.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          // Location button
          GestureDetector(
            onTap: _sendLocation,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.location_on,
                color: AppColors.textSecondary,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Text input
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _messageController,
                keyboardType: TextInputType.none,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: TextStyle(color: AppColors.textTertiary),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                textCapitalization: TextCapitalization.sentences,
                onTap: _toggleTextKeyboard,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Send button
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF9500), Color(0xFFFF6B00)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _isSending
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _showReportDialog(RideModel ride) {
    HapticService.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _ReportBottomSheet(ride: ride),
    );
  }
}

// Quick response chip widget
class _QuickResponseChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickResponseChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFF9500).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFFF9500).withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const Color(0xFFFF9500), size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFFF9500),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Message bubble widget
class _MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final bool showAvatar;
  final String passengerName;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.showAvatar,
    required this.passengerName,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe && showAvatar) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF9500).withValues(alpha: 0.2),
              ),
              child: Center(
                child: Text(
                  passengerName.isNotEmpty ? passengerName[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: Color(0xFFFF9500),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ] else if (!isMe) ...[
            const SizedBox(width: 40),
          ],

          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFFFF9500) : AppColors.card,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Location message
                  if (message.type == MessageType.location) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.location_on,
                          color: isMe ? Colors.white : const Color(0xFFFF9500),
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Shared location',
                          style: TextStyle(
                            color: isMe ? Colors.white : AppColors.textPrimary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    // Text message
                    Text(
                      message.content,
                      style: TextStyle(
                        color: isMe ? Colors.white : AppColors.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  // Time
                  Text(
                    _formatTime(message.createdAt),
                    style: TextStyle(
                      color: isMe
                          ? Colors.white.withValues(alpha: 0.7)
                          : AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (isMe) ...[
            const SizedBox(width: 4),
            Icon(
              message.isRead ? Icons.done_all : Icons.done,
              color: message.isRead ? const Color(0xFFFF9500) : AppColors.textTertiary,
              size: 16,
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

// Report bottom sheet
class _ReportBottomSheet extends StatefulWidget {
  final RideModel ride;

  const _ReportBottomSheet({required this.ride});

  @override
  State<_ReportBottomSheet> createState() => _ReportBottomSheetState();
}

class _ReportBottomSheetState extends State<_ReportBottomSheet> {
  final TextEditingController _detailsController = TextEditingController();
  final ReportService _reportService = ReportService();
  String? _selectedReason;
  bool _isSubmitting = false;

  final List<Map<String, dynamic>> _reportReasons = [
    {'id': 'rude', 'label': 'Rude behavior', 'icon': Icons.sentiment_dissatisfied},
    {'id': 'no_show', 'label': 'No show', 'icon': Icons.person_off},
    {'id': 'wrong_address', 'label': 'Wrong address', 'icon': Icons.wrong_location},
    {'id': 'unsafe', 'label': 'Felt unsafe', 'icon': Icons.warning_amber},
    {'id': 'intoxicated', 'label': 'Passenger intoxicated', 'icon': Icons.local_bar},
    {'id': 'damage', 'label': 'Damage to vehicle', 'icon': Icons.car_crash},
    {'id': 'harassment', 'label': 'Harassment', 'icon': Icons.report_problem},
    {'id': 'other', 'label': 'Other', 'icon': Icons.more_horiz},
  ];

  Future<void> _submitReport() async {
    if (_selectedReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a reason')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    HapticService.mediumImpact();

    try {
      final driverProvider = Provider.of<DriverProvider>(context, listen: false);
      final locationProvider = Provider.of<LocationProvider>(context, listen: false);
      final driver = driverProvider.driver;

      if (driver == null) {
        throw Exception('Driver not found');
      }

      // Get current location for the report
      final position = locationProvider.currentPosition;

      // Save to Supabase driver_reports table
      await _reportService.submitRiderReport(
        driverId: driver.id,
        rideId: widget.ride.id,
        riderId: widget.ride.passengerId,
        riderName: widget.ride.passengerName,
        reason: _selectedReason!,
        details: _detailsController.text.isNotEmpty ? _detailsController.text : null,
        latitude: position?.latitude,
        longitude: position?.longitude,
      );

      //Report submitted to Supabase: $_selectedReason');

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report submitted. We\'ll review it shortly.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      //Report error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error submitting report. Try again.')),
        );
      }
    }

    setState(() => _isSubmitting = false);
  }

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.flag, color: Colors.red, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Report Rider',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        widget.ride.passengerName,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Reason selection
            const Text(
              'What happened?',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),

            // Reason chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _reportReasons.map((reason) {
                final isSelected = _selectedReason == reason['id'];
                return GestureDetector(
                  onTap: () {
                    HapticService.lightImpact();
                    setState(() => _selectedReason = reason['id']);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.red.withValues(alpha: 0.15)
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? Colors.red
                            : AppColors.border.withValues(alpha: 0.3),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          reason['icon'],
                          color: isSelected ? Colors.red : AppColors.textSecondary,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          reason['label'],
                          style: TextStyle(
                            color: isSelected ? Colors.red : AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Details input
            const Text(
              'Additional details (optional)',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.border.withValues(alpha: 0.3),
                ),
              ),
              child: TextField(
                controller: _detailsController,
                style: const TextStyle(color: AppColors.textPrimary),
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Describe what happened...',
                  hintStyle: TextStyle(color: AppColors.textTertiary),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Submit button
            GestureDetector(
              onTap: _isSubmitting ? null : _submitReport,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: _selectedReason == null
                      ? AppColors.surface
                      : Colors.red,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: _isSubmitting
                    ? const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                      )
                    : const Center(
                        child: Text(
                          'Submit Report',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
