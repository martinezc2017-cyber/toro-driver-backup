import 'package:flutter/material.dart';

/// TORO DRIVER — paleta "TORO claro" (la misma del rider).
/// Fondo claro, azul eléctrico TORO, azul marino para el texto, oro de marca
/// como acento. Los nombres se conservan para no tocar las ~190 pantallas.
class AppColors {
  AppColors._();

  // ═══════════════════════════════════════════════════════════════════════════
  // MARCA
  // ═══════════════════════════════════════════════════════════════════════════

  static const Color primary = Color(0xFF1769FF); // azul TORO
  static const Color primaryLight = Color(0xFF4F93FF);
  static const Color primaryBright = Color(0xFF1769FF);
  static const Color primaryPale = Color(0xFFEAF2FF); // fondo suave azul
  static const Color primaryCyan = Color(0xFF1769FF); // alias heredado (era cyan)
  static const Color primaryDark = Color(0xFF0B46B5); // canto 3D / degradados
  static const Color accentSoft = Color(0xFFEAF2FF);

  // Éxito = verde TORO (legible en claro)
  static const Color success = Color(0xFF0B8068);
  static const Color successLight = Color(0xFF17B897);
  static const Color successDark = Color(0xFF07604E);
  static const Color successSoft = Color(0xFFE8FBF5);

  // Error
  static const Color error = Color(0xFFC93540);
  static const Color errorLight = Color(0xFFE5484D);
  static const Color errorDark = Color(0xFFA32830);
  static const Color errorSoft = Color(0xFFFFF0F1);

  // Aviso (ámbar legible)
  static const Color warning = Color(0xFF9A6700);
  static const Color warningLight = Color(0xFFB7791F);
  static const Color warningDark = Color(0xFF7A5200);
  static const Color warningSoft = Color(0xFFFFF7E6);

  // Info
  static const Color info = Color(0xFF1769FF);
  static const Color infoLight = Color(0xFF4F93FF);
  static const Color infoDark = Color(0xFF0B46B5);

  // ═══════════════════════════════════════════════════════════════════════════
  // BASE CLARA
  // ═══════════════════════════════════════════════════════════════════════════

  static const Color background = Color(0xFFF6F8FC);
  static const Color backgroundWarm = Color(0xFFFAF9F6);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color card = Color(0xFFFFFFFF);
  static const Color cardSecondary = Color(0xFFF3F6FA);
  static const Color cardHover = Color(0xFFEEF2F8);
  static const Color cardTertiary = Color(0xFFE6EAF0);

  // Bordes
  static const Color border = Color(0xFFE6EAF0);
  static const Color borderSubtle = Color(0xFFEEF1F6);
  static const Color borderStrong = Color(0xFFD0D8E5);
  static const Color borderFocus = Color(0xFF1769FF);
  static const Color divider = Color(0xFFE6EAF0);
  static const Color edge = Color(0xFFD5DEEC); // canto 3D de lo blanco

  // Texto (azul marino)
  static const Color textPrimary = Color(0xFF102A56);
  static const Color textSecondary = Color(0xFF667085);
  static const Color textTertiary = Color(0xFF737F93);
  static const Color textDisabled = Color(0xFF98A2B3);

  // Franja oscura de marca (cabeceras) — el único azul profundo del app
  static const Color ink = Color(0xFF061233);
  static const Color navy = Color(0xFF102A56);

  // ═══════════════════════════════════════════════════════════════════════════
  // SEMÁNTICOS
  // ═══════════════════════════════════════════════════════════════════════════

  static const Color accent = primary;
  static const Color secondary = primaryDark;

  static const Color online = success;
  static const Color offline = textTertiary;
  static const Color busy = warning;
  static const Color away = error;

  static const Color rideRequested = warning;
  static const Color rideAccepted = primary;
  static const Color ridePickup = primaryLight;
  static const Color rideInProgress = primaryBright;
  static const Color rideCompleted = success;
  static const Color rideCancelled = error;

  // Extras
  static const Color star = Color(0xFFD4AF37);
  static const Color gold = Color(0xFFD4AF37); // oro de marca
  static const Color goldDeep = Color(0xFFB8860B); // oro legible como texto
  static const Color goldSoft = Color(0xFFFBF5E5);
  static const Color platinum = Color(0xFFD0D8E5);
  static const Color purple = Color(0xFF7C5CFF);
  static const Color magenta = Color(0xFFD9458F);

  // Alias heredado: donde decía "cyan" ahora va el azul TORO
  static const Color neonCyan = Color(0xFF1769FF);

  // BLACK ROSE (nivel premium) en claro: oro sobre crema
  static const Color blackRose = Color(0xFFB8860B);
  static const Color blackRoseDark = Color(0xFF8B6914);
  static const Color blackRoseLight = Color(0xFF6B4E0B);
  static const Color blackRoseBg = Color(0xFFFBF5E5);

  // Social brands
  static const Color facebook = Color(0xFF1877F2);

