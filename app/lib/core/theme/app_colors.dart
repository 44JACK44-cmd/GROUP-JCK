/// Colores centralizados y adaptativos.
///
/// Ningún widget debe usar `AppColors.textoSecundario`, `Colors.white` o `Color(0xFF…)`
/// para texto o superficies: todos toman el color desde aquí, que a su vez
/// sigue al tema claro/oscuro/sistema de [TemaApp].
library;

import 'package:flutter/material.dart';

import '../state/tema.dart';

class AppColors {
  AppColors._();

  static bool get oscuro {
    final modo = TemaApp.modo.value;
    if (modo == ThemeMode.dark) return true;
    if (modo == ThemeMode.light) return false;
    try {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;
    } catch (_) {
      // En pruebas unitarias sin binding se asume modo claro.
      return false;
    }
  }

  // Texto
  static Color get textoPrincipal =>
      oscuro ? Color(0xFFF5F5F5) : Color(0xFF171717);
  static Color get textoSecundario =>
      oscuro ? Color(0xFFB8B8B8) : Color(0xFF525252);
  static Color get textoMuted =>
      oscuro ? Color(0xFF858585) : Color(0xFF737373);

  // Superficies
  static Color get fondo =>
      oscuro ? Color(0xFF0B0B0B) : Color(0xFFF7F7F7);
  static Color get superficie =>
      oscuro ? Color(0xFF151515) : Color(0xFFFFFFFF);
  static Color get superficieElevada =>
      oscuro ? Color(0xFF1D1D1D) : Color(0xFFFFFFFF);
  static Color get borde =>
      oscuro ? Color(0xFF2A2A2A) : Color(0xFFE5E5E5);

  // Acentos (azul SOLO para acciones y selección)
  static const Color primary = Color(0xFF3B82F6);
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);

  /// Constantes para enumerados y otros lugares que requieren `const`.
  static const Color mutedClaro = Color(0xFF737373);
  static const Color mutedOscuro = Color(0xFF858585);
}