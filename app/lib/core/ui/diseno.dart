/// Componentes visuales reutilizables del rediseño.
///
/// Interfaz sobria: blanco y gris claro, azul moderado para acciones, verde
/// para éxito, naranja para advertencia y rojo solo para errores. Sin emojis:
/// todos los iconos son `IconData` de Material.
library;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../data/actividad_repo.dart';
import '../domain/formato.dart';
import 'widgets.dart';

/// Contenedor con el mismo radio y borde en toda la app.
class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;

  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Padding(padding: padding, child: child),
            ),
    );
  }
}

/// Botón de acción principal, con icono profesional y alto cómodo.
class ActionButton extends StatelessWidget {
  final String texto;
  final IconData icono;
  final VoidCallback? onPressed;
  final Color? color;
  final bool destacado;

  const ActionButton({
    super.key,
    required this.texto,
    required this.icono,
    this.onPressed,
    this.color,
    this.destacado = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.primary;
    final child = FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icono, size: 22),
      label: Text(texto),
      style: FilledButton.styleFrom(
        backgroundColor: destacado ? c : c.withValues(alpha: 0.08),
        foregroundColor: destacado ? Colors.white : c,
        minimumSize: const Size.fromHeight(52),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
    );
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: texto,
      child: child,
    );
  }
}

/// Título de sección, discreto y consistente.
class SectionTitle extends StatelessWidget {
  final String texto;
  final Widget? trailing;

  const SectionTitle(this.texto, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            texto,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Indicador de carga pequeño y alineado.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      ),
    );
  }
}

/// Insignia de estado con color y texto (nunca solo color).
class StatusBadge extends StatelessWidget {
  final String estado;
  final bool compacto;

  const StatusBadge(this.estado, {super.key, this.compacto = false});

  @override
  Widget build(BuildContext context) => EstadoBadge(estado, compacto: compacto);
}

/// Icono profesional para cada tipo de movimiento real.
IconData iconoMovimiento(String tipo) => switch (tipo) {
      'PEDIDO' => Icons.receipt_long_outlined,
      'PAGO' => Icons.account_balance_wallet_outlined,
      'GASTO' => Icons.local_gas_station_outlined,
      'INCIDENCIA' => Icons.build_outlined,
      'BALON' => Icons.local_fire_department_outlined,
      _ => Icons.timeline,
    };

Color colorMovimiento(String tipo) => switch (tipo) {
      'PEDIDO' => AppTheme.primary,
      'PAGO' => AppTheme.success,
      'GASTO' => AppTheme.warning,
      'INCIDENCIA' => AppTheme.danger,
      _ => Colors.black54,
    };

/// Fila de movimiento: hora, icono, descripción, pedido, usuario y monto.
class MovementTile extends StatelessWidget {
  final MovimientoActividad movimiento;

  const MovementTile(this.movimiento, {super.key});

  @override
  Widget build(BuildContext context) {
    final m = movimiento;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: colorMovimiento(m.tipo).withValues(alpha: 0.12),
        child: Icon(iconoMovimiento(m.tipo),
            size: 20, color: colorMovimiento(m.tipo)),
      ),
      title: Text(
        m.titulo,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        [
          horaCorta(m.fecha),
          if (m.detalle.isNotEmpty) m.detalle,
          if (m.pedidoId != null) 'Pedido ${m.pedidoId}',
          if (m.estado.isNotEmpty) m.estado,
        ].join('  ·  '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: Colors.black54),
      ),
      trailing: m.monto > 0
          ? Text(
              dinero(m.monto),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            )
          : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    );
  }
}

/// Resumen de dinero usado en rendición y declaración.
class PaymentSummary extends StatelessWidget {
  final double efectivo;
  final double yape;
  final double deuda;
  final double fondo;
  final double gastosEfectivo;
  final double esperado;

  const PaymentSummary({
    super.key,
    required this.efectivo,
    required this.yape,
    required this.deuda,
    required this.fondo,
    required this.gastosEfectivo,
    required this.esperado,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilaValor('Fondo de vuelto', dinero(fondo)),
          FilaValor('Efectivo cobrado', dinero(efectivo)),
          FilaValor('Gastos en efectivo', dinero(gastosEfectivo)),
          const Divider(height: 18),
          FilaValor('Efectivo esperado', dinero(esperado), destacado: true),
          FilaValor('Yape (no es efectivo)', dinero(yape)),
          FilaValor('Deuda (no es efectivo)', dinero(deuda)),
        ],
      ),
    );
  }
}
