/// Línea de tiempo real de la operación: pedidos, pagos, gastos, fallas y
/// balones. La misma fuente para ADMIN y motorizado, sin datos de ejemplo.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/data/actividad_repo.dart';
import '../../core/data/sb.dart';
import '../../core/domain/formato.dart';
import '../../core/state/bus.dart';
import '../../core/ui/diseno.dart';
import '../../core/ui/estado_conexion.dart';
import '../../core/ui/widgets.dart';
import '../auth/auth_controller.dart';

class MovimientosPage extends ConsumerStatefulWidget {
  MovimientosPage({super.key});

  @override
  ConsumerState<MovimientosPage> createState() => _MovimientosPageState();
}

class _MovimientosPageState extends ConsumerState<MovimientosPage> {
  List<MovimientoActividad> _items = [];
  String? _filtro;
  bool _cargando = true;
  int _peticion = 0;

  static const _filtros = <String, String>{
    'TODOS': 'Todos',
    'PEDIDO': 'Pedidos',
    'PAGO': 'Pagos',
    'GASTO': 'Gastos',
    'INCIDENCIA': 'Fallas',
  };

  @override
  void initState() {
    super.initState();
    SyncBus.pedidos.addListener(_onBus);
    SyncBus.dinero.addListener(_onBus);
    SyncBus.movimientos.addListener(_onBus);
    _cargar();
  }

  @override
  void dispose() {
    SyncBus.pedidos.removeListener(_onBus);
    SyncBus.dinero.removeListener(_onBus);
    SyncBus.movimientos.removeListener(_onBus);
    super.dispose();
  }

  void _onBus() {
    if (mounted) _cargar();
  }

  Future<void> _cargar() async {
    final auth = ref.read(authProvider);
    final uid = auth.usuarioId;
    if (uid == null) return;
    final miPeticion = ++_peticion;
    final desde = inicioHoy().subtract(Duration(days: 7));
    final hasta = DateTime.now().add(Duration(minutes: 1));
    try {
      final data = auth.esAdmin
          ? await actividadRepo.movimientosDeTodos(desde: desde, hasta: hasta)
          : await actividadRepo.movimientosDe(
              motorizadoId: uid,
              desde: desde,
              hasta: hasta,
            );
      if (!mounted || miPeticion != _peticion) return;
      setState(() {
        _items = data;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted || miPeticion != _peticion) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(traducirError(e, contexto: 'No pudimos cargar movimientos').mensaje),
        ),
      );
    }
  }

  List<MovimientoActividad> get _visibles => _filtro == null || _filtro == 'TODOS'
      ? _items
      : _items.where((m) => m.tipo == _filtro).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Movimientos')),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          physics: AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            EstadoConexion(),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final e in _filtros.entries)
                    Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(e.value),
                        selected: (_filtro ?? 'TODOS') == e.key,
                        selectedColor: AppTheme.primary.withValues(alpha: 0.12),
                        onSelected: (_) => setState(() => _filtro = e.key),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(height: 12),
            if (_cargando)
              LoadingState()
            else if (_visibles.isEmpty)
             EstadoVacio(
               icono: Icons.timeline,
               titulo: 'Sin movimientos en estos días',
             )
            else
              for (final m in _visibles) MovementTile(m),
          ],
        ),
      ),
    );
  }
}