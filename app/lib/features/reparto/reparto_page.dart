import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import '../../core/offline/outbox.dart';
import '../auth/auth_controller.dart';

/// Pantalla del motorizado: sus pedidos asignados y en camino,
/// con acciones para iniciar ruta y registrar la entrega.
class RepartoPage extends ConsumerStatefulWidget {
  const RepartoPage({super.key});

  @override
  ConsumerState<RepartoPage> createState() => _RepartoPageState();
}

class _RepartoPageState extends ConsumerState<RepartoPage> {
  List<Map<String, dynamic>> _pendientes = [];
  List<Map<String, dynamic>> _entregados = [];
  bool _cargando = true;

  SupabaseClient get _sb => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _cargar();
    _sincronizar();
  }

  Future<void> _sincronizar() async {
    final n = await Outbox.procesar();
    if (n > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$n operación(es) pendiente(s) se enviaron.')),
      );
      _cargar();
    }
  }

  Future<void> _cargar() async {
    final uid = ref.read(authProvider).usuarioId;
    if (uid == null) return;
    try {
      final resultados = await Future.wait([
        _sb.from('pedidos')
            .select('id, numero, fecha, total, estado, cliente_id, clientes(nombre, telefono, direccion, latitud, longitud)')
            .eq('repartidor_id', uid)
            .inFilter('estado', ['ASIGNADO', 'EN_CAMINO'])
            .order('fecha'),
        _sb.from('pedidos')
            .select('id, numero, fecha, total, estado, clientes(nombre)')
            .eq('repartidor_id', uid)
            .eq('estado', 'ENTREGADO')
            .order('fecha', ascending: false)
            .limit(10),
      ]);
      if (!mounted) return;
      setState(() {
        _pendientes = List<Map<String, dynamic>>.from(resultados[0] as List);
        _entregados = List<Map<String, dynamic>>.from(resultados[1] as List);
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos cargar tus entregas. Revisa tu conexión.')),
      );
    }
  }

  Future<void> _iniciarRuta(Map<String, dynamic> pedido) async {
    try {
      await _sb.from('pedidos').update({'estado': 'EN_CAMINO'}).eq('id', pedido['id']);
      _cargar();
    } catch (_) {
      _error('No se pudo actualizar. Inténtalo de nuevo.');
    }
  }

  Future<void> _registrarEntrega(Map<String, dynamic> pedido) async {
    final datos = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EntregaSheet(pedido: pedido),
    );
    if (datos == null) return;

    final uid = ref.read(authProvider).usuarioId;
    final empresaId = ref.read(authProvider).empresaId;
    final entrega = {
      'empresa_id': empresaId,
      'pedido_id': pedido['id'],
      'estado_bal_on_vacio': datos['balonVacio'],
      'estado_pago': datos['pagado'] ? 'PAGADO' : 'PENDIENTE',
      'registrado_por': uid,
      'uuid_offline': datos['uuidOffline'],
    };

    Map<String, dynamic>? pago;
    if (datos['pagado'] == true) {
      pago = {
        'empresa_id': empresaId,
        'pedido_id': pedido['id'],
        'cliente_id': pedido['cliente_id'],
        'monto': datos['monto'],
        'metodo': datos['metodo'],
        'registrado_por': uid,
        'uuid_offline': datos['uuidOfflinePago'],
      };
    }

    Map<String, dynamic>? movimientoBalon;
    final balones = datos['balones'] as int? ?? 0;
    if (balones > 0) {
      // Entrega de balones llenos; si devolvió vacío, también se registra.
      movimientoBalon = {
        'empresa_id': empresaId,
        'cliente_id': pedido['cliente_id'],
        'tipo': 'ENTREGA_LLENO',
        'pedido_id': pedido['id'],
        'cantidad': balones,
        'usuario_id': uid,
        'uuid_offline': datos['uuidOfflineBalon'],
      };
    }

    try {
      await _sb.from('entregas').insert(entrega);
      if (pago != null) await _sb.from('pagos').insert(pago);
      if (movimientoBalon != null) await _sb.from('movimiento_bal_on').insert(movimientoBalon);
      await _sb.from('pedidos').update({'estado': 'ENTREGADO'}).eq('id', pedido['id']);
      _cargar();
    } catch (_) {
      // Sin internet: encolar entrega completa (el sync marca el pedido ENTREGADO).
      await Outbox.encolarEntrega(entrega: entrega, pago: pago, movimientoBalon: movimientoBalon);
      _cargar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sin conexión: entrega guardada y se enviará automáticamente.')),
        );
      }
    }
  }

  void _error(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final hora = DateTime.now().hour;
    final saludo = hora < 12 ? 'Buenos días' : (hora < 19 ? 'Buenas tardes' : 'Buenas noches');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis entregas'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: () => ref.read(authProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('$saludo, ${auth.nombre ?? ''} 👋',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  if (_pendientes.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 48, color: AppTheme.primary),
                            SizedBox(height: 12),
                            Text(
                              'No tienes pedidos por entregar.\nCuando te asignen uno, aparecerá aquí.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    Text('Por entregar (${_pendientes.length})',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    for (final p in _pendientes) _TarjetaPedido(p, _iniciarRuta, _registrarEntrega),
                  ],
                  if (_entregados.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text('Entregados hoy', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    for (final p in _entregados)
                      Card(
                        child: ListTile(
                          dense: true,
                          leading: const Icon(Icons.check_circle, color: AppTheme.success),
                          title: Text('#${p['numero']} — ${(p['clientes'] as Map?)?['nombre'] ?? ''}'),
                          trailing: Text('S/ ${(p['total'] as num? ?? 0).toStringAsFixed(2)}'),
                        ),
                      ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

class _TarjetaPedido extends StatelessWidget {
  final Map<String, dynamic> pedido;
  final void Function(Map<String, dynamic>) onIniciar;
  final void Function(Map<String, dynamic>) onEntregar;

  const _TarjetaPedido(this.pedido, this.onIniciar, this.onEntregar);

  @override
  Widget build(BuildContext context) {
    final cliente = pedido['clientes'] as Map<String, dynamic>?;
    final enCamino = pedido['estado'] == 'EN_CAMINO';
    final tieneUbicacion = cliente?['latitud'] != null && cliente?['longitud'] != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('#${pedido['numero']} — ${cliente?['nombre'] ?? 'Cliente'}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                Text('S/ ${(pedido['total'] as num? ?? 0).toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
              ],
            ),
            const SizedBox(height: 6),
            if ((cliente?['direccion'] as String? ?? '').isNotEmpty)
              Text(cliente!['direccion'] as String,
                  style: const TextStyle(color: Colors.black54, fontSize: 13)),
            if ((cliente?['telefono'] as String? ?? '').isNotEmpty)
              Text(cliente!['telefono'] as String,
                  style: const TextStyle(color: Colors.black54, fontSize: 13)),
            if (!tieneUbicacion)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Sin ubicación exacta',
                    style: TextStyle(color: AppTheme.warning, fontSize: 12)),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (!enCamino)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => onIniciar(pedido),
                      icon: const Icon(Icons.route_outlined),
                      label: const Text('Iniciar ruta'),
                    ),
                  )
                else
                  const Expanded(child: _ChipEnCamino()),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () => onEntregar(pedido),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Entregar'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipEnCamino extends StatelessWidget {
  const _ChipEnCamino();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text('En camino',
          style: TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w600)),
    );
  }
}

