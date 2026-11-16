/// Pruebas de la sincronización: el aviso interno y la frescura del GPS.
///
/// Son reglas puras (no tocan la red) para que un cambio de estado nunca se
/// quede sin avisar a las pantallas, y para que el mapa no mienta.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gas_app/core/data/ubicaciones_repo.dart';
import 'package:gas_app/core/state/bus.dart';

void main() {
  group('SyncBus', () {
    test('cada aviso incrementa su contador', () {
      final pedidosAntes = SyncBus.pedidos.value;
      final dineroAntes = SyncBus.dinero.value;
      final ubicacionAntes = SyncBus.ubicaciones.value;

      SyncBus.pedidosCambiaron();
      SyncBus.dineroCambio();
      SyncBus.ubicacionCambio();

      expect(SyncBus.pedidos.value, pedidosAntes + 1);
      expect(SyncBus.dinero.value, dineroAntes + 1);
      expect(SyncBus.ubicaciones.value, ubicacionAntes + 1);
    });

    test('un pedido entregado avisa también al dinero', () {
      final pedidosAntes = SyncBus.pedidos.value;
      final dineroAntes = SyncBus.dinero.value;

      SyncBus.pedidoYdinero();

      expect(SyncBus.pedidos.value, pedidosAntes + 1);
      expect(SyncBus.dinero.value, dineroAntes + 1);
    });
  });

  group('frescura de la ubicación', () {
    test('sin fecha no hay ubicación', () {
      expect(EstadoUbicacion.desde(null), EstadoUbicacion.sinUbicacion);
    });

    test('menos de 2 minutos es en vivo', () {
      expect(
        EstadoUbicacion.desde(DateTime.now().subtract(const Duration(seconds: 30))),
        EstadoUbicacion.activo,
      );
    });

    test('más de 2 minutos ya no es en vivo', () {
      expect(
        EstadoUbicacion.desde(DateTime.now().subtract(const Duration(minutes: 5))),
        EstadoUbicacion.reciente,
      );
    });

    test('más de 10 minutos es sin actualizar', () {
      expect(
        EstadoUbicacion.desde(DateTime.now().subtract(const Duration(minutes: 30))),
        EstadoUbicacion.sinActualizar,
      );
    });
  });
}
