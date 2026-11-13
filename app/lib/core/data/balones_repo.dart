/// Repositorio de balones y fierros (activos retornables).
///
/// Balón y fierro son activos SEPARADOS: nunca se mezclan sus saldos.
/// Nada se borra: cada devolución genera un movimiento nuevo, así que siempre
/// hay trazabilidad de lo que salió y lo que volvió.
library;

import 'package:uuid/uuid.dart';

import '../domain/deuda.dart';
import 'auditoria_repo.dart';
import 'sb.dart';

/// Cliente con balones (o fierros) pendientes de devolución.
class PendienteDevolucion {
  final String clienteId;
  final String nombre;
  final String? telefono;
  final int cantidad;

  const PendienteDevolucion({
    required this.clienteId,
    required this.nombre,
    required this.cantidad,
    this.telefono,
  });
}

class BalonesRepo {
  const BalonesRepo();

  /// Lista de clientes con balones vacíos pendientes de devolución.
  Future<List<PendienteDevolucion>> pendientesBalones() async {
    final saldos = await _saldos('movimiento_bal_on', entregado: 'ENTREGA_LLENO');
    return _conNombres(saldos);
  }

  /// Lista de clientes con fierros pendientes de devolución.
  Future<List<PendienteDevolucion>> pendientesFierros() async {
    final saldos = await _saldos('movimiento_fierro', entregado: 'ENTREGA');
    return _conNombres(saldos);
  }

  Future<Map<String, int>> _saldos(String tabla, {required String entregado}) async {
    final data = await sb.from(tabla).select('cliente_id, tipo, cantidad').limit(5000);
    return calcularSaldosActivos(
      movimientos: List<Map<String, dynamic>>.from(data),
      tipoEntrega: entregado,
    );
  }

  Future<List<PendienteDevolucion>> _conNombres(Map<String, int> saldos) async {
    if (saldos.isEmpty) return const [];
    final ids = saldos.keys.toList();
    final clientes = await sb
        .from('clientes')
        .select('id, nombre, telefono')
        .inFilter('id', ids);
    final lista = <PendienteDevolucion>[];
    for (final c in clientes) {
      final id = c['id'] as String;
      lista.add(PendienteDevolucion(
        clienteId: id,
        nombre: c['nombre'] as String? ?? 'Cliente',
        telefono: c['telefono'] as String?,
        cantidad: saldos[id] ?? 0,
      ));
    }
    lista.sort((a, b) => b.cantidad.compareTo(a.cantidad));
    return lista;
  }

  /// Registra la devolución de un balón vacío. Nunca borra: suma un movimiento.
  Future<void> registrarDevolucionBalon({
    required String empresaId,
    required String usuarioId,
    required String clienteId,
    required int cantidad,
    String? pedidoId,
  }) async {
    if (cantidad <= 0) throw Exception('La cantidad debe ser mayor a cero.');
    await sb.from('movimiento_bal_on').insert({
      'empresa_id': empresaId,
      'cliente_id': clienteId,
      'tipo': 'DEVOLUCION_VACIO',
      if (pedidoId != null) 'pedido_id': pedidoId,
      'cantidad': cantidad,
      'usuario_id': usuarioId,
      'uuid_offline': const Uuid().v4(),
    });
    await auditoriaRepo.registrar(
      empresaId: empresaId,
      entidad: 'balon',
      entidadId: clienteId,
      accion: 'DEVOLUCION_VACIO',
      usuarioId: usuarioId,
      detalle: {'cantidad': cantidad, if (pedidoId != null) 'pedido_id': pedidoId},
    );
  }

  /// Registra la devolución de un fierro / soporte.
  Future<void> registrarDevolucionFierro({
    required String empresaId,
    required String usuarioId,
    required String clienteId,
    required int cantidad,
    String? pedidoId,
  }) async {
    if (cantidad <= 0) throw Exception('La cantidad debe ser mayor a cero.');
    await sb.from('movimiento_fierro').insert({
      'empresa_id': empresaId,
      'cliente_id': clienteId,
      'tipo': 'DEVOLUCION',
      if (pedidoId != null) 'pedido_id': pedidoId,
      'cantidad': cantidad,
      'usuario_id': usuarioId,
      'uuid_offline': const Uuid().v4(),
    });
    await auditoriaRepo.registrar(
      empresaId: empresaId,
      entidad: 'fierro',
      entidadId: clienteId,
      accion: 'DEVOLUCION',
      usuarioId: usuarioId,
      detalle: {'cantidad': cantidad, if (pedidoId != null) 'pedido_id': pedidoId},
    );
  }

  /// Movimientos recientes de balones (para el historial).
  Future<List<Map<String, dynamic>>> movimientos({int limite = 50}) async {
    final data = await sb
        .from('movimiento_bal_on')
        .select('id, tipo, cantidad, fecha, cliente_id, pedido_id, clientes(nombre)')
        .order('fecha', ascending: false)
        .limit(limite);
    return List<Map<String, dynamic>>.from(data);
  }
}

const balonesRepo = BalonesRepo();
