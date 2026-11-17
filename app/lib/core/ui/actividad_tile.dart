/// Fila única para un movimiento de la jornada.
///
/// La usan el motorizado ("Mi registro") y el admin (detalle del motorizado):
/// así los dos ven exactamente la misma información y la misma foto de Yape.
library;

import 'package:gas_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../data/actividad_repo.dart';
import '../domain/formato.dart';
import 'widgets.dart';

class ActividadTile extends StatelessWidget {
  final MovimientoActividad movimiento;
  final VoidCallback? onTap;

  ActividadTile({super.key, required this.movimiento, this.onTap});

  @override
  Widget build(BuildContext context) {
    final m = movimiento;
    final (icono, color) = switch (m.tipo) {
      'PEDIDO' => (Icons.receipt_long_outlined, AppTheme.primary),
      'GASTO' => (Icons.payments_outlined, AppTheme.warning),
      'INCIDENCIA' => (Icons.build_outlined, AppTheme.danger),
      _ => (Icons.circle_outlined, AppColors.textoMuted),
    };
    final hora = '${m.fecha.hour.toString().padLeft(2, '0')}:'
        '${m.fecha.minute.toString().padLeft(2, '0')}';

    return Card(
      margin: EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            children: [
              if (m.comprobanteUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    m.comprobanteUrl!,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(icono, color: color),
                  ),
                )
              else
                Icon(icono, color: color),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.titulo,
                      style: TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 2),
                    Text(
                      [
                        hora,
                        if (m.detalle.isNotEmpty) m.detalle,
                        if (m.metodo != null) metodoPago(m.metodo),
                      ].join(' · '),
                      style: TextStyle(fontSize: 12, color: AppColors.textoSecundario),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (m.monto > 0)
                    Text(dinero(m.monto), style: TextStyle(fontWeight: FontWeight.bold)),
                  if (m.estado.isNotEmpty) ...[
                    SizedBox(height: 4),
                    EstadoBadge(m.estado, compacto: true),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}