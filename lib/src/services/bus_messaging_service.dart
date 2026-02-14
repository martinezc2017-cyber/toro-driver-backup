import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Message types for bus communications
enum BusMessageType {
  chat,
  system,
  report,
  alert,
  event,
}

/// Call status for bus calls
enum BusCallStatus {
  initiated,
  ringing,
  answered,
  ended,
  missed,
  rejected,
}

/// Model for a bus message
class BusMessage {
  final String id;
  final String? routeId;
  final String senderId;
  final String? receiverId;
  final String? receiverType;
  final String message;
  final BusMessageType messageType;
  final DateTime? readAt;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final Map<String, dynamic>? sender;

  BusMessage({
    required this.id,
    this.routeId,
    required this.senderId,
    this.receiverId,
    this.receiverType,
    required this.message,
    required this.messageType,
    this.readAt,
    required this.metadata,
    required this.createdAt,
    this.sender,
  });

  factory BusMessage.fromJson(Map<String, dynamic> json) {
    return BusMessage(
      id: json['id'] as String,
      routeId: json['route_id'] as String?,
      senderId: json['sender_id'] as String,
      receiverId: json['receiver_id'] as String?,
      receiverType: json['receiver_type'] as String?,
      message: json['message'] as String,
      messageType: BusMessageType.values.firstWhere(
        (e) => e.name == (json['message_type'] as String? ?? 'chat'),
        orElse: () => BusMessageType.chat,
      ),
      readAt: json['read_at'] != null ? DateTime.parse(json['read_at']) : null,
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
      createdAt: DateTime.parse(json['created_at'] as String),
      sender: json['sender'] as Map<String, dynamic>?,
    );
  }

  bool get isRead => readAt != null;
}

/// Service for bus messaging (chat, reports, alerts) and calls
class BusMessagingService extends ChangeNotifier {
  static final BusMessagingService _instance = BusMessagingService._internal();
  factory BusMessagingService() => _instance;
  BusMessagingService._internal();

  final _client = Supabase.instance.client;
  RealtimeChannel? _messageChannel;
  String? _currentUserId;
  String? _currentRouteId;

  final List<BusMessage> _messages = [];
  List<BusMessage> get messages => List.unmodifiable(_messages);

  int get unreadCount => _messages.where((m) => !m.isRead && m.receiverId == _currentUserId).length;

  /// Initialize service for a user and optional route
  Future<void> initialize({
    required String userId,
    String? routeId,
  }) async {
    _currentUserId = userId;
    _currentRouteId = routeId;

    // Load existing messages
    await _loadMessages();

    // Subscribe to new messages
    _subscribeToMessages();

    debugPrint('BUS_MESSAGING: Initialized for user $userId');
  }

  /// Load messages from database
  Future<void> _loadMessages() async {
    if (_currentUserId == null) return;

    try {
      var query = _client
          .from('bus_messages')
          .select('*, sender:profiles!bus_messages_sender_id_fkey(id, full_name, avatar_url)')
          .or('sender_id.eq.$_currentUserId,receiver_id.eq.$_currentUserId');

      if (_currentRouteId != null) {
        query = _client
            .from('bus_messages')
            .select('*, sender:profiles!bus_messages_sender_id_fkey(id, full_name, avatar_url)')
            .eq('route_id', _currentRouteId!)
            .or('sender_id.eq.$_currentUserId,receiver_id.eq.$_currentUserId');
      }

      final response = await query
          .order('created_at', ascending: false)
          .limit(100);

      _messages.clear();
      for (final json in response) {
        _messages.add(BusMessage.fromJson(json));
      }

      notifyListeners();
      debugPrint('BUS_MESSAGING: Loaded ${_messages.length} messages');
    } catch (e) {
      debugPrint('BUS_MESSAGING: Error loading messages: $e');
    }
  }

