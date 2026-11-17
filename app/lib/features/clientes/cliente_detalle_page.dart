/// Ficha del cliente: el centro de información del pedido.
///
/// Muestra contacto, ubicación, precio habitual, deuda, balones pendientes,
/// total de pedidos y el último pedido. Con acciones directas.
library;

import 'package:gas_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/data/clientes_repo.dart';
import '../../core/data/pago_con_comprobante.dart';
import '../../core/data/productos_repo.dart';
import '../../core/data/sb.dart';
import '../../core/domain/estado_pedido.dart';
import '../../core/domain/formato.dart';
import '../../core/domain/navegacion.dart';
import '../../core/ui/widgets.dart';
import '../auth/auth_controller.dart';
import '../pagos/pago_sheet.dart';
import '../pedidos/nuevo_pedido_page.dart';
import 'cliente_form_page.dart';

class ClienteDetallePage extends ConsumerStatefulWidget {
  final Map<String, dynamic> cliente;

  ClienteDetallePage({super.key, required this.cliente});

  @override
  ConsumerState<ClienteDetallePage> createState() => _ClienteDetallePageState();
}

class _ClienteDetallePageState extends ConsumerState<ClienteDetallePage> {
  bool _cargando = true;
  double _deuda = 0;
  int _balonesPendientes = 0;
  int _fierrosPendientes = 0;
  int _totalPedidos = 0;
  double _precioHabitual = 0;
  List<Map<String, dynamic>> _pedidos = [];

