import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/package_delivery_model.dart';

class DeliveryService {
  final SupabaseClient _client = SupabaseConfig.client;

  // Get available delivery tickets for driver (nearby)
  Future<List<DriverTicketModel>> getAvailableTickets({
    required double latitude,
    required double longitude,
    double radiusMiles = 10.0,
  }) async {
    try {
      final response = await _client.rpc(
        'get_available_tickets',
        params: {
          'p_driver_lat': latitude,
          'p_driver_lng': longitude,
          'p_radius_miles': radiusMiles,
        },
      );

      return (response as List)
          .map((json) => DriverTicketModel.fromJson(json))
          .toList();
    } catch (e) {
      // Fallback to simple query without geo filtering
      final response = await _client
          .from(SupabaseConfig.driverTicketsTable)
          .select()
          .eq('status', 'available')
          .order('created_at', ascending: false)
          .limit(20);

      return (response as List)
          .map((json) => DriverTicketModel.fromJson(json))
          .toList();
    }
  }

  // Get ticket by ID
  Future<DriverTicketModel?> getTicket(String ticketId) async {
    final response = await _client
        .from(SupabaseConfig.driverTicketsTable)
        .select()
        .eq('id', ticketId)
        .maybeSingle();

    if (response == null) return null;
    return DriverTicketModel.fromJson(response);
  }

  // Get delivery by ID
  Future<PackageDeliveryModel?> getDelivery(String deliveryId) async {
    final response = await _client
        .from(SupabaseConfig.packageDeliveriesTable)
        .select()
        .eq('id', deliveryId)
        .maybeSingle();

    if (response == null) return null;
    return PackageDeliveryModel.fromJson(response);
  }

  // Accept delivery ticket - uses SQL function for atomicity
  Future<DriverTicketModel> acceptTicket(
      String ticketId, String driverId) async {
    try {
      final response = await _client.rpc(
        'accept_delivery_ticket',
        params: {
          'p_ticket_id': ticketId,
          'p_driver_id': driverId,
        },
      );

      return DriverTicketModel.fromJson(response);
    } catch (e) {
      // Fallback to direct update
      final response = await _client
          .from(SupabaseConfig.driverTicketsTable)
          .update({
            'driver_id': driverId,
            'status': 'accepted',
            'accepted_at': DateTime.now().toIso8601String(),
          })
          .eq('id', ticketId)
          .eq('status', 'available')
          .select()
          .single();

      // Also update the delivery
      final ticket = DriverTicketModel.fromJson(response);
      await _client.from(SupabaseConfig.packageDeliveriesTable).update({
        'driver_id': driverId,
        'status': DeliveryStatus.accepted.name,
        'accepted_at': DateTime.now().toIso8601String(),
      }).eq('id', ticket.deliveryId);

      return ticket;
    }
  }

