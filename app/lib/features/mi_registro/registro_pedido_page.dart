/// "Mi registro" del motorizado: registro rápido de un pedido propio.
///
/// Unificado con el resto del sistema: lo que aquí se registra es un PEDIDO
/// real (origen MOTORIZADO) que ya queda ENTREGADO, con su pago, su balón
/// y su movimiento de caja. No existe una tabla paralela: la rendición, la
/// caja, el recepcionista y el admin lo ven automáticamente.
library;

import 'package:gas_app/core/theme/app_colors.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme.dart';
import '../../core/data/clientes_repo.dart';
import '../../core/data/entregas_repo.dart';
import '../../core/data/pedidos_repo.dart';
import '../../core/data/productos_repo.dart';
import '../../core/data/sb.dart';
import '../../core/domain/formato.dart';
import '../../core/domain/precio.dart';
import '../../core/offline/outbox.dart';
import '../../core/storage/comprobante_service.dart';
import '../auth/auth_controller.dart';
import '../clientes/mapa_selector_page.dart';

class RegistroPedidoPage extends ConsumerStatefulWidget {
  RegistroPedidoPage({super.key});

  @override
  ConsumerState<RegistroPedidoPage> createState() => _RegistroPedidoPageState();
}

class _RegistroPedidoPageState extends ConsumerState<RegistroPedidoPage> {
  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _referenciaCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();
  final _precioCtrl = TextEditingController();
  final _cantidadCtrl = TextEditingController(text: '1');

  Map<String, dynamic>? _cliente;
  List<Map<String, dynamic>> _sugerencias = [];
  bool _buscandoCliente = false;

  List<Map<String, dynamic>> _productos = [];
  bool _cargandoProductos = true;
  String? _productoSeleccionadoId;

