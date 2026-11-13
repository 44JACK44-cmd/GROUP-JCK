import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_controller.dart';
import '../../app/theme.dart';

/// Pantalla principal del repartidor: sus entregas del día.
/// Fase 1: estructura base; la lista real de pedidos llega en Fase 4.
class RepartoPage extends ConsumerWidget {
  const RepartoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final hora = DateTime.now().hour;
    final saludo = hora < 12 ? 'Buenos días' : (hora < 19 ? 'Buenas tardes' : 'Buenas noches');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis entregas'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: () => ref.read(authProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$saludo, ${auth.nombre ?? ''} 👋',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              const Text('🚚 Tus entregas aparecerán aquí.',
                  style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 28),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 48, color: AppTheme.primary),
                      SizedBox(height: 12),
                      Text(
                        'No tienes pedidos por entregar.\nCuando te asignen uno, aparecerá aquí.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
