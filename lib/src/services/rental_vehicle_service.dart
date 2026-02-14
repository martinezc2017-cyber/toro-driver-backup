import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

/// Dedicated service for rental vehicle operations.
/// Handles CRUD, photo uploads, and browsing.
class RentalVehicleService {
  static final _client = SupabaseConfig.client;
  static const _table = 'rental_vehicle_listings';
  static const _bucket = 'rental-media';

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLISH / UPDATE LISTING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new rental listing with photos and owner document
  static Future<Map<String, dynamic>> publishListing({
    required String ownerId,
    required String vehicleType,
    required String make,
    required String model,
    required int year,
    required String plate,
    String? color,
    String? vin,
    String? title,
    String? description,
    required double weeklyPrice,
    double dailyPrice = 0,
    double monthlyPrice = 0,
    double depositAmount = 0,
    double perKmBase = 0,
    String? insuranceCompany,
    String? insurancePolicyNumber,
    DateTime? insuranceExpiry,
    List<XFile> photos = const [],
    XFile? ownerDocument,
    String ownerDocumentType = 'ine',
    String? ownerName,
    String? ownerPhone,
    String? ownerEmail,
    List<String> features = const [],
    int mileageLimitKm = 0,
    String fuelPolicy = 'full_to_full',
    int minRentalDays = 1,
    int maxRentalDays = 90,
    bool instantBooking = false,
    String currency = 'MXN',
    String? pickupAddress,
    double? pickupLat,
    double? pickupLng,
    DateTime? availableFrom,
    DateTime? availableTo,
    double? signLat,
    double? signLng,
  }) async {
    // Upload photos
    final photoUrls = await uploadPhotos(ownerId, photos);

    // Upload owner document (INE/license)
    String? documentUrl;
    if (ownerDocument != null) {
      documentUrl = await _uploadFile(
        ownerId,
        ownerDocument,
        'documents',
      );
    }

    final data = <String, dynamic>{
      'owner_id': ownerId,
      'vehicle_type': vehicleType,
      'vehicle_make': make,
      'vehicle_model': model,
      'vehicle_year': year,
      'vehicle_plate': plate,
      'vehicle_color': color,
      'vehicle_vin': vin,
      'title': title ?? '$make $model $year',
      'description': description,
      'weekly_price_base': weeklyPrice,
      'daily_price': dailyPrice,
      'monthly_price': monthlyPrice,
      'deposit_amount': depositAmount,
      'per_km_base': perKmBase,
      'insurance_company': insuranceCompany,
      'insurance_policy_number': insurancePolicyNumber,
      'insurance_expiry': insuranceExpiry?.toIso8601String().substring(0, 10),
      'image_urls': photoUrls,
      'owner_document_url': documentUrl,
      'owner_document_type': ownerDocumentType,
      'owner_name': ownerName,
      'owner_phone': ownerPhone,
      'owner_email': ownerEmail,
      'features': features,
      'mileage_limit_km': mileageLimitKm,
      'fuel_policy': fuelPolicy,
      'min_rental_days': minRentalDays,
      'max_rental_days': maxRentalDays,
      'instant_booking': instantBooking,
      'currency': currency,
      'pickup_address': pickupAddress,
      'pickup_lat': pickupLat,
      'pickup_lng': pickupLng,
      'available_from': availableFrom?.toIso8601String().substring(0, 10),
      'available_to': availableTo?.toIso8601String().substring(0, 10),
      'owner_signed_at': DateTime.now().toIso8601String(),
      'owner_sign_lat': signLat,
      'owner_sign_lng': signLng,
      'status': 'active',
    };

    final result = await _client
        .from(_table)
        .insert(data)
        .select()
        .single();

    return result;
  }

  /// Update an existing listing
  static Future<void> updateListing({
    required String listingId,
    Map<String, dynamic> updates = const {},
    List<XFile> newPhotos = const [],
    String? ownerId,
  }) async {
    if (newPhotos.isNotEmpty && ownerId != null) {
      final newUrls = await uploadPhotos(ownerId, newPhotos);
      // Append to existing
      final existing = await _client
          .from(_table)
          .select('image_urls')
          .eq('id', listingId)
          .single();
      final currentUrls = List<String>.from(existing['image_urls'] ?? []);
      currentUrls.addAll(newUrls);
      updates['image_urls'] = currentUrls;
    }

    updates['updated_at'] = DateTime.now().toIso8601String();

    await _client
        .from(_table)
        .update(updates)
        .eq('id', listingId);
  }

