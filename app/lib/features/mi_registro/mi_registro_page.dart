/// "Mi registro": cuaderno digital del motorizado.
///
/// Es la bitácora real de la jornada. El resumen sale de `rendicionRepo` y la
/// actividad de `actividadRepo` (pedidos, gastos, incidencias y fotos de Yape).
/// Nada se calcula en paralelo: admin y motorizado ven los mismos datos.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import '../../core/data/actividad_repo.dart';
import '../../core/data/rendicion_repo.dart';
import '../../core/data/sb.dart';
import '../../core/domain/formato.dart';
import '../../core/state/bus.dart';
import '../../core/ui/actividad_tile.dart';
import '../../core/ui/widgets.dart';
import '../auth/auth_controller.dart';

class MiRegistroPage extends ConsumerStatefulWidget {
  const MiRegistroPage({super.key});

  @override
  ConsumerState<MiRegistroPage> createState() => _MiRegistroPageState();
}

class _MiRegistroPageState extends ConsumerState<MiRegistroPage> {
  DateTime _dia = inicioHoy();
  Rendicion _resumen = const Rendicion();
  List<MovimientoActividad> _movimientos = [];
  bool _cargando = true;
  String? _error;

  /// Descarta respuestas viejas cuando se cambia de día o llegan avisos.
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
    final uid = ref.read(authProvider).usuarioId;
    if (uid == null) return;
    try {
      _canal = sb
          .channel('mi-registro-$uid')
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
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'usuario_id',
              value: uid,
            ),
            callback: (_) {
              if (mounted) _cargar();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'fondo_vuelto',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'motorizado_id',
              value: uid,
            ),
            callback: (_) {
              if (mounted) _cargar();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'rendiciones',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'motorizado_id',
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
    final auth = ref.read(authProvider);
    final uid = auth.usuarioId;
    if (uid == null) return;
    final miPeticion = ++_peticion;
    final desde = _dia;
    final hasta = _dia.add(const Duration(days: 1));
    try {
      final res = await Future.wait([
        rendicionRepo.calcular(desde: desde, hasta: hasta, motorizadoId: uid),
        actividadRepo.movimientosDe(
          motorizadoId: uid,
          desde: desde,
          hasta: hasta,
        ),
      ]);
      if (!mounted || miPeticion != _peticion) return;
      setState(() {
        _resumen = res[0] as Rendicion;
        _movimientos = res[1] as List<MovimientoActividad>;
        _cargando = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || miPeticion != _peticion) return;
      setState(() {
        _cargando = false;
        _error = traducirError(e, contexto: 'No pudimos cargar tu registro').mensaje;
      });
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi registro'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _acciones(),
            const SizedBox(height: 16),
            _selectorDia(),
            const SizedBox(height: 12),
            if (_error != null)
              _tarjetaError()
            else ...[
              _resumenCard(),
              const SizedBox(height: 18),
              Text('Actividad', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (_cargando)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                )
              else if (_movimientos.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'Sin movimientos en este día.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                )
              else
                for (final m in _movimientos) ...[
                  ActividadTile(movimiento: m),
                  const SizedBox(height: 0),
                ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _acciones() {
    Widget boton(String label, IconData icono, Color color, String ruta) {
      return Expanded(
        child: FilledButton.icon(
          onPressed: () => context.push(ruta),
          icon: Icon(icono),
          label: Text(label),
          style: FilledButton.styleFrom(
            backgroundColor: color,
            minimumSize: const Size.fromHeight(52),
          ),
        ),
      );
    }

    return Row(
      children: [
        boton('Pedido', Icons.add_circle_outline, AppTheme.primary, '/mi-registro/pedido'),
        const SizedBox(width: 8),
        boton('Gasto', Icons.payments_outlined, AppTheme.warning, '/mi-registro/gasto'),
        const SizedBox(width: 8),
        boton('Falla', Icons.build_outlined, AppTheme.danger, '/mi-registro/incidencia'),
      ],
    );
  }

  Widget _selectorDia() {
    final esHoy = _dia == inicioHoy();
    return Row(
      children: [
        IconButton(
          tooltip: 'Día anterior',
          onPressed: () => _cambiarDia(-1),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Center(
            child: Text(_tituloDia, style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
        IconButton(
          tooltip: 'Día siguiente',
          onPressed: esHoy ? null : () => _cambiarDia(1),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  Widget _tarjetaError() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.error_outline, color: AppTheme.danger, size: 36),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            FilledButton(onPressed: _cargar, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }

  Widget _resumenCard() {
    final r = _resumen;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilaValor('Pedidos', '${r.pedidosRealizados}'),
            FilaValor('Entregados', '${r.entregados}', color: AppTheme.success),
            FilaValor('No entregados', '${r.noEntregados}',
                color: r.noEntregados > 0 ? AppTheme.danger : null),
            const Divider(height: 22),
            FilaValor('Ventas', dinero(r.totalACobrar), destacado: true),
            FilaValor('Cobrado', dinero(r.cobrado)),
            FilaValor('Efectivo', dinero(r.efectivo)),
            FilaValor('Yape', dinero(r.yape), color: AppTheme.info),
            if (r.pendiente > 0)
              FilaValor('Deuda', dinero(r.pendiente), color: AppTheme.danger),
            const Divider(height: 22),
            FilaValor('Balones entregados', '${r.balonesEntregados}'),
            FilaValor('Balones devueltos', '${r.balonesDevueltos}',
                color: AppTheme.success),
            const Divider(height: 22),
            FilaValor('Fondo de vuelto', dinero(r.fondoInicial), color: AppTheme.info),
            FilaValor('Gastos en efectivo', dinero(r.gastosEfectivo),
                color: r.gastosEfectivo > 0 ? AppTheme.danger : null),
            FilaValor('Efectivo esperado', dinero(r.efectivoEsperado),
                destacado: true),
            if (r.hayDeclaracion) ...[
              FilaValor('Efectivo declarado', dinero(r.efectivoDeclarado)),
              FilaValor(
                'Diferencia',
                '${r.diferencia >= 0 ? '+' : '-'}${dinero(r.diferencia.abs())}',
                color: r.tieneDiferencia ? AppTheme.danger : AppTheme.success,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
