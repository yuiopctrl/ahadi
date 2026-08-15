import 'package:flutter/material.dart';

class AhadiColors {
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

class AhadiTypography {
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
    color: AhadiColors.muted,
    letterSpacing: 0,
  );
  static const cardTitle = TextStyle(
    fontFamily: sans,
    fontSize: 16,
    fontWeight: FontWeight.w800,
  );
  static const secondary = TextStyle(
    fontFamily: sans,
    fontSize: 14,
    color: AhadiColors.muted,
  );
  static const financialValue = TextStyle(
    fontFamily: condensed,
    fontSize: 18,
    fontWeight: FontWeight.w800,
    letterSpacing: 0,
  );
  static const label = TextStyle(
    fontFamily: sans,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: AhadiColors.muted,
  );
  static const reference = TextStyle(
    fontFamily: mono,
    fontSize: 13,
    fontWeight: FontWeight.w700,
  );
}

ThemeData ahadiTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AhadiColors.primary,
    primary: AhadiColors.primary,
    surface: AhadiColors.surface,
    error: AhadiColors.danger,
  );
  final barColor = scheme.surfaceContainer;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AhadiColors.background,
    fontFamily: AhadiTypography.sans,
    textTheme: const TextTheme(
      headlineSmall: AhadiTypography.pageTitle,
      titleMedium: AhadiTypography.cardTitle,
      bodyMedium: TextStyle(fontFamily: AhadiTypography.sans, fontSize: 14),
      bodySmall: TextStyle(fontFamily: AhadiTypography.sans, fontSize: 12),
      labelLarge: TextStyle(
        fontFamily: AhadiTypography.sans,
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
      labelSmall: AhadiTypography.label,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: barColor,
      foregroundColor: AhadiColors.text,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      iconTheme: const IconThemeData(color: AhadiColors.text),
      actionsIconTheme: const IconThemeData(color: AhadiColors.text),
      titleTextStyle: const TextStyle(
        color: AhadiColors.text,
        fontFamily: AhadiTypography.sans,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(backgroundColor: barColor),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AhadiColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AhadiColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AhadiColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AhadiColors.primary, width: 1.4),
      ),
    ),
    cardTheme: CardThemeData(
      color: AhadiColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AhadiColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AhadiColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: const BorderSide(color: AhadiColors.border),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
}
