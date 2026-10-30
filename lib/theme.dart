import 'package:flutter/material.dart';

// Zentrales Design: eure Palette, Material 3, heller und dunkler Modus.
// Palette: Creme #F5EEC2, Tannengrün #416A59, Nachtblau #39395F,
//          Grasgrün #73A24E, Limette #A9C25D.
class AppTheme {
  static const cream = Color(0xFFF5EEC2);
  static const forest = Color(0xFF416A59);
  static const navy = Color(0xFF39395F);
  static const grass = Color(0xFF73A24E);
  static const lime = Color(0xFFA9C25D);

  static ThemeData get light => _build(
    const ColorScheme(
      brightness: Brightness.light,
      primary: forest,
      onPrimary: Colors.white,
      primaryContainer: lime,
      onPrimaryContainer: navy,
      secondary: grass,
      onSecondary: Colors.white,
      secondaryContainer: lime,
      onSecondaryContainer: navy,
      tertiary: navy,
      onTertiary: cream,
      error: Color(0xFFB3261E),
      onError: Colors.white,
      surface: Color(0xFFFBF7E6),
      onSurface: navy,
      onSurfaceVariant: Color(0xFF5A5A78),
      surfaceContainerHighest: cream,
      outline: Color(0xFFDDD5A8),
    ),
  );

  static ThemeData get dark => _build(
    const ColorScheme(
      brightness: Brightness.dark,
      primary: lime,
      onPrimary: Color(0xFF23233A),
      primaryContainer: forest,
      onPrimaryContainer: cream,
      secondary: grass,
      onSecondary: Color(0xFF23233A),
      secondaryContainer: forest,
      onSecondaryContainer: cream,
      tertiary: cream,
      onTertiary: navy,
      error: Color(0xFFF2B8B5),
      onError: Color(0xFF601410),
      surface: Color(0xFF23233A),
      onSurface: cream,
      onSurfaceVariant: Color(0xFFCFC9A6),
      surfaceContainerHighest: navy,
      outline: Color(0xFF4A4A70),
    ),
  );

  static ThemeData _build(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
