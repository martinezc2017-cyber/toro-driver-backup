import 'package:flutter/material.dart';
import '../services/navigation_service.dart';
import '../services/directions_service.dart';
import '../models/ride_model.dart';
import 'maneuver_arrow.dart';

/// Widget de UI de navegación turn-by-turn estilo Google Maps
class NavigationUI extends StatelessWidget {
  final NavigationState state;
  final VoidCallback? onClose;
  final VoidCallback? onMute;
  final VoidCallback? onOverview;
  final VoidCallback? onShowSteps;
  final VoidCallback? onCallPassenger; // Llamar al pasajero
  final bool isMuted;
  final bool isOverviewMode;
  final double? currentSpeed;
  final double? speedLimit;
  final String? currentStreetName;
  final String? currentCounty;
  final String? gpsHighwayShield;
  final bool hasTolls;
  final int incidentCount;
  // Información del viaje
  final RideModel? ride;

  // Distancia en metros para mostrar la sub-maniobra "Después"
  static const double _subManeuverDistance = 100.0;

  const NavigationUI({
    super.key,
    required this.state,
    this.onClose,
    this.onMute,
    this.onOverview,
    this.onShowSteps,
    this.onCallPassenger,
    this.isMuted = false,
    this.isOverviewMode = false,
    this.currentSpeed,
    this.speedLimit,
    this.currentStreetName,
    this.currentCounty,
    this.gpsHighwayShield,
    this.hasTolls = false,
    this.incidentCount = 0,
    this.ride,
  });

  /// Determina si el nivel 2 (sub-maniobra "Después") debe mostrarse
  bool get _shouldShowSubManeuver {
    final type = state.maneuverType;
    if (type == 'arrive') return true;
    return state.distanceToNextManeuver <= _subManeuverDistance;
  }

  /// Extrae solo el nombre de la calle de una instrucción
  /// Ej: "Gire a la izquierda en Main Street" -> "Main Street"
  String _extractStreetName(String instruction) {
    // Patrones comunes a remover
    final patterns = [
      RegExp(r'^(Gire|Gira|Turn|Take)\s+(a la\s+)?(izquierda|derecha|left|right)\s+(en|on|onto|hacia)\s+', caseSensitive: false),
      RegExp(r'^(Continúe|Continue|Sigue|Siga)\s+(por|on|recto|straight)\s+(en\s+)?', caseSensitive: false),
      RegExp(r'^(Tome|Take)\s+(la\s+)?(salida|exit|rampa|ramp)\s+(hacia|to|on)\s+', caseSensitive: false),
      RegExp(r'^(Incorpórese|Merge)\s+(a|onto|into)\s+', caseSensitive: false),
      RegExp(r'^(En la glorieta|At the roundabout)[,\s]+(tome|take)\s+(la\s+)?\d+[ªa]?\s+(salida|exit)\s+(hacia|to|on)\s+', caseSensitive: false),
      RegExp(r'^(Manténgase|Keep|Stay)\s+(a la\s+)?(izquierda|derecha|left|right)\s+(en|on|hacia)\s+', caseSensitive: false),
    ];

    String result = instruction;
    for (final pattern in patterns) {
      result = result.replaceFirst(pattern, '');
    }

    // Si no cambió, intentar extraer después de "en", "on", "onto"
    if (result == instruction) {
      final match = RegExp(r'\s+(en|on|onto|hacia)\s+(.+)$', caseSensitive: false).firstMatch(instruction);
      if (match != null && match.group(2) != null) {
        result = match.group(2)!;
      }
    }

    return result.trim().isEmpty ? instruction : result.trim();
  }

