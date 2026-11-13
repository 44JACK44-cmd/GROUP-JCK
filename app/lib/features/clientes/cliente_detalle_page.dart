import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import 'cliente_form_page.dart';

/// Ficha del cliente: datos de contacto, ubicación, deuda estimada,
/// balones en su poder y últimos pedidos.
class ClienteDetallePage extends StatefulWidget {
  final Map<String, dynamic> cliente;

  const ClienteDetallePage({super.key, required this.cliente});

  @override
  State<ClienteDetallePage> createState() => _ClienteDetallePageState();
}

class _ClienteDetallePageState extends State<ClienteDetallePage> {
  bool _cargando = true;
  double _deuda = 0;
  int _balones = 0;
  List<Map<String, dynamic>> _pedidos = [];

  SupabaseClient get _sb => Supabase.instance.client;

  String get _clienteId => widget.cliente['id'] as String;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final resultados = await Future.wait([
        // Pedidos con su estado de pago en la entrega
        _sb.from('pedidos')
            .select('id, numero, fecha, total, estado, entregas(estado_pago)')
            .eq('cliente_id', _clienteId)
            .order('fecha', ascending: false)
            .limit(10),
        // Todos los pedidos entregados-pendientes para la deuda
        _sb.from('pedidos')
            .select('id, total, estado, entregas(estado_pago)')
            .eq('cliente_id', _clienteId)
            .eq('estado', 'ENTREGADO'),
        _sb.from('pagos').select('monto').eq('cliente_id', _clienteId),
        _sb.from('movimiento_bal_on').select('tipo, cantidad').eq('cliente_id', _clienteId),
      ]);

      if (!mounted) return;

      final pedidosRecientes = List<Map<String, dynamic>>.from(resultados[0] as List);
      final pedidosEntregados = List<Map<String, dynamic>>.from(resultados[1] as List);
      final pagos = List<Map<String, dynamic>>.from(resultados[2] as List);
      final movimientos = List<Map<String, dynamic>>.from(resultados[3] as List);

      // Deuda = entregas pendientes de pago − abonos registrados
      double pendiente = 0;
      for (final p in pedidosEntregados) {
        if (_entregaPendiente(p)) pendiente += (p['total'] as num? ?? 0).toDouble();
      }
      double abonado = 0;
      for (final p in pagos) {
        abonado += (p['monto'] as num? ?? 0).toDouble();
      }
      final deuda = (pendiente - abonado) < 0 ? 0.0 : pendiente - abonado;

      var balones = 0;
      for (final m in movimientos) {
        final cant = (m['cantidad'] as num? ?? 0).toInt();
        balones += m['tipo'] == 'ENTREGA_LLENO' ? cant : -cant;
      }

