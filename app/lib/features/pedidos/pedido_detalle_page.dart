/// Detalle de un pedido.
///
/// Muestra solo lo necesario para atender la entrega y, según el rol,
/// las acciones: asignar, tomar, iniciar ruta, entregar, cancelar.
library;

import 'package:gas_app/core/theme/app_colors.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import '../../core/data/entregas_repo.dart';
import '../../core/data/motorizados_repo.dart';
import '../../core/data/pedidos_repo.dart';
import '../../core/data/sb.dart';
import '../../core/domain/estado_pedido.dart';
import '../../core/domain/formato.dart';
import '../../core/domain/navegacion.dart';
import '../../core/ui/app_bar_volver.dart';
import '../../core/ui/estado_stepper.dart';
import '../../core/ui/widgets.dart';
import '../auth/auth_controller.dart';
import 'flujo_entrega.dart';

class PedidoDetallePage extends ConsumerStatefulWidget {
  final Map<String, dynamic> pedido;

  PedidoDetallePage({super.key, required this.pedido});

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
  bool _huboCambios = false;

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

  /// Comparte la foto del comprobante (WhatsApp u otra app instalada).
  /// Si no se puede descargar, se comparte el enlace como respaldo.
  Future<void> _compartirComprobante(String url) async {
    try {
      final respuesta = await http.get(Uri.parse(url)).timeout(Duration(seconds: 20));
      if (respuesta.statusCode != 200) throw Exception('No se pudo descargar');
      final dir = await getTemporaryDirectory();
      final archivo = File('${dir.path}/comprobante-yape-${DateTime.now().millisecondsSinceEpoch}.jpg');
      await archivo.writeAsBytes(respuesta.bodyBytes);
      await Share.shareXFiles(
        [XFile(archivo.path, mimeType: 'image/jpeg')],
        text: 'Comprobante de Yape del pedido',
      );
    } catch (_) {
      await Share.share('Comprobante de Yape: $url');
    }
  }

