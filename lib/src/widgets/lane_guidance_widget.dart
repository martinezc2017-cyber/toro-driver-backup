import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Widget de Lane Guidance - Muestra carriles como Google Maps
///
/// Escucha el EventChannel 'toro_driver/lane_guidance' que envía datos desde Android/iOS
/// Formato: [{"active": true, "directions": ["straight"]}, ...]
class LaneGuidanceWidget extends StatefulWidget {
  const LaneGuidanceWidget({super.key});

  @override
  State<LaneGuidanceWidget> createState() => _LaneGuidanceWidgetState();
}

class _LaneGuidanceWidgetState extends State<LaneGuidanceWidget> {
  static const EventChannel _laneChannel =
      EventChannel('toro_driver/lane_guidance');

  List<LaneData> _lanes = [];
  StreamSubscription? _laneSubscription;

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  void _startListening() {
    _laneSubscription = _laneChannel.receiveBroadcastStream().listen(
      (dynamic data) {
        if (data is String) {
          final List<dynamic> lanesJson = json.decode(data);
          setState(() {
            _lanes = lanesJson.map((lane) => LaneData.fromJson(lane)).toList();
          });
        }
      },
      onError: (dynamic error) {
        debugPrint('Lane guidance error: $error');
        setState(() => _lanes = []);
      },
    );
  }

  @override
  void dispose() {
    _laneSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_lanes.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _lanes.map((lane) => _buildLane(lane)).toList(),
      ),
    );
  }

  Widget _buildLane(LaneData lane) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: lane.active
            ? const Color(0xFF4285F4).withOpacity(0.3)
            : Colors.transparent,
        border: Border.all(
          color: lane.active ? const Color(0xFF4285F4) : Colors.white54,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(
        _getDirectionIcon(lane.directions.first),
        color: lane.active ? Colors.white : Colors.white54,
        size: 24,
      ),
    );
  }

  IconData _getDirectionIcon(String direction) {
    switch (direction) {
      case 'straight':
      case 'straight_ahead':
        return Icons.arrow_upward;
      case 'left':
        return Icons.turn_left;
      case 'right':
        return Icons.turn_right;
      case 'slight_left':
        return Icons.turn_slight_left;
      case 'slight_right':
        return Icons.turn_slight_right;
      case 'sharp_left':
        return Icons.turn_sharp_left;
      case 'sharp_right':
        return Icons.turn_sharp_right;
      case 'uturn':
        return Icons.u_turn_left;
      default:
        return Icons.arrow_upward;
    }
  }
}

class LaneData {
  final bool active;
  final List<String> directions;

  LaneData({
    required this.active,
    required this.directions,
  });

  factory LaneData.fromJson(Map<String, dynamic> json) {
    return LaneData(
      active: json['active'] as bool,
      directions: (json['directions'] as List)
          .map((d) => d.toString())
          .toList(),
    );
  }
}
