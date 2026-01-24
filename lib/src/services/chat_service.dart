import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/message_model.dart';

class ChatService {
  final SupabaseClient _client = SupabaseConfig.client;

  StreamSubscription? _messageSubscription;
  final _messageController = StreamController<List<MessageModel>>.broadcast();

  Stream<List<MessageModel>> get messageStream => _messageController.stream;

  // Get conversation messages
  Future<List<MessageModel>> getMessages(String conversationId) async {
    final response = await _client
        .from(SupabaseConfig.messagesTable)
        .select()
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true);

    return (response as List).map((json) => MessageModel.fromJson(json)).toList();
  }

  // Send text message
  Future<MessageModel> sendMessage({
    required String conversationId,
    required String senderId,
    required String receiverId,
    required String content,
    MessageType type = MessageType.text,
  }) async {
    final response = await _client.from(SupabaseConfig.messagesTable).insert({
      'conversation_id': conversationId,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'content': content,
      'type': type.name,
      'is_read': false,
      'created_at': DateTime.now().toIso8601String(),
    }).select().single();

    return MessageModel.fromJson(response);
  }

  // Send location message
  Future<MessageModel> sendLocationMessage({
    required String conversationId,
    required String senderId,
    required String receiverId,
    required double latitude,
    required double longitude,
  }) async {
    final response = await _client.from(SupabaseConfig.messagesTable).insert({
      'conversation_id': conversationId,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'content': 'Ubicación compartida',
      'type': MessageType.location.name,
      'latitude': latitude,
      'longitude': longitude,
      'is_read': false,
      'created_at': DateTime.now().toIso8601String(),
    }).select().single();

    return MessageModel.fromJson(response);
  }

  // Send image message
  Future<MessageModel> sendImageMessage({
    required String conversationId,
    required String senderId,
    required String receiverId,
    required String imageUrl,
  }) async {
    final response = await _client.from(SupabaseConfig.messagesTable).insert({
      'conversation_id': conversationId,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'content': imageUrl,
      'type': MessageType.image.name,
      'is_read': false,
      'created_at': DateTime.now().toIso8601String(),
    }).select().single();

    return MessageModel.fromJson(response);
  }

  // Mark message as read
  Future<void> markAsRead(String messageId) async {
    await _client
        .from(SupabaseConfig.messagesTable)
        .update({
          'is_read': true,
          'read_at': DateTime.now().toIso8601String(),
        })
        .eq('id', messageId);
  }

  // Mark all messages in conversation as read
  Future<void> markConversationAsRead(String conversationId, String readerId) async {
    await _client
        .from(SupabaseConfig.messagesTable)
        .update({
          'is_read': true,
          'read_at': DateTime.now().toIso8601String(),
        })
        .eq('conversation_id', conversationId)
        .eq('receiver_id', readerId)
        .eq('is_read', false);
  }

  // Get or create conversation for a ride
  Future<String> getOrCreateConversation(String rideId, String driverId, String passengerId) async {
    // Check if conversation exists
    final existing = await _client
        .from(SupabaseConfig.conversationsTable)
        .select('id')
        .eq('ride_id', rideId)
        .maybeSingle();

    if (existing != null) {
      return existing['id'] as String;
    }

    // Create new conversation
    final response = await _client.from(SupabaseConfig.conversationsTable).insert({
      'ride_id': rideId,
      'driver_id': driverId,
      'passenger_id': passengerId,
      'created_at': DateTime.now().toIso8601String(),
    }).select().single();

    return response['id'] as String;
  }

  // Stream messages for a conversation (real-time)
  Stream<List<MessageModel>> streamMessages(String conversationId) {
    return _client
        .from(SupabaseConfig.messagesTable)
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .map((data) => data.map((json) => MessageModel.fromJson(json)).toList());
  }

  // Subscribe to new messages for driver
  void subscribeToMessages(String driverId, Function(MessageModel) onNewMessage) {
    _messageSubscription = _client
        .from(SupabaseConfig.messagesTable)
        .stream(primaryKey: ['id'])
        .eq('receiver_id', driverId)
        .listen((data) {
      if (data.isNotEmpty) {
        final latestMessage = MessageModel.fromJson(data.last);
        if (!latestMessage.isRead) {
          onNewMessage(latestMessage);
        }
      }
    });
  }

  // Get unread messages count
  Future<int> getUnreadCount(String driverId) async {
    final response = await _client
        .from(SupabaseConfig.messagesTable)
        .select('id')
        .eq('receiver_id', driverId)
        .eq('is_read', false);

    return (response as List).length;
  }

  // Get recent conversations for driver
  Future<List<Map<String, dynamic>>> getRecentConversations(String driverId) async {
    final response = await _client
        .from(SupabaseConfig.conversationsTable)
        .select('''
          *,
          ride:ride_id (
            id,
            pickup_address,
            dropoff_address
          ),
          passenger:passenger_id (
            id,
            first_name,
            last_name,
            profile_image_url
          )
        ''')
        .eq('driver_id', driverId)
        .order('updated_at', ascending: false)
        .limit(20);

    return List<Map<String, dynamic>>.from(response);
  }

  // Delete message
  Future<void> deleteMessage(String messageId) async {
    await _client
        .from(SupabaseConfig.messagesTable)
        .delete()
        .eq('id', messageId);
  }

  // Send quick response
  Future<MessageModel> sendQuickResponse({
    required String conversationId,
    required String senderId,
    required String receiverId,
    required QuickResponseType responseType,
  }) async {
    final content = _getQuickResponseContent(responseType);
    return sendMessage(
      conversationId: conversationId,
      senderId: senderId,
      receiverId: receiverId,
      content: content,
      type: MessageType.quickResponse,
    );
  }

  String _getQuickResponseContent(QuickResponseType type) {
    switch (type) {
      case QuickResponseType.onMyWay:
        return 'Voy en camino';
      case QuickResponseType.arrived:
        return 'He llegado';
      case QuickResponseType.waiting:
        return 'Te estoy esperando';
      case QuickResponseType.traffic:
        return 'Hay tráfico, llegaré en unos minutos';
      case QuickResponseType.cantFind:
        return 'No encuentro la ubicación, ¿puedes darme más indicaciones?';
      case QuickResponseType.thanks:
        return '¡Gracias!';
    }
  }

  // Dispose
  void dispose() {
    _messageSubscription?.cancel();
    _messageController.close();
  }
}

enum QuickResponseType {
  onMyWay,
  arrived,
  waiting,
  traffic,
  cantFind,
  thanks,
}
