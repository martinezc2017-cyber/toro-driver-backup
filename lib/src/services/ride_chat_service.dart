import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

/// Service for in-app chat between driver and rider
class RideChatService {
  final SupabaseClient _client = SupabaseConfig.client;
  RealtimeChannel? _chatChannel;
  final _messagesController = StreamController<List<Map<String, dynamic>>>.broadcast();

  Stream<List<Map<String, dynamic>>> get messagesStream => _messagesController.stream;

  /// Get chat history for a delivery
  Future<List<Map<String, dynamic>>> getMessages(String deliveryId) async {
    try {
      final response = await _client
          .from('ride_messages')
          .select()
          .eq('delivery_id', deliveryId)
          .order('created_at', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('CHAT -> Error getting messages: $e');
      return [];
    }
  }

  /// Send a message
  Future<bool> sendMessage({
    required String deliveryId,
    required String senderId,
    required String senderType, // 'driver' or 'rider'
    required String message,
    String messageType = 'text',
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _client.from('ride_messages').insert({
        'delivery_id': deliveryId,
        'sender_id': senderId,
        'sender_type': senderType,
        'message': message,
        'message_type': messageType,
        'metadata': metadata ?? {},
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      debugPrint('CHAT -> Message sent');
      return true;
    } catch (e) {
      debugPrint('CHAT -> Error sending message: $e');
      return false;
    }
  }

  /// Subscribe to real-time messages for a delivery
  void subscribeToMessages(String deliveryId, Function(Map<String, dynamic>) onNewMessage) {
    if (_chatChannel != null) {
      _client.removeChannel(_chatChannel!);
      _chatChannel = null;
    }

    _chatChannel = _client.channel('ride_chat_$deliveryId');

    _chatChannel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'ride_messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'delivery_id',
        value: deliveryId,
      ),
      callback: (payload) {
        debugPrint('CHAT -> New message received');
        onNewMessage(payload.newRecord);
      },
    ).subscribe();

    debugPrint('CHAT -> Subscribed to messages for delivery $deliveryId');
  }

  /// Mark messages as read
  Future<void> markMessagesAsRead(String deliveryId, String readerId) async {
    try {
      await _client
          .from('ride_messages')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('delivery_id', deliveryId)
          .neq('sender_id', readerId)
          .isFilter('read_at', null);
    } catch (e) {
      debugPrint('CHAT -> Error marking messages as read: $e');
    }
  }

  /// Get unread message count
  Future<int> getUnreadCount(String deliveryId, String readerId) async {
    try {
      final response = await _client
          .from('ride_messages')
          .select('id')
          .eq('delivery_id', deliveryId)
          .neq('sender_id', readerId)
          .isFilter('read_at', null);

      return (response as List).length;
    } catch (e) {
      debugPrint('CHAT -> Error getting unread count: $e');
      return 0;
    }
  }

  /// Unsubscribe from messages
  void unsubscribe() {
    if (_chatChannel != null) {
      _client.removeChannel(_chatChannel!);
      _chatChannel = null;
    }
  }

  /// Dispose
  void dispose() {
    unsubscribe();
    _messagesController.close();
  }
}
