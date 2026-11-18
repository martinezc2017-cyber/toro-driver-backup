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

  /// Ficha de TORO Driver en el App Store.
  static const String appStoreUrl =
      'https://apps.apple.com/app/toro-driver/id6760872144';

  /// Renglón de `app_versions` que manda en cada plataforma.
  ///
  /// iOS tiene el suyo (`toro_driver_ios`). Antes las dos plataformas leían el
  /// mismo renglón, y ese renglón sigue los lanzamientos de Android: cada vez
  /// que salía una versión de Android, el iPhone —y el revisor de Apple, que
  /// siempre trae una versión que todavía no está publicada— veía "actualiza la
  /// app" con un botón que abría Google Play. Apple lo rechaza (2.3.10) y,
  /// si el aviso era obligatorio, el revisor ni siquiera podía entrar.
  ///
  /// Si el renglón de iOS no existe, la app se considera al día.
  static String rowIdFor(String platform, String appName) =>
      platform == 'ios' ? '${appName}_ios' : appName;

  /// A qué tienda manda el botón de actualizar.
  ///
  /// En iOS SIEMPRE es el App Store: aunque en la base alguien capture por
  /// error un enlace de otra tienda, el iPhone nunca lo abre.
  static String? resolveStoreUrl(String platform, String? urlFromDb) {
    if (platform != 'ios') return urlFromDb;
    final host = Uri.tryParse(urlFromDb ?? '')?.host.toLowerCase() ?? '';
    final isAppleStore = host == 'apps.apple.com' || host == 'itunes.apple.com';
    return isAppleStore ? urlFromDb : appStoreUrl;
  }

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
      // Read from app_versions table (simple, no RPC needed).
      // Cada plataforma lee SU renglón: ver [rowIdFor].
      final row = await _client
          .from('app_versions')
          .select()
          .eq('id', rowIdFor(_currentPlatform, appName))
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
        storeUrl: resolveStoreUrl(
          _currentPlatform,
          row['store_url'] as String?,
        ),
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