  /// Delete a listing
  static Future<void> deleteListing(String listingId) async {
    await _client
        .from(_table)
        .update({'status': 'deleted'})
        .eq('id', listingId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHOTO UPLOADS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Upload multiple photos to rental-media bucket
  static Future<List<String>> uploadPhotos(String ownerId, List<XFile> photos) async {
    final urls = <String>[];
    for (final photo in photos) {
      final url = await _uploadFile(ownerId, photo, 'vehicles');
      if (url != null) urls.add(url);
    }
    return urls;
  }

  /// Upload a single file and return its public URL
  static Future<String?> _uploadFile(String ownerId, XFile file, String folder) async {
    try {
      final ext = file.path.split('.').last.toLowerCase();
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final path = '$ownerId/$folder/$fileName';

      if (kIsWeb) {
        final bytes = await file.readAsBytes();
        await _client.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: 'image/$ext', upsert: true),
        );
      } else {
        await _client.storage.from(_bucket).upload(
          path,
          File(file.path),
          fileOptions: FileOptions(contentType: 'image/$ext', upsert: true),
        );
      }

      final url = _client.storage.from(_bucket).getPublicUrl(path);
      return url;
    } catch (e) {
      debugPrint('[RENTAL] Upload error: $e');
      return null;
    }
  }

  /// Delete a photo from storage
  static Future<void> deletePhoto(String url) async {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;
      final bucketIndex = pathSegments.indexOf(_bucket);
      if (bucketIndex >= 0) {
        final storagePath = pathSegments.sublist(bucketIndex + 1).join('/');
        await _client.storage.from(_bucket).remove([storagePath]);
      }
    } catch (e) {
      debugPrint('[RENTAL] Delete photo error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BROWSE / SEARCH LISTINGS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all active listings (for browsing)
  static Future<List<Map<String, dynamic>>> getActiveListings({
    String? vehicleType,
    double? maxDailyPrice,
    double? maxWeeklyPrice,
    String? searchQuery,
    int limit = 50,
    int offset = 0,
  }) async {
    var query = _client
        .from(_table)
        .select('*')
        .eq('status', 'active');

    if (vehicleType != null && vehicleType.isNotEmpty) {
      query = query.eq('vehicle_type', vehicleType);
    }

    if (maxWeeklyPrice != null && maxWeeklyPrice > 0) {
      query = query.lte('weekly_price_base', maxWeeklyPrice);
    }

    if (maxDailyPrice != null && maxDailyPrice > 0) {
      query = query.lte('daily_price', maxDailyPrice);
    }

    final result = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    return List<Map<String, dynamic>>.from(result);
  }

  /// Get a single listing by ID
  static Future<Map<String, dynamic>?> getListingById(String id) async {
    try {
      final result = await _client
          .from(_table)
          .select('*')
          .eq('id', id)
          .single();
      return result;
    } catch (e) {
      debugPrint('[RENTAL] Get listing error: $e');
      return null;
    }
  }

  /// Get listings owned by a specific user
  static Future<List<Map<String, dynamic>>> getMyListings(String ownerId) async {
    final result = await _client
        .from(_table)
        .select('*')
        .eq('owner_id', ownerId)
        .neq('status', 'deleted')
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(result);
  }

  /// Toggle listing status (active/inactive)
  static Future<void> toggleStatus(String listingId, String currentStatus) async {
    final newStatus = currentStatus == 'active' ? 'inactive' : 'active';
    await _client
        .from(_table)
        .update({
          'status': newStatus,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', listingId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // OWNER INFO
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get owner info for a listing
  static Future<Map<String, dynamic>?> getOwnerInfo(String ownerId) async {
    try {
      final result = await _client
          .from('drivers')
          .select('id, name, email, phone, profile_image_url, rating, total_rides')
          .eq('id', ownerId)
          .single();
      return result;
    } catch (e) {
      debugPrint('[RENTAL] Get owner error: $e');
      return null;
    }
  }
}
