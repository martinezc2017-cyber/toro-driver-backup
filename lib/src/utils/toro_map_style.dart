import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// TORO NIGHT - Estilo de mapa propio de Toro.
///
/// Parte de `navigation-night-v1` (trae trafico, shields y labels de
/// navegacion) y al cargar el estilo lo re-pinta con la paleta de la app:
/// fondo casi negro (AppColors.background), agua azul profundo, calles en
/// grises azulados y autopistas en el azul Toro. Las capas de trafico NO se
/// tocan para que los colores de congestion sigan siendo legibles.
class ToroMapStyle {
  ToroMapStyle._();

  static const String baseStyleUri =
      'mapbox://styles/mapbox/navigation-night-v1';

  // Paleta (alineada con AppColors)
  static const String _land = '#07090F';
  static const String _landuse = '#0B0E16';
  static const String _park = '#0A1712';
  static const String _water = '#0A1A2F';
  static const String _building = '#12151F';
  static const String _buildingOutline = '#1A1E2A';
  static const String _roadCase = '#05070B';
  static const String _roadMinor = '#1A1F2B';
  static const String _roadStreet = '#222838';
  static const String _roadSecondary = '#2A3346';
  static const String _roadPrimary = '#34405A';
  static const String _roadMotorway = '#1D4ED8'; // AppColors.primaryDark
  static const String _rail = '#1F2430';
  static const String _admin = '#3B4252';
  static const String _labelText = '#9AA4B5';
  static const String _labelTextStrong = '#E5E7EB';
  static const String _labelPoi = '#6B7588';
  static const String _labelWater = '#4F7CAC';
  static const String _labelHalo = '#05070B';

  /// Aplica la paleta Toro sobre el estilo ya cargado. Llamar desde
  /// `onStyleLoadedListener` del MapWidget (se re-ejecuta si el estilo
  /// se recarga). Tolerante a capas que no existan en la version del estilo.
  static Future<void> apply(MapboxMap map) async {
    final List<StyleObjectInfo?> layers;
    try {
      layers = await map.style.getStyleLayers();
    } catch (_) {
      return;
    }

    final futures = <Future<void>>[];
    for (final layer in layers) {
      if (layer == null) continue;
      _paintFor(layer.id, layer.type).forEach((property, value) {
        futures.add(
          map.style
              .setStyleLayerProperty(layer.id, property, value)
              .catchError((_) {}),
        );
      });
    }
    await Future.wait(futures);
  }

  static Map<String, Object> _paintFor(String id, String type) {
    // Trafico / incidentes: conservar colores originales
    if (id.contains('traffic') ||
        id.contains('congestion') ||
        id.contains('incident')) {
      return const {};
    }

    switch (type) {
      case 'background':
        return const {'background-color': _land};

      case 'fill':
        if (id.contains('water')) return const {'fill-color': _water};
        if (id.contains('building')) {
          return const {
            'fill-color': _building,
            'fill-outline-color': _buildingOutline,
          };
        }
        if (id.contains('park') ||
            id.contains('national') ||
            id.contains('landcover') ||
            id.contains('pitch') ||
            id.contains('golf')) {
          return const {'fill-color': _park};
        }
        if (id.contains('landuse') || id.contains('aeroway')) {
          return const {'fill-color': _landuse};
        }
        if (id == 'land') return const {'fill-color': _land};
        return const {};

      case 'fill-extrusion':
        if (id.contains('building')) {
          return const {
            'fill-extrusion-color': _building,
            'fill-extrusion-opacity': 0.75,
          };
        }
        return const {};

      case 'line':
        if (id.contains('water')) return const {'line-color': _water};
        if (id.contains('admin') || id.contains('boundary')) {
          return const {'line-color': _admin};
        }
        if (id.contains('rail') || id.contains('transit')) {
          return const {'line-color': _rail};
        }
        if (id.contains('road') ||
            id.contains('bridge') ||
            id.contains('tunnel')) {
          if (id.contains('case') || id.contains('casing')) {
            return const {'line-color': _roadCase};
          }
          if (id.contains('motorway') || id.contains('trunk')) {
            return const {'line-color': _roadMotorway};
          }
          if (id.contains('primary')) return const {'line-color': _roadPrimary};
          if (id.contains('secondary') || id.contains('tertiary')) {
            return const {'line-color': _roadSecondary};
          }
          if (id.contains('street')) return const {'line-color': _roadStreet};
          if (id.contains('path') ||
              id.contains('pedestrian') ||
              id.contains('steps')) {
            return const {};
          }
          return const {'line-color': _roadMinor};
        }
        return const {};

      case 'symbol':
        // Shields/exits usan iconos con su propio texto: no tocar
        if (id.contains('shield') || id.contains('exit')) return const {};
        if (id.contains('water')) {
          return const {
            'text-color': _labelWater,
            'text-halo-color': _labelHalo,
          };
        }
        if (id.contains('poi') || id.contains('transit')) {
          return const {
            'text-color': _labelPoi,
            'text-halo-color': _labelHalo,
          };
        }
        if (id.contains('settlement') ||
            id.contains('place') ||
            id.contains('country') ||
            id.contains('state')) {
          return const {
            'text-color': _labelTextStrong,
            'text-halo-color': _labelHalo,
          };
        }
        return const {
          'text-color': _labelText,
          'text-halo-color': _labelHalo,
        };
    }
    return const {};
  }
}
