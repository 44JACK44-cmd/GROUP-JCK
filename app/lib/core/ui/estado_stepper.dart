/// Stepper visual del estado real de un pedido.
///
/// No inventa estados ni permite saltos: solo pinta lo que dice la base.
/// El botón que cambia el estado sigue en la pantalla del pedido y valida la
/// transición con [EstadoPedido.puedeTransicionarA] y con RLS en el servidor.
library;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../domain/estado_pedido.dart';

class EstadoStepper extends StatelessWidget {
  final String estado;
  final bool pagado;

  const EstadoStepper({
    super.key,
    required this.estado,
    this.pagado = false,
  });

  static const _pasos = <EstadoPedido>[
    EstadoPedido.nuevo,
    EstadoPedido.asignado,
    EstadoPedido.enCamino,
    EstadoPedido.entregado,
  ];

  @override
  Widget build(BuildContext context) {
    final estadoActual = EstadoPedido.desdeDb(estado);
    final esFinal = estadoActual == EstadoPedido.cancelado ||
        estadoActual == EstadoPedido.noEntregado;

    if (esFinal) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(estadoActual.icono, size: 20, color: estadoActual.color),
            const SizedBox(width: 8),
            Text(
              estadoActual.label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: estadoActual.color,
              ),
            ),
          ],
        ),
      );
    }

    final indice = _pasos.indexOf(estadoActual);
    final total = _pasos.length + (pagado ? 1 : 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < total; i++) ...[
              Expanded(
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: i <= indice || (pagado && i == total - 1)
                        ? AppTheme.primary
                        : const Color(0xFFE3E6E2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              if (i < total - 1) const SizedBox(width: 4),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < total; i++) ...[
              Expanded(
                child: Column(
                  children: [
                    Icon(
                      i == total - 1 && pagado
                          ? Icons.payments_outlined
                          : _pasos[i.clamp(0, _pasos.length - 1)].icono,
                      size: 18,
                      color: i <= indice || (pagado && i == total - 1)
                          ? AppTheme.primary
                          : Colors.black38,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      i == total - 1 && pagado
                          ? 'Pagado'
                          : _pasos[i.clamp(0, _pasos.length - 1)].label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: i <= indice || (pagado && i == total - 1)
                            ? AppTheme.primary
                            : Colors.black54,
                        fontWeight: i == indice ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
