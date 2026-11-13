/// Pedidos del administrador.
///
/// Cuatro grupos claros: Pendientes · En camino · Completados · Cancelados.
/// Los pendientes van de más antiguos a más recientes: lo que más lleva
/// esperando se atiende primero.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import '../../core/data/pedidos_repo.dart';
import '../../core/data/sb.dart';
import '../../core/domain/estado_pedido.dart';
import '../../core/domain/formato.dart';
import '../../core/ui/widgets.dart';
import 'nuevo_pedido_page.dart';
import 'pedido_detalle_page.dart';

class PedidosPage extends ConsumerStatefulWidget {
  const PedidosPage({super.key});

  @override
  ConsumerState<PedidosPage> createState() => _PedidosPageState();
}

class _PedidosPageState extends ConsumerState<PedidosPage> {
  GrupoPedido _grupo = GrupoPedido.pendientes;
  List<Map<String, dynamic>> _pedidos = [];
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

  /// Actualiza la lista cuando el motorizado entrega o asigna un pedido.
  void _escucharRealtime() {
    try {
      _canal = sb
          .channel('pedidos-admin')
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
      // Si Realtime no está disponible, la lista se actualiza al tirar hacia abajo.
    }
  }

  Future<void> _cargar() async {
    try {
      final data = await pedidosRepo.listar(
        estados: _grupo.estados,
        masAntigosPrimero: _grupo == GrupoPedido.pendientes,
        limite: 200,
      );
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
      MaterialPageRoute(builder: (_) => const NuevoPedidoPage()),
    );
    if (creado == true) {
      _cargar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pedido registrado.')),
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
        title: const Text('Pedidos'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final g in GrupoPedido.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(g.label),
                        avatar: Icon(g.icono, size: 16),
                        selected: _grupo == g,
                        selectedColor: AppTheme.primary.withValues(alpha: 0.15),
                        labelStyle: TextStyle(
                          color: _grupo == g ? AppTheme.primary : Colors.black87,
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
        icon: const Icon(Icons.add),
        label: const Text('Nuevo pedido'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
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
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: _pedidos.length,
                    separatorBuilder: (_, i) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final p = _pedidos[i];
                      return TarjetaPedido(
                        pedido: p,
                        onTap: () => _abrirDetalle(p),
                        mostrarPrioridad: _grupo == GrupoPedido.pendientes,
                        trailer: _grupo == GrupoPedido.pendientes
                            ? Text(
                                antiguedad(parseFecha(p['fecha'])),
                                style: const TextStyle(
                                  color: Colors.black54,
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