  // ═══════════════════════════════════════════════════════════════════════════
  // DEGRADADOS (azul eléctrico → azul profundo; nada de arcoíris)
  // ═══════════════════════════════════════════════════════════════════════════

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF4F93FF), Color(0xFF1769FF), Color(0xFF0F55D6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient primaryGradientDeep = LinearGradient(
    colors: [Color(0xFF0B46B5), Color(0xFF1769FF), Color(0xFF4F93FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF07604E), Color(0xFF0B8068), Color(0xFF17B897)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient dangerGradient = LinearGradient(
    colors: [Color(0xFFA32830), Color(0xFFC93540), Color(0xFFE5484D)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient warningGradient = LinearGradient(
    colors: [Color(0xFF7A5200), Color(0xFF9A6700), Color(0xFFB7791F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient subtleGradient = LinearGradient(
    colors: [Color(0xFFEEF2F8), Color(0xFFF6F8FC), Color(0xFFEEF2F8)],
  );

  // Superficies claras (antes grises oscuros)
  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFF6F8FC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFF3F6FA)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Cabecera = franja de marca (azul marino → azul profundo)
  static const LinearGradient headerGradient = LinearGradient(
    colors: [Color(0xFF040C24), Color(0xFF07173F), Color(0xFF0A2F8A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cyberGradient = LinearGradient(
    colors: [primaryDark, primary, primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient auroraGradient = LinearGradient(
    colors: [primaryDark, primary, primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient carbonGradient = LinearGradient(
    colors: [Color(0xFFF6F8FC), Color(0xFFFFFFFF), Color(0xFFF3F6FA)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient metalGradient = LinearGradient(
    colors: [Color(0xFFF3F6FA), Color(0xFFFFFFFF), Color(0xFFF3F6FA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient sunsetGradient = warningGradient;

  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFE8C766), Color(0xFFD4AF37), Color(0xFFB8860B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient blackRoseGradient = LinearGradient(
    colors: [Color(0xFF8B6914), Color(0xFFD4AF37), Color(0xFF8B6914)],
  );

  static const LinearGradient blackRoseBgGradient = LinearGradient(
    colors: [Color(0xFFFFF9E8), Color(0xFFFBF5E5)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static LinearGradient shimmerGradient = LinearGradient(
    colors: [cardSecondary, card, cardSecondary],
    stops: const [0.0, 0.5, 1.0],
    begin: const Alignment(-1.0, -0.3),
    end: const Alignment(1.0, 0.3),
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // CRISTAL (sobre fondo claro: tinte azul marino, no blanco)
  // ═══════════════════════════════════════════════════════════════════════════

  static Color glassBackground = navy.withValues(alpha: 0.03);
  static Color glassBackgroundLight = navy.withValues(alpha: 0.05);
  static Color glassBorder = navy.withValues(alpha: 0.08);
  static Color glassBorderLight = navy.withValues(alpha: 0.12);

  // ═══════════════════════════════════════════════════════════════════════════
  // SOMBRAS (los "glow" neón ahora son sombras TORO tenues)
  // ═══════════════════════════════════════════════════════════════════════════

  static const Color _shadowInk = Color(0xFF102A56);

  static List<BoxShadow> glowPrimary = [
    BoxShadow(color: primary.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 6)),
  ];
  static List<BoxShadow> primaryGlow = glowPrimary;
  static List<BoxShadow> glowPrimaryIntense = [
    BoxShadow(color: primary.withValues(alpha: 0.28), blurRadius: 18, offset: const Offset(0, 8)),
  ];
  static List<BoxShadow> glowSuccess = [
    BoxShadow(color: success.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 6)),
  ];
  static List<BoxShadow> glowError = [
    BoxShadow(color: error.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 6)),
  ];
  static List<BoxShadow> glowWarning = [
    BoxShadow(color: warning.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 6)),
  ];
  static List<BoxShadow> glowPurple = [
    BoxShadow(color: purple.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 6)),
  ];
  static List<BoxShadow> glowGold = [
    BoxShadow(color: gold.withValues(alpha: 0.22), blurRadius: 14, offset: const Offset(0, 6)),
  ];

  static List<BoxShadow> shadowSubtle = [
    BoxShadow(color: _shadowInk.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 3)),
  ];
  static List<BoxShadow> shadowMedium = [
    BoxShadow(color: _shadowInk.withValues(alpha: 0.10), blurRadius: 18, offset: const Offset(0, 6)),
  ];
  static List<BoxShadow> shadowStrong = [
    BoxShadow(color: _shadowInk.withValues(alpha: 0.14), blurRadius: 26, offset: const Offset(0, 10)),
  ];
  static List<BoxShadow> shadowFloating = [
    BoxShadow(color: _shadowInk.withValues(alpha: 0.16), blurRadius: 36, offset: const Offset(0, 14)),
  ];
  static List<BoxShadow> cardShadow = shadowSubtle;
  static List<BoxShadow> innerGlow = [
    BoxShadow(color: Colors.white.withValues(alpha: 0.6), blurRadius: 8, spreadRadius: -2),
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // UTILIDADES
  // ═══════════════════════════════════════════════════════════════════════════

  static Color withOpacity(Color color, double opacity) => color.withValues(alpha: opacity);
  static Color primaryWithOpacity(double opacity) => primary.withValues(alpha: opacity);
  static Color successWithOpacity(double opacity) => success.withValues(alpha: opacity);
  static Color errorWithOpacity(double opacity) => error.withValues(alpha: opacity);
  static Color warningWithOpacity(double opacity) => warning.withValues(alpha: opacity);

  /// Sombra de acento (antes "neón"): tenue y hacia abajo.
  static List<BoxShadow> neonShadow(Color color, {double intensity = 0.4, double blur = 15}) {
    return [
      BoxShadow(color: color.withValues(alpha: (intensity * 0.5).clamp(0.0, 0.3)), blurRadius: blur, offset: const Offset(0, 6)),
    ];
  }

  static List<BoxShadow> doubleGlow(Color color, {double intensity = 0.4}) {
    return [
      BoxShadow(color: color.withValues(alpha: (intensity * 0.5).clamp(0.0, 0.3)), blurRadius: 14, offset: const Offset(0, 6)),
      BoxShadow(color: _shadowInk.withValues(alpha: 0.06), blurRadius: 24, offset: const Offset(0, 10)),
    ];
  }

  static const List<Color> chartColors = [primary, success, warning, error, purple, goldDeep];
}
