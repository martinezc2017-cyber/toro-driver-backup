import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../config/supabase_config.dart';

class BugReportService {
  static final BugReportService _instance = BugReportService._internal();
  factory BugReportService() => _instance;
  BugReportService._internal();

  final SupabaseClient _client = SupabaseConfig.client;
  final ImagePicker _picker = ImagePicker();

  /// Captura screenshot de un widget (RepaintBoundary)
  Future<Uint8List?> captureScreenshot(GlobalKey screenshotKey) async {
    try {
      final boundary = screenshotKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('Error capturing screenshot: $e');
      return null;
    }
  }

  /// Permite al usuario elegir imagen de galería
  Future<Uint8List?> pickImageFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (image == null) return null;
      return await image.readAsBytes();
    } catch (e) {
      debugPrint('Error picking image: $e');
      return null;
    }
  }

  /// Sube la imagen a Supabase Storage
  Future<String?> uploadScreenshot(Uint8List bytes, String userId) async {
    try {
      final fileName = 'bug-${DateTime.now().millisecondsSinceEpoch}.png';
      final path = 'bugs/$userId/$fileName';

      await _client.storage
          .from('bug-reports')
          .uploadBinary(path, bytes, fileOptions: const FileOptions(
            contentType: 'image/png',
            upsert: false,
          ));

      final url = _client.storage.from('bug-reports').getPublicUrl(path);
      return url;
    } catch (e) {
      debugPrint('Error uploading screenshot: $e');
      return null;
    }
  }

  /// Obtiene info del dispositivo
  Future<Map<String, dynamic>> getDeviceInfo() async {
    final info = <String, dynamic>{};
    try {
      final deviceInfo = DeviceInfoPlugin();
      final packageInfo = await PackageInfo.fromPlatform();

      info['app_version'] = packageInfo.version;
      info['build_number'] = packageInfo.buildNumber;

      if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        info['platform'] = 'iOS';
        info['os_version'] = iosInfo.systemVersion;
        info['device_model'] = iosInfo.utsname.machine;
        info['device_name'] = iosInfo.name;
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        info['platform'] = 'Android';
        info['os_version'] = androidInfo.version.release;
        info['device_model'] = androidInfo.model;
        info['device_name'] = androidInfo.brand;
      }
    } catch (e) {
      debugPrint('Error getting device info: $e');
    }
    return info;
  }

  /// Envía un bug report completo
  Future<bool> submitBugReport({
    required String userId,
    required String description,
    required String screenName,
    Uint8List? screenshotBytes,
    String? severity = 'medium',
    Map<String, dynamic>? extraData,
  }) async {
    try {
      String? screenshotUrl;
      if (screenshotBytes != null) {
        screenshotUrl = await uploadScreenshot(screenshotBytes, userId);
      }

      final deviceInfo = await getDeviceInfo();

      await _client.from('bug_reports').insert({
        'user_id': userId,
        'description': description,
        'screen_name': screenName,
        'screenshot_url': screenshotUrl,
        'severity': severity,
        'device_info': deviceInfo,
        'extra_data': extraData,
        'status': 'open',
        'created_at': DateTime.now().toIso8601String(),
      });

      return true;
    } catch (e) {
      debugPrint('Error submitting bug report: $e');
      return false;
    }
  }
}
