/// Contenedor principal con la barra de navegación inferior.
///
/// La navegación se adapta al rol:
///  - ADMIN: Inicio · Pedidos · Clientes · Cobros · Más
///  - MOTORIZADO: Inicio · Mis pedidos · Historial · Más
library;

import 'package:gas_app/core/theme/app_colors.dart';
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

  Pestana({
    required this.ruta,
    required this.label,
    required this.icono,
    this.iconoActivo,
  });

  IconData get activo => iconoActivo ?? icono;
}

/// Pestañas del administrador.
List<Pestana> pestanasAdmin = [
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
      ruta: '/caja',
      label: 'Caja',
      icono: Icons.account_balance_outlined,
      iconoActivo: Icons.account_balance),
  Pestana(ruta: '/mas', label: 'Más', icono: Icons.grid_view_outlined, iconoActivo: Icons.grid_view),
];

/// Pestañas del motorizado.
List<Pestana> pestanasMotorizado = [
  Pestana(ruta: '/inicio', label: 'Inicio', icono: Icons.home_outlined, iconoActivo: Icons.home),
  Pestana(
      ruta: '/mis-pedidos',
      label: 'Pedidos',
      icono: Icons.receipt_long_outlined,
      iconoActivo: Icons.receipt_long),
  Pestana(
      ruta: '/movimientos',
      label: 'Movimientos',
      icono: Icons.timeline_outlined,
      iconoActivo: Icons.timeline),
  Pestana(ruta: '/mas-moto', label: 'Más', icono: Icons.grid_view_outlined, iconoActivo: Icons.grid_view),
];

class AppShell extends ConsumerWidget {
  final Widget child;
  final String location;

  AppShell({super.key, required this.child, required this.location});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final pestanas = auth.esMotorizado ? pestanasMotorizado : pestanasAdmin;

    final index = indicePestanaActiva(pestanas, location, esAdmin: auth.esAdmin);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        backgroundColor: AppColors.superficie,
        indicatorColor: AppTheme.primary.withValues(alpha: 0.14),
        surfaceTintColor: AppColors.superficie,
        height: 70,
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

/// Qué pestaña debe quedar resaltada según la ruta actual.
///
/// Se elige la coincidencia más específica (`/pedidos/nuevo` resalta
/// "Pedidos") y las pantallas del admin que no son pestaña se mapean a su
/// sección real.
int indicePestanaActiva(
  List<Pestana> pestanas,
  String location, {
  required bool esAdmin,
}) {
  var indice = -1;
  var largo = 0;
  for (var i = 0; i < pestanas.length; i++) {
    final ruta = pestanas[i].ruta;
    final coincide = location == ruta || location.startsWith('$ruta/');
    if (coincide && ruta.length > largo) {
      indice = i;
      largo = ruta.length;
    }
  }
  if (indice >= 0) return indice;

  // Pantallas del administrador dentro de una sección con pestaña.
  if (esAdmin) {
    final seccion = switch (location) {
      '/mis-pedidos' ||
      '/historial' ||
      '/balones' ||
      '/mi-registro' ||
      '/mi-registro/pedido' ||
      '/mi-registro/gasto' ||
      '/mi-registro/incidencia' =>
        '/pedidos',
      _ => null,
    };
    if (seccion != null) {
      final i = pestanas.indexWhere((p) => p.ruta == seccion);
      if (i >= 0) return i;
    }
  }
  return 0;
}