  String _formaPago = 'EFECTIVO';
  bool _balonDejado = false;
  DateTime _hora = DateTime.now();
  double? _latitud;
  double? _longitud;
  String? _fotoPath; // ruta local del comprobante (Yape)
  bool _subiendoFoto = false;

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
  }

  @override
  void dispose() {
    for (final c in [
      _nombreCtrl,
      _telefonoCtrl,
      _direccionCtrl,
      _referenciaCtrl,
      _observacionesCtrl,
      _precioCtrl,
      _cantidadCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cargarProductos() async {
    try {
      final data = await ProductosRepo().vendibles();
      if (!mounted) return;
      setState(() {
        _productos = data;
        _cargandoProductos = false;
        if (data.isNotEmpty && _productoSeleccionadoId == null) {
          _productoSeleccionadoId = data.first['id'] as String;
          final sugerido = (data.first['precio_base'] as num?)?.toDouble();
          if (sugerido != null && sugerido > 0) {
            _precioCtrl.text = PrecioLibre.paraEditar(sugerido);
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargandoProductos = false);
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
    _direccionCtrl.text = cliente['direccion'] as String? ?? '';
    _referenciaCtrl.text = cliente['referencia'] as String? ?? '';
    _latitud = (cliente['latitud'] as num?)?.toDouble();
    _longitud = (cliente['longitud'] as num?)?.toDouble();
    _sugerencias = [];
    setState(() => _cliente = cliente);
  }

  Future<void> _marcarUbicacion() async {
    final elegida = await abrirMiniMapa(
      context,
      latitud: _latitud,
      longitud: _longitud,
      direccion: _direccionCtrl.text,
      referencia: _referenciaCtrl.text,
      titulo: 'Ubicación del cliente',
    );
    if (elegida == null) return;
    setState(() {
      _latitud = elegida.latitud;
      _longitud = elegida.longitud;
      if ((elegida.direccion ?? '').isNotEmpty) _direccionCtrl.text = elegida.direccion!;
      if ((elegida.referencia ?? '').isNotEmpty) _referenciaCtrl.text = elegida.referencia!;
    });
  }

  Future<void> _tomarFoto(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(source: source, imageQuality: 70, maxWidth: 1280);
      if (x == null) return;
      // Copiar a directorio persistente para que no se pierda offline.
      final dir = await getApplicationDocumentsDirectory();
      final destino = Directory('${dir.path}/comprobantes');
      if (!await destino.exists()) await destino.create(recursive: true);
      final archivo = File('${destino.path}/${Uuid().v4()}.jpg');
      await File(x.path).copy(archivo.path);
      if (!mounted) return;
      setState(() => _fotoPath = archivo.path);
    } catch (_) {
      _aviso('No se pudo obtener la foto.');
    }
  }

  void _mostrarOpcionesFoto() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.camera_alt_outlined),
              title: Text('Tomar foto'),
              onTap: () {
                Navigator.of(ctx).pop();
                _tomarFoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined),
              title: Text('Elegir de la galería'),
              onTap: () {
                Navigator.of(ctx).pop();
                _tomarFoto(ImageSource.gallery);
              },
            ),
            if (_fotoPath != null)
              ListTile(
                leading: Icon(Icons.delete_outline, color: AppTheme.danger),
                title: Text('Quitar foto'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  setState(() => _fotoPath = null);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      _aviso('Escribe el nombre del cliente.');
      return;
    }
    final producto = _productos.firstWhere(
      (p) => p['id'] == _productoSeleccionadoId,
      orElse: () => <String, dynamic>{},
    );
    if (producto.isEmpty) {
      _aviso('Elige un producto.');
      return;
    }
    final cantidad = int.tryParse(_cantidadCtrl.text) ?? 0;
    if (cantidad <= 0) {
      _aviso('La cantidad debe ser mayor a cero.');
      return;
    }
    final precio = PrecioLibre.parse(_precioCtrl.text);
    if (precio == null) {
      _aviso('Escribe cuánto cobraste.');
      return;
    }
    if (_formaPago == 'YAPE' && _fotoPath == null) {
      final continuar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Sin comprobante'),
          content: Text(
            'Registraste un cobro por Yape sin foto del comprobante. '
            '¿Deseas continuar de todas formas?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('Agregar foto')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text('Continuar')),
          ],
        ),
      );
      if (continuar != true) return;
    }

    setState(() => _guardando = true);
    final auth = ref.read(authProvider);
    final empresaId = auth.empresaId!;
    final usuarioId = auth.usuarioId!;
    final total = precio * cantidad;
    final uuid = Uuid().v4();
    final telefono = _telefonoCtrl.text.trim();
    final direccion = _direccionCtrl.text.trim();
    final referencia = _referenciaCtrl.text.trim();
    final observaciones = _observacionesCtrl.text.trim();
    final balonDejado = _balonDejado;
    final formaPago = _formaPago;
    final montoCobrado = formaPago == 'DEUDA' ? 0.0 : total;
    final cobrado = montoCobrado > 0.009;

    final clienteNuevo = _cliente == null
        ? {
            'nombre': nombre,
            'telefono': telefono.isEmpty ? null : telefono,
            'direccion': direccion.isEmpty ? null : direccion,
            'referencia': referencia.isEmpty ? null : referencia,
            'latitud': _latitud,
            'longitud': _longitud,
          }
        : null;

    try {
      // 1) Cliente.
      String clienteId;
      if (_cliente != null) {
        clienteId = _cliente!['id'] as String;
        await clientesRepo.guardarUbicacion(
          clienteId: clienteId,
          telefono: telefono.isEmpty ? null : telefono,
          direccion: direccion.isEmpty ? null : direccion,
          referencia: referencia.isEmpty ? null : referencia,
          latitud: _latitud,
          longitud: _longitud,
        );
      } else {
        clienteId = await clientesRepo.crear(
          empresaId: empresaId,
          nombre: nombre,
          telefono: telefono.isEmpty ? null : telefono,
          direccion: direccion.isEmpty ? null : direccion,
          referencia: referencia.isEmpty ? null : referencia,
          latitud: _latitud,
          longitud: _longitud,
        );
      }

      // 2) Pedido (origen MOTORIZADO, ya entregado).
      final pedidoId = await pedidosRepo.crear(
        empresaId: empresaId,
        clienteId: clienteId,
        usuarioId: usuarioId,
        lineas: [
          LineaPedido(
            productoId: producto['id'] as String,
            nombre: _nombreProducto(producto),
            cantidad: cantidad,
            precioUnitario: precio,
          ),
        ],
        total: total,
        formaPago: formaPago,
        observaciones: observaciones.isEmpty ? null : observaciones,
        repartidorId: usuarioId,
        uuidOffline: uuid,
        origen: 'MOTORIZADO',
        // La hora la pone la base de datos (`pedidos.fecha default now()`).
      );

      // 3) Subir comprobante si hay foto y es Yape.
      String? comprobanteUrl;
      if (formaPago == 'YAPE' && _fotoPath != null) {
        setState(() => _subiendoFoto = true);
        comprobanteUrl = await ComprobanteService.subir(_fotoPath!);
        if (mounted) setState(() => _subiendoFoto = false);
      }

      // 4) Entrega completa: pago, balón, fierro, caja.
      final balonVacio = balonDejado
          ? EstadoBalonVacio.recibido
          : EstadoBalonVacio.noRecibido;
      final datos = DatosEntrega(
        montoCobrado: montoCobrado,
        metodo: formaPago,
        balonVacio: balonVacio,
        fierro: EstadoFierro.noAplica,
        cantidadBalones: balonDejado ? cantidad : 0,
        cantidadFierros: 0,
        observaciones: observaciones.isEmpty ? null : observaciones,
      );
      await entregasRepo.registrarEntrega(
        empresaId: empresaId,
        usuarioId: usuarioId,
        pedidoId: pedidoId,
        clienteId: clienteId,
        total: total,
        datos: datos,
        comprobanteUrl: comprobanteUrl,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            formaPago == 'DEUDA'
                ? 'Registrado. Queda debiendo ${dinero(total)}.'
                : 'Registrado. Cobrado ${dinero(montoCobrado)}.',
          ),
        ),
      );
    } catch (e) {
      if (esErrorDeRed(e)) {
        await Outbox.encolarPedidoCompleto(
          uuidOffline: uuid,
          pedido: {
            'empresa_id': empresaId,
            'cliente_id': _cliente?['id'],
            'creado_por': usuarioId,
            'forma_pago': formaPago,
            'observaciones': observaciones.isEmpty ? null : observaciones,
            'total': total,
            'uuid_offline': uuid,
            'repartidor_id': usuarioId,
            'origen': 'MOTORIZADO',
            'fecha': DateTime.now().toIso8601String(),
          },
          clienteNuevo: clienteNuevo,
          detalles: [
            {
              'empresa_id': empresaId,
              'producto_id': producto['id'],
              'cantidad': cantidad,
              'precio_unitario': precio,
            },
          ],
          entrega: {
            'estado_bal_on_vacio': (balonDejado ? 'RECIBIDO' : 'NO_RECIBIDO'),
            'estado_pago': montoCobrado + 0.009 >= total ? 'PAGADO' : 'PENDIENTE',
            'registrado_por': usuarioId,
            'empresa_id': empresaId,
          },
          pago: cobrado
              ? {
                  'monto': montoCobrado,
                  'metodo': formaPago,
                  'registrado_por': usuarioId,
                  'empresa_id': empresaId,
                }
              : null,
          balon: balonDejado
              ? {
                  'cantidad': cantidad,
                  'usuario_id': usuarioId,
                  'empresa_id': empresaId,
                }
              : null,
          comprobanteLocalPath: _fotoPath,
        );
        if (!mounted) return;
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sin conexión: el registro quedó guardado y se enviará solo.'),
          ),
        );
        return;
      }
      if (!mounted) return;
      setState(() => _guardando = false);
      _aviso(traducirError(e, contexto: 'No pudimos registrar').mensaje);
    } finally {
      if (mounted) setState(() => _subiendoFoto = false);
    }
  }

  String _nombreProducto(Map<String, dynamic> p) {
    final kg = p['capacidad_kg'];
    final nombre = p['nombre'] as String? ?? 'Producto';
    return kg == null ? nombre : '$nombre (${kg}kg)';
  }

  void _aviso(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Nuevo registro')),
      body: _cargandoProductos
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : ListView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                _seccion(
                  titulo: '¿A dónde lo llevaste?',
                  icono: Icons.place_outlined,
                  hijos: [
                    TextField(
                      controller: _nombreCtrl,
                      textCapitalization: TextCapitalization.words,
                      onChanged: _buscarCliente,
                      decoration: InputDecoration(
                        labelText: 'Cliente',
                        hintText: 'Juan Pérez',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                    if (_buscandoCliente)
                      Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    if (_sugerencias.isNotEmpty) ...[
                      SizedBox(height: 6),
                      for (final s in _sugerencias)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(s['nombre'] as String? ?? ''),
                          subtitle: Text(s['telefono'] as String? ?? ''),
                          onTap: () => _usarCliente(s),
                        ),
                    ],
                    SizedBox(height: 10),
                    TextField(
                      controller: _telefonoCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Teléfono (opcional)',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                    SizedBox(height: 10),
                    TextField(
                      controller: _direccionCtrl,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: 'Dirección',
                        prefixIcon: Icon(Icons.signpost_outlined),
                      ),
                    ),
                    SizedBox(height: 10),
                    TextField(
                      controller: _referenciaCtrl,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: 'Referencia (opcional)',
                        prefixIcon: Icon(Icons.info_outline),
                      ),
                    ),
                    SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _marcarUbicacion,
                      icon: Icon(Icons.map_outlined),
                      label: Text(
                        _latitud != null ? 'Cambiar ubicación' : 'Marcar ubicación',
                      ),
                      style: OutlinedButton.styleFrom(minimumSize: Size.fromHeight(46)),
                    ),
                    if (_latitud != null)
                      Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          '${_latitud!.toStringAsFixed(5)}, ${_longitud!.toStringAsFixed(5)}',
                          style: TextStyle(fontSize: 11.5, color: AppColors.textoMuted),
                        ),
                      ),
                  ],
                ),
                SizedBox(height: 12),
                _seccion(
                  titulo: 'Hora del pedido',
                  icono: Icons.schedule_outlined,
                  hijos: [
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 18, color: AppColors.textoMuted),
                        SizedBox(width: 8),
                        Text(
                          '${_hora.hour.toString().padLeft(2, '0')}:${_hora.minute.toString().padLeft(2, '0')}'
                          '  ·  ${_hora.day}/${_hora.month}/${_hora.year}',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      'La hora la registra el sistema automáticamente.',
                      style: TextStyle(fontSize: 12, color: AppColors.textoMuted),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                _seccion(
                  titulo: '¿Qué llevaste?',
                  icono: Icons.propane_tank_outlined,
                  hijos: [
                    if (_cargandoProductos)
                      Center(child: CircularProgressIndicator(strokeWidth: 2))
                    else if (_productos.length == 1)
                      Padding(
                        padding: EdgeInsets.only(bottom: 4),
                        child: Text(
                          'Producto: ${_nombreProducto(_productos.first)}',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final p in _productos)
                            ChoiceChip(
                              label: Text(_nombreProducto(p)),
                              selected: _productoSeleccionadoId == p['id'],
                              onSelected: (_) {
                                setState(() {
                                  _productoSeleccionadoId = p['id'] as String;
                                });
                                final sug = (p['precio_base'] as num?)?.toDouble();
                                if (sug != null && sug > 0 && _precioCtrl.text.isEmpty) {
                                  _precioCtrl.text = PrecioLibre.paraEditar(sug);
                                }
                              },
                            ),
                        ],
                      ),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Text('Cantidad', style: TextStyle(fontWeight: FontWeight.w600)),
                        Spacer(),
                        IconButton.filledTonal(
                          onPressed: (int.tryParse(_cantidadCtrl.text) ?? 1) > 1
                              ? () => setState(() {
                                    final n = (int.tryParse(_cantidadCtrl.text) ?? 1) - 1;
                                    _cantidadCtrl.text = '$n';
                                  })
                              : null,
                          icon: Icon(Icons.remove, size: 18),
                        ),
                        SizedBox(
                          width: 34,
                          child: Text(
                            _cantidadCtrl.text,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                        ),
                        IconButton.filledTonal(
                          onPressed: () => setState(() {
                            final n = (int.tryParse(_cantidadCtrl.text) ?? 0) + 1;
                            _cantidadCtrl.text = '$n';
                          }),
                          icon: Icon(Icons.add, size: 18),
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    TextField(
                      controller: _precioCtrl,
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        prefixText: 'S/ ',
                        labelText: '¿Cuánto cobraste?',
                        hintText: '50',
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                _seccion(
                  titulo: '¿Cómo pagó?',
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
                    if (_formaPago == 'YAPE') ...[
                      SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _subiendoFoto ? null : _mostrarOpcionesFoto,
                        icon: _subiendoFoto
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(Icons.camera_alt_outlined),
                        label: Text(_fotoPath == null ? 'Tomar foto del comprobante' : 'Cambiar foto'),
                        style: OutlinedButton.styleFrom(minimumSize: Size.fromHeight(46)),
                      ),
                      if (_fotoPath != null) ...[
                        SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(_fotoPath!),
                            height: 140,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ],
                    ],
                    if (_formaPago == 'DEUDA')
                      Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Quedará como deuda del cliente (no se cuenta como dinero recibido).',
                          style: TextStyle(fontSize: 12.5, color: AppColors.textoSecundario),
                        ),
                      ),
                  ],
                ),
                SizedBox(height: 12),
                _seccion(
                  titulo: '¿Dejó balón vacío?',
                  icono: Icons.recycling_outlined,
                  hijos: [
                    Row(
                      children: [
                        Expanded(
                          child: _BotonOpcion(
                            icono: Icons.check_circle_outline,
                            etiqueta: 'Sí',
                            seleccionado: _balonDejado,
                            color: AppTheme.success,
                            onTap: () => setState(() => _balonDejado = true),
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: _BotonOpcion(
                            icono: Icons.cancel_outlined,
                            etiqueta: 'No',
                            seleccionado: !_balonDejado,
                            color: AppTheme.warning,
                            onTap: () => setState(() => _balonDejado = false),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: 12),
                TextField(
                  controller: _observacionesCtrl,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Observación (opcional)',
                    hintText: 'Casa azul, paga mañana…',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
              ],
            ),
      bottomSheet: Container(
        padding: EdgeInsets.fromLTRB(20, 10, 20, 16),
        decoration: BoxDecoration(
          color: AppColors.superficie,
          border: Border(top: BorderSide(color: AppColors.borde)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon: _guardando
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(Icons.check),
                  label: Text(_guardando ? 'Guardando…' : 'REGISTRAR'),
                  style: FilledButton.styleFrom(minimumSize: Size.fromHeight(52)),
                ),
              ),
            ],
          ),
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
                Text(titulo, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
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
          color: seleccionado ? color.withValues(alpha: 0.14) : AppColors.superficie,
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