import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme.dart';
import '../../core/offline/outbox.dart';
import '../auth/auth_controller.dart';
import '../clientes/cliente_form_page.dart';

class _LineaPedido {
  final String productoId;
  final String nombre;
  int cantidad = 0;
  double precio;
  _LineaPedido({required this.productoId, required this.nombre, required this.precio});
}

/// Registro rápido de pedido: buscar cliente → tocar productos → guardar.
/// Si no hay internet, el pedido queda en cola y se sincroniza solo.
class NuevoPedidoPage extends ConsumerStatefulWidget {
  const NuevoPedidoPage({super.key});

  @override
  ConsumerState<NuevoPedidoPage> createState() => _NuevoPedidoPageState();
}

class _NuevoPedidoPageState extends ConsumerState<NuevoPedidoPage> {
  final _busquedaClienteCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();

  SupabaseClient get _sb => Supabase.instance.client;

  Map<String, dynamic>? _cliente;
  List<Map<String, dynamic>> _sugerencias = [];
  List<Map<String, dynamic>> _productos = [];
  List<_LineaPedido> _lineas = [];
  String? _formaPago;
  bool _cargandoProductos = true;
  bool _guardando = false;
  bool _buscandoCliente = false;

  static const _formasPago = {
    'EFECTIVO': 'Efectivo',
    'YAPE': 'Yape',
    'PLIN': 'Plin',
    'TRANSFERENCIA': 'Transferencia',
    'OTRO': 'Otro',
  };

  @override
  void initState() {
    super.initState();
    _cargarProductos();
  }

