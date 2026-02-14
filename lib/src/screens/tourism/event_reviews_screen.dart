import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/tourism_event_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';

/// Pantalla que muestra las resenas de un evento de turismo especifico.
///
/// Muestra un resumen con calificacion promedio, desglose por categoria,
/// porcentaje de recomendacion y etiquetas de mejora. Debajo lista las
/// resenas anonimas con estrellas, comentario y fecha.
class EventReviewsScreen extends StatefulWidget {
  final String eventId;
  final String? eventTitle;

  const EventReviewsScreen({
    super.key,
    required this.eventId,
    this.eventTitle,
  });

  @override
  State<EventReviewsScreen> createState() => _EventReviewsScreenState();
}

class _EventReviewsScreenState extends State<EventReviewsScreen> {
  final TourismEventService _eventService = TourismEventService();

  List<Map<String, dynamic>> _reviews = [];
  bool _isLoading = true;
  String? _error;

  // Aggregated data
  double _avgOverall = 0;
  double _avgDriver = 0;
  double _avgOrganizer = 0;
  double _avgVehicle = 0;
  int _totalReviews = 0;
  int _recommendPct = 0;
  List<MapEntry<String, int>> _sortedTags = [];

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final reviews = await _eventService.getEventReviews(widget.eventId);

      // Calculate aggregates
      double sumOverall = 0, sumDriver = 0, sumOrganizer = 0, sumVehicle = 0;
      int recommendCount = 0;
      final Map<String, int> tagCounts = {};

      for (final r in reviews) {
        sumOverall += (r['overall_rating'] as num?)?.toDouble() ?? 0;
        sumDriver += (r['driver_rating'] as num?)?.toDouble() ?? 0;
        sumOrganizer += (r['organizer_rating'] as num?)?.toDouble() ?? 0;
        sumVehicle += (r['vehicle_rating'] as num?)?.toDouble() ?? 0;
        if (r['would_recommend'] == true) recommendCount++;

        final tags = r['improvement_tags'];
        if (tags is List) {
          for (final tag in tags) {
            final tagStr = tag.toString();
            tagCounts[tagStr] = (tagCounts[tagStr] ?? 0) + 1;
          }
        }
      }

