import 'package:flutter/material.dart';

/// TORO DRIVER - Neon Dark Theme Colors
/// Same style as Rider Web with animated neon gradients
class AppColors {
  AppColors._();

  // ═══════════════════════════════════════════════════════════════════════════
  // NEON COLOR PALETTE - Same as Rider Web
  // ═══════════════════════════════════════════════════════════════════════════

  // Primary Blue (matches Rider)
  static const Color primary = Color(0xFF2563EB);
  static const Color primaryLight = Color(0xFF60A5FA);
  static const Color primaryBright = Color(0xFF60A5FA);
  static const Color primaryPale = Color(0xFF93C5FD);
  static const Color primaryCyan = Color(0xFF00D4FF);
  static const Color primaryDark = Color(0xFF1D4ED8);

  // Success - Elegant Green (matches Rider)
  static const Color success = Color(0xFF4CAF50);
  static const Color successLight = Color(0xFF66BB6A);
  static const Color successDark = Color(0xFF388E3C);

  // Error/Danger - Elegant Red (matches Rider)
  static const Color error = Color(0xFFE53935);
  static const Color errorLight = Color(0xFFEF5350);
  static const Color errorDark = Color(0xFFC62828);

  // Warning - Amber (matches Rider)
  static const Color warning = Color(0xFFFBBF24);
  static const Color warningLight = Color(0xFFFCD34D);
  static const Color warningDark = Color(0xFFF59E0B);

  // Info - Elegant Blue (matches Rider)
  static const Color info = Color(0xFF42A5F5);
  static const Color infoLight = Color(0xFF64B5F6);
  static const Color infoDark = Color(0xFF1E88E5);

  // ═══════════════════════════════════════════════════════════════════════════
  // DARK THEME BASE COLORS
  // ═══════════════════════════════════════════════════════════════════════════

  // Backgrounds (matches Rider)
  static const Color background = Color(0xFF0A0A0A);
  static const Color surface = Color(0xFF0D0D0D);
  static const Color card = Color(0xFF161616);
  static const Color cardSecondary = Color(0xFF1E1E1E);
  static const Color cardHover = Color(0xFF222222);
  static const Color cardTertiary = Color(0xFF2A2A2A);

  // Borders (matches Rider)
  static const Color border = Color(0xFF2A2A2A);
  static const Color borderSubtle = Color(0xFF1F1F1F);
  static const Color borderFocus = Color(0xFF2563EB);
  static const Color divider = Color(0xFF2A2A2A);

  // Text Colors (matches Rider)
  static const Color textPrimary = Color(0xFFF5F5F5);
  static const Color textSecondary = Color(0xFFB8B8B8);
  static const Color textTertiary = Color(0xFF7A7A7A);
  static const Color textDisabled = Color(0xFF5A5A5A);

  // ═══════════════════════════════════════════════════════════════════════════
  // SEMANTIC COLORS
  // ═══════════════════════════════════════════════════════════════════════════

  static const Color accent = primary;
  static const Color secondary = primaryLight;

  // Status colors
  static const Color online = success;
  static const Color offline = textTertiary;
  static const Color busy = warning;
  static const Color away = error;

  // Ride status
  static const Color rideRequested = warning;
  static const Color rideAccepted = primary;
  static const Color ridePickup = primaryLight;
  static const Color rideInProgress = primaryBright;
  static const Color rideCompleted = success;
  static const Color rideCancelled = error;

  // Extras
  static const Color star = Color(0xFFFFD60A);
  static const Color gold = Color(0xFFFFD700);
  static const Color platinum = Color(0xFFE5E4E2);
  static const Color purple = Color(0xFF8B5CF6);
  static const Color magenta = Color(0xFFEC4899);

  // Neon Cyan (avatar glow, community card border)
  static const Color neonCyan = Color(0xFF00FFFF);

  // Social brands
  static const Color facebook = Color(0xFF1877F2);

