import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/presentation/auth_controller.dart';

class MasItem {
  const MasItem(this.icon, this.label, this.route);

  final IconData icon;
  final String label;
  final String route;
}

class MasScreen extends ConsumerWidget {
  const MasScreen({super.key, required this.items});

  final List<MasItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Más')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                for (final item in items) ...[
                  ListTile(
                    leading: Icon(item.icon, color: AppColors.primary, size: 28),
                    title: Text(item.label, style: Theme.of(context).textTheme.titleMedium),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(item.route),
                  ),
                  if (item != items.last) const Divider(height: 1, indent: 16, endIndent: 16),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (user != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 4),
              child: Text('Sesión de ${user.nombre}', style: const TextStyle(color: AppColors.textSecondary)),
            ),
          OutlinedButton.icon(
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
            label: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
  }
}
