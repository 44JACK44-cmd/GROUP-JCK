/// Actividad de los motorizados (vista del recepcionista/admin).
///
/// Muestra, por motorizado, el resumen del día y la lista de movimientos
/// (pedidos entregados y gastos) en orden cronológico. Se actualiza en tiempo
/// real cuando un motorizado registra algo.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import '../../core/data/actividad_repo.dart';
import '../../core/data/motorizados_repo.dart';
import '../../core/data/rendicion_repo.dart';
import '../../core/data/sb.dart';
import '../../core/domain/formato.dart';
import '../../core/state/bus.dart';
import '../../core/ui/actividad_tile.dart';
import '../../core/ui/widgets.dart';

class MotorizadosActividadPage extends ConsumerStatefulWidget {
  const MotorizadosActividadPage({super.key});

  @override
  ConsumerState<MotorizadosActividadPage> createState() =>
      _MotorizadosActividadPageState();
}

class _MotorizadosActividadPageState
    extends ConsumerState<MotorizadosActividadPage> {
  List<Map<String, dynamic>> _motorizados = [];
  Map<String, Rendicion> _resumen = {};
  bool _cargando = true;
  RealtimeChannel? _canal;

  @override
  void initState() {
    super.initState();
    _cargar();
    _escucharRealtime();
  }

  @override
  void dispose() {
    _canal?.unsubscribe();
    super.dispose();
  }

  void _escucharRealtime() {
    try {
      _canal = sb
          .channel('moto-actividad')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'pedidos',
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
          .subscribe();
    } catch (_) {}
  }

  Future<void> _cargar() async {
    try {
      final motos = await motorizadosRepo.listar();
      final inicio = inicioHoy();
      final fin = DateTime.now().add(const Duration(minutes: 1));
      final resumenes = <String, Rendicion>{};
      await Future.wait(motos.map((m) async {
        final r = await rendicionRepo.calcular(
          desde: inicio,
          hasta: fin,
          motorizadoId: m['id'] as String,
        );
        resumenes[m['id'] as String] = r;
      }));
      if (!mounted) return;
      setState(() {
        _motorizados = motos;
        _resumen = resumenes;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
    }
  }

  Future<void> _configurarDias(Map<String, dynamic> moto) async {
    final id = moto['id'] as String;
    final nombre = moto['nombre'] as String? ?? '';
    final dias = await motorizadosRepo.diasTrabajo(id);
    final seleccion = <int>{...(dias ?? [1, 2, 3, 4, 5, 6, 7])};
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) => AlertDialog(
            title: Text('Días de trabajo — $nombre'),
            content: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 1; i <= 7; i++)
                  FilterChip(
                    label: Text(_nombreDia(i)),
                    selected: seleccion.contains(i),
                    onSelected: (v) => setSt(() {
                      if (v) {
                        seleccion.add(i);
                      } else {
                        seleccion.remove(i);
                      }
                    }),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Guardar'),
              ),
            ],
          ),
        );
      },
    );
    if (ok != true) return;
    await motorizadosRepo.guardarDiasTrabajo(
      id,
      seleccion.isEmpty ? null : (seleccion.toList()..sort()),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Días de trabajo de $nombre actualizados.')),
      );
    }
  }

  String _nombreDia(int d) => const ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'][d - 1];

  Future<void> _abrirDetalle(Map<String, dynamic> moto) async {
    final id = moto['id'] as String;
    final nombre = moto['nombre'] as String? ?? '';
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ActividadMotorizadoPage(
          motorizadoId: id,
          nombre: nombre,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Motorizados')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  if (_motorizados.isEmpty)
                    const EstadoVacio(
                      icono: Icons.delivery_dining_outlined,
                      titulo: 'No hay motorizados registrados',
                    )
                  else
                    for (final m in _motorizados)
                      _TarjetaMotorizado(
                        nombre: m['nombre'] as String? ?? '',
                        activo: m['activo'] as bool? ?? true,
                        resumen: _resumen[m['id'] as String] ?? const Rendicion(),
                        onTap: () => _abrirDetalle(m),
                        onConfigurarDias: () => _configurarDias(m),
                      ),
                ],
              ),
            ),
    );
  }
}

class _TarjetaMotorizado extends StatelessWidget {
  final String nombre;
  final bool activo;
  final Rendicion resumen;
  final VoidCallback onTap;
  final VoidCallback onConfigurarDias;

