/// "Mis pedidos": los pedidos asignados al motorizado.
///
/// Para el ADMIN la misma pantalla muestra todos los pedidos en ruta y
/// permite filtrar por motorizado (el admin también puede repartir).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import '../../core/data/motorizados_repo.dart';
import '../../core/data/pedidos_repo.dart';
import '../../core/data/sb.dart';
import '../../core/domain/formato.dart';
import '../../core/ui/widgets.dart';
import '../auth/auth_controller.dart';
import 'pedido_detalle_page.dart';

class MisPedidosPage extends ConsumerStatefulWidget {
  const MisPedidosPage({super.key});

  @override
  ConsumerState<MisPedidosPage> createState() => _MisPedidosPageState();
}

class _MisPedidosPageState extends ConsumerState<MisPedidosPage> {
  List<Map<String, dynamic>> _pedidos = [];
  List<Map<String, dynamic>> _disponibles = [];
  List<Map<String, dynamic>> _motorizados = [];
  String? _filtroMotorizado;
  bool _cargando = true;
  RealtimeChannel? _canal;

  @override
  void initState() {
    super.initState();
    _cargar();
    _cargarMotorizados();
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
          .channel('pedidos-moto')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'pedidos',
            callback: (_) {
              if (mounted) _cargar();
            },
          )
          .subscribe();
    } catch (_) {
      // Sin realtime: se actualiza al tirar hacia abajo.
    }
  }

  Future<void> _cargarMotorizados() async {
    if (!ref.read(authProvider).esAdmin) return;
    try {
      final data = await motorizadosRepo.listar(soloActivos: false);
      if (!mounted) return;
      setState(() => _motorizados = data);
    } catch (_) {
      // Sin filtro disponible: se muestran todos los pedidos.
    }
  }

  Future<void> _cargar() async {
    final auth = ref.read(authProvider);
    try {
      final data = await pedidosRepo.listar(
        repartidorId: auth.esAdmin ? _filtroMotorizado : auth.usuarioId,
        estados: const ['ASIGNADO', 'EN_CAMINO'],
        masAntigosPrimero: true,
        limite: 200,
      );
      // Pedidos disponibles (sin asignar) para que el motorizado los tome
      List<Map<String, dynamic>> disponibles = [];
      if (auth.esMotorizado) {
        try {
          disponibles = await pedidosRepo.listar(
            estados: const ['NUEVO'],
            masAntigosPrimero: true,
            limite: 50,
          );
          // Filtrar solo los que no tienen repartidor asignado
          disponibles = disponibles.where((p) => p['repartidor_id'] == null).toList();
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _pedidos = data;
        _disponibles = disponibles;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(traducirError(e, contexto: 'No pudimos cargar tus pedidos').mensaje)),
      );
    }
  }

  Future<void> _tomarPedido(Map<String, dynamic> pedido) async {
    final auth = ref.read(authProvider);
    try {
      await pedidosRepo.asignar(
        pedidoId: pedido['id'] as String,
        empresaId: auth.empresaId!,
        usuarioId: auth.usuarioId!,
        repartidorId: auth.usuarioId,
        nombreRepartidor: auth.nombre,
      );
      _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tomaste el pedido.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(traducirError(e, contexto: 'No pudimos tomar el pedido').mensaje)),
      );
    }
  }

  Future<void> _abrirDetalle(Map<String, dynamic> pedido) async {
    final cambio = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PedidoDetallePage(pedido: pedido)),
    );
    if (cambio == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis pedidos'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (auth.esAdmin && _motorizados.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: DropdownButtonFormField<String?>(
                initialValue: _filtroMotorizado,
                decoration: const InputDecoration(
                  labelText: 'Motorizado',
                  isDense: true,
                  prefixIcon: Icon(Icons.delivery_dining_outlined),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Todos los motorizados'),
                  ),
                  for (final m in _motorizados)
                    DropdownMenuItem<String?>(
                      value: m['id'] as String,
                      child: Text(m['nombre'] as String? ?? ''),
                    ),
                ],
                onChanged: (v) {
                  setState(() => _filtroMotorizado = v);
                  _cargar();
                },
              ),
            ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : RefreshIndicator(
                    onRefresh: _cargar,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        // Pedidos disponibles para tomar
                        if (_disponibles.isNotEmpty) ...[
                          Text('Pedidos disponibles para tomar',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          for (final p in _disponibles)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Card(
                                color: AppTheme.warning.withValues(alpha: 0.05),
                                child: ListTile(
                                  leading: const Icon(Icons.delivery_dining_outlined, color: AppTheme.warning),
                                  title: Text(
                                    (p['clientes'] as Map?)?['nombre'] as String? ?? 'Cliente',
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(
                                    '${(p['clientes'] as Map?)?['direccion'] ?? ''} · ${dinero((p['total'] as num? ?? 0).toDouble())}',
                                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                                  ),
                                  trailing: FilledButton(
                                    onPressed: () => _tomarPedido(p),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppTheme.warning,
                                      minimumSize: const Size(0, 36),
                                    ),
                                    child: const Text('Tomar', style: TextStyle(fontSize: 13)),
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                        ],
                        // Pedidos asignados
                        if (_pedidos.isEmpty && _disponibles.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 40),
                            child: EstadoVacio(
                              icono: Icons.inventory_2_outlined,
                              titulo: 'No tienes pedidos por entregar',
                              mensaje: 'Cuando te asignen uno o tomes uno disponible, aparecerá aquí.',
                            ),
                          )
                        else if (_pedidos.isNotEmpty) ...[
                          Text('Mis pedidos', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          for (final p in _pedidos)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: TarjetaPedido(
                                pedido: p,
                                onTap: () => _abrirDetalle(p),
                                trailer: Text(
                                  antiguedad(parseFecha(p['fecha'])),
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
