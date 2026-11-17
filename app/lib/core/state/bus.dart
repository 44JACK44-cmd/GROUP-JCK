/// Bus de eventos de la aplicación.
///
/// Una sola acción real (propia o de otro teléfono vía Realtime) incrementa
/// exactamente los avisos que corresponden. Las pantallas abiertas escuchan
/// estos `ValueNotifier` y vuelven a leer la base de datos: nunca mantienen un
/// estado paralelo ni dependen de que el usuario pulse "Actualizar".
library;

import 'package:flutter/foundation.dart';

class SyncBus {
  SyncBus._();

  /// Pedidos: crear, asignar, aceptar, iniciar, entregar, cancelar, reabrir.
  static final ValueNotifier<int> pedidos = ValueNotifier<int>(0);

  /// Dinero: pagos, Yape, deuda, gastos, caja.
  static final ValueNotifier<int> dinero = ValueNotifier<int>(0);

  /// Ubicación GPS de los motorizados.
  static final ValueNotifier<int> ubicaciones = ValueNotifier<int>(0);

  /// Movimientos visibles (pedidos, cobros, gastos, fallas, balones).
  static final ValueNotifier<int> movimientos = ValueNotifier<int>(0);

  /// Rendiciones y cierres.
  static final ValueNotifier<int> rendiciones = ValueNotifier<int>(0);

  /// Estado de conexión (true = hay Internet).
  static final ValueNotifier<bool> enLinea = ValueNotifier<bool>(true);

  /// La cola offline está enviando operaciones.
  static final ValueNotifier<bool> sincronizando = ValueNotifier<bool>(false);

  static void pedidosCambiaron() {
    pedidos.value++;
    movimientos.value++;
  }

  static void dineroCambio() {
    dinero.value++;
    movimientos.value++;
  }

  static void ubicacionCambio() => ubicaciones.value++;

  static void movimientosCambiaron() => movimientos.value++;

  static void rendicionCambio() {
    rendiciones.value++;
    movimientos.value++;
  }

  /// Un cambio de pedido casi siempre mueve dinero, movimientos y rendición.
  static void pedidoYdinero() {
    pedidosCambiaron();
    dineroCambio();
    rendicionCambio();
  }

  static void conexionCambio(bool enLinea) {
    if (SyncBus.enLinea.value == enLinea) return;
    SyncBus.enLinea.value = enLinea;
    movimientos.value++;
  }

  static void sincronizandoCambio(bool valor) {
    if (sincronizando.value == valor) return;
    sincronizando.value = valor;
  }

  /// Aviso global usado al reconectar o al aplicar una migración.
  static void todoCambio() {
    pedidos.value++;
    dinero.value++;
    ubicaciones.value++;
    movimientos.value++;
    rendiciones.value++;
  }
}