/// Pruebas del cierre diario y de las reglas del dinero.
///
/// Reglas que se comprueban aquí:
/// 1. Solo los pedidos ENTREGADOS cuentan como venta (nunca lo pendiente ni
///    lo cancelado o no entregado).
/// 2. Un gasto descuenta del bolsillo con el que se pagó (efectivo, Yape…).
/// 3. Vendido no es lo mismo que cobrado: la deuda es la diferencia.
/// 4. Si el motorizado declaró su efectivo, la diferencia se calcula contra lo
///    que debería haber; si no declaró, no se inventa una diferencia.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gas_app/core/data/rendiciones_repo.dart';

Map<String, dynamic> _pedido(String estado, double total) =>
    {'estado': estado, 'total': total};

Map<String, dynamic> _pago(double monto, String metodo) =>
    {'monto': monto, 'metodo': metodo};

Map<String, dynamic> _gasto(double monto, [String medio = 'EFECTIVO']) =>
    {'monto': monto, 'medio_pago': medio};

Map<String, dynamic> _rendicion(double efectivo, [String estado = 'PENDIENTE']) =>
    {'efectivo_declarado': efectivo, 'estado': estado};

void main() {
  group('solo lo entregado es venta', () {
    test('pedidos pendientes, cancelados y no entregados no suman', () {
      final cierre = CalculoCierre.calcular(
        pedidos: [
          _pedido('ENTREGADO', 40),
          _pedido('ENTREGADO', 60),
          _pedido('NUEVO', 100),
          _pedido('ASIGNADO', 100),
          _pedido('EN_CAMINO', 100),
          _pedido('CANCELADO', 100),
          _pedido('NO_ENTREGADO', 100),
        ],
        pagos: const [],
        gastos: const [],
        rendiciones: const [],
      );
      expect(cierre.totalVentas, 100);
      expect(cierre.pedidosPendientes, 3);
    });

    test('sin pedidos entregados no hay ventas ni deudas', () {
      final cierre = CalculoCierre.calcular(
        pedidos: [_pedido('NUEVO', 50)],
        pagos: const [],
        gastos: const [],
        rendiciones: const [],
      );
      expect(cierre.totalVentas, 0);
      expect(cierre.deudasTotal, 0);
    });
  });

  group('cobrado por método', () {
    test('separa efectivo y Yape, y no los confunde', () {
      final cierre = CalculoCierre.calcular(
        pedidos: [_pedido('ENTREGADO', 200)],
        pagos: [
          _pago(120, 'EFECTIVO'),
          _pago(80, 'YAPE'),
          _pago(30, 'PLIN'),
        ],
        gastos: const [],
        rendiciones: const [],
      );
      expect(cierre.efectivoEsperado, 120);
      expect(cierre.yapeTotal, 80);
      // 230 cobrado > 200 vendido: no hay deuda (nunca negativa).
      expect(cierre.deudasTotal, 0);
    });

    test('vendido menos cobrado es la deuda real', () {
      final cierre = CalculoCierre.calcular(
        pedidos: [_pedido('ENTREGADO', 300)],
        pagos: [_pago(100, 'EFECTIVO')],
        gastos: const [],
        rendiciones: const [],
      );
      expect(cierre.totalVentas, 300);
      expect(cierre.deudasTotal, 200);
    });
  });

  group('los gastos descuentan del bolsillo correcto', () {
    test('un gasto en Yape no reduce el efectivo esperado', () {
      final cierre = CalculoCierre.calcular(
        pedidos: [_pedido('ENTREGADO', 100)],
        pagos: [_pago(100, 'EFECTIVO')],
        gastos: [_gasto(30, 'YAPE')],
        rendiciones: const [],
      );
      expect(cierre.efectivoEsperado, 100);
      expect(cierre.gastosTotal, 30);
      expect(cierre.gastosEfectivo, 0);
      expect(cierre.efectivoNeto, 100);
    });

    test('un gasto en efectivo sí reduce lo que debe quedar', () {
      final cierre = CalculoCierre.calcular(
        pedidos: [_pedido('ENTREGADO', 100)],
        pagos: [_pago(100, 'EFECTIVO')],
        gastos: [_gasto(30, 'EFECTIVO'), _gasto(20, 'YAPE')],
        rendiciones: const [],
      );
      expect(cierre.gastosTotal, 50);
      expect(cierre.gastosEfectivo, 30);
      expect(cierre.efectivoNeto, 70);
    });

    test('un gasto sin medio de pago se toma como efectivo', () {
      final cierre = CalculoCierre.calcular(
        pedidos: [_pedido('ENTREGADO', 100)],
        pagos: [_pago(100, 'EFECTIVO')],
        gastos: const [
          {'monto': 25}
        ],
        rendiciones: const [],
      );
      expect(cierre.gastosEfectivo, 25);
      expect(cierre.efectivoNeto, 75);
    });
  });

  group('efectivo declarado y diferencias', () {
    test('sin rendiciones no se inventa una diferencia', () {
      final cierre = CalculoCierre.calcular(
        pedidos: [_pedido('ENTREGADO', 100)],
        pagos: [_pago(100, 'EFECTIVO')],
        gastos: const [],
        rendiciones: const [],
      );
      expect(cierre.efectivoRecibido, 100);
      expect(cierre.diferencias, 0);
      expect(cierre.rendicionesPendientes, 0);
    });

    test('si declaró de menos, la diferencia es negativa (falta)', () {
      final cierre = CalculoCierre.calcular(
        pedidos: [_pedido('ENTREGADO', 100)],
        pagos: [_pago(100, 'EFECTIVO')],
        gastos: [_gasto(10, 'EFECTIVO')],
        rendiciones: [_rendicion(80)],
      );
      expect(cierre.efectivoNeto, 90);
      expect(cierre.efectivoRecibido, 80);
      expect(cierre.diferencias, -10);
      expect(cierre.rendicionesPendientes, 1);
    });

    test('si declaró de más, la diferencia es positiva (sobra)', () {
      final cierre = CalculoCierre.calcular(
        pedidos: [_pedido('ENTREGADO', 100)],
        pagos: [_pago(100, 'EFECTIVO')],
        gastos: const [],
        rendiciones: [_rendicion(105)],
      );
      expect(cierre.efectivoRecibido, 105);
      expect(cierre.diferencias, 5);
    });

    test('una rendición aprobada ya no cuenta como pendiente', () {
      final cierre = CalculoCierre.calcular(
        pedidos: [_pedido('ENTREGADO', 100)],
        pagos: [_pago(100, 'EFECTIVO')],
        gastos: const [],
        rendiciones: [
          _rendicion(100, 'APROBADA'),
          _rendicion(20, 'PENDIENTE'),
        ],
      );
      expect(cierre.rendicionesPendientes, 1);
      expect(cierre.efectivoRecibido, 120);
    });
  });
}
