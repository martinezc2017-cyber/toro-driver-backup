import '../config/supabase_config.dart';

/// Service for logging audit events to Supabase
/// All driver events are tracked for legal compliance and support
class AuditService {
  static final AuditService _instance = AuditService._internal();
  static AuditService get instance => _instance;
  AuditService._internal();

  /// Log an audit event to Supabase
  Future<void> logEvent({
    required String eventType,
    required String entityType,
    required String entityId,
    String? description,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;

      await SupabaseConfig.client.from('audit_log').insert({
        'event_type': eventType,
        'entity_type': entityType,
        'entity_id': entityId,
        'user_id': user?.id,
        'description': description,
        'metadata': metadata,
        'created_at': DateTime.now().toIso8601String(),
      });

      // [AUDIT] Event logged: $eventType - $entityType - $entityId');
    } catch (e) {
      // Don't throw - audit logging should never block the app
      // [AUDIT] Error logging event: $e');
    }
  }

  // ============================================
  // PRE-DEFINED EVENT TYPES FOR DRIVER APP
  // ============================================

  /// Driver attempted to go online but was blocked
  Future<void> logOnlineBlocked({
    required String driverId,
    required String reason,
    required Map<String, dynamic> status,
  }) async {
    await logEvent(
      eventType: 'driver_online_blocked',
      entityType: 'driver',
      entityId: driverId,
      description: 'Driver blocked from going online: $reason',
      metadata: {
        'reason': reason,
        'admin_approved': status['admin_approved'],
        'all_docs_signed': status['all_docs_signed'],
        'can_receive_rides': status['can_receive_rides'],
        'onboarding_stage': status['onboarding_stage'],
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Driver successfully went online
  Future<void> logOnlineSuccess({
    required String driverId,
    double? latitude,
    double? longitude,
  }) async {
    await logEvent(
      eventType: 'driver_went_online',
      entityType: 'driver',
      entityId: driverId,
      description: 'Driver successfully went online',
      metadata: {
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Driver went offline
  Future<void> logOffline({
    required String driverId,
    String? reason,
  }) async {
    await logEvent(
      eventType: 'driver_went_offline',
      entityType: 'driver',
      entityId: driverId,
      description: reason ?? 'Driver went offline',
      metadata: {
        'reason': reason,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Document signed by driver
  Future<void> logDocumentSigned({
    required String driverId,
    required String documentType,
    String? ipAddress,
    double? latitude,
    double? longitude,
  }) async {
    await logEvent(
      eventType: 'document_signed',
      entityType: 'driver',
      entityId: driverId,
      description: 'Driver signed $documentType',
      metadata: {
        'document_type': documentType,
        'ip_address': ipAddress,
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Driver session started (app opened)
  Future<void> logSessionStart({
    required String driverId,
    String? appVersion,
    String? deviceInfo,
  }) async {
    await logEvent(
      eventType: 'driver_session_start',
      entityType: 'driver',
      entityId: driverId,
      description: 'Driver app session started',
      metadata: {
        'app_version': appVersion,
        'device_info': deviceInfo,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Driver completed a ride
  Future<void> logRideCompleted({
    required String driverId,
    required String rideId,
    required double earnings,
    double? tipAmount,
  }) async {
    await logEvent(
      eventType: 'ride_completed',
      entityType: 'ride',
      entityId: rideId,
      description: 'Driver completed ride',
      metadata: {
        'driver_id': driverId,
        'earnings': earnings,
        'tip_amount': tipAmount,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Driver accepted a ride
  Future<void> logRideAccepted({
    required String driverId,
    required String rideId,
    double? pickupLat,
    double? pickupLng,
  }) async {
    await logEvent(
      eventType: 'ride_accepted',
      entityType: 'ride',
      entityId: rideId,
      description: 'Driver accepted ride',
      metadata: {
        'driver_id': driverId,
        'pickup_lat': pickupLat,
        'pickup_lng': pickupLng,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Driver cancelled a ride
  Future<void> logRideCancelled({
    required String driverId,
    required String rideId,
    String? reason,
  }) async {
    await logEvent(
      eventType: 'ride_cancelled_by_driver',
      entityType: 'ride',
      entityId: rideId,
      description: 'Driver cancelled ride: ${reason ?? "No reason"}',
      metadata: {
        'driver_id': driverId,
        'reason': reason,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Instant payout requested
  Future<void> logPayoutRequest({
    required String driverId,
    required double amount,
    String? payoutMethod,
  }) async {
    await logEvent(
      eventType: 'instant_payout_requested',
      entityType: 'driver',
      entityId: driverId,
      description: 'Driver requested instant payout of \$${amount.toStringAsFixed(2)}',
      metadata: {
        'amount': amount,
        'payout_method': payoutMethod,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  // ============================================
  // TOURISM EVENT AUDIT EVENTS
  // ============================================

  /// Event republished to broadcast (returned to draft)
  Future<void> logEventRepublished({
    required String eventId,
    required String action,
    String? previousDriverId,
    String? previousVehicleId,
    String? previousStatus,
    String? reason,
  }) async {
    await logEvent(
      eventType: 'event_republished',
      entityType: 'tourism_event',
      entityId: eventId,
      description: 'Event returned to broadcast: $action',
      metadata: {
        'action': action,
        'previous_driver_id': previousDriverId,
        'previous_vehicle_id': previousVehicleId,
        'previous_status': previousStatus,
        'reason': reason,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Driver assigned to event
  Future<void> logEventDriverAssigned({
    required String eventId,
    required String driverId,
    String? vehicleId,
    String? method,
  }) async {
    await logEvent(
      eventType: 'event_driver_assigned',
      entityType: 'tourism_event',
      entityId: eventId,
      description: 'Driver assigned via $method',
      metadata: {
        'driver_id': driverId,
        'vehicle_id': vehicleId,
        'method': method,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Driver left/rejected event
  Future<void> logEventDriverLeft({
    required String eventId,
    required String driverId,
    String? reason,
  }) async {
    await logEvent(
      eventType: 'event_driver_left',
      entityType: 'tourism_event',
      entityId: eventId,
      description: 'Driver left event: ${reason ?? "voluntary"}',
      metadata: {
        'driver_id': driverId,
        'reason': reason,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Event status changed
  Future<void> logEventStatusChange({
    required String eventId,
    required String fromStatus,
    required String toStatus,
    String? changedBy,
    String? reason,
  }) async {
    await logEvent(
      eventType: 'event_status_change',
      entityType: 'tourism_event',
      entityId: eventId,
      description: 'Status: $fromStatus → $toStatus',
      metadata: {
        'from_status': fromStatus,
        'to_status': toStatus,
        'changed_by': changedBy,
        'reason': reason,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Bid activity on event
  Future<void> logEventBidActivity({
    required String eventId,
    required String bidId,
    required String action,
    String? driverId,
    double? pricePerKm,
  }) async {
    await logEvent(
      eventType: 'event_bid_$action',
      entityType: 'tourism_event',
      entityId: eventId,
      description: 'Bid $action on event',
      metadata: {
        'bid_id': bidId,
        'driver_id': driverId,
        'action': action,
        'price_per_km': pricePerKm,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }
}
