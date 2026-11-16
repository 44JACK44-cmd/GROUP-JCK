/// Aviso interno de sincronización.
///
/// Regla de la fase: **una acción → un estado real → todas las pantallas
/// actualizadas**. Cada vez que una escritura termina bien (online o al
/// sincronizar la cola offline) se avisa aquí. Las pantallas abiertas escuchan
/// el aviso y vuelven a leer la base de datos; nunca inventan su propio estado.
///
/// No sustituye a Supabase Realtime: lo complementa. Realtime avisa cuando el
/// cambio viene de otro teléfono; este bus avisa cuando el cambio lo hizo esta
/// misma app (incluido lo que se acaba de sincronizar desde el Outbox).
library;

import 'package:flutter/foundation.dart';

class SyncBus {
  SyncBus._();

  /// Pedidos: crear, asignar, iniciar, entregar, cancelar, reabrir.
  static final ValueNotifier<int> pedidos = ValueNotifier<int>(0);

  /// Dinero y movimientos: pagos, gastos, balones, caja, rendición.
  static final ValueNotifier<int> dinero = ValueNotifier<int>(0);

  /// Ubicación GPS de los motorizados.
  static final ValueNotifier<int> ubicaciones = ValueNotifier<int>(0);

  static void pedidosCambiaron() => pedidos.value++;

  static void dineroCambio() => dinero.value++;

  static void ubicacionCambio() => ubicaciones.value++;

  /// Un cambio de pedido casi siempre mueve dinero y rendición.
  static void pedidoYdinero() {
    pedidosCambiaron();
    dineroCambio();
  }
}
