import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class ShellTab {
  const ShellTab(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const adminTabs = [
  ShellTab('Inicio', Icons.home_outlined, Icons.home),
  ShellTab('Pedidos', Icons.inventory_2_outlined, Icons.inventory_2),
  ShellTab('Clientes', Icons.people_outline, Icons.people),
  ShellTab('Cobros', Icons.payments_outlined, Icons.payments),
  ShellTab('Más', Icons.menu, Icons.menu),
];

const repartidorTabs = [
  ShellTab('Entregas', Icons.local_shipping_outlined, Icons.local_shipping),
  ShellTab('Cobros', Icons.payments_outlined, Icons.payments),
  ShellTab('Más', Icons.menu, Icons.menu),
];

/// Barra inferior común. Cada rol recibe sus propias pestañas.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell, required this.tabs});

  final StatefulNavigationShell shell;
  final List<ShellTab> tabs;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          for (final t in tabs)
            NavigationDestination(icon: Icon(t.icon), selectedIcon: Icon(t.selectedIcon), label: t.label),
        ],
      ),
    );
  }
}
