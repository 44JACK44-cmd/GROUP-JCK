/// Rendición de cuentas por motorizado.
///
/// Toda la información sale de los registros reales: `pedidos`, `entregas`,
/// `pagos`, `movimiento_bal_on`, `movimiento_fierro` y `combustible`.
/// No hay datos ficticios.
library;

import 'sb.dart';

/// Resumen de un periodo para un motorizado (o para toda la empresa).
class Rendicion {
  final int pedidosRealizados;
  final int entregados;
  final int noEntregados;
  final int cancelados;
  final int pendientes;

  final double totalACobrar;
  final double cobrado;
  final double pendiente;

  final double yape;
  final double efectivo;
  final double otros;

  final double deudasGeneradas;

  final int balonesVaciosRecibidos;
  final int balonesVaciosPendientes;
  final int fierrosPendientes;

  final double combustible;

  const Rendicion({
    this.pedidosRealizados = 0,
    this.entregados = 0,
    this.noEntregados = 0,
    this.cancelados = 0,
    this.pendientes = 0,
    this.totalACobrar = 0,
    this.cobrado = 0,
    this.pendiente = 0,
    this.yape = 0,
    this.efectivo = 0,
    this.otros = 0,
    this.deudasGeneradas = 0,
    this.balonesVaciosRecibidos = 0,
    this.balonesVaciosPendientes = 0,
    this.fierrosPendientes = 0,
    this.combustible = 0,
  });

  bool get vacio => pedidosRealizados == 0;
}

class RendicionRepo {
  const RendicionRepo();

  /// Calcula la rendición de un periodo.
  ///
  /// - [motorizadoId] filtra por motorizado asignado (null = toda la empresa).
  /// - [soloAsignados] cuando es true solo cuenta pedidos que tienen motorizado.
  Future<Rendicion> calcular({
    required DateTime desde,
    required DateTime hasta,
    String? motorizadoId,
  }) async {
    final hastaIso = hasta.toIso8601String();

    // 1. Pedidos del periodo.
    var qPedidos = sb
        .from('pedidos')
        .select('id, numero, total, estado, cliente_id, repartidor_id, fecha')
        .gte('fecha', desde.toIso8601String())
        .lte('fecha', hastaIso);
    if (motorizadoId != null) {
      qPedidos = qPedidos.eq('repartidor_id', motorizadoId);
    }
    final pedidos = List<Map<String, dynamic>>.from(await qPedidos.limit(5000));

    if (pedidos.isEmpty) {
      return Rendicion();
    }

    final pedidosIds = pedidos.map((p) => p['id'] as String).toList();

    // 2. Entregas y pagos de esos pedidos.
    final res = await Future.wait([
      sb.from('entregas')
          .select('pedido_id, estado_bal_on_vacio, estado_pago')
          .inFilter('pedido_id', pedidosIds)
          .limit(5000),
      sb.from('pagos')
          .select('pedido_id, monto, metodo')
          .inFilter('pedido_id', pedidosIds)
          .limit(10000),
      sb.from('movimiento_bal_on')
          .select('cliente_id, tipo, cantidad, usuario_id, fecha')
          .inFilter('pedido_id', pedidosIds)
          .limit(10000),
      sb.from('movimiento_fierro')
          .select('cliente_id, tipo, cantidad, usuario_id, fecha')
          .inFilter('pedido_id', pedidosIds)
          .limit(10000),
    ]);

    final entregas = List<Map<String, dynamic>>.from(res[0] as List);
    final pagos = List<Map<String, dynamic>>.from(res[1] as List);
    final movBalones = List<Map<String, dynamic>>.from(res[2] as List);
    final movFierros = List<Map<String, dynamic>>.from(res[3] as List);

    // 3. Totales por estado.
    var entregados = 0, noEntregados = 0, cancelados = 0, pendientes = 0;
    var totalACobrar = 0.0;
    for (final p in pedidos) {
      final estado = p['estado'] as String? ?? '';
      final total = (p['total'] as num? ?? 0).toDouble();
      switch (estado) {
        case 'ENTREGADO':
          entregados++;
          totalACobrar += total;
          break;
        case 'NO_ENTREGADO':
          noEntregados++;
          break;
        case 'CANCELADO':
          cancelados++;
          break;
        default:
          pendientes++;
      }
    }

    // 4. Cobrado por método.
    var cobrado = 0.0, yape = 0.0, efectivo = 0.0, otros = 0.0;
    for (final p in pagos) {
      final monto = (p['monto'] as num? ?? 0).toDouble();
      final metodo = p['metodo'] as String? ?? 'OTRO';
      cobrado += monto;
      switch (metodo) {
        case 'YAPE':
          yape += monto;
          break;
        case 'EFECTIVO':
          efectivo += monto;
          break;
        default:
          otros += monto;
      }
    }

    // 5. Balones: recibidos (devoluciones) y pendientes (no devueltos).
    var vaciosRecibidos = 0;
    final clientesConPendiente = <String>{};
    for (final m in movBalones) {
      final cant = (m['cantidad'] as num? ?? 0).toInt();
      if (m['tipo'] == 'DEVOLUCION_VACIO') vaciosRecibidos += cant;
    }
    for (final e in entregas) {
      if (e['estado_bal_on_vacio'] == 'NO_RECIBIDO') {
        // El cliente queda debiendo el vacío hasta que lo devuelva.
        final pedido = pedidos.firstWhere(
          (p) => p['id'] == e['pedido_id'],
          orElse: () => const {},
        );
        final clienteId = pedido['cliente_id'] as String?;
        if (clienteId != null) clientesConPendiente.add(clienteId);
      }
    }

    var fierrosPendientes = 0;
    for (final m in movFierros) {
      final cant = (m['cantidad'] as num? ?? 0).toInt();
      if (m['tipo'] == 'DEVOLUCION') fierrosPendientes += cant;
    }
    fierrosPendientes = fierrosPendientes < 0 ? 0 : fierrosPendientes;

    // 6. Combustible del motorizado en el periodo.
    var combustible = 0.0;
    if (motorizadoId != null) {
      final comb = await sb
          .from('combustible')
          .select('monto')
          .eq('usuario_id', motorizadoId)
          .gte('fecha', desde.toIso8601String())
          .lte('fecha', hastaIso)
          .limit(500);
      for (final c in comb) {
        combustible += (c['monto'] as num? ?? 0).toDouble();
      }
    }

    final pendiente = (totalACobrar - cobrado) > 0 ? totalACobrar - cobrado : 0.0;

    return Rendicion(
      pedidosRealizados: pedidos.length,
      entregados: entregados,
      noEntregados: noEntregados,
      cancelados: cancelados,
      pendientes: pendientes,
      totalACobrar: totalACobrar,
      cobrado: cobrado,
      pendiente: pendiente,
      yape: yape,
      efectivo: efectivo,
      otros: otros,
      deudasGeneradas: pendiente,
      balonesVaciosRecibidos: vaciosRecibidos,
      balonesVaciosPendientes: clientesConPendiente.length,
      fierrosPendientes: fierrosPendientes,
      combustible: combustible,
    );
  }
}

const rendicionRepo = RendicionRepo();
