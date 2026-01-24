import 'package:flutter/foundation.dart';
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

      debugPrint('[AUDIT] Event logged: $eventType - $entityType - $entityId');
    } catch (e) {
      // Don't throw - audit logging should never block the app
      debugPrint('[AUDIT] Error logging event: $e');
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
}
