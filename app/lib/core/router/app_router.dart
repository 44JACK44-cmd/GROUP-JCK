import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/auth/domain/user_session.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/home/presentation/admin_home_screen.dart';
import '../../features/mas/presentation/mas_screen.dart';
import '../../features/mas/presentation/section_screen.dart';
import '../../features/reparto/presentation/entregas_screen.dart';
import '../../features/shell/presentation/app_shell.dart';
import '../../shared/widgets/loading_state.dart';
import 'routes.dart';

/// Decide a dónde ir según la sesión y el rol. El repartidor nunca entra a rutas de administrador.
String? redirectFor(AsyncValue<UserSession?> auth, String location) {
  if (auth.isLoading && !auth.hasValue) return location == Routes.splash ? null : Routes.splash;
  final user = auth.value;
  if (user == null) return location == Routes.login ? null : Routes.login;
  final home = user.rol == UserRole.repartidor ? Routes.entregas : Routes.inicio;
  if (location == Routes.login || location == Routes.splash) return home;
  final permitido = user.rol == UserRole.repartidor
      ? Routes.isRepartidorRoute(location)
      : Routes.isAdminRoute(location);
  return permitido ? null : home;
}

const _masAdmin = [
  MasItem(Icons.propane_tank_outlined, 'Balones', Routes.balones),
  MasItem(Icons.local_gas_station_outlined, 'Combustible', Routes.combustible),
  MasItem(Icons.point_of_sale_outlined, 'Caja', Routes.caja),
  MasItem(Icons.bar_chart_outlined, 'Reportes', Routes.reportes),
  MasItem(Icons.settings_outlined, 'Configuración', Routes.configuracion),
];

const _masRepartidor = [
  MasItem(Icons.local_gas_station_outlined, 'Combustible', Routes.repartoCombustible),
];

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  GoRoute section(String path, String title, IconData icon, String emptyTitle, String emptyMessage) => GoRoute(
        path: path,
        builder: (_, _) => SectionScreen(title: title, icon: icon, emptyTitle: emptyTitle, emptyMessage: emptyMessage),
      );

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) => redirectFor(ref.read(authControllerProvider), state.matchedLocation),
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const Scaffold(body: LoadingState())),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      section(Routes.nuevoPedido, 'Nuevo pedido', Icons.add_circle_outline, 'Registro de pedidos',
          'Aquí registrarás un pedido en pocos pasos mientras atiendes la llamada.'),
      section(Routes.balones, 'Balones', Icons.propane_tank_outlined, 'Control de balones',
          'Aquí verás balones llenos, vacíos, en clientes y pendientes de devolución.'),
      section(Routes.combustible, 'Combustible', Icons.local_gas_station_outlined, 'Sin cargas de combustible',
          'Cuando registres combustible, aparecerá aquí.'),
      section(Routes.caja, 'Caja', Icons.point_of_sale_outlined, 'Caja cerrada',
          'Aquí abrirás la caja y verás ingresos y egresos del día.'),
      section(Routes.reportes, 'Reportes', Icons.bar_chart_outlined, 'Resumen del día',
          'Aquí verás pedidos, ventas, cobros y combustible del día.'),
      section(Routes.configuracion, 'Configuración', Icons.settings_outlined, 'Configuración',
          'Aquí gestionarás productos, precios, usuarios y vehículos.'),
      section(Routes.repartoCombustible, 'Combustible', Icons.local_gas_station_outlined, 'Sin cargas de combustible',
          'Cuando registres combustible, aparecerá aquí.'),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(shell: shell, tabs: adminTabs),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: Routes.inicio, builder: (_, _) => const AdminHomeScreen())]),
          StatefulShellBranch(routes: [
            section(Routes.pedidos, 'Pedidos', Icons.inventory_2_outlined, 'No hay pedidos pendientes',
                'Cuando llegue un nuevo pedido, aparecerá aquí.'),
          ]),
          StatefulShellBranch(routes: [
            section(Routes.clientes, 'Clientes', Icons.people_outline, 'Aún no hay clientes',
                'Los clientes que registres aparecerán aquí.'),
          ]),
          StatefulShellBranch(routes: [
            section(Routes.cobros, 'Cobros', Icons.payments_outlined, 'No hay cobros pendientes',
                'Los clientes que deban dinero aparecerán aquí.'),
          ]),
          StatefulShellBranch(routes: [GoRoute(path: Routes.mas, builder: (_, _) => const MasScreen(items: _masAdmin))]),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(shell: shell, tabs: repartidorTabs),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: Routes.entregas, builder: (_, _) => const EntregasScreen())]),
          StatefulShellBranch(routes: [
            section(Routes.repartoCobros, 'Cobros', Icons.payments_outlined, 'No tienes cobros pendientes',
                'Los cobros de tus entregas aparecerán aquí.'),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.repartoMas, builder: (_, _) => const MasScreen(items: _masRepartidor)),
          ]),
        ],
      ),
    ],
  );
});
