/// Pruebas de la prioridad automática por antigüedad y del cálculo de deudas.
import 'package:flutter_test/flutter_test.dart';
import 'package:gas_app/core/domain/deuda.dart';
import 'package:gas_app/core/domain/prioridad.dart';

void main() {
  group('prioridad por antigüedad', () {
    final ahora = DateTime(2026, 11, 13, 12, 0);

    test('más de 2 horas esperando → urgente', () {
      final p = Prioridad.de(ahora.subtract(const Duration(hours: 2, minutes: 30)), ahora: ahora);
      expect(p, NivelPrioridad.urgente);
    });

    test('más de 1 hora esperando → alta', () {
      final p = Prioridad.de(ahora.subtract(const Duration(hours: 1, minutes: 45)), ahora: ahora);
      expect(p, NivelPrioridad.alta);
    });

    test('35 minutos esperando → media', () {
      final p = Prioridad.de(ahora.subtract(const Duration(minutes: 35)), ahora: ahora);
      expect(p, NivelPrioridad.media);
    });

    test('un pedido recién creado → normal', () {
      final p = Prioridad.de(ahora.subtract(const Duration(minutes: 2)), ahora: ahora);
      expect(p, NivelPrioridad.normal);
    });

    test('el pedido más antiguo va primero', () {
      final viejo = DateTime(2026, 11, 13, 8);
      final nuevo = DateTime(2026, 11, 13, 11);
      expect(Prioridad.masAntiguoPrimero(viejo, nuevo), isTrue);
      expect(Prioridad.masAntiguoPrimero(nuevo, viejo), isFalse);
    });
  });

  group('cálculo de deudas', () {
    Map<String, dynamic> pedido(String id, String cliente, double total, String estado) => {
          'id': id,
          'cliente_id': cliente,
          'total': total,
          'estado': estado,
        };

    Map<String, dynamic> pago(String cliente, double monto, String? pedidoId) => {
          'cliente_id': cliente,
          'monto': monto,
          'pedido_id': pedidoId,
        };

    test('un pedido entregado sin pagos es deuda completa', () {
      final r = calcularDeudas(
        pedidos: [pedido('p1', 'c1', 45, 'ENTREGADO')],
        pagos: [],
      );
      expect(r.porCliente['c1'], 45);
      expect(r.total, 45);
    });

    test('un pedido entregado y pagado no genera deuda', () {
      final r = calcularDeudas(
        pedidos: [pedido('p1', 'c1', 45, 'ENTREGADO')],
        pagos: [pago('c1', 45, 'p1')],
      );
      expect(r.porCliente.containsKey('c1'), isFalse);
      expect(r.total, 0);
    });

    test('pago parcial: queda la diferencia', () {
      final r = calcularDeudas(
        pedidos: [pedido('p1', 'c1', 45, 'ENTREGADO')],
        pagos: [pago('c1', 20, 'p1')],
      );
      expect(r.porCliente['c1'], 25);
      expect(r.porPedido['p1'], 25);
    });

    test('un abono a cuenta reduce la deuda del cliente', () {
      final r = calcularDeudas(
        pedidos: [pedido('p1', 'c1', 45, 'ENTREGADO')],
        pagos: [pago('c1', 20, null)],
      );
      expect(r.porCliente['c1'], 25);
    });

    test('los pedidos no entregados no generan deuda', () {
      final r = calcularDeudas(
        pedidos: [
          pedido('p1', 'c1', 45, 'NUEVO'),
          pedido('p2', 'c1', 60, 'ASIGNADO'),
          pedido('p3', 'c1', 90, 'CANCELADO'),
        ],
        pagos: [],
      );
      expect(r.total, 0);
    });

    test('varios clientes se calculan por separado', () {
      final r = calcularDeudas(
        pedidos: [
          pedido('p1', 'c1', 45, 'ENTREGADO'),
          pedido('p2', 'c2', 90, 'ENTREGADO'),
          pedido('p3', 'c2', 60, 'ENTREGADO'),
        ],
        pagos: [pago('c2', 90, 'p2')],
      );
      expect(r.porCliente['c1'], 45);
      expect(r.porCliente['c2'], 60);
      expect(r.total, 105);
    });

    test('un abono mayor que la deuda no genera saldo negativo', () {
      final r = calcularDeudas(
        pedidos: [pedido('p1', 'c1', 45, 'ENTREGADO')],
        pagos: [pago('c1', 100, null)],
      );
      expect(r.porCliente.containsKey('c1'), isFalse);
      expect(r.total, 0);
    });
  });

  group('saldos de balones', () {
    test('entregados menos devueltos', () {
      final saldos = calcularSaldosActivos(
        movimientos: [
          {'cliente_id': 'c1', 'tipo': 'ENTREGA_LLENO', 'cantidad': 2},
          {'cliente_id': 'c1', 'tipo': 'DEVOLUCION_VACIO', 'cantidad': 1},
        ],
        tipoEntrega: 'ENTREGA_LLENO',
      );
      expect(saldos['c1'], 1);
    });

    test('quien devolvió todo no aparece', () {
      final saldos = calcularSaldosActivos(
        movimientos: [
          {'cliente_id': 'c1', 'tipo': 'ENTREGA_LLENO', 'cantidad': 2},
          {'cliente_id': 'c1', 'tipo': 'DEVOLUCION_VACIO', 'cantidad': 2},
        ],
        tipoEntrega: 'ENTREGA_LLENO',
      );
      expect(saldos.containsKey('c1'), isFalse);
    });
  });
}
