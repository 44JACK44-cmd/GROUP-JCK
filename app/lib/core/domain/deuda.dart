/// Cálculo de deudas y saldos de balones.
///
/// Funciones PURAS: reciben las filas que trae la base de datos y devuelven
/// el resultado. Así se pueden probar sin base de datos y, sobre todo, hay
/// una sola fuente de verdad para el cálculo de deuda.
library;

class ResultadoDeudas {
  /// Deuda por cliente (clienteId → monto).
  final Map<String, double> porCliente;

  /// Suma de todas las deudas.
  final double total;

  /// Deuda de un pedido concreto.
  final Map<String, double> porPedido;

  const ResultadoDeudas({
    required this.porCliente,
    required this.total,
    required this.porPedido,
  });
}

/// Calcula la deuda de cada cliente.
///
/// Reglas:
///  - Solo cuentan los pedidos ENTREGADOS.
///  - De cada pedido se resta lo pagado *de ese pedido*.
///  - Los abonos sin pedido (pago a cuenta) se descuentan del total de la
///    deuda del cliente.
///  - Nunca hay deuda negativa.
ResultadoDeudas calcularDeudas({
  required List<Map<String, dynamic>> pedidos,
  required List<Map<String, dynamic>> pagos,
}) {
  // 1. Lo pagado por pedido.
  final pagadoPorPedido = <String, double>{};
  final abonosPorCliente = <String, double>{};
  for (final p in pagos) {
    final clienteId = p['cliente_id'] as String?;
    if (clienteId == null) continue;
    final monto = (p['monto'] as num? ?? 0).toDouble();
    final pedidoId = p['pedido_id'] as String?;
    if (pedidoId == null) {
      abonosPorCliente[clienteId] = (abonosPorCliente[clienteId] ?? 0) + monto;
    } else {
      pagadoPorPedido[pedidoId] = (pagadoPorPedido[pedidoId] ?? 0) + monto;
    }
  }

  // 2. Saldo pendiente por pedido.
  final saldoPorPedido = <String, double>{};
  final saldoPorCliente = <String, double>{};
  for (final ped in pedidos) {
    if (ped['estado'] != 'ENTREGADO') continue;
    final clienteId = ped['cliente_id'] as String?;
    final pedidoId = ped['id'] as String?;
    if (clienteId == null || pedidoId == null) continue;
    final total = (ped['total'] as num? ?? 0).toDouble();
    final pagado = pagadoPorPedido[pedidoId] ?? 0;
    final saldo = total - pagado;
    if (saldo > 0.009) {
      saldoPorPedido[pedidoId] = saldo;
      saldoPorCliente[clienteId] = (saldoPorCliente[clienteId] ?? 0) + saldo;
    }
  }

  // 3. Los abonos a cuenta reducen la deuda del cliente.
  for (final entry in abonosPorCliente.entries) {
    final saldo = (saldoPorCliente[entry.key] ?? 0) - entry.value;
    if (saldo > 0.009) {
      saldoPorCliente[entry.key] = saldo;
    } else {
      saldoPorCliente.remove(entry.key);
    }
  }

  final total = saldoPorCliente.values.fold<double>(0, (s, v) => s + v);
  return ResultadoDeudas(
    porCliente: saldoPorCliente,
    total: total,
    porPedido: saldoPorPedido,
  );
}

/// Saldo de balones (o fierros) por cliente: entregados − devueltos.
///
/// El resultado solo incluye los que deben algo (> 0).
Map<String, int> calcularSaldosActivos({
  required List<Map<String, dynamic>> movimientos,
  required String tipoEntrega,
}) {
  final saldo = <String, int>{};
  for (final m in movimientos) {
    final clienteId = m['cliente_id'] as String?;
    if (clienteId == null) continue;
    final cantidad = (m['cantidad'] as num? ?? 0).toInt();
    saldo[clienteId] = (saldo[clienteId] ?? 0) +
        (m['tipo'] == tipoEntrega ? cantidad : -cantidad);
  }
  return {
    for (final e in saldo.entries)
      if (e.value > 0) e.key: e.value,
  };
}