      final total = reviews.length;
      final sorted = tagCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      if (mounted) {
        setState(() {
          _reviews = reviews;
          _totalReviews = total;
          _avgOverall = total > 0 ? sumOverall / total : 0;
          _avgDriver = total > 0 ? sumDriver / total : 0;
          _avgOrganizer = total > 0 ? sumOrganizer / total : 0;
          _avgVehicle = total > 0 ? sumVehicle / total : 0;
          _recommendPct =
              total > 0 ? (recommendCount / total * 100).round() : 0;
          _sortedTags = sorted;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _shareReport() {
    HapticService.mediumImpact();

    final buffer = StringBuffer();
    buffer.writeln(
        'Reporte de Resenas - ${widget.eventTitle ?? "Evento"}');
    buffer.writeln('=' * 40);
    buffer.writeln(
        'Calificacion general: ${_avgOverall.toStringAsFixed(1)}/5');
    buffer.writeln('Conductor: ${_avgDriver.toStringAsFixed(1)}/5');
    buffer.writeln('Organizador: ${_avgOrganizer.toStringAsFixed(1)}/5');
    buffer.writeln('Vehiculo: ${_avgVehicle.toStringAsFixed(1)}/5');
    buffer.writeln('Total de resenas: $_totalReviews');
    buffer.writeln('Recomendarian: $_recommendPct%');
    buffer.writeln();

    if (_sortedTags.isNotEmpty) {
      buffer.writeln('Sugerencias de mejora:');
      for (final tag in _sortedTags.take(5)) {
        buffer.writeln('  - ${tag.key} (${tag.value})');
      }
      buffer.writeln();
    }

    if (_reviews.any((r) =>
        r['comment'] != null &&
        r['comment'].toString().trim().isNotEmpty)) {
      buffer.writeln('Comentarios anonimos:');
      for (final r in _reviews) {
        final comment = r['comment']?.toString().trim();
        if (comment != null && comment.isNotEmpty) {
          final rating =
              (r['overall_rating'] as num?)?.toDouble() ?? 0;
          buffer.writeln(
              '  [${'*' * rating.round()}] $comment');
        }
      }
    }

    Share.share(buffer.toString());
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      const months = [
        '',
        'Ene',
        'Feb',
        'Mar',
        'Abr',
        'May',
        'Jun',
        'Jul',
        'Ago',
        'Sep',
        'Oct',
        'Nov',
        'Dic',
      ];
      return '${date.day} ${months[date.month]} ${date.year}';
    } catch (_) {
      return '';
    }
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.background,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      )
                    : _error != null
                        ? _buildErrorState()
                        : _totalReviews == 0
                            ? _buildEmptyState()
                            : _buildContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(
            color: AppColors.border.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              HapticService.lightImpact();
              Navigator.pop(context);
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.border.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: AppColors.textSecondary,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Resenas del Evento',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (widget.eventTitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.eventTitle!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (_totalReviews > 0)
            GestureDetector(
              onTap: _shareReport,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.share_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.card,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.rate_review_outlined,
                size: 48,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Aun no hay resenas para este evento',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Cuando los pasajeros dejen resenas, apareceran aqui de forma anonima.',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 48,
            color: AppColors.error,
          ),
          const SizedBox(height: 16),
          const Text(
            'Error al cargar resenas',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _loadReviews,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return RefreshIndicator(
      onRefresh: _loadReviews,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSummaryCard(),
          const SizedBox(height: 16),
          if (_sortedTags.isNotEmpty) ...[
            _buildImprovementTags(),
            const SizedBox(height: 16),
          ],
          _buildDownloadButton(),
          const SizedBox(height: 20),
          // Section title
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Resenas ($_totalReviews)',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          // Review list
          for (final review in _reviews) _buildReviewCard(review),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.border.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          // Big overall rating
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _avgOverall.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w800,
                  color: AppColors.star,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStarRow(_avgOverall, size: 24),
                  const SizedBox(height: 4),
                  Text(
                    '$_totalReviews resenas',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Recommend percentage
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.thumb_up_rounded,
                  color: AppColors.success,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  '$_recommendPct% recomendaria',
                  style: const TextStyle(
                    color: AppColors.success,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 16),
          // Category ratings
          _buildCategoryRow(
              Icons.person, 'Conductor', _avgDriver),
          const SizedBox(height: 10),
          _buildCategoryRow(
              Icons.business, 'Organizador', _avgOrganizer),
          const SizedBox(height: 10),
          _buildCategoryRow(
              Icons.directions_bus, 'Vehiculo', _avgVehicle),
        ],
      ),
    );
  }

  Widget _buildCategoryRow(
      IconData icon, String label, double rating) {
    return Row(
      children: [
        Icon(icon, color: AppColors.textTertiary, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ),
        _buildStarRow(rating, size: 16),
        const SizedBox(width: 8),
        SizedBox(
          width: 30,
          child: Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildStarRow(double rating, {double size = 20}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starValue = index + 1;
        if (rating >= starValue) {
          return Icon(Icons.star_rounded,
              color: AppColors.star, size: size);
        } else if (rating >= starValue - 0.5) {
          return Icon(Icons.star_half_rounded,
              color: AppColors.star, size: size);
        } else {
          return Icon(Icons.star_outline_rounded,
              color: AppColors.textTertiary, size: size);
        }
      }),
    );
  }

  Widget _buildImprovementTags() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.border.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lightbulb_outline,
                  color: AppColors.warning, size: 18),
              SizedBox(width: 8),
              Text(
                'Sugerencias de mejora',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _sortedTags.take(8).map((tag) {
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color:
                      AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.warning
                        .withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  '${tag.key} (${tag.value})',
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadButton() {
    return GestureDetector(
      onTap: _shareReport,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.3),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.download_rounded,
                color: AppColors.primary, size: 20),
            SizedBox(width: 8),
            Text(
              'Descargar Reporte',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> review) {
    final overallRating =
        (review['overall_rating'] as num?)?.toDouble() ?? 0;
    final comment = review['comment'] as String?;
    final createdAt = review['created_at'] as String?;
    final tags = review['improvement_tags'] as List?;
    final wouldRecommend =
        review['would_recommend'] as bool? ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.border.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Rating + date row
          Row(
            children: [
              _buildStarRow(overallRating, size: 18),
              const SizedBox(width: 8),
              Text(
                overallRating.toStringAsFixed(1),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (wouldRecommend)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color:
                        AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.thumb_up,
                          color: AppColors.success, size: 12),
                      SizedBox(width: 4),
                      Text(
                        'Recomienda',
                        style: TextStyle(
                          color: AppColors.success,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              Text(
                _formatDate(createdAt),
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          // Comment
          if (comment != null && comment.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              comment,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
          // Tags
          if (tags != null && tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: tags.map((tag) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.textTertiary
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    tag.toString(),
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
