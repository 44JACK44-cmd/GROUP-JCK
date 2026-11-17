/// Nuevo pedido: una sola pantalla, en el orden en que se atiende una llamada.
///
///   1. ¿Quién llama?            → nombre + teléfono
///   2. ¿Dónde llevar?           → mini mapa (dirección + referencia + pin)
///   3. ¿Qué lleva?              → producto y cantidad
///   4. ¿Cuánto debe cobrar?     → precio LIBRE (el catálogo solo sugiere)
///   5. ¿Cómo paga?              → efectivo / Yape / deuda
///   6. ¿Quién lo lleva?         → motorizado
///   7. Nota (opcional)
///   8. CONFIRMAR PEDIDO
///
/// Nada de este flujo depende del precio base: si el negocio cobra S/ 55 por un
/// balón de S/ 50, se escribe 55 y se guarda 55.
library;

import 'package:gas_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme.dart';
import '../../core/data/clientes_repo.dart';
import '../../core/data/motorizados_repo.dart';
import '../../core/data/pedidos_repo.dart';
import '../../core/data/productos_repo.dart';
import '../../core/data/sb.dart';
import '../../core/domain/formato.dart';
import '../../core/domain/precio.dart';
import '../../core/offline/outbox.dart';
import '../auth/auth_controller.dart';
import '../clientes/mapa_selector_page.dart';

/// Una línea del pedido mientras se escribe.
class LineaRapida {
  final String productoId;
  final String nombre;
  final int cantidad;
  final double precio;

  LineaRapida({
    required this.productoId,
    required this.nombre,
    this.cantidad = 1,
    required this.precio,
  });

  double get subtotal => cantidad * precio;

  LineaRapida copyWith({int? cantidad, double? precio}) => LineaRapida(
        productoId: productoId,
        nombre: nombre,
        cantidad: cantidad ?? this.cantidad,
        precio: precio ?? this.precio,
      );
}

class NuevoPedidoPage extends ConsumerStatefulWidget {
  /// Cliente ya elegido (viene de la ficha del cliente).
  final Map<String, dynamic>? clienteInicial;

  NuevoPedidoPage({super.key, this.clienteInicial});

  @override
  ConsumerState<NuevoPedidoPage> createState() => _NuevoPedidoPageState();
}

class _NuevoPedidoPageState extends ConsumerState<NuevoPedidoPage> {
  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _notaCtrl = TextEditingController();

  Map<String, dynamic>? _cliente;
  List<Map<String, dynamic>> _sugerencias = [];
  bool _buscandoCliente = false;

  List<Map<String, dynamic>> _productos = [];
  bool _cargandoProductos = true;
  String? _errorProductos;
  Map<String, double> _preciosCliente = {};

  List<LineaRapida> _lineas = [];
  String _formaPago = 'EFECTIVO';

  List<Map<String, dynamic>> _motorizados = [];
  Map<String, int> _enRuta = {};
  String? _motorizadoId;

  String _direccion = '';
  String _referencia = '';
  double? _latitud;
  double? _longitud;
  bool _ubicacionCambiada = false;

  bool _guardando = false;

  static const _formasPago = [
    ('EFECTIVO', Icons.payments_outlined, 'Efectivo'),
    ('YAPE', Icons.account_balance_wallet_outlined, 'Yape'),
    ('DEUDA', Icons.assignment_outlined, 'Queda debiendo'),
  ];