  String get _clienteId => widget.cliente['id'] as String;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final res = await Future.wait([
        clientesRepo.resumenDe(_clienteId),
        clientesRepo.totalPedidos(_clienteId),
        clientesRepo.ultimosPedidos(_clienteId, limite: 10),
        _cargarPrecioHabitual(),
      ]);
      if (!mounted) return;
      final resumen = res[0] as ResumenCliente;
      setState(() {
        _deuda = resumen.deuda;
        _balonesPendientes = resumen.balonesPendientes;
        _fierrosPendientes = resumen.fierrosPendientes;
        _totalPedidos = res[1] as int;
        _pedidos = res[2] as List<Map<String, dynamic>>;
        _precioHabitual = res[3] as double;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(traducirError(e, contexto: 'No pudimos cargar la ficha').mensaje)),
      );
    }
  }

  /// Precio que este cliente paga habitualmente (precio especial o base).
  Future<double> _cargarPrecioHabitual() async {
    try {
      final especiales = await clientesRepo.preciosDe(_clienteId);
      if (especiales.isNotEmpty) {
        return especiales.values.reduce((a, b) => a > b ? a : b);
      }
      final productos = await ProductosRepo().vendibles();
      if (productos.isEmpty) return 0;
      return (productos.first['precio_base'] as num? ?? 0).toDouble();
    } catch (_) {
      return 0;
    }
  }

  Future<void> _editar() async {
    final cambio = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ClienteFormPage(cliente: widget.cliente)),
    );
    if (cambio == true && mounted) _cargar();
  }

  Future<void> _nuevoPedido() async {
    final creado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => NuevoPedidoPage(clienteInicial: widget.cliente)),
    );
    if (creado == true && mounted) _cargar();
  }

  Future<void> _registrarPago() async {
    final resultado = await mostrarHojaPago(
      context,
      clienteNombre: widget.cliente['nombre'] as String? ?? 'cliente',
      suggestedMonto: _deuda > 0 ? _deuda : 0,
    );
    if (resultado == null) return;

    final auth = ref.read(authProvider);
    try {
      final offline = await pagoConComprobante.registrar(
        empresaId: auth.empresaId!,
        usuarioId: auth.usuarioId!,
        clienteId: _clienteId,
        monto: resultado['monto'] as double,
        metodo: resultado['metodo'] as String,
        fotoPath: resultado['fotoPath'] as String?,
      );
      _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(offline
              ? 'Guardado en el dispositivo. La foto se subirá sola.'
              : 'Pago registrado.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(traducirError(e, contexto: 'No pudimos registrar el pago').mensaje)),
      );
    }
  }

  Future<void> _verHistorial() async {
    final data = await clientesRepo.ultimosPedidos(_clienteId, limite: 50);
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, controller) => ListView(
          controller: controller,
          padding: EdgeInsets.all(16),
          children: [
            Text('Pedidos de ${widget.cliente['nombre']}',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            if (data.isEmpty)
              Text('Sin pedidos registrados.',
                  style: TextStyle(color: AppColors.textoSecundario)),
            for (final p in data)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  EstadoPedido.desdeDb(p['estado']).icono,
                  color: EstadoPedido.desdeDb(p['estado']).color,
                ),
                title: Text('#${p['numero']} · ${dinero((p['total'] as num? ?? 0))}'),
                subtitle: Text(fechaCorta(parseFecha(p['fecha'] as String?))),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cliente;
    final tel = c['telefono'] as String? ?? '';
    final direccion = c['direccion'] as String? ?? '';
    final referencia = c['referencia'] as String? ?? '';
    final lat = (c['latitud'] as num?)?.toDouble();
    final lng = (c['longitud'] as num?)?.toDouble();
    final ultimo = _pedidos.isEmpty ? null : _pedidos.first;

    return Scaffold(
      appBar: AppBar(
        title: Text('Cliente'),
        actions: [
          IconButton(tooltip: 'Editar', icon: Icon(Icons.edit_outlined), onPressed: _editar),
        ],
      ),
      body: _cargando
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  // ---- Datos ----
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  c['nombre'] as String? ?? '',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ),
                              _ChipTipo(c['tipo'] as String? ?? 'PARTICULAR'),
                            ],
                          ),
                          if (tel.isNotEmpty) ...[
                            SizedBox(height: 8),
                            InkWell(
                              onTap: () => llamar(tel),
                              child: Row(
                                children: [
                                  Icon(Icons.phone_outlined, size: 18, color: AppTheme.primary),
                                  SizedBox(width: 6),
                                  Text(tel, style: TextStyle(color: AppTheme.primary)),
                                ],
                              ),
                            ),
                          ],
                          if (direccion.isNotEmpty) ...[
                            SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.place_outlined, size: 18, color: AppColors.textoMuted),
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
                          if ((c['observaciones'] as String? ?? '').isNotEmpty)
                            Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Text(c['observaciones'] as String,
                                  style: TextStyle(color: AppColors.textoSecundario, fontSize: 13)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 12),

                  // ---- Números ----
                  Row(
                    children: [
                      Expanded(
                        child: TarjetaMetrica(
                          titulo: 'Deuda',
                          valor: dinero(_deuda, conDecimales: false),
                          icono: Icons.account_balance_wallet_outlined,
                          color: _deuda > 0 ? AppTheme.danger : AppTheme.success,
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: TarjetaMetrica(
                          titulo: 'Balones pendientes',
                          valor: '$_balonesPendientes',
                          icono: Icons.local_fire_department_outlined,
                          color: _balonesPendientes > 0 ? AppTheme.warning : AppColors.textoSecundario,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        children: [
                          FilaValor(
                            'Precio habitual',
                            _precioHabitual > 0 ? dinero(_precioHabitual) : 'Sin definir',
                          ),
                          FilaValor('Pedidos realizados', '$_totalPedidos'),
                          FilaValor(
                            'Último pedido',
                            ultimo == null
                                ? 'Sin pedidos'
                                : fechaCorta(parseFecha(ultimo['fecha'] as String?)),
                          ),
                          if (_fierrosPendientes > 0)
                            FilaValor('Fierros pendientes', '$_fierrosPendientes',
                                color: AppTheme.warning),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 16),

                  // ---- Acciones ----
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _nuevoPedido,
                      icon: Icon(Icons.add_circle_outline),
                      label: Text('NUEVO PEDIDO'),
                      style: FilledButton.styleFrom(
                        minimumSize: Size.fromHeight(52),
                        backgroundColor: AppTheme.primary,
                      ),
                    ),
                  ),
                  SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: (lat == null || lng == null) && direccion.isEmpty
                              ? null
                              : () => (lat != null && lng != null)
                                  ? abrirMapaCliente(latitud: lat, longitud: lng)
                                  : abrirMapaPorDireccion(direccion),
                          icon: Icon(Icons.map_outlined),
                          label: Text('Ver ubicación'),
                          style: OutlinedButton.styleFrom(minimumSize: Size.fromHeight(48)),
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _verHistorial,
                          icon: Icon(Icons.history_outlined),
                          label: Text('Historial'),
                          style: OutlinedButton.styleFrom(minimumSize: Size.fromHeight(48)),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _registrarPago,
                      icon: Icon(Icons.payments_outlined),
                      label: Text('Registrar pago'),
                      style: OutlinedButton.styleFrom(minimumSize: Size.fromHeight(48)),
                    ),
                  ),
                  SizedBox(height: 20),

                  // ---- Últimos pedidos ----
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Últimos pedidos', style: Theme.of(context).textTheme.titleMedium),
                          SizedBox(height: 8),
                          if (_pedidos.isEmpty)
                            Text('Sin pedidos registrados.',
                                style: TextStyle(color: AppColors.textoSecundario))
                          else
                            for (final p in _pedidos) _FilaPedido(p),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ChipTipo extends StatelessWidget {
  final String tipo;
  const _ChipTipo(this.tipo);

  static const _labels = {
    'PARTICULAR': 'Particular',
    'RESTAURANTE': 'Restaurante',
    'NEGOCIO': 'Negocio',
    'OTRO': 'Otro',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _labels[tipo] ?? tipo,
        style: TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _FilaPedido extends StatelessWidget {
  final Map<String, dynamic> pedido;
  const _FilaPedido(this.pedido);

  @override
  Widget build(BuildContext context) {
    final estado = EstadoPedido.desdeDb(pedido['estado']);
    final fecha = parseFecha(pedido['fecha'] as String?);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(estado.icono, size: 18, color: estado.color),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pedido #${pedido['numero']}',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  fecha == null ? '' : fechaCorta(fecha),
                  style: TextStyle(color: AppColors.textoSecundario, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(dinero((pedido['total'] as num? ?? 0)),
              style: TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}