/// Contenedor principal con la barra de navegación inferior.
///
/// La navegación se adapta al rol:
///  - ADMIN: Inicio · Pedidos · Clientes · Cobros · Más
///  - MOTORIZADO: Inicio · Mis pedidos · Historial · Más
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../auth/auth_controller.dart';

/// Una pestaña de la barra inferior.
class Pestana {
  final String ruta;
  final String label;
  final IconData icono;
  final IconData? iconoActivo;

  const Pestana({
    required this.ruta,
    required this.label,
    required this.icono,
    this.iconoActivo,
  });

  IconData get activo => iconoActivo ?? icono;
}

/// Pestañas del administrador.
const List<Pestana> pestanasAdmin = [
  Pestana(ruta: '/inicio', label: 'Inicio', icono: Icons.home_outlined, iconoActivo: Icons.home),
  Pestana(
      ruta: '/pedidos',
      label: 'Pedidos',
      icono: Icons.receipt_long_outlined,
      iconoActivo: Icons.receipt_long),
  Pestana(
      ruta: '/clientes',
      label: 'Clientes',
      icono: Icons.people_outline,
      iconoActivo: Icons.people),
  Pestana(
      ruta: '/cobros',
      label: 'Cobros',
      icono: Icons.payments_outlined,
      iconoActivo: Icons.payments),
  Pestana(ruta: '/mas', label: 'Más', icono: Icons.grid_view_outlined, iconoActivo: Icons.grid_view),
];

/// Pestañas del motorizado.
const List<Pestana> pestanasMotorizado = [
  Pestana(ruta: '/inicio', label: 'Inicio', icono: Icons.home_outlined, iconoActivo: Icons.home),
  Pestana(
      ruta: '/mis-pedidos',
      label: 'Mis pedidos',
      icono: Icons.delivery_dining_outlined,
      iconoActivo: Icons.delivery_dining),
  Pestana(
      ruta: '/historial',
      label: 'Historial',
      icono: Icons.history_outlined,
      iconoActivo: Icons.history),
  Pestana(ruta: '/mas-moto', label: 'Más', icono: Icons.grid_view_outlined, iconoActivo: Icons.grid_view),
];

class AppShell extends ConsumerWidget {
  final Widget child;
  final String location;

  const AppShell({super.key, required this.child, required this.location});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final pestanas = auth.esMotorizado ? pestanasMotorizado : pestanasAdmin;

    var index = pestanas.indexWhere((p) => location.startsWith(p.ruta));
    if (index < 0) index = 0;

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        backgroundColor: Colors.white,
        indicatorColor: AppTheme.primary.withValues(alpha: 0.12),
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) {
          final ruta = pestanas[i].ruta;
          if (ruta != location) {
            // go_router aplica el redirect por rol.
            context.go(ruta);
          }
        },
        destinations: [
          for (final p in pestanas)
            NavigationDestination(
              icon: Icon(p.icono),
              selectedIcon: Icon(p.activo, color: AppTheme.primary),
              label: p.label,
            ),
        ],
      ),
    );
  }
}
