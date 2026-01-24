import '../config/supabase_config.dart';
import '../core/logging/app_logger.dart';

/// Modelo para driver en ranking
class RankedDriver {
  final String id;
  final String name;
  final String? profileImageUrl;
  final int points;
  final int rank;
  final int? previousRank;
  final String? state;

  RankedDriver({
    required this.id,
    required this.name,
    this.profileImageUrl,
    required this.points,
    required this.rank,
    this.previousRank,
    this.state,
  });

  /// Cambio de posición respecto al período anterior
  int get rankChange {
    if (previousRank == null) return 0;
    return previousRank! - rank; // Positivo = subió, negativo = bajó
  }

  String get initial => name.isNotEmpty ? name[0].toUpperCase() : 'D';
}

/// Servicio para obtener rankings reales de Supabase
class RankingService {
  static final _supabase = SupabaseConfig.client;

  /// Obtener ranking general (todos los drivers)
  static Future<List<RankedDriver>> getRanking({
    required String period, // 'weekly', 'monthly', 'alltime'
    String? stateFilter, // Filtrar por estado (ej: 'Arizona', 'Texas')
    int limit = 50,
  }) async {
    try {
      AppLogger.log('RANKING SERVICE -> Fetching $period ranking');

      // Obtener drivers - ordenar por acceptance_rate (mayor es mejor)
      final response = await _supabase
          .from('drivers')
          .select('id, name, profile_image_url, total_rides, acceptance_rate, state, previous_rank, usa_rank, state_rank')
          .order('acceptance_rate', ascending: false, nullsFirst: false)
          .limit(limit);

      final drivers = (response as List).asMap().entries.map((entry) {
        final index = entry.key;
        final data = entry.value as Map<String, dynamic>;

        // Usar acceptance_rate de la base de datos
        final acceptanceRate = (data['acceptance_rate'] as num?)?.toDouble() ?? 0.0;
        final previousRank = (data['previous_rank'] as num?)?.toInt();
        final usaRank = (data['usa_rank'] as num?)?.toInt();

        // Convertir acceptance_rate (0.0-1.0) a porcentaje (0-100) para display
        // y usar como "points" para mostrar en la UI
        final acceptancePercentage = (acceptanceRate * 100).round();

        return RankedDriver(
          id: data['id'] as String,
          name: data['name'] as String? ?? 'Driver',
          profileImageUrl: data['profile_image_url'] as String?,
          points: acceptancePercentage,
          rank: usaRank ?? (index + 1),
          previousRank: previousRank,
          state: data['state'] as String?,
        );
      }).toList();

      // Si hay filtro por estado, reordenar
      if (stateFilter != null && stateFilter.isNotEmpty) {
        final filteredDrivers = drivers.where((d) => d.state == stateFilter).toList();
        // Reasignar ranks dentro del estado
        return filteredDrivers.asMap().entries.map((entry) {
          return RankedDriver(
            id: entry.value.id,
            name: entry.value.name,
            profileImageUrl: entry.value.profileImageUrl,
            points: entry.value.points,
            rank: entry.key + 1,
            previousRank: entry.value.previousRank,
            state: entry.value.state,
          );
        }).toList();
      }

      AppLogger.log('RANKING SERVICE -> Fetched ${drivers.length} drivers');
      return drivers;
    } catch (e) {
      AppLogger.error('RANKING SERVICE -> Error: $e');
      // Retornar datos de prueba si falla
      return _getMockData();
    }
  }

  /// Obtener posición del driver actual
  static Future<Map<String, dynamic>> getMyPosition(String driverId) async {
    try {
      // Obtener mi driver directamente
      final myDriverResponse = await _supabase
          .from('drivers')
          .select('id, acceptance_rate, total_rides, previous_rank, usa_rank')
          .eq('id', driverId)
          .maybeSingle();

      // Contar total de drivers
      final countResponse = await _supabase
          .from('drivers')
          .select('id');

      final totalDrivers = (countResponse as List).length;

      if (myDriverResponse == null) {
        return {'rank': 0, 'total': totalDrivers, 'points': 0, 'change': 0};
      }

      final totalRides = (myDriverResponse['total_rides'] as num?)?.toInt() ?? 0;
      final acceptanceRate = (myDriverResponse['acceptance_rate'] as num?)?.toDouble() ?? 0.0;

      // Convertir acceptance_rate (0.0-1.0) a porcentaje (0-100)
      final acceptancePercentage = (acceptanceRate * 100).round();

      // Sin viajes = sin ranking todavía
      final myRank = totalRides > 0
          ? ((myDriverResponse['usa_rank'] as num?)?.toInt() ?? totalDrivers)
          : totalDrivers + 1;

      final previousRank = (myDriverResponse['previous_rank'] as num?)?.toInt();

      return {
        'rank': myRank,
        'total': totalDrivers,
        'points': acceptancePercentage, // Ahora muestra acceptance rate %
        'change': previousRank != null ? previousRank - myRank : 0,
      };
    } catch (e) {
      AppLogger.error('RANKING SERVICE -> Error getting position: $e');
      return {
        'rank': 0,
        'total': 0,
        'points': 0,
        'change': 0,
      };
    }
  }

  /// Datos de prueba si la BD no tiene la estructura
  static List<RankedDriver> _getMockData() {
    return [
      RankedDriver(id: '1', name: 'Ana García', points: 98, rank: 1, previousRank: 1),
      RankedDriver(id: '2', name: 'Carlos M.', points: 95, rank: 2, previousRank: 3),
      RankedDriver(id: '3', name: 'Pedro López', points: 92, rank: 3, previousRank: 2),
      RankedDriver(id: '4', name: 'Roberto S.', points: 90, rank: 4, previousRank: 5),
      RankedDriver(id: '5', name: 'María L.', points: 88, rank: 5, previousRank: 4),
      RankedDriver(id: '6', name: 'Fernando G.', points: 85, rank: 6, previousRank: 9),
      RankedDriver(id: '7', name: 'Lucía P.', points: 83, rank: 7, previousRank: 6),
      RankedDriver(id: '8', name: 'Diego M.', points: 80, rank: 8, previousRank: 10),
      RankedDriver(id: '9', name: 'Sofía R.', points: 78, rank: 9, previousRank: 8),
      RankedDriver(id: '10', name: 'Juan C.', points: 75, rank: 10, previousRank: 7),
    ];
  }
}
