import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

/// Service for managing tourism event invitations, check-ins, and GPS tracking.
///
/// Handles:
/// - Creating and managing invitations for tourism events
/// - Bulk invitation sending
/// - Invitation code generation and validation
/// - Passenger acceptance/decline flow
/// - Check-in tracking at stops
/// - Real-time GPS tracking of passengers
class TourismInvitationService {
  // Singleton
  static final TourismInvitationService _instance =
      TourismInvitationService._internal();
  factory TourismInvitationService() => _instance;
  TourismInvitationService._internal();

  final SupabaseClient _client = SupabaseConfig.client;

  // ---------------------------------------------------------------------------
  // INVITATIONS
  // ---------------------------------------------------------------------------

  /// Creates a new invitation for a tourism event.
  ///
  /// [eventId] - The ID of the tourism event.
  /// [invitee] - Map containing invitee details (name, email, phone, etc.).
  ///             Accepts both 'invitee_*' and 'invited_*' field names.
  ///
  /// Returns the created invitation record with normalized field names.
  Future<Map<String, dynamic>> createInvitation(
    String eventId,
    Map<String, dynamic> invitee,
  ) async {
    try {
      final code = generateInvitationCode();
      final now = DateTime.now().toIso8601String();

      // Normalize field names (code uses invitee_*, DB uses invited_*)
      final normalizedInvitee = <String, dynamic>{};
      for (final entry in invitee.entries) {
        // Convert invitee_* to invited_* for database
        if (entry.key == 'invitee_name') {
          normalizedInvitee['invited_name'] = entry.value;
        } else if (entry.key == 'invitee_email') {
          normalizedInvitee['invited_email'] = entry.value;
        } else if (entry.key == 'invitee_phone') {
          normalizedInvitee['invited_phone'] = entry.value;
        } else if (entry.key == 'delivery_method') {
          normalizedInvitee['invitation_method'] = entry.value;
        } else {
          normalizedInvitee[entry.key] = entry.value;
        }
      }

      // Try to find existing user by email or phone to link invitation
      if (normalizedInvitee['user_id'] == null) {
        try {
          Map<String, dynamic>? profile;
          final email = normalizedInvitee['invited_email'] as String?;
          final phone = normalizedInvitee['invited_phone'] as String?;

          if (email != null && email.isNotEmpty) {
            profile = await _client
                .from('profiles')
                .select('id')
                .eq('email', email)
                .maybeSingle();
          }
          if (profile == null && phone != null && phone.isNotEmpty) {
            profile = await _client
                .from('profiles')
                .select('id')
                .eq('phone', phone)
                .maybeSingle();
          }
          if (profile != null) {
            normalizedInvitee['user_id'] = profile['id'];
            debugPrint('INVITATION -> Linked to existing user: ${profile['id']}');
          }
        } catch (_) {}
      }

      final data = {
        'event_id': eventId,
        'invitation_code': code,
        'status': 'pending',
        'created_at': now,
        'updated_at': now,
        ...normalizedInvitee,
      };

      final response = await _client
          .from('tourism_invitations')
          .insert(data)
          .select()
          .single();

      // Send in-app notification to linked user
      final linkedUserId = normalizedInvitee['user_id'] as String?;
      if (linkedUserId != null) {
        try {
          await _client.from('notifications').insert({
            'user_id': linkedUserId,
            'title': 'Nueva invitacion de turismo',
            'body': 'Te han invitado al evento "${normalizedInvitee['invited_name'] ?? 'turismo'}". Revisa tu seccion Explorar.',
            'type': 'tourism_invitation',
            'data': {
              'event_id': eventId,
              'invitation_id': response['id'],
              'invitation_code': code,
            },
            'read': false,
          });
          debugPrint('INVITATION -> Notification sent to user: $linkedUserId');
        } catch (e) {
          debugPrint('INVITATION -> Notification insert error: $e');
        }
      }

      // Normalize response field names for consistency
      final result = Map<String, dynamic>.from(response);
      result['invitee_name'] = result['invited_name'];
      result['invitee_email'] = result['invited_email'];
      result['invitee_phone'] = result['invited_phone'];
      result['delivery_method'] = result['invitation_method'];

      return result;
    } catch (e) {
      throw Exception('Failed to create invitation: $e');
    }
  }

