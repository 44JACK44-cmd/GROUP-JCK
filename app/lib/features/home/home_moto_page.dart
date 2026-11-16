/// Inicio del motorizado: "MI DÍA".
///
/// Información práctica, sin gráficos: qué tengo que hacer, cuánto cobré
/// y qué quedó pendiente.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import '../../core/data/balones_repo.dart';
import '../../core/data/pedidos_repo.dart';
import '../../core/data/rendicion_repo.dart';
import '../../core/data/sb.dart';
import '../../core/domain/formato.dart';
import '../../core/location/ubicacion_service.dart';
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
  RealtimeChannel? _canal;

  @override
  void initState() {
    super.initState();
    _cargar();
    _escucharRealtime();
    UbicacionService.instance.iniciarSiCorresponde();
    UbicacionService.instance.estado.addListener(_onGps);
  }

  @override
  void dispose() {
    UbicacionService.instance.estado.removeListener(_onGps);
    _canal?.unsubscribe();
    super.dispose();
  }

  void _onGps() {
    if (mounted) setState(() {});
  }

  void _escucharRealtime() {
    final uid = ref.read(authProvider).usuarioId;
    if (uid == null) return;
    try {
      _canal = sb
          .channel('home-moto-$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'pedidos',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'repartidor_id',
              value: uid,
            ),
            callback: (_) {
              if (mounted) _cargar();
            },
          )
          .subscribe();
    } catch (_) {}
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

  Widget _gpsCard() {
    final servicio = UbicacionService.instance;
    final estado = servicio.estado.value;
    final ultimo = servicio.ultimoEnvio.value;
    final (color, icono) = switch (estado) {
      EstadoGps.activo => (AppTheme.success, Icons.location_on),
      EstadoGps.apagado => (Colors.black45, Icons.location_off_outlined),
      EstadoGps.sinPermiso => (AppTheme.danger, Icons.location_disabled),
      EstadoGps.sinSesion => (Colors.black45, Icons.person_off_outlined),
    };

    String detalle;
    switch (estado) {
      case EstadoGps.activo:
        detalle = ultimo == null
            ? 'Compartiendo tu ubicación con el administrador.'
            : 'Último envío ${antiguedad(ultimo).toLowerCase()}. Se actualiza sola.';
      case EstadoGps.apagado:
        detalle = 'Comparte tu ubicación solo mientras trabajas.';
      case EstadoGps.sinPermiso:
        detalle = 'La app necesita permiso de ubicación para el seguimiento.';
      case EstadoGps.sinSesion:
        detalle = 'Inicia sesión para compartir tu ubicación.';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icono, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    estado.label,
                    style: TextStyle(fontWeight: FontWeight.bold, color: color),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(detalle, style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
            const SizedBox(height: 8),
            if (estado == EstadoGps.activo)
              OutlinedButton.icon(
                onPressed: () => servicio.desactivar(),
                icon: const Icon(Icons.pause),
                label: const Text('Pausar ubicación'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              )
            else
              FilledButton.icon(
                onPressed: () async {
                  final r = await servicio.activar();
                  if (!mounted) return;
                  if (r == EstadoGps.sinPermiso) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Permiso denegado. Actívalo en Ajustes del teléfono para compartir tu ubicación.',
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('Activar ubicación'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              ),
          ],
        ),
      ),
    );
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
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => context.go('/mi-registro'),
                  icon: const Icon(Icons.edit_note, size: 26),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('MI REGISTRO', style: TextStyle(fontSize: 17)),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.info,
                    minimumSize: const Size.fromHeight(54),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _gpsCard(),
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
                      if (_hoy.gastosTotal > 0) ...[
                        const Divider(height: 22),
                        FilaValor('Gastos', dinero(_hoy.gastosTotal), color: AppTheme.warning),
                        FilaValor('Efectivo esperado', dinero(_hoy.efectivo - _hoy.gastosEfectivo),
                            destacado: true),
                      ],
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
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => context.push('/calendario'),
                icon: const Icon(Icons.calendar_month_outlined),
                label: const Text('Calendario'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
