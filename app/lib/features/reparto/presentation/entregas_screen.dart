import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../shared/greeting.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../auth/presentation/auth_controller.dart';

class EntregasScreen extends ConsumerWidget {
  const EntregasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).value;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Text(
                '${saludo(DateTime.now())}, ${user?.primerNombre ?? ''} 👋',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            const Expanded(
              child: EmptyState(
                icon: Icons.local_shipping_outlined,
                title: 'No tienes entregas pendientes',
                message: 'Cuando te asignen un pedido, aparecerá aquí.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
