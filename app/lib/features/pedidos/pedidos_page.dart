/// Pedidos del administrador.
///
/// Cuatro grupos claros: Pendientes · En camino · Completados · Cancelados.
/// Los pendientes van de más antiguos a más recientes: lo que más lleva
/// esperando se atiende primero.
library;

import 'package:gas_app/core/theme/app_colors.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/data/motorizados_repo.dart';
import '../../core/data/pedidos_repo.dart';
import '../../core/data/sb.dart';
import '../../core/state/bus.dart';
import '../../core/domain/resumen_pedido.dart';
import '../../core/domain/estado_pedido.dart';
import '../../core/domain/formato.dart';
import '../../core/ui/widgets.dart';
import '../auth/auth_controller.dart';
import 'nuevo_pedido_page.dart';
import 'pedido_detalle_page.dart';

class PedidosPage extends ConsumerStatefulWidget {
  PedidosPage({super.key});

  @override
  ConsumerState<PedidosPage> createState() => _PedidosPageState();
}

class _PedidosPageState extends ConsumerState<PedidosPage> {
  GrupoPedido _grupo = GrupoPedido.pendientes;
  List<Map<String, dynamic>> _pedidos = [];
  bool _cargando = true;
  Map<String, String> _motorizadoNombre = {};

  @override
  void initState() {
    super.initState();
    SyncBus.pedidos.addListener(_onBus);
    SyncBus.movimientos.addListener(_onBus);
    _cargar();
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

  Future<void> _cargar() async {
    try {
      final esHoy = _grupo == GrupoPedido.hoy;
      final data = await pedidosRepo.listar(
        estados: esHoy ? const [] : _grupo.estados,
        desde: esHoy ? inicioHoy() : null,
        hasta: esHoy ? DateTime.now().add(Duration(minutes: 1)) : null,
        masAntigosPrimero: _grupo == GrupoPedido.pendientes,
        limite: 200,
      );
      // Nombres de motorizados para las tarjetas.
      final auth = ref.read(authProvider);
      if (auth.esAdmin && _motorizadoNombre.isEmpty) {
        try {
          final motos = await motorizadosRepo.listar();
          _motorizadoNombre = {
            for (final m in motos) m['id'] as String: m['nombre'] as String? ?? '',
          };
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _pedidos = data;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(traducirError(e, contexto: 'No pudimos cargar los pedidos').mensaje)),
      );
    }
  }

  Future<void> _nuevoPedido() async {
    final creado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => NuevoPedidoPage()),
    );
    if (creado == true) {
      _cargar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pedido registrado.')),
        );
      }
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
    return Scaffold(
      appBar: AppBar(
        title: Text(_grupo == GrupoPedido.hoy ? 'Pedidos de hoy' : 'Pedidos'),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(56),
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final g in GrupoPedido.values)
                    Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(g.label),
                        avatar: Icon(g.icono, size: 16),
                        selected: _grupo == g,
                        selectedColor: AppTheme.primary.withValues(alpha: 0.15),
                        labelStyle: TextStyle(
                          color: _grupo == g ? AppTheme.primary : AppColors.textoPrincipal,
                          fontWeight: _grupo == g ? FontWeight.w600 : FontWeight.normal,
                        ),
                        onSelected: (_) {
                          setState(() {
                            _grupo = g;
                            _cargando = true;
                          });
                          _cargar();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nuevoPedido,
        backgroundColor: AppTheme.primary,
        icon: Icon(Icons.add),
        label: Text('Nuevo pedido'),
      ),
      body: _cargando
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _pedidos.isEmpty
              ? EstadoVacio(
                  icono: Icons.receipt_long_outlined,
                  titulo: 'No hay pedidos en "${_grupo.label}"',
                  mensaje: _grupo == GrupoPedido.pendientes
                      ? 'Toca "Nuevo pedido" para registrar el primero.'
                      : null,
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.separated(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: _pedidos.length,
                    separatorBuilder: (_, i) => SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final p = _pedidos[i];
                      return TarjetaPedido(
                        pedido: p,
                        onTap: () => _abrirDetalle(p),
                        mostrarPrioridad: _grupo == GrupoPedido.pendientes,
                        productoResumen: resumenProductos(p),
                        motorizadoNombre: _motorizadoNombre[p['repartidor_id'] as String?],
                        trailer: _grupo == GrupoPedido.hoy
                            ? Text(
                                horaCorta(parseFecha(p['fecha'])),
                                style: TextStyle(
                                  color: AppColors.textoSecundario,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            : _grupo == GrupoPedido.pendientes
                                ? Text(
                                    antiguedad(parseFecha(p['fecha'])),
                                    style: TextStyle(
                                      color: AppColors.textoSecundario,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )
                                : null,
                      );
                    },
                  ),
                ),
    );
  }
}