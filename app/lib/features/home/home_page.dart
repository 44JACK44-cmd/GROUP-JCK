/// Inicio del administrador.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/data/balones_repo.dart';
import '../../core/data/clientes_repo.dart';
import '../../core/data/pedidos_repo.dart';
import '../../core/domain/formato.dart';
import '../../core/ui/widgets.dart';
import '../auth/auth_controller.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _pendientes = 0;
  int _enCamino = 0;
  double _deudas = 0;
  int _balonesPendientes = 0;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final res = await Future.wait([
        pedidosRepo.contar(estados: const ['NUEVO', 'ASIGNADO']),
        pedidosRepo.contar(estados: const ['EN_CAMINO']),
        clientesRepo.deudasGlobales(),
        balonesRepo.pendientesBalones(),
      ]);
      if (!mounted) return;
      final deudas = (res[2] as Map<String, double>).values.fold<double>(0, (s, v) => s + v);
      final balones = (res[3] as List).fold<int>(0, (s, p) => s + (p.cantidad as int));
      setState(() {
        _pendientes = res[0] as int;
        _enCamino = res[1] as int;
        _deudas = deudas;
        _balonesPendientes = balones;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final hora = DateTime.now().hour;
    final saludo = hora < 12 ? 'Buenos dias' : (hora < 19 ? 'Buenas tardes' : 'Buenas noches');

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _cargar,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => context.push('/pedidos/nuevo'),
                  icon: const Icon(Icons.add, size: 26),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text('NUEVO PEDIDO', style: TextStyle(fontSize: 18)),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    minimumSize: const Size.fromHeight(60),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$saludo, ${auth.nombre ?? ''}',
                            style: Theme.of(context).textTheme.titleLarge),
                        Text(auth.empresaNombre ?? '',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppTheme.primary, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar sesion',
                    onPressed: () => ref.read(authProvider.notifier).logout(),
                    icon: const Icon(Icons.logout),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Que necesitas ver?', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.5,
                children: [
                  TarjetaMetrica(
                    titulo: 'Pedidos pendientes',
                    valor: _cargando ? '...' : '$_pendientes',
                    icono: Icons.pending_actions_outlined,
                    color: AppTheme.warning,
                    onTap: () => context.go('/pedidos'),
                  ),
                  TarjetaMetrica(
                    titulo: 'Entregas en curso',
                    valor: _cargando ? '...' : '$_enCamino',
                    icono: Icons.route_outlined,
                    color: AppTheme.info,
                    onTap: () => context.go('/pedidos'),
                  ),
                  TarjetaMetrica(
                    titulo: 'Deudas pendientes',
                    valor: _cargando ? '...' : dinero(_deudas, conDecimales: false),
                    icono: Icons.account_balance_wallet_outlined,
                    color: _deudas > 0 ? AppTheme.danger : AppTheme.success,
                    onTap: () => context.push('/deudas'),
                  ),
                  TarjetaMetrica(
                    titulo: 'Balones pendientes',
                    valor: _cargando ? '...' : '$_balonesPendientes',
                    icono: Icons.local_fire_department_outlined,
                    color: AppTheme.warning,
                    onTap: () => context.push('/balones'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => context.go('/pedidos'),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('VER PEDIDOS'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              ),
              const SizedBox(height: 20),
              Text('Dinero y control', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.7,
                children: [
                  _Acceso(icono: Icons.point_of_sale_outlined, titulo: 'Caja', onTap: () => context.push('/caja')),
                  _Acceso(icono: Icons.assignment_turned_in_outlined, titulo: 'Rendicion', onTap: () => context.push('/rendicion')),
                  _Acceso(icono: Icons.bar_chart_outlined, titulo: 'Reportes', onTap: () => context.push('/reportes')),
                  _Acceso(icono: Icons.delivery_dining_outlined, titulo: 'Motorizados', onTap: () => context.push('/motorizados-actividad')),
                ],
              ),
              const SizedBox(height: 20),
              Text('Accesos rapidos', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.7,
                children: [
                  _Acceso(icono: Icons.people_outline, titulo: 'Clientes', onTap: () => context.go('/clientes')),
                  _Acceso(icono: Icons.calendar_month_outlined, titulo: 'Calendario', onTap: () => context.push('/calendario')),
                  _Acceso(icono: Icons.payments_outlined, titulo: 'Cobros', onTap: () => context.go('/cobros')),
                  _Acceso(icono: Icons.compare_arrows, titulo: 'Conciliacion', onTap: () => context.push('/conciliacion')),
                  _Acceso(icono: Icons.grid_view_outlined, titulo: 'Mas', onTap: () => context.go('/mas')),
                ],
              ),
            ],
          ),
        ),
      ),
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
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icono, color: AppTheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
