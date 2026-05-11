import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/bug_report_service.dart';
import '../providers/driver_provider.dart';
import '../utils/app_colors.dart';

/// Botón flotante de Bug Report con captura de pantalla
class BugReportButton extends StatelessWidget {
  final GlobalKey? screenshotKey;
  final String screenName;

  const BugReportButton({
    super.key,
    this.screenshotKey,
    required this.screenName,
  });

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      heroTag: 'bug_report_$screenName',
      backgroundColor: const Color(0xFFFF3B30).withValues(alpha: 0.9),
      onPressed: () => _showBugReportDialog(context),
      tooltip: 'Reportar Bug',
      child: const Icon(Icons.bug_report_rounded, color: Colors.white, size: 20),
    );
  }

  Future<void> _showBugReportDialog(BuildContext context) async {
    final service = BugReportService();
    Uint8List? screenshot;

    if (screenshotKey != null) {
      screenshot = await service.captureScreenshot(screenshotKey!);
    }

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => BugReportDialog(
        initialScreenshot: screenshot,
        screenName: screenName,
      ),
    );
  }
}

class BugReportDialog extends StatefulWidget {
  final Uint8List? initialScreenshot;
  final String screenName;

  const BugReportDialog({
    super.key,
    this.initialScreenshot,
    required this.screenName,
  });

  @override
  State<BugReportDialog> createState() => _BugReportDialogState();
}

class _BugReportDialogState extends State<BugReportDialog> {
  final _descController = TextEditingController();
  final _service = BugReportService();
  Uint8List? _screenshot;
  String _severity = 'medium';
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _screenshot = widget.initialScreenshot;
  }

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickFromGallery() async {
    final bytes = await _service.pickImageFromGallery();
    if (bytes != null) {
      setState(() => _screenshot = bytes);
    }
  }

  Future<void> _submit() async {
    if (_descController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor describe el problema')),
      );
      return;
    }

    setState(() => _submitting = true);

    final driverProvider = context.read<DriverProvider>();
    final userId = driverProvider.driver?.id ?? 'anonymous';

    final success = await _service.submitBugReport(
      userId: userId,
      description: _descController.text.trim(),
      screenName: widget.screenName,
      screenshotBytes: _screenshot,
      severity: _severity,
    );

    if (!mounted) return;

    setState(() => _submitting = false);

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle : Icons.error,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Text(success
                ? '¡Bug reportado! Gracias por ayudar 🐛'
                : 'Error al enviar reporte'),
          ],
        ),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bug_report_rounded, color: Color(0xFFFF3B30), size: 28),
                const SizedBox(width: 12),
                Text(
                  'Reportar Bug',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Pantalla: ${widget.screenName}',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),

            // Description
            TextField(
              controller: _descController,
              maxLines: 4,
              style: TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Describe el problema en detalle...',
                hintStyle: TextStyle(color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 16),

            // Severity
            Text('Severidad:', style: TextStyle(color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _SeverityChip(label: 'Baja', value: 'low', selected: _severity, onTap: (v) => setState(() => _severity = v)),
                _SeverityChip(label: 'Media', value: 'medium', selected: _severity, onTap: (v) => setState(() => _severity = v)),
                _SeverityChip(label: 'Alta', value: 'high', selected: _severity, onTap: (v) => setState(() => _severity = v)),
                _SeverityChip(label: 'Crítica', value: 'critical', selected: _severity, onTap: (v) => setState(() => _severity = v)),
              ],
            ),
            const SizedBox(height: 16),

            // Screenshot preview
            if (_screenshot != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: [
                    Image.memory(_screenshot!, height: 200, fit: BoxFit.cover, width: double.infinity),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => setState(() => _screenshot = null),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: _pickFromGallery,
                icon: const Icon(Icons.image_outlined),
                label: const Text('Subir captura desde galería'),
              ),
            const SizedBox(height: 20),

            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _submitting ? null : () => Navigator.pop(context),
                  child: Text('Cancelar', style: TextStyle(color: AppColors.textSecondary)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF3B30),
                    foregroundColor: Colors.white,
                  ),
                  child: _submitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Enviar Reporte'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SeverityChip extends StatelessWidget {
  final String label;
  final String value;
  final String selected;
  final ValueChanged<String> onTap;

  const _SeverityChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == selected;
    Color color = const Color(0xFF999999);
    if (value == 'low') color = Colors.green;
    if (value == 'medium') color = Colors.orange;
    if (value == 'high') color = Colors.deepOrange;
    if (value == 'critical') color = Colors.red;

    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : color,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
