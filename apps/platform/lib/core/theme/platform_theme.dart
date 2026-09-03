import 'package:flutter/material.dart';

class PlatformColors {
  static const primary = Color(0xff8f1d2c);
  static const primaryStrong = Color(0xff6f1722);
  static const primarySoft = Color(0xfff7e8eb);
  static const background = Color(0xfff7f5f2);
  static const surface = Color(0xffffffff);
  static const text = Color(0xff172033);
  static const muted = Color(0xff5d6677);
  static const border = Color(0xffe7e2dc);
  static const success = Color(0xff168455);
  static const warning = Color(0xffb7791f);
  static const danger = Color(0xffc53030);
}

class PlatformTypography {
  static const sans = 'Ubuntu Sans';
  static const condensed = 'Ubuntu Condensed';
  static const mono = 'Ubuntu Mono';

  static const pageTitle = TextStyle(
    fontFamily: sans,
    fontSize: 24,
    fontWeight: FontWeight.w800,
    height: 1.15,
  );
  static const sectionTitle = TextStyle(
    fontFamily: sans,
    fontSize: 12,
    fontWeight: FontWeight.w800,
    color: PlatformColors.muted,
  );
  static const cardTitle = TextStyle(
    fontFamily: sans,
    fontSize: 16,
    fontWeight: FontWeight.w800,
  );
  static const secondary = TextStyle(
    fontFamily: sans,
    fontSize: 14,
    color: PlatformColors.muted,
  );
  static const label = TextStyle(
    fontFamily: sans,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: PlatformColors.muted,
  );
  static const mono13 = TextStyle(
    fontFamily: mono,
    fontSize: 13,
    fontWeight: FontWeight.w700,
  );
}

ThemeData platformTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: PlatformColors.primary,
    primary: PlatformColors.primary,
    surface: PlatformColors.surface,
    error: PlatformColors.danger,
  );
  final barColor = scheme.surfaceContainer;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: PlatformColors.background,
    fontFamily: PlatformTypography.sans,
    textTheme: const TextTheme(
      headlineSmall: PlatformTypography.pageTitle,
      titleMedium: PlatformTypography.cardTitle,
      bodyMedium: TextStyle(fontFamily: PlatformTypography.sans, fontSize: 14),
      bodySmall: TextStyle(fontFamily: PlatformTypography.sans, fontSize: 12),
      labelLarge: TextStyle(
        fontFamily: PlatformTypography.sans,
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
      labelSmall: PlatformTypography.label,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: barColor,
      foregroundColor: PlatformColors.text,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      iconTheme: const IconThemeData(color: PlatformColors.text),
      actionsIconTheme: const IconThemeData(color: PlatformColors.text),
      titleTextStyle: const TextStyle(
        color: PlatformColors.text,
        fontFamily: PlatformTypography.sans,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: barColor,
      selectedIconTheme: const IconThemeData(color: PlatformColors.primary),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PlatformColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: PlatformColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: PlatformColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: PlatformColors.primary, width: 1.4),
      ),
    ),
    cardTheme: CardThemeData(
      color: PlatformColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: PlatformColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: PlatformColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(120, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(120, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: const BorderSide(color: PlatformColors.border),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStateProperty.all(barColor),
    ),
  );
}
