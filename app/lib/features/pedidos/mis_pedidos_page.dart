/// "Mis pedidos": los pedidos asignados al motorizado.
///
/// Para el ADMIN la misma pantalla muestra todos los pedidos en ruta y
/// permite filtrar por motorizado (el admin también puede repartir).
library;

import 'package:gas_app/core/theme/app_colors.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/data/motorizados_repo.dart';
import '../../core/data/pedidos_repo.dart';
import '../../core/data/sb.dart';
import '../../core/domain/estado_pedido.dart';
import '../../core/domain/navegacion.dart';
import '../../core/domain/resumen_pedido.dart';
import '../../core/domain/formato.dart';
import '../../core/state/bus.dart';
import '../../core/ui/widgets.dart';
import 'pedido_detalle_page.dart';
import '../../core/prefs/ajustes_prefs.dart';
import '../auth/auth_controller.dart';
import '../rutas/ruta_page.dart';
import 'flujo_entrega.dart';

class MisPedidosPage extends ConsumerStatefulWidget {
  MisPedidosPage({super.key});

  @override
  ConsumerState<MisPedidosPage> createState() => _MisPedidosPageState();
}

class _MisPedidosPageState extends ConsumerState<MisPedidosPage> {
  List<Map<String, dynamic>> _pedidos = [];
  List<Map<String, dynamic>> _disponibles = [];
  List<Map<String, dynamic>> _motorizados = [];
  String? _filtroMotorizado;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    SyncBus.pedidos.addListener(_onBus);
    SyncBus.movimientos.addListener(_onBus);
    _cargar();
    _cargarMotorizados();
  }

  @override
  void dispose() {
    SyncBus.pedidos.removeListener(_onBus);
    SyncBus.movimientos.removeListener(_onBus);
    super.dispose();
  }

  void _onBus() {
    if (mounted) _cargar();
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
      await pedidosRepo.tomarPedido(
        pedidoId: pedido['id'] as String,
        nombreRepartidor: auth.nombre,
      );
      _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tomaste el pedido.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(traducirError(e, contexto: 'No pudimos tomar el pedido').mensaje)),
      );
    }
  }

  Future<void> _navegar(Map<String, dynamic> pedido) async {
    final auth = ref.read(authProvider);
    final cliente = pedido['clientes'] as Map<String, dynamic>?;
    final lat = (cliente?['latitud'] as num?)?.toDouble();
    final lng = (cliente?['longitud'] as num?)?.toDouble();
    final direccion = cliente?['direccion'] as String? ?? '';

    // Lo ponemos en camino apenas se empieza a navegar.
    try {
      await pedidosRepo.cambiarEstado(
        pedidoId: pedido['id'] as String,
        empresaId: auth.empresaId!,
        usuarioId: auth.usuarioId!,
        destino: EstadoPedido.enCamino,
        esAdmin: auth.esAdmin,
      );
      pedido['estado'] = 'EN_CAMINO';
      if (mounted) setState(() {});
    } catch (_) {
      // Puede que ya estuviera en camino: no bloqueamos la navegación.
    }

    if (!mounted) return;
    if (lat == null || lng == null) {
      final abierto = await navegarACliente(direccion: direccion);
      if (!abierto && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('El cliente no tiene ubicación guardada. Edita su ficha para marcarla.'),
          ),
        );
      }
      return;
    }

    final dentro = await AjustesPrefs.mapaDentroDeApp();
    if (!mounted) return;
    if (!dentro) {
      await navegarACliente(latitud: lat, longitud: lng, direccion: direccion);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RutaPage(
          latitud: lat,
          longitud: lng,
          clienteNombre: cliente?['nombre'] as String?,
          direccion: direccion.isEmpty ? null : direccion,
        ),
      ),
    );
  }

  Future<void> _entregar(Map<String, dynamic> pedido) async {
    final ok = await ejecutarEntrega(context, ref, pedido);
    if (ok) _cargar();
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
        title: Text('Mis pedidos'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargar,
            icon: Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (auth.esAdmin && _motorizados.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: DropdownButtonFormField<String?>(
                initialValue: _filtroMotorizado,
                decoration: InputDecoration(
                  labelText: 'Motorizado',
                  isDense: true,
                  prefixIcon: Icon(Icons.delivery_dining_outlined),
                ),
                items: [
                  DropdownMenuItem<String?>(
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
                ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : RefreshIndicator(
                    onRefresh: _cargar,
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        // Pedidos disponibles para tomar
                        if (_disponibles.isNotEmpty) ...[
                          Text('Pedidos disponibles para tomar',
                              style: Theme.of(context).textTheme.titleMedium),
                          SizedBox(height: 8),
                          for (final p in _disponibles)
                            Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Card(
                                color: AppTheme.warning.withValues(alpha: 0.05),
                                child: ListTile(
                                  leading: Icon(Icons.delivery_dining_outlined, color: AppTheme.warning),
                                  title: Text(
                                    (p['clientes'] as Map?)?['nombre'] as String? ?? 'Cliente',
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(
                                    '${(p['clientes'] as Map?)?['direccion'] ?? ''} · ${dinero((p['total'] as num? ?? 0).toDouble())}',
                                    style: TextStyle(color: AppColors.textoSecundario, fontSize: 12),
                                  ),
                                  trailing: FilledButton(
                                    onPressed: () => _tomarPedido(p),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppTheme.warning,
                                      minimumSize: Size(0, 36),
                                    ),
                                    child: Text('Tomar', style: TextStyle(fontSize: 13)),
                                  ),
                                ),
                              ),
                            ),
                          SizedBox(height: 16),
                        ],
                        // Pedidos asignados
                        if (_pedidos.isEmpty && _disponibles.isEmpty)
                          Padding(
                            padding: EdgeInsets.only(top: 40),
                            child: EstadoVacio(
                              icono: Icons.inventory_2_outlined,
                              titulo: 'No tienes pedidos por entregar',
                              mensaje: 'Cuando te asignen uno o tomes uno disponible, aparecerá aquí.',
                            ),
                          )
                        else if (_pedidos.isNotEmpty) ...[
                          Text('Mis pedidos', style: Theme.of(context).textTheme.titleMedium),
                          SizedBox(height: 8),
                          for (final p in _pedidos)
                            Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: TarjetaPedido(
                                pedido: p,
                                onTap: () => _abrirDetalle(p),
                                trailer: Text(
                                  antiguedad(parseFecha(p['fecha'])),
                                  style: TextStyle(
                                    color: AppColors.textoSecundario,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                productoResumen: resumenProductos(p),
                                acciones: [
                                  OutlinedButton.icon(
                                    onPressed: () => _navegar(p),
                                    icon: Icon(Icons.navigation_outlined, size: 18),
                                    label: Text('NAVEGAR'),
                                    style: OutlinedButton.styleFrom(minimumSize: Size.fromHeight(44)),
                                  ),
                                  FilledButton.icon(
                                    onPressed: () => _entregar(p),
                                    icon: Icon(Icons.check_circle_outline, size: 18),
                                    label: Text('ENTREGADO'),
                                    style: FilledButton.styleFrom(
                                      minimumSize: Size.fromHeight(44),
                                      backgroundColor: AppTheme.success,
                                    ),
                                  ),
                                ],
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