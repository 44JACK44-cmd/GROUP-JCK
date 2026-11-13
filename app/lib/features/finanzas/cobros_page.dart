import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import '../auth/auth_controller.dart';

/// Registro de cobros/pagos de clientes + historial reciente.
class CobrosPage extends ConsumerStatefulWidget {
  const CobrosPage({super.key});

  @override
  ConsumerState<CobrosPage> createState() => _CobrosPageState();
}

class _CobrosPageState extends ConsumerState<CobrosPage> {
  List<Map<String, dynamic>> _pagos = [];
  bool _cargando = true;

  SupabaseClient get _sb => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final data = await _sb
          .from('pagos')
          .select('id, monto, metodo, fecha, clientes(nombre, telefono)')
          .order('fecha', ascending: false)
          .limit(100);
      if (!mounted) return;
      setState(() {
        _pagos = List<Map<String, dynamic>>.from(data);
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
      _error('No pudimos cargar los cobros. Revisa tu conexión.');
    }
  }

  Future<void> _registrar() async {
    final datos = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CobroSheet(),
    );
    if (datos == null) return;

    try {
      await _sb.from('pagos').insert({
        'empresa_id': ref.read(authProvider).empresaId,
        'cliente_id': datos['clienteId'],
        'pedido_id': datos['pedidoId'],
        'monto': datos['monto'],
        'metodo': datos['metodo'],
        'registrado_por': ref.read(authProvider).usuarioId,
      });
      _cargar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cobro registrado.')),
        );
      }
    } catch (_) {
      _error('No se pudo registrar el cobro.');
    }
  }

  void _error(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  double get _totalHoy {
    final hoy = DateTime.now();
    return _pagos
        .where((p) {
          final f = DateTime.tryParse(p['fecha'] as String? ?? '');
          return f != null &&
              f.day == hoy.day && f.month == hoy.month && f.year == hoy.year;
        })
        .fold(0.0, (s, p) => s + (p['monto'] as num).toDouble());
  }

  String _labelMetodo(String m) => switch (m) {
        'EFECTIVO' => 'Efectivo',
        'YAPE' => 'Yape',
        'PLIN' => 'Plin',
        'TRANSFERENCIA' => 'Transf.',
        'OTRO' => 'Otro',
        _ => m,
      };

  String _fecha(String? iso) {
    final f = DateTime.tryParse(iso ?? '');
    if (f == null) return '';
    return '${f.day}/${f.month} ${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cobros')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _registrar,
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.payments_outlined),
        label: const Text('Cobrar'),
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
                          const Icon(Icons.today_outlined, size: 36, color: AppTheme.success),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Cobrado hoy',
                                    style: TextStyle(color: Colors.black54)),
                                Text('S/ ${_totalHoy.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        fontSize: 24, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Historial', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_pagos.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('Sin cobros registrados.',
                            style: TextStyle(color: Colors.black54)),
                      ),
                    )
                  else
                    for (final p in _pagos)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.payments_outlined,
                              color: AppTheme.success),
                          title: Text(
                            (p['clientes'] as Map?)?['nombre'] as String? ?? 'Cliente',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${_fecha(p['fecha'] as String?)}  ·  ${_labelMetodo(p['metodo'] as String? ?? '')}',
                          ),
                          trailing: Text('S/ ${(p['monto'] as num).toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, color: AppTheme.success)),
                        ),
                      ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

class _CobroSheet extends StatefulWidget {
  const _CobroSheet();

  @override
  State<_CobroSheet> createState() => _CobroSheetState();
}

class _CobroSheetState extends State<_CobroSheet> {
  final _busquedaCtrl = TextEditingController();
  final _montoCtrl = TextEditingController();
  List<Map<String, dynamic>> _sugerencias = [];
  Map<String, dynamic>? _cliente;
  String _metodo = 'EFECTIVO';
  bool _buscando = false;

  SupabaseClient get _sb => Supabase.instance.client;

  static const _metodos = {
    'EFECTIVO': 'Efectivo',
    'YAPE': 'Yape',
    'PLIN': 'Plin',
    'TRANSFERENCIA': 'Transferencia',
    'OTRO': 'Otro',
  };

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    _montoCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscar(String texto) async {
    final q = texto.trim();
    if (q.length < 2) {
      setState(() => _sugerencias = []);
      return;
    }
    setState(() => _buscando = true);
    try {
      final data = await _sb
          .from('clientes')
          .select('id, nombre, telefono')
          .eq('activo', true)
          .or('nombre.ilike.%$q%,telefono.ilike.%$q%')
          .order('nombre')
          .limit(8);
      if (!mounted) return;
      setState(() {
        _sugerencias = List<Map<String, dynamic>>.from(data);
        _buscando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _buscando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
            const Text('Registrar cobro',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (_cliente == null) ...[
              TextField(
                controller: _busquedaCtrl,
                onChanged: _buscar,
                decoration: InputDecoration(
                  hintText: 'Buscar cliente',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _buscando
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : null,
                ),
              ),
              for (final s in _sugerencias)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(s['nombre'] as String? ?? ''),
                  subtitle: Text(s['telefono'] as String? ?? ''),
                  onTap: () => setState(() {
                    _cliente = s;
                    _sugerencias = [];
                    _busquedaCtrl.clear();
                  }),
                ),
            ] else
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                  child: Text(
                    (_cliente!['nombre'] as String? ?? '?')[0].toUpperCase(),
                    style: const TextStyle(color: AppTheme.primary),
                  ),
                ),
                title: Text(_cliente!['nombre'] as String? ?? ''),
                trailing: TextButton(
                  onPressed: () => setState(() => _cliente = null),
                  child: const Text('Cambiar'),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _montoCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Monto (S/) *'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _metodo,
              decoration: const InputDecoration(labelText: 'Método'),
              items: [
                for (final e in _metodos.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _metodo = v ?? 'EFECTIVO'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _cliente == null
                  ? null
                  : () {
                      final monto = double.tryParse(_montoCtrl.text) ?? 0;
                      if (monto <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('El monto debe ser mayor a cero.')),
                        );
                        return;
                      }
                      Navigator.of(context).pop({
                        'clienteId': _cliente!['id'],
                        'monto': monto,
                        'metodo': _metodo,
                        'pedidoId': null,
                      });
                    },
              child: const Text('Guardar cobro'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
