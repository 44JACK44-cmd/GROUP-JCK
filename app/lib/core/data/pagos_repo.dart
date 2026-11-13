/// Repositorio de pagos y deudas.
///
/// Un pago SIEMPRE pertenece a un cliente y, si viene de una entrega, a un
/// pedido. El método (efectivo, Yape, …), la fecha, la hora y el usuario que
/// lo registró quedan guardados: eso es el control de Yape.
library;

import 'package:uuid/uuid.dart';

import 'auditoria_repo.dart';
import 'sb.dart';

class PagosRepo {
  const PagosRepo();

  /// Registra un pago.
  ///
  /// - [pedidoId] puede ser null: es un abono a cuenta de la deuda del
  ///   cliente (pago posterior de una deuda).
  /// - El `uuid_offline` evita duplicados al reintentar (offline).
  Future<String> registrar({
    required String empresaId,
    required String usuarioId,
    required String clienteId,
    required double monto,
    required String metodo,
    String? pedidoId,
    String? uuidOffline,
  }) async {
    if (monto <= 0) throw Exception('El monto debe ser mayor a cero.');

    final data = await sb
        .from('pagos')
        .insert({
          'empresa_id': empresaId,
          'pedido_id': pedidoId,
          'cliente_id': clienteId,
          'monto': monto,
          'metodo': metodo,
          'registrado_por': usuarioId,
          'uuid_offline': uuidOffline ?? const Uuid().v4(),
        })
        .select('id')
        .single();

    await auditoriaRepo.registrar(
      empresaId: empresaId,
      entidad: 'pago',
      entidadId: data['id'] as String,
      accion: 'REGISTRAR_PAGO',
      usuarioId: usuarioId,
      detalle: {
        'monto': monto,
        'metodo': metodo,
        'cliente_id': clienteId,
        if (pedidoId != null) 'pedido_id': pedidoId,
      },
    );

    return data['id'] as String;
  }

  /// Historial de pagos (opcionalmente filtrado por cliente o método).
  Future<List<Map<String, dynamic>>> listar({
    String? clienteId,
    String? metodo,
    DateTime? desde,
    DateTime? hasta,
    int limite = 200,
  }) async {
    var q = sb.from('pagos').select(
      'id, monto, metodo, fecha, cliente_id, pedido_id, registrado_por, '
      'clientes(nombre, telefono)',
    );
    if (clienteId != null) q = q.eq('cliente_id', clienteId);
    if (metodo != null) q = q.eq('metodo', metodo);
    if (desde != null) q = q.gte('fecha', desde.toIso8601String());
    if (hasta != null) q = q.lte('fecha', hasta.toIso8601String());
    final data = await q.order('fecha', ascending: false).limit(limite);
    return List<Map<String, dynamic>>.from(data);
  }

  /// Totales por método en un rango (para caja e informes).
  Future<Map<String, double>> totalesPorMetodo({
    DateTime? desde,
    DateTime? hasta,
    String? clienteId,
  }) async {
    var q = sb.from('pagos').select('monto, metodo');
    if (desde != null) q = q.gte('fecha', desde.toIso8601String());
    if (hasta != null) q = q.lte('fecha', hasta.toIso8601String());
    if (clienteId != null) q = q.eq('cliente_id', clienteId);
    final data = await q.limit(5000);
    final totales = <String, double>{};
    for (final p in data) {
      final m = p['metodo'] as String? ?? 'OTRO';
      totales[m] = (totales[m] ?? 0) + (p['monto'] as num? ?? 0).toDouble();
    }
    return totales;
  }

  /// Total cobrado en un rango (opcionalmente de un solo motorizado vía pedido).
  Future<double> totalCobrado({DateTime? desde, DateTime? hasta}) async {
    final totales = await totalesPorMetodo(desde: desde, hasta: hasta);
    return totales.values.fold<double>(0.0, (s, v) => s + v);
  }
}

const pagosRepo = PagosRepo();