  // ═══════════════════════════════════════════════════════════════════════════
  // NEON GRADIENTS - Animated flowing effect
  // ═══════════════════════════════════════════════════════════════════════════

  // Primary gradient for buttons (matches Rider)
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [
      Color(0xFF2563EB),
      Color(0xFF60A5FA),
      Color(0xFF60A5FA),
      Color(0xFF93C5FD),
      Color(0xFF3B82F6),
      Color(0xFF2563EB),
      Color(0xFF60A5FA),
    ],
  );

  // Deep primary gradient (matches Rider)
  static const LinearGradient primaryGradientDeep = LinearGradient(
    colors: [Color(0xFF1D4ED8), Color(0xFF2563EB), Color(0xFF60A5FA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Success gradient
  static const LinearGradient successGradient = LinearGradient(
    colors: [
      Color(0xFF388E3C),
      Color(0xFF4CAF50),
      Color(0xFF66BB6A),
      Color(0xFFA5D6A7),
      Color(0xFF4CAF50),
      Color(0xFF388E3C),
    ],
  );

  // Danger gradient
  static const LinearGradient dangerGradient = LinearGradient(
    colors: [
      Color(0xFFC62828),
      Color(0xFFE53935),
      Color(0xFFEF5350),
      Color(0xFFEF9A9A),
      Color(0xFFE53935),
      Color(0xFFC62828),
    ],
  );

  // Warning/Fire gradient (for FireGlow compatibility)
  static const LinearGradient warningGradient = LinearGradient(
    colors: [
      Color(0xFFF59E0B),
      Color(0xFFFBBF24),
      Color(0xFFFCD34D),
      Color(0xFFFBBF24),
      Color(0xFFF59E0B),
    ],
  );

  // Subtle/Gray gradient
  static const LinearGradient subtleGradient = LinearGradient(
    colors: [
      Color(0xFF4B5563),
      Color(0xFF6B7280),
      Color(0xFF9CA3AF),
      Color(0xFF6B7280),
      Color(0xFF4B5563),
    ],
  );

  // Card gradient
  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF1A1A1A), Color(0xFF141414)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Surface gradient
  static const LinearGradient surfaceGradient = LinearGradient(
    colors: [Color(0xFF141414), Color(0xFF0F0F0F)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Header gradient
  static const LinearGradient headerGradient = LinearGradient(
    colors: [Color(0xFF0F0F0F), Color(0xFF0A0A0A)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Cyber gradient (neon blue)
  static const LinearGradient cyberGradient = LinearGradient(
    colors: [primary, primaryLight, primaryBright],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Aurora gradient
  static const LinearGradient auroraGradient = LinearGradient(
    colors: [primary, success, primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Carbon gradient
  static const LinearGradient carbonGradient = LinearGradient(
    colors: [Color(0xFF141414), Color(0xFF0F0F0F), Color(0xFF0A0A0A)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Metal gradient
  static const LinearGradient metalGradient = LinearGradient(
    colors: [Color(0xFF1F1F1F), Color(0xFF141414), Color(0xFF1F1F1F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Sunset gradient (fire)
  static const LinearGradient sunsetGradient = warningGradient;

  // Gold gradient
  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFFFD700), Color(0xFFFFA500), Color(0xFFFFD700)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Shimmer gradient
  static LinearGradient shimmerGradient = LinearGradient(
    colors: [
      card,
      cardSecondary.withValues(alpha: 0.8),
      card,
    ],
    stops: const [0.0, 0.5, 1.0],
    begin: const Alignment(-1.0, -0.3),
    end: const Alignment(1.0, 0.3),
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // GLASSMORPHISM
  // ═══════════════════════════════════════════════════════════════════════════

  static Color glassBackground = Colors.white.withValues(alpha: 0.03);
  static Color glassBackgroundLight = Colors.white.withValues(alpha: 0.05);
  static Color glassBorder = Colors.white.withValues(alpha: 0.08);
  static Color glassBorderLight = Colors.white.withValues(alpha: 0.1);

  // ═══════════════════════════════════════════════════════════════════════════
  // NEON GLOW SHADOWS
  // ═══════════════════════════════════════════════════════════════════════════

  // Primary neon glow
  static List<BoxShadow> glowPrimary = [
    BoxShadow(
      color: primary.withValues(alpha: 0.4),
      blurRadius: 15,
      spreadRadius: 0,
    ),
  ];

  // Alias for compatibility
  static List<BoxShadow> primaryGlow = glowPrimary;

  // Intense primary glow
  static List<BoxShadow> glowPrimaryIntense = [
    BoxShadow(
      color: primary.withValues(alpha: 0.5),
      blurRadius: 25,
      spreadRadius: 2,
    ),
    BoxShadow(
      color: primaryLight.withValues(alpha: 0.3),
      blurRadius: 40,
      spreadRadius: -5,
    ),
  ];

  // Success glow
  static List<BoxShadow> glowSuccess = [
    BoxShadow(
      color: success.withValues(alpha: 0.4),
      blurRadius: 15,
      spreadRadius: 0,
    ),
  ];

  // Error glow
  static List<BoxShadow> glowError = [
    BoxShadow(
      color: error.withValues(alpha: 0.4),
      blurRadius: 15,
      spreadRadius: 0,
    ),
  ];

  // Warning/Fire glow
  static List<BoxShadow> glowWarning = [
    BoxShadow(
      color: warning.withValues(alpha: 0.4),
      blurRadius: 15,
      spreadRadius: 0,
    ),
  ];

  // Purple glow
  static List<BoxShadow> glowPurple = [
    BoxShadow(
      color: purple.withValues(alpha: 0.4),
      blurRadius: 15,
      spreadRadius: 0,
    ),
  ];

  // Gold glow
  static List<BoxShadow> glowGold = [
    BoxShadow(
      color: gold.withValues(alpha: 0.4),
      blurRadius: 15,
      spreadRadius: 0,
    ),
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // REGULAR SHADOWS
  // ═══════════════════════════════════════════════════════════════════════════

  static List<BoxShadow> shadowSubtle = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.3),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> shadowMedium = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.4),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> shadowStrong = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.5),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> shadowFloating = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.6),
      blurRadius: 40,
      offset: const Offset(0, 16),
    ),
  ];

  static List<BoxShadow> cardShadow = shadowSubtle;

  static List<BoxShadow> innerGlow = [
    BoxShadow(
      color: Colors.white.withValues(alpha: 0.05),
      blurRadius: 8,
      spreadRadius: -2,
    ),
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // UTILITY METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  static Color withOpacity(Color color, double opacity) =>
      color.withValues(alpha: opacity);

  static Color primaryWithOpacity(double opacity) =>
      primary.withValues(alpha: opacity);

  static Color successWithOpacity(double opacity) =>
      success.withValues(alpha: opacity);

  static Color errorWithOpacity(double opacity) =>
      error.withValues(alpha: opacity);

  static Color warningWithOpacity(double opacity) =>
      warning.withValues(alpha: opacity);

  /// Get neon box shadow for glow effect
  static List<BoxShadow> neonShadow(Color color, {double intensity = 0.4, double blur = 15}) {
    return [
      BoxShadow(
        color: color.withValues(alpha: intensity),
        blurRadius: blur,
        spreadRadius: 0,
      ),
    ];
  }

  /// Get double glow shadow for stronger effect
  static List<BoxShadow> doubleGlow(Color color, {double intensity = 0.4}) {
    return [
      BoxShadow(
        color: color.withValues(alpha: intensity),
        blurRadius: 15,
        spreadRadius: 0,
      ),
      BoxShadow(
        color: color.withValues(alpha: intensity * 0.5),
        blurRadius: 30,
        spreadRadius: -5,
      ),
    ];
  }

  // Chart colors (neon)
  static const List<Color> chartColors = [
    primary,
    success,
    warning,
    error,
    purple,
    primaryBright,
  ];
}
