import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

/// Servicio de feedback háptico futurista
class HapticService {
  HapticService._();

  static bool _hasVibrator = false;
  static bool _hasAmplitudeControl = false;
  static bool _isEnabled = true;

  /// Inicializar el servicio de vibración
  static Future<void> initialize() async {
    _hasVibrator = await Vibration.hasVibrator();
    _hasAmplitudeControl = await Vibration.hasAmplitudeControl();
  }

  /// Habilitar o deshabilitar el feedback háptico
  static void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  /// Verificar si el feedback háptico está habilitado
  static bool get isEnabled => _isEnabled;

  // ═══════════════════════════════════════════════════════════════════════════
  // VIBRACIONES BÁSICAS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Vibración ligera - Para toques y selecciones
  static Future<void> lightImpact() async {
    if (!_isEnabled) return;
    await HapticFeedback.lightImpact();
    if (_hasVibrator && _hasAmplitudeControl) {
      await Vibration.vibrate(duration: 10, amplitude: 40);
    }
  }

  /// Vibración media - Para confirmaciones
  static Future<void> mediumImpact() async {
    if (!_isEnabled) return;
    await HapticFeedback.mediumImpact();
    if (_hasVibrator && _hasAmplitudeControl) {
      await Vibration.vibrate(duration: 20, amplitude: 80);
    }
  }

  /// Vibración fuerte - Para acciones importantes
  static Future<void> heavyImpact() async {
    if (!_isEnabled) return;
    await HapticFeedback.heavyImpact();
    if (_hasVibrator && _hasAmplitudeControl) {
      await Vibration.vibrate(duration: 30, amplitude: 120);
    }
  }

  /// Selección - Para cambios de selección
  static Future<void> selectionClick() async {
    if (!_isEnabled) return;
    await HapticFeedback.selectionClick();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PATRONES PERSONALIZADOS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Éxito - Patrón de vibración para acciones exitosas
  static Future<void> success() async {
    if (!_isEnabled) return;
    await HapticFeedback.mediumImpact();
    if (_hasVibrator) {
      await Vibration.vibrate(
        pattern: [0, 50, 50, 100],
        intensities: [0, 80, 0, 120],
      );
    }
  }

  /// Error - Patrón de vibración para errores
  static Future<void> error() async {
    if (!_isEnabled) return;
    await HapticFeedback.heavyImpact();
    if (_hasVibrator) {
      await Vibration.vibrate(
        pattern: [0, 100, 50, 100, 50, 100],
        intensities: [0, 255, 0, 255, 0, 255],
      );
    }
  }

  /// Advertencia - Patrón de vibración para advertencias
  static Future<void> warning() async {
    if (!_isEnabled) return;
    await HapticFeedback.mediumImpact();
    if (_hasVibrator) {
      await Vibration.vibrate(
        pattern: [0, 80, 80, 80],
        intensities: [0, 100, 0, 100],
      );
    }
  }

  /// Notificación - Patrón suave para notificaciones
  static Future<void> notification() async {
    if (!_isEnabled) return;
    await HapticFeedback.lightImpact();
    if (_hasVibrator) {
      await Vibration.vibrate(
        pattern: [0, 30, 30, 30, 30, 30],
        intensities: [0, 60, 0, 60, 0, 60],
      );
    }
  }

  /// Nuevo viaje - Patrón especial para nuevos viajes
  static Future<void> newRide() async {
    if (!_isEnabled) return;
    if (_hasVibrator) {
      await Vibration.vibrate(
        pattern: [0, 100, 100, 100, 100, 200],
        intensities: [0, 150, 0, 150, 0, 255],
      );
    } else {
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 200));
      await HapticFeedback.heavyImpact();
    }
  }

  /// Pulso - Vibración tipo pulso continuo
  static Future<void> pulse() async {
    if (!_isEnabled) return;
    if (_hasVibrator) {
      await Vibration.vibrate(
        pattern: [0, 20, 40, 20, 40, 20],
        intensities: [0, 100, 0, 100, 0, 100],
      );
    } else {
      await HapticFeedback.lightImpact();
    }
  }

  /// Completado - Patrón satisfactorio para tareas completadas
  static Future<void> completed() async {
    if (!_isEnabled) return;
    if (_hasVibrator) {
      await Vibration.vibrate(
        pattern: [0, 30, 50, 50, 50, 100],
        intensities: [0, 80, 0, 120, 0, 200],
      );
    } else {
      await HapticFeedback.mediumImpact();
      await Future.delayed(const Duration(milliseconds: 100));
      await HapticFeedback.heavyImpact();
    }
  }

  /// Swipe - Vibración para gestos de deslizamiento
  static Future<void> swipe() async {
    if (!_isEnabled) return;
    await HapticFeedback.selectionClick();
    if (_hasVibrator && _hasAmplitudeControl) {
      await Vibration.vibrate(duration: 15, amplitude: 50);
    }
  }

  /// Botón principal presionado
  static Future<void> buttonPress() async {
    if (!_isEnabled) return;
    await HapticFeedback.lightImpact();
    if (_hasVibrator && _hasAmplitudeControl) {
      await Vibration.vibrate(duration: 25, amplitude: 100);
    }
  }

  /// Toggle switch
  static Future<void> toggle() async {
    if (!_isEnabled) return;
    await HapticFeedback.selectionClick();
    if (_hasVibrator && _hasAmplitudeControl) {
      await Vibration.vibrate(duration: 12, amplitude: 60);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CANCELAR VIBRACIÓN
  // ═══════════════════════════════════════════════════════════════════════════

  /// Cancelar cualquier vibración en curso
  static Future<void> cancel() async {
    if (_hasVibrator) {
      await Vibration.cancel();
    }
  }
}
