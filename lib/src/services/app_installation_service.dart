import 'dart:convert';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/supabase_config.dart';

class AppInstallationService {
  AppInstallationService._();

  static final AppInstallationService instance = AppInstallationService._();
  static const _deviceIdKey = 'toro_device_id';

  Future<void> recordOpen() => _record(countOpen: true);

  Future<void> identifyAuthenticatedDriver() => _record(countOpen: false);

  Future<void> _record({required bool countOpen}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var installationId = prefs.getString(_deviceIdKey);
      if (installationId == null || installationId.length < 8) {
        installationId =
            '${_platform()}_${DateTime.now().millisecondsSinceEpoch}_${Random.secure().nextInt(0x7fffffff)}';
        await prefs.setString(_deviceIdKey, installationId);
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final deviceInfo = await DeviceInfoPlugin().deviceInfo;
      final deviceData = deviceInfo.data;
      final location = await _installationLocation();

      await SupabaseConfig.client.rpc(
        'record_app_installation',
        params: {
          'p_installation_id': installationId,
          'p_app_role': 'driver',
          'p_platform': _platform(),
          'p_app_version': packageInfo.version,
          'p_build_number': packageInfo.buildNumber,
          'p_device_model': _firstValue(deviceData, const [
            'model',
            'marketingName',
            'productName',
            'name',
            'browserName',
          ]),
          'p_os_version': _firstValue(deviceData, const [
            'version.release',
            'systemVersion',
            'displayVersion',
            'osRelease',
            'userAgent',
          ]),
          'p_country_code': location['country_code'],
          'p_state_code': location['state_code'],
          'p_city': location['city'],
          'p_latitude': location['latitude'],
          'p_longitude': location['longitude'],
          'p_location_source': location['location_source'],
          'p_count_open': countOpen,
        },
      );
    } catch (error) {
      debugPrint('[APP_INSTALLATION] Driver telemetry unavailable: $error');
    }
  }

  Future<Map<String, dynamic>> _profileLocation() async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return const {};

    final result = <String, dynamic>{};
    try {
      final profile = await SupabaseConfig.client
          .from('profiles')
          .select('country_code, city, signup_lat, signup_lng')
          .eq('id', userId)
          .maybeSingle();
      if (profile != null) {
        result.addAll({
          'country_code': profile['country_code'],
          'city': profile['city'],
          'latitude': profile['signup_lat'],
          'longitude': profile['signup_lng'],
          'location_source': 'profile',
        });
      }
    } catch (_) {}
    try {
      final driver = await SupabaseConfig.client
          .from('drivers')
          .select('country_code, state_code')
          .eq('user_id', userId)
          .maybeSingle();
      if (driver != null) {
        result['country_code'] =
            driver['country_code'] ?? result['country_code'];
        result['state_code'] = driver['state_code'];
        result['location_source'] = 'driver_profile';
      }
    } catch (_) {}
    return result;
  }

  Future<Map<String, dynamic>> _installationLocation() async {
    final result = await _profileLocation();
    final needsApproximation =
        result['country_code'] == null ||
        result['state_code'] == null ||
        result['city'] == null;
    if (!needsApproximation) return result;

    try {
      final response = await http
          .get(
            Uri.parse(
              'https://ipwho.is/?fields=success,country_code,region_code,city,latitude,longitude',
            ),
          )
          .timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return result;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['success'] != true) return result;

      var usedIp = false;
      void fill(String key, dynamic value) {
        if (result[key] == null && value != null) {
          result[key] = value;
          usedIp = true;
        }
      }

      fill('country_code', data['country_code']);
      fill('state_code', data['region_code']);
      fill('city', data['city']);
      fill('latitude', data['latitude']);
      fill('longitude', data['longitude']);
      if (usedIp) {
        result['location_source'] = result['location_source'] == null
            ? 'ip'
            : '${result['location_source']}_ip';
      }
    } catch (_) {}
    return result;
  }

  static String? _firstValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      dynamic value = data;
      for (final part in key.split('.')) {
        if (value is! Map || !value.containsKey(part)) {
          value = null;
          break;
        }
        value = value[part];
      }
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  static String _platform() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'unknown',
    };
  }
}
