/// Modo de color de la app: claro, oscuro o según el sistema.
///
/// Se guarda solo en el dispositivo y se aplica desde `main.dart` antes de
/// dibujar cualquier pantalla, para evitar parpadeos.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TemaApp {
  TemaApp._();

  static const _clave = 'ajustes_tema';
  static final ValueNotifier<ThemeMode> modo =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  static Future<void> cargar() async {
    final p = await SharedPreferences.getInstance();
    final valor = p.getString(_clave) ?? 'system';
    modo.value = switch (valor) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  static Future<void> guardar(ThemeMode valor) async {
    modo.value = valor;
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _clave,
      switch (valor) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      },
    );
  }

  static String etiqueta(ThemeMode m) => switch (m) {
        ThemeMode.light => 'Claro',
        ThemeMode.dark => 'Oscuro',
        ThemeMode.system => 'Sistema',
      };
}
