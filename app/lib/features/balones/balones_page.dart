import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import '../auth/auth_controller.dart';

/// Control de balones: cuántos tiene cada cliente y registro de devoluciones.
class BalonesPage extends ConsumerStatefulWidget {
  const BalonesPage({super.key});

  @override
  ConsumerState<BalonesPage> createState() => _BalonesPageState();
}

class _BalonesPageState extends ConsumerState<BalonesPage> {
  List<Map<String, dynamic>> _saldos = [];
  List<Map<String, dynamic>> _movimientos = [];
  bool _cargando = true;

  SupabaseClient get _sb => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final resultados = await Future.wait([
        _sb.from('movimiento_bal_on')
            .select('cliente_id, tipo, cantidad, fecha')
            .order('fecha', ascending: false),
        _sb.from('clientes').select('id, nombre, telefono').eq('activo', true),
      ]);
      if (!mounted) return;

      final nombres = {
        for (final c in resultados[1] as List)
          (c as Map)['id'] as String: c,
      };

      // Saldo por cliente: llenos entregados − vacíos devueltos.
      final saldo = <String, int>{};
      for (final m in resultados[0] as List) {
        final row = m as Map<String, dynamic>;
        final cid = row['cliente_id'] as String;
        final cant = (row['cantidad'] as num).toInt();
        saldo[cid] = (saldo[cid] ?? 0) + (row['tipo'] == 'ENTREGA_LLENO' ? cant : -cant);
      }

      final saldos = saldo.entries
          .where((e) => e.value > 0)
          .map((e) => {
                'cliente': nombres[e.key],
                'saldo': e.value,
              })
          .where((e) => e['cliente'] != null)
          .toList()
        ..sort((a, b) => (b['saldo'] as int).compareTo(a['saldo'] as int));

      setState(() {
        _saldos = saldos;
        _movimientos = List<Map<String, dynamic>>.from(
            (resultados[0] as List).take(15).toList());
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
      _error('No pudimos cargar los balones. Revisa tu conexión.');
    }
  }

  Future<void> _registrarDevolucion() async {
    if (_saldos.isEmpty) {
      _error('Ningún cliente tiene balones pendientes.');
      return;
    }
    final elegido = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DevolucionSheet(saldos: _saldos),
    );
    if (elegido == null) return;

    try {
      await _sb.from('movimiento_bal_on').insert({
        'empresa_id': ref.read(authProvider).empresaId,
        'cliente_id': elegido['cliente_id'],
        'tipo': 'DEVOLUCION_VACIO',
        'cantidad': elegido['cantidad'],
        'usuario_id': ref.read(authProvider).usuarioId,
      });
      _cargar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Devolución registrada: ${elegido['cantidad']} balón(es).')),
        );
      }
    } catch (_) {
      _error('No se pudo registrar. Inténtalo de nuevo.');
    }
  }

  void _error(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final totalPrestados = _saldos.fold<int>(0, (s, e) => s + (e['saldo'] as int));
    return Scaffold(
      appBar: AppBar(title: const Text('Balones')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _registrarDevolucion,
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.assignment_return_outlined),
        label: const Text('Devolución'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.local_fire_department_outlined,
                              size: 36, color: AppTheme.warning),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Balones en la calle',
                                    style: TextStyle(color: Colors.black54)),
                                Text('$totalPrestados',
                                    style: const TextStyle(
                                        fontSize: 26, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Clientes con balones (${_saldos.length})',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_saldos.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('Nadie tiene balones pendientes.',
                            style: TextStyle(color: Colors.black54)),
                      ),
                    )
                  else
                    for (final s in _saldos)
                      Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.warning.withValues(alpha: 0.15),
                            child: const Icon(Icons.local_fire_department_outlined,
                                color: AppTheme.warning),
                          ),
                          title: Text(
                            (s['cliente'] as Map?)?['nombre'] as String? ?? 'Cliente',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            (s['cliente'] as Map?)?['telefono'] as String? ?? '',
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.warning.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text('${s['saldo']}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, color: AppTheme.warning)),
                          ),
                        ),
                      ),
                  const SizedBox(height: 20),
                  Text('Movimientos recientes', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final m in _movimientos)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        m['tipo'] == 'ENTREGA_LLENO'
                            ? Icons.south_west
                            : Icons.north_east,
                        color: m['tipo'] == 'ENTREGA_LLENO' ? AppTheme.primary : AppTheme.success,
                        size: 20,
                      ),
                      title: Text(m['tipo'] == 'ENTREGA_LLENO'
                          ? 'Entrega de ${m['cantidad']} lleno(s)'
                          : 'Devolución de ${m['cantidad']} vacío(s)'),
                      subtitle: Text(_fecha(m['fecha'] as String?)),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  String _fecha(String? iso) {
    final f = DateTime.tryParse(iso ?? '');
    if (f == null) return '';
    return '${f.day}/${f.month}/${f.year} ${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}';
  }
}

class _DevolucionSheet extends StatefulWidget {
  final List<Map<String, dynamic>> saldos;
  const _DevolucionSheet({required this.saldos});

  @override
  State<_DevolucionSheet> createState() => _DevolucionSheetState();
}

class _DevolucionSheetState extends State<_DevolucionSheet> {
  String? _clienteId;
  final _cantidadCtrl = TextEditingController(text: '1');

  @override
  void dispose() {
    _cantidadCtrl.dispose();
    super.dispose();
  }

  int get _maxSaldo {
    for (final s in widget.saldos) {
      if (s['cliente']?['id'] == _clienteId) return s['saldo'] as int;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Registrar devolución de balón vacío',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _clienteId,
            decoration: const InputDecoration(labelText: 'Cliente'),
            items: [
              for (final s in widget.saldos)
                DropdownMenuItem(
                  value: (s['cliente'] as Map)['id'] as String,
                  child: Text(
                    '${(s['cliente'] as Map)['nombre']} — debe ${s['saldo']}',
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _clienteId = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cantidadCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Cantidad (máx. $_maxSaldo)',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _clienteId == null
                ? null
                : () {
                    final cant = int.tryParse(_cantidadCtrl.text) ?? 0;
                    if (cant <= 0 || cant > _maxSaldo) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Cantidad inválida (1 a $_maxSaldo).')),
                      );
                      return;
                    }
                    Navigator.of(context).pop({
                      'cliente_id': _clienteId,
                      'cantidad': cant,
                    });
                  },
            child: const Text('Registrar'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
