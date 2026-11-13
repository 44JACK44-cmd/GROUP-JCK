/// Registro rápido de pedido por el motorizado.
///
/// Para cuando el receptor se olvidó de anotar el pedido en la app.
/// Queda marcado como "registrado por motorizado" para que el receptor lo revise.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme.dart';
import '../../core/data/clientes_repo.dart';
import '../../core/data/pedidos_repo.dart';
import '../../core/data/sb.dart';
import '../../core/offline/outbox.dart';
import '../auth/auth_controller.dart';
import '../clientes/mapa_selector_page.dart';

class RegistroPedidoPage extends ConsumerStatefulWidget {
  const RegistroPedidoPage({super.key});

  @override
  ConsumerState<RegistroPedidoPage> createState() => _RegistroPedidoPageState();
}

class _RegistroPedidoPageState extends ConsumerState<RegistroPedidoPage> {
  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _referenciaCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();
  final _precioCtrl = TextEditingController(text: '45.00');
  final _cantidadCtrl = TextEditingController(text: '1');

  String _producto = 'Balón 10 kg';
  String _formaPago = 'EFECTIVO';
  double? _latitud;
  double? _longitud;
  bool _guardando = false;
  Map<String, String> _productoIds = {};
  List<Map<String, dynamic>> _productosDb = [];

  static const _formasPago = {
    'EFECTIVO': '💵 Efectivo',
    'YAPE': '📱 Yape',
    'DEUDA': '🟠 Quedó debiendo',
  };

  @override
  void initState() {
    super.initState();
    _cargarProductos();
  }

  Future<void> _cargarProductos() async {
    try {
      final data = await sb
          .from('productos')
          .select('id, nombre, capacidad_kg, precio_base')
          .eq('activo', true)
          .order('nombre');
      if (!mounted) return;
      final mapa = <String, String>{};
      final lista = List<Map<String, dynamic>>.from(data);
      for (final p in lista) {
        final kg = p['capacidad_kg'];
        final nombre = p['nombre'] as String? ?? 'Producto';
        final label = kg == null ? nombre : '$nombre (${kg}kg)';
        mapa[label] = p['id'] as String;
      }
      setState(() {
        _productosDb = lista;
        _productoIds = mapa;
        if (mapa.isNotEmpty) _producto = mapa.keys.first;
      });
    } catch (_) {
      // Usar valores por defecto
    }
  }

  @override
  void dispose() {
    for (final c in [_nombreCtrl, _telefonoCtrl, _direccionCtrl, _referenciaCtrl,
      _observacionesCtrl, _precioCtrl, _cantidadCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _elegirEnMapa() async {
    final resultado = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => MapaSelectorPage(
          latitud: _latitud,
          longitud: _longitud,
          titulo: 'Ubicación del cliente',
        ),
      ),
    );
    if (resultado == null) return;
    setState(() {
      _latitud = resultado['latitud'] as double?;
      _longitud = resultado['longitud'] as double?;
    });
  }

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      _error('Escribe el nombre del cliente.');
      return;
    }
    final cantidad = int.tryParse(_cantidadCtrl.text) ?? 0;
    if (cantidad <= 0) {
      _error('La cantidad debe ser mayor a cero.');
      return;
    }
    final precio = double.tryParse(_precioCtrl.text) ?? 0;
    if (precio <= 0) {
      _error('El precio debe ser mayor a cero.');
      return;
    }

    setState(() => _guardando = true);
    final auth = ref.read(authProvider);
    final total = cantidad * precio;
    final uuid = const Uuid().v4();

