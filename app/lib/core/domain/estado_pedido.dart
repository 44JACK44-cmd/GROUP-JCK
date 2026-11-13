/// Estados del pedido y las transiciones permitidas.
///
/// Los valores de [db] son los que viven en `pedidos.estado`.
/// La capa de datos nunca escribe un estado suelto: siempre pasa por
/// [puedeTransicionar] para que no haya saltos incoherentes.
library;

import 'package:flutter/material.dart';

import '../../app/theme.dart';

enum EstadoPedido {
  nuevo('NUEVO', 'Pendiente', Icons.receipt_long_outlined),
  asignado('ASIGNADO', 'Asignado', Icons.person_outlined),
  enCamino('EN_CAMINO', 'En camino', Icons.route_outlined),
  entregado('ENTREGADO', 'Entregado', Icons.check_circle_outline),
  cancelado('CANCELADO', 'Cancelado', Icons.cancel_outlined),
  noEntregado('NO_ENTREGADO', 'No entregado', Icons.report_gmailerrorred_outlined);

  const EstadoPedido(this.db, this.label, this.icono);

  /// Valor guardado en la base de datos.
  final String db;

  /// Texto que ve el usuario.
  final String label;

  final IconData icono;

  bool get esFinalizado => this == EstadoPedido.entregado || this == EstadoPedido.cancelado;

  /// Color semántico del estado.
  Color get color => switch (this) {
        EstadoPedido.entregado => AppTheme.success,
        EstadoPedido.cancelado => AppTheme.danger,
        EstadoPedido.noEntregado => AppTheme.danger,
        EstadoPedido.asignado => AppTheme.warning,
        EstadoPedido.enCamino => AppTheme.warning,
        EstadoPedido.nuevo => AppTheme.info,
      };

  /// Traduce el valor de la BD. Estados desconocidos caen en [EstadoPedido.nuevo].
  static EstadoPedido desdeDb(Object? valor) {
    final v = valor?.toString();
    return EstadoPedido.values.firstWhere(
      (e) => e.db == v,
      orElse: () => EstadoPedido.nuevo,
    );
  }

  /// Estados a los que se puede pasar según el rol.
  /// `esAdmin` habilita las acciones administrativas explícitas
  /// (reabrir un pedido entregado, reactivar uno cancelado).
  Set<EstadoPedido> siguientes({required bool esAdmin}) {
    switch (this) {
      case EstadoPedido.nuevo:
        return {EstadoPedido.asignado, EstadoPedido.cancelado};
      case EstadoPedido.asignado:
        return {
          EstadoPedido.enCamino,
          EstadoPedido.nuevo, // desasignar
          EstadoPedido.cancelado,
        };
      case EstadoPedido.enCamino:
        return {
          EstadoPedido.entregado,
          EstadoPedido.noEntregado,
          EstadoPedido.cancelado,
        };
      case EstadoPedido.entregado:
        // Cerrado: solo un administrador puede reabrirlo (queda auditado).
        return esAdmin ? {EstadoPedido.enCamino} : <EstadoPedido>{};
      case EstadoPedido.cancelado:
        return esAdmin ? {EstadoPedido.nuevo} : <EstadoPedido>{};
      case EstadoPedido.noEntregado:
        return esAdmin
            ? {EstadoPedido.enCamino, EstadoPedido.cancelado}
            : <EstadoPedido>{};
    }
  }

  /// ¿La transición es válida?
  bool puedeTransicionarA(EstadoPedido destino, {required bool esAdmin}) =>
      siguientes(esAdmin: esAdmin).contains(destino);

  /// Mensaje comprensible cuando alguien intenta algo incoherente.
  String mensajeTransicionInvalida(EstadoPedido destino) => switch (this) {
        EstadoPedido.entregado =>
          'Este pedido ya fue entregado. Pide al administrador si necesitas reabrirlo.',
        EstadoPedido.cancelado => 'Este pedido está cancelado.',
        EstadoPedido.noEntregado => 'Este pedido quedó como no entregado.',
        _ => 'No se puede pasar de "$label" a "${destino.label}".',
      };
}

/// Grupo de estados mostrado en la lista de pedidos del administrador.
enum GrupoPedido {
  pendientes('Pendientes', ['NUEVO', 'ASIGNADO'], Icons.pending_actions_outlined),
  enCamino('En camino', ['EN_CAMINO'], Icons.route_outlined),
  completados('Completados', ['ENTREGADO'], Icons.check_circle_outline),
  cancelados('Cancelados', ['CANCELADO', 'NO_ENTREGADO'], Icons.cancel_outlined);

  const GrupoPedido(this.label, this.estados, this.icono);

  final String label;
  final List<String> estados;
  final IconData icono;
}