  @override
  void initState() {
    super.initState();
    _cargarProductos();
    _cargarMotorizados();
    final inicial = widget.clienteInicial;
    if (inicial != null) _usarCliente(inicial);
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    _notaCtrl.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- carga

  Future<void> _cargarProductos() async {
    setState(() {
      _cargandoProductos = true;
      _errorProductos = null;
    });
    try {
      final data = await ProductosRepo().vendibles();
      if (!mounted) return;
      setState(() {
        _productos = data;
        _cargandoProductos = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargandoProductos = false;
        _errorProductos = 'No pudimos cargar los productos.';
      });
    }
  }

  Future<void> _cargarMotorizados() async {
    final auth = ref.read(authProvider);
    if (!auth.esAdmin) return;
    try {
      final lista = await motorizadosRepo.listar();
      // Cuántos pedidos lleva cada uno: sirve para ver quién está libre.
      var enRuta = <String, int>{};
      try {
        final activos = await pedidosRepo.listar(
          estados: const ['ASIGNADO', 'EN_CAMINO'],
          limite: 200,
        );
        for (final p in activos) {
          final id = p['repartidor_id'] as String?;
          if (id != null) enRuta[id] = (enRuta[id] ?? 0) + 1;
        }
      } catch (_) {
        enRuta = {};
      }
      if (!mounted) return;
      setState(() {
        _motorizados = lista;
        _enRuta = enRuta;
      });
    } catch (_) {
      // Sin lista de motorizados el pedido se puede guardar igual ("sin asignar").
    }
  }

  Future<void> _buscarCliente(String texto) async {
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

  void _usarCliente(Map<String, dynamic> cliente) {
    _nombreCtrl.text = cliente['nombre'] as String? ?? '';
    _telefonoCtrl.text = cliente['telefono'] as String? ?? '';
    _direccion = cliente['direccion'] as String? ?? '';
    _referencia = cliente['referencia'] as String? ?? '';
    _latitud = (cliente['latitud'] as num?)?.toDouble();
    _longitud = (cliente['longitud'] as num?)?.toDouble();
    _sugerencias = [];
    _cargarPreciosDe(cliente);
    setState(() => _cliente = cliente);
  }

  Future<void> _cargarPreciosDe(Map<String, dynamic> cliente) async {
    try {
      final precios = await clientesRepo.preciosDe(cliente['id'] as String);
      if (!mounted) return;
      setState(() {
        _preciosCliente = precios;
        // Si ya había un producto elegido, se actualiza al precio del cliente.
        _lineas = _lineas
            .map((l) => _preciosCliente.containsKey(l.productoId)
                ? l.copyWith(precio: _preciosCliente[l.productoId]!)
                : l)
            .toList();
      });
    } catch (_) {
      // Sin precios especiales: se usa el del catálogo como sugerencia.
    }
  }

  // ------------------------------------------------------------- datos

  double get _total => _lineas.fold(0, (s, l) => s + l.subtotal);
  int get _cantidad => _lineas.fold(0, (s, l) => s + l.cantidad);

  String _nombreProducto(Map<String, dynamic> p) {
    final kg = p['capacidad_kg'];
    final nombre = p['nombre'] as String? ?? 'Producto';
    return kg == null ? nombre : '$nombre (${kg}kg)';
  }

  double? _sugeridoPara(Map<String, dynamic> p) {
    final id = p['id'] as String;
    return PrecioLibre.sugerido(
      precioCliente: _preciosCliente[id],
      precioBase: (p['precio_base'] as num?)?.toDouble(),
    );
  }

  void _alternarProducto(Map<String, dynamic> p) {
    final id = p['id'] as String;
    final existe = _lineas.indexWhere((l) => l.productoId == id);
    setState(() {
      if (existe >= 0) {
        _lineas.removeAt(existe);
      } else {
        _lineas.add(LineaRapida(
          productoId: id,
          nombre: _nombreProducto(p),
          precio: _sugeridoPara(p) ?? 0,
        ));
      }
    });
  }

  void _actualizar(int indice, LineaRapida linea) {
    setState(() => _lineas[indice] = linea);
  }

  Future<void> _marcarUbicacion() async {
    final elegida = await abrirMiniMapa(
      context,
      latitud: _latitud,
      longitud: _longitud,
      direccion: _direccion,
      referencia: _referencia,
      titulo: _cliente == null ? 'Ubicación del pedido' : 'Ubicación de ${_nombreCtrl.text.trim()}',
    );
    if (elegida == null) return;
    setState(() {
      _latitud = elegida.latitud;
      _longitud = elegida.longitud;
      if ((elegida.direccion ?? '').isNotEmpty) _direccion = elegida.direccion!;
      if ((elegida.referencia ?? '').isNotEmpty) _referencia = elegida.referencia!;
      _ubicacionCambiada = true;
    });
  }

  // ------------------------------------------------------------ guardar

  Future<void> _confirmarPedido() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      _aviso('Escribe el nombre del cliente.');
      return;
    }
    final items = _lineas.where((l) => l.cantidad > 0).toList();
    if (items.isEmpty) {
      _aviso('Elige el producto que se lleva.');
      return;
    }
    final sinPrecio = items.where((l) => l.precio <= 0).toList();
    if (sinPrecio.isNotEmpty) {
      _aviso('Escribe cuánto debe cobrar.');
      return;
    }

    final confirmado = await _resumen(items);
    if (confirmado != true) return;
    await _guardar(nombre, items);
  }