  /// Subscribe to realtime messages
  void _subscribeToMessages() {
    if (_messageChannel != null) {
      _client.removeChannel(_messageChannel!);
      _messageChannel = null;
    }

    _messageChannel = _client
        .channel('bus_messages_$_currentUserId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'bus_messages',
          filter: _currentRouteId != null
              ? PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: 'route_id',
                  value: _currentRouteId!,
                )
              : null,
          callback: (payload) {
            final newMessage = BusMessage.fromJson(payload.newRecord);
            // Only add if it's for me or from me
            if (newMessage.senderId == _currentUserId ||
                newMessage.receiverId == _currentUserId ||
                newMessage.receiverType == 'broadcast') {
              _messages.insert(0, newMessage);
              notifyListeners();
              debugPrint('BUS_MESSAGING: New message received');
            }
          },
        )
        .subscribe();
  }

  /// Send a message
  Future<bool> sendMessage({
    required String message,
    String? receiverId,
    String? receiverType,
    String? routeId,
    BusMessageType messageType = BusMessageType.chat,
    Map<String, dynamic>? metadata,
  }) async {
    if (_currentUserId == null) {
      debugPrint('BUS_MESSAGING: Cannot send - not initialized');
      return false;
    }

    try {
      await _client.from('bus_messages').insert({
        'sender_id': _currentUserId,
        'receiver_id': receiverId,
        'receiver_type': receiverType ?? 'user',
        'route_id': routeId ?? _currentRouteId,
        'message': message,
        'message_type': messageType.name,
        'metadata': metadata ?? {},
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      debugPrint('BUS_MESSAGING: Message sent');
      return true;
    } catch (e) {
      debugPrint('BUS_MESSAGING: Error sending message: $e');
      return false;
    }
  }

  /// Send a system message (e.g., status update)
  Future<bool> sendSystemMessage({
    required String message,
    String? routeId,
    Map<String, dynamic>? metadata,
  }) async {
    return sendMessage(
      message: message,
      routeId: routeId,
      receiverType: 'broadcast',
      messageType: BusMessageType.system,
      metadata: metadata,
    );
  }

  /// Send an alert message
  Future<bool> sendAlert({
    required String message,
    String? routeId,
    Map<String, dynamic>? metadata,
  }) async {
    return sendMessage(
      message: message,
      routeId: routeId,
      receiverType: 'broadcast',
      messageType: BusMessageType.alert,
      metadata: metadata,
    );
  }

  /// Send a report
  Future<bool> sendReport({
    required String message,
    String? receiverId,
    String? routeId,
    Map<String, dynamic>? metadata,
  }) async {
    return sendMessage(
      message: message,
      receiverId: receiverId,
      routeId: routeId,
      receiverType: 'admin',
      messageType: BusMessageType.report,
      metadata: metadata,
    );
  }

  /// Mark a message as read
  Future<void> markAsRead(String messageId) async {
    try {
      await _client.from('bus_messages').update({
        'read_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', messageId);

      // Update local state
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        final msg = _messages[index];
        _messages[index] = BusMessage(
          id: msg.id,
          routeId: msg.routeId,
          senderId: msg.senderId,
          receiverId: msg.receiverId,
          receiverType: msg.receiverType,
          message: msg.message,
          messageType: msg.messageType,
          readAt: DateTime.now(),
          metadata: msg.metadata,
          createdAt: msg.createdAt,
          sender: msg.sender,
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('BUS_MESSAGING: Error marking as read: $e');
    }
  }

  /// Mark all messages as read
  Future<void> markAllAsRead() async {
    if (_currentUserId == null) return;

    try {
      await _client
          .from('bus_messages')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('receiver_id', _currentUserId!)
          .isFilter('read_at', null);

      // Update local state
      for (var i = 0; i < _messages.length; i++) {
        final msg = _messages[i];
        if (msg.receiverId == _currentUserId && msg.readAt == null) {
          _messages[i] = BusMessage(
            id: msg.id,
            routeId: msg.routeId,
            senderId: msg.senderId,
            receiverId: msg.receiverId,
            receiverType: msg.receiverType,
            message: msg.message,
            messageType: msg.messageType,
            readAt: DateTime.now(),
            metadata: msg.metadata,
            createdAt: msg.createdAt,
            sender: msg.sender,
          );
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('BUS_MESSAGING: Error marking all as read: $e');
    }
  }

  /// Get conversation with a specific user
  List<BusMessage> getConversationWith(String userId) {
    return _messages
        .where((m) =>
            (m.senderId == userId && m.receiverId == _currentUserId) ||
            (m.senderId == _currentUserId && m.receiverId == userId))
        .toList();
  }

  // ==================== CALLS ====================

  /// Initiate a phone call and log it
  Future<bool> initiateCall({
    required String receiverId,
    required String phoneNumber,
    String? routeId,
  }) async {
    if (_currentUserId == null) {
      debugPrint('BUS_MESSAGING: Cannot call - not initialized');
      return false;
    }

    String? callId;

    try {
      // Log call initiation
      final response = await _client.from('bus_calls').insert({
        'caller_id': _currentUserId,
        'receiver_id': receiverId,
        'route_id': routeId ?? _currentRouteId,
        'call_type': 'voice',
        'status': 'initiated',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }).select('id').single();

      callId = response['id'] as String;

      // Launch phone app
      final uri = Uri(scheme: 'tel', path: phoneNumber);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);

        // Update status to ringing
        await _client.from('bus_calls').update({
          'status': 'ringing',
        }).eq('id', callId);

        debugPrint('BUS_MESSAGING: Call initiated to $phoneNumber');
        return true;
      } else {
        // Update status to missed if can't launch
        await _client.from('bus_calls').update({
          'status': 'missed',
        }).eq('id', callId);

        debugPrint('BUS_MESSAGING: Cannot launch phone app');
        return false;
      }
    } catch (e) {
      debugPrint('BUS_MESSAGING: Error initiating call: $e');
      return false;
    }
  }

  /// Update call status (usually called when call ends)
  Future<void> updateCallStatus({
    required String callId,
    required BusCallStatus status,
    int? durationSeconds,
  }) async {
    try {
      final data = <String, dynamic>{
        'status': status.name,
      };

      if (status == BusCallStatus.answered) {
        data['started_at'] = DateTime.now().toUtc().toIso8601String();
      }

      if (status == BusCallStatus.ended) {
        data['ended_at'] = DateTime.now().toUtc().toIso8601String();
        if (durationSeconds != null) {
          data['duration_seconds'] = durationSeconds;
        }
      }

      await _client.from('bus_calls').update(data).eq('id', callId);
      debugPrint('BUS_MESSAGING: Call status updated to ${status.name}');
    } catch (e) {
      debugPrint('BUS_MESSAGING: Error updating call status: $e');
    }
  }

  /// Clean up
  @override
  void dispose() {
    if (_messageChannel != null) {
      _client.removeChannel(_messageChannel!);
      _messageChannel = null;
    }
    _messages.clear();
    super.dispose();
  }
}
