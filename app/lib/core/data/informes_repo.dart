/// Informes administrativos: pedidos, ventas, pagos, deudas, balones,
/// motorizados y combustible. Todo con datos reales de la base.
library;

import '../domain/deuda.dart';
import 'sb.dart';

class InformesResumen {
  final int totalPedidos;
  final int pendientes;
  final int entregados;
  final int cancelados;

  final double totalVendido;
  final double cobrado;
  final double pendiente;

  final double efectivo;
  final double yape;
  final double otros;

  final int clientesDeudores;
  final double totalDeudas;

  final int balonesEntregados;
  final int balonesVaciosRecibidos;
  final int balonesVaciosPendientes;

  final double combustible;
  final double gastos;

  const InformesResumen({
    this.totalPedidos = 0,
    this.pendientes = 0,
    this.entregados = 0,
    this.cancelados = 0,
    this.totalVendido = 0,
    this.cobrado = 0,
    this.pendiente = 0,
    this.efectivo = 0,
    this.yape = 0,
    this.otros = 0,
    this.clientesDeudores = 0,
    this.totalDeudas = 0,
    this.balonesEntregados = 0,
    this.balonesVaciosRecibidos = 0,
    this.balonesVaciosPendientes = 0,
    this.combustible = 0,
    this.gastos = 0,
  });
}

/// Rendimiento de un motorizado en el periodo.
class RendimientoMotorizado {
  final String id;
  final String nombre;
  final int pedidos;
  final int entregados;
  final double cobrado;
  final double pendiente;

  const RendimientoMotorizado({
    required this.id,
    required this.nombre,
    this.pedidos = 0,
    this.entregados = 0,
    this.cobrado = 0,
    this.pendiente = 0,
  });
}

class InformesRepo {
  const InformesRepo();

