/// Formateo de dinero, fechas y antigüedad (tiempo esperando).
/// Todo el texto que ve el usuario sale de aquí para que sea consistente.
library;

/// S/ 45.00  (o S/ 45 si [conDecimales] es false)
String dinero(num? valor, {bool conDecimales = true}) {
  final v = (valor ?? 0).toDouble();
  final texto = conDecimales ? v.toStringAsFixed(2) : _sinCero(v);
  return 'S/ $texto';
}

String _sinCero(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(2);
}

/// Texto del método de pago legible: "Yape", "Efectivo"…
String metodoPago(String? metodo) => switch (metodo) {
      'EFECTIVO' => 'Efectivo',
      'YAPE' => 'Yape',
      'PLIN' => 'Plin',
      'TRANSFERENCIA' => 'Transferencia',
      'OTRO' => 'Otro',
      'DEUDA' => 'Quedó debiendo',
      null || '' => 'Pendiente',
      _ => metodo,
    };

/// Antigüedad legible: "Hace 2 h 30 min", "Hace 35 min", "Hace 3 días".
String antiguedad(DateTime? fecha, {DateTime? ahora}) {
  if (fecha == null) return '';
  final ref = ahora ?? DateTime.now();
  final d = ref.difference(fecha);
  if (d.isNegative) return 'Ahora';
  if (d.inSeconds < 60) return 'Hace un momento';
  if (d.inMinutes < 60) return 'Hace ${d.inMinutes} min';
  if (d.inHours < 24) {
    final min = d.inMinutes % 60;
    return min == 0 ? 'Hace ${d.inHours} h' : 'Hace ${d.inHours} h $min min';
  }
  final dias = d.inDays;
  return 'Hace $dias ${dias == 1 ? 'día' : 'días'}';
}

/// "13/11/2026"
String fechaCorta(DateTime? f) {
  if (f == null) return '';
  return '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';
}

/// "13/11/2026 14:30"
String fechaHora(DateTime? f) {
  if (f == null) return '';
  final h = f.hour.toString().padLeft(2, '0');
  final m = f.minute.toString().padLeft(2, '0');
  return '${fechaCorta(f)} $h:$m';
}

/// "Hoy 14:30" / "Ayer 09:12" / "13/11 14:30"
String fechaRelativa(DateTime? f, {DateTime? ahora}) {
  if (f == null) return '';
  final ref = ahora ?? DateTime.now();
  final hoy = DateTime(ref.year, ref.month, ref.day);
  final dia = DateTime(f.year, f.month, f.day);
  final h = f.hour.toString().padLeft(2, '0');
  final m = f.minute.toString().padLeft(2, '0');
  final diferencia = hoy.difference(dia).inDays;
  if (diferencia == 0) return 'Hoy $h:$m';
  if (diferencia == 1) return 'Ayer $h:$m';
  return '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')} $h:$m';
}

/// Inicio del día actual.
DateTime inicioHoy([DateTime? base]) {
  final b = base ?? DateTime.now();
  return DateTime(b.year, b.month, b.day);
}

/// Inicio de la semana (lunes).
DateTime inicioSemana([DateTime? base]) {
  final b = base ?? DateTime.now();
  final hoy = DateTime(b.year, b.month, b.day);
  return hoy.subtract(Duration(days: hoy.weekday - 1));
}

/// Inicio del mes.
DateTime inicioMes([DateTime? base]) {
  final b = base ?? DateTime.now();
  return DateTime(b.year, b.month, 1);
}

/// Convierte un ISO de Supabase a DateTime local.
DateTime? parseFecha(Object? iso) {
  if (iso == null) return null;
  final d = DateTime.tryParse(iso.toString());
  return d?.toLocal();
}
