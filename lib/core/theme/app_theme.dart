import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Material 3 foundation, heavily customised to the CampusBuzz identity:
/// dark-first, Syne headings, DM Sans body, orange/lime accents.
abstract final class CbTheme {
  static ThemeData dark() {
    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
    final heading = GoogleFonts.syneTextTheme(base.textTheme);
    final body = GoogleFonts.dmSansTextTheme(base.textTheme);
    final text = body.copyWith(
      displayLarge: heading.displayLarge?.copyWith(fontWeight: FontWeight.w800, color: CbColors.textPrimary, letterSpacing: -1),
      displayMedium: heading.displayMedium?.copyWith(fontWeight: FontWeight.w800, color: CbColors.textPrimary, letterSpacing: -0.5),
      displaySmall: heading.displaySmall?.copyWith(fontWeight: FontWeight.w800, color: CbColors.textPrimary),
      headlineLarge: heading.headlineLarge?.copyWith(fontWeight: FontWeight.w800, color: CbColors.textPrimary),
      headlineMedium: heading.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: CbColors.textPrimary),
      headlineSmall: heading.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: CbColors.textPrimary),
      titleLarge: heading.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: CbColors.textPrimary),
      titleMedium: body.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: CbColors.textPrimary),
      titleSmall: body.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: CbColors.textPrimary),
      bodyLarge: body.bodyLarge?.copyWith(color: CbColors.textPrimary),
      bodyMedium: body.bodyMedium?.copyWith(color: CbColors.textSecondary),
      bodySmall: body.bodySmall?.copyWith(color: CbColors.textTertiary),
      labelLarge: body.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: CbColors.textPrimary),
      labelMedium: body.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: CbColors.textSecondary),
      labelSmall: body.labelSmall?.copyWith(color: CbColors.textTertiary, letterSpacing: 0.4),
    );

    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: CbColors.orange,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFF3D1A0C),
      onPrimaryContainer: CbColors.orangeText,
      secondary: CbColors.lime,
      onSecondary: CbColors.dark,
      secondaryContainer: Color(0xFF2A3A0F),
      onSecondaryContainer: CbColors.limeText,
      tertiary: CbColors.info,
      onTertiary: CbColors.dark,
      error: CbColors.danger,
      onError: Colors.white,
      surface: CbColors.surface1,
      onSurface: CbColors.textPrimary,
      surfaceContainerHighest: CbColors.surface3,
      surfaceContainerHigh: CbColors.surface2,
      surfaceContainer: CbColors.surface2,
      surfaceContainerLow: CbColors.surface1,
      surfaceContainerLowest: CbColors.surface0,
      onSurfaceVariant: CbColors.textSecondary,
      outline: CbColors.border,
      outlineVariant: Color(0xFF1F1F2A),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: CbColors.textPrimary,
      onInverseSurface: CbColors.dark,
      inversePrimary: CbColors.orange,
    );

    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: CbColors.surface0,
      canvasColor: CbColors.surface0,
      textTheme: text,
      primaryTextTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: CbColors.surface0,
        foregroundColor: CbColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(color: CbColors.surface1, elevation: 0, shape: shape, margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias),
      chipTheme: ChipThemeData(
        backgroundColor: CbColors.surface2,
        selectedColor: CbColors.orange,
        secondarySelectedColor: CbColors.lime,
        labelStyle: text.labelMedium?.copyWith(color: CbColors.textPrimary),
        secondaryLabelStyle: text.labelMedium?.copyWith(color: CbColors.dark),
        side: const BorderSide(color: CbColors.border),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        showCheckmark: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: CbColors.orange,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 52),
          shape: const StadiumBorder(),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: CbColors.textPrimary,
          minimumSize: const Size(48, 52),
          side: const BorderSide(color: CbColors.border, width: 1.5),
          shape: const StadiumBorder(),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: CbColors.limeText, minimumSize: const Size(48, 44), textStyle: text.labelLarge),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: CbColors.surface2,
        hintStyle: text.bodyMedium?.copyWith(color: CbColors.textTertiary),
        labelStyle: text.bodyMedium,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: CbColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: CbColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: CbColors.lime, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: CbColors.danger)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: CbColors.surface1,
        indicatorColor: CbColors.orange.withValues(alpha: 0.2),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? CbColors.orangeText : CbColors.textTertiary)),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => text.labelSmall?.copyWith(color: s.contains(WidgetState.selected) ? CbColors.textPrimary : CbColors.textTertiary, fontWeight: FontWeight.w600)),
        height: 68,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: CbColors.surface1,
        indicatorColor: CbColors.orange.withValues(alpha: 0.2),
        selectedIconTheme: const IconThemeData(color: CbColors.orangeText),
        unselectedIconTheme: const IconThemeData(color: CbColors.textTertiary),
        selectedLabelTextStyle: text.labelMedium?.copyWith(color: CbColors.textPrimary),
        unselectedLabelTextStyle: text.labelMedium,
      ),
      dividerTheme: const DividerThemeData(color: CbColors.border, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(backgroundColor: CbColors.surface3, contentTextStyle: text.bodyLarge, behavior: SnackBarBehavior.floating, shape: shape),
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: CbColors.surface1, shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24)))),
      dialogTheme: DialogThemeData(backgroundColor: CbColors.surface1, shape: shape, titleTextStyle: text.headlineSmall, contentTextStyle: text.bodyLarge),
      listTileTheme: const ListTileThemeData(iconColor: CbColors.textSecondary, textColor: CbColors.textPrimary),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? CbColors.dark : CbColors.textSecondary),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? CbColors.lime : CbColors.surface3),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: CbColors.lime, linearTrackColor: CbColors.surface3),
      tabBarTheme: TabBarThemeData(labelColor: CbColors.textPrimary, unselectedLabelColor: CbColors.textTertiary, indicatorColor: CbColors.lime, labelStyle: text.labelLarge, unselectedLabelStyle: text.labelLarge),
      dataTableTheme: DataTableThemeData(headingTextStyle: text.labelMedium, dataTextStyle: text.bodyMedium?.copyWith(color: CbColors.textPrimary), dividerThickness: 1),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(selectedBackgroundColor: CbColors.orange, selectedForegroundColor: Colors.white, foregroundColor: CbColors.textSecondary, side: const BorderSide(color: CbColors.border)),
      ),
    );
  }
}
