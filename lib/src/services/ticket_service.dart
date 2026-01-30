import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class TicketService {
  final SupabaseClient _client = SupabaseConfig.client;

  // Create a new support ticket
  Future<Map<String, dynamic>?> createTicket({
    required String subject,
    required String description,
    required String category,
    required String priority,
    required String userId,
    required String userName,
    String? userEmail,
    String? userPhone,
  }) async {
    try {
      final response = await _client.from('support_tickets').insert({
        'subject': subject,
        'description': description,
        'category': category,
        'priority': priority,
        'status': 'open',
        'user_id': userId,
        'user_name': userName,
        'user_type': 'driver',
        'user_email': userEmail,
        'user_phone': userPhone,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).select().single();

      return response;
    } catch (e) {
      return null;
    }
  }

  // Get tickets for a specific driver
  Future<List<Map<String, dynamic>>> getDriverTickets(String userId) async {
    try {
      final response = await _client
          .from('support_tickets')
          .select()
          .eq('user_id', userId)
          .eq('user_type', 'driver')
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  // Get a single ticket by ID
  Future<Map<String, dynamic>?> getTicket(String ticketId) async {
    try {
      final response = await _client
          .from('support_tickets')
          .select()
          .eq('id', ticketId)
          .single();

      return response;
    } catch (e) {
      return null;
    }
  }

  // Listen to ticket updates for notifications
  Stream<List<Map<String, dynamic>>> watchTicketUpdates(String userId) {
    return _client
        .from('support_tickets')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .map((data) {
          // Filter for this user's driver tickets
          return data
              .where((ticket) =>
                  ticket['user_id'] == userId &&
                  ticket['user_type'] == 'driver')
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        });
  }

  // Get open tickets count
  Future<int> getOpenTicketsCount(String userId) async {
    try {
      final response = await _client
          .from('support_tickets')
          .select('id')
          .eq('user_id', userId)
          .eq('user_type', 'driver')
          .inFilter('status', ['open', 'pending', 'in_progress']);

      return (response as List).length;
    } catch (e) {
      return 0;
    }
  }

  // Get recent trips for trip selection
  Future<List<Map<String, dynamic>>> getRecentTrips(String driverId, {int limit = 5}) async {
    try {
      final response = await _client
          .from('deliveries')
          .select('id, created_at, pickup_address, dropoff_address, final_price, status')
          .eq('driver_id', driverId)
          .inFilter('status', ['completed', 'delivered'])
          .order('completed_at', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }
}
