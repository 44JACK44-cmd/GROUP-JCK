/// Navegación centralizada de la aplicación.
///
/// Regla: una pantalla interna NUNCA debe cerrar la app al presionar atrás.
/// El botón atrás del sistema se resuelve aquí, en un solo lugar, usando el
/// stack real del Navigator y la ruta actual informada por el shell.
library;

import 'package:flutter/material.dart';

class NavegacionService {
  NavegacionService._();

  /// Ruta actual (la actualiza AppShell y el router).
  static final ValueNotifier<String> ruta = ValueNotifier<String>('/inicio');

  /// Último aviso interno (por ejemplo, pedido asignado).
  static final ValueNotifier<String?> aviso = ValueNotifier<String?>(null);

  static bool esInicio(String ruta) =>
      ruta == '/inicio' || ruta == '/login' || ruta == '/welcome';

  static void mostrarAviso(String texto) => aviso.value = texto;

  static void limpiarAviso() => aviso.value = null;
}