  // Update delivery status to driver en route
  Future<PackageDeliveryModel> startEnRoute(String deliveryId) async {
    final response = await _client
        .from(SupabaseConfig.packageDeliveriesTable)
        .update({
          'status': DeliveryStatus.driverEnRoute.name,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', deliveryId)
        .select()
        .single();

    return PackageDeliveryModel.fromJson(response);
  }

  // Mark package as picked up
  Future<PackageDeliveryModel> pickupPackage(String deliveryId) async {
    final response = await _client
        .from(SupabaseConfig.packageDeliveriesTable)
        .update({
          'status': DeliveryStatus.pickedUp.name,
          'picked_up_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', deliveryId)
        .select()
        .single();

    return PackageDeliveryModel.fromJson(response);
  }

  // Mark as in transit
  Future<PackageDeliveryModel> startTransit(String deliveryId) async {
    final response = await _client
        .from(SupabaseConfig.packageDeliveriesTable)
        .update({
          'status': DeliveryStatus.inTransit.name,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', deliveryId)
        .select()
        .single();

    return PackageDeliveryModel.fromJson(response);
  }

  // Complete delivery - uses SQL function for atomicity
  Future<PackageDeliveryModel> completeDelivery(
      String deliveryId, String driverId) async {
    try {
      final response = await _client.rpc(
        'complete_package_delivery',
        params: {
          'p_delivery_id': deliveryId,
          'p_driver_id': driverId,
        },
      );

      return PackageDeliveryModel.fromJson(response);
    } catch (e) {
      // Fallback to direct update
      final response = await _client
          .from(SupabaseConfig.packageDeliveriesTable)
          .update({
            'status': DeliveryStatus.delivered.name,
            'delivered_at': DateTime.now().toIso8601String(),
            'payment_status': PaymentStatus.captured.name,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', deliveryId)
          .eq('driver_id', driverId)
          .select()
          .single();

      // Update ticket
      await _client.from(SupabaseConfig.driverTicketsTable).update({
        'status': 'completed',
        'completed_at': DateTime.now().toIso8601String(),
      }).eq('delivery_id', deliveryId);

      return PackageDeliveryModel.fromJson(response);
    }
  }

  // ─── Marketplace delivery: accept + load full context ───

  /// Loads a delivery + ALL bundled marketplace orders + their items + vendor.
  /// Uses the canonical `delivery_full_context` RPC which returns a single
  /// jsonb payload with `{delivery, orders: [...]}`.
  Future<Map<String, dynamic>?> getDeliveryFullContext(String deliveryId) async {
    try {
      final res = await _client.rpc('delivery_full_context', params: {
        'p_delivery_id': deliveryId,
      });
      if (res == null) return null;
      return Map<String, dynamic>.from(res as Map);
    } catch (e) {
      return null;
    }
  }

  /// Loads a marketplace delivery + its linked order + vendor + items.
  /// Returns null if not found.
  Future<Map<String, dynamic>?> getMarketplaceDeliveryContext(String deliveryId) async {
    try {
      final delivery = await _client
          .from('deliveries')
          .select('id, service_type, status, driver_id, '
              'pickup_lat, pickup_lng, pickup_address, '
              'destination_lat, destination_lng, destination_address, '
              'estimated_price, driver_earnings, '
              'country_code, state_code, notes, created_at')
          .eq('id', deliveryId)
          .maybeSingle();
      if (delivery == null) return null;
      if (delivery['service_type'] != 'marketplace') {
        return {'delivery': delivery, 'is_marketplace': false};
      }
      final order = await _client
          .from('marketplace_orders')
          .select('id, status, subtotal, delivery_fee, flat_commission, total, '
              'vendor_payout, payment_method, buyer_name, buyer_phone, '
              'pickup_otp, delivery_otp, '
              'vendor_id, vendor_pickup_address, delivery_address, '
              'delivery_notes, prep_time_min')
          .eq('delivery_id', deliveryId)
          .maybeSingle();
      Map<String, dynamic>? vendor;
      if (order != null) {
        vendor = await _client
            .from('vendors')
            .select('id, business_name, category_primary, logo_url')
            .eq('id', order['vendor_id'])
            .maybeSingle();
      }
      final items = order == null ? [] : await _client
          .from('marketplace_order_items')
          .select('id, product_name_snapshot, quantity, unit_price_snapshot, line_total')
          .eq('order_id', order['id']);
      return {
        'is_marketplace': true,
        'delivery': delivery,
        'order': order,
        'vendor': vendor,
        'items': items,
      };
    } catch (_) { return null; }
  }

  /// Accepts a marketplace delivery. Sets driver_id on delivery + status='driver_assigned'
  /// on marketplace_orders. Throws if not eligible or already taken.
  Future<Map<String, dynamic>> acceptMarketplaceDelivery(String deliveryId) async {
    final res = await _client.rpc('driver_accept_marketplace_delivery', params: {
      'p_delivery_id': deliveryId,
    });
    return (res is Map) ? Map<String, dynamic>.from(res) : <String, dynamic>{};
  }

  /// Contactos (vendor/buyer/driver) de una orden — RPC protegida (solo el chofer
  /// asignado o el comprador). El app muestra al que toca segun la fase.
  Future<List<Map<String, dynamic>>> marketplaceContacts(String orderId) async {
    try {
      final res = await _client.rpc('marketplace_delivery_contacts', params: {'p_order_id': orderId});
      return (res is List) ? List<Map<String, dynamic>>.from(res) : <Map<String, dynamic>>[];
    } catch (e) {
      debugPrint('marketplaceContacts error: $e');
      return <Map<String, dynamic>>[];
    }
  }

  /// Reporta no-show. p_by='driver' (el comprador no estaba) o 'buyer' (el chofer
  /// no llego). Cancela + restock; como el cobro es al ENTREGAR, la autorizacion
  /// no se captura y el comprador NO se cobra.
  Future<Map<String, dynamic>> reportNoShow({
    required String orderId,
    required String by,
    String? photoUrl,
    double? lat,
    double? lng,
  }) async {
    final res = await _client.rpc('marketplace_report_no_show', params: {
      'p_order_id': orderId,
      'p_by': by,
      'p_photo_url': photoUrl,
      'p_lat': lat,
      'p_lng': lng,
    });
    return (res is Map) ? Map<String, dynamic>.from(res) : <String, dynamic>{};
  }

  /// El chofer LLEGÓ a recoger -> avisa al vendedor (con el PIN de recogida en el
  /// cuerpo del push) para que entregue el paquete y dé el código. RPC SECURITY
  /// DEFINER: busca el vendor.user_id + pickup_otp y manda la notificación.
  Future<void> notifyVendorDriverArrived(String orderId) async {
    try {
      await _client.rpc('marketplace_notify_driver_arrived', params: {'p_order_id': orderId});
    } catch (_) { /* no fatal: el chofer igual puede confirmar con el OTP */ }
  }

  /// Releases a marketplace delivery back to the dispatch pool with a recorded
  /// reason. Only valid before pickup — once driver has taken possession of
  /// the goods this raises an error and becomes a support case.
  Future<Map<String, dynamic>> cancelMarketplaceDelivery(
    String deliveryId, {
    required String reason,
  }) async {
    final res = await _client.rpc('driver_cancel_marketplace_delivery', params: {
      'p_delivery_id': deliveryId,
      'p_reason': reason,
    });
    return (res is Map) ? Map<String, dynamic>.from(res) : <String, dynamic>{};
  }

  // ─── Marketplace pickup/delivery confirmation (with OTP + photo + GPS) ───

  /// Confirms marketplace pickup. Calls RPC marketplace_confirm_pickup.
  /// Throws on failure (wrong OTP, photo missing, geofence too far, etc.)
  Future<bool> confirmMarketplacePickup({
    required String orderId,
    required String otp,
    required String photoUrl,
    double? lat,
    double? lng,
  }) async {
    final res = await _client.rpc('marketplace_confirm_pickup', params: {
      'p_order_id': orderId,
      'p_otp': otp,
      'p_photo_url': photoUrl,
      'p_driver_lat': lat,
      'p_driver_lng': lng,
    });
    return res == true;
  }

  /// Confirms marketplace delivery. Calls RPC marketplace_confirm_delivery.
  Future<bool> confirmMarketplaceDelivery({
    required String orderId,
    required String otp,
    required String photoUrl,
    double? lat,
    double? lng,
  }) async {
    final res = await _client.rpc('marketplace_confirm_delivery', params: {
      'p_order_id': orderId,
      'p_otp': otp,
      'p_photo_url': photoUrl,
      'p_driver_lat': lat,
      'p_driver_lng': lng,
    });
    return res == true;
  }

  /// Captures the manual-capture card PaymentIntent for a DELIVERED marketplace
  /// order — when the buyer's money actually moves. Idempotent server-side
  /// (key mp_capture per order), so a double-call is safe. No-op for cash/wallet
  /// (no card PI). MUST run on delivery confirmation, or the 7-day auth expires
  /// and the money is never collected.
  Future<void> captureMarketplacePayment(String orderId) async {
    try {
      await _client.functions.invoke(
        'stripe-marketplace-capture',
        body: {'order_id': orderId},
      );
    } catch (_) {
      // non-fatal: capture is idempotent and can be retried (or admin-triggered)
    }
  }

  /// Uploads a proof photo to the marketplace-proofs bucket and returns its URL.
  Future<String?> uploadProofPhoto({
    required String orderId,
    required String stage, // 'pickup' or 'delivery'
    required Uint8List bytes,
    double? lat,
    double? lng,
  }) async {
    try {
      final ext = 'jpg';
      final path = '$orderId/${stage}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _client.storage.from('marketplace-proofs').uploadBinary(path, bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false));
      final url = _client.storage.from('marketplace-proofs').getPublicUrl(path);

      // Also write to order_proof_photos canonical table (multi-photo audit trail).
      // Best effort — if table doesn't exist (older DB), ignore.
      try {
        await _client.from('order_proof_photos').insert({
          'order_id': orderId,
          'stage': stage,
          'url': url,
          'uploaded_by': _client.auth.currentUser?.id,
          'lat': lat,
          'lng': lng,
        });
      } catch (_) { /* canonical proof table optional */ }

      return url;
    } catch (e) {
      return null;
    }
  }

  // Cancel delivery
  Future<PackageDeliveryModel> cancelDelivery(
      String deliveryId, String reason) async {
    final response = await _client
        .from(SupabaseConfig.packageDeliveriesTable)
        .update({
          'status': DeliveryStatus.cancelled.name,
          'cancelled_at': DateTime.now().toIso8601String(),
          'cancellation_reason': reason,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', deliveryId)
        .select()
        .single();

    return PackageDeliveryModel.fromJson(response);
  }

  // Get driver's active delivery
  Future<PackageDeliveryModel?> getActiveDelivery(String driverId) async {
    final response = await _client
        .from(SupabaseConfig.packageDeliveriesTable)
        .select()
        .eq('driver_id', driverId)
        .inFilter('status', [
          DeliveryStatus.accepted.name,
          DeliveryStatus.driverEnRoute.name,
          DeliveryStatus.pickedUp.name,
          DeliveryStatus.inTransit.name,
        ])
        .maybeSingle();

    if (response == null) return null;
    return PackageDeliveryModel.fromJson(response);
  }

  // Get driver's delivery history
  Future<List<PackageDeliveryModel>> getDeliveryHistory(
    String driverId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _client
        .from(SupabaseConfig.packageDeliveriesTable)
        .select()
        .eq('driver_id', driverId)
        .inFilter(
            'status', [DeliveryStatus.delivered.name, DeliveryStatus.cancelled.name])
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    return (response as List)
        .map((json) => PackageDeliveryModel.fromJson(json))
        .toList();
  }

  // Update driver location (also updates active delivery)
  Future<void> updateDriverLocation(
      String driverId, double lat, double lng) async {
    try {
      await _client.rpc(
        'update_driver_location',
        params: {
          'p_driver_id': driverId,
          'p_lat': lat,
          'p_lng': lng,
        },
      );
    } catch (e) {
      // Fallback to direct update
      await _client.from(SupabaseConfig.driversTable).update({
        'current_lat': lat,
        'current_lng': lng,
        'last_location_update': DateTime.now().toIso8601String(),
      }).eq('id', driverId);

      // Update active delivery location
      await _client
          .from(SupabaseConfig.packageDeliveriesTable)
          .update({
            'driver_lat': lat,
            'driver_lng': lng,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('driver_id', driverId)
          .inFilter('status', [
            DeliveryStatus.accepted.name,
            DeliveryStatus.driverEnRoute.name,
            DeliveryStatus.pickedUp.name,
            DeliveryStatus.inTransit.name,
          ]);
    }
  }

  // Get tax summary for year (IRS 1099-K)
  Future<TaxSummary> getTaxSummary(String driverId, int year) async {
    try {
      final response = await _client.rpc(
        'get_driver_tax_summary',
        params: {
          'p_driver_id': driverId,
          'p_year': year,
        },
      );

      if (response is List && response.isNotEmpty) {
        return TaxSummary.fromJson(response.first);
      }
      return TaxSummary(
        totalDeliveries: 0,
        grossEarnings: 0,
        tipsReceived: 0,
        platformFees: 0,
        netEarnings: 0,
        needs1099K: false,
      );
    } catch (e) {
      // Fallback to manual calculation
      final response = await _client
          .from(SupabaseConfig.earningsReportTable)
          .select()
          .eq('driver_id', driverId)
          .eq('year', year);

      if ((response as List).isEmpty) {
        return TaxSummary(
          totalDeliveries: 0,
          grossEarnings: 0,
          tipsReceived: 0,
          platformFees: 0,
          netEarnings: 0,
          needs1099K: false,
        );
      }

      int totalDeliveries = 0;
      double grossEarnings = 0;
      double tipsReceived = 0;
      double platformFees = 0;
      double netEarnings = 0;

      for (final row in response) {
        totalDeliveries += row['total_deliveries'] as int? ?? 0;
        grossEarnings += (row['gross_earnings'] as num?)?.toDouble() ?? 0;
        tipsReceived += (row['tips_received'] as num?)?.toDouble() ?? 0;
        platformFees += (row['platform_fees_paid'] as num?)?.toDouble() ?? 0;
        netEarnings += (row['net_earnings'] as num?)?.toDouble() ?? 0;
      }

      return TaxSummary(
        totalDeliveries: totalDeliveries,
        grossEarnings: grossEarnings,
        tipsReceived: tipsReceived,
        platformFees: platformFees,
        netEarnings: netEarnings,
        needs1099K: grossEarnings >= 600,
      );
    }
  }

  // Stream available tickets (real-time)
  // FIX: Listen to ALL status changes to detect cancellations, then filter locally
  Stream<List<DriverTicketModel>> streamAvailableTickets() {
    // FIXED: Remove status filter from stream to detect when tickets become unavailable
    // Filter locally for 'available' status
    return _client
        .from(SupabaseConfig.driverTicketsTable)
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((data) {
          // Filter locally to detect status changes (cancelled, accepted, etc.)
          final available = data.where((json) => json['status'] == 'available').toList();
          return available.map((json) => DriverTicketModel.fromJson(json)).toList();
        });
  }

  // Stream current delivery (real-time)
  Stream<PackageDeliveryModel?> streamDelivery(String deliveryId) {
    return _client
        .from(SupabaseConfig.packageDeliveriesTable)
        .stream(primaryKey: ['id'])
        .eq('id', deliveryId)
        .map((data) =>
            data.isNotEmpty ? PackageDeliveryModel.fromJson(data.first) : null);
  }

  // Send message in delivery chat
  Future<void> sendMessage({
    required String deliveryId,
    required String senderId,
    required String message,
    required bool isDriver,
  }) async {
    await _client.from(SupabaseConfig.deliveryMessagesTable).insert({
      'delivery_id': deliveryId,
      'sender_type': isDriver ? 'driver' : 'rider',
      'sender_id': senderId,
      'message': message,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // Get messages for delivery
  Future<List<Map<String, dynamic>>> getMessages(String deliveryId) async {
    final response = await _client
        .from(SupabaseConfig.deliveryMessagesTable)
        .select()
        .eq('delivery_id', deliveryId)
        .order('created_at', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  // Stream messages for delivery (real-time)
  Stream<List<Map<String, dynamic>>> streamMessages(String deliveryId) {
    return _client
        .from(SupabaseConfig.deliveryMessagesTable)
        .stream(primaryKey: ['id'])
        .eq('delivery_id', deliveryId)
        .order('created_at', ascending: true);
  }

  // Mark messages as read
  Future<void> markMessagesAsRead(String deliveryId, String readerId) async {
    await _client
        .from(SupabaseConfig.deliveryMessagesTable)
        .update({'is_read': true})
        .eq('delivery_id', deliveryId)
        .neq('sender_id', readerId);
  }

  // Get today's deliveries count
  Future<int> getTodayDeliveriesCount(String driverId) async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    final response = await _client
        .from(SupabaseConfig.packageDeliveriesTable)
        .select('id')
        .eq('driver_id', driverId)
        .eq('status', DeliveryStatus.delivered.name)
        .gte('delivered_at', startOfDay.toIso8601String());

    return (response as List).length;
  }

  // Get today's earnings from deliveries
  Future<double> getTodayDeliveryEarnings(String driverId) async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    final response = await _client
        .from(SupabaseConfig.packageDeliveriesTable)
        .select('driver_earnings, tip_amount')
        .eq('driver_id', driverId)
        .eq('status', DeliveryStatus.delivered.name)
        .gte('delivered_at', startOfDay.toIso8601String());

    double total = 0;
    for (final row in response as List) {
      total += (row['driver_earnings'] as num?)?.toDouble() ?? 0;
      total += (row['tip_amount'] as num?)?.toDouble() ?? 0;
    }
    return total;
  }
}
