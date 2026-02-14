import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/tourism_event_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/haptic_service.dart';

/// Pantalla que muestra el dashboard de calificaciones del conductor
/// a traves de todos los eventos de turismo completados.
///
/// Incluye calificacion general promedio con estrellas animadas,
/// cuadricula de estadisticas, tendencia de ultimos eventos,
/// sugerencias de mejora principales y credenciales/insignias ganadas.
class MyRatingsScreen extends StatefulWidget {
  const MyRatingsScreen({super.key});

  @override
  State<MyRatingsScreen> createState() => _MyRatingsScreenState();
}

class _MyRatingsScreenState extends State<MyRatingsScreen>
    with SingleTickerProviderStateMixin {
  final TourismEventService _eventService = TourismEventService();

  bool _isLoading = true;
  String? _error;

  // Aggregated data
  double _avgOverall = 0;
  double _avgDriver = 0;
  int _totalReviews = 0;
  int _totalEvents = 0;
  int _recommendPct = 0;
  List<Map<String, dynamic>> _topTags = [];
  List<Map<String, dynamic>> _recentEvents = [];

  // Animation
  late AnimationController _animController;
  late Animation<double> _starAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _starAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.elasticOut,
    );
    _loadRatings();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadRatings() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('No autenticado');
      }

      final results = await Future.wait([
        _eventService.getMyAverageRatings(userId),
        _eventService.getRecentEventRatings(userId, limit: 5),
      ]);

      final ratings = results[0] as Map<String, dynamic>;
      final recent = results[1] as List<Map<String, dynamic>>;

      if (mounted) {
        setState(() {
          _avgOverall =
              (ratings['avg_overall'] as num?)?.toDouble() ?? 0;
          _avgDriver =
              (ratings['avg_driver'] as num?)?.toDouble() ?? 0;
          _totalReviews =
              (ratings['total_reviews'] as num?)?.toInt() ?? 0;
          _totalEvents =
              (ratings['total_events'] as num?)?.toInt() ?? 0;
          _recommendPct =
              (ratings['recommend_pct'] as num?)?.toInt() ?? 0;
          _topTags = List<Map<String, dynamic>>.from(
            ratings['improvement_tags'] ?? [],
          );
          _recentEvents = recent;
          _isLoading = false;
        });
        _animController.forward();
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

  // ---------------------------------------------------------------------------
  // Badge logic
  // ---------------------------------------------------------------------------

  List<Map<String, dynamic>> _getBadges() {
    final badges = <Map<String, dynamic>>[];

    if (_avgOverall >= 4.8 && _totalReviews >= 10) {
      badges.add({
        'icon': Icons.workspace_premium,
        'label': 'Excelencia',
        'color': AppColors.gold,
        'description': 'Promedio >= 4.8 con 10+ resenas',
      });
    }
    if (_avgOverall >= 4.5 && _totalReviews >= 5) {
      badges.add({
        'icon': Icons.star_rounded,
        'label': 'Destacado',
        'color': AppColors.star,
        'description': 'Promedio >= 4.5 con 5+ resenas',
      });
    }
    if (_recommendPct >= 90 && _totalReviews >= 5) {
      badges.add({
        'icon': Icons.thumb_up_rounded,
        'label': 'Recomendado',
        'color': AppColors.success,
        'description': '90%+ de pasajeros te recomiendan',
      });
    }
    if (_totalEvents >= 10) {
      badges.add({
        'icon': Icons.emoji_events_rounded,
        'label': 'Veterano',
        'color': AppColors.purple,
        'description': '10+ eventos completados',
      });
    }
    if (_totalEvents >= 1 && _totalReviews == 0) {
      badges.add({
        'icon': Icons.rocket_launch_rounded,
        'label': 'Nuevo',
        'color': AppColors.info,
        'description': 'Recien comenzando',
      });
    }

    return badges;
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
          const Expanded(
            child: Text(
              'Mis Calificaciones',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              HapticService.lightImpact();
              _loadRatings();
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.refresh,
                color: AppColors.primary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline,
              size: 48, color: AppColors.error),
          const SizedBox(height: 16),
          const Text(
            'Error al cargar calificaciones',
            style: TextStyle(
                fontSize: 16, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _loadRatings,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final badges = _getBadges();

    return RefreshIndicator(
      onRefresh: _loadRatings,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildOverallRatingCard(),
          const SizedBox(height: 16),
          _buildStatsGrid(),
          const SizedBox(height: 16),
          if (_recentEvents.isNotEmpty) ...[
            _buildTrendSection(),
            const SizedBox(height: 16),
          ],
          if (_topTags.isNotEmpty) ...[
            _buildImprovementSection(),
            const SizedBox(height: 16),
          ],
          if (badges.isNotEmpty) _buildBadgesSection(badges),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildOverallRatingCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.card, AppColors.cardSecondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.star.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.star.withValues(alpha: 0.08),
            blurRadius: 20,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Calificacion General',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          // Animated rating number
          AnimatedBuilder(
            animation: _starAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: 0.5 + (_starAnimation.value * 0.5),
                child: child,
              );
            },
            child: Text(
              _avgOverall.toStringAsFixed(1),
              style: const TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.w800,
                color: AppColors.star,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Animated stars
          AnimatedBuilder(
            animation: _starAnimation,
            builder: (context, child) {
              return Opacity(
                opacity:
                    _starAnimation.value.clamp(0.0, 1.0),
                child: child,
              );
            },
            child: _buildStarRow(_avgOverall, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            'Basado en $_totalReviews resenas',
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          // Category averages row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildMiniCategoryStat(
                  'Conductor', _avgDriver, AppColors.primary),
              Container(
                width: 1,
                height: 30,
                color: AppColors.border,
              ),
              _buildMiniCategoryStat(
                  'Recomienda', _recommendPct.toDouble(),
                  AppColors.success,
                  isPercent: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniCategoryStat(
      String label, double value, Color color,
      {bool isPercent = false}) {
    return Column(
      children: [
        Text(
          isPercent
              ? '${value.toInt()}%'
              : value.toStringAsFixed(1),
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 12,
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

  Widget _buildStatsGrid() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            Icons.reviews_rounded,
            '$_totalReviews',
            'Resenas recibidas',
            AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            Icons.event_available_rounded,
            '$_totalEvents',
            'Eventos completados',
            AppColors.success,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTrendSection() {
    return Container(
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
              Icon(Icons.trending_up_rounded,
                  color: AppColors.primaryCyan, size: 18),
              SizedBox(width: 8),
              Text(
                'Ultimos 5 eventos',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (int i = 0; i < _recentEvents.length; i++) ...[
            _buildTrendRow(_recentEvents[i]),
            if (i < _recentEvents.length - 1)
              const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildTrendRow(Map<String, dynamic> event) {
    final title = event['title'] as String? ?? 'Evento';
    final rating =
        (event['avg_overall_rating'] as num?)?.toDouble() ?? 0;
    final reviews =
        (event['total_reviews'] as num?)?.toInt() ?? 0;
    final barWidth = (rating / 5.0).clamp(0.0, 1.0);

    Color barColor;
    if (rating >= 4.5) {
      barColor = AppColors.success;
    } else if (rating >= 3.5) {
      barColor = AppColors.primary;
    } else if (rating >= 2.5) {
      barColor = AppColors.warning;
    } else {
      barColor = AppColors.error;
    }

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(
            title,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 4,
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(4),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: barWidth,
              child: Container(
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 32,
          child: Text(
            rating.toStringAsFixed(1),
            style: TextStyle(
              color: barColor,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 30,
          child: Text(
            '($reviews)',
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 11,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildImprovementSection() {
    return Container(
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
                'Areas de mejora principales',
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
            children: _topTags.map((tagData) {
              final tag = tagData['tag'] as String? ?? '';
              final count =
                  (tagData['count'] as num?)?.toInt() ?? 0;
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.warning
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.warning
                        .withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  '$tag ($count)',
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

  Widget _buildBadgesSection(
      List<Map<String, dynamic>> badges) {
    return Container(
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
              Icon(Icons.military_tech_rounded,
                  color: AppColors.gold, size: 18),
              SizedBox(width: 8),
              Text(
                'Credenciales obtenidas',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (int i = 0; i < badges.length; i++) ...[
            _buildBadgeRow(badges[i]),
            if (i < badges.length - 1) ...[
              const SizedBox(height: 10),
              Divider(
                color:
                    AppColors.border.withValues(alpha: 0.2),
                height: 1,
              ),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildBadgeRow(Map<String, dynamic> badge) {
    final icon = badge['icon'] as IconData;
    final label = badge['label'] as String;
    final color = badge['color'] as Color;
    final description = badge['description'] as String;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.2),
                blurRadius: 8,
              ),
            ],
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
