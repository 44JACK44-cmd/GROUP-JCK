/// Inicio del motorizado: "MI DÍA".
///
/// Información práctica, sin gráficos: qué tengo que hacer, cuánto cobré
/// y qué quedó pendiente.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/data/balones_repo.dart';
import '../../core/data/pedidos_repo.dart';
import '../../core/data/rendicion_repo.dart';
import '../../core/domain/formato.dart';
import '../../core/ui/widgets.dart';
import '../auth/auth_controller.dart';

class HomeMotoPage extends ConsumerStatefulWidget {
  const HomeMotoPage({super.key});

  @override
  ConsumerState<HomeMotoPage> createState() => _HomeMotoPageState();
}

class _HomeMotoPageState extends ConsumerState<HomeMotoPage> {
  Rendicion _hoy = const Rendicion();
  int _porEntregar = 0;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final uid = ref.read(authProvider).usuarioId;
    if (uid == null) return;
    try {
      final inicio = inicioHoy();
      final fin = DateTime.now().add(const Duration(minutes: 1));
      final res = await Future.wait([
        rendicionRepo.calcular(desde: inicio, hasta: fin, motorizadoId: uid),
        pedidosRepo.listar(
          repartidorId: uid,
          estados: const ['ASIGNADO', 'EN_CAMINO'],
          limite: 100,
        ),
        balonesRepo.pendientesBalones(),
      ]);
      if (!mounted) return;
      setState(() {
        _hoy = res[0] as Rendicion;
        _porEntregar = (res[1] as List).length;
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
    final saludo = hora < 12 ? 'Buenos días' : (hora < 19 ? 'Buenas tardes' : 'Buenas noches');

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _cargar,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$saludo, ${auth.nombre ?? ''} 👋',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 2),
                        Text(
                          _porEntregar > 0
                              ? 'Tienes $_porEntregar pedido(s) por entregar.'
                              : 'No tienes pedidos por entregar.',
                          style: const TextStyle(
                            color: Colors.black54,
                            fontWeight: FontWeight.w600,
                          ),
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
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => context.go('/mis-pedidos'),
                  icon: const Icon(Icons.delivery_dining_outlined, size: 26),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('VER MIS PEDIDOS', style: TextStyle(fontSize: 17)),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    minimumSize: const Size.fromHeight(58),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text('MI DÍA', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FilaValor('Pedidos', '${_hoy.pedidosRealizados}'),
                      FilaValor('Entregados', '${_hoy.entregados}', color: AppTheme.success),
                      FilaValor('Por entregar', '$_porEntregar', color: AppTheme.warning),
                      const Divider(height: 22),
                      FilaValor('Cobrado', dinero(_hoy.cobrado), destacado: true),
                      FilaValor('Yape', dinero(_hoy.yape), color: AppTheme.info),
                      FilaValor('Efectivo', dinero(_hoy.efectivo)),
                      if (_hoy.pendiente > 0)
                        FilaValor('Pendiente de cobro', dinero(_hoy.pendiente),
                            color: AppTheme.danger),
                      const Divider(height: 22),
                      FilaValor('Balones vacíos recibidos', '${_hoy.balonesVaciosRecibidos}'),
                      FilaValor('Balones vacíos pendientes', '${_hoy.balonesVaciosPendientes}',
                          color: _hoy.balonesVaciosPendientes > 0 ? AppTheme.warning : null),
                    ],
                  ),
                ),
              ),
              if (_cargando)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(color: AppTheme.primary),
                ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => context.go('/historial'),
                icon: const Icon(Icons.history_outlined),
                label: const Text('Ver historial de mis pedidos'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