  /// Fetches all invitations for a specific event with profile data.
  ///
  /// [eventId] - The ID of the tourism event.
  ///
  /// Returns a list of invitation records with user profile info (if linked),
  /// ordered by creation date. NO LIMIT - returns ALL invitations.
  ///
  /// The response includes normalized field names:
  /// - invitee_name (from invited_name or profile.full_name)
  /// - invitee_email (from invited_email or profile.email)
  /// - invitee_phone (from invited_phone or profile.phone)
  Future<List<Map<String, dynamic>>> getEventInvitations(String eventId) async {
    try {
      // Fetch invitations with optional profile join
      final response = await _client
          .from('tourism_invitations')
          .select('''
            *,
            profile:profiles!tourism_invitations_user_id_fkey(
              id,
              full_name,
              email,
              phone,
              avatar_url
            )
          ''')
          .eq('event_id', eventId)
          .order('created_at', ascending: false);

      // Normalize the data to use consistent field names
      final results = <Map<String, dynamic>>[];
      for (final row in response as List) {
        final invitation = Map<String, dynamic>.from(row as Map);
        final profile = invitation.remove('profile') as Map<String, dynamic>?;

        // Normalize field names (DB uses invited_*, code uses invitee_*)
        // Priority: invitation data > profile data
        invitation['invitee_name'] = invitation['invited_name'] ??
            profile?['full_name'] ??
            'Sin nombre';
        invitation['invitee_email'] =
            invitation['invited_email'] ?? profile?['email'];
        invitation['invitee_phone'] =
            invitation['invited_phone'] ?? profile?['phone'];
        invitation['avatar_url'] = profile?['avatar_url'];

        // Keep original DB field names for compatibility
        invitation['invited_name'] ??= invitation['invitee_name'];
        invitation['invited_email'] ??= invitation['invitee_email'];
        invitation['invited_phone'] ??= invitation['invitee_phone'];

        // Add profile info if available
        if (profile != null) {
          invitation['profile_id'] = profile['id'];
          invitation['has_profile'] = true;
        } else {
          invitation['has_profile'] = false;
        }

        results.add(invitation);
      }

      return results;
    } catch (e) {
      // Log error but still try basic query without join
      try {
        final fallbackResponse = await _client
            .from('tourism_invitations')
            .select()
            .eq('event_id', eventId)
            .order('created_at', ascending: false);

        // Normalize field names for fallback
        final results = <Map<String, dynamic>>[];
        for (final row in fallbackResponse as List) {
          final invitation = Map<String, dynamic>.from(row as Map);
          invitation['invitee_name'] =
              invitation['invited_name'] ?? 'Sin nombre';
          invitation['invitee_email'] = invitation['invited_email'];
          invitation['invitee_phone'] = invitation['invited_phone'];
          invitation['has_profile'] = false;
          results.add(invitation);
        }
        return results;
      } catch (_) {
        return [];
      }
    }
  }

  /// Finds an invitation by its unique code.
  ///
  /// [code] - The invitation code (e.g., INV-XXXXXXXX).
  ///
  /// Returns the invitation record or null if not found.
  Future<Map<String, dynamic>?> getInvitationByCode(String code) async {
    try {
      final response = await _client
          .from('tourism_invitations')
          .select('*, tourism_events(*)')
          .eq('invitation_code', code)
          .maybeSingle();

      return response;
    } catch (e) {
      return null;
    }
  }

