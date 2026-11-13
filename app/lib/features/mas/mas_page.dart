import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';

/// Menú "Más": módulos secundarios del administrador.
class MasPage extends StatelessWidget {
  const MasPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Más')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Tile(
            icono: Icons.local_fire_department_outlined,
            titulo: 'Balones',
            subtitulo: 'Control de balones prestados y devoluciones',
            color: AppTheme.warning,
            onTap: () => context.push('/balones'),
          ),
          _Tile(
            icono: Icons.point_of_sale_outlined,
            titulo: 'Caja',
            subtitulo: 'Dinero del día, gastos e ingresos',
            color: AppTheme.success,
            onTap: () => context.push('/caja'),
          ),
          _Tile(
            icono: Icons.payments_outlined,
            titulo: 'Cobros',
            subtitulo: 'Registrar pagos y ver historial',
            color: AppTheme.info,
            onTap: () => context.push('/cobros'),
          ),
          _Tile(
            icono: Icons.local_gas_station_outlined,
            titulo: 'Combustible',
            subtitulo: 'Gastos de gasolina por vehículo',
            color: AppTheme.warning,
            onTap: () => context.push('/combustible'),
          ),
          _Tile(
            icono: Icons.bar_chart_outlined,
            titulo: 'Reportes',
            subtitulo: 'Ventas, cobros y gastos del día y la semana',
            color: AppTheme.primary,
            onTap: () => context.push('/reportes'),
          ),
          _Tile(
            icono: Icons.delivery_dining_outlined,
            titulo: 'Motorizados',
            subtitulo: 'Tu equipo de reparto',
            color: AppTheme.primary,
            onTap: () => context.push('/motorizados'),
          ),
          _Tile(
            icono: Icons.people_outline,
            titulo: 'Clientes',
            subtitulo: 'Directorio de clientes',
            color: AppTheme.primary,
            onTap: () => context.push('/clientes'),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String subtitulo;
  final Color color;
  final VoidCallback onTap;

  const _Tile({
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icono, color: color),
        ),
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitulo, style: const TextStyle(color: Colors.black54)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
