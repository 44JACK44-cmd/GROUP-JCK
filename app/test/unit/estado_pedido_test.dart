/// Pruebas de los estados del pedido y las transiciones permitidas.
import 'package:flutter_test/flutter_test.dart';
import 'package:gas_app/core/domain/estado_pedido.dart';

void main() {
  group('lectura del estado', () {
    test('traduce los valores de la base de datos', () {
      expect(EstadoPedido.desdeDb('NUEVO'), EstadoPedido.nuevo);
      expect(EstadoPedido.desdeDb('ASIGNADO'), EstadoPedido.asignado);
      expect(EstadoPedido.desdeDb('EN_CAMINO'), EstadoPedido.enCamino);
      expect(EstadoPedido.desdeDb('ENTREGADO'), EstadoPedido.entregado);
      expect(EstadoPedido.desdeDb('CANCELADO'), EstadoPedido.cancelado);
      expect(EstadoPedido.desdeDb('NO_ENTREGADO'), EstadoPedido.noEntregado);
    });

    test('un estado desconocido cae en "Pendiente"', () {
      expect(EstadoPedido.desdeDb('RARO'), EstadoPedido.nuevo);
      expect(EstadoPedido.desdeDb(null), EstadoPedido.nuevo);
    });

    test('las etiquetas son legibles, no técnicas', () {
      expect(EstadoPedido.nuevo.label, 'Pendiente');
      expect(EstadoPedido.enCamino.label, 'En camino');
      expect(EstadoPedido.entregado.label, 'Entregado');
    });
  });

  group('transiciones válidas', () {
    test('el flujo normal es NUEVO → ASIGNADO → EN_CAMINO → ENTREGADO', () {
      expect(EstadoPedido.nuevo.puedeTransicionarA(EstadoPedido.asignado, esAdmin: false), isTrue);
      expect(
          EstadoPedido.asignado.puedeTransicionarA(EstadoPedido.enCamino, esAdmin: false), isTrue);
      expect(
          EstadoPedido.enCamino.puedeTransicionarA(EstadoPedido.entregado, esAdmin: false), isTrue);
    });

    test('no se puede pasar de ENTREGADO a EN_CAMINO sin operación administrativa', () {
      expect(
        EstadoPedido.entregado.puedeTransicionarA(EstadoPedido.enCamino, esAdmin: false),
        isFalse,
      );
      // El administrador sí puede, pero es una acción explícita.
      expect(
        EstadoPedido.entregado.puedeTransicionarA(EstadoPedido.enCamino, esAdmin: true),
        isTrue,
      );
    });

    test('un pedido cancelado no vuelve sin que lo reactive el admin', () {
      expect(
        EstadoPedido.cancelado.puedeTransicionarA(EstadoPedido.nuevo, esAdmin: false),
        isFalse,
      );
      expect(
        EstadoPedido.cancelado.puedeTransicionarA(EstadoPedido.nuevo, esAdmin: true),
        isTrue,
      );
    });

    test('no se puede saltar de NUEVO a ENTREGADO', () {
      expect(
        EstadoPedido.nuevo.puedeTransicionarA(EstadoPedido.entregado, esAdmin: false),
        isFalse,
      );
      expect(
        EstadoPedido.nuevo.puedeTransicionarA(EstadoPedido.entregado, esAdmin: true),
        isFalse,
      );
    });

    test('no se puede desasignar un pedido ya en camino', () {
      expect(
        EstadoPedido.enCamino.puedeTransicionarA(EstadoPedido.nuevo, esAdmin: false),
        isFalse,
      );
    });

    test('cualquier estado no entregado se puede cancelar', () {
      expect(EstadoPedido.nuevo.puedeTransicionarA(EstadoPedido.cancelado, esAdmin: true), isTrue);
      expect(
          EstadoPedido.asignado.puedeTransicionarA(EstadoPedido.cancelado, esAdmin: true), isTrue);
      expect(
          EstadoPedido.enCamino.puedeTransicionarA(EstadoPedido.cancelado, esAdmin: true), isTrue);
    });

    test('el motorizado no puede cancelar un pedido ya entregado', () {
      expect(
        EstadoPedido.entregado.puedeTransicionarA(EstadoPedido.cancelado, esAdmin: false),
        isFalse,
      );
    });
  });

  group('mensajes', () {
    test('"ya fue entregado" se explica al usuario', () {
      final msg = EstadoPedido.entregado.mensajeTransicionInvalida(EstadoPedido.enCamino);
      expect(msg, contains('ya fue entregado'));
    });

    test('un estado terminal explica que está cancelado', () {
      final msg = EstadoPedido.cancelado.mensajeTransicionInvalida(EstadoPedido.nuevo);
      expect(msg, contains('cancelado'));
    });
  });

  group('grupos de la lista', () {
    test('pendientes, en camino, completados y cancelados son distintos', () {
      expect(GrupoPedido.pendientes.estados, ['NUEVO', 'ASIGNADO']);
      expect(GrupoPedido.enCamino.estados, ['EN_CAMINO']);
      expect(GrupoPedido.completados.estados, ['ENTREGADO']);
      expect(GrupoPedido.cancelados.estados, ['CANCELADO', 'NO_ENTREGADO']);
    });
  });
}