  /// Fetches an invitation by its ID.
  ///
  /// [invitationId] - The UUID of the invitation.
  ///
  /// Returns the invitation record or null if not found.
  Future<Map<String, dynamic>?> getInvitationById(String invitationId) async {
    try {
      final response = await _client
          .from('tourism_invitations')
          .select('*, tourism_events(*)')
          .eq('id', invitationId)
          .maybeSingle();

      return response;
    } catch (e) {
      return null;
    }
  }

  /// Updates an existing invitation.
  ///
  /// [invitationId] - The UUID of the invitation to update.
  /// [updates] - Map of fields to update.
  ///
  /// Returns the updated invitation record.
  Future<Map<String, dynamic>> updateInvitation(
    String invitationId,
    Map<String, dynamic> updates,
  ) async {
    try {
      final data = {
        ...updates,
        'updated_at': DateTime.now().toIso8601String(),
      };

      final response = await _client
          .from('tourism_invitations')
          .update(data)
          .eq('id', invitationId)
          .select()
          .single();

      return response;
    } catch (e) {
      throw Exception('Failed to update invitation: $e');
    }
  }

  /// Deletes an invitation.
  ///
  /// [invitationId] - The UUID of the invitation to delete.
  Future<void> deleteInvitation(String invitationId) async {
    try {
      await _client
          .from('tourism_invitations')
          .delete()
          .eq('id', invitationId);
    } catch (e) {
      throw Exception('Failed to delete invitation: $e');
    }
  }

  /// Resends an invitation by updating its sent_at timestamp.
  ///
  /// [invitationId] - The UUID of the invitation.
  /// [method] - Optional new delivery method ('email', 'sms', 'whatsapp').
  ///
  /// Returns the updated invitation record.
  Future<Map<String, dynamic>> resendInvitation(
    String invitationId, {
    String? method,
  }) async {
    try {
      final now = DateTime.now().toIso8601String();
      final updates = <String, dynamic>{
        'updated_at': now,
        'sent_at': now,
        if (method != null) 'invitation_method': method,
      };

      // If status was expired or declined, reset to pending
      final current = await getInvitationById(invitationId);
      if (current != null) {
        final currentStatus = current['status'] as String?;
        if (currentStatus == 'expired' || currentStatus == 'declined') {
          updates['status'] = 'pending';
          updates['declined_at'] = null;
        }
      }

      final response = await _client
          .from('tourism_invitations')
          .update(updates)
          .eq('id', invitationId)
          .select()
          .single();

      // Normalize response
      final result = Map<String, dynamic>.from(response);
      result['invitee_name'] = result['invited_name'];
      result['invitee_email'] = result['invited_email'];
      result['invitee_phone'] = result['invited_phone'];
      result['delivery_method'] = result['invitation_method'];

      return result;
    } catch (e) {
      throw Exception('Failed to resend invitation: $e');
    }
  }

