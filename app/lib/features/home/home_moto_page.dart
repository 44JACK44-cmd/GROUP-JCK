/// Inicio del motorizado: cuatro tareas reales, sin gráficos ni ruido.
///
/// Mis pedidos · Mi registro · Gastos · Rendición.
/// Todo lo demás (historial, calendario) sigue disponible desde esas pantallas.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import '../../core/data/pedidos_repo.dart';
import '../../core/data/rendicion_repo.dart';
import '../../core/data/sb.dart';
import '../../core/domain/formato.dart';
import '../../core/location/ubicacion_service.dart';
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
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'gastos',
            callback: (_) {
              if (mounted) _cargar();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'fondo_vuelto',
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

  Widget _seccion({
    required IconData icono,
    required Color color,
    required String titulo,
    required String detalle,
    required String accion,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icono, color: color, size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      titulo,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(detalle,
                  style: const TextStyle(color: Colors.black54, fontSize: 13)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  minimumSize: const Size.fromHeight(44),
                ),
                child: Text(accion),
              ),
            ],
          ),
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
                              ? '🟢 Jornada activa · $_porEntregar pedido(s) por entregar'
                              : '🟢 Jornada activa · sin pedidos por entregar',
                          style: const TextStyle(
                            color: AppTheme.success,
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
              const SizedBox(height: 16),
              _seccion(
                icono: Icons.delivery_dining_outlined,
                color: AppTheme.primary,
                titulo: 'MIS PEDIDOS',
                detalle: '$_porEntregar pendiente(s) · ${_hoy.entregados} entregados hoy',
                accion: 'VER PEDIDOS',
                onTap: () => context.go('/mis-pedidos'),
              ),
              const SizedBox(height: 12),
              _seccion(
                icono: Icons.edit_note,
                color: AppTheme.info,
                titulo: 'MI REGISTRO',
                detalle: '${_hoy.pedidosRealizados} pedidos · '
                    '${dinero(_hoy.totalACobrar)} ventas · fondo '
                    '${dinero(_hoy.fondoInicial)}',
                accion: 'REGISTRAR MOVIMIENTO',
                onTap: () => context.go('/mi-registro'),
              ),
              const SizedBox(height: 12),
              _seccion(
                icono: Icons.payments_outlined,
                color: AppTheme.warning,
                titulo: 'GASTOS',
                detalle: '${dinero(_hoy.gastosTotal)} gastados hoy',
                accion: 'REGISTRAR GASTO',
                onTap: () => context.push('/mi-registro/gasto'),
              ),
              const SizedBox(height: 12),
              _seccion(
                icono: Icons.assignment_turned_in_outlined,
                color: AppTheme.success,
                titulo: 'RENDICIÓN',
                detalle: 'Esperado ${dinero(_hoy.efectivoEsperado)}'
                    '${_hoy.hayDeclaracion ? ' · declarado ${dinero(_hoy.efectivoDeclarado)}' : ''}',
                accion: 'VER MI RENDICIÓN',
                onTap: () => context.push('/declarar-rendicion'),
              ),
              const SizedBox(height: 12),
              _gpsCard(),
              if (_cargando)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(color: AppTheme.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