    try {
      // Buscar o crear cliente
      String clienteId;
      final clientes = await clientesRepo.buscar(nombre);
      if (clientes.isNotEmpty) {
        clienteId = clientes.first['id'] as String;
      } else {
        clienteId = await clientesRepo.crear(
          empresaId: auth.empresaId!,
          nombre: nombre,
          telefono: _telefonoCtrl.text.trim().isEmpty ? null : _telefonoCtrl.text.trim(),
          direccion: _direccionCtrl.text.trim().isEmpty ? null : _direccionCtrl.text.trim(),
          referencia: _referenciaCtrl.text.trim().isEmpty ? null : _referenciaCtrl.text.trim(),
          latitud: _latitud,
          longitud: _longitud,
          observaciones: 'Registrado por motorizado',
        );
      }

      // Crear pedido con origen MOTORIZADO
      final productoId = _productoIds[_producto] ?? '';
      if (productoId.isEmpty) {
        _error('No se encontró el producto seleccionado.');
        setState(() => _guardando = false);
        return;
      }

      await pedidosRepo.crear(
        empresaId: auth.empresaId!,
        clienteId: clienteId,
        usuarioId: auth.usuarioId!,
        lineas: [LineaPedido(
          productoId: productoId,
          nombre: _producto,
          cantidad: cantidad,
          precioUnitario: precio,
        )],
        total: total,
        formaPago: _formaPago,
        observaciones: _observacionesCtrl.text.trim().isEmpty
            ? 'Registrado por motorizado'
            : _observacionesCtrl.text.trim(),
        uuidOffline: uuid,
        origen: 'MOTORIZADO',
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pedido registrado. El receptor lo revisará.')),
      );
    } catch (e) {
      if (esErrorDeRed(e)) {
        await Outbox.encolarPedido(
          pedido: {
            'empresa_id': auth.empresaId,
            'cliente_id': null,
            'creado_por': auth.usuarioId,
            'forma_pago': _formaPago,
            'observaciones': 'Registrado por motorizado: $nombre',
            'total': total,
            'uuid_offline': uuid,
            'origen': 'MOTORIZADO',
          },
          detalles: [
            {
              'empresa_id': auth.empresaId,
              'producto_id': null,
              'cantidad': cantidad,
              'precio_unitario': precio,
            },
          ],
        );
        if (!mounted) return;
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sin conexión: el pedido quedó guardado.')),
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
    final tieneUbicacion = _latitud != null && _longitud != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar pedido')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Cliente
          TextFormField(
            controller: _nombreCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nombre del cliente *',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _telefonoCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Teléfono',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _direccionCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Dirección',
              prefixIcon: Icon(Icons.place_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _referenciaCtrl,
            decoration: const InputDecoration(
              labelText: 'Referencia',
              prefixIcon: Icon(Icons.signpost_outlined),
            ),
          ),
          const SizedBox(height: 12),
          // Ubicación en mapa
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        tieneUbicacion ? Icons.location_on : Icons.location_off_outlined,
                        color: tieneUbicacion ? AppTheme.success : Colors.black45,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tieneUbicacion ? 'Ubicación marcada' : 'Sin ubicación',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  if (tieneUbicacion)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 28),
                      child: Text(
                        '${_latitud!.toStringAsFixed(6)}, ${_longitud!.toStringAsFixed(6)}',
                        style: const TextStyle(color: Colors.black54, fontSize: 13),
                      ),
                    ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _elegirEnMapa,
                      icon: const Icon(Icons.map_outlined),
                      label: Text(tieneUbicacion ? 'Cambiar en el mapa' : 'Marcar en el mapa'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Producto y precio
          DropdownButtonFormField<String>(
            initialValue: _productoIds.isNotEmpty ? _producto : null,
            decoration: const InputDecoration(
              labelText: 'Producto',
              prefixIcon: Icon(Icons.local_fire_department_outlined),
            ),
            items: _productoIds.keys.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
            onChanged: (v) {
              setState(() {
                _producto = v ?? _producto;
                // Buscar precio base del producto seleccionado
                for (final p in _productosDb) {
                  final kg = p['capacidad_kg'];
                  final nombre = p['nombre'] as String? ?? 'Producto';
                  final label = kg == null ? nombre : '$nombre (${kg}kg)';
                  if (label == _producto) {
                    _precioCtrl.text = (p['precio_base'] as num? ?? 45.00).toStringAsFixed(2);
                  }
                }
              });
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _cantidadCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Cantidad',
                    prefixIcon: Icon(Icons.numbers),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _precioCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Precio',
                    prefixText: 'S/ ',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Forma de pago
          Text('Forma de pago', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
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
                  onSelected: (v) => setState(() => _formaPago = v ? e.key : 'EFECTIVO'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _observacionesCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Observaciones (opcional)',
              prefixIcon: Icon(Icons.notes_outlined),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _guardando ? null : _guardar,
            icon: const Icon(Icons.check),
            label: Text(_guardando ? 'Guardando…' : 'Registrar pedido'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ],
      ),
    );
  }
}