  /// Cancels an invitation (sets status to 'expired').
  ///
  /// [invitationId] - The UUID of the invitation.
  /// [reason] - Optional cancellation reason.
  Future<void> cancelInvitation(String invitationId, {String? reason}) async {
    try {
      final now = DateTime.now().toIso8601String();
      await _client.from('tourism_invitations').update({
        'status': 'expired',
        'updated_at': now,
        if (reason != null) 'special_needs': reason, // Using special_needs to store reason
      }).eq('id', invitationId);
    } catch (e) {
      throw Exception('Failed to cancel invitation: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // BULK OPERATIONS
  // ---------------------------------------------------------------------------

  /// Sends multiple invitations at once for an event.
  ///
  /// [eventId] - The ID of the tourism event.
  /// [invitees] - List of invitee data maps.
  /// [method] - Delivery method: 'email', 'sms', 'whatsapp', or 'manual'.
  ///
  /// Returns a map with results: {success: count, failed: count, invitations: list}.
  Future<Map<String, dynamic>> sendBulkInvitations(
    String eventId,
    List<Map<String, dynamic>> invitees,
    String method,
  ) async {
    final results = <Map<String, dynamic>>[];
    int successCount = 0;
    int failedCount = 0;

    for (final invitee in invitees) {
      try {
        final invitation = await createInvitation(eventId, {
          ...invitee,
          'delivery_method': method,
          'sent_at': DateTime.now().toIso8601String(),
        });
        results.add(invitation);
        successCount++;
      } catch (e) {
        failedCount++;
      }
    }

    return {
      'success': successCount,
      'failed': failedCount,
      'invitations': results,
    };
  }

  // ---------------------------------------------------------------------------
  // CODES AND LINKS
  // ---------------------------------------------------------------------------

  /// Generates a unique invitation code.
  ///
  /// Format: INV-XXXXXXXX (8 alphanumeric characters).
  String generateInvitationCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    final code = List.generate(8, (_) => chars[random.nextInt(chars.length)]).join();
    return 'INV-$code';
  }

  /// Generates a shareable invitation URL.
  ///
  /// [code] - The invitation code.
  ///
  /// Returns a deep link URL for the invitation.
  String generateInvitationUrl(String code) {
    // Using a universal link format that can be handled by the app
    return 'https://toro.app/invite/$code';
  }

  // ---------------------------------------------------------------------------
  // PASSENGER RESPONSE
  // ---------------------------------------------------------------------------

  /// Accepts an invitation on behalf of a passenger.
  ///
  /// [invitationId] - The UUID of the invitation.
  /// [userId] - The user ID of the passenger accepting.
  ///
  /// Returns the updated invitation record.
  Future<Map<String, dynamic>> acceptInvitation(
    String invitationId,
    String userId,
  ) async {
    try {
      final now = DateTime.now().toIso8601String();

      final response = await _client
          .from('tourism_invitations')
          .update({
            'status': 'accepted',
            'user_id': userId,
            'accepted_at': now,
            'updated_at': now,
          })
          .eq('id', invitationId)
          .select()
          .single();

      // Notify organizer and driver that a passenger accepted
      _notifyInvitationAccepted(response);

      return response;
    } catch (e) {
      throw Exception('Failed to accept invitation: $e');
    }
  }

  /// Sends notification to organizer (and driver if assigned) when passenger accepts.
  Future<void> _notifyInvitationAccepted(Map<String, dynamic> invitation) async {
    try {
      final eventId = invitation['event_id'] as String?;
      if (eventId == null) return;

      final event = await _client
          .from('tourism_events')
          .select('event_name, organizer_id, driver_id')
          .eq('id', eventId)
          .maybeSingle();
      if (event == null) return;

      final passengerName = invitation['invited_name'] ?? 'Un pasajero';
      final eventName = event['event_name'] ?? 'Evento';
      final organizerId = event['organizer_id'] as String?;
      final driverId = event['driver_id'] as String?;

      // Find organizer's user_id
      if (organizerId != null) {
        final organizer = await _client
            .from('organizers')
            .select('user_id')
            .eq('id', organizerId)
            .maybeSingle();

        if (organizer != null) {
          await _client.from('notifications').insert({
            'user_id': organizer['user_id'],
            'title': 'Pasajero Confirmado',
            'body': '$passengerName aceptó la invitación para "$eventName"',
            'type': 'tourism_invitation_accepted',
            'data': {
              'event_id': eventId,
              'invitation_id': invitation['id'],
            },
            'read': false,
          });
        }
      }

      // Also notify driver if assigned
      if (driverId != null) {
        await _client.from('notifications').insert({
          'user_id': driverId,
          'title': 'Nuevo Pasajero',
          'body': '$passengerName se unió a "$eventName"',
          'type': 'tourism_invitation_accepted',
          'data': {
            'event_id': eventId,
            'invitation_id': invitation['id'],
          },
          'read': false,
        });
      }
    } catch (_) {
      // Non-critical: don't fail the acceptance if notification fails
    }
  }

  /// Declines an invitation.
  ///
  /// [invitationId] - The UUID of the invitation.
  ///
  /// Returns the updated invitation record.
  Future<Map<String, dynamic>> declineInvitation(String invitationId) async {
    try {
      final now = DateTime.now().toIso8601String();

      final response = await _client
          .from('tourism_invitations')
          .update({
            'status': 'declined',
            'declined_at': now,
            'updated_at': now,
          })
          .eq('id', invitationId)
          .select()
          .single();

      return response;
    } catch (e) {
      throw Exception('Failed to decline invitation: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // CHECK-IN
  // ---------------------------------------------------------------------------

  /// Records a check-in for a passenger.
  ///
  /// [invitationId] - The UUID of the invitation.
  /// [performedByType] - Who performed the check-in: 'driver', 'organizer', 'passenger', 'system'.
  /// [performedById] - The ID of the person who performed the check-in.
  /// [lat] - Latitude of check-in location.
  /// [lng] - Longitude of check-in location.
  /// [checkInType] - Type of check-in: 'boarding', 'stop', 'final', 'manual'.
  /// [stopName] - Optional name of the stop.
  /// [stopIndex] - Optional index of the stop in the route.
  ///
  /// Returns the created check-in record.
  Future<Map<String, dynamic>> checkInPassenger({
    required String invitationId,
    required String performedByType,
    required String performedById,
    required double lat,
    required double lng,
    required String checkInType,
    String? stopName,
    int? stopIndex,
  }) async {
    try {
      final now = DateTime.now().toIso8601String();

      final checkInData = {
        'invitation_id': invitationId,
        'performed_by_type': performedByType,
        'performed_by_id': performedById,
        'lat': lat,
        'lng': lng,
        'check_in_type': checkInType,
        'stop_name': stopName,
        'stop_index': stopIndex,
        'checked_in_at': now,
        'created_at': now,
      };

      final response = await _client
          .from('tourism_check_ins')
          .insert(checkInData)
          .select()
          .single();

      // Update the invitation status
      await _client.from('tourism_invitations').update({
        'status': 'checked_in',
        'last_check_in_at': now,
        'updated_at': now,
      }).eq('id', invitationId);

      return response;
    } catch (e) {
      throw Exception('Failed to check in passenger: $e');
    }
  }

  /// Fetches the check-in history for a specific invitation.
  ///
  /// [invitationId] - The UUID of the invitation.
  ///
  /// Returns a list of check-in records ordered by time.
  Future<List<Map<String, dynamic>>> getCheckInHistory(
      String invitationId) async {
    try {
      final response = await _client
          .from('tourism_check_ins')
          .select()
          .eq('invitation_id', invitationId)
          .order('checked_in_at', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  /// Fetches all check-ins for an event.
  ///
  /// [eventId] - The ID of the tourism event.
  ///
  /// Returns a list of check-in records with invitation details.
  Future<List<Map<String, dynamic>>> getEventCheckIns(String eventId) async {
    try {
      final response = await _client
          .from('tourism_check_ins')
          .select('*, tourism_invitations(invited_name, invited_email, invited_phone, user_id, status)')
          .eq('event_id', eventId)
          .order('checked_at', ascending: false);

      // Normalize response to have consistent field names
      final results = <Map<String, dynamic>>[];
      for (final row in response as List) {
        final checkIn = Map<String, dynamic>.from(row as Map);
        final invitation = checkIn['tourism_invitations'] as Map<String, dynamic>?;

        // Normalize invitation data
        if (invitation != null) {
          checkIn['invitee_name'] = invitation['invited_name'] ?? 'Pasajero';
          checkIn['invitee_email'] = invitation['invited_email'];
          checkIn['invitee_phone'] = invitation['invited_phone'];
        } else {
          checkIn['invitee_name'] = 'Pasajero';
        }

        results.add(checkIn);
      }

      return results;
    } catch (e) {
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // GPS TRACKING
  // ---------------------------------------------------------------------------

  /// Updates the GPS location of a passenger.
  ///
  /// [invitationId] - The UUID of the invitation.
  /// [lat] - Current latitude.
  /// [lng] - Current longitude.
  /// [accuracy] - Optional GPS accuracy in meters.
  Future<void> updatePassengerLocation(
    String invitationId,
    double lat,
    double lng, {
    double? accuracy,
  }) async {
    try {
      final now = DateTime.now().toIso8601String();

      await _client.from('tourism_passenger_locations').upsert({
        'invitation_id': invitationId,
        'lat': lat,
        'lng': lng,
        'accuracy': accuracy,
        'updated_at': now,
      }, onConflict: 'invitation_id');
    } catch (e) {
      throw Exception('Failed to update passenger location: $e');
    }
  }

  /// Fetches all passenger locations for an event.
  ///
  /// [eventId] - The ID of the tourism event.
  ///
  /// Returns a list of passengers with their GPS locations from tourism_invitations.
  Future<List<Map<String, dynamic>>> getPassengerLocations(
      String eventId) async {
    try {
      debugPrint('GPS_SVC -> getPassengerLocations called for event: $eventId');
      // Read locations directly from tourism_invitations
      // DB columns: last_known_lat, last_known_lng (NOT last_lat, last_lng)
      final response = await _client
          .from('tourism_invitations')
          .select('id, invited_name, invited_email, invited_phone, user_id, status, current_check_in_status, last_known_lat, last_known_lng, last_gps_update, gps_tracking_enabled, seat_number, boarding_stop, dropoff_stop')
          .eq('event_id', eventId)
          .inFilter('status', ['accepted', 'boarded', 'checked_in'])
          .not('last_known_lat', 'is', null);

      debugPrint('GPS_SVC -> Raw response: $response');
      debugPrint('GPS_SVC -> Response count: ${(response as List).length}');

      final results = <Map<String, dynamic>>[];
      for (final row in response) {
        final inv = Map<String, dynamic>.from(row as Map);
        debugPrint('GPS_SVC -> Processing: name=${inv['invited_name']}, lat=${inv['last_known_lat']}, lng=${inv['last_known_lng']}');
        results.add({
          'invitation_id': inv['id'],
          'invitee_name': inv['invited_name'] ?? 'Pasajero',
          'invitee_email': inv['invited_email'],
          'invitee_phone': inv['invited_phone'],
          'user_id': inv['user_id'],
          'status': inv['status'],
          'check_in_status': inv['current_check_in_status'],
          'lat': inv['last_known_lat'],
          'lng': inv['last_known_lng'],
          'updated_at': inv['last_gps_update'],
          'gps_tracking_enabled': inv['gps_tracking_enabled'] ?? false,
          'seat_number': inv['seat_number'],
          'boarding_stop': inv['boarding_stop'],
          'dropoff_stop': inv['dropoff_stop'],
        });
      }

      debugPrint('GPS_SVC -> Returning ${results.length} locations');
      return results;
    } catch (e) {
      debugPrint('GPS_SVC -> ERROR: $e');
      return [];
    }
  }

  /// Subscribes to real-time passenger location updates for an event.
  ///
  /// [eventId] - The ID of the tourism event.
  /// [onUpdate] - Callback function called when a location is updated.
  ///
  /// Listens to changes in tourism_invitations where last_known_lat/last_known_lng are updated.
  StreamSubscription<dynamic>? streamPassengerLocations(
    String eventId,
    void Function(Map<String, dynamic> location) onUpdate,
  ) {
    try {
      final channel = _client.channel('passenger_locations_$eventId');

      channel.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'tourism_invitations',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'event_id',
          value: eventId,
        ),
        callback: (payload) {
          final newRecord = payload.newRecord;
          // DB columns: last_known_lat, last_known_lng
          if (newRecord.isNotEmpty && newRecord['last_known_lat'] != null) {
            onUpdate({
              'invitation_id': newRecord['id'],
              'invitee_name': newRecord['invited_name'] ?? 'Pasajero',
              'lat': newRecord['last_known_lat'],
              'lng': newRecord['last_known_lng'],
              'status': newRecord['status'],
              'check_in_status': newRecord['current_check_in_status'],
              'updated_at': newRecord['last_gps_update'],
            });
          }
        },
      ).subscribe();

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Subscribes to real-time passenger locations using RealtimeChannel.
  ///
  /// Returns a RealtimeChannel that can be unsubscribed.
  RealtimeChannel subscribeToPassengerLocations({
    required String eventId,
    required void Function(Map<String, dynamic> location) onLocationUpdate,
  }) {
    final channel = _client.channel('passenger_locations_rt_$eventId');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'tourism_invitations',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'event_id',
        value: eventId,
      ),
      callback: (payload) {
        final newRecord = payload.newRecord;
        // DB columns: last_known_lat, last_known_lng (NOT last_lat, last_lng)
        if (newRecord.isNotEmpty && newRecord['last_known_lat'] != null) {
          onLocationUpdate({
            'invitation_id': newRecord['id'],
            'invitee_name': newRecord['invited_name'] ?? 'Pasajero',
            'lat': newRecord['last_known_lat'],
            'lng': newRecord['last_known_lng'],
            'status': newRecord['status'],
            'check_in_status': newRecord['current_check_in_status'],
            'updated_at': newRecord['last_gps_update'],
          });
        }
      },
    ).subscribe();

    return channel;
  }

  // ---------------------------------------------------------------------------
  // STATS
  // ---------------------------------------------------------------------------

  /// Fetches invitation statistics for an event.
  ///
  /// [eventId] - The ID of the tourism event.
  ///
  /// Returns a map with statistics:
  /// - total: Total number of invitations
  /// - accepted: Number of accepted invitations
  /// - declined: Number of declined invitations
  /// - pending: Number of pending invitations
  /// - checked_in: Number of checked-in passengers
  /// - gps_active: Number of passengers with active GPS tracking
  Future<Map<String, dynamic>> getInvitationStats(String eventId) async {
    try {
      final invitations = await getEventInvitations(eventId);

      int total = invitations.length;
      int accepted = 0;
      int declined = 0;
      int pending = 0;
      int checkedIn = 0;
      int boarded = 0;
      int offBoarded = 0;

      for (final invitation in invitations) {
        var status = invitation['status'] as String?;
        // If rider checked in but status wasn't synced, use current_check_in_status
        final checkInSt = invitation['current_check_in_status'] as String?;
        if (status == 'accepted' && (checkInSt == 'boarded' || checkInSt == 'arrived')) {
          status = 'checked_in';
        }
        switch (status) {
          case 'accepted':
            accepted++;
            break;
          case 'declined':
            declined++;
            break;
          case 'pending':
            pending++;
            break;
          case 'checked_in':
            checkedIn++;
            break;
          case 'boarded':
            boarded++;
            break;
          case 'off_boarded':
            offBoarded++;
            break;
        }
      }

      // Get active GPS locations count
      final locations = await getPassengerLocations(eventId);
      final now = DateTime.now();
      int gpsActive = 0;

      for (final location in locations) {
        final updatedAt = location['updated_at'] as String?;
        if (updatedAt != null) {
          final updateTime = DateTime.tryParse(updatedAt);
          if (updateTime != null &&
              now.difference(updateTime).inMinutes < 15) {
            gpsActive++;
          }
        }
      }

      // "Cupo" = total accepted/confirmed passengers (accepted + checked_in + boarded)
      final confirmedCount = accepted + checkedIn + boarded;

      return {
        'total': total,
        'accepted': accepted,
        'declined': declined,
        'pending': pending,
        'checked_in': checkedIn,
        'boarded': boarded,
        'off_boarded': offBoarded,
        'confirmed': confirmedCount,
        'gps_active': gpsActive,
      };
    } catch (e) {
      return {
        'total': 0,
        'accepted': 0,
        'declined': 0,
        'pending': 0,
        'checked_in': 0,
        'boarded': 0,
        'off_boarded': 0,
        'confirmed': 0,
        'gps_active': 0,
      };
    }
  }

  // ---------------------------------------------------------------------------
  // PICKUP REQUESTS
  // ---------------------------------------------------------------------------

  /// Gets all pickup requests for an event (passengers who requested custom pickup locations).
  ///
  /// Returns pending, approved, and denied pickup requests with passenger info.
  Future<List<Map<String, dynamic>>> getPickupRequests(String eventId) async {
    try {
      final response = await _client
          .from('tourism_invitations')
          .select('''
            id, invited_name, invited_email, invited_phone, user_id, status,
            pickup_address, pickup_lat, pickup_lng, pickup_requested_at,
            pickup_approved, pickup_approved_at, pickup_notes, pickup_order,
            profiles(full_name, phone, avatar_url)
          ''')
          .eq('event_id', eventId)
          .not('pickup_lat', 'is', null)
          .order('pickup_requested_at', ascending: false);

      final results = <Map<String, dynamic>>[];
      for (final row in response as List) {
        final inv = Map<String, dynamic>.from(row as Map);
        final profile = inv['profiles'] as Map<String, dynamic>?;

        results.add({
          'invitation_id': inv['id'],
          'passenger_name': profile?['full_name'] ?? inv['invited_name'] ?? 'Pasajero',
          'passenger_phone': profile?['phone'] ?? inv['invited_phone'],
          'avatar_url': profile?['avatar_url'],
          'status': inv['status'],
          'pickup_address': inv['pickup_address'],
          'pickup_lat': inv['pickup_lat'],
          'pickup_lng': inv['pickup_lng'],
          'pickup_requested_at': inv['pickup_requested_at'],
          'pickup_approved': inv['pickup_approved'], // null=pending, true=approved, false=denied
          'pickup_approved_at': inv['pickup_approved_at'],
          'pickup_notes': inv['pickup_notes'],
          'pickup_order': inv['pickup_order'],
        });
      }

      return results;
    } catch (e) {
      return [];
    }
  }

  /// Counts pending pickup requests for an event.
  Future<int> countPendingPickups(String eventId) async {
    try {
      final response = await _client
          .from('tourism_invitations')
          .select('id')
          .eq('event_id', eventId)
          .not('pickup_lat', 'is', null)
          .isFilter('pickup_approved', null);

      return (response as List).length;
    } catch (e) {
      return 0;
    }
  }

  /// Approves or denies a pickup request.
  ///
  /// [invitationId] - The invitation ID.
  /// [approved] - True to approve, false to deny.
  /// [order] - Optional order in the route (for approved pickups).
  /// [notes] - Optional notes for the passenger.
  Future<bool> respondToPickupRequest(
    String invitationId, {
    required bool approved,
    int? order,
    String? notes,
  }) async {
    try {
      await _client.from('tourism_invitations').update({
        'pickup_approved': approved,
        'pickup_approved_at': DateTime.now().toUtc().toIso8601String(),
        if (order != null) 'pickup_order': order,
        if (notes != null) 'pickup_notes': notes,
      }).eq('id', invitationId);

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Updates pickup order for multiple invitations (after route optimization).
  Future<bool> updatePickupOrders(
    String eventId,
    List<Map<String, dynamic>> orders,
  ) async {
    try {
      for (final order in orders) {
        await _client
            .from('tourism_invitations')
            .update({'pickup_order': order['order']})
            .eq('id', order['invitation_id'])
            .eq('event_id', eventId);
      }
      return true;
    } catch (e) {
      return false;
    }
  }
}
