import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Result of version check
class VersionCheckResult {
  final bool allowed;
  final String updateRequired; // 'none', 'soft', 'hard'
  final String? messageEn;
  final String? messageEs;
  final String? storeUrl;
  final List<String> deprecatedFeatures;

  VersionCheckResult({
    required this.allowed,
    required this.updateRequired,
    this.messageEn,
    this.messageEs,
    this.storeUrl,
    this.deprecatedFeatures = const [],
  });

  factory VersionCheckResult.fromJson(Map<String, dynamic> json) {
    return VersionCheckResult(
      allowed: json['allowed'] as bool? ?? true,
      updateRequired: json['update_required'] as String? ?? 'none',
      messageEn: json['message_en'] as String?,
      messageEs: json['message_es'] as String?,
      storeUrl: json['store_url'] as String?,
      deprecatedFeatures: (json['deprecated_features'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  bool get needsSoftUpdate => updateRequired == 'soft';
  bool get needsHardUpdate => updateRequired == 'hard';
  bool get isUpToDate => updateRequired == 'none';

  /// Get message based on locale
  String? getMessage(String locale) {
    if (locale.startsWith('es')) {
      return messageEs ?? messageEn;
    }
    return messageEn ?? messageEs;
  }
}

/// Service to check app version against server requirements
class VersionCheckService {
  static final VersionCheckService _instance = VersionCheckService._internal();
  factory VersionCheckService() => _instance;
  VersionCheckService._internal();

  final _client = Supabase.instance.client;

  /// Cached result to avoid repeated checks
  VersionCheckResult? _cachedResult;
  DateTime? _lastCheck;

  /// App info
  String? _appVersion;
  int? _buildNumber;
  String? _platform;

  /// Get current platform string
  String get _currentPlatform {
    if (_platform != null) return _platform!;
    if (kIsWeb) {
      _platform = 'web';
    } else if (Platform.isAndroid) {
      _platform = 'android';
    } else if (Platform.isIOS) {
      _platform = 'ios';
    } else {
      _platform = 'android'; // Default
    }
    return _platform!;
  }

  /// Initialize and load app info
  Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = info.version;
      _buildNumber = int.tryParse(info.buildNumber) ?? 1;
      debugPrint(
          '📱 VersionCheck: App v$_appVersion+$_buildNumber ($_currentPlatform)');
    } catch (e) {
      debugPrint('⚠️ VersionCheck: Could not get package info: $e');
      _appVersion = '1.0.0';
      _buildNumber = 1;
    }
  }

  /// Check version against server
  /// Returns cached result if checked within last 5 minutes
  Future<VersionCheckResult> checkVersion({
    bool forceCheck = false,
    String appName = 'toro_driver',
  }) async {
    // Return cached result if recent
    if (!forceCheck &&
        _cachedResult != null &&
        _lastCheck != null &&
        DateTime.now().difference(_lastCheck!).inMinutes < 5) {
      return _cachedResult!;
    }

    // Ensure we have app info
    if (_appVersion == null || _buildNumber == null) {
      await init();
    }

    try {
      // Read from app_versions table (simple, no RPC needed)
      final row = await _client
          .from('app_versions')
          .select()
          .eq('id', appName)
          .maybeSingle();

      if (row == null) {
        return VersionCheckResult(allowed: true, updateRequired: 'none');
      }

      final latestBuild = row['latest_build'] as int? ?? 0;
      final minBuild = row['min_build'] as int? ?? 0;
      final currentBuild = _buildNumber ?? 0;

      String updateRequired = 'none';
      bool allowed = true;

      if (currentBuild < minBuild) {
        // Below minimum - force update
        updateRequired = 'hard';
        allowed = false;
      } else if (currentBuild < latestBuild) {
        // Behind latest - soft update
        updateRequired = 'soft';
      }

      final result = VersionCheckResult(
        allowed: allowed,
        updateRequired: updateRequired,
        messageEn: row['message_en'] as String?,
        messageEs: row['message_es'] as String?,
        storeUrl: row['store_url'] as String?,
      );

      _cachedResult = result;
      _lastCheck = DateTime.now();

      debugPrint(
          'VersionCheck: build=$currentBuild latest=$latestBuild min=$minBuild -> $updateRequired');

      return result;
    } catch (e) {
      debugPrint('VersionCheck error: $e');
      // Fail open - allow app to continue if check fails
      return VersionCheckResult(
        allowed: true,
        updateRequired: 'none',
      );
    }
  }

  /// Open store URL for update
  Future<bool> openStoreForUpdate() async {
    final url = _cachedResult?.storeUrl;
    if (url == null) return false;

    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      }
    } catch (e) {
      debugPrint('⚠️ Could not open store: $e');
    }
    return false;
  }

  /// Check if a specific feature is deprecated
  bool isFeatureDeprecated(String featureName) {
    return _cachedResult?.deprecatedFeatures.contains(featureName) ?? false;
  }

  /// Get current app version string
  String get appVersion => _appVersion ?? 'unknown';

  /// Get current build number
  int get buildNumber => _buildNumber ?? 0;

  /// Clear cache (useful for testing or force refresh)
  void clearCache() {
    _cachedResult = null;
    _lastCheck = null;
  }
}
