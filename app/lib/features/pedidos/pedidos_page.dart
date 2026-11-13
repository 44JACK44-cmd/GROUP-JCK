import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import 'nuevo_pedido_page.dart';
import 'pedido_detalle_page.dart';

/// Lista de pedidos de la empresa con filtro por estado.
class PedidosPage extends StatefulWidget {
  const PedidosPage({super.key});

  @override
  State<PedidosPage> createState() => _PedidosPageState();
}

class _PedidosPageState extends State<PedidosPage> {
  final _filtros = ['TODOS', 'NUEVO', 'ASIGNADO', 'EN_CAMINO', 'ENTREGADO'];
  String _filtro = 'TODOS';
  List<Map<String, dynamic>> _pedidos = [];
  bool _cargando = true;

  SupabaseClient get _sb => Supabase.instance.client;

  static const _labels = {
    'NUEVO': 'Nuevo',
    'ASIGNADO': 'Asignado',
    'EN_CAMINO': 'En camino',
    'ENTREGADO': 'Entregado',
    'CANCELADO': 'Cancelado',
  };

  static const _colores = {
    'NUEVO': AppTheme.info,
    'ASIGNADO': AppTheme.warning,
    'EN_CAMINO': AppTheme.warning,
    'ENTREGADO': AppTheme.success,
    'CANCELADO': AppTheme.danger,
  };

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      var query = _sb
          .from('pedidos')
          .select('id, numero, fecha, total, estado, forma_pago, clientes(nombre, telefono)');
      if (_filtro != 'TODOS') query = query.eq('estado', _filtro);
      final data = await query.order('fecha', ascending: false).limit(200);
      if (!mounted) return;
      setState(() {
        _pedidos = List<Map<String, dynamic>>.from(data);
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos cargar los pedidos. Revisa tu conexión.')),
      );
    }
  }

  Future<void> _nuevoPedido() async {
    final creado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const NuevoPedidoPage()),
    );
    if (creado == true) _cargar();
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
      appBar: AppBar(title: const Text('Pedidos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nuevoPedido,
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo'),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final f in _filtros)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(_labels[f] ?? f),
                      selected: _filtro == f,
                      selectedColor: AppTheme.primary.withValues(alpha: 0.15),
                      labelStyle: TextStyle(
                        color: _filtro == f ? AppTheme.primary : Colors.black87,
                        fontWeight: _filtro == f ? FontWeight.w600 : FontWeight.normal,
                      ),
                      onSelected: (_) {
                        setState(() {
                          _filtro = f;
                          _cargando = true;
                        });
                        _cargar();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : _pedidos.isEmpty
                    ? const _Vacio()
                    : RefreshIndicator(
                        onRefresh: _cargar,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                          itemCount: _pedidos.length,
                          separatorBuilder: (_, i) => const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final p = _pedidos[i];
                            final cliente = p['clientes'] as Map<String, dynamic>?;
                            final estado = p['estado'] as String? ?? '';
                            final color = _colores[estado] ?? Colors.black54;
                            final fecha = DateTime.tryParse(p['fecha'] as String? ?? '');
                            return Card(
                              child: ListTile(
                                title: Text(
                                  cliente?['nombre'] as String? ?? 'Cliente',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  [
                                    '#${p['numero']}',
                                    if (fecha != null)
                                      '${fecha.day}/${fecha.month} ${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}',
                                    if (cliente?['telefono'] != null) cliente!['telefono'],
                                  ].join('  ·  '),
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('S/ ${(p['total'] as num? ?? 0).toStringAsFixed(2)}',
                                        style: const TextStyle(fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(_labels[estado] ?? estado,
                                          style: TextStyle(
                                              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                ),
                                onTap: () => _abrirDetalle(p),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        SizedBox(height: 120),
        Icon(Icons.receipt_long_outlined, size: 56, color: Colors.black26),
        SizedBox(height: 12),
        Center(
          child: Text(
            'No hay pedidos en esta categoría.\nToca "Nuevo" para registrar el primero.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
        ),
      ],
    );
  }
}
