/// Detalle de un pedido.
///
/// Muestra solo lo necesario para atender la entrega y, según el rol,
/// las acciones: asignar, tomar, iniciar ruta, entregar, cancelar.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import '../../core/data/entregas_repo.dart';
import '../../core/data/motorizados_repo.dart';
import '../../core/data/pedidos_repo.dart';
import '../../core/data/sb.dart';
import '../../core/domain/estado_pedido.dart';
import '../../core/domain/formato.dart';
import '../../core/domain/navegacion.dart';
import '../../core/offline/outbox.dart';
import '../../core/ui/widgets.dart';
import '../auth/auth_controller.dart';
import 'entrega_sheet.dart';

class PedidoDetallePage extends ConsumerStatefulWidget {
  final Map<String, dynamic> pedido;

  const PedidoDetallePage({super.key, required this.pedido});

  @override
  ConsumerState<PedidoDetallePage> createState() => _PedidoDetallePageState();
}

class _PedidoDetallePageState extends ConsumerState<PedidoDetallePage> {
  List<Map<String, dynamic>> _detalles = [];
  Map<String, dynamic>? _entrega;
  List<Map<String, dynamic>> _pagos = [];
  String? _motorizadoNombre;
  bool _cargando = true;
  bool _trabajando = false;

  SupabaseClient get _sb => Supabase.instance.client;

  String get _pedidoId => widget.pedido['id'] as String;

  EstadoPedido get _estado => EstadoPedido.desdeDb(widget.pedido['estado']);

  double get _total => (widget.pedido['total'] as num? ?? 0).toDouble();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final resultados = await Future.wait([
        pedidosRepo.detalles(_pedidoId),
        pedidosRepo.entregaDe(_pedidoId),
        pedidosRepo.pagosDe(_pedidoId),
      ]);
      final repartidorId = widget.pedido['repartidor_id'] as String?;
      String? nombre;
      if (repartidorId != null) {
        final perfil =
            await _sb.from('perfiles').select('nombre').eq('id', repartidorId).maybeSingle();
        nombre = perfil?['nombre'] as String?;
      }
      if (!mounted) return;
      setState(() {
        _detalles = resultados[0] as List<Map<String, dynamic>>;
        _entrega = resultados[1] as Map<String, dynamic>?;
        _pagos = resultados[2] as List<Map<String, dynamic>>;
        _motorizadoNombre = nombre;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      _error(traducirError(e, contexto: 'No pudimos cargar el pedido').mensaje);
    }
  }

  int get _cantidadBalones =>
      _detalles.fold(0, (s, d) => s + ((d['cantidad'] as num? ?? 0).toInt()));

  double get _cobrado =>
      _pagos.fold(0.0, (s, p) => s + ((p['monto'] as num? ?? 0).toDouble()));

  double get _deuda {
    final d = _total - _cobrado;
    return d > 0.009 ? d : 0;
  }

  // ------------------------------------------------------------------
  // Acciones
  // ------------------------------------------------------------------

