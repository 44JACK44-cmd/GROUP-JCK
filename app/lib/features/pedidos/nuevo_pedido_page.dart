/// Registro rápido de pedido.
///
/// Formulario corto: cliente → producto y cantidad → precio → forma de pago.
/// El precio sale del precio habitual del cliente y se puede modificar.
/// La prioridad NO se pregunta: se calcula por antigüedad.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme.dart';
import '../../core/data/clientes_repo.dart';
import '../../core/data/pedidos_repo.dart';
import '../../core/data/sb.dart';
import '../../core/domain/formato.dart';
import '../../core/offline/outbox.dart';
import '../auth/auth_controller.dart';
import '../clientes/cliente_form_page.dart';

/// Una línea del pedido: producto + cantidad + precio.
class LineaPedidoUI {
  final String productoId;
  final String nombre;
  final int cantidad;
  final double precio;

  const LineaPedidoUI({
    required this.productoId,
    required this.nombre,
    required this.cantidad,
    required this.precio,
  });

  LineaPedidoUI copyWith({int? cantidad, double? precio}) => LineaPedidoUI(
        productoId: productoId,
        nombre: nombre,
        cantidad: cantidad ?? this.cantidad,
        precio: precio ?? this.precio,
      );
}

class NuevoPedidoPage extends ConsumerStatefulWidget {
  /// Cliente preseleccionado (viene de la ficha del cliente).
  final Map<String, dynamic>? clienteInicial;

  const NuevoPedidoPage({super.key, this.clienteInicial});

  @override
  ConsumerState<NuevoPedidoPage> createState() => _NuevoPedidoPageState();
}

class _NuevoPedidoPageState extends ConsumerState<NuevoPedidoPage> {
  final _busquedaCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();

  Map<String, dynamic>? _cliente;
  List<Map<String, dynamic>> _sugerencias = [];
  List<Map<String, dynamic>> _productos = [];
  Map<String, double> _preciosCliente = {};
  List<LineaPedidoUI> _lineas = [];
  String? _formaPago;
  bool _cargandoProductos = true;
  bool _guardando = false;
  bool _buscandoCliente = false;
  bool _asignarPorZona = false;

  /// Formas de pago que el administrador puede dejar anotadas al crear el pedido.
  static const _formasPago = {
    'EFECTIVO': '💵 Efectivo',
    'YAPE': '📱 Yape',
    'DEUDA': '🟠 Quedó debiendo',
    'OTRO': '💳 Otro',
  };

