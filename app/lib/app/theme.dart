import 'package:flutter/material.dart';

/// Sistema visual central.
///
/// Paleta neutra: el azul es SOLO acento (acciones, selección, enlaces).
/// El fondo oscuro es negro/carbón, nunca azul. El fondo claro es gris muy
/// claro con superficies blancas.
class AppTheme {
  // Acentos (iguales en ambos temas)
  static const Color primary = Color(0xFF3B82F6);
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // Compatibilidad con código que aún usa estas constantes
  static const Color background = Color(0xFFF7F7F7);
  static const Color cardColor = Color(0xFFFFFFFF);

  static const Duration rapida = Duration(milliseconds: 140);
  static const Duration normal = Duration(milliseconds: 220);
  static const Duration lenta = Duration(milliseconds: 320);

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFE8F0FE),
      onPrimaryContainer: Color(0xFF1D4ED8),
      secondary: Color(0xFF4B5563),
      onSecondary: Colors.white,
      surface: Color(0xFFFFFFFF),
      onSurface: Color(0xFF171717),
      surfaceContainerHighest: Color(0xFFF1F1F1),
      onSurfaceVariant: Color(0xFF525252),
      error: danger,
      onError: Colors.white,
      outline: Color(0xFFE5E5E5),
      outlineVariant: Color(0xFFE5E5E5),
      shadow: Color(0x1A000000),
      scrim: Color(0x66000000),
      inverseSurface: Color(0xFF1D1D1D),
      onInverseSurface: Colors.white,
      inversePrimary: Color(0xFFBFDBFE),
      surfaceTint: primary,
    );

    return _base(
      scheme: scheme,
      fondo: const Color(0xFFF7F7F7),
      superficie: const Color(0xFFFFFFFF),
      borde: const Color(0xFFE5E5E5),
      texto: const Color(0xFF171717),
      textoSecundario: const Color(0xFF525252),
      splash: const Color(0x1A3B82F6),
    );
  }

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFF1E3A5F),
      onPrimaryContainer: Color(0xFFBFDBFE),
      secondary: Color(0xFFB8B8B8),
      onSecondary: Color(0xFF0B0B0B),
      surface: Color(0xFF151515),
      onSurface: Color(0xFFF5F5F5),
      surfaceContainerHighest: Color(0xFF1D1D1D),
      onSurfaceVariant: Color(0xFFB8B8B8),
      error: danger,
      onError: Colors.white,
      outline: Color(0xFF2A2A2A),
      outlineVariant: Color(0xFF2A2A2A),
      shadow: Color(0x00000000),
      scrim: Color(0xB3000000),
      inverseSurface: Color(0xFFE5E5E5),
      onInverseSurface: Color(0xFF0B0B0B),
      inversePrimary: Color(0xFF1D4ED8),
      surfaceTint: primary,
    );

    return _base(
      scheme: scheme,
      fondo: const Color(0xFF0B0B0B),
      superficie: const Color(0xFF151515),
      borde: const Color(0xFF2A2A2A),
      texto: const Color(0xFFF5F5F5),
      textoSecundario: const Color(0xFFB8B8B8),
      splash: const Color(0x333B82F6),
    );
  }

  static ThemeData _base({
    required ColorScheme scheme,
    required Color fondo,
    required Color superficie,
    required Color borde,
    required Color texto,
    required Color textoSecundario,
    required Color splash,
  }) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: fondo,
      canvasColor: fondo,
      cardColor: superficie,
      dialogBackgroundColor: superficie,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      textTheme: TextTheme(
        titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: texto),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: texto),
        titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: texto),
        bodyLarge: TextStyle(fontSize: 16, color: texto),
        bodyMedium: TextStyle(fontSize: 14, color: texto),
        bodySmall: TextStyle(fontSize: 12, color: textoSecundario),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: texto),
        labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textoSecundario),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: fondo,
        foregroundColor: texto,
        surfaceTintColor: fondo,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: texto,
        ),
        iconTheme: IconThemeData(color: texto, size: 23),
      ),
      cardTheme: CardThemeData(
        color: superficie,
        surfaceTintColor: superficie,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borde),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: superficie,
        surfaceTintColor: superficie,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: texto),
        contentTextStyle: TextStyle(fontSize: 14, color: textoSecundario),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: superficie,
        surfaceTintColor: superficie,
        modalBackgroundColor: superficie,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: superficie,
        hintStyle: TextStyle(color: textoSecundario.withValues(alpha: 0.7)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borde),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borde),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          overlayColor: splash,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          side: BorderSide(color: borde),
          overlayColor: splash,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          overlayColor: splash,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      iconTheme: IconThemeData(color: textoSecundario, size: 22),
      dividerTheme: DividerThemeData(color: borde, thickness: 1, space: 16),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: borde),
        labelStyle: TextStyle(fontSize: 12.5, color: texto),
        secondaryLabelStyle: TextStyle(fontSize: 12.5, color: texto),
        selectedColor: primary.withValues(alpha: 0.14),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: superficie,
        surfaceTintColor: superficie,
        indicatorColor: primary.withValues(alpha: 0.14),
        labelTextStyle: WidgetStateProperty.all(
          TextStyle(fontSize: 11, color: textoSecundario),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected) ? primary : textoSecundario,
              size: 23,
            )),
        height: 70,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: superficie,
        selectedItemColor: primary,
        unselectedItemColor: textoSecundario,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
