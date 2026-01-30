import 'dart:io';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

/// OTA Update Service - Custom DIY approach
/// Checks for updates from Supabase and downloads APK if available
class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  final SupabaseClient _client = SupabaseConfig.client;

  PackageInfo? _packageInfo;
  AppVersion? _latestVersion;
  bool _isDownloading = false;
  double _downloadProgress = 0;

  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;
  AppVersion? get latestVersion => _latestVersion;

  /// Initialize the service
  Future<void> initialize() async {
    _packageInfo = await PackageInfo.fromPlatform();
  }

  /// Check if an update is available
  /// Returns UpdateInfo if update available, null otherwise
  Future<UpdateInfo?> checkForUpdate() async {
    if (_packageInfo == null) {
      await initialize();
    }

    try {
      final response = await _client
          .from('app_versions')
          .select()
          .eq('app_name', 'toro_driver')
          .order('build_number', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      _latestVersion = AppVersion.fromJson(response);
      final currentBuild = int.tryParse(_packageInfo?.buildNumber ?? '0') ?? 0;

      if (_latestVersion!.buildNumber > currentBuild) {
        // Update available
        final isMandatory = _latestVersion!.isMandatory ||
            (_latestVersion!.minSupportedBuild != null &&
                currentBuild < _latestVersion!.minSupportedBuild!);

        return UpdateInfo(
          currentVersion: _packageInfo!.version,
          currentBuild: currentBuild,
          newVersion: _latestVersion!.version,
          newBuild: _latestVersion!.buildNumber,
          releaseNotes: _latestVersion!.releaseNotes,
          apkUrl: _latestVersion!.apkUrl,
          isMandatory: isMandatory,
        );
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Download and install update
  Future<bool> downloadAndInstall(String apkUrl, {
    void Function(double progress)? onProgress,
  }) async {
    if (_isDownloading) return false;
    if (!Platform.isAndroid) {
      return false;
    }

    _isDownloading = true;
    _downloadProgress = 0;

    try {
      // Get download directory
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/toro_driver_update.apk';
      final file = File(filePath);

      // Download with progress
      final request = http.Request('GET', Uri.parse(apkUrl));
      final response = await http.Client().send(request);

      final contentLength = response.contentLength ?? 0;
      final List<int> bytes = [];
      int downloaded = 0;

      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        downloaded += chunk.length;

        if (contentLength > 0) {
          _downloadProgress = downloaded / contentLength;
          onProgress?.call(_downloadProgress);
        }
      }

      await file.writeAsBytes(bytes);

      _isDownloading = false;
      _downloadProgress = 1;

      // Open APK for installation
      final result = await OpenFilex.open(filePath);

      return result.type == ResultType.done;
    } catch (e) {
      _isDownloading = false;
      return false;
    }
  }

  /// Show update dialog
  static Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) async {
    return showDialog(
      context: context,
      barrierDismissible: !info.isMandatory,
      builder: (context) => _UpdateDialog(info: info),
    );
  }
}

/// Information about an available update
class UpdateInfo {
  final String currentVersion;
  final int currentBuild;
  final String newVersion;
  final int newBuild;
  final String? releaseNotes;
  final String? apkUrl;
  final bool isMandatory;

  UpdateInfo({
    required this.currentVersion,
    required this.currentBuild,
    required this.newVersion,
    required this.newBuild,
    this.releaseNotes,
    this.apkUrl,
    this.isMandatory = false,
  });

  bool get hasApk => apkUrl != null && apkUrl!.isNotEmpty;
}

/// App version from database
class AppVersion {
  final String version;
  final int buildNumber;
  final String? apkUrl;
  final String? releaseNotes;
  final bool isMandatory;
  final int? minSupportedBuild;

  AppVersion({
    required this.version,
    required this.buildNumber,
    this.apkUrl,
    this.releaseNotes,
    this.isMandatory = false,
    this.minSupportedBuild,
  });

  factory AppVersion.fromJson(Map<String, dynamic> json) {
    return AppVersion(
      version: json['version'] as String? ?? '1.0.0',
      buildNumber: json['build_number'] as int? ?? 1,
      apkUrl: json['apk_url'] as String?,
      releaseNotes: json['release_notes'] as String?,
      isMandatory: json['is_mandatory'] as bool? ?? false,
      minSupportedBuild: json['min_supported_build'] as int?,
    );
  }
}

/// Update dialog widget
class _UpdateDialog extends StatefulWidget {
  final UpdateInfo info;

  const _UpdateDialog({required this.info});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  final _updateService = UpdateService();
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.info.isMandatory && !_downloading,
      child: AlertDialog(
        title: Row(
          children: [
            Icon(Icons.system_update, color: Colors.blue[700]),
            const SizedBox(width: 12),
            const Text('Nueva Version'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version ${widget.info.newVersion} disponible',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Tu version actual: ${widget.info.currentVersion}',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            if (widget.info.releaseNotes != null) ...[
              const SizedBox(height: 16),
              const Text('Novedades:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(widget.info.releaseNotes!, style: const TextStyle(fontSize: 14)),
            ],
            if (_downloading) ...[
              const SizedBox(height: 20),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text(
                'Descargando... ${(_progress * 100).toInt()}%',
                style: const TextStyle(fontSize: 12),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
            if (widget.info.isMandatory) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange[700], size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Esta actualizacion es obligatoria',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (!widget.info.isMandatory && !_downloading)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Mas tarde'),
            ),
          ElevatedButton.icon(
            onPressed: _downloading || !widget.info.hasApk ? null : _downloadUpdate,
            icon: _downloading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            label: Text(_downloading ? 'Descargando...' : 'Actualizar'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadUpdate() async {
    if (!widget.info.hasApk) return;

    setState(() {
      _downloading = true;
      _error = null;
    });

    final success = await _updateService.downloadAndInstall(
      widget.info.apkUrl!,
      onProgress: (progress) {
        setState(() => _progress = progress);
      },
    );

    if (!success && mounted) {
      setState(() {
        _downloading = false;
        _error = 'Error al descargar. Intenta de nuevo.';
      });
    }
  }
}