  Future<void> _asignarMotorizado() async {
    List<Map<String, dynamic>> motorizados;
    try {
      motorizados = await motorizadosRepo.listar();
    } catch (_) {
      _error('No pudimos cargar los motorizados.');
      return;
    }
    if (motorizados.isEmpty) {
      _error('No tienes motorizados registrados. Agrégalos desde "Más".');
      return;
    }
    if (!mounted) return;

    final elegido = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('¿A quién se lo asignas?',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ),
            for (final m in motorizados)
              ListTile(
                leading: const Icon(Icons.delivery_dining_outlined),
                title: Text(m['nombre'] as String? ?? ''),
                subtitle: Text(m['telefono'] as String? ?? ''),
                onTap: () => Navigator.of(ctx).pop(m),
              ),
          ],
        ),
      ),
    );
    if (elegido == null) return;

    final auth = ref.read(authProvider);
    try {
      await pedidosRepo.asignar(
        pedidoId: _pedidoId,
        empresaId: auth.empresaId!,
        usuarioId: auth.usuarioId!,
        repartidorId: elegido['id'] as String,
        nombreRepartidor: elegido['nombre'] as String?,
      );
      widget.pedido['repartidor_id'] = elegido['id'];
      widget.pedido['estado'] = 'ASIGNADO';
      setState(() => _motorizadoNombre = elegido['nombre'] as String?);
      _mensaje('Pedido asignado a ${elegido['nombre']}.');
    } catch (e) {
      _error(e is Exception ? e.toString().replaceFirst('Exception: ', '') : 'No se pudo asignar.');
    }
  }

  Future<void> _tomarPedido() async {
    final auth = ref.read(authProvider);
    try {
      await pedidosRepo.asignar(
        pedidoId: _pedidoId,
        empresaId: auth.empresaId!,
        usuarioId: auth.usuarioId!,
        repartidorId: auth.usuarioId,
        nombreRepartidor: auth.nombre,
      );
      widget.pedido['repartidor_id'] = auth.usuarioId;
      widget.pedido['estado'] = 'ASIGNADO';
      setState(() => _motorizadoNombre = auth.nombre);
      _mensaje('Tomaste el pedido.');
    } catch (e) {
      _error(e is Exception ? e.toString().replaceFirst('Exception: ', '') : 'No se pudo tomar.');
    }
  }

  Future<void> _iniciarRuta() async {
    final auth = ref.read(authProvider);
    try {
      await pedidosRepo.cambiarEstado(
        pedidoId: _pedidoId,
        empresaId: auth.empresaId!,
        usuarioId: auth.usuarioId!,
        destino: EstadoPedido.enCamino,
        esAdmin: auth.esAdmin,
      );
      widget.pedido['estado'] = 'EN_CAMINO';
      setState(() {});
      _mensaje('Pedido en camino.');
    } catch (e) {
      _error(e is Exception ? e.toString().replaceFirst('Exception: ', '') : 'No se pudo actualizar.');
    }
  }

  Future<void> _entregar() async {
    final auth = ref.read(authProvider);

    final datos = await mostrarFormularioEntrega(
      context,
      total: _total,
      cantidadBalones: _cantidadBalones,
    );
    if (datos == null) return;

    setState(() => _trabajando = true);
    try {
      await entregasRepo.registrarEntrega(
        empresaId: auth.empresaId!,
        usuarioId: auth.usuarioId!,
        pedidoId: _pedidoId,
        clienteId: widget.pedido['cliente_id'] as String,
        total: _total,
        datos: datos,
      );
      widget.pedido['estado'] = 'ENTREGADO';
      await _cargar();
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mensajeEntrega(datos, _total))),
      );
    } catch (e) {
      if (esErrorDeRed(e)) {
        // Sin conexión: se encola y se sincroniza luego.
        await Outbox.encolarEntrega(
          entrega: {
            'empresa_id': auth.empresaId,
            'pedido_id': _pedidoId,
            'estado_bal_on_vacio': datos.balonVacio.db,
            'estado_pago': datos.montoCobrado + 0.009 >= _total ? 'PAGADO' : 'PENDIENTE',
            'registrado_por': auth.usuarioId,
          },
          pago: datos.montoCobrado > 0
              ? {
                  'empresa_id': auth.empresaId,
                  'pedido_id': _pedidoId,
                  'cliente_id': widget.pedido['cliente_id'],
                  'monto': datos.montoCobrado,
                  'metodo': datos.metodo,
                  'registrado_por': auth.usuarioId,
                }
              : null,
          movimientoBalon: _cantidadBalones > 0
              ? {
                  'empresa_id': auth.empresaId,
                  'cliente_id': widget.pedido['cliente_id'],
                  'tipo': 'ENTREGA_LLENO',
                  'pedido_id': _pedidoId,
                  'cantidad': _cantidadBalones,
                  'usuario_id': auth.usuarioId,
                }
              : null,
        );
        if (!mounted) return;
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sin conexión: la entrega quedó guardada y se enviará sola.'),
          ),
        );
        return;
      }
      if (!mounted) return;
      setState(() => _trabajando = false);
      _error(e is Exception ? e.toString().replaceFirst('Exception: ', '') : 'No se pudo entregar.');
    }
  }

  String _mensajeEntrega(datos, double total) {
    if (datos.montoCobrado <= 0.009) return 'Entregado. Quedó una deuda de ${dinero(total)}.';
    if (datos.montoCobrado + 0.009 < total) {
      return 'Entregado. Cobraste ${dinero(datos.montoCobrado)}, debe ${dinero(total - datos.montoCobrado)}.';
    }
    return 'Entregado. Cobraste ${dinero(datos.montoCobrado)}.';
  }

  Future<void> _cancelar() async {
    final motivo = await _pedirMotivo('Cancelar pedido', '¿Por qué se cancela?');
    if (motivo == null) return;
    final auth = ref.read(authProvider);
    try {
      await pedidosRepo.cancelar(
        pedidoId: _pedidoId,
        empresaId: auth.empresaId!,
        usuarioId: auth.usuarioId!,
        motivo: motivo,
      );
      widget.pedido['estado'] = 'CANCELADO';
      if (!mounted) return;
      Navigator.of(context).pop(true);
      _mensaje('Pedido cancelado.');
    } catch (e) {
      _error(e is Exception ? e.toString().replaceFirst('Exception: ', '') : 'No se pudo cancelar.');
    }
  }

  Future<void> _reabrir() async {
    final motivo = await _pedirMotivo('Reabrir pedido', 'Motivo (opcional)');
    if (motivo == null) return;
    final auth = ref.read(authProvider);
    try {
      await pedidosRepo.reactivar(
        pedidoId: _pedidoId,
        empresaId: auth.empresaId!,
        usuarioId: auth.usuarioId!,
      );
      widget.pedido['estado'] = 'NUEVO';
      await _cargar();
      _mensaje('Pedido reactivado.');
    } catch (e) {
      _error(e is Exception ? e.toString().replaceFirst('Exception: ', '') : 'No se pudo reabrir.');
    }
  }

  Future<String?> _pedirMotivo(String titulo, String etiqueta) async {
    final ctrl = TextEditingController();
    final resultado = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 2,
          decoration: InputDecoration(labelText: etiqueta),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return resultado;
  }

  void _mensaje(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _error(String msg) => _mensaje(msg);

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final p = widget.pedido;
    final cliente = p['clientes'] as Map<String, dynamic>?;
    final estado = _estado;

    final esMio = p['repartidor_id'] == auth.usuarioId;
    final soyMotorizado = auth.esMotorizado;
    final puedeOperar = soyMotorizado ? esMio : auth.esAdmin;
    final direccion = cliente?['direccion'] as String? ?? '';
    final referencia = cliente?['referencia'] as String? ?? '';
    final lat = (cliente?['latitud'] as num?)?.toDouble();
    final lng = (cliente?['longitud'] as num?)?.toDouble();

    return Scaffold(
      appBar: AppBar(title: Text('Pedido #${p['numero']}')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                // ---- Cliente ----
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                              child: Text(
                                (cliente?['nombre'] as String? ?? '?')[0].toUpperCase(),
                                style: const TextStyle(color: AppTheme.primary),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    cliente?['nombre'] as String? ?? 'Cliente',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold, fontSize: 17),
                                  ),
                                  if (_motorizadoNombre != null)
                                    Text('🛵 $_motorizadoNombre',
                                        style: const TextStyle(
                                            color: Colors.black54, fontSize: 13)),
                                ],
                              ),
                            ),
                            EstadoBadge(estado.db),
                          ],
                        ),
                        if (direccion.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.place_outlined, size: 18, color: AppTheme.info),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(direccion,
                                    style: const TextStyle(fontSize: 15, height: 1.3)),
                              ),
                            ],
                          ),
                        ],
                        if (referencia.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 24, top: 2),
                            child: Text('Referencia: $referencia',
                                style: const TextStyle(color: Colors.black54, fontSize: 13)),
                          ),
                        if (lat == null || lng == null)
                          const Padding(
                            padding: EdgeInsets.only(left: 24, top: 4),
                            child: Text('Sin coordenadas: la ruta usará la dirección.',
                                style: TextStyle(color: Colors.black45, fontSize: 12)),
                          ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: (cliente?['telefono'] as String? ?? '').isEmpty
                                    ? null
                                    : () => llamar(cliente?['telefono'] as String?),
                                icon: const Icon(Icons.call_outlined),
                                label: const Text('Llamar'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: (lat == null || lng == null) && direccion.isEmpty
                                    ? null
                                    : () => abrirMapaCliente(
                                          latitud: lat ?? 0,
                                          longitud: lng ?? 0,
                                        ),
                                icon: const Icon(Icons.map_outlined),
                                label: const Text('Ver mapa'),
                              ),
                            ),
                          ],
                        ),
                        if (lat != null && lng != null) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => navegarACliente(
                                latitud: lat,
                                longitud: lng,
                                direccion: direccion,
                              ),
                              icon: const Icon(Icons.directions_outlined),
                              label: const Text('Ir al cliente'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(50),
                                backgroundColor: AppTheme.info,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ---- Qué entregar y cuánto cobrar ----
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final d in _detalles)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                const Icon(Icons.local_fire_department_outlined,
                                    size: 18, color: AppTheme.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${d['cantidad']} × ${_nombreProducto(d)}',
                                    style: const TextStyle(fontWeight: FontWeight.w500),
                                  ),
                                ),
                                Text(dinero((d['cantidad'] as num? ?? 0) *
                                        (d['precio_unitario'] as num? ?? 0)),
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        if (_detalles.isEmpty)
                          const Text('Sin productos registrados.',
                              style: TextStyle(color: Colors.black54)),
                        const Divider(height: 22),
                        FilaValor(
                          'Cobrar',
                          dinero(_total),
                          destacado: true,
                        ),
                        if (_entrega != null) ...[
                          FilaValor(
                            'Cobrado',
                            dinero(_cobrado),
                            color: AppTheme.success,
                          ),
                          if (_deuda > 0)
                            FilaValor('Debe', dinero(_deuda), color: AppTheme.danger),
                          FilaValor(
                            'Pago',
                            _pagos.isEmpty
                                ? 'Pendiente'
                                : metodoPago(_pagos.first['metodo'] as String?),
                          ),
                          FilaValor(
                            'Balón vacío',
                            labelEstadoBalon(_entrega!['estado_bal_on_vacio'] as String?),
                            color: _entrega!['estado_bal_on_vacio'] == 'NO_RECIBIDO'
                                ? AppTheme.warning
                                : null,
                          ),
                        ] else if (p['forma_pago'] != null) ...[
                          FilaValor('Pago esperado', metodoPago(p['forma_pago'] as String)),
                        ],
                        if ((p['observaciones'] as String? ?? '').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text('Nota: ${p['observaciones']}',
                                style: const TextStyle(
                                    color: Colors.black54, fontStyle: FontStyle.italic)),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ---- Acciones ----
                if (puedeOperar && !estado.esFinalizado) ...[
                  if (estado == EstadoPedido.nuevo && auth.esAdmin) ...[
                    FilledButton.icon(
                      onPressed: _tomarPedido,
                      icon: const Icon(Icons.pan_tool_alt_outlined),
                      label: const Text('Tomar el pedido'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        backgroundColor: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _asignarMotorizado,
                      icon: const Icon(Icons.delivery_dining_outlined),
                      label: const Text('Asignar motorizado'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (estado == EstadoPedido.asignado) ...[
                    OutlinedButton.icon(
                      onPressed: _iniciarRuta,
                      icon: const Icon(Icons.route_outlined),
                      label: const Text('Iniciar ruta'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (estado == EstadoPedido.asignado || estado == EstadoPedido.enCamino) ...[
                    FilledButton.icon(
                      onPressed: _trabajando ? null : _entregar,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Entregar pedido'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        backgroundColor: AppTheme.success,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
                if (auth.esAdmin && !estado.esFinalizado) ...[
                  OutlinedButton.icon(
                    onPressed: _cancelar,
                    icon: const Icon(Icons.cancel_outlined, color: AppTheme.danger),
                    label: const Text('Cancelar pedido',
                        style: TextStyle(color: AppTheme.danger)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      side: const BorderSide(color: AppTheme.danger),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (auth.esAdmin && estado.esFinalizado) ...[
                  OutlinedButton.icon(
                    onPressed: _reabrir,
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Reabrir pedido'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  ),
                  const SizedBox(height: 10),
                ],
                if (estado.esFinalizado)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      estado == EstadoPedido.entregado
                          ? 'Este pedido ya fue entregado.'
                          : 'Este pedido está ${estado.label.toLowerCase()}.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ),
              ],
            ),
    );
  }

  String _nombreProducto(Map<String, dynamic> d) {
    final producto = d['productos'] as Map<String, dynamic>?;
    final nombre = producto?['nombre'] as String? ?? 'Producto';
    final kg = producto?['capacidad_kg'];
    return kg == null ? nombre : '$nombre (${kg}kg)';
  }
}
