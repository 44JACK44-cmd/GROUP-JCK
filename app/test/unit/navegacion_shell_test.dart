/// Pruebas de la barra inferior: qué pestaña queda resaltada.
///
/// Antes cualquier ruta desconocida dejaba "Inicio" marcado y el admin veía
/// "Pedidos" apagado incluso dentro de un pedido.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gas_app/features/shell/app_shell.dart';

void main() {
  group('pestañas del administrador', () {
    test('una subpantalla resalta su sección', () {
      expect(
        indicePestanaActiva(pestanasAdmin, '/pedidos/nuevo', esAdmin: true),
        1,
      );
      expect(
        indicePestanaActiva(pestanasAdmin, '/clientes/abc', esAdmin: true),
        2,
      );
    });

    test('mis pedidos resalta Pedidos, no Inicio', () {
      expect(
        indicePestanaActiva(pestanasAdmin, '/mis-pedidos', esAdmin: true),
        1,
      );
    });

    test('más y mas-moto no se confunden', () {
      expect(indicePestanaActiva(pestanasAdmin, '/mas', esAdmin: true), 4);
      expect(
        indicePestanaActiva(pestanasAdmin, '/mas-moto', esAdmin: true),
        0,
      );
    });

    test('una pantalla suelta no rompe la barra', () {
      expect(indicePestanaActiva(pestanasAdmin, '/caja', esAdmin: true), 0);
    });
  });

  group('pestañas del motorizado', () {
    test('cobros no existe en su barra y no rompe', () {
      expect(
        indicePestanaActiva(pestanasMotorizado, '/cobros', esAdmin: false),
        0,
      );
    });

    test('mis pedidos, mi registro e historial se resaltan', () {
      expect(
        indicePestanaActiva(pestanasMotorizado, '/mis-pedidos', esAdmin: false),
        1,
      );
      expect(
        indicePestanaActiva(pestanasMotorizado, '/mi-registro', esAdmin: false),
        2,
      );
      expect(
        indicePestanaActiva(pestanasMotorizado, '/historial', esAdmin: false),
        3,
      );
    });

    test('el menú del motorizado es su propio "Más"', () {
      expect(
        indicePestanaActiva(pestanasMotorizado, '/mas-moto', esAdmin: false),
        4,
      );
    });
  });
}