      setState(() {
        _pedidos = pedidosRecientes;
        _deuda = deuda;
        _balones = balones;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos cargar la ficha. Revisa tu conexión.')),
      );
    }
  }

  bool _entregaPendiente(Map<String, dynamic> pedido) {
    final e = pedido['entregas'];
    if (e is List) {
      return e.any((x) => x['estado_pago'] == 'PENDIENTE');
    }
    if (e is Map) return e['estado_pago'] == 'PENDIENTE';
    return false;
  }

  Future<void> _editar() async {
    final cambio = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ClienteFormPage(cliente: widget.cliente)),
    );
    if (cambio == true && mounted) _cargar();
  }

  Future<void> _llamar() async {
    final tel = widget.cliente['telefono'] as String?;
    if (tel == null || tel.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: tel.replaceAll(' ', ''));
    await launchUrl(uri);
  }

  Future<void> _comoLlegar() async {
    final lat = widget.cliente['latitud'];
    final lng = widget.cliente['longitud'];
    final dir = widget.cliente['direccion'] as String?;
    String destino;
    if (lat != null && lng != null) {
      destino = '$lat,$lng';
    } else if (dir != null && dir.isNotEmpty) {
      destino = Uri.encodeComponent(dir);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este cliente no tiene ubicación registrada.')),
      );
      return;
    }
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$destino');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cliente;
    final tieneTel = (c['telefono'] as String? ?? '').isNotEmpty;
    final tieneUbicacion = c['latitud'] != null && c['longitud'] != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cliente'),
        actions: [
          IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined), onPressed: _editar),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Datos principales
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  c['nombre'] as String? ?? '',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ),
                              _ChipTipo(c['tipo'] as String? ?? 'PARTICULAR'),
                            ],
                          ),
                          if (tieneTel) ...[
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: _llamar,
                              child: Row(
                                children: [
                                  const Icon(Icons.phone_outlined, size: 18, color: AppTheme.primary),
                                  const SizedBox(width: 6),
                                  Text(c['telefono'] as String,
                                      style: const TextStyle(color: AppTheme.primary)),
                                ],
                              ),
                            ),
                          ],
                          if ((c['direccion'] as String? ?? '').isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.place_outlined, size: 18, color: Colors.black45),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(c['direccion'] as String,
                                      style: const TextStyle(color: Colors.black87)),
                                ),
                              ],
                            ),
                          ],
                          if ((c['referencia'] as String? ?? '').isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('Ref: ${c['referencia']}',
                                style: const TextStyle(color: Colors.black54, fontSize: 13)),
                          ],
                          if ((c['observaciones'] as String? ?? '').isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(c['observaciones'] as String,
                                style: const TextStyle(color: Colors.black54, fontSize: 13)),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: tieneTel ? _llamar : null,
                                  icon: const Icon(Icons.call_outlined),
                                  label: const Text('Llamar'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _comoLlegar,
                                  icon: const Icon(Icons.directions_outlined),
                                  label: const Text('Cómo llegar'),
                                ),
                              ),
                            ],
                          ),
                          if (!tieneUbicacion)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'Sin ubicación exacta: la ruta usará la dirección escrita.',
                                style: TextStyle(color: Colors.black45, fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Deuda y balones
                  Row(
                    children: [
                      Expanded(child: _TarjetaValor(
                        titulo: 'Saldo pendiente',
                        valor: 'S/ ${_deuda.toStringAsFixed(2)}',
                        color: _deuda > 0 ? AppTheme.danger : AppTheme.success,
                        icono: Icons.account_balance_wallet_outlined,
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: _TarjetaValor(
                        titulo: 'Balones con él',
                        valor: '$_balones',
                        color: _balones > 0 ? AppTheme.warning : Colors.black54,
                        icono: Icons.local_fire_department_outlined,
                      )),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Historial
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Últimos pedidos',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          if (_pedidos.isEmpty)
                            const Text('Sin pedidos registrados.',
                                style: TextStyle(color: Colors.black54))
                          else
                            for (final p in _pedidos) _FilaPedido(p),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _labels[tipo] ?? tipo,
        style: const TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _TarjetaValor extends StatelessWidget {
  final String titulo;
  final String valor;
  final Color color;
  final IconData icono;

  const _TarjetaValor({
    required this.titulo,
    required this.valor,
    required this.color,
    required this.icono,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icono, color: color, size: 22),
            const SizedBox(height: 6),
            Text(titulo, style: const TextStyle(color: Colors.black54, fontSize: 12)),
            Text(valor, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _FilaPedido extends StatelessWidget {
  final Map<String, dynamic> pedido;
  const _FilaPedido(this.pedido);

  static const _estados = {
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
    final estado = pedido['estado'] as String? ?? '';
    final fecha = DateTime.tryParse(pedido['fecha'] as String? ?? '');
    final color = _colores[estado] ?? Colors.black54;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pedido #${pedido['numero']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  fecha == null ? '' : '${fecha.day}/${fecha.month}/${fecha.year}',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
          Text('S/ ${(pedido['total'] as num? ?? 0).toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(_estados[estado] ?? estado,
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