  Future<bool?> _resumen(List<LineaRapida> items) {
    final motorizado = _motorizados
        .where((m) => m['id'] == _motorizadoId)
        .map((m) => m['nombre'] as String? ?? '')
        .firstOrNull;

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Revisa el pedido',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
              SizedBox(height: 16),
              _FilaResumen('Cliente', _nombreCtrl.text.trim()),
              if (_telefonoCtrl.text.trim().isNotEmpty)
                _FilaResumen('Teléfono', _telefonoCtrl.text.trim()),
              _FilaResumen(
                'Producto',
                items.map((l) => '${l.nombre} × ${l.cantidad}').join('\n'),
              ),
              _FilaResumen(
                'Cobrar',
                dinero(_total),
                destacado: true,
                color: AppTheme.primary,
              ),
              _FilaResumen('Pago', _etiquetaPago(_formaPago)),
              _FilaResumen(
                'Ubicación',
                _direccion.isEmpty ? 'Sin marcar' : _direccion,
                color: _direccion.isEmpty ? AppTheme.warning : null,
              ),
              if (_referencia.isNotEmpty) _FilaResumen('Referencia', _referencia),
              _FilaResumen('Motorizado', motorizado ?? 'Lo asigna después'),
              if (_notaCtrl.text.trim().isNotEmpty)
                _FilaResumen('Nota', _notaCtrl.text.trim()),
              SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => Navigator.of(ctx).pop(true),
                icon: Icon(Icons.check_circle_outline),
                label: Text('CONFIRMAR PEDIDO'),
                style: FilledButton.styleFrom(minimumSize: Size.fromHeight(54)),
              ),
              SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('Volver a revisar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _guardar(String nombre, List<LineaRapida> items) async {
    setState(() => _guardando = true);
    final auth = ref.read(authProvider);
    final total = items.fold<double>(0, (s, l) => s + l.subtotal);
    final uuid = Uuid().v4();
    final nota = _notaCtrl.text.trim();
    final telefono = _telefonoCtrl.text.trim();
    final empresaId = auth.empresaId!;
    final usuarioId = auth.usuarioId!;

    final lineas = items
        .map((l) => LineaPedido(
              productoId: l.productoId,
              nombre: l.nombre,
              cantidad: l.cantidad,
              precioUnitario: l.precio,
            ))
        .toList();

    // Sin conexión y cliente nuevo: la cola crea el cliente al sincronizar.
    final clienteNuevo = _cliente == null
        ? {
            'nombre': nombre,
            'telefono': telefono.isEmpty ? null : telefono,
            'direccion': _direccion.isEmpty ? null : _direccion,
            'referencia': _referencia.isEmpty ? null : _referencia,
            'latitud': _latitud,
            'longitud': _longitud,
          }
        : null;

    try {
      // 1) Cliente: se reutiliza el elegido o se crea con estos datos.
      String clienteId;
      if (_cliente != null) {
        clienteId = _cliente!['id'] as String;
        final telefonoCambio =
            telefono.isNotEmpty && telefono != (_cliente!['telefono'] as String? ?? '');
        if (_ubicacionCambiada || telefonoCambio) {
          await clientesRepo.guardarUbicacion(
            clienteId: clienteId,
            telefono: telefono.isEmpty ? null : telefono,
            direccion: _direccion.isEmpty ? null : _direccion,
            referencia: _referencia.isEmpty ? null : _referencia,
            latitud: _latitud,
            longitud: _longitud,
          );
        }
      } else {
        clienteId = await clientesRepo.crear(
          empresaId: empresaId,
          nombre: nombre,
          telefono: telefono.isEmpty ? null : telefono,
          direccion: _direccion.isEmpty ? null : _direccion,
          referencia: _referencia.isEmpty ? null : _referencia,
          latitud: _latitud,
          longitud: _longitud,
        );
      }

      // 2) Pedido.
      final pedidoId = await pedidosRepo.crear(
        empresaId: empresaId,
        clienteId: clienteId,
        usuarioId: usuarioId,
        lineas: lineas,
        total: total,
        formaPago: _formaPago,
        observaciones: nota,
        repartidorId: _motorizadoId,
        uuidOffline: uuid,
      );

      // 3) Si se eligió motorizado, queda asignado de una vez.
      if (_motorizadoId != null) {
        final nombreMoto = _motorizados
            .where((m) => m['id'] == _motorizadoId)
            .map((m) => m['nombre'] as String?)
            .firstOrNull;
        await pedidosRepo.asignar(
          pedidoId: pedidoId,
          empresaId: empresaId,
          usuarioId: usuarioId,
          repartidorId: _motorizadoId,
          nombreRepartidor: nombreMoto,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_motorizadoId == null
              ? 'Pedido creado.'
              : 'Pedido creado y asignado.'),
        ),
      );
    } catch (e) {
      if (esErrorDeRed(e)) {
        await Outbox.encolarPedido(
          pedido: {
            'empresa_id': empresaId,
            'cliente_id': _cliente?['id'],
            'creado_por': usuarioId,
            'forma_pago': _formaPago,
            'observaciones': nota.isEmpty ? null : nota,
            'total': total,
            'uuid_offline': uuid,
            if (_motorizadoId != null) 'repartidor_id': _motorizadoId,
            if (_motorizadoId != null) 'estado': 'ASIGNADO',
          },
          detalles: items
              .map((l) => {
                    'empresa_id': empresaId,
                    'producto_id': l.productoId,
                    'cantidad': l.cantidad,
                    'precio_unitario': l.precio,
                  })
              .toList(),
          clienteNuevo: clienteNuevo,
        );
        if (!mounted) return;
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sin conexión: el pedido quedó guardado y se enviará solo.'),
          ),
        );
        return;
      }
      if (!mounted) return;
      setState(() => _guardando = false);
      _aviso(traducirError(e, contexto: 'No pudimos crear el pedido').mensaje);
    }
  }

  String _etiquetaPago(String v) => switch (v) {
        'EFECTIVO' => 'Efectivo',
        'YAPE' => 'Yape',
        'DEUDA' => 'Queda debiendo',
        _ => 'Otro',
      };

  void _aviso(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Nuevo pedido')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          _seccionCliente(),
          SizedBox(height: 12),
          _seccionUbicacion(),
          SizedBox(height: 12),
          _seccionProducto(),
          SizedBox(height: 12),
          _seccionPago(),
          if (_motorizados.isNotEmpty) ...[
            SizedBox(height: 12),
            _seccionMotorizado(),
          ],
          SizedBox(height: 12),
          TextField(
            controller: _notaCtrl,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Nota (opcional)',
              hintText: 'Casa azul, dejar con el vecino…',
              prefixIcon: Icon(Icons.notes_outlined),
            ),
          ),
        ],
      ),
      bottomSheet: _barraInferior(),
    );
  }

  Widget _seccionCliente() {
    final c = _cliente;
    return _seccion(
      titulo: '¿Quién llama?',
      icono: Icons.person_outline,
      hijos: [
        if (c == null) ...[
          TextField(
            controller: _nombreCtrl,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onChanged: _buscarCliente,
            decoration: InputDecoration(
              labelText: 'Nombre',
              hintText: 'Juan Pérez',
              prefixIcon: Icon(Icons.badge_outlined),
              suffixIcon: _buscandoCliente
                  ? Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
          ),
          SizedBox(height: 10),
          TextField(
            controller: _telefonoCtrl,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +*#-]'))],
            decoration: InputDecoration(
              labelText: 'Teléfono',
              hintText: '999 888 777',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          if (_sugerencias.isNotEmpty) ...[
            SizedBox(height: 6),
            for (final s in _sugerencias)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                  child: Text(
                    (s['nombre'] as String? ?? '?')[0].toUpperCase(),
                    style: TextStyle(color: AppTheme.primary),
                  ),
                ),
                title: Text(s['nombre'] as String? ?? ''),
                subtitle: Text([
                  if (s['telefono'] != null) s['telefono'],
                  if (s['direccion'] != null) s['direccion'],
                ].whereType<String>().join(' · ')),
                onTap: () => _usarCliente(s),
              ),
            if (_sugerencias.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Toca un cliente para usar su dirección guardada.',
                  style: TextStyle(fontSize: 12, color: AppColors.textoMuted),
                ),
              ),
          ],
        ] else
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
              child: Text(
                (c['nombre'] as String? ?? '?')[0].toUpperCase(),
                style: TextStyle(color: AppTheme.primary),
              ),
            ),
            title: Text(c['nombre'] as String? ?? '',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text([
              if ((c['telefono'] as String? ?? '').isNotEmpty) c['telefono'],
              if ((c['direccion'] as String? ?? '').isNotEmpty) c['direccion'],
            ].whereType<String>().join(' · ')),
            trailing: TextButton(
              onPressed: () => setState(() {
                _cliente = null;
                _nombreCtrl.clear();
                _telefonoCtrl.clear();
                _lineas = [];
                _preciosCliente = {};
              }),
              child: Text('Cambiar'),
            ),
          ),
      ],
    );
  }

  Widget _seccionUbicacion() {
    final marcada = _latitud != null && _longitud != null;
    return _seccion(
      titulo: '¿Dónde llevar?',
      icono: Icons.place_outlined,
      hijos: [
        if (_direccion.isNotEmpty || marcada)
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle, color: AppTheme.success, size: 18),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _direccion.isEmpty ? 'Punto marcado en el mapa' : _direccion,
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                  ],
                ),
                if (_referencia.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 2, left: 24),
                    child: Text(_referencia,
                        style: TextStyle(fontSize: 12.5, color: AppColors.textoSecundario)),
                  ),
                if (marcada)
                  Padding(
                    padding: EdgeInsets.only(top: 2, left: 24),
                    child: Text(
                      '${_latitud!.toStringAsFixed(5)}, ${_longitud!.toStringAsFixed(5)}',
                      style: TextStyle(fontSize: 11, color: AppColors.textoMuted),
                    ),
                  ),
              ],
            ),
          ),
        SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _marcarUbicacion,
          icon: Icon(Icons.map_outlined),
          label: Text(
            marcada || _direccion.isNotEmpty ? 'Cambiar ubicación' : 'Marcar ubicación',
          ),
          style: OutlinedButton.styleFrom(minimumSize: Size.fromHeight(50)),
        ),
      ],
    );
  }

  Widget _seccionProducto() {
    return _seccion(
      titulo: '¿Qué se lleva?',
      icono: Icons.propane_tank_outlined,
      hijos: [
        if (_cargandoProductos)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_errorProductos != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_errorProductos!, style: TextStyle(color: AppTheme.danger)),
              TextButton(onPressed: _cargarProductos, child: Text('Reintentar')),
            ],
          )
        else if (_productos.isEmpty)
          Text('No hay productos cargados. Pide al administrador que los registre.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in _productos)
                _ChipProducto(
                  nombre: _nombreProducto(p),
                  sugerido: _sugeridoPara(p),
                  seleccionado: _lineas.any((l) => l.productoId == p['id']),
                  onTap: () => _alternarProducto(p),
                ),
            ],
          ),
        for (var i = 0; i < _lineas.length; i++) ...[
          SizedBox(height: 10),
          _LineaCard(
            linea: _lineas[i],
            puedeQuitar: _lineas.length > 1,
            onCambio: (nueva) => _actualizar(i, nueva),
            onQuitar: () => setState(() => _lineas.removeAt(i)),
          ),
        ],
      ],
    );
  }

  Widget _seccionPago() {
    return _seccion(
      titulo: '¿Cómo paga?',
      icono: Icons.payments_outlined,
      hijos: [
        Row(
          children: [
            for (final f in _formasPago) ...[
              Expanded(
                child: _BotonOpcion(
                  icono: f.$2,
                  etiqueta: f.$3,
                  seleccionado: _formaPago == f.$1,
                  color: f.$1 == 'DEUDA' ? AppTheme.warning : AppTheme.primary,
                  onTap: () => setState(() => _formaPago = f.$1),
                ),
              ),
              if (f != _formasPago.last) SizedBox(width: 8),
            ],
          ],
        ),
        if (_formaPago == 'DEUDA')
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Quedará como deuda del cliente.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textoSecundario),
            ),
          ),
      ],
    );
  }

  Widget _seccionMotorizado() {
    return _seccion(
      titulo: '¿Quién lo lleva?',
      icono: Icons.delivery_dining_outlined,
      hijos: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text('Sin asignar'),
              selected: _motorizadoId == null,
              selectedColor: AppTheme.primary.withValues(alpha: 0.15),
              onSelected: (_) => setState(() => _motorizadoId = null),
            ),
            for (final m in _motorizados)
              ChoiceChip(
                avatar: Icon(
                  Icons.circle,
                  size: 10,
                  color: (_enRuta[m['id']] ?? 0) > 0 ? AppTheme.warning : AppTheme.success,
                ),
                label: Text(m['nombre'] as String? ?? ''),
                selected: _motorizadoId == m['id'],
                selectedColor: AppTheme.primary.withValues(alpha: 0.15),
                onSelected: (_) => setState(() => _motorizadoId = m['id'] as String),
              ),
          ],
        ),
        SizedBox(height: 6),
        Text(
          _motorizadoId == null
              ? 'El pedido queda libre para que lo tome un motorizado.'
              : 'Queda asignado ahora mismo.',
          style: TextStyle(fontSize: 12, color: AppColors.textoMuted),
        ),
      ],
    );
  }

  Widget _barraInferior() {
    final listo = _lineas.isNotEmpty &&
        _lineas.every((l) => l.cantidad > 0 && l.precio > 0);
    return Container(
      padding: EdgeInsets.fromLTRB(20, 10, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.borde)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _cantidad == 1 ? '1 unidad' : '$_cantidad unidades',
                  style: TextStyle(color: AppColors.textoSecundario, fontSize: 12.5),
                ),
                Text(
                  dinero(_total),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),
            SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _guardando || !listo ? null : _confirmarPedido,
                icon: Icon(Icons.check),
                label: Text(_guardando ? 'Guardando…' : 'CONFIRMAR PEDIDO'),
                style: FilledButton.styleFrom(minimumSize: Size.fromHeight(52)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _seccion({
    required String titulo,
    required IconData icono,
    required List<Widget> hijos,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icono, size: 20, color: AppTheme.primary),
                SizedBox(width: 8),
                Text(
                  titulo,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            SizedBox(height: 12),
            ...hijos,
          ],
        ),
      ),
    );
  }
}

