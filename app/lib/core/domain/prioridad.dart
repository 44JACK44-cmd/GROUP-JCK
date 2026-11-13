/// Prioridad de un pedido pendiente, calculada por antigüedad.
///
/// El usuario nunca elige la prioridad: el sistema la deduce de cuánto lleva
/// esperando el pedido. "Los más antiguos primero".
library;

import 'package:flutter/material.dart';

import '../../app/theme.dart';

enum NivelPrioridad {
  urgente('Urgente', Icons.priority_high, AppTheme.danger),
  alta('Alta', Icons.keyboard_double_arrow_up, AppTheme.warning),
  media('Media', Icons.keyboard_arrow_up, AppTheme.info),
  normal('Normal', Icons.keyboard_arrow_down, Colors.black45);

  const NivelPrioridad(this.label, this.icono, this.color);

  final String label;
  final IconData icono;
  final Color color;
}

/// Umbrales (en minutos) de antigüedad.
class Prioridad {
  /// A partir de 2 horas esperando → urgente.
  static const minutosUrgente = 120;

  /// A partir de 1 hora esperando → alta.
  static const minutosAlta = 60;

  /// Calcula el nivel de prioridad según la antigüedad del pedido.
  static NivelPrioridad de(DateTime? fecha, {DateTime? ahora}) {
    if (fecha == null) return NivelPrioridad.normal;
    final ref = ahora ?? DateTime.now();
    final minutos = ref.difference(fecha).inMinutes;
    if (minutos >= minutosUrgente) return NivelPrioridad.urgente;
    if (minutos >= minutosAlta) return NivelPrioridad.alta;
    if (minutos >= 15) return NivelPrioridad.media;
    return NivelPrioridad.normal;
  }

  /// Devuelve true si el pedido `a` es más antiguo que `b` (va antes).
  static bool masAntiguoPrimero(DateTime? a, DateTime? b) {
    final fa = a ?? DateTime.now().add(const Duration(days: 3650));
    final fb = b ?? DateTime.now().add(const Duration(days: 3650));
    return fa.isBefore(fb);
  }
}
