/// Red de seguridad para que todo cobro quede reflejado en la caja abierta.
///
/// El camino normal es el trigger `trg_pago_ingreso_caja` de la base de datos.
/// Esta llamada es **idempotente** y cubre los casos en que el trigger no
/// llegó a dispararse: sincronización offline, reintentos o una base de datos
/// a la que todavía le falta la migración.
library;

import 'sb.dart';

/// Registra en caja el ingreso del pago [pagoId], si aún no existe.
///
/// - Primero usa la función `registrar_ingreso_caja` (validada en servidor).
/// - Si la función no está disponible y se conocen [empresaId] y [monto],
///   inserta el movimiento directamente (solo funciona con permisos de
///   administrador).
///
/// Nunca lanza: el cobro ya está guardado y no debe revertirse por la caja.
Future<void> asegurarIngresoCaja(
  String pagoId, {
  String? empresaId,
  double? monto,
  String? usuarioId,
  String? metodo,
}) async {
  try {
    await sb.rpc('registrar_ingreso_caja', params: {'p_pago_id': pagoId});
    return;
  } catch (_) {
    // Continúa con el respaldo.
  }

  if (empresaId == null || monto == null) return;

  try {
    final existente = await sb
        .from('movimiento_caja')
        .select('id')
        .eq('origen', 'PAGO')
        .eq('referencia_id', pagoId)
        .maybeSingle();
    if (existente != null) return;

    final caja = await sb
        .from('cajas')
        .select('id')
        .eq('empresa_id', empresaId)
        .eq('estado', 'ABIERTA')
        .order('fecha_apertura', ascending: false)
        .limit(1)
        .maybeSingle();
    if (caja == null) return;

    await sb.from('movimiento_caja').insert({
      'empresa_id': empresaId,
      'caja_id': caja['id'],
      'tipo': 'INGRESO',
      'origen': 'PAGO',
      'referencia_id': pagoId,
      'monto': monto,
      'descripcion': metodo == null ? 'Cobro de pedido' : 'Cobro de pedido ($metodo)',
      'usuario_id': usuarioId,
    });
  } catch (_) {
    // Silencioso: el pago ya quedó registrado.
  }
}
