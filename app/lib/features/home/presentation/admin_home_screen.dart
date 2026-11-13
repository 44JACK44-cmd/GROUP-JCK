import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/greeting.dart';
import '../../../shared/widgets/action_tile.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../auth/presentation/auth_controller.dart';

class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).value;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          children: [
            Text('${saludo(DateTime.now())}, ${user?.primerNombre ?? ''} 👋', style: text.headlineSmall),
            const SizedBox(height: 4),
            Text('¿Qué necesitas hacer?', style: text.bodyLarge?.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 24),
            SizedBox(
              height: 72,
              child: PrimaryButton(
                label: 'NUEVO PEDIDO',
                icon: Icons.add_circle_outline,
                onPressed: () => context.push(Routes.nuevoPedido),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: ActionTile(icon: Icons.inventory_2_outlined, label: 'Pedidos', onTap: () => context.go(Routes.pedidos))),
                const SizedBox(width: 12),
                Expanded(child: ActionTile(icon: Icons.people_outline, label: 'Clientes', onTap: () => context.go(Routes.clientes))),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: ActionTile(icon: Icons.payments_outlined, label: 'Cobros', onTap: () => context.go(Routes.cobros))),
                const SizedBox(width: 12),
                Expanded(child: ActionTile(icon: Icons.propane_tank_outlined, label: 'Balones', onTap: () => context.push(Routes.balones))),
              ],
            ),
            const SizedBox(height: 28),
            Text('Hoy', style: text.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Aquí verás los pedidos por entregar, los cobros pendientes y los balones por devolver.',
              style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