  const _TarjetaMotorizado({
    required this.nombre,
    required this.activo,
    required this.resumen,
    required this.onTap,
    required this.onConfigurarDias,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                    child: Text(
                      nombre.isEmpty ? '?' : nombre[0].toUpperCase(),
                      style: const TextStyle(color: AppTheme.primary),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(
                          activo ? 'Activo' : 'Inactivo',
                          style: TextStyle(
                            fontSize: 12,
                            color: activo ? AppTheme.success : Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Días de trabajo',
                    onPressed: onConfigurarDias,
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.black45),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _Mini('Pedidos', '${resumen.pedidosRealizados}'),
                  _Mini('Ventas', dinero(resumen.totalACobrar)),
                  _Mini('Efectivo', dinero(resumen.efectivo)),
                  _Mini('Yape', dinero(resumen.yape)),
                ],
              ),
              if (resumen.gastosTotal > 0 || resumen.pendiente > 0) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (resumen.gastosTotal > 0)
                      _Mini('Gastos', dinero(resumen.gastosTotal), color: AppTheme.warning),
                    if (resumen.pendiente > 0)
                      _Mini('Deudas', dinero(resumen.pendiente), color: AppTheme.danger),
                    if (resumen.balonesVaciosPendientes > 0)
                      _Mini('Balones pend.', '${resumen.balonesVaciosPendientes}',
                          color: AppTheme.warning),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  final String etiqueta;
  final String valor;
  final Color? color;

  const _Mini(this.etiqueta, this.valor, {this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta, style: const TextStyle(fontSize: 10.5, color: Colors.black45)),
          Text(
            valor,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color ?? Colors.black87,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}


/// Detalle de actividad de un motorizado: resumen, pedidos, gastos,
/// incidencias y fotos de Yape. Realtime + bus para que el admin vea lo mismo
/// que el motorizado, sin volver a entrar a la pantalla.
class _ActividadMotorizadoPage extends ConsumerStatefulWidget {
  final String motorizadoId;
  final String nombre;

  const _ActividadMotorizadoPage({
    required this.motorizadoId,
    required this.nombre,
  });

  @override
  ConsumerState<_ActividadMotorizadoPage> createState() =>
      _ActividadMotorizadoPageState();
}

class _ActividadMotorizadoPageState
    extends ConsumerState<_ActividadMotorizadoPage> {
  DateTime _dia = inicioHoy();
  Rendicion _resumen = const Rendicion();
  List<MovimientoActividad> _movimientos = [];
  bool _cargando = true;
  int _peticion = 0;
  RealtimeChannel? _canal;

  @override
  void initState() {
    super.initState();
    SyncBus.pedidos.addListener(_onBus);
    SyncBus.dinero.addListener(_onBus);
    _cargar();
    _escuchar();
  }

  @override
  void dispose() {
    SyncBus.pedidos.removeListener(_onBus);
    SyncBus.dinero.removeListener(_onBus);
    _canal?.unsubscribe();
    super.dispose();
  }

  void _onBus() {
    if (mounted) _cargar();
  }

  void _escuchar() {
    try {
      _canal = sb
          .channel('moto-detalle-${widget.motorizadoId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'pedidos',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'repartidor_id',
              value: widget.motorizadoId,
            ),
            callback: (_) {
              if (mounted) _cargar();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'gastos',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'usuario_id',
              value: widget.motorizadoId,
            ),
            callback: (_) {
              if (mounted) _cargar();
            },
          )
          .subscribe();
    } catch (_) {}
  }

  Future<void> _cargar() async {
    final miPeticion = ++_peticion;
    final hasta = _dia.add(const Duration(days: 1));
    try {
      final res = await Future.wait([
        rendicionRepo.calcular(
          desde: _dia,
          hasta: hasta,
          motorizadoId: widget.motorizadoId,
        ),
        actividadRepo.movimientosDe(
          motorizadoId: widget.motorizadoId,
          desde: _dia,
          hasta: hasta,
        ),
      ]);
      if (!mounted || miPeticion != _peticion) return;
      setState(() {
        _resumen = res[0] as Rendicion;
        _movimientos = res[1] as List<MovimientoActividad>;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted || miPeticion != _peticion) return;
      setState(() => _cargando = false);
    }
  }

  void _cambiarDia(int dias) {
    final nuevo = _dia.add(Duration(days: dias));
    if (nuevo.isAfter(inicioHoy())) return;
    setState(() {
      _dia = nuevo;
      _cargando = true;
    });
    _cargar();
  }

  String get _tituloDia {
    final hoy = inicioHoy();
    if (_dia == hoy) return 'Hoy';
    if (_dia == hoy.subtract(const Duration(days: 1))) return 'Ayer';
    return fechaCorta(_dia);
  }

  @override
  Widget build(BuildContext context) {
    final r = _resumen;
    final esHoy = _dia == inicioHoy();
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.nombre),
            Text(
              'Actividad · $_tituloDia',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Día anterior',
                  onPressed: () => _cambiarDia(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Center(
                    child: Text(_tituloDia,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                ),
                IconButton(
                  tooltip: 'Día siguiente',
                  onPressed: esHoy ? null : () => _cambiarDia(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _Mini('Pedidos', '${r.pedidosRealizados}'),
                        _Mini('Entregados', '${r.entregados}',
                            color: AppTheme.success),
                        _Mini('Ventas', dinero(r.totalACobrar)),
                        _Mini('Cobrado', dinero(r.cobrado)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _Mini('Efectivo', dinero(r.efectivo)),
                        _Mini('Yape', dinero(r.yape), color: AppTheme.info),
                        _Mini('Gastos', dinero(r.gastosTotal),
                            color: r.gastosTotal > 0 ? AppTheme.warning : null),
                        _Mini('Deudas', dinero(r.pendiente),
                            color: r.pendiente > 0 ? AppTheme.danger : null),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Movimientos', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_cargando)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                ),
              )
            else if (_movimientos.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: EstadoVacio(
                  icono: Icons.history_outlined,
                  titulo: 'Sin actividad en este día',
                ),
              )
            else
              for (final m in _movimientos) ActividadTile(movimiento: m),
          ],
        ),
      ),
    );
  }
}
