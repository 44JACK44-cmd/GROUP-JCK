import 'package:flutter/material.dart';

/// Tema visual: fondo claro y suave, un solo color primario sobrio,
/// botones grandes y legibles. Colores semánticos solo con significado.
class AppTheme {
  static const primary = Color(0xFF2F6FB0); // azul moderado
  static const success = Color(0xFF2E8B57);
  static const warning = Color(0xFFD98324);
  static const danger = Color(0xFFC0392B);
  static const info = Color(0xFF2D6A9F);
  static const background = Color(0xFFF7F8FA);
  static const cardColor = Colors.white;

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      surface: background,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      textTheme: const TextTheme(
        titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
            color: Color(0xFF1E242B)),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
            color: Color(0xFF1E242B)),
        bodyLarge: TextStyle(fontSize: 16, color: Color(0xFF232A32)),
        bodyMedium: TextStyle(fontSize: 14, color: Color(0xFF2A3139)),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
            color: Color(0xFF232A32)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: Colors.black87,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE6E8E5)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFDADDD9)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFDADDD9)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE6E8E5),
        thickness: 1,
        space: 16,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: const BorderSide(color: Color(0xFFE0E4E0)),
        labelStyle: const TextStyle(fontSize: 12.5),
      ),
      iconTheme: const IconThemeData(size: 22),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// Tema oscuro. Superficies gris oscuro y texto claro, con la misma
  /// jerarquía de colores semánticos que el tema claro.
  static ThemeData dark() {
    const fondo = Color(0xFF171C23);
    const tarjeta = Color(0xFF232B35);
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
      primary: Color(0xFF6FA8DC),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: fondo,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      textTheme: const TextTheme(
        titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
            color: Colors.white),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
            color: Colors.white),
        bodyLarge: TextStyle(fontSize: 16, color: Color(0xFFE6EAF0)),
        bodyMedium: TextStyle(fontSize: 14, color: Color(0xFFD6DCE5)),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
            color: Colors.white),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: fondo,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: tarjeta,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF37414E)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tarjeta,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF4A5665)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF4A5665)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: Color(0xFF6FA8DC)),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF37414E),
        thickness: 1,
        space: 16,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: const BorderSide(color: Color(0xFF4A5665)),
        labelStyle: const TextStyle(fontSize: 12.5),
      ),
      iconTheme: const IconThemeData(size: 22),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
