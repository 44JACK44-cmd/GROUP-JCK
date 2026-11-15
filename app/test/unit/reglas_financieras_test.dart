/// Pruebas de reglas comerciales que no dependen de la red.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gas_app/core/data/entregas_repo.dart';
import 'package:gas_app/core/data/productos_repo.dart';
import 'package:gas_app/core/data/rendicion_repo.dart';

void main() {
  group('estado de pago de una entrega', () {
    test('cobrar todo deja PAGADO', () {
      expect(EstadoPagoEntrega.calcular(40, 40), EstadoPagoEntrega.pagado);
    });

    test('cobrar una parte deja PARCIAL', () {
      expect(EstadoPagoEntrega.calcular(40, 15), EstadoPagoEntrega.parcial);
    });

    test('no cobrar deja PENDIENTE', () {
      expect(EstadoPagoEntrega.calcular(40, 0), EstadoPagoEntrega.pendiente);
    });

    test('un céntimo de diferencia no marca deuda', () {
      expect(EstadoPagoEntrega.calcular(40, 39.995), EstadoPagoEntrega.pagado);
    });
  });

  group('deuda de una entrega', () {
    DatosEntrega datos(double cobrado) => DatosEntrega(
          montoCobrado: cobrado,
          metodo: 'EFECTIVO',
          balonVacio: EstadoBalonVacio.recibido,
          fierro: EstadoFierro.devuelto,
        );

    test('si cobró todo no queda deuda', () {
      final d = datos(40);
      expect(d.quedanDeuda(40), isFalse);
      expect(d.deuda(40), 0);
    });

    test('si cobró una parte, la deuda es la diferencia', () {
      final d = datos(15);
      expect(d.quedanDeuda(40), isTrue);
      expect(d.deuda(40), 25);
    });

    test('nunca devuelve deuda negativa', () {
      final d = datos(50);
      expect(d.deuda(40), 0);
    });
  });

  group('fierro y balón vacío: un solo activo retornable', () {
    test('el producto retornable nunca se vende', () {
      expect(
        ProductosRepo.esVendible(
            {'nombre': 'Fierro / Balón vacío', 'tipo': 'RETORNABLE'}),
        isFalse,
      );
      expect(
        ProductosRepo.esVendible({'nombre': 'Balón 10 kg', 'tipo': 'PRODUCTO'}),
        isTrue,
      );
      // Sin la columna `tipo` (migración pendiente) se comporta como vendible
      // para no esconder el catálogo existente.
      expect(ProductosRepo.esVendible({'nombre': 'Balón 10 kg'}), isTrue);
    });

    test('el saldo de fierros es entregados menos devueltos', () {
      final saldo = RendicionRepo.saldoFierros([
        {'tipo': 'ENTREGA', 'cantidad': 3},
        {'tipo': 'DEVOLUCION', 'cantidad': 1},
      ]);
      expect(saldo, 2);
    });

    test('si devolvió más de lo que se le dejó, el saldo es 0', () {
      final saldo = RendicionRepo.saldoFierros([
        {'tipo': 'ENTREGA', 'cantidad': 1},
        {'tipo': 'DEVOLUCION', 'cantidad': 4},
      ]);
      expect(saldo, 0);
    });

    test('sin movimientos no hay fierros pendientes', () {
      expect(RendicionRepo.saldoFierros(const []), 0);
    });

    test('las cantidades inválidas o negativas no alteran el saldo', () {
      final saldo = RendicionRepo.saldoFierros([
        {'tipo': 'ENTREGA', 'cantidad': 2},
        {'tipo': 'ENTREGA', 'cantidad': -5},
        {'tipo': 'DEVOLUCION', 'cantidad': 0},
        {'tipo': 'OTRO', 'cantidad': 9},
      ]);
      expect(saldo, 2);
    });
  });
}
