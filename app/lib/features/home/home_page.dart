import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_controller.dart';
import '../../app/theme.dart';

/// Pantalla de inicio del administrador.
/// Fase 1: estructura base con accesos directos; los módulos se
/// implementan en las fases 2-6.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final hora = DateTime.now().hour;
    final saludo = hora < 12 ? 'Buenos días' : (hora < 19 ? 'Buenas tardes' : 'Buenas noches');

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$saludo 👋',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          auth.empresaNombre ?? '',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppTheme.primary, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          auth.nombre ?? '',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar sesión',
                    onPressed: () => ref.read(authProvider.notifier).logout(),
                    icon: const Icon(Icons.logout),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Acción principal
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _proximamente(context, 'Nuevo pedido'),
                  icon: const Icon(Icons.add_circle_outline, size: 28),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('NUEVO PEDIDO', style: TextStyle(fontSize: 18)),
                  ),
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                ),
              ),
              const SizedBox(height: 16),
              // Accesos rápidos (2 columnas)
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.6,
                children: [
                  _Acceso(icono: Icons.inventory_2_outlined, titulo: 'Pedidos',
                      onTap: () => _proximamente(context, 'Pedidos')),
                  _Acceso(icono: Icons.people_outline, titulo: 'Clientes',
                      onTap: () => _proximamente(context, 'Clientes')),
                  _Acceso(icono: Icons.payments_outlined, titulo: 'Cobros',
                      onTap: () => _proximamente(context, 'Cobros')),
                  _Acceso(icono: Icons.delivery_dining_outlined, titulo: 'Motorizados',
                      onTap: () => context.push('/motorizados')),
                  _Acceso(icono: Icons.local_fire_department_outlined, titulo: 'Balones',
                      onTap: () => _proximamente(context, 'Balones')),
                ],
              ),
              const SizedBox(height: 28),
              Text('Hoy', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Los resúmenes del día aparecerán aquí cuando estén disponibles.',
                    style: TextStyle(color: Colors.black54),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _proximamente(BuildContext context, String modulo) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$modulo estará disponible pronto')),
    );
  }
}

class _Acceso extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final VoidCallback onTap;

  const _Acceso({required this.icono, required this.titulo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icono, size: 30, color: AppTheme.primary),
              const SizedBox(height: 8),
              Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