  @override
  Widget build(BuildContext context) {
    if (!state.isNavigating) return const SizedBox.shrink();

    return Stack(
      children: [
        // Banner superior compacto (nivel 1 + nivel 2 condicional)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: _buildCompactManeuverBanner(),
          ),
        ),

        // Indicador de tunel / dead reckoning
        if (state.isDeadReckoning)
          Positioned(
            top: 120,
            left: 0,
            right: 0,
            child: _buildDeadReckoningIndicator(),
          ),

        // Nivel 3: Nombre de calle actual (GPS) - arriba del panel inferior
        if ((currentStreetName != null && currentStreetName!.isNotEmpty) || currentCounty != null)
          Positioned(
            bottom: ride != null ? 145 : 70, // Más arriba si hay info de ride
            left: 0,
            right: 0,
            child: _buildStreetNameBar(),
          ),

        // Panel inferior COMPACTO
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildCompactBottomPanel(),
        ),
      ],
    );
  }

  /// Barra minimalista con calle actual del GPS
  Widget _buildStreetNameBar() {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Shield si es highway
            if (gpsHighwayShield != null && gpsHighwayShield!.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getShieldColor(gpsHighwayShield!),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  gpsHighwayShield!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            // Nombre de calle
            Flexible(
              child: Text(
                currentStreetName ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getShieldColor(String shield) {
    final upper = shield.toUpperCase();
    if (upper.startsWith('I-')) return const Color(0xFF1A3D7C); // Interstate azul
    if (upper.startsWith('US')) return const Color(0xFF1A3D7C);
    if (upper.contains('LOOP') || upper.startsWith('AZ') || upper.startsWith('SR')) {
      return const Color(0xFF2E7D32); // State route verde
    }
    return Colors.grey.shade700;
  }

  /// Badge para shield de highway del GPS
  Widget _buildGpsShieldBadge(String shield) {
    final text = shield.toUpperCase();
    Color bgColor;
    Color textColor = Colors.white;

    if (text.startsWith('I-')) {
      bgColor = const Color(0xFF1A3D7C); // Azul interstate
    } else if (text.startsWith('US')) {
      bgColor = Colors.white;
      textColor = Colors.black;
    } else if (text.contains('LOOP') || text.startsWith('AZ')) {
      bgColor = const Color(0xFF2E7D32); // Verde state route
    } else {
      bgColor = Colors.grey[700]!;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: bgColor == Colors.white
            ? Border.all(color: Colors.black, width: 1)
            : null,
      ),
      child: Text(
        shield,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// Construye un badge para shield de carretera (I-10, US-60, AZ-202)
  Widget _buildShieldBadge(BannerComponent shield) {
    // Detectar tipo de carretera para color
    final text = shield.text;
    Color bgColor;
    Color textColor = Colors.white;

    if (text.startsWith('I-') || text.contains('Interstate')) {
      // Interstate - rojo/azul
      bgColor = const Color(0xFF1A3D7C); // Azul interstate
    } else if (text.startsWith('US-') || text.startsWith('US ')) {
      // US Route - blanco con borde negro
      bgColor = Colors.white;
      textColor = Colors.black;
    } else if (text.contains('Loop') || text.contains('202') || text.contains('101')) {
      // State route / Loop - verde
      bgColor = const Color(0xFF2E7D32);
    } else {
      // Default - gris
      bgColor = Colors.grey[700]!;
    }

    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: bgColor == Colors.white
            ? Border.all(color: Colors.black, width: 1)
            : null,
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// Banner compacto con nivel 1 siempre + nivel 2 condicional
  /// Al tocar muestra todos los pasos de la ruta
  Widget _buildCompactManeuverBanner() {
    return GestureDetector(
      onTap: onShowSteps,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        decoration: BoxDecoration(
          // 85% opacidad - se ve ligeramente a través pero texto legible
          color: const Color(0xD91A73E8),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(60),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // NIVEL 1: Turn-by-turn - SIEMPRE muestra el próximo giro
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Row(
              children: [
                // Flecha del giro (solo anima cuando está cerca)
                ManeuverArrow(
                  maneuverType: state.maneuverType,
                  modifier: state.maneuverModifier,
                  exitRef: state.exitRef,
                  size: 56,
                  color: Colors.white,
                  backgroundColor: const Color(0xFF1565C0),
                  animate: state.distanceToNextManeuver < 300,
                  distanceToManeuver: state.distanceToNextManeuver,
                ),
                const SizedBox(width: 12),
                // Distancia + calle del giro
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.formattedDistanceToManeuver,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                        ),
                      ),
                      Text(
                        state.streetName.isNotEmpty
                            ? state.streetName
                            : _extractStreetName(state.currentInstruction),
                        style: TextStyle(
                          color: Colors.white.withAlpha(240),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // NIVEL 2: Sub-maniobra - solo cuando está cerca (100m)
          if (_shouldShowSubManeuver && state.nextInstruction != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xD91565C0), // 85% opacidad
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    'Después',
                    style: TextStyle(
                      color: Colors.white.withAlpha(180),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _getManeuverIcon(
                      state.nextStep?.maneuver.type ?? 'straight',
                      state.nextStep?.maneuver.modifier,
                    ),
                    color: Colors.white70,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      state.nextInstruction!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

          // Lane guidance (si hay y está cerca)
          if (_shouldShowSubManeuver && state.hasLanes)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xD90D47A1), // 85% opacidad
                borderRadius: (state.nextInstruction == null)
                    ? const BorderRadius.only(
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      )
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: state.lanes!.map((lane) => _buildLaneIndicator(lane)).toList(),
              ),
            ),
        ],
      ),
    ),
    );
  }

  /// Construye un indicador de carril
  Widget _buildLaneIndicator(LaneInfo lane) {
    final isValid = lane.valid;
    final isActive = lane.active ?? lane.valid;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isActive
            ? Colors.white.withAlpha(51)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isValid
              ? Colors.white.withAlpha(204)
              : Colors.white.withAlpha(77),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: lane.indications.map((indication) {
          return Icon(
            _getLaneIcon(indication),
            color: isValid
                ? (isActive ? Colors.white : Colors.white.withAlpha(204))
                : Colors.white.withAlpha(77),
            size: 16,
          );
        }).toList(),
      ),
    );
  }

  /// Obtiene el icono para una indicacion de carril
  IconData _getLaneIcon(String indication) {
    switch (indication) {
      case 'left':
        return Icons.turn_left;
      case 'right':
        return Icons.turn_right;
      case 'slight left':
        return Icons.turn_slight_left;
      case 'slight right':
        return Icons.turn_slight_right;
      case 'sharp left':
        return Icons.turn_sharp_left;
      case 'sharp right':
        return Icons.turn_sharp_right;
      case 'uturn':
        return Icons.u_turn_left;
      case 'straight':
      default:
        return Icons.straight;
    }
  }

  /// Indicador de modo tunel / dead reckoning
  Widget _buildDeadReckoningIndicator() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 50),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.withAlpha(230),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(77),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.signal_cellular_connected_no_internet_0_bar, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          const Text(
            'TUNEL - GPS limitado',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Panel inferior con info del viaje + ETA + controles
  Widget _buildCompactBottomPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(100),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Fila superior: Info del viaje
              if (ride != null) _buildRideInfoRow(),
              if (ride != null) const SizedBox(height: 10),

              // Fila inferior: ETA + controles
              Row(
                children: [
                  // ETA y tiempo
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(
                              state.formattedETA,
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (hasTolls) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withAlpha(40),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.toll, color: Colors.amber, size: 14),
                                    SizedBox(width: 3),
                                    Text('TOLL', style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          '${state.formattedDurationRemaining} • ${state.formattedDistanceRemaining}',
                          style: TextStyle(color: Colors.grey[400], fontSize: 13),
                        ),
                      ],
                    ),
                  ),

                  // Controles
                  _buildCompactButton(
                    icon: isMuted ? Icons.volume_off : Icons.volume_up,
                    onTap: onMute,
                  ),
                  const SizedBox(width: 8),
                  _buildCompactButton(
                    icon: isOverviewMode ? Icons.navigation : Icons.map_outlined,
                    onTap: onOverview,
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onClose,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE53935),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'End',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Fila con información del rider/paquete/carpool
  Widget _buildRideInfoRow() {
    if (ride == null) return const SizedBox.shrink();

    final r = ride!;

    // Icono y color según tipo de viaje
    IconData typeIcon;
    Color typeColor;
    String typeLabel;

    switch (r.type) {
      case RideType.passenger:
        typeIcon = Icons.person;
        typeColor = const Color(0xFF4CAF50);
        typeLabel = 'Rider';
        break;
      case RideType.package:
        typeIcon = Icons.inventory_2;
        typeColor = const Color(0xFFFF9800);
        typeLabel = 'Package';
        break;
      case RideType.carpool:
        typeIcon = Icons.groups;
        typeColor = const Color(0xFF2196F3);
        typeLabel = 'Carpool';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          // Foto o icono de tipo
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: typeColor.withAlpha(40),
              borderRadius: BorderRadius.circular(22),
              image: r.displayImageUrl != null
                  ? DecorationImage(
                      image: NetworkImage(r.displayImageUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: r.displayImageUrl == null
                ? Icon(typeIcon, color: typeColor, size: 24)
                : null,
          ),
          const SizedBox(width: 12),

          // Info del viaje
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    // Tipo badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: typeColor.withAlpha(50),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        typeLabel.toUpperCase(),
                        style: TextStyle(
                          color: typeColor,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // Carpool: mostrar asientos
                    if (r.type == RideType.carpool) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.event_seat, color: Colors.grey[400], size: 14),
                      const SizedBox(width: 2),
                      Text(
                        '${r.filledSeats}',
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                    ],
                    // Good tipper indicator
                    if (r.isGoodTipper) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.green.withAlpha(40),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star, color: Colors.green, size: 10),
                            SizedBox(width: 2),
                            Text('TIP', style: TextStyle(color: Colors.green, fontSize: 8, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                // Nombre
                Text(
                  r.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // Notas (si hay y no es JSON)
                if (r.notes != null &&
                    r.notes!.isNotEmpty &&
                    !r.notes!.startsWith('{') &&
                    !r.notes!.startsWith('['))
                  Text(
                    r.notes!,
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),

          // Precio
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '\$${r.driverEarnings.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (r.tip > 0)
                Text(
                  '+\$${r.tip.toStringAsFixed(2)} tip',
                  style: const TextStyle(color: Colors.green, fontSize: 11),
                ),
            ],
          ),
          const SizedBox(width: 8),

          // Botón llamar
          if (r.passengerPhone != null && r.passengerPhone!.isNotEmpty)
            GestureDetector(
              onTap: onCallPassenger,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.phone, color: Colors.white, size: 20),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompactButton({
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  IconData _getManeuverIcon(String type, String? modifier) {
    switch (type) {
      case 'turn':
        switch (modifier) {
          case 'left':
            return Icons.turn_left;
          case 'right':
            return Icons.turn_right;
          case 'slight left':
            return Icons.turn_slight_left;
          case 'slight right':
            return Icons.turn_slight_right;
          case 'sharp left':
            return Icons.turn_sharp_left;
          case 'sharp right':
            return Icons.turn_sharp_right;
          case 'uturn':
            return Icons.u_turn_left;
          default:
            return Icons.straight;
        }
      case 'depart':
        return Icons.trip_origin;
      case 'arrive':
        return Icons.flag;
      case 'merge':
        return Icons.merge;
      case 'fork':
        return modifier == 'left' ? Icons.fork_left : Icons.fork_right;
      case 'roundabout':
      case 'rotary':
        return Icons.roundabout_left;
      case 'off ramp':
        return Icons.ramp_right;
      case 'on ramp':
        return Icons.ramp_left;
      default:
        return Icons.straight;
    }
  }
}

/// Barra de progreso de ruta
class RouteProgressBar extends StatelessWidget {
  final double progress; // 0.0 a 1.0
  final Color color;

  const RouteProgressBar({
    super.key,
    required this.progress,
    this.color = Colors.blue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 4,
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(2),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

/// Widget compacto para próxima maniobra (modo minimizado)
class NextManeuverCompact extends StatelessWidget {
  final NavigationState state;
  final VoidCallback? onTap;

  const NextManeuverCompact({
    super.key,
    required this.state,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!state.isNavigating) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 50, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A73E8),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(77),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getManeuverIcon(state.maneuverType, state.maneuverModifier),
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(width: 12),
            Text(
              state.formattedDistanceToManeuver,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                state.streetName,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getManeuverIcon(String type, String? modifier) {
    switch (type) {
      case 'turn':
        switch (modifier) {
          case 'left': return Icons.turn_left;
          case 'right': return Icons.turn_right;
          case 'slight left': return Icons.turn_slight_left;
          case 'slight right': return Icons.turn_slight_right;
          default: return Icons.straight;
        }
      case 'arrive': return Icons.flag;
      case 'roundabout': return Icons.roundabout_left;
      default: return Icons.straight;
    }
  }
}
