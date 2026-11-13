import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../auth/auth_controller.dart';

/// Detalle de un pedido: cliente, productos, estado y acciones
/// según el rol (admin asigna/cancela; el reparto se gestiona en /reparto).
class PedidoDetallePage extends ConsumerStatefulWidget {
  final Map<String, dynamic> pedido;

  const PedidoDetallePage({super.key, required this.pedido});

  @override
  ConsumerState<PedidoDetallePage> createState() => _PedidoDetallePageState();
}

class _PedidoDetallePageState extends ConsumerState<PedidoDetallePage> {
  List<Map<String, dynamic>> _detalles = [];
  String? _repartidorNombre;
  bool _cargando = true;

  SupabaseClient get _sb => Supabase.instance.client;

  String get _pedidoId => widget.pedido['id'] as String;
  String get _estado => widget.pedido['estado'] as String? ?? 'NUEVO';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final futures = <Future<dynamic>>[
        _sb.from('detalle_pedido')
            .select('cantidad, precio_unitario, productos(nombre, capacidad_kg)')
            .eq('pedido_id', _pedidoId),
      ];
      final repartidorId = widget.pedido['repartidor_id'] as String?;
      if (repartidorId != null) {
        futures.add(
          _sb.from('perfiles').select('nombre').eq('id', repartidorId).maybeSingle(),
        );
      }
      final resultados = await Future.wait(futures);
      if (!mounted) return;
      final perfil = resultados.length > 1
          ? resultados[1] as Map<String, dynamic>?
          : null;
      setState(() {
        _detalles = List<Map<String, dynamic>>.from(resultados[0] as List);
        _repartidorNombre = perfil?['nombre'] as String?;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
    }
  }

  Future<void> _asignarMotorizado() async {
    List<Map<String, dynamic>> motorizados;
    try {
      final data = await _sb
          .from('perfiles')
          .select('id, nombre, telefono')
          .eq('rol', 'MOTORIZADO')
          .eq('activo', true)
          .order('nombre');
      motorizados = List<Map<String, dynamic>>.from(data);
    } catch (_) {
      _error('No pudimos cargar los motorizados.');
      return;
    }
    if (motorizados.isEmpty) {
      _error('No tienes motorizados registrados. Agrégalos desde el inicio.');
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

    try {
      await _sb.from('pedidos').update({
        'repartidor_id': elegido['id'],
        'estado': 'ASIGNADO',
      }).eq('id', _pedidoId);
      widget.pedido['repartidor_id'] = elegido['id'];
      widget.pedido['estado'] = 'ASIGNADO';
      setState(() => _repartidorNombre = elegido['nombre'] as String?);
      _error('Pedido asignado a ${elegido['nombre']}.');
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      _error('No se pudo asignar. Inténtalo de nuevo.');
    }
  }

  Future<void> _cancelar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar pedido'),
        content: const Text('¿Seguro que quieres cancelar este pedido?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await _sb.from('pedidos').update({'estado': 'CANCELADO'}).eq('id', _pedidoId);
      widget.pedido['estado'] = 'CANCELADO';
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      _error('No se pudo cancelar. Inténtalo de nuevo.');
    }
  }

  void _error(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _llamarCliente() async {
    final tel = (widget.pedido['clientes'] as Map?)?['telefono'] as String?;
    if (tel == null || tel.isEmpty) return;
    await launchUrl(Uri(scheme: 'tel', path: tel.replaceAll(' ', '')));
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final p = widget.pedido;
    final cliente = p['clientes'] as Map<String, dynamic>?;
    final estado = _estado;
    final puedeGestionar = auth.esAdmin && estado != 'ENTREGADO' && estado != 'CANCELADO';

    return Scaffold(
      appBar: AppBar(title: Text('Pedido #${p['numero']}')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Cliente
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                      child: Text(
                        (cliente?['nombre'] as String? ?? '?')[0].toUpperCase(),
                        style: const TextStyle(color: AppTheme.primary),
                      ),
                    ),
                    title: Text(cliente?['nombre'] as String? ?? 'Cliente',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text([
                      if (cliente?['telefono'] != null) cliente!['telefono'],
                      if (_repartidorNombre != null) '🛵 $_repartidorNombre',
                    ].join('  ·  ')),
                    trailing: (cliente?['telefono'] as String? ?? '').isNotEmpty
                        ? IconButton(
                            tooltip: 'Llamar',
                            icon: const Icon(Icons.call_outlined, color: AppTheme.primary),
                            onPressed: _llamarCliente,
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 12),

                // Estado y total
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Estado', style: TextStyle(color: Colors.black54)),
                              const SizedBox(height: 4),
                              _BadgeEstado(estado),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('Total', style: TextStyle(color: Colors.black54)),
                            Text('S/ ${(p['total'] as num? ?? 0).toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Productos
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Productos', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        for (final d in _detalles) _FilaDetalle(d),
                        const Divider(height: 20),
                        if ((p['forma_pago'] as String?) != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('Pago: ${_labelFormaPago(p['forma_pago'] as String)}',
                                style: const TextStyle(color: Colors.black54)),
                          ),
                        if ((p['observaciones'] as String? ?? '').isNotEmpty)
                          Text('Nota: ${p['observaciones']}',
                              style: const TextStyle(color: Colors.black54, fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Acciones
                if (puedeGestionar) ...[
                  if (estado == 'NUEVO')
                    FilledButton.icon(
                      onPressed: _asignarMotorizado,
                      icon: const Icon(Icons.delivery_dining_outlined),
                      label: const Text('Asignar motorizado'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        backgroundColor: AppTheme.primary,
                      ),
                    ),
                  if (estado == 'NUEVO') const SizedBox(height: 10),
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
                ],
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  String _labelFormaPago(String f) => switch (f) {
        'EFECTIVO' => 'Efectivo',
        'YAPE' => 'Yape',
        'PLIN' => 'Plin',
        'TRANSFERENCIA' => 'Transferencia',
        'OTRO' => 'Otro',
        _ => f,
      };
}

class _BadgeEstado extends StatelessWidget {
  final String estado;
  const _BadgeEstado(this.estado);

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
  Widget build(BuildContext context) {
    final color = _colores[estado] ?? Colors.black54;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(_labels[estado] ?? estado,
          style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _FilaDetalle extends StatelessWidget {
  final Map<String, dynamic> detalle;
  const _FilaDetalle(this.detalle);

  @override
  Widget build(BuildContext context) {
    final producto = detalle['productos'] as Map<String, dynamic>?;
    final nombre = producto?['nombre'] as String? ?? 'Producto';
    final kg = producto?['capacidad_kg'];
    final cantidad = detalle['cantidad'] as num? ?? 0;
    final precio = detalle['precio_unitario'] as num? ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              kg == null ? '$cantidad × $nombre' : '$cantidad × $nombre (${kg}kg)',
            ),
          ),
          Text('S/ ${(cantidad * precio).toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
