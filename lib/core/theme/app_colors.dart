import 'package:flutter/material.dart';

/// CampusBuzz brand palette. Dark is the primary digital identity.
abstract final class CbColors {
  static const orange = Color(0xFFFF5F1F);
  static const lime = Color(0xFFCDFF57);
  static const dark = Color(0xFF0A0A0F);

  // Surfaces (dark scale)
  static const surface0 = Color(0xFF0A0A0F);
  static const surface1 = Color(0xFF12121A);
  static const surface2 = Color(0xFF1A1A24);
  static const surface3 = Color(0xFF23232F);
  static const border = Color(0xFF2C2C3A);

  // Text on dark
  static const textPrimary = Color(0xFFF7F7FA);
  static const textSecondary = Color(0xFFB4B4C2);
  static const textTertiary = Color(0xFF7C7C8E);

  // Accessible accent variants (for text on dark backgrounds)
  static const orangeText = Color(0xFFFF8A5B);
  static const limeText = Color(0xFFD8FF7A);

  // Status (never rely on colour alone — pair with icon/label)
  static const success = Color(0xFF4ADE80);
  static const warning = Color(0xFFF6C945);
  static const danger = Color(0xFFFF5C5C);
  static const info = Color(0xFF57D9FF);

  static const gradient = LinearGradient(
    colors: [orange, lime],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const gradientSoft = LinearGradient(
    colors: [Color(0x33FF5F1F), Color(0x33CDFF57)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static Color bandColor(String band) => switch (band) {
        'green' => success,
        'yellow' => warning,
        'red' => danger,
        _ => textTertiary,
      };
}
