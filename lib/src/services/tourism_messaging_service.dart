import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

/// Message types for tourism event chat.
enum TourismMessageType {
  text,
  image,
  location,
  announcement,
  callToBus,
  emergency,
  system,
}

/// Model for a tourism chat message.
class TourismMessage {
  final String id;
  final String eventId;
  final String senderId;
  final String senderType; // 'organizer', 'driver', 'passenger'
  final String? senderName;
  final String? senderAvatarUrl;
  final String? message;
  final TourismMessageType messageType;
  final String? imageUrl;
  final String? thumbnailUrl;
  final double? lat;
  final double? lng;
  final String? locationName;
  final String targetType; // 'all', 'organizer_only', 'driver_only', etc.
  final String? targetUserId;
  final bool isPinned;
  final List<String> readBy;
  final DateTime createdAt;

  TourismMessage({
    required this.id,
    required this.eventId,
    required this.senderId,
    required this.senderType,
    this.senderName,
    this.senderAvatarUrl,
    this.message,
    required this.messageType,
    this.imageUrl,
    this.thumbnailUrl,
    this.lat,
    this.lng,
    this.locationName,
    required this.targetType,
    this.targetUserId,
    required this.isPinned,
    required this.readBy,
    required this.createdAt,
  });

  factory TourismMessage.fromJson(Map<String, dynamic> json) {
    // Parse message type
    TourismMessageType type = TourismMessageType.text;
    final typeStr = json['message_type'] as String?;
    if (typeStr != null) {
      switch (typeStr) {
        case 'text':
          type = TourismMessageType.text;
          break;
        case 'image':
          type = TourismMessageType.image;
          break;
        case 'location':
          type = TourismMessageType.location;
          break;
        case 'announcement':
          type = TourismMessageType.announcement;
          break;
        case 'call_to_bus':
          type = TourismMessageType.callToBus;
          break;
        case 'emergency':
          type = TourismMessageType.emergency;
          break;
        case 'system':
          type = TourismMessageType.system;
          break;
      }
    }

    // Parse read_by array
    List<String> readBy = [];
    final readByData = json['read_by'];
    if (readByData is List) {
      readBy = readByData.map((e) => e.toString()).toList();
    }

    return TourismMessage(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      senderId: json['sender_id'] as String,
      senderType: json['sender_type'] as String? ?? 'passenger',
      senderName: json['sender_name'] as String?,
      senderAvatarUrl: json['sender_avatar_url'] as String?,
      message: json['message'] as String?,
      messageType: type,
      imageUrl: json['image_url'] as String?,
      thumbnailUrl: json['thumbnail_url'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      locationName: json['location_name'] as String?,
      targetType: json['target_type'] as String? ?? 'all',
      targetUserId: json['target_user_id'] as String?,
      isPinned: json['is_pinned'] as bool? ?? false,
      readBy: readBy,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    String typeStr;
    switch (messageType) {
      case TourismMessageType.text:
        typeStr = 'text';
        break;
      case TourismMessageType.image:
        typeStr = 'image';
        break;
      case TourismMessageType.location:
        typeStr = 'location';
        break;
      case TourismMessageType.announcement:
        typeStr = 'announcement';
        break;
      case TourismMessageType.callToBus:
        typeStr = 'call_to_bus';
        break;
      case TourismMessageType.emergency:
        typeStr = 'emergency';
        break;
      case TourismMessageType.system:
        typeStr = 'system';
        break;
    }

    return {
      'id': id,
      'event_id': eventId,
      'sender_id': senderId,
      'sender_type': senderType,
      'sender_name': senderName,
      'sender_avatar_url': senderAvatarUrl,
      'message': message,
      'message_type': typeStr,
      'image_url': imageUrl,
      'thumbnail_url': thumbnailUrl,
      'lat': lat,
      'lng': lng,
      'location_name': locationName,
      'target_type': targetType,
      'target_user_id': targetUserId,
      'is_pinned': isPinned,
      'read_by': readBy,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// Service for tourism event group chat messaging.
///
/// Handles sending and receiving messages for tourism events,
/// including text, images, announcements, and call-to-bus messages.
class TourismMessagingService {
  // Singleton
  static final TourismMessagingService _instance =
      TourismMessagingService._internal();
  factory TourismMessagingService() => _instance;
  TourismMessagingService._internal();

  final SupabaseClient _client = SupabaseConfig.client;
  RealtimeChannel? _messageChannel;
  /// Named subscriptions for multiple concurrent subscribers (e.g., dashboard + parent screen).
  final Map<String, RealtimeChannel> _namedChannels = {};
  final _messagesController =
      StreamController<List<TourismMessage>>.broadcast();

  Stream<List<TourismMessage>> get messagesStream => _messagesController.stream;

  // ===========================================================================
  // MESSAGES CRUD
  // ===========================================================================

  /// Get all messages for an event.
  ///
  /// Returns messages ordered by creation time (oldest first).
  /// Pinned messages are returned separately in the result.
  Future<List<TourismMessage>> getMessages(String eventId) async {
    try {
      final response = await _client
          .from('tourism_messages')
          .select()
          .eq('event_id', eventId)
          .order('created_at', ascending: true);

      return (response as List)
          .map((json) => TourismMessage.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('TOURISM_CHAT -> Error getting messages: $e');
      return [];
    }
  }

  /// Get pinned announcement for an event.
  ///
  /// Returns the most recent pinned announcement message.
  Future<TourismMessage?> getPinnedAnnouncement(String eventId) async {
    try {
      final response = await _client
          .from('tourism_messages')
          .select()
          .eq('event_id', eventId)
          .eq('is_pinned', true)
          .eq('message_type', 'announcement')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;
      return TourismMessage.fromJson(response);
    } catch (e) {
      debugPrint('TOURISM_CHAT -> Error getting pinned announcement: $e');
      return null;
    }
  }

  /// Send a text message to the event chat.
  ///
  /// [eventId] - the event to send to
  /// [senderId] - the user sending the message
  /// [senderType] - 'driver', 'organizer', or 'passenger'
  /// [senderName] - display name of the sender
  /// [message] - the text message content
  /// [senderAvatarUrl] - optional avatar URL
  Future<bool> sendMessage({
    required String eventId,
    required String senderId,
    required String senderType,
    required String senderName,
    required String message,
    String? senderAvatarUrl,
    String targetType = 'all',
    String? targetUserId,
  }) async {
    try {
      await _client.from('tourism_messages').insert({
        'event_id': eventId,
        'sender_id': senderId,
        'sender_type': senderType,
        'sender_name': senderName,
        'sender_avatar_url': senderAvatarUrl,
        'message': message,
        'message_type': 'text',
        'target_type': targetType,
        'target_user_id': targetUserId,
        'is_pinned': false,
        'read_by': [],
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      debugPrint('TOURISM_CHAT -> Message sent');
      return true;
    } catch (e) {
      debugPrint('TOURISM_CHAT -> Error sending message: $e');
      return false;
    }
  }

  /// Send an image message to the event chat.
  ///
  /// [imageUrl] - the URL of the uploaded image
  /// [thumbnailUrl] - optional thumbnail URL
  Future<bool> sendImageMessage({
    required String eventId,
    required String senderId,
    required String senderType,
    required String senderName,
    required String imageUrl,
    String? thumbnailUrl,
    String? senderAvatarUrl,
  }) async {
    try {
      await _client.from('tourism_messages').insert({
        'event_id': eventId,
        'sender_id': senderId,
        'sender_type': senderType,
        'sender_name': senderName,
        'sender_avatar_url': senderAvatarUrl,
        'message': null,
        'message_type': 'image',
        'image_url': imageUrl,
        'thumbnail_url': thumbnailUrl,
        'target_type': 'all',
        'is_pinned': false,
        'read_by': [],
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      debugPrint('TOURISM_CHAT -> Image message sent');
      return true;
    } catch (e) {
      debugPrint('TOURISM_CHAT -> Error sending image message: $e');
      return false;
    }
  }

  /// Send an announcement message (only for driver/organizer).
  ///
  /// Announcements can be pinned to appear at the top of the chat.
  Future<bool> sendAnnouncement({
    required String eventId,
    required String senderId,
    required String senderType,
    required String senderName,
    required String message,
    bool pin = false,
    String? senderAvatarUrl,
  }) async {
    // Only driver and organizer can send announcements
    if (senderType != 'driver' && senderType != 'organizer') {
      debugPrint('TOURISM_CHAT -> Only driver/organizer can send announcements');
      return false;
    }

    try {
      // If pinning, unpin previous announcements first
      if (pin) {
        await _client
            .from('tourism_messages')
            .update({'is_pinned': false})
            .eq('event_id', eventId)
            .eq('is_pinned', true);
      }

      await _client.from('tourism_messages').insert({
        'event_id': eventId,
        'sender_id': senderId,
        'sender_type': senderType,
        'sender_name': senderName,
        'sender_avatar_url': senderAvatarUrl,
        'message': message,
        'message_type': 'announcement',
        'target_type': 'all',
        'is_pinned': pin,
        'read_by': [],
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      debugPrint('TOURISM_CHAT -> Announcement sent (pinned: $pin)');
      return true;
    } catch (e) {
      debugPrint('TOURISM_CHAT -> Error sending announcement: $e');
      return false;
    }
  }

  /// Send a "call to bus" message (only for driver/organizer).
  ///
  /// This is a special message type that alerts all passengers
  /// to return to the bus.
  Future<bool> sendCallToBus({
    required String eventId,
    required String senderId,
    required String senderType,
    required String senderName,
    String? senderAvatarUrl,
  }) async {
    // Only driver and organizer can call to bus
    if (senderType != 'driver' && senderType != 'organizer') {
      debugPrint('TOURISM_CHAT -> Only driver/organizer can call to bus');
      return false;
    }

    try {
      await _client.from('tourism_messages').insert({
        'event_id': eventId,
        'sender_id': senderId,
        'sender_type': senderType,
        'sender_name': senderName,
        'sender_avatar_url': senderAvatarUrl,
        'message': 'Regresen al autobus!',
        'message_type': 'call_to_bus',
        'target_type': 'all',
        'is_pinned': false,
        'read_by': [],
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      debugPrint('TOURISM_CHAT -> Call to bus sent');
      return true;
    } catch (e) {
      debugPrint('TOURISM_CHAT -> Error sending call to bus: $e');
      return false;
    }
  }

  /// Pin or unpin a message.
  Future<bool> togglePin(String messageId, bool isPinned) async {
    try {
      await _client
          .from('tourism_messages')
          .update({'is_pinned': isPinned})
          .eq('id', messageId);

      debugPrint('TOURISM_CHAT -> Message pin toggled: $isPinned');
      return true;
    } catch (e) {
      debugPrint('TOURISM_CHAT -> Error toggling pin: $e');
      return false;
    }
  }

  /// Mark a message as read by the current user.
  Future<void> markAsRead(String messageId, String userId) async {
    try {
      // Get current read_by array
      final response = await _client
          .from('tourism_messages')
          .select('read_by')
          .eq('id', messageId)
          .single();

      final readBy = List<String>.from(response['read_by'] ?? []);
      if (!readBy.contains(userId)) {
        readBy.add(userId);
        await _client
            .from('tourism_messages')
            .update({'read_by': readBy})
            .eq('id', messageId);
      }
    } catch (e) {
      debugPrint('TOURISM_CHAT -> Error marking as read: $e');
    }
  }

  // ===========================================================================
  // REALTIME SUBSCRIPTION
  // ===========================================================================

  /// Subscribe to real-time messages for an event.
  ///
  /// [onNewMessage] is called whenever a new message is received.
  void subscribeToMessages(
    String eventId,
    Function(TourismMessage) onNewMessage,
  ) {
    if (_messageChannel != null) {
      _client.removeChannel(_messageChannel!);
      _messageChannel = null;
    }

    _messageChannel = _client.channel('tourism_chat_$eventId');

    _messageChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'tourism_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'event_id',
            value: eventId,
          ),
          callback: (payload) {
            debugPrint('TOURISM_CHAT -> New message received');
            final message = TourismMessage.fromJson(payload.newRecord);
            onNewMessage(message);
          },
        )
        .subscribe();

    debugPrint('TOURISM_CHAT -> Subscribed to messages for event $eventId');
  }

  /// Subscribe with a unique [subscriberKey] so multiple widgets can listen
  /// without overwriting each other's channels.
  void subscribeWithKey(
    String subscriberKey,
    String eventId,
    Function(TourismMessage) onNewMessage,
  ) {
    // Clean up previous subscription for this key
    final oldChannel = _namedChannels[subscriberKey];
    if (oldChannel != null) {
      _client.removeChannel(oldChannel);
    }

    final channel = _client.channel('tourism_chat_${eventId}_$subscriberKey');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'tourism_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'event_id',
            value: eventId,
          ),
          callback: (payload) {
            try {
              final message = TourismMessage.fromJson(payload.newRecord);
              onNewMessage(message);
            } catch (e) {
              debugPrint('TOURISM_CHAT -> Error parsing realtime message: $e');
            }
          },
        )
        .subscribe();

    _namedChannels[subscriberKey] = channel;
    debugPrint('TOURISM_CHAT -> [$subscriberKey] subscribed for event $eventId');
  }

  /// Unsubscribe a specific named subscriber.
  void unsubscribeKey(String subscriberKey) {
    final channel = _namedChannels[subscriberKey];
    if (channel != null) {
      _client.removeChannel(channel);
    }
    _namedChannels.remove(subscriberKey);
  }

  /// Unsubscribe from real-time messages (legacy single-channel).
  void unsubscribe() {
    if (_messageChannel != null) {
      _client.removeChannel(_messageChannel!);
      _messageChannel = null;
    }
  }

  /// Dispose the service.
  void dispose() {
    unsubscribe();
    for (final ch in _namedChannels.values) {
      _client.removeChannel(ch);
    }
    _namedChannels.clear();
    _messagesController.close();
  }

  // ===========================================================================
  // IMAGE UPLOAD
  // ===========================================================================

  /// Upload an image to storage and return the public URL.
  ///
  /// [imageBytes] - the image data
  /// [fileName] - the file name (with extension)
  /// [eventId] - the event ID (used for folder organization)
  Future<String?> uploadImage({
    required List<int> imageBytes,
    required String fileName,
    required String eventId,
  }) async {
    try {
      final path = 'tourism/$eventId/$fileName';

      await _client.storage
          .from('chat-images')
          .uploadBinary(path, Uint8List.fromList(imageBytes));

      final publicUrl =
          _client.storage.from('chat-images').getPublicUrl(path);

      debugPrint('TOURISM_CHAT -> Image uploaded: $publicUrl');
      return publicUrl;
    } catch (e) {
      debugPrint('TOURISM_CHAT -> Error uploading image: $e');
      return null;
    }
  }

  // ===========================================================================
  // STATISTICS
  // ===========================================================================

  /// Get participant count for an event.
  Future<int> getParticipantCount(String eventId) async {
    try {
      final response = await _client
          .from('tourism_invitations')
          .select('id')
          .eq('event_id', eventId)
          .eq('status', 'accepted');

      return (response as List).length;
    } catch (e) {
      debugPrint('TOURISM_CHAT -> Error getting participant count: $e');
      return 0;
    }
  }
}