/// Formulario de entrega: estado del balón vacío, pago y método.
class _EntregaSheet extends StatefulWidget {
  final Map<String, dynamic> pedido;
  const _EntregaSheet({required this.pedido});

  @override
  State<_EntregaSheet> createState() => _EntregaSheetState();
}

class _EntregaSheetState extends State<_EntregaSheet> {
  String _balonVacio = 'NO_APLICA';
  bool _pagado = true;
  String _metodo = 'EFECTIVO';
  late final TextEditingController _montoCtrl;
  bool _guardando = false;

  static const _metodos = {
    'EFECTIVO': 'Efectivo',
    'YAPE': 'Yape',
    'PLIN': 'Plin',
    'TRANSFERENCIA': 'Transferencia',
    'OTRO': 'Otro',
  };

  @override
  void initState() {
    super.initState();
    _montoCtrl = TextEditingController(
      text: (widget.pedido['total'] as num? ?? 0).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _montoCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    final monto = double.tryParse(_montoCtrl.text) ?? 0;
    if (_pagado && monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El monto debe ser mayor a cero.')),
      );
      return;
    }
    setState(() => _guardando = true);
    // Se calculan los balones desde el detalle (cada línea = balones).
    int balones = 0;
    try {
      final det = await Supabase.instance.client
          .from('detalle_pedido')
          .select('cantidad, productos(capacidad_kg)')
          .eq('pedido_id', widget.pedido['id']);
      for (final d in det) {
        final prod = d['productos'] as Map<String, dynamic>?;
        if (prod?['capacidad_kg'] != null) {
          balones += (d['cantidad'] as num).toInt();
        }
      }
    } catch (_) {/* si falla el cálculo, se entrega sin movimiento de balón */}

    if (!mounted) return;
    Navigator.of(context).pop({
      'balonVacio': _balonVacio,
      'pagado': _pagado,
      'monto': monto,
      'metodo': _metodo,
      'balones': balones,
      'uuidOffline': null, // el outbox genera los suyos
      'uuidOfflinePago': null,
      'uuidOfflineBalon': null,
    });
  }

  @override
  Widget build(BuildContext context) {
    final cliente = widget.pedido['clientes'] as Map<String, dynamic>?;
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Entregar a ${cliente?['nombre'] ?? 'cliente'}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            const Text('¿Recibiste el balón vacío?',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'RECIBIDO', label: Text('Sí')),
                ButtonSegment(value: 'NO_RECIBIDO', label: Text('No')),
                ButtonSegment(value: 'NO_APLICA', label: Text('N/A')),
              ],
              selected: {_balonVacio},
              onSelectionChanged: (s) => setState(() => _balonVacio = s.first),
            ),
            const SizedBox(height: 16),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Cliente pagó'),
              value: _pagado,
              onChanged: (v) => setState(() => _pagado = v),
            ),
            if (_pagado) ...[
              TextField(
                controller: _montoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Monto recibido (S/)'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _metodo,
                decoration: const InputDecoration(labelText: 'Método de pago'),
                items: [
                  for (final e in _metodos.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _metodo = v ?? 'EFECTIVO'),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _guardando ? null : _confirmar,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: AppTheme.success,
              ),
              child: _guardando
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Confirmar entrega'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
