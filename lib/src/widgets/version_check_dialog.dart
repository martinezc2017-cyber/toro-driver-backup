import 'package:flutter/material.dart';

import '../services/version_check_service.dart';

/// Dialog shown when app needs update
class VersionCheckDialog extends StatelessWidget {
  final VersionCheckResult result;
  final VoidCallback? onUpdate;
  final VoidCallback? onLater;

  const VersionCheckDialog({
    super.key,
    required this.result,
    this.onUpdate,
    this.onLater,
  });

  /// Show update dialog
  /// Returns true if user chose to update, false otherwise
  static Future<bool?> show(
    BuildContext context,
    VersionCheckResult result,
  ) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: !result.needsHardUpdate,
      builder: (context) => VersionCheckDialog(
        result: result,
        onUpdate: () {
          Navigator.of(context).pop(true);
          VersionCheckService().openStoreForUpdate();
        },
        onLater: result.needsHardUpdate
            ? null
            : () => Navigator.of(context).pop(false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isHardUpdate = result.needsHardUpdate;

    // Use theme colors
    final errorColor = colorScheme.error;

    return PopScope(
      canPop: !isHardUpdate,
      child: AlertDialog(
        backgroundColor: colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              isHardUpdate ? Icons.error_outline : Icons.system_update,
              color: isHardUpdate ? errorColor : colorScheme.primary,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isHardUpdate ? 'Actualización Requerida' : 'Actualización Disponible',
                style: theme.textTheme.titleMedium,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.getMessage(locale) ??
                  (isHardUpdate
                      ? 'Tu versión de la app ya no es compatible. Por favor actualiza para continuar.'
                      : 'Una nueva versión está disponible. Actualiza para una mejor experiencia.'),
              style: theme.textTheme.bodyMedium,
            ),
            if (isHardUpdate) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: errorColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: errorColor.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: errorColor, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No puedes continuar sin actualizar.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: errorColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (!isHardUpdate && onLater != null)
            TextButton(
              onPressed: onLater,
              child: Text(
                'Más Tarde',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ),
          ElevatedButton(
            onPressed: onUpdate,
            style: ElevatedButton.styleFrom(
              backgroundColor: isHardUpdate ? errorColor : colorScheme.primary,
              foregroundColor: isHardUpdate ? colorScheme.onError : colorScheme.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Actualizar Ahora'),
          ),
        ],
      ),
    );
  }
}