  @override
  void dispose() {
    _busquedaClienteCtrl.dispose();
    _observacionesCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarProductos() async {
    try {
      final data = await _sb
          .from('productos')
          .select('id, nombre, capacidad_kg, precio_base')
          .eq('activo', true)
          .order('nombre');
      if (!mounted) return;
      setState(() {
        _productos = List<Map<String, dynamic>>.from(data);
        _cargandoProductos = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargandoProductos = false);
      _error('No pudimos cargar los productos. Revisa tu conexión.');
    }
  }

  Future<void> _buscarClientes(String texto) async {
    final q = texto.trim();
    if (q.length < 2) {
      setState(() => _sugerencias = []);
      return;
    }
    setState(() => _buscandoCliente = true);
    try {
      final data = await _sb
          .from('clientes')
          .select('id, nombre, telefono, direccion')
          .eq('activo', true)
          .or('nombre.ilike.%$q%,telefono.ilike.%$q%')
          .order('nombre')
          .limit(8);
      if (!mounted) return;
      setState(() {
        _sugerencias = List<Map<String, dynamic>>.from(data);
        _buscandoCliente = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _buscandoCliente = false);
    }
  }

  Future<void> _seleccionarCliente(Map<String, dynamic> cliente) async {
    setState(() {
      _cliente = cliente;
      _sugerencias = [];
      _busquedaClienteCtrl.clear();
      _lineas = [];
    });
    await _cargarPreciosCliente(cliente['id'] as String);
  }

  /// Aplica precios especiales del cliente sobre el precio base.
  Future<void> _cargarPreciosCliente(String clienteId) async {
    try {
      final data = await _sb
          .from('precios_cliente')
          .select('producto_id, precio')
          .eq('cliente_id', clienteId);
      final especiales = {
        for (final p in data) p['producto_id'] as String: (p['precio'] as num).toDouble(),
      };
      if (!mounted) return;
      setState(() {
        _lineas = _productos.map((p) {
          final id = p['id'] as String;
          return _LineaPedido(
            productoId: id,
            nombre: _nombreProducto(p),
            precio: especiales[id] ?? (p['precio_base'] as num).toDouble(),
          );
        }).toList();
      });
    } catch (_) {
      // Si falla la carga de precios especiales, usar precio base.
      if (!mounted) return;
      setState(() {
        _lineas = _productos.map((p) => _LineaPedido(
              productoId: p['id'] as String,
              nombre: _nombreProducto(p),
              precio: (p['precio_base'] as num).toDouble(),
            )).toList();
      });
    }
  }

  String _nombreProducto(Map<String, dynamic> p) {
    final kg = p['capacidad_kg'];
    return kg == null ? p['nombre'] as String : '${p['nombre']} (${kg}kg)';
  }

  double get _total => _lineas.fold(0, (s, l) => s + l.cantidad * l.precio);

  Future<void> _nuevoClienteRapido() async {
    final cambio = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ClienteFormPage()),
    );
    if (cambio == true && _busquedaClienteCtrl.text.trim().isNotEmpty) {
      await _buscarClientes(_busquedaClienteCtrl.text);
    }
  }

  Future<void> _guardar() async {
    final cliente = _cliente;
    if (cliente == null) {
      _error('Primero selecciona al cliente.');
      return;
    }
    final items = _lineas.where((l) => l.cantidad > 0).toList();
    if (items.isEmpty) {
      _error('Agrega al menos un producto al pedido.');
      return;
    }
    if (items.any((l) => l.precio <= 0)) {
      _error('Revisa los precios: deben ser mayores a cero.');
      return;
    }

    setState(() => _guardando = true);
    final auth = ref.read(authProvider);
    final total = items.fold<double>(0, (s, l) => s + l.cantidad * l.precio);

    final pedido = {
      'empresa_id': auth.empresaId,
      'cliente_id': cliente['id'],
      'creado_por': auth.usuarioId,
      'forma_pago': _formaPago,
      'observaciones': _observacionesCtrl.text.trim().isEmpty
          ? null
          : _observacionesCtrl.text.trim(),
      'total': total,
      'uuid_offline': const Uuid().v4(),
    };
    final detalles = items
        .map((l) => {
              'producto_id': l.productoId,
              'cantidad': l.cantidad,
              'precio_unitario': l.precio,
            })
        .toList();

    try {
      final insertado = await _sb.from('pedidos').insert(pedido).select('id').single();
      final pedidoId = insertado['id'] as String;
      for (final d in detalles) {
        await _sb.from('detalle_pedido').insert({...d, 'pedido_id': pedidoId});
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      // Sin internet: encolar para sincronizar después.
      await Outbox.encolarPedido(pedido: pedido, detalles: detalles);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sin conexión: pedido guardado y se enviará automáticamente.')),
      );
    }
  }

  void _error(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo pedido')),
      body: _cargandoProductos
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _seccionCliente(),
                      const SizedBox(height: 16),
                      _seccionProductos(),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _observacionesCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Observaciones',
                          hintText: 'Ej. Dejar con el portero',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _formaPago,
                        decoration: const InputDecoration(labelText: 'Forma de pago (opcional)'),
                        items: [
                          for (final e in _formasPago.entries)
                            DropdownMenuItem(value: e.key, child: Text(e.value)),
                        ],
                        onChanged: (v) => setState(() => _formaPago = v),
                      ),
                      const SizedBox(height: 90),
                    ],
                  ),
                ),
                _barraInferior(),
              ],
            ),
    );
  }

  Widget _seccionCliente() {
    final c = _cliente;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cliente', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (c == null) ...[
              TextField(
                controller: _busquedaClienteCtrl,
                onChanged: _buscarClientes,
                decoration: InputDecoration(
                  hintText: 'Nombre o teléfono',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _buscandoCliente
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : null,
                ),
              ),
              if (_sugerencias.isNotEmpty)
                ..._sugerencias.map((s) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(s['nombre'] as String? ?? ''),
                      subtitle: Text([
                        if (s['telefono'] != null) s['telefono'],
                        if (s['direccion'] != null) s['direccion'],
                      ].whereType<String>().join(' · ')),
                      onTap: () => _seleccionarCliente(s),
                    )),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _nuevoClienteRapido,
                  icon: const Icon(Icons.person_add_alt_1, size: 18),
                  label: const Text('Cliente nuevo'),
                ),
              ),
            ] else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                  child: Text(
                    (c['nombre'] as String? ?? '?')[0].toUpperCase(),
                    style: const TextStyle(color: AppTheme.primary),
                  ),
                ),
                title: Text(c['nombre'] as String? ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text([
                  if (c['telefono'] != null) c['telefono'],
                  if (c['direccion'] != null) c['direccion'],
                ].whereType<String>().join(' · ')),
                trailing: TextButton(
                  onPressed: () => setState(() => _cliente = null),
                  child: const Text('Cambiar'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _seccionProductos() {
    if (_lineas.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(
            child: Text('Selecciona primero al cliente.',
                style: TextStyle(color: Colors.black54)),
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Productos', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final l in _lineas)
              _FilaProducto(linea: l, onCambio: () => setState(() {})),
          ],
        ),
      ),
    );
  }

  Widget _barraInferior() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE6E8E5))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total', style: TextStyle(color: Colors.black54, fontSize: 13)),
                Text('S/ ${_total.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.primary)),
              ],
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: const Icon(Icons.check),
              label: Text(_guardando ? 'Guardando…' : 'Guardar pedido'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 50),
                padding: const EdgeInsets.symmetric(horizontal: 24),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilaProducto extends StatefulWidget {
  final _LineaPedido linea;
  final VoidCallback onCambio;
  const _FilaProducto({required this.linea, required this.onCambio});

  @override
  State<_FilaProducto> createState() => _FilaProductoState();
}

class _FilaProductoState extends State<_FilaProducto> {
  late final TextEditingController _precioCtrl;
  late int _cantidad;

  @override
  void initState() {
    super.initState();
    _cantidad = widget.linea.cantidad;
    _precioCtrl = TextEditingController(text: widget.linea.precio.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _precioCtrl.dispose();
    super.dispose();
  }

  void _actualizarPrecio() {
    widget.linea.precio = double.tryParse(_precioCtrl.text) ?? 0;
    widget.onCambio();
  }

  void _cambiarCantidad(int delta) {
    setState(() => _cantidad = (_cantidad + delta).clamp(0, 999));
    widget.linea.cantidad = _cantidad;
    widget.onCambio();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.linea;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _precioCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixText: 'S/ ',
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    onChanged: (_) => _actualizarPrecio(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: _cantidad > 0 ? () => _cambiarCantidad(-1) : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              SizedBox(
                width: 28,
                child: Text('$_cantidad', textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => _cambiarCantidad(1),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