  /// Muestra el comprobante de Yape guardado en Supabase Storage.
  void _verComprobante(String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Padding(
                    padding: EdgeInsets.all(30),
                    child: Text('No se pudo cargar el comprobante.'),
                  ),
                ),
              ),
              SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () => _compartirComprobante(url),
                icon: Icon(Icons.share_outlined),
                label: Text('Compartir foto'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('Cerrar'),
              ),
            ],
          ),
        ),
      ),
    );
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
            Padding(
              padding: EdgeInsets.all(16),
              child: Text('¿A quién se lo asignas?',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ),
            for (final m in motorizados)
              ListTile(
                leading: Icon(Icons.delivery_dining_outlined),
                title: Text(m['nombre'] as String? ?? ''),
                subtitle: Text(m['telefono'] as String? ?? ''),
                onTap: () => Navigator.of(ctx).pop(m),
              ),
          ],
        ),
      ),
    );
    if (elegido == null) return;

    // Aviso no bloqueante: si no suele trabajar hoy, ADMIN puede asignar igual.
    try {
      final dias = await motorizadosRepo.diasTrabajo(elegido['id'] as String);
      if (!motorizadosRepo.trabajaHoy(dias, DateTime.now().weekday) && mounted) {
        final continuar = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('No suele trabajar hoy'),
            content: Text(
              '${elegido['nombre'] ?? 'Este motorizado'} normalmente no trabaja '
              'este día. ¿Quieres asignar el pedido excepcionalmente?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text('Asignar igual'),
              ),
            ],
          ),
        );
        if (continuar != true) return;
      }
    } catch (_) {
      // Sin información de días se permite la asignación normal.
    }

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
      _huboCambios = true;
      setState(() => _motorizadoNombre = elegido['nombre'] as String?);
      _mensaje('Pedido asignado a ${elegido['nombre']}.');
    } catch (e) {
      _error(e is Exception ? e.toString().replaceFirst('Exception: ', '') : 'No se pudo asignar.');
    }
  }

  Future<void> _tomarPedido() async {
    final auth = ref.read(authProvider);
    try {
      await pedidosRepo.tomarPedido(
        pedidoId: _pedidoId,
        nombreRepartidor: auth.nombre,
      );
      widget.pedido['repartidor_id'] = auth.usuarioId;
      widget.pedido['estado'] = 'ASIGNADO';
      _huboCambios = true;
      setState(() => _motorizadoNombre = auth.nombre);
      _mensaje('Tomaste el pedido.');
    } catch (e) {
      _error(e is Exception ? e.toString().replaceFirst('Exception: ', '') : 'No se pudo tomar.');
    }
  }

  Future<void> _liberar() async {
    final auth = ref.read(authProvider);
    try {
      await pedidosRepo.liberar(
        pedidoId: _pedidoId,
        empresaId: auth.empresaId!,
        usuarioId: auth.usuarioId!,
      );
      widget.pedido['repartidor_id'] = null;
      widget.pedido['estado'] = 'NUEVO';
      _huboCambios = true;
      setState(() => _motorizadoNombre = null);
      _mensaje('Pedido liberado: cualquier motorizado puede tomarlo.');
    } catch (e) {
      _error(e is Exception ? e.toString().replaceFirst('Exception: ', '') : 'No se pudo liberar.');
    }
  }

  Future<void> _noEntregado() async {
    final motivo = await _pedirMotivo(
      'No se pudo entregar',
      'Motivo (cliente ausente, dirección errada, etc.)',
    );
    if (motivo == null) return;

    final auth = ref.read(authProvider);
    setState(() => _trabajando = true);
    try {
      await entregasRepo.registrarNoEntregado(
        empresaId: auth.empresaId!,
        usuarioId: auth.usuarioId!,
        pedidoId: _pedidoId,
        motivo: motivo,
      );
      widget.pedido['estado'] = 'NO_ENTREGADO';
      _huboCambios = true;
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pedido marcado como no entregado.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _trabajando = false);
      _error(e is Exception
          ? e.toString().replaceFirst('Exception: ', '')
          : 'No se pudo actualizar el pedido.');
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
      _huboCambios = true;
      setState(() {});
      _mensaje('Pedido en camino.');
      await _abrirRuta();
    } catch (e) {
      _error(e is Exception ? e.toString().replaceFirst('Exception: ', '') : 'No se pudo actualizar.');
    }
  }

  /// "Ir al cliente": abre Google Maps con la ubicación GUARDADA DEL CLIENTE
  /// como destino. Nunca se usa la ubicación actual del motorizado como meta.
  Future<void> _abrirRuta() async {
    final cliente = widget.pedido['clientes'] as Map<String, dynamic>?;
    final lat = (cliente?['latitud'] as num?)?.toDouble();
    final lng = (cliente?['longitud'] as num?)?.toDouble();
    final direccion = cliente?['direccion'] as String? ?? '';

    final abierto = await navegarACliente(
      latitud: lat,
      longitud: lng,
      direccion: direccion.isEmpty ? null : direccion,
    );
    if (!abierto && mounted) {
      _error('No se pudo abrir Google Maps. Revisa que esté instalado y que el '
          'cliente tenga una dirección o ubicación guardada.');
    }
  }

  Future<void> _entregar() async {
    final ok = await ejecutarEntrega(
      context,
      ref,
      widget.pedido,
      total: _total,
      cantidadBalones: _cantidadBalones,
    );
    if (!ok || !mounted) return;
    _huboCambios = true;
    await _cargar();
    if (mounted) Navigator.of(context).pop(true);
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
      _huboCambios = true;
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
      _huboCambios = true;
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text('Guardar'),
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // Al volver, la lista se refresca si algo cambió en este pedido.
        Navigator.of(context).pop(_huboCambios);
      },
      child: Scaffold(
        appBar: AppBarVolver(titulo: 'Pedido #${p['numero']}'),
        body: _cargando
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : ListView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                // ---- Cliente ----
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                              child: Text(
                                (cliente?['nombre'] as String? ?? '?')[0].toUpperCase(),
                                style: TextStyle(color: AppTheme.primary),
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    cliente?['nombre'] as String? ?? 'Cliente',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold, fontSize: 17),
                                  ),
                                  if (_motorizadoNombre != null)
                                    Text(_motorizadoNombre ?? '',
                                        style: TextStyle(
                                            color: AppColors.textoSecundario, fontSize: 13)),
                                ],
                              ),
                            ),
                            EstadoBadge(estado.db),
                          ],
                        ),
                        if (direccion.isNotEmpty) ...[
                          SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.place_outlined, size: 18, color: AppTheme.info),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(direccion,
                                    style: TextStyle(fontSize: 15, height: 1.3)),
                              ),
                            ],
                          ),
                        ],
                        if (referencia.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(left: 24, top: 2),
                            child: Text('Referencia: $referencia',
                                style: TextStyle(color: AppColors.textoSecundario, fontSize: 13)),
                          ),
                        if (lat == null || lng == null)
                          Padding(
                            padding: EdgeInsets.only(left: 24, top: 4),
                            child: Text('Sin coordenadas: la ruta usará la dirección.',
                                style: TextStyle(color: AppColors.textoMuted, fontSize: 12)),
                          ),
                        SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: (cliente?['telefono'] as String? ?? '').isEmpty
                                    ? null
                                    : () => llamar(cliente?['telefono'] as String?),
                                icon: Icon(Icons.call_outlined),
                                label: Text('Llamar'),
                              ),
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: (lat == null || lng == null) && direccion.isEmpty
                                    ? null
                                    : () => abrirMapaCliente(
                                          latitud: lat ?? 0,
                                          longitud: lng ?? 0,
                                        ),
                                icon: Icon(Icons.map_outlined),
                                label: Text('Ver mapa'),
                              ),
                            ),
                          ],
                        ),
                        if (lat != null || direccion.isNotEmpty) ...[
                          SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _abrirRuta,
                              icon: Icon(Icons.directions_outlined),
                              label: Text('Ir al cliente'),
                              style: FilledButton.styleFrom(
                                minimumSize: Size.fromHeight(50),
                                backgroundColor: AppTheme.info,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 12),

                // ---- Qué entregar y cuánto cobrar ----
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final d in _detalles)
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Icon(Icons.local_fire_department_outlined,
                                    size: 18, color: AppTheme.primary),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${d['cantidad']} × ${_nombreProducto(d)}',
                                    style: TextStyle(fontWeight: FontWeight.w500),
                                  ),
                                ),
                                Text(dinero((d['cantidad'] as num? ?? 0) *
                                        (d['precio_unitario'] as num? ?? 0)),
                                    style: TextStyle(fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        if (_detalles.isEmpty)
                          Text('Sin productos registrados.',
                              style: TextStyle(color: AppColors.textoSecundario)),
                        Divider(height: 22),
                        EstadoStepper(
                          estado: p['estado'] as String? ?? 'NUEVO',
                          pagado: _entrega?['estado_pago'] == 'PAGADO',
                        ),
                        Divider(height: 22),
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
                          for (final pago in _pagos)
                            if (pago['comprobante_url'] != null)
                              Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: OutlinedButton.icon(
                                  onPressed: () => _verComprobante(
                                    pago['comprobante_url'] as String,
                                  ),
                                  icon: Icon(Icons.receipt_long_outlined),
                                  label: Text('VER COMPROBANTE'),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: Size.fromHeight(42),
                                  ),
                                ),
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
                            padding: EdgeInsets.only(top: 8),
                            child: Text('Nota: ${p['observaciones']}',
                                style: TextStyle(
                                    color: AppColors.textoSecundario, fontStyle: FontStyle.italic)),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 20),

                // ---- Acciones ----
                // Motorizado: tomar un pedido libre.
                if (soyMotorizado &&
                    estado == EstadoPedido.nuevo &&
                    p['repartidor_id'] == null) ...[
                  FilledButton.icon(
                    onPressed: _tomarPedido,
                    icon: Icon(Icons.pan_tool_alt_outlined),
                    label: Text('Tomar el pedido'),
                    style: FilledButton.styleFrom(
                      minimumSize: Size.fromHeight(50),
                      backgroundColor: AppTheme.primary,
                    ),
                  ),
                  SizedBox(height: 10),
                ],
                // ADMIN: asignar o cambiar de motorizado, y liberar.
                if (auth.esAdmin &&
                    !estado.esFinalizado &&
                    (estado == EstadoPedido.nuevo || estado == EstadoPedido.asignado)) ...[
                  OutlinedButton.icon(
                    onPressed: _asignarMotorizado,
                    icon: Icon(Icons.delivery_dining_outlined),
                    label: Text(estado == EstadoPedido.asignado
                        ? 'Cambiar de motorizado'
                        : 'Asignar motorizado'),
                    style: OutlinedButton.styleFrom(minimumSize: Size.fromHeight(50)),
                  ),
                  SizedBox(height: 10),
                  if (estado == EstadoPedido.asignado)
                    OutlinedButton.icon(
                      onPressed: _liberar,
                      icon: Icon(Icons.person_off_outlined),
                      label: Text('Liberar pedido'),
                      style: OutlinedButton.styleFrom(minimumSize: Size.fromHeight(50)),
                    ),
                  if (estado == EstadoPedido.asignado) SizedBox(height: 10),
                ],
                if (puedeOperar && estado == EstadoPedido.asignado) ...[
                  OutlinedButton.icon(
                    onPressed: _iniciarRuta,
                    icon: Icon(Icons.route_outlined),
                    label: Text('Iniciar ruta'),
                    style: OutlinedButton.styleFrom(minimumSize: Size.fromHeight(50)),
                  ),
                  SizedBox(height: 10),
                ],
                if (puedeOperar &&
                    (estado == EstadoPedido.asignado || estado == EstadoPedido.enCamino)) ...[
                  FilledButton.icon(
                    onPressed: _trabajando ? null : _entregar,
                    icon: Icon(Icons.check_circle_outline),
                    label: Text('Entregar pedido'),
                    style: FilledButton.styleFrom(
                      minimumSize: Size.fromHeight(52),
                      backgroundColor: AppTheme.success,
                    ),
                  ),
                  SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _trabajando ? null : _noEntregado,
                    icon: Icon(Icons.report_gmailerrorred_outlined,
                        color: AppTheme.warning),
                    label: Text('No se pudo entregar',
                        style: TextStyle(color: AppTheme.warning)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: Size.fromHeight(50),
                      side: BorderSide(color: AppTheme.warning),
                    ),
                  ),
                  SizedBox(height: 10),
                ],
                if (auth.esAdmin && !estado.esFinalizado) ...[
                  OutlinedButton.icon(
                    onPressed: _cancelar,
                    icon: Icon(Icons.cancel_outlined, color: AppTheme.danger),
                    label: Text('Cancelar pedido',
                        style: TextStyle(color: AppTheme.danger)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: Size.fromHeight(50),
                      side: BorderSide(color: AppTheme.danger),
                    ),
                  ),
                  SizedBox(height: 10),
                ],
                if (auth.esAdmin && estado.esFinalizado) ...[
                  OutlinedButton.icon(
                    onPressed: _reabrir,
                    icon: Icon(Icons.restart_alt),
                    label: Text('Reabrir pedido'),
                    style: OutlinedButton.styleFrom(minimumSize: Size.fromHeight(50)),
                  ),
                  SizedBox(height: 10),
                ],
                if (estado.esFinalizado)
                  Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      estado == EstadoPedido.entregado
                          ? 'Este pedido ya fue entregado.'
                          : 'Este pedido está ${estado.label.toLowerCase()}.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textoSecundario),
                    ),
                  ),
              ],
            ),
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