  @override
  void initState() {
    super.initState();
    _cargarProductos();
    final inicial = widget.clienteInicial;
    if (inicial != null) {
      // Cliente ya elegido: se muestran sus productos con su precio.
      _seleccionarCliente(inicial);
    }
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    _observacionesCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarProductos() async {
    try {
      final data = await sb
          .from('productos')
          .select('id, nombre, capacidad_kg, precio_base')
          .eq('activo', true)
          .order('nombre');
      if (!mounted) return;
      setState(() {
        _productos = List<Map<String, dynamic>>.from(data);
        _cargandoProductos = false;
      });
    } catch (e) {
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
      final data = await clientesRepo.buscar(q);
      if (!mounted) return;
      setState(() {
        _sugerencias = data;
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
      _busquedaCtrl.clear();
      _lineas = [];
    });
    try {
      _preciosCliente = await clientesRepo.preciosDe(cliente['id'] as String);
    } catch (_) {
      _preciosCliente = {};
    }
    if (!mounted) return;
    setState(() {
      _lineas = _productos
          .map((p) => LineaPedidoUI(
                productoId: p['id'] as String,
                nombre: _nombreProducto(p),
                cantidad: 0,
                precio: _preciosCliente[p['id'] as String] ??
                    (p['precio_base'] as num? ?? 0).toDouble(),
              ))
          .toList();
    });
  }

  String _nombreProducto(Map<String, dynamic> p) {
    final kg = p['capacidad_kg'];
    final nombre = p['nombre'] as String? ?? 'Producto';
    return kg == null ? nombre : '$nombre (${kg}kg)';
  }

  double get _total => _lineas.fold(0, (s, l) => s + l.cantidad * l.precio);

  int get _cantidadTotal => _lineas.fold(0, (s, l) => s + l.cantidad);

  Future<void> _nuevoCliente() async {
    final cambio = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ClienteFormPage()),
    );
    if (cambio == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cliente creado. Búscalo para hacer el pedido.')),
      );
    }
  }

  void _actualizarLinea(int indice, LineaPedidoUI linea) {
    setState(() => _lineas[indice] = linea);
  }

  Future<void> _guardar() async {
    final cliente = _cliente;
    if (cliente == null) {
      _error('Primero selecciona al cliente.');
      return;
    }
    final items = _lineas.where((l) => l.cantidad > 0).toList();
    if (items.isEmpty) {
      _error('Agrega al menos una cantidad de producto.');
      return;
    }
    if (items.any((l) => l.precio <= 0)) {
      _error('Revisa los precios: deben ser mayores a cero.');
      return;
    }

    setState(() => _guardando = true);
    final auth = ref.read(authProvider);
    final total = items.fold<double>(0, (s, l) => s + l.cantidad * l.precio);
    final uuid = const Uuid().v4();

    final pedido = {
      'empresa_id': auth.empresaId,
      'cliente_id': cliente['id'],
      'creado_por': auth.usuarioId,
      'forma_pago': _formaPago,
      'observaciones': _observacionesCtrl.text.trim().isEmpty
          ? null
          : _observacionesCtrl.text.trim(),
      'total': total,
      'uuid_offline': uuid,
    };
    final detalles = items
        .map((l) => {
              'empresa_id': auth.empresaId,
              'producto_id': l.productoId,
              'cantidad': l.cantidad,
              'precio_unitario': l.precio,
            })
        .toList();

    try {
      final pedidoId = await pedidosRepo.crear(
        empresaId: auth.empresaId!,
        clienteId: cliente['id'] as String,
        usuarioId: auth.usuarioId!,
        lineas: items
            .map((l) => LineaPedido(
                  productoId: l.productoId,
                  nombre: l.nombre,
                  cantidad: l.cantidad,
                  precioUnitario: l.precio,
                ))
            .toList(),
        total: total,
        formaPago: _formaPago,
        observaciones: _observacionesCtrl.text.trim(),
        uuidOffline: uuid,
      );

      // Asignación automática por zona si está activada
      if (_asignarPorZona) {
        await pedidosRepo.asignarPorZona(pedidoId: pedidoId);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pedido registrado.')),
      );
    } catch (e) {
      if (esErrorDeRed(e)) {
        // Sin conexión: se encola para enviarse sola.
        await Outbox.encolarPedido(pedido: pedido, detalles: detalles);
        if (!mounted) return;
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sin conexión: el pedido quedó guardado y se enviará solo.'),
          ),
        );
        return;
      }
      if (!mounted) return;
      setState(() => _guardando = false);
      _error(traducirError(e, contexto: 'No pudimos registrar el pedido').mensaje);
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
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: [
                      _seccionCliente(),
                      const SizedBox(height: 14),
                      if (_cliente != null) _seccionProductos(),
                      if (_cliente != null) ...[
                        const SizedBox(height: 14),
                        _seccionPago(),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _observacionesCtrl,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Observaciones (opcional)',
                            hintText: 'Ej. Dejar con el portero',
                            prefixIcon: Icon(Icons.notes_outlined),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
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
            const SizedBox(height: 10),
            if (c == null) ...[
              TextField(
                controller: _busquedaCtrl,
                textCapitalization: TextCapitalization.words,
                onChanged: _buscarClientes,
                decoration: InputDecoration(
                  hintText: 'Nombre o teléfono',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _buscandoCliente
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
              ),
              if (_sugerencias.isNotEmpty)
                ..._sugerencias.map((s) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                        child: Text(
                          (s['nombre'] as String? ?? '?')[0].toUpperCase(),
                          style: const TextStyle(color: AppTheme.primary),
                        ),
                      ),
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
                  onPressed: _nuevoCliente,
                  icon: const Icon(Icons.person_add_alt_1, size: 18),
                  label: const Text('Cliente nuevo'),
                ),
              ),
            ] else
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
        ),
      ),
    );
  }

  Widget _seccionProductos() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Producto y cantidad', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (_preciosCliente.isNotEmpty)
                  const Text('Precio del cliente',
                      style: TextStyle(color: Colors.black45, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 4),
            for (var i = 0; i < _lineas.length; i++)
              _FilaProducto(
                linea: _lineas[i],
                esPrecioCliente: _preciosCliente.containsKey(_lineas[i].productoId),
                onCambio: (nueva) => _actualizarLinea(i, nueva),
              ),
          ],
        ),
      ),
    );
  }

  Widget _seccionPago() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Forma de pago esperada', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in _formasPago.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _formaPago == e.key,
                    selectedColor: AppTheme.primary.withValues(alpha: 0.15),
                    labelStyle: TextStyle(
                      color: _formaPago == e.key ? AppTheme.primary : Colors.black87,
                      fontWeight: _formaPago == e.key ? FontWeight.w600 : FontWeight.normal,
                    ),
                    onSelected: (v) => setState(() => _formaPago = v ? e.key : null),
                  ),
              ],
            ),
            if (_formaPago == 'DEUDA')
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Quedará registrado como deuda. Podrás cobrarla luego.',
                  style: TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Asignar automáticamente por zona'),
              subtitle: const Text('El sistema elegirá el motorizado de la zona del cliente'),
              value: _asignarPorZona,
              onChanged: (v) => setState(() => _asignarPorZona = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _barraInferior() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
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
                Text(
                  '$_cantidadTotal balón(es)',
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
                Text(
                  dinero(_total),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _guardando || _cliente == null ? null : _guardar,
              icon: const Icon(Icons.check),
              label: Text(_guardando ? 'Guardando…' : 'Guardar pedido'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 50),
                padding: const EdgeInsets.symmetric(horizontal: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fila de producto: cantidad con +/- y precio editable.
class _FilaProducto extends StatelessWidget {
  final LineaPedidoUI linea;
  final bool esPrecioCliente;
  final ValueChanged<LineaPedidoUI> onCambio;

  const _FilaProducto({
    required this.linea,
    required this.esPrecioCliente,
    required this.onCambio,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(linea.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: _PrecioCampo(
                        valor: linea.precio,
                        onChanged: (v) => onCambio(linea.copyWith(precio: v)),
                      ),
                    ),
                    if (esPrecioCliente)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(Icons.bookmark, size: 14, color: AppTheme.info),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: linea.cantidad > 0
                    ? () => onCambio(linea.copyWith(cantidad: linea.cantidad - 1))
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              SizedBox(
                width: 26,
                child: Text(
                  '${linea.cantidad}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => onCambio(linea.copyWith(cantidad: linea.cantidad + 1)),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Campo de precio con su propio controlador.
class _PrecioCampo extends StatefulWidget {
  final double valor;
  final ValueChanged<double> onChanged;

  const _PrecioCampo({required this.valor, required this.onChanged});

  @override
  State<_PrecioCampo> createState() => _PrecioCampoState();
}

class _PrecioCampoState extends State<_PrecioCampo> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.valor.toStringAsFixed(2),
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      decoration: const InputDecoration(
        isDense: true,
        prefixText: 'S/ ',
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      onChanged: (t) => widget.onChanged(double.tryParse(t) ?? 0),
    );
  }
}