  Future<InformesResumen> calcular({
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final desdeIso = desde.toIso8601String();
    final hastaIso = hasta.toIso8601String();

    final res = await Future.wait([
      sb.from('pedidos').select('id, total, estado').gte('fecha', desdeIso).lte('fecha', hastaIso).limit(5000),
      sb.from('pagos').select('monto, metodo, cliente_id').gte('fecha', desdeIso).lte('fecha', hastaIso).limit(5000),
      sb.from('gastos').select('monto').gte('fecha', desdeIso).lte('fecha', hastaIso).limit(2000),
      sb.from('combustible').select('monto').gte('fecha', desdeIso).lte('fecha', hastaIso).limit(2000),
      sb.from('movimiento_bal_on').select('tipo, cantidad, cliente_id').limit(5000),
      sb.from('entregas').select('pedido_id, estado_bal_on_vacio').limit(5000),
    ]);

    var totalPedidos = 0, pendientes = 0, entregados = 0, cancelados = 0;
    var totalVendido = 0.0;
    for (final p in res[0] as List) {
      totalPedidos++;
      final estado = p['estado'] as String? ?? '';
      if (estado == 'ENTREGADO') {
        entregados++;
        totalVendido += (p['total'] as num? ?? 0).toDouble();
      } else if (estado == 'CANCELADO' || estado == 'NO_ENTREGADO') {
        cancelados++;
      } else {
        pendientes++;
      }
    }

    var efectivo = 0.0, yape = 0.0, otros = 0.0, cobrado = 0.0;
    for (final p in res[1] as List) {
      final monto = (p['monto'] as num? ?? 0).toDouble();
      cobrado += monto;
      switch (p['metodo'] as String? ?? 'OTRO') {
        case 'EFECTIVO':
          efectivo += monto;
          break;
        case 'YAPE':
          yape += monto;
          break;
        default:
          otros += monto;
      }
    }

    var gastos = 0.0;
    for (final g in res[2] as List) {
      gastos += (g['monto'] as num? ?? 0).toDouble();
    }

    var combustible = 0.0;
    for (final c in res[3] as List) {
      combustible += (c['monto'] as num? ?? 0).toDouble();
    }

    var entregadosBalones = 0, vaciosRecibidos = 0;
    final saldoBalon = <String, int>{};
    for (final m in res[4] as List) {
      final cant = (m['cantidad'] as num? ?? 0).toInt();
      final cid = m['cliente_id'] as String;
      if (m['tipo'] == 'ENTREGA_LLENO') {
        entregadosBalones += cant;
        saldoBalon[cid] = (saldoBalon[cid] ?? 0) + cant;
      } else {
        vaciosRecibidos += cant;
        saldoBalon[cid] = (saldoBalon[cid] ?? 0) - cant;
      }
    }
    final vaciosPendientes = saldoBalon.values.fold(0, (s, v) => s + (v > 0 ? v : 0));

    // Clientes con deuda (entregado − cobrado por cliente).
    var clientesDeudores = 0;
    var totalDeudas = 0.0;
    final deudas = await _deudasGlobales();
    for (final v in deudas.values) {
      if (v > 0.009) {
        clientesDeudores++;
        totalDeudas += v;
      }
    }

    return InformesResumen(
      totalPedidos: totalPedidos,
      pendientes: pendientes,
      entregados: entregados,
      cancelados: cancelados,
      totalVendido: totalVendido,
      cobrado: cobrado,
      pendiente: (totalVendido - cobrado) > 0 ? totalVendido - cobrado : 0,
      efectivo: efectivo,
      yape: yape,
      otros: otros,
      clientesDeudores: clientesDeudores,
      totalDeudas: totalDeudas,
      balonesEntregados: entregadosBalones,
      balonesVaciosRecibidos: vaciosRecibidos,
      balonesVaciosPendientes: vaciosPendientes,
      combustible: combustible,
      gastos: gastos,
    );
  }

  Future<Map<String, double>> _deudasGlobales() async {
    final res = await Future.wait([
      sb.from('pedidos').select('id, cliente_id, total, estado').eq('estado', 'ENTREGADO').limit(5000),
      sb.from('pagos').select('monto, cliente_id, pedido_id').limit(10000),
    ]);
    return calcularDeudas(
      pedidos: List<Map<String, dynamic>>.from(res[0] as List),
      pagos: List<Map<String, dynamic>>.from(res[1] as List),
    ).porCliente;
  }

  /// Rendimiento por motorizado en el periodo.
  Future<List<RendimientoMotorizado>> porMotorizado({
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final res = await Future.wait([
      sb.from('perfiles').select('id, nombre').eq('rol', 'MOTORIZADO'),
      sb.from('pedidos')
          .select('id, repartidor_id, total, estado')
          .gte('fecha', desde.toIso8601String())
          .lte('fecha', hasta.toIso8601String())
          .limit(5000),
      sb.from('pagos').select('monto, pedido_id').limit(10000),
    ]);

    final motorizados = List<Map<String, dynamic>>.from(res[0] as List);
    final pedidos = List<Map<String, dynamic>>.from(res[1] as List);
    final pagos = List<Map<String, dynamic>>.from(res[2] as List);

    final pagosPorPedido = <String, double>{};
    for (final p in pagos) {
      final pid = p['pedido_id'] as String?;
      if (pid == null) continue;
      pagosPorPedido[pid] = (pagosPorPedido[pid] ?? 0) + (p['monto'] as num? ?? 0).toDouble();
    }

    final porMotorizado = <String, RendimientoMotorizado>{};
    for (final m in motorizados) {
      porMotorizado[m['id'] as String] = RendimientoMotorizado(
        id: m['id'] as String,
        nombre: m['nombre'] as String? ?? 'Motorizado',
      );
    }

    for (final p in pedidos) {
      final mid = p['repartidor_id'] as String?;
      if (mid == null) continue;
      final base = porMotorizado[mid];
      if (base == null) continue;
      final entregado = p['estado'] == 'ENTREGADO';
      porMotorizado[mid] = RendimientoMotorizado(
        id: base.id,
        nombre: base.nombre,
        pedidos: base.pedidos + 1,
        entregados: base.entregados + (entregado ? 1 : 0),
        cobrado: base.cobrado + (entregado ? (pagosPorPedido[p['id'] as String] ?? 0) : 0),
        pendiente: base.pendiente +
            (entregado ? ((p['total'] as num? ?? 0).toDouble() - (pagosPorPedido[p['id'] as String] ?? 0)) : 0),
      );
    }

    final lista = porMotorizado.values.where((m) => m.pedidos > 0).toList()
      ..sort((a, b) => b.cobrado.compareTo(a.cobrado));
    return lista;
  }
}

const informesRepo = InformesRepo();