/// Chip grande de producto: nombre + precio sugerido (solo referencia).
class _ChipProducto extends StatelessWidget {
  final String nombre;
  final double? sugerido;
  final bool seleccionado;
  final VoidCallback onTap;

  const _ChipProducto({
    required this.nombre,
    required this.sugerido,
    required this.seleccionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: seleccionado ? AppTheme.primary.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: seleccionado ? AppTheme.primary : AppColors.borde,
            width: seleccionado ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              nombre,
              style: TextStyle(
                fontWeight: seleccionado ? FontWeight.w700 : FontWeight.w600,
                color: seleccionado ? AppTheme.primary : AppColors.textoPrincipal,
                fontSize: 14,
              ),
            ),
            if (sugerido != null)
              Text(
                'Sugerido ${dinero(sugerido!)}',
                style: TextStyle(fontSize: 11, color: AppColors.textoMuted),
              ),
          ],
        ),
      ),
    );
  }
}

/// Línea elegida: cantidad y precio libre.
class _LineaCard extends StatelessWidget {
  final LineaRapida linea;
  final bool puedeQuitar;
  final ValueChanged<LineaRapida> onCambio;
  final VoidCallback onQuitar;

  const _LineaCard({
    required this.linea,
    required this.puedeQuitar,
    required this.onCambio,
    required this.onQuitar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color(0xFFF7F8F6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  linea.nombre,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                ),
              ),
              if (puedeQuitar)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Quitar',
                  onPressed: onQuitar,
                  icon: Icon(Icons.close, size: 18),
                ),
            ],
          ),
          SizedBox(height: 6),
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: linea.cantidad > 1
                    ? () => onCambio(linea.copyWith(cantidad: linea.cantidad - 1))
                    : null,
                icon: Icon(Icons.remove, size: 18),
              ),
              SizedBox(
                width: 34,
                child: Text(
                  '${linea.cantidad}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
              IconButton.filledTonal(
                onPressed: () => onCambio(linea.copyWith(cantidad: linea.cantidad + 1)),
                icon: Icon(Icons.add, size: 18),
              ),
              Spacer(),
              Expanded(
                flex: 2,
                child: TextFormField(
                  key: ValueKey('precio-${linea.productoId}-${linea.cantidad}'),
                  initialValue: linea.precio > 0 ? PrecioLibre.paraEditar(linea.precio) : '',
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  onChanged: (t) =>
                      onCambio(linea.copyWith(precio: PrecioLibre.parse(t) ?? 0)),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixText: 'S/ ',
                    labelText: 'Cobrar',
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Botón grande de forma de pago.
class _BotonOpcion extends StatelessWidget {
  final IconData icono;
  final String etiqueta;
  final bool seleccionado;
  final Color color;
  final VoidCallback onTap;

  const _BotonOpcion({
    required this.icono,
    required this.etiqueta,
    required this.seleccionado,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 62,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: seleccionado ? color.withValues(alpha: 0.14) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: seleccionado ? color : AppColors.borde,
            width: seleccionado ? 1.6 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icono, size: 22, color: seleccionado ? color : AppColors.textoSecundario),
            SizedBox(height: 2),
            Text(
              etiqueta,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: seleccionado ? color : AppColors.textoPrincipal,
                fontWeight: seleccionado ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fila del resumen previo a confirmar.
class _FilaResumen extends StatelessWidget {
  final String etiqueta;
  final String valor;
  final bool destacado;
  final Color? color;

  const _FilaResumen(
    this.etiqueta,
    this.valor, {
    this.destacado = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(etiqueta,
                style: TextStyle(color: AppColors.textoSecundario, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              valor,
              style: TextStyle(
                fontWeight: destacado ? FontWeight.bold : FontWeight.w500,
                fontSize: destacado ? 20 : 14,